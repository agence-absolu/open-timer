import Foundation

/// Une saisie de temps déjà enregistrée dans OpenProject.
struct TimeEntry: Identifiable, Hashable {
    let id: Int
    let workPackageTitle: String?
    let workPackageHref: String?
    let projectTitle: String?
    let comment: String
    let spentOn: String   // "yyyy-MM-dd"
    let seconds: Int      // durée en secondes, parsée depuis le champ ISO 8601 `hours`
    let startTime: Date?  // instant de début en UTC (si l'option est activée sur l'instance)
    let endTime: Date?    // instant de fin en UTC (idem)
    let lockVersion: Int?

    /// Date reformatée jj/MM/aaaa pour l'affichage.
    var displayDate: String {
        guard let d = Formatters.ymd.date(from: spentOn) else { return spentOn }
        return TimeEntry.displayFormatter.string(from: d)
    }

    static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy"
        f.locale = Locale(identifier: "fr_FR")
        return f
    }()
}
