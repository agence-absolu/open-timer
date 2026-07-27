import SwiftUI

/// Couleurs de l'app. On s'appuie sur la teinte système (native) pour l'accent,
/// et une teinte rouge dédiée à l'état « enregistrement en cours ».
enum Palette {
    static let accent = Color.accentColor
    static let recording = Color(red: 0.90, green: 0.29, blue: 0.31)
    static let card = Color.primary.opacity(0.05)
    static let cardStrong = Color.primary.opacity(0.08)
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
