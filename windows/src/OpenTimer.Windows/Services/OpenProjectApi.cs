using System.Globalization;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using OpenTimer.Models;

namespace OpenTimer.Services;

/// <summary>Erreur remontée par l'API OpenProject (message déjà lisible par l'utilisateur).</summary>
public sealed class OpenProjectException(string message) : Exception(message);

/// <summary>
/// Client minimal de l'API REST v3 d'OpenProject.
/// Authentification par token : Basic base64("apikey:&lt;token&gt;").
///
/// Port fidèle de <c>macos/Sources/OpenTimer/Services/OpenProjectAPI.swift</c> : toute
/// évolution d'un côté doit être répercutée de l'autre.
///
/// Les corps de requête sont bâtis en dictionnaires puis sérialisés — pendant direct du
/// <c>JSONSerialization.data(withJSONObject:)</c> côté Swift. Les réponses, elles, sont
/// parcourues à la main (HAL), sans type de décodage.
/// </summary>
public sealed class OpenProjectApi
{
    private static readonly HttpClient Http = new();

    private readonly Uri _baseUrl;
    private readonly string _authHeader;

    public OpenProjectApi(Uri baseUrl, string token)
    {
        _baseUrl = baseUrl;
        _authHeader = Convert.ToBase64String(Encoding.UTF8.GetBytes($"apikey:{token}"));
    }

    /// <summary>Nom du statut proposé à la clôture d'un WP (voir <see cref="TimerManager"/>).</summary>
    public const string DoneStatusName = "Traité";

    // MARK: - Endpoints

    /// <summary>Utilisateur courant — sert aussi de test de connexion.</summary>
    public async Task<string> CurrentUserAsync(CancellationToken ct = default)
    {
        using var doc = await SendAsync(HttpMethod.Get, "api/v3/users/me", null, ct);
        return Str(doc.RootElement, "name") ?? "Utilisateur inconnu";
    }

    /// <summary>Work packages assignés à l'utilisateur courant et dont le statut est ouvert.</summary>
    public Task<List<WorkPackage>> MyWorkPackagesAsync(CancellationToken ct = default) =>
        FetchWorkPackagesAsync(
            Filters(("assignee", "=", ["me"]), ("status", "o", [])), 100, ct);

    /// <summary>
    /// Recherche parmi tous les WP ouverts — assignés ou non. Sert à travailler sur un
    /// work package assigné à quelqu'un d'autre.
    ///
    /// Saisie purement numérique (avec « # » optionnel) → recherche par <b>id exact</b>
    /// (le filtre plein-texte <c>**</c> ne matche pas les identifiants) ; on ne restreint
    /// alors pas au statut ouvert, pour retrouver le WP même s'il est clos. Sinon,
    /// recherche plein-texte (libellé…) sur les WP ouverts.
    /// </summary>
    public Task<List<WorkPackage>> SearchWorkPackagesAsync(
        string query, int limit = 50, CancellationToken ct = default)
    {
        var trimmed = query.Trim();
        if (trimmed.Length == 0) return Task.FromResult(new List<WorkPackage>());

        var digits = trimmed.StartsWith('#') ? trimmed[1..] : trimmed;
        if (digits.Length > 0 && digits.All(char.IsDigit))
            return FetchWorkPackagesAsync(Filters(("id", "=", [digits])), limit, ct);

        return FetchWorkPackagesAsync(
            Filters(("search", "**", [trimmed]), ("status", "o", [])), limit, ct);
    }

    /// <summary>Requête <c>work_packages</c> filtrée, triée par mise à jour décroissante.</summary>
    private async Task<List<WorkPackage>> FetchWorkPackagesAsync(
        string filtersJson, int pageSize, CancellationToken ct)
    {
        var query = BuildQuery(
            ("pageSize", pageSize.ToString(CultureInfo.InvariantCulture)),
            ("filters", filtersJson),
            ("sortBy", "[[\"updatedAt\",\"desc\"]]"));

        using var doc = await SendAsync(HttpMethod.Get, "api/v3/work_packages" + query, null, ct);

        var result = new List<WorkPackage>();
        foreach (var el in Elements(doc.RootElement))
        {
            var id = Int(el, "id");
            var subject = Str(el, "subject");
            if (id is null || subject is null) continue;
            var project = Obj(Obj(el, "_links"), "project");
            result.Add(new WorkPackage(id.Value, subject, Str(project, "title")));
        }
        return result;
    }

