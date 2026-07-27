import Foundation

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

    init() {
        self.baseURL = UserDefaults.standard.string(forKey: "baseURL") ?? ""

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
    }

    func saveToken() {
        UserDefaults.standard.set(token, forKey: Self.tokenKey)
        KeychainStore.delete("apiToken")
    }

    /// Client API, ou `nil` si l'URL ou le token ne sont pas exploitables.
    var api: OpenProjectAPI? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed), url.scheme != nil, !token.isEmpty else { return nil }
        return OpenProjectAPI(baseURL: url, token: token)
    }
}
