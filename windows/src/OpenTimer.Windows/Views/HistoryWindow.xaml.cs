using System.Net.Http;
using System.Windows;
using OpenTimer.Services;

namespace OpenTimer.Views;

/// <summary>
/// Projection d'affichage d'une saisie — la grille ne sait pas formater une durée en secondes.
///
/// Public et non imbriqué : le binding WPF passe par <c>TypeDescriptor</c>, qui n'atteint pas
/// les propriétés d'un type non public. Une colonne resterait silencieusement vide.
/// </summary>
public sealed record HistoryRow(int Id, string DisplayDate, string Duration, string Title, string Comment);

/// <summary>
/// Fenêtre « Historique ». Pendant de <c>HistoryView.swift</c>, en lecture seule pour
/// l'instant : l'édition (Début/Fin → Durée recalculée) et la suppression restent à porter.
/// </summary>
public partial class HistoryWindow : Window
{
    private readonly SettingsStore _settings = App.Settings;

    public HistoryWindow()
    {
        InitializeComponent();
        Loaded += async (_, _) => await ReloadAsync();
    }

    private async void OnReload(object sender, RoutedEventArgs e) => await ReloadAsync();

    private async Task ReloadAsync()
    {
        if (_settings.Api is not { } api)
        {
            StatusText.Text = "Connexion à configurer dans les préférences.";
            return;
        }

        ReloadButton.IsEnabled = false;
        StatusText.Text = "Chargement…";
        try
        {
            var entries = await api.RecentTimeEntriesAsync();
            EntriesList.ItemsSource = entries.Select(entry => new HistoryRow(
                entry.Id,
                entry.DisplayDate,
                TimerManager.FormatHm(TimeSpan.FromSeconds(entry.Seconds)),
                entry.WorkPackageId is { } wpId
                    ? $"#{wpId} — {entry.WorkPackageTitle}"
                    : entry.WorkPackageTitle ?? "",
                entry.Comment)).ToList();

            StatusText.Text = $"{entries.Count} saisie(s).";
        }
        catch (Exception ex) when (ex is OpenProjectException or HttpRequestException or TaskCanceledException)
        {
            StatusText.Text = ex.Message;
        }
        finally
        {
            ReloadButton.IsEnabled = true;
        }
    }
}
