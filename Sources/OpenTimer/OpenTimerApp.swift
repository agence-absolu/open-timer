import SwiftUI

@main
struct OpenTimerApp: App {
    @StateObject private var timer = TimerManager()
    @StateObject private var settings = SettingsStore()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(timer)
                .environmentObject(settings)
        } label: {
            // Le label est réévalué à chaque tick du chrono (@Published elapsed),
            // ce qui fait défiler le temps directement dans la barre de menu.
            if timer.isRunning {
                Text("▶ \(timer.formattedElapsed)")
            } else {
                Image(systemName: "timer")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
