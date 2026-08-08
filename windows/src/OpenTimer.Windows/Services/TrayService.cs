using System.ComponentModel;
using System.Drawing;
using System.Windows.Forms;

namespace OpenTimer.Services;

/// <summary>
/// Icône de la zone de notification et son menu contextuel.
/// Pendant de <c>MenuBarExtra</c> + <c>MenuBarMenu.swift</c> côté macOS.
///
/// L'icône est redessinée à chaque changement de <b>minute</b> (voir
/// <see cref="TrayIconRenderer"/>) : redessiner chaque seconde ferait clignoter la
/// barre des tâches pour un chiffre invisible à 16 px. Le tooltip, lui, porte la
/// durée précise et se met à jour à chaque tick.
/// </summary>
public sealed class TrayService : IDisposable
{
    private readonly NotifyIcon _icon;
    private readonly TimerManager _timer;
    private readonly ToolStripMenuItem _statusItem;
    private readonly ToolStripSeparator _statusSeparator;

    /// <summary>Icône affichée, à disposer avant remplacement (ressource GDI non gérée).</summary>
    private Icon? _currentIcon;

    /// <summary>Dernière minute rendue, pour ne redessiner que quand le texte change.</summary>
    private int _renderedMinutes = -1;

    public event Action? NewRequested;
    public event Action? HistoryRequested;
    public event Action? PreferencesRequested;
    public event Action? QuitRequested;

    public TrayService(TimerManager timer)
    {
        _timer = timer;

        _statusItem = new ToolStripMenuItem("") { Visible = false };
        _statusItem.Click += (_, _) => NewRequested?.Invoke();
        _statusSeparator = new ToolStripSeparator { Visible = false };

        var menu = new ContextMenuStrip();
        menu.Items.Add(_statusItem);
        menu.Items.Add(_statusSeparator);
        menu.Items.Add(Item("Nouveau…", () => NewRequested?.Invoke()));
        menu.Items.Add(Item("Historique…", () => HistoryRequested?.Invoke()));
        menu.Items.Add(Item("Préférences…", () => PreferencesRequested?.Invoke()));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(Item("Quitter OpenTimer", () => QuitRequested?.Invoke()));

        _icon = new NotifyIcon
        {
            ContextMenuStrip = menu,
            Text = "OpenTimer",
            Visible = true,
        };
        // Clic gauche : ouvrir « Nouveau », pendant du clic sur l'icône du Dock macOS.
        _icon.MouseClick += (_, e) =>
        {
            if (e.Button == MouseButtons.Left) NewRequested?.Invoke();
        };

        _timer.PropertyChanged += OnTimerChanged;
        Refresh(force: true);

        static ToolStripMenuItem Item(string text, Action action)
        {
            var item = new ToolStripMenuItem(text);
            item.Click += (_, _) => action();
            return item;
        }
    }

    private void OnTimerChanged(object? sender, PropertyChangedEventArgs e)
    {
        var stateChanged = e.PropertyName is nameof(TimerManager.IsRunning)
            or nameof(TimerManager.IsPaused) or nameof(TimerManager.ActiveWp);
        if (stateChanged || e.PropertyName == nameof(TimerManager.Elapsed))
            Refresh(force: stateChanged);
    }

    private void Refresh(bool force)
    {
        var running = _timer.IsRunning;
        var minutes = (int)_timer.Elapsed.TotalMinutes;

        // Tooltip : durée à la seconde près, limitée à 63 caractères (contrainte Win32).
        var wp = _timer.ActiveWp;
        var tip = running
            ? $"{(_timer.IsPaused ? "⏸" : "●")} {_timer.FormattedElapsed}"
              + (wp is null ? "" : $" — #{wp.Id}")
            : "OpenTimer";
        _icon.Text = tip.Length > 63 ? tip[..63] : tip;

        _statusItem.Visible = running;
        _statusSeparator.Visible = running;
        if (running) _statusItem.Text = tip;

        if (!force && minutes == _renderedMinutes) return;
        _renderedMinutes = minutes;

        var next = running
            ? TrayIconRenderer.RenderElapsed(_timer.Elapsed, _timer.IsPaused)
            : TrayIconRenderer.RenderIdle();

        _icon.Icon = next;
        _currentIcon?.Dispose();
        _currentIcon = next;
    }

    public void Dispose()
    {
        _timer.PropertyChanged -= OnTimerChanged;
        _icon.Visible = false;
        _icon.Dispose();
        _currentIcon?.Dispose();
    }
}