    /// <summary>Activités de temps autorisées pour un work package, via le formulaire de création.</summary>
    public async Task<List<Activity>> ActivitiesAsync(string workPackageHref, CancellationToken ct = default)
    {
        var body = Json(new Dictionary<string, object?>
        {
            ["_links"] = new Dictionary<string, object?>
            {
                ["workPackage"] = new Dictionary<string, object?> { ["href"] = workPackageHref },
            },
        });

        using var doc = await SendAsync(HttpMethod.Post, "api/v3/time_entries/form", body, ct);

        var schema = Obj(Obj(doc.RootElement, "_embedded"), "schema");
        var embedded = Obj(Obj(schema, "activity"), "_embedded");

        var result = new List<Activity>();
        if (embedded is null || !embedded.Value.TryGetProperty("allowedValues", out var values)
            || values.ValueKind != JsonValueKind.Array)
            return result;

        foreach (var value in values.EnumerateArray())
        {
            var selfLink = Obj(Obj(value, "_links"), "self");
            var href = Str(selfLink, "href");
            if (href is null) continue;
            result.Add(new Activity(href, Str(value, "name") ?? Str(selfLink, "title") ?? "Activité"));
        }
        return result;
    }

    /// <summary>
    /// Crée un time entry. <paramref name="hours"/> est une durée ISO 8601 (ex. « PT1H23M »).
    /// <paramref name="startTimeUtc"/> n'est accepté que si l'instance autorise les heures
    /// début/fin (voir <see cref="StartEndSupportedAsync"/>) ; sa date locale doit alors être
    /// égale à <paramref name="spentOn"/>.
    /// </summary>
    public async Task CreateTimeEntryAsync(
        string workPackageHref, string hours, string spentOn, string comment,
        string? activityHref, string? startTimeUtc = null, CancellationToken ct = default)
    {
        var links = new Dictionary<string, object?>
        {
            ["workPackage"] = new Dictionary<string, object?> { ["href"] = workPackageHref },
        };
        if (activityHref is not null)
            links["activity"] = new Dictionary<string, object?> { ["href"] = activityHref };

        var payload = new Dictionary<string, object?>
        {
            ["hours"] = hours,
            ["spentOn"] = spentOn,
            ["_links"] = links,
        };
        if (comment.Length > 0)
            payload["comment"] = new Dictionary<string, object?> { ["raw"] = comment };
        if (startTimeUtc is not null) payload["startTime"] = startTimeUtc;

        (await SendAsync(HttpMethod.Post, "api/v3/time_entries", Json(payload), ct)).Dispose();
    }

    /// <summary>Dernières saisies de temps de l'utilisateur courant (plus récentes d'abord).</summary>
    public async Task<List<TimeEntry>> RecentTimeEntriesAsync(int limit = 20, CancellationToken ct = default)
    {
        var query = BuildQuery(
            ("pageSize", limit.ToString(CultureInfo.InvariantCulture)),
            ("filters", Filters(("user", "=", ["me"]))),
            ("sortBy", "[[\"spentOn\",\"desc\"],[\"createdAt\",\"desc\"]]"));

        using var doc = await SendAsync(HttpMethod.Get, "api/v3/time_entries" + query, null, ct);

        var result = new List<TimeEntry>();
        foreach (var el in Elements(doc.RootElement))
        {
            var entry = ParseTimeEntry(el);
            if (entry is not null) result.Add(entry);
        }
        return result;
    }

    /// <summary>
    /// Met à jour une saisie (durée, date, commentaire, + heure de début si supportée).
    /// Pas de <c>endTime</c> : OpenProject le calcule (<c>startTime</c> + <c>hours</c>) et
    /// refuse de l'écrire (erreur 500 <c>undefined method 'end_time='</c>).
    /// </summary>
    public async Task UpdateTimeEntryAsync(
        int id, int seconds, string spentOn, string comment, int? lockVersion,
        string? startTimeUtc = null, CancellationToken ct = default)
    {
        var payload = new Dictionary<string, object?>
        {
            ["hours"] = IsoDurationPrecise(seconds),
            ["spentOn"] = spentOn,
            ["comment"] = new Dictionary<string, object?> { ["raw"] = comment },
        };
        if (startTimeUtc is not null) payload["startTime"] = startTimeUtc;
        if (lockVersion is not null) payload["lockVersion"] = lockVersion.Value;

        (await SendAsync(HttpMethod.Patch, $"api/v3/time_entries/{id}", Json(payload), ct)).Dispose();
    }

