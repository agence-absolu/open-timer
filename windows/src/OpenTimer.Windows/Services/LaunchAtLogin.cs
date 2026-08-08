using Microsoft.Win32;

namespace OpenTimer.Services;

/// <summary>
/// Lancement au démarrage de la session Windows, via la clé de registre <c>Run</c> de
/// l'utilisateur courant. Pendant de <c>SMAppService.mainApp</c> côté macOS.
///
/// HKCU et non HKLM : pas de droits administrateur requis, et le réglage suit le profil.
/// </summary>
public static class LaunchAtLogin
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "OpenTimer";

    /// <summary>Chemin de l'exécutable courant, entre guillemets (le chemin peut contenir des espaces).</summary>
    private static string ExecutablePath =>
        $"\"{Environment.ProcessPath ?? AppContext.BaseDirectory}\"";

    public static bool IsEnabled
    {
        get
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(RunKey);
                return key?.GetValue(ValueName) is string;
            }
            catch
            {
                return false;
            }
        }
    }

    /// <summary>Active ou désactive le lancement au démarrage. Renvoie <c>false</c> si le registre a refusé.</summary>
    public static bool SetEnabled(bool enabled)
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey, writable: true)
                            ?? Registry.CurrentUser.CreateSubKey(RunKey);
            if (key is null) return false;

            if (enabled) key.SetValue(ValueName, ExecutablePath, RegistryValueKind.String);
            else key.DeleteValue(ValueName, throwOnMissingValue: false);
            return true;
        }
        catch
        {
            return false;
        }
    }
}
