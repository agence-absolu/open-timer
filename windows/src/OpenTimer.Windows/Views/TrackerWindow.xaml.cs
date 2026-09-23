using System.ComponentModel;
using System.Net.Http;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using OpenTimer.Models;
using OpenTimer.Services;

namespace OpenTimer.Views;

/// <summary>
/// Fenêtre « Nouveau ». Trois états, comme <c>TrackerView.swift</c> : connexion manquante,
/// session en cours, ou recherche + démarrage.
/// </summary>
public partial class TrackerWindow : Window
{
    private readonly SettingsStore _settings = App.Settings;
    private readonly TimerManager _timer = App.Timer;

    /// <summary>Mes WP, chargés une fois : le filtre hors « tous les WP » est purement local.</summary>
    private List<WorkPackage> _myWorkPackages = [];

    /// <summary>Debounce de la recherche serveur (350 ms, même valeur que sur macOS).</summary>
    private readonly DispatcherTimer _searchDebounce = new() { Interval = TimeSpan.FromMilliseconds(350) };

    /// <summary>Annule la recherche serveur précédente quand la saisie repart.</summary>
    private CancellationTokenSource? _searchCts;

    public TrackerWindow()
    {
        InitializeComponent();

        _searchDebounce.Tick += async (_, _) =>
        {
            _searchDebounce.Stop();
            await RunSearchAsync();
        };

        _timer.PropertyChanged += OnTimerChanged;
        Closed += (_, _) => _timer.PropertyChanged -= OnTimerChanged;

        Loaded += async (_, _) => await RefreshAsync();
    }