    /// <summary>Supprime une saisie.</summary>
    public async Task DeleteTimeEntryAsync(int id, CancellationToken ct = default) =>
        (await SendAsync(HttpMethod.Delete, $"api/v3/time_entries/{id}", null, ct)).Dispose();

    // MARK: - Clôture d'un work package

    /// <summary>
    /// Détail minimal d'un WP nécessaire au PATCH de clôture : <c>lockVersion</c> (verrou
    /// optimiste requis par OpenProject) et lien vers le créateur (author).
    /// </summary>
    public sealed record WorkPackageCompletion(int LockVersion, string? AuthorHref, string? AuthorName);

    /// <summary>Lit <c>lockVersion</c> et l'auteur d'un WP depuis sa représentation HAL.</summary>
    public async Task<WorkPackageCompletion> WorkPackageCompletionAsync(string href, CancellationToken ct = default)
    {
        using var doc = await SendAsync(HttpMethod.Get, StripLeadingSlash(href), null, ct);
        var author = Obj(Obj(doc.RootElement, "_links"), "author");
        return new WorkPackageCompletion(
            Int(doc.RootElement, "lockVersion") ?? 0,
            Str(author, "href"),
            Str(author, "title"));
    }

    /// <summary>
    /// Href du statut portant ce nom (comparaison insensible à la casse et aux accents),
    /// <c>null</c> si l'instance n'a pas de statut de ce nom.
    /// </summary>
    public async Task<string?> StatusHrefAsync(string name, CancellationToken ct = default)
    {
        using var doc = await SendAsync(HttpMethod.Get, "api/v3/statuses", null, ct);
        var target = Fold(name);
        foreach (var el in Elements(doc.RootElement))
        {
            if (Fold(Str(el, "name") ?? "") != target) continue;
            return Str(Obj(Obj(el, "_links"), "self"), "href");
        }
        return null;
    }

    /// <summary>
    /// PATCH un WP : statut et/ou assigné. <paramref name="lockVersion"/> doit être la version
    /// courante (verrou optimiste). Les liens <c>null</c> sont laissés inchangés.
    /// </summary>
    public async Task UpdateWorkPackageAsync(
        string href, int lockVersion, string? statusHref, string? assigneeHref,
        CancellationToken ct = default)
    {
        var links = new Dictionary<string, object?>();
        if (statusHref is not null)
            links["status"] = new Dictionary<string, object?> { ["href"] = statusHref };
        if (assigneeHref is not null)
            links["assignee"] = new Dictionary<string, object?> { ["href"] = assigneeHref };

        var payload = new Dictionary<string, object?>
        {
            ["lockVersion"] = lockVersion,
            ["_links"] = links,
        };

        (await SendAsync(HttpMethod.Patch, StripLeadingSlash(href), Json(payload), ct)).Dispose();
    }

    /// <summary>
    /// Indique si l'instance autorise les heures de début/fin (option admin
    /// <c>allow_tracking_start_and_end_times</c>), lu depuis le schéma du formulaire.
    /// </summary>
    public async Task<bool> StartEndSupportedAsync(string? workPackageHref, CancellationToken ct = default)
    {
        try
        {
            var payload = new Dictionary<string, object?>();
            if (workPackageHref is not null)
            {
                payload["_links"] = new Dictionary<string, object?>
                {
                    ["workPackage"] = new Dictionary<string, object?> { ["href"] = workPackageHref },
                };
            }

            using var doc = await SendAsync(HttpMethod.Post, "api/v3/time_entries/form", Json(payload), ct);
            var schema = Obj(Obj(doc.RootElement, "_embedded"), "schema");
            var start = Obj(schema, "startTime");
            return start is not null
                && start.Value.TryGetProperty("writable", out var w)
                && w.ValueKind == JsonValueKind.True;
        }
        catch
        {
            return false;
        }
    }

    // MARK: - Construction des requêtes

    private static string Json(object payload) => JsonSerializer.Serialize(payload);

