import AppKit
import Foundation

/// Thème d'affichage choisi par l'utilisateur, appliqué à toute l'app.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Système"
        case .light: return "Clair"
        case .dark: return "Sombre"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// Détient l'URL de l'instance et le token, persistés dans les préférences de l'app,
/// et fabrique un client API prêt à l'emploi.
///
/// Le token est stocké dans `UserDefaults` (et non dans le trousseau) : l'app étant
/// signée ad-hoc, sa signature change à chaque build, ce qui faisait perdre l'accès à
/// l'entrée trousseau après une mise à jour. Les préférences persistent de façon fiable.
/// Le trousseau n'est plus lu qu'une fois, pour migrer un token déjà présent.
@MainActor
final class SettingsStore: ObservableObject {
    private static let tokenKey = "apiToken"

    @Published var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: "baseURL") }
    }
    @Published var token: String

    /// Thème d'affichage, appliqué à toute l'app dès sa modification.
    @Published var appearance: AppAppearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: "appearance")
            applyAppearance()
        }
    }

    init() {
        self.baseURL = UserDefaults.standard.string(forKey: "baseURL") ?? ""
        self.appearance = UserDefaults.standard.string(forKey: "appearance")
            .flatMap(AppAppearance.init(rawValue:)) ?? .system

        if let stored = UserDefaults.standard.string(forKey: Self.tokenKey), !stored.isEmpty {
            self.token = stored
        } else if let legacy = KeychainStore.load("apiToken"), !legacy.isEmpty {
            // Migration depuis l'ancien stockage trousseau vers les préférences.
            self.token = legacy
            UserDefaults.standard.set(legacy, forKey: Self.tokenKey)
            KeychainStore.delete("apiToken")
        } else {
            self.token = ""
        }

        applyAppearance()
    }

    func saveToken() {
        UserDefaults.standard.set(token, forKey: Self.tokenKey)
        KeychainStore.delete("apiToken")
    }

    /// Applique le thème choisi à l'ensemble de l'app (menu + fenêtres).
    func applyAppearance() {
        NSApplication.shared.appearance = appearance.nsAppearance
    }

    /// Client API, ou `nil` si l'URL ou le token ne sont pas exploitables.
    var api: OpenProjectAPI? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed), url.scheme != nil, !token.isEmpty else { return nil }
        return OpenProjectAPI(baseURL: url, token: token)
    }

    /// URL web du work package sur l'instance OpenProject : `BASE_URL/wp/{ID}`.
    func workPackageURL(id: Int) -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let base = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        return URL(string: "\(base)/wp/\(id)")
    }
}