    private void OnTimerChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(TimerManager.FormattedElapsed))
        {
            ElapsedText.Text = _timer.FormattedElapsed;
            return;
        }
        if (e.PropertyName is nameof(TimerManager.IsRunning) or nameof(TimerManager.IsPaused)
            or nameof(TimerManager.LastError) or nameof(TimerManager.LastSaved))
        {
            UpdateVisibleState();
        }
    }

    // MARK: - États

    private async Task RefreshAsync()
    {
        UpdateVisibleState();
        if (_settings.Api is { } api && !_timer.IsRunning) await LoadMyWorkPackagesAsync(api);
    }

    private void UpdateVisibleState()
    {
        var configured = _settings.Api is not null;

        NotConfiguredPanel.Visibility = configured ? Visibility.Collapsed : Visibility.Visible;
        RunningPanel.Visibility = configured && _timer.IsRunning ? Visibility.Visible : Visibility.Collapsed;
        PickerPanel.Visibility = configured && !_timer.IsRunning ? Visibility.Visible : Visibility.Collapsed;

        if (_timer.IsRunning)
        {
            RunningWpText.Text = _timer.ActiveWp?.Display ?? "";
            ElapsedText.Text = _timer.FormattedElapsed;
            PauseButton.Content = _timer.IsPaused ? "Reprendre" : "Pause";
            PausedHint.Visibility = _timer.IsPaused ? Visibility.Visible : Visibility.Collapsed;
        }

        StatusText.Text = _timer.LastError ?? _timer.LastSaved ?? "";
    }

    // MARK: - Chargement et recherche

    private async Task LoadMyWorkPackagesAsync(OpenProjectApi api)
    {
        try
        {
            _myWorkPackages = await api.MyWorkPackagesAsync();
            ApplyLocalFilter();
        }
        catch (Exception ex) when (ex is OpenProjectException or HttpRequestException or TaskCanceledException)
        {
            StatusText.Text = ex.Message;
        }
    }

    private void OnSearchTextChanged(object sender, TextChangedEventArgs e)
    {
        if (AllWorkPackagesBox.IsChecked == true)
        {
            _searchDebounce.Stop();
            _searchDebounce.Start();
        }
        else
        {
            ApplyLocalFilter();
        }
    }

    private async void OnScopeToggled(object sender, RoutedEventArgs e)
    {
        if (AllWorkPackagesBox.IsChecked == true) await RunSearchAsync();
        else ApplyLocalFilter();
    }

    /// <summary>Filtre local sur mes WP : sous-chaîne sur le libellé ou l'identifiant.</summary>
    private void ApplyLocalFilter()
    {
        var q = SearchBox.Text.Trim();
        var items = q.Length == 0
            ? _myWorkPackages
            : _myWorkPackages.Where(wp =>
                wp.Subject.Contains(q, StringComparison.CurrentCultureIgnoreCase)
                || wp.Id.ToString().Contains(q, StringComparison.Ordinal)).ToList();

        WorkPackageList.ItemsSource = items;
    }

    /// <summary>Recherche serveur sur tous les WP ouverts (case « Tous les work packages »).</summary>
    private async Task RunSearchAsync()
    {
        if (_settings.Api is not { } api) return;

        _searchCts?.Cancel();
        var cts = new CancellationTokenSource();
        _searchCts = cts;

        var query = SearchBox.Text.Trim();
        if (query.Length == 0)
        {
            WorkPackageList.ItemsSource = _myWorkPackages;
            return;
        }

        try
        {
            var results = await api.SearchWorkPackagesAsync(query, ct: cts.Token);
            if (!cts.IsCancellationRequested) WorkPackageList.ItemsSource = results;
        }
        catch (OperationCanceledException)
        {
            // Frappe suivante : résultat obsolète, rien à afficher.
        }
        catch (Exception ex) when (ex is OpenProjectException or HttpRequestException)
        {
            StatusText.Text = ex.Message;
        }
    }

    // MARK: - Sélection et démarrage

    private async void OnWorkPackageSelected(object sender, SelectionChangedEventArgs e)
    {
        StartButton.IsEnabled = WorkPackageList.SelectedItem is WorkPackage;
        if (WorkPackageList.SelectedItem is not WorkPackage wp) return;
        if (_settings.Api is not { } api) return;

        try
        {
            var activities = await api.ActivitiesAsync(wp.Href);
            ActivityBox.ItemsSource = activities;
            // Présélection de « Développement » si l'instance la propose, comme sur macOS.
            ActivityBox.SelectedItem =
                activities.FirstOrDefault(a => a.Name.Equals("Développement", StringComparison.OrdinalIgnoreCase))
                ?? activities.FirstOrDefault();
        }
        catch (Exception ex) when (ex is OpenProjectException or HttpRequestException)
        {
            ActivityBox.ItemsSource = null;
            StatusText.Text = ex.Message;
        }
    }

    private void OnStart(object sender, RoutedEventArgs e)
    {
        if (WorkPackageList.SelectedItem is not WorkPackage wp) return;
        RunningCommentBox.Text = CommentBox.Text;
        _timer.Start(wp, (ActivityBox.SelectedItem as Activity)?.Href);
        UpdateVisibleState();
    }

    private void OnPauseResume(object sender, RoutedEventArgs e)
    {
        if (_timer.IsPaused) _timer.Resume();
        else _timer.Pause();
    }

    private async void OnStop(object sender, RoutedEventArgs e)
    {
        StopButton.IsEnabled = false;
        try
        {
            await _timer.StopAsync(_settings.Api, RunningCommentBox.Text);
        }
        finally
        {
            StopButton.IsEnabled = true;
        }

        // Désélection du WP à l'arrêt (v0.6.1) et rechargement de la liste.
        WorkPackageList.SelectedItem = null;
        CommentBox.Text = "";
        RunningCommentBox.Text = "";
        if (_settings.Api is { } api) await LoadMyWorkPackagesAsync(api);

        PromptPendingCompletion();
    }

    /// <summary>
    /// Proposition de clôture après un arrêt réussi (v0.7.0) : passer le WP en « Traité »
    /// et le réaffecter à son créateur.
    /// </summary>
    private async void PromptPendingCompletion()
    {
        if (_timer.PendingCompletionValue is not { } pending) return;

        var parts = new List<string>();
        if (pending.StatusHref is not null) parts.Add($"passer en « {pending.StatusName} »");
        if (pending.AssigneeName is { } name) parts.Add($"réaffecter à {name}");
        else if (pending.AssigneeHref is not null) parts.Add("réaffecter au créateur");

        var answer = System.Windows.MessageBox.Show(
            $"Clôturer #{pending.Wp.Id} ?\n\n{string.Join("\net ", parts)}.",
            "OpenTimer", MessageBoxButton.YesNo, MessageBoxImage.Question);

        if (answer == MessageBoxResult.Yes) await _timer.ApplyPendingCompletionAsync(_settings.Api);
        else _timer.DismissPendingCompletion();

        UpdateVisibleState();
    }

    private void OnOpenPreferences(object sender, RoutedEventArgs e)
    {
        // Passe par App pour réutiliser l'unique instance : ouvrir une seconde fenêtre
        // Préférences laisserait deux vues divergentes du même SettingsStore.
        App.ShowPreferences();

        // La connexion peut devenir valide pendant que cette fenêtre reste ouverte : on
        // rafraîchit à chaque retour au premier plan plutôt qu'une seule fois ici.
        Activated -= OnActivatedAfterPreferences;
        Activated += OnActivatedAfterPreferences;
    }

    private async void OnActivatedAfterPreferences(object? sender, EventArgs e)
    {
        Activated -= OnActivatedAfterPreferences;
        await RefreshAsync();
    }
}