    /// <summary>
    /// Sérialise un tableau de filtres OpenProject :
    /// <c>[{"champ":{"operator":"…","values":[…]}}, …]</c>.
    /// </summary>
    private static string Filters(params (string Field, string Op, string[] Values)[] items) =>
        Json(items.Select(i => new Dictionary<string, object?>
        {
            [i.Field] = new Dictionary<string, object?>
            {
                ["operator"] = i.Op,
                ["values"] = i.Values,
            },
        }).ToList());

    /// <summary>
    /// Query string entièrement percent-encodée. On l'assemble à la main plutôt qu'avec un
    /// helper : le pendant Swift doit contourner un encodage de l'espace en « + » que
    /// OpenProject réinterprète, et <see cref="Uri.EscapeDataString"/> encode espace en %20 et
    /// « + » en %2B — le comportement attendu par l'API. Ne pas remplacer par du
    /// <c>HttpUtility.ParseQueryString</c>, qui réintroduit l'encodage « + ».
    /// </summary>
    private static string BuildQuery(params (string Key, string Value)[] items) =>
        "?" + string.Join("&", items.Select(i =>
            $"{Uri.EscapeDataString(i.Key)}={Uri.EscapeDataString(i.Value)}"));

    private async Task<JsonDocument> SendAsync(
        HttpMethod method, string pathAndQuery, string? body, CancellationToken ct)
    {
        using var req = new HttpRequestMessage(method, new Uri(_baseUrl, pathAndQuery));
        req.Headers.Authorization = new AuthenticationHeaderValue("Basic", _authHeader);
        req.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        if (body is not null)
            req.Content = new StringContent(body, Encoding.UTF8, "application/json");

        using var resp = await Http.SendAsync(req, ct);
        var data = await resp.Content.ReadAsByteArrayAsync(ct);

        if (!resp.IsSuccessStatusCode)
            throw new OpenProjectException(ErrorMessage(data) ?? $"HTTP {(int)resp.StatusCode}");

        // Un 204 (DELETE) n'a pas de corps : on rend un document vide plutôt que de lever.
        if (data.Length == 0) return JsonDocument.Parse("{}");

        try
        {
            return JsonDocument.Parse(data);
        }
        catch (JsonException)
        {
            throw new OpenProjectException("Réponse invalide du serveur.");
        }
    }

    private static string? ErrorMessage(byte[] data)
    {
        try
        {
            using var doc = JsonDocument.Parse(data);
            return Str(doc.RootElement, "message");
        }
        catch
        {
            return null;
        }
    }

    // MARK: - Parsing HAL

    private static TimeEntry? ParseTimeEntry(JsonElement el)
    {
        var id = Int(el, "id");
        if (id is null) return null;

        var links = Obj(el, "_links");
        var wp = Obj(links, "workPackage");
        var project = Obj(links, "project");

        return new TimeEntry(
            Id: id.Value,
            WorkPackageTitle: Str(wp, "title"),
            WorkPackageHref: Str(wp, "href"),
            ProjectTitle: Str(project, "title"),
            Comment: Str(Obj(el, "comment"), "raw") ?? "",
            SpentOn: Str(el, "spentOn") ?? "",
            Seconds: SecondsFromIsoDuration(Str(el, "hours") ?? "PT0S"),
            StartTime: ParseUtc(Str(el, "startTime")),
            EndTime: ParseUtc(Str(el, "endTime")),
            CreatedAt: ParseUtc(Str(el, "createdAt")),
            LockVersion: Int(el, "lockVersion"));
    }

    /// <summary>Éléments de la collection HAL (<c>_embedded.elements</c>), vide si absente.</summary>
    private static IEnumerable<JsonElement> Elements(JsonElement root)
    {
        var embedded = Obj(root, "_embedded");
        if (embedded is null || !embedded.Value.TryGetProperty("elements", out var elements)
            || elements.ValueKind != JsonValueKind.Array)
            yield break;
        foreach (var el in elements.EnumerateArray()) yield return el;
    }

    private static JsonElement? Obj(JsonElement? parent, string key) =>
        parent is { ValueKind: JsonValueKind.Object } p
            && p.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.Object
            ? v : null;

    private static string? Str(JsonElement? parent, string key) =>
        parent is { ValueKind: JsonValueKind.Object } p
            && p.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.String
            ? v.GetString() : null;

    private static int? Int(JsonElement? parent, string key) =>
        parent is { ValueKind: JsonValueKind.Object } p
            && p.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.Number
            && v.TryGetInt32(out var i)
            ? i : null;

