import SwiftUI

/// Fenêtre « Préférences » : connexion à l'instance, lancement au démarrage, thème.
struct PreferencesView: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsView()

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "Général")

                Toggle(isOn: $launchAtLogin) {
                    Text("Lancer au démarrage")
                }
                .toggleStyle(.checkbox)
                .onChange(of: launchAtLogin) { newValue in
                    do { try LaunchAtLogin.set(newValue) }
                    catch { launchAtLogin = LaunchAtLogin.isEnabled }
                }

                HStack {
                    Text("Apparence")
                    Spacer()
                    Picker("", selection: $settings.appearance) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.label).tag(appearance)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .frame(width: 360)
        .windowSurface()
    }
}
