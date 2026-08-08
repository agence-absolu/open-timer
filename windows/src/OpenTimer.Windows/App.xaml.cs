using System.Windows;
using OpenTimer.Services;
using OpenTimer.Views;

namespace OpenTimer;

/// <summary>
/// Point d'entrée. Pendant de <c>OpenTimerApp.swift</c> : l'app n'a pas de fenêtre
/// principale, elle vit dans la zone de notification et ouvre ses fenêtres à la demande.
///
/// Les deux services partagés (<see cref="SettingsStore"/>, <see cref="TimerManager"/>)
/// sont créés ici et exposés en statique — équivalent de l'injection dans l'environnement
/// SwiftUI côté macOS.
/// </summary>
public partial class App : System.Windows.Application
{
    public static SettingsStore Settings { get; private set; } = null!;
    public static TimerManager Timer { get; private set; } = null!;

    private TrayService? _tray;
    private readonly Dictionary<Type, Window> _windows = [];

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        Settings = new SettingsStore();
        Timer = new TimerManager();

        _tray = new TrayService(Timer);
        _tray.NewRequested += ShowTracker;
        _tray.HistoryRequested += () => Show(() => new HistoryWindow());
        _tray.PreferencesRequested += ShowPreferences;
        _tray.QuitRequested += () => Shutdown();

        // Ouverture au lancement, comme sur macOS (v0.7.0).
        ShowTracker();
    }

    public static void ShowTracker() => Current().Show(() => new TrackerWindow());

    public static void ShowPreferences() => Current().Show(() => new PreferencesWindow());

    private static App Current() => (App)System.Windows.Application.Current;

    protected override void OnExit(ExitEventArgs e)
    {
        _tray?.Dispose();
        base.OnExit(e);
    }

    /// <summary>
    /// Affiche une fenêtre unique par type. La fermeture la masque au lieu de la détruire
    /// (<see cref="ShutdownMode.OnExplicitShutdown"/> garde le processus vivant dans le tray),
    /// ce qui préserve la saisie en cours entre deux ouvertures.
    /// </summary>
    private void Show<T>(Func<T> factory) where T : Window
    {
        if (!_windows.TryGetValue(typeof(T), out var window))
        {
            window = factory();
            window.Closing += (sender, args) =>
            {
                args.Cancel = true;
                ((Window)sender!).Hide();
            };
            _windows[typeof(T)] = window;
        }

        window.Show();
        if (window.WindowState == WindowState.Minimized) window.WindowState = WindowState.Normal;
        window.Activate();
    }
}
