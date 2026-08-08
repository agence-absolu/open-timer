import SwiftUI

/// Configuration de l'URL de l'instance et du token, avec test de connexion.
struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    var onSaved: () -> Void = {}

    @State private var testResult: String?
    @State private var testOK = false
    @State private var testing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Connexion")

            VStack(spacing: 8) {
                TextField("https://votre-instance.openproject.com", text: $settings.baseURL)
                    .textFieldStyle(.roundedBorder)
                SecureField("Token API", text: $settings.token)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 8) {
                Button { Task { await test() } } label: {
                    if testing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Tester")
                    }
                }
                .disabled(testing || settings.api == nil)

                Spacer()

                Button("Enregistrer") {
                    settings.saveToken()
                    onSaved()
                }
                .buttonStyle(.borderedProminent)
                .disabled(settings.token.isEmpty)
            }

            if let result = testResult {
                Label(result, systemImage: testOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(testOK ? .green : .red)
            }

            Text("Token : OpenProject → Mon compte → Jetons d'accès → API.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func test() async {
        testing = true
        testResult = nil
        guard let api = settings.api else {
            testResult = "URL ou token invalide."
            testOK = false
            testing = false
            return
        }
        do {
            let name = try await api.currentUser()
            testResult = "Connecté : \(name)"
            testOK = true
        } catch {
            testResult = error.localizedDescription
            testOK = false
        }
        testing = false
    }
}
