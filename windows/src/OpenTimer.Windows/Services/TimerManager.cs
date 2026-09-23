using System.ComponentModel;
using System.Globalization;
using System.Runtime.CompilerServices;
using System.Windows.Threading;
using OpenTimer.Models;

namespace OpenTimer.Services;

/// <summary>
/// Pilote le chrono : démarrage/arrêt, temps écoulé (tick 1 s), et écriture du
/// time entry dans OpenProject à l'arrêt.
///
/// Port de <c>macos/Sources/OpenTimer/Services/TimerManager.swift</c>. Le modèle
/// « segments cumulés » (<see cref="_accumulated"/> + <see cref="_segmentStart"/>) est
/// repris tel quel : il survit à une mise en veille, contrairement à un compteur incrémenté
/// à chaque tick.
///
/// Tous les membres s'utilisent depuis le thread UI (équivalent du <c>@MainActor</c> Swift).
/// </summary>
public sealed class TimerManager : INotifyPropertyChanged
{
    private bool _isRunning;
    private bool _isPaused;
    private TimeSpan _elapsed;
    private WorkPackage? _activeWp;
    private string? _lastError;
    private string? _lastSaved;
    private PendingCompletion? _pendingCompletion;

    public bool IsRunning { get => _isRunning; private set => Set(ref _isRunning, value); }
    public bool IsPaused { get => _isPaused; private set => Set(ref _isPaused, value); }
    public TimeSpan Elapsed { get => _elapsed; private set { if (Set(ref _elapsed, value)) Notify(nameof(FormattedElapsed)); } }
    public WorkPackage? ActiveWp { get => _activeWp; private set => Set(ref _activeWp, value); }
    public string? LastError { get => _lastError; set => Set(ref _lastError, value); }
    public string? LastSaved { get => _lastSaved; set => Set(ref _lastSaved, value); }

    /// <summary>
    /// Proposition de clôture affichée après un arrêt réussi : passer le WP en « Traité »
    /// et le réaffecter à son créateur. <c>null</c> = aucune proposition en attente.
    /// </summary>
    public PendingCompletion? PendingCompletionValue
    {
        get => _pendingCompletion;
        set => Set(ref _pendingCompletion, value);
    }

    /// <summary>Données figées d'une proposition de clôture (le WP a déjà été désélectionné côté UI).</summary>
    public sealed record PendingCompletion(
        WorkPackage Wp,
        int LockVersion,
        string? StatusHref,
        string StatusName,
        string? AssigneeHref,
        string? AssigneeName);

    /// <summary>Instant de début du segment en cours (<c>null</c> si en pause).</summary>
    private DateTime? _segmentStart;

    /// <summary>Temps cumulé des segments déjà terminés (figé pendant les pauses).</summary>
    private TimeSpan _accumulated;

    private DispatcherTimer? _ticker;
    private string? _activeActivityHref;

    public void Start(WorkPackage wp, string? activityHref = null)
    {
        if (IsRunning) return;
        LastError = null;
        LastSaved = null;
        PendingCompletionValue = null;
        ActiveWp = wp;
        _activeActivityHref = activityHref;
        _accumulated = TimeSpan.Zero;
        _segmentStart = DateTime.UtcNow;
        Elapsed = TimeSpan.Zero;
        IsPaused = false;
        IsRunning = true;
        StartTicker();
    }

    /// <summary>Met le chrono en pause : le temps du segment courant est cumulé et figé.</summary>
    public void Pause()
    {
        if (!IsRunning || IsPaused) return;
        _accumulated = CurrentElapsed();
        _segmentStart = null;
        IsPaused = true;
        StopTicker();
        Elapsed = _accumulated;
    }

    /// <summary>Reprend le chrono après une pause.</summary>
    public void Resume()
    {
        if (!IsRunning || !IsPaused) return;
        _segmentStart = DateTime.UtcNow;
        IsPaused = false;
        StartTicker();
    }

    private void StartTicker()
    {
        _ticker = new DispatcherTimer(DispatcherPriority.Normal)
        {
            Interval = TimeSpan.FromSeconds(1),
        };
        _ticker.Tick += (_, _) => Elapsed = CurrentElapsed();
        _ticker.Start();
    }

    private void StopTicker()
    {
        _ticker?.Stop();
        _ticker = null;
    }

    /// <summary>Temps écoulé réel à cet instant (cumulé + segment courant s'il tourne).</summary>
    private TimeSpan CurrentElapsed() =>
        _segmentStart is { } start ? _accumulated + (DateTime.UtcNow - start) : _accumulated;

