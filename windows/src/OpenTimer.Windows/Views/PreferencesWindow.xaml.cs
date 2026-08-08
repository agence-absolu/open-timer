using System.Net.Http;
using System.Windows;
using OpenTimer.Services;

namespace OpenTimer.Views;

/// <summary>
/// Connexion (URL + token + test) et lancement au démarrage.
/// Pendant de <c>PreferencesView.swift</c> + <c>SettingsView.swift</c>.
/// </summary>
public partial class PreferencesWindow : Window
{
    private readonly SettingsStore _settings = App.Settings;

    public PreferencesWindow()
    {
        InitializeComponent();

        BaseUrlBox.Text = _settings.BaseUrl;
        TokenBox.Password = _settings.Token;
        LaunchAtLoginBox.IsChecked = LaunchAtLogin.IsEnabled;

        // Persistance à la volée : pas de bouton « Enregistrer », comme sur macOS.
        BaseUrlBox.LostFocus += (_, _) => _settings.BaseUrl = BaseUrlBox.Text;
        TokenBox.LostFocus += (_, _) => { _settings.Token = TokenBox.Password; _settings.Save(); };
    }

    private async void OnTest(object sender, RoutedEventArgs e)
    {
        // Le test porte sur ce qui est saisi à l'écran, pas sur ce qui a été persisté.
        _settings.BaseUrl = BaseUrlBox.Text;
        _settings.Token = TokenBox.Password;
        _settings.Save();

        if (_settings.Api is not { } api)
        {
            TestResult.Text = "URL ou token invalide.";
            return;
        }

        TestButton.IsEnabled = false;
        TestResult.Text = "Connexion…";
        try
        {
            var name = await api.CurrentUserAsync();
            TestResult.Text = $"Connecté : {name}";
        }
        catch (Exception ex) when (ex is OpenProjectException or HttpRequestException or TaskCanceledException)
        {
            TestResult.Text = ex.Message;
        }
        finally
        {
            TestButton.IsEnabled = true;
        }
    }

    private void OnLaunchAtLoginToggled(object sender, RoutedEventArgs e)
    {
        var wanted = LaunchAtLoginBox.IsChecked == true;
        if (!LaunchAtLogin.SetEnabled(wanted))
        {
            // Le registre a refusé : on remet la case dans son état réel.
            LaunchAtLoginBox.IsChecked = LaunchAtLogin.IsEnabled;
        }
    }
}
