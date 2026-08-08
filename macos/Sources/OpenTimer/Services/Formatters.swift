import Foundation

/// Formatteurs partagés, non isolés (utilisables depuis n'importe quel contexte).
enum Formatters {
    /// Date au format OpenProject `yyyy-MM-dd`, en heure locale.
    static let ymd: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
