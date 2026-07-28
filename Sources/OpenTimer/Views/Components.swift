import SwiftUI

/// Couleurs de l'app. On s'appuie sur la teinte système (native) pour l'accent,
/// et une teinte rouge dédiée à l'état « enregistrement en cours ».
enum Palette {
    static let accent = Color.accentColor
    static let recording = Color(red: 0.90, green: 0.29, blue: 0.31)
    static let card = Color.primary.opacity(0.05)
    static let cardStrong = Color.primary.opacity(0.08)
    /// Fond opaque des fenêtres flottantes : blanc en thème clair, sombre en thème sombre.
    static let windowBackground = Color(nsColor: .textBackgroundColor)
}

extension View {
    /// Fond opaque plein cadre pour une fenêtre flottante.
    func windowSurface() -> some View {
        background(Palette.windowBackground)
    }
}

/// Petit intitulé de section en majuscules (style Réglages macOS / capture Toggl).
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}

/// Bouton d'action principal : plein, pleine largeur, avec état pressé et désactivé.
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        Filled(configuration: configuration, tint: tint)
    }

    struct Filled: View {
        let configuration: ButtonStyleConfiguration
        let tint: Color
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(.white)
                .background(
                    tint.opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.35),
                    in: RoundedRectangle(cornerRadius: 8)
                )
        }
    }
}

extension View {
    /// Fond de carte arrondi standard pour regrouper des champs.
    func cardBackground(_ color: Color = Palette.card, radius: CGFloat = 8) -> some View {
        background(color, in: RoundedRectangle(cornerRadius: radius))
    }
}

/// Lien direct vers le work package sur l'instance OpenProject (ouvre le navigateur).
struct OpenProjectLink: View {
    let url: URL
    var compact = false

    var body: some View {
        Link(destination: url) {
            if compact {
                Image(systemName: "arrow.up.forward.square")
            } else {
                Label("Ouvrir dans OpenProject", systemImage: "arrow.up.forward.square")
                    .font(.caption)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Ouvrir dans OpenProject")
    }
}
