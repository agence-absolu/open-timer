import Foundation

/// Un work package OpenProject, décodé depuis la représentation HAL de l'API v3.
struct WorkPackage: Identifiable, Hashable {
    let id: Int
    let subject: String
    let projectName: String?

    var href: String { "/api/v3/work_packages/\(id)" }

    var display: String {
        if let projectName, !projectName.isEmpty {
            return "#\(id) — \(subject)  ·  \(projectName)"
        }
        return "#\(id) — \(subject)"
    }
}

/// Une activité de temps autorisée pour un work package (Développement, Réunion, …).
struct Activity: Identifiable, Hashable {
    let href: String
    let name: String
    var id: String { href }
}
