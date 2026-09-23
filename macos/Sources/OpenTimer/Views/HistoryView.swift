import SwiftUI

/// Fenêtre « Historique » : liste des saisies, et bascule vers l'éditeur au clic.
struct HistoryWindowView: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var editingEntry: TimeEntry?
    @State private var historyReload = 0

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
            .frame(width: 460, height: 480)
            .windowSurface()
    }

    @ViewBuilder private var content: some View {
        if settings.token.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Connexion non configurée", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
                Text("Renseigne l'URL et le token dans les Préférences.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else if let entry = editingEntry {
            TimeEntryEditView(
                entry: entry,
                api: settings.api,
                url: entry.workPackageID.flatMap(settings.workPackageURL)
            ) {
                editingEntry = nil
                historyReload += 1
            }
        } else {
            HistoryView(
                api: settings.api,
                reloadToken: historyReload,
                wpURL: settings.workPackageURL
            ) { editingEntry = $0 }
        }
    }
}

/// Liste des dernières saisies de temps ; un clic ouvre l'éditeur.
struct HistoryView: View {
    let api: OpenProjectAPI?
    let reloadToken: Int
    var wpURL: (Int) -> URL? = { _ in nil }
    var onEdit: (TimeEntry) -> Void

    @State private var entries: [TimeEntry] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "Dernières saisies")
                Spacer()
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Recharger")
            }

            if loading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Chargement…").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 10)
            } else if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
            } else if entries.isEmpty {
                Text("Aucune saisie récente.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 10)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(entries) { entry in
                            TimeEntryRow(entry: entry, url: entry.workPackageID.flatMap(wpURL))
                                .contentShape(Rectangle())
                                .onTapGesture { onEdit(entry) }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: reloadToken) { await load() }
    }

    private func load() async {
        guard let api else { error = "Token manquant."; return }
        loading = true
        error = nil
        do { entries = try await api.recentTimeEntries(limit: 20) }
        catch { self.error = error.localizedDescription }
        loading = false
    }
}

private struct TimeEntryRow: View {
    let entry: TimeEntry
    let url: URL?

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.workPackageTitle ?? "—").font(.callout).lineLimit(1)
                HStack(spacing: 5) {
                    if let p = entry.projectTitle, !p.isEmpty { Text(p).lineLimit(1) }
                    Text("· \(entry.displayDate)")
                }
                .font(.caption2).foregroundStyle(.secondary)
                if !entry.comment.isEmpty {
                    Text(entry.comment).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let url { OpenProjectLink(url: url, compact: true) }
            Text(TimerManager.formatHM(TimeInterval(entry.seconds)))
                .font(.caption.monospacedDigit().weight(.semibold))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Palette.cardStrong, in: Capsule())
            Image(systemName: "chevron.right")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6).padding(.horizontal, 8)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Éditeur d'une saisie : Début et Fin éditables, Durée = Fin − Début (calculée).
/// Corrige le cas « oubli d'arrêt » : on ajuste la Fin, la durée se recalcule.
struct TimeEntryEditView: View {
    let entry: TimeEntry
    let api: OpenProjectAPI?
    let url: URL?
    var onDone: () -> Void

    @State private var comment: String
    @State private var start: Date
    @State private var end: Date
    @State private var startEndSupported: Bool?
    @State private var busy = false
    @State private var error: String?
    @State private var confirmDelete = false

    init(entry: TimeEntry, api: OpenProjectAPI?, url: URL? = nil, onDone: @escaping () -> Void) {
        self.entry = entry
        self.api = api
        self.url = url
        self.onDone = onDone
        _comment = State(initialValue: entry.comment)

        // Sans heures début/fin côté serveur (option désactivée), la fin est reconstituée à
        // partir de `createdAt` : l'app crée la saisie à l'arrêt du chrono. On garde le jour
        // de `spentOn` (il a pu être modifié depuis). L'heure courante n'est qu'un dernier recours.
        let day = Formatters.ymd.date(from: entry.spentOn) ?? Date()
        let duration = TimeInterval(entry.seconds)
        let seededEnd = entry.endTime
            ?? Self.combine(day: day, timeFrom: entry.createdAt ?? Date())
        let seededStart = entry.startTime ?? seededEnd.addingTimeInterval(-duration)
        _start = State(initialValue: seededStart)
        _end = State(initialValue: entry.endTime ?? seededStart.addingTimeInterval(duration))
    }

