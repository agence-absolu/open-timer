import AppKit
import Combine
import Foundation

/// Pilote le chrono : démarrage/arrêt, temps écoulé (tick 1 s), et écriture du
/// time entry dans OpenProject à l'arrêt.
@MainActor
final class TimerManager: ObservableObject {
    @Published private(set) var isRunning = false {
        didSet { updateDockIcon() }
    }
    @Published private(set) var isPaused = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var activeWP: WorkPackage?
    @Published var lastError: String?
    @Published var lastSaved: String?

    /// Instant de début du segment en cours (nil si en pause).
    private var segmentStart: Date?
    /// Temps cumulé des segments déjà terminés (figé pendant les pauses).
    private var accumulated: TimeInterval = 0
    private var ticker: AnyCancellable?
    private var activeActivityHref: String?

    func start(_ wp: WorkPackage, activityHref: String? = nil) {
        guard !isRunning else { return }
        lastError = nil
        lastSaved = nil
        activeWP = wp
        activeActivityHref = activityHref
        accumulated = 0
        segmentStart = Date()
        elapsed = 0
        isPaused = false
        isRunning = true
        startTicker()
    }

    /// Met le chrono en pause : le temps du segment courant est cumulé et figé.
    func pause() {
        guard isRunning, !isPaused else { return }
        accumulated = currentElapsed()
        segmentStart = nil
        isPaused = true
        ticker?.cancel()
        ticker = nil
        elapsed = accumulated
    }

    /// Reprend le chrono après une pause.
    func resume() {
        guard isRunning, isPaused else { return }
        segmentStart = Date()
        isPaused = false
        startTicker()
    }

    private func startTicker() {
        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.elapsed = self.currentElapsed()
            }
    }

    /// Temps écoulé réel à cet instant (cumulé + segment courant s'il tourne).
    private func currentElapsed() -> TimeInterval {
        guard let segmentStart else { return accumulated }
        return accumulated + Date().timeIntervalSince(segmentStart)
    }

    func stop(using api: OpenProjectAPI?, comment: String) async {
        guard isRunning, let wp = activeWP else { return }
        // En pause, on prend le temps figé au moment de la pause ; sinon le temps courant.
        let seconds = Int(currentElapsed())
        ticker?.cancel()
        ticker = nil
        isRunning = false
        isPaused = false

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
        accumulated = 0
        segmentStart = nil
        isPaused = false
        activeWP = nil
        activeActivityHref = nil
    }

    /// Intervertit l'icône du Dock selon l'état du chrono : icône « running »
    /// tant qu'une session est active (y compris en pause), icône du bundle sinon.
    /// `= nil` restaure l'icône par défaut déclarée dans l'Info.plist.
    private func updateDockIcon() {
        if isRunning,
           let url = Bundle.main.url(forResource: "OpenTimerRunning", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = image
        } else {
            NSApplication.shared.applicationIconImage = nil
        }
    }

    var formattedElapsed: String { Self.format(elapsed) }

    nonisolated static func format(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    /// Durée en heures:minutes (sans secondes), arrondie à la minute la plus proche.
    /// Pour l'historique et l'éditeur, où les secondes ne sont pas pertinentes.
    nonisolated static func formatHM(_ t: TimeInterval) -> String {
        let totalMinutes = Int((max(0, t) / 60).rounded())
        return String(format: "%d:%02d", totalMinutes / 60, totalMinutes % 60)
    }
}