    /// <summary>Repli casse + accents, pour comparer des noms de statut saisis à la main.</summary>
    private static string Fold(string text)
    {
        var decomposed = text.Normalize(NormalizationForm.FormD);
        var sb = new StringBuilder(decomposed.Length);
        foreach (var ch in decomposed)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(ch) != UnicodeCategory.NonSpacingMark)
                sb.Append(ch);
        }
        return sb.ToString().Normalize(NormalizationForm.FormC).ToUpperInvariant();
    }

    /// <summary>
    /// Un href HAL commence par « / » ; les chemins sont concaténés à <c>baseURL</c>, on retire
    /// donc la barre initiale pour éviter une double barre.
    /// </summary>
    private static string StripLeadingSlash(string href) =>
        href.StartsWith('/') ? href[1..] : href;

    // MARK: - Utilitaires

    /// <summary>Convertit une durée en secondes vers une durée ISO 8601 arrondie à la minute (min. 1 min).</summary>
    public static string IsoDuration(int seconds)
    {
        var totalMinutes = RoundedMinutes(seconds);
        var h = totalMinutes / 60;
        var m = totalMinutes % 60;
        var sb = new StringBuilder("PT");
        if (h > 0) sb.Append(CultureInfo.InvariantCulture, $"{h}H");
        if (m > 0 || h == 0) sb.Append(CultureInfo.InvariantCulture, $"{m}M");
        return sb.ToString();
    }

    /// <summary>Nombre de minutes retenu par <see cref="IsoDuration"/> (arrondi à la minute, min. 1 min).</summary>
    public static int RoundedMinutes(int seconds) =>
        Math.Max(1, (int)Math.Round(seconds / 60.0, MidpointRounding.AwayFromZero));

    /// <summary>Durée ISO 8601 précise (heures/minutes/secondes exactes), pour l'édition.</summary>
    public static string IsoDurationPrecise(int seconds)
    {
        var s = Math.Max(0, seconds);
        int h = s / 3600, m = s % 3600 / 60, sec = s % 60;
        var sb = new StringBuilder("PT");
        if (h > 0) sb.Append(CultureInfo.InvariantCulture, $"{h}H");
        if (m > 0) sb.Append(CultureInfo.InvariantCulture, $"{m}M");
        if (sec > 0 || (h == 0 && m == 0)) sb.Append(CultureInfo.InvariantCulture, $"{sec}S");
        return sb.ToString();
    }

    /// <summary>Parse une date-heure ISO 8601 UTC (avec ou sans fraction de seconde).</summary>
    public static DateTime? ParseUtc(string? text)
    {
        if (string.IsNullOrEmpty(text)) return null;
        return DateTime.TryParse(text, CultureInfo.InvariantCulture,
            DateTimeStyles.AdjustToUniversal | DateTimeStyles.RoundtripKind, out var d)
            ? DateTime.SpecifyKind(d, DateTimeKind.Utc)
            : null;
    }

    /// <summary>Sérialise un instant en date-heure ISO 8601 UTC (ex. « 2026-07-27T17:32:00Z »).</summary>
    public static string UtcString(DateTime date) =>
        date.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ", CultureInfo.InvariantCulture);

    /// <summary>Parse une durée ISO 8601 (ex. « PT1H30M15S ») en secondes. Ignore les mois/années.</summary>
    public static int SecondsFromIsoDuration(string text)
    {
        if (!text.StartsWith('P')) return 0;

        var total = 0;
        var number = new StringBuilder();
        var inTime = false;

        foreach (var ch in text.AsSpan(1))
        {
            switch (ch)
            {
                case 'T':
                    inTime = true;
                    break;
                case >= '0' and <= '9':
                case '.':
                    number.Append(ch);
                    break;
                case 'D':
                    total += Num(number) * 86400; number.Clear();
                    break;
                case 'H':
                    total += Num(number) * 3600; number.Clear();
                    break;
                case 'M':
                    if (inTime) total += Num(number) * 60;  // sinon = mois, ignoré
                    number.Clear();
                    break;
                case 'S':
                    total += Num(number); number.Clear();
                    break;
                default:
                    number.Clear();
                    break;
            }
        }
        return total;

        static int Num(StringBuilder sb) =>
            double.TryParse(sb.ToString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var d)
                ? (int)d : 0;
    }
}