    private var durationSeconds: Int { Int(end.timeIntervalSince(start)) }
    private var isValid: Bool { durationSeconds > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Button { onDone() } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                SectionLabel(text: "Modifier la saisie")
            }

            // Work package concerné
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.workPackageTitle ?? "—").font(.callout.weight(.medium)).lineLimit(2)
                    if let p = entry.projectTitle, !p.isEmpty {
                        Text(p).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                if let url { OpenProjectLink(url: url, compact: true) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .cardBackground()

            // Description
            VStack(alignment: .leading, spacing: 5) {
                SectionLabel(text: "Détails")
                TextField("Description…", text: $comment).textFieldStyle(.roundedBorder)
            }

            // Début / Fin / Durée groupés
            VStack(alignment: .leading, spacing: 5) {
                SectionLabel(text: "Durée")
                VStack(spacing: 0) {
                    editorRow("Début") {
                        DatePicker("", selection: $start, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                    }
                    Divider().padding(.leading, 10)
                    editorRow("Fin") {
                        DatePicker("", selection: $end, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                    }
                    Divider().padding(.leading, 10)
                    editorRow("Total") {
                        Text(isValid ? TimerManager.formatHM(TimeInterval(durationSeconds)) : "—")
                            .font(.body.monospacedDigit().weight(.semibold))
                            .foregroundStyle(isValid ? Color.primary : Color.red)
                    }
                }
                .cardBackground()

                if !isValid {
                    Text("La fin doit être postérieure au début.")
                        .font(.caption2).foregroundStyle(.red)
                }
            }

            if startEndSupported == false {
                Text("Heures début/fin non enregistrées côté OpenProject (option désactivée). Seules la durée et la date le sont.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
            }

            // Actions
            if confirmDelete {
                HStack {
                    Text("Supprimer cette saisie ?").font(.caption)
                    Spacer()
                    Button("Annuler") { confirmDelete = false }.disabled(busy)
                    Button("Supprimer", role: .destructive) { Task { await remove() } }.disabled(busy)
                }
            } else {
                HStack {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain).foregroundStyle(.red)
                    .disabled(busy)
                    .help("Supprimer")
                    Spacer()
                    if busy { ProgressView().controlSize(.small) }
                    Button("Enregistrer") { Task { await save() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(busy || !isValid)
                }
            }
        }
        .task {
            startEndSupported = await api?.startEndSupported(forWorkPackageHref: entry.workPackageHref)
        }
    }

    private func editorRow<Trailing: View>(_ label: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(label).font(.callout).foregroundStyle(.secondary)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
    }

    private func save() async {
        guard let api else { error = "Token manquant."; return }
        guard isValid else { error = "La fin doit être postérieure au début."; return }
        busy = true
        error = nil
        let sendTimes = (startEndSupported ?? false)
        let spentOn = Formatters.ymd.string(from: start)
        do {
            try await api.updateTimeEntry(
                id: entry.id,
                seconds: durationSeconds,
                spentOn: spentOn,
                comment: comment,
                lockVersion: entry.lockVersion,
                startTimeUTC: sendTimes ? OpenProjectAPI.utcString(start) : nil
            )
            onDone()
        } catch {
            self.error = error.localizedDescription
            busy = false
        }
    }

    private func remove() async {
        guard let api else { error = "Token manquant."; return }
        busy = true
        error = nil
        do {
            try await api.deleteTimeEntry(id: entry.id)
            onDone()
        } catch {
            self.error = error.localizedDescription
            busy = false
        }
    }

    /// Combine le jour d'une date avec l'heure/minute d'une autre.
    static func combine(day: Date, timeFrom time: Date) -> Date {
        let cal = Calendar.current
        let d = cal.dateComponents([.year, .month, .day], from: day)
        let t = cal.dateComponents([.hour, .minute], from: time)
        var c = DateComponents()
        c.year = d.year; c.month = d.month; c.day = d.day
        c.hour = t.hour; c.minute = t.minute
        return cal.date(from: c) ?? day
    }
}
