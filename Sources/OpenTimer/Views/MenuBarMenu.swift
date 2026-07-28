import AppKit
import SwiftUI

/// Menu natif de la barre de menu (style capture Toggl) : quatre entrées qui
/// ouvrent les fenêtres flottantes, plus une ligne d'état quand le chrono tourne.
struct MenuBarMenu: View {
    @EnvironmentObject var timer: TimerManager
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Ligne d'état cliquable : ramène la fenêtre du chrono en cours au premier plan.
        if timer.isRunning {
            Button(runningLabel) { open(WindowID.new) }
            Divider()
        }

        Button("Nouveau") { open(WindowID.new) }
        Button("Historique") { open(WindowID.history) }

        Divider()

        Button("Préférences…") { open(WindowID.preferences) }

        Divider()

        Button("Quitter") { NSApplication.shared.terminate(nil) }
    }

    /// Résumé de la session en cours affiché en tête de menu.
    private var runningLabel: String {
        let subject = timer.activeWP?.subject ?? "Session"
        return "\(timer.isPaused ? "⏸" : "●") \(subject) — \(timer.formattedElapsed)"
    }

    /// Active l'app (pour amener la fenêtre au premier plan) puis l'ouvre/la révèle.
    private func open(_ id: String) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: id)
    }
}
