using System.ComponentModel;
using System.IO;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace OpenTimer.Services;

/// <summary>Thème d'affichage choisi par l'utilisateur, appliqué à toute l'app.</summary>
public enum AppAppearance
{
    System,
    Light,
    Dark,
}

public static class AppAppearanceExtensions
{
    public static string Label(this AppAppearance a) => a switch
    {
        AppAppearance.System => "Système",
        AppAppearance.Light => "Clair",
        AppAppearance.Dark => "Sombre",
        _ => "Système",
    };
}

/// <summary>
/// Détient l'URL de l'instance et le token, persistés dans
/// <c>%APPDATA%\OpenTimer\settings.json</c>, et fabrique un client API prêt à l'emploi.
///
/// Le token est chiffré au repos via <see cref="Dpapi"/> (lié au compte Windows) ; le
/// fichier reste lisible pour le reste des réglages.
/// </summary>
public sealed class SettingsStore : INotifyPropertyChanged
{
    private static readonly string Dir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "OpenTimer");

    private static readonly string FilePath = Path.Combine(Dir, "settings.json");

    /// <summary>Forme sérialisée du fichier de réglages.</summary>
    private sealed class Payload
    {
        [JsonPropertyName("baseUrl")] public string BaseUrl { get; set; } = "";
        /// <summary>Token chiffré DPAPI, encodé en base64. Jamais en clair sur le disque.</summary>
        [JsonPropertyName("tokenProtected")] public string TokenProtected { get; set; } = "";
        [JsonPropertyName("appearance")] public string Appearance { get; set; } = nameof(AppAppearance.System);
    }

    private string _baseUrl = "";
    private string _token = "";
    private AppAppearance _appearance = AppAppearance.System;

    public SettingsStore() => Load();

    public string BaseUrl
    {
        get => _baseUrl;
        set { if (Set(ref _baseUrl, value)) Save(); }
    }

    /// <summary>Token API. Modifier la propriété ne persiste rien : appeler <see cref="Save"/>.</summary>
    public string Token
    {
        get => _token;
        set => Set(ref _token, value);
    }

    public AppAppearance Appearance
    {
        get => _appearance;
        set { if (Set(ref _appearance, value)) Save(); }
    }

    /// <summary>Client API, ou <c>null</c> si l'URL ou le token ne sont pas exploitables.</summary>
    public OpenProjectApi? Api
    {
        get
        {
            var trimmed = BaseUrl.Trim();
            if (Token.Length == 0) return null;
            if (!Uri.TryCreate(trimmed, UriKind.Absolute, out var uri)) return null;
            if (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps) return null;
            // Barre finale obligatoire : sans elle, `new Uri(base, "api/v3/…")` remplace le
            // dernier segment du chemin au lieu de s'y ajouter (instance servie sous /openproject).
            if (!uri.AbsoluteUri.EndsWith('/')) uri = new Uri(uri.AbsoluteUri + "/");
            return new OpenProjectApi(uri, Token);
        }
    }

    /// <summary>URL web du work package sur l'instance OpenProject : <c>BASE_URL/wp/{ID}</c>.</summary>
    public Uri? WorkPackageUrl(int id)
    {
        var trimmed = BaseUrl.Trim().TrimEnd('/');
        if (trimmed.Length == 0) return null;
        return Uri.TryCreate($"{trimmed}/wp/{id}", UriKind.Absolute, out var uri) ? uri : null;
    }

    // MARK: - Persistance

    private void Load()
    {
        try
        {
            if (!File.Exists(FilePath)) return;
            var payload = JsonSerializer.Deserialize<Payload>(File.ReadAllText(FilePath));
            if (payload is null) return;

            _baseUrl = payload.BaseUrl;
            _token = Dpapi.Unprotect(payload.TokenProtected);
            _appearance = Enum.TryParse<AppAppearance>(payload.Appearance, ignoreCase: true, out var a)
                ? a : AppAppearance.System;
        }
        catch (Exception ex) when (ex is IOException or JsonException or UnauthorizedAccessException)
        {
            // Fichier illisible ou corrompu : on démarre sur les valeurs par défaut.
        }
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Dir);
            var payload = new Payload
            {
                BaseUrl = _baseUrl,
                TokenProtected = Dpapi.Protect(_token),
                Appearance = _appearance.ToString(),
            };
            File.WriteAllText(FilePath,
                JsonSerializer.Serialize(payload, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Écriture impossible : les réglages restent valides en mémoire pour la session.
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    private bool Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return false;
        field = value;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
        return true;
    }
}
