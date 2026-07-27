import ServiceManagement

/// Inscription de l'app au démarrage de session, sans passer par les Réglages
/// Système ni un helper séparé (API SMAppService, macOS 13+).
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Active ou désactive le lancement automatique. Peut échouer si l'app n'est
    /// pas correctement signée / installée (throws remonté à l'appelant).
    static func set(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        switch (enabled, service.status) {
        case (true, let s) where s != .enabled:
            try service.register()
        case (false, .enabled):
            try service.unregister()
        default:
            break  // déjà dans l'état voulu
        }
    }
}
