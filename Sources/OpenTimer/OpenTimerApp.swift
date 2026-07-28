import AppKit
import SwiftUI

/// Identifiants des fenêtres flottantes ouvertes depuis le menu de la barre.
enum WindowID {
    static let new = "new"
    static let history = "history"
    static let preferences = "preferences"
}

/// Délégué d'app minimal : gère le clic sur l'icône du Dock pour (r)ouvrir la
/// fenêtre « Nouveau » (qui affiche la session en cours si le chrono tourne).
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Fournie par la vue une fois l'action `openWindow` de l'environnement disponible.
    var onReopen: (() -> Void)?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        onReopen?()
        return true
    }
}

@main
struct OpenTimerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var timer = TimerManager()
    @StateObject private var settings = SettingsStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu()
                .environmentObject(timer)
                .environmentObject(settings)
        } label: {
            MenuBarLabel(appDelegate: appDelegate)
                .environmentObject(timer)
        }
        .menuBarExtraStyle(.menu)

        Window("Nouveau", id: WindowID.new) {
            TrackerView()
                .environmentObject(timer)
                .environmentObject(settings)
        }
        .windowResizability(.contentSize)

        Window("Historique", id: WindowID.history) {
            HistoryWindowView()
                .environmentObject(timer)
                .environmentObject(settings)
        }
        .windowResizability(.contentSize)

        Window("Préférences", id: WindowID.preferences) {
            PreferencesView()
                .environmentObject(timer)
                .environmentObject(settings)
        }
        .windowResizability(.contentSize)
    }
}

/// Label de la barre de menu. En plus d'afficher le chrono, il capte l'action
/// `openWindow` de l'environnement pour armer le clic sur l'icône du Dock.
private struct MenuBarLabel: View {
    let appDelegate: AppDelegate
    @EnvironmentObject var timer: TimerManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            // Réévalué à chaque tick (@Published elapsed) → le temps défile dans la barre.
            if timer.isRunning {
                Text("\(timer.isPaused ? "⏸" : "●") \(timer.formattedElapsed)")
            } else {
                Image(systemName: "timer")
            }
        }
        .onAppear {
            appDelegate.onReopen = {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: WindowID.new)
            }
        }
    }
}