    public async Task StopAsync(OpenProjectApi? api, string comment)
    {
        if (!IsRunning || ActiveWp is not { } wp) return;

        // En pause, on prend le temps figé au moment de la pause ; sinon le temps courant.
        var seconds = (int)CurrentElapsed().TotalSeconds;
        StopTicker();
        IsRunning = false;
        IsPaused = false;
        PendingCompletionValue = null;

        if (api is null)
        {
            LastError = "Configure d'abord ton token dans Préférences.";
            Reset();
            return;
        }

        var hours = OpenProjectApi.IsoDuration(seconds);
        // Heure de début envoyée si l'instance l'accepte : bloc continu qui se termine à
        // l'arrêt et dure exactement `hours` (OpenProject calcule la fin = début + durée ;
        // les pauses ne sont donc pas représentées). `spentOn` doit être le jour du début.
        var stoppedAt = DateTime.UtcNow;
        var startedAt = stoppedAt.AddMinutes(-OpenProjectApi.RoundedMinutes(seconds));
        var sendStart = await api.StartEndSupportedAsync(wp.Href);
        var spentOn = (sendStart ? startedAt : stoppedAt).ToLocalTime()
            .ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        try
        {
            // Activité choisie au démarrage ; sinon la première autorisée (requise par OP).
            var activityHref = _activeActivityHref;
            if (activityHref is null)
            {
                try
                {
                    activityHref = (await api.ActivitiesAsync(wp.Href)).FirstOrDefault()?.Href;
                }
                catch (Exception ex) when (ex is OpenProjectException or HttpRequestException)
                {
                    // L'API refusera peut-être la saisie sans activité ; on laisse remonter là.
                }
            }

            await api.CreateTimeEntryAsync(wp.Href, hours, spentOn, comment, activityHref,
                sendStart ? OpenProjectApi.UtcString(startedAt) : null);
            LastSaved = $"Enregistré : {hours} sur #{wp.Id}";
            LastError = null;

            // Une fois le temps enregistré, on propose de clôturer le WP.
            await PreparePendingCompletionAsync(api, wp);
        }
        catch (Exception ex) when (ex is OpenProjectException or HttpRequestException or TaskCanceledException)
        {
            LastError = ex.Message;
        }
        Reset();
    }

    /// <summary>
    /// Prépare (sans l'appliquer) la proposition de clôture : cherche le statut « Traité »
    /// et le créateur du WP. Ne propose rien si aucune des deux actions n'est possible ;
    /// toute erreur réseau est ignorée silencieusement (la proposition est facultative).
    /// </summary>
    private async Task PreparePendingCompletionAsync(OpenProjectApi api, WorkPackage wp)
    {
        string? statusHref = null;
        try { statusHref = await api.StatusHrefAsync(OpenProjectApi.DoneStatusName); }
        catch { /* proposition facultative : on continue sans le statut */ }

        OpenProjectApi.WorkPackageCompletion? detail = null;
        try { detail = await api.WorkPackageCompletionAsync(wp.Href); }
        catch { /* idem : on continue sans le créateur */ }

        if (statusHref is null && detail?.AuthorHref is null) return;

        PendingCompletionValue = new PendingCompletion(
            Wp: wp,
            LockVersion: detail?.LockVersion ?? 0,
            StatusHref: statusHref,
            StatusName: OpenProjectApi.DoneStatusName,
            AssigneeHref: detail?.AuthorHref,
            AssigneeName: detail?.AuthorName);
    }

    /// <summary>Applique la proposition de clôture : PATCH statut + assigné, puis l'efface.</summary>
    public async Task ApplyPendingCompletionAsync(OpenProjectApi? api)
    {
        if (PendingCompletionValue is not { } pending) return;
        if (api is null)
        {
            LastError = "Configure d'abord ton token dans Préférences.";
            PendingCompletionValue = null;
            return;
        }

        try
        {
            await api.UpdateWorkPackageAsync(
                pending.Wp.Href, pending.LockVersion, pending.StatusHref, pending.AssigneeHref);

            var parts = new List<string>();
            if (pending.StatusHref is not null) parts.Add($"statut « {pending.StatusName} »");
            if (pending.AssigneeName is { } name) parts.Add($"réaffecté à {name}");
            else if (pending.AssigneeHref is not null) parts.Add("réaffecté au créateur");

            LastSaved = $"#{pending.Wp.Id} — {string.Join(", ", parts)}";
            LastError = null;
        }
        catch (Exception ex) when (ex is OpenProjectException or HttpRequestException)
        {
            LastError = ex.Message;
        }
        PendingCompletionValue = null;
    }

    /// <summary>Écarte la proposition de clôture sans rien modifier.</summary>
    public void DismissPendingCompletion() => PendingCompletionValue = null;

    private void Reset()
    {
        Elapsed = TimeSpan.Zero;
        _accumulated = TimeSpan.Zero;
        _segmentStart = null;
        IsPaused = false;
        ActiveWp = null;
        _activeActivityHref = null;
    }

    public string FormattedElapsed => Format(Elapsed);

    /// <summary>Durée en H:MM:SS.</summary>
    public static string Format(TimeSpan t)
    {
        var s = (int)Math.Max(0, t.TotalSeconds);
        return string.Format(CultureInfo.InvariantCulture, "{0}:{1:00}:{2:00}",
            s / 3600, s % 3600 / 60, s % 60);
    }

    /// <summary>
    /// Durée en heures:minutes (sans secondes), arrondie à la minute la plus proche.
    /// Pour l'historique et l'éditeur, où les secondes ne sont pas pertinentes.
    /// </summary>
    public static string FormatHm(TimeSpan t)
    {
        var totalMinutes = (int)Math.Round(Math.Max(0, t.TotalSeconds) / 60.0, MidpointRounding.AwayFromZero);
        return string.Format(CultureInfo.InvariantCulture, "{0}:{1:00}",
            totalMinutes / 60, totalMinutes % 60);
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    private void Notify(string name) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    private bool Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return false;
        field = value;
        Notify(name!);
        return true;
    }
}
