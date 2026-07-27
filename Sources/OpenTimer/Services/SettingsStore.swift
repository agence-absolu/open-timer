import Foundation

/// Détient l'URL de l'instance et le token, persistés (UserDefaults + Keychain),
/// et fabrique un client API prêt à l'emploi.
@MainActor
final class SettingsStore: ObservableObject {
    @Published var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: "baseURL") }
    }
    @Published var token: String

    init() {
        self.baseURL = UserDefaults.standard.string(forKey: "baseURL") ?? ""
        self.token = KeychainStore.load("apiToken") ?? ""
    }

    func saveToken() {
        KeychainStore.save(token, account: "apiToken")
    }

    /// Client API, ou `nil` si l'URL ou le token ne sont pas exploitables.
    var api: OpenProjectAPI? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed), url.scheme != nil, !token.isEmpty else { return nil }
        return OpenProjectAPI(baseURL: url, token: token)
    }
}
