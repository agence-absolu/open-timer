import Combine
import Foundation

/// Pilote le chrono : démarrage/arrêt, temps écoulé (tick 1 s), et écriture du
/// time entry dans OpenProject à l'arrêt.
@MainActor
final class TimerManager: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var activeWP: WorkPackage?
    @Published var lastError: String?
    @Published var lastSaved: String?

    private var startDate: Date?
    private var ticker: AnyCancellable?
    private var activeActivityHref: String?

    func start(_ wp: WorkPackage, activityHref: String? = nil) {
        guard !isRunning else { return }
        lastError = nil
        lastSaved = nil
        activeWP = wp
        activeActivityHref = activityHref
        startDate = Date()
        elapsed = 0
        isRunning = true
        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let start = self.startDate else { return }
                self.elapsed = Date().timeIntervalSince(start)
            }
    }

    func stop(using api: OpenProjectAPI?, comment: String) async {
        guard isRunning, let wp = activeWP else { return }
        ticker?.cancel()
        ticker = nil
        isRunning = false
        let seconds = Int(elapsed)

        guard let api else {
            lastError = "Configure d'abord ton token dans Réglages."
            reset()
            return
        }

        let hours = OpenProjectAPI.isoDuration(seconds: seconds)
        let today = Formatters.ymd.string(from: Date())
        do {
            // Activité choisie au démarrage ; sinon la première autorisée (requise par OP).
            var activityHref = activeActivityHref
            if activityHref == nil {
                activityHref = (try? await api.activities(forWorkPackageHref: wp.href))?.first?.href
            }
            try await api.createTimeEntry(
                workPackageHref: wp.href,
                hours: hours,
                spentOn: today,
                comment: comment,
                activityHref: activityHref
            )
            lastSaved = "Enregistré : \(hours) sur #\(wp.id)"
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        reset()
    }

    private func reset() {
        elapsed = 0
        startDate = nil
        activeWP = nil
        activeActivityHref = nil
    }

    var formattedElapsed: String { Self.format(elapsed) }

    nonisolated static func format(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
}
