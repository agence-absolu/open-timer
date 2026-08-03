import AppKit
import SwiftUI

/// Fenêtre « Nouveau » : recherche d'un work package et démarrage du chrono,
/// ou vue « en cours » quand une session est active.
struct TrackerView: View {
    @EnvironmentObject var timer: TimerManager
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.openWindow) private var openWindow

    @State private var workPackages: [WorkPackage] = []
    @State private var selected: WorkPackage?
    @State private var query: String = ""
    @State private var comment: String = ""
    @State private var activities: [Activity] = []
    @State private var selectedActivity: Activity?
    @State private var loading = false
    @State private var loadError: String?

    /// Élargit la recherche à tous les WP ouverts (pas seulement les miens) via une
    /// requête serveur ; sinon on filtre localement mes WP assignés.
    @State private var searchAll = false
    @State private var remoteResults: [WorkPackage] = []
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if settings.token.isEmpty {
                needsSetup
            } else if timer.isRunning {
                runningView
            } else {
                trackerView
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .frame(width: 360)
        .windowSurface()
        .task(id: settings.token) { if !settings.token.isEmpty && workPackages.isEmpty { await load() } }
        .onChange(of: timer.isRunning) { running in
            // À l'arrêt du chrono, on désélectionne le WP pour éviter de relancer
            // un timer par inadvertance : il faut resélectionner explicitement.
            if !running {
                selected = nil
                activities = []
                selectedActivity = nil
            }
        }
    }

    // MARK: - Connexion manquante

    private var needsSetup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Connexion non configurée", systemImage: "exclamationmark.triangle.fill")
                .font(.callout).foregroundStyle(.orange)
            Text("Renseigne l'URL de ton instance et ton token API dans les Préférences.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Ouvrir les Préférences") { openWindow(id: WindowID.preferences) }
        }
    }

    // MARK: - État « en cours »

    private var runningView: some View {
        let paused = timer.isPaused
        let accent = paused ? Color.secondary : Palette.recording
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: paused ? "pause.circle.fill" : "record.circle")
                        .foregroundStyle(accent)
                    Text(paused ? "En pause" : "En cours")
                        .font(.caption.weight(.medium)).foregroundStyle(accent)
                    Spacer()
                    if let wp = timer.activeWP, let url = settings.workPackageURL(id: wp.id) {
                        OpenProjectLink(url: url, compact: true)
                    }
                }
                Text(timer.activeWP?.subject ?? "—").font(.headline).lineLimit(2)
                if let wp = timer.activeWP {
                    HStack(spacing: 5) {
                        Text("#\(wp.id)").monospacedDigit()
                        if let client = wp.projectName, !client.isEmpty {
                            Text("· \(client)").lineLimit(1)
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Text(timer.formattedElapsed)
                    .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(paused ? Color.secondary : Color.primary)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .cardBackground(accent.opacity(0.09), radius: 12)

            HStack(spacing: 8) {
                Button {
                    if paused { timer.resume() } else { timer.pause() }
                } label: {
                    Label(paused ? "Reprendre" : "Pause",
                          systemImage: paused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(PrimaryButtonStyle(tint: paused ? Palette.accent : Color.secondary))

                Button {
                    let c = comment
                    Task { await timer.stop(using: settings.api, comment: c); comment = "" }
                } label: {
                    Label("Arrêter", systemImage: "stop.fill")
                }
                .buttonStyle(PrimaryButtonStyle(tint: Palette.recording))
            }

            statusLine
        }
    }

    // MARK: - État « tracker » (recherche + démarrage)

    private var trackerView: some View {
        VStack(alignment: .leading, spacing: 10) {
            completionCard
            searchField
            scopeToggle
            resultsList

            if selected != nil {
                activityPicker
            }

            TextField("Commentaire (optionnel)", text: $comment)
                .textFieldStyle(.roundedBorder)

            Button {
                if let wp = selected { timer.start(wp, activityHref: selectedActivity?.href) }
            } label: {
                Label("Démarrer", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(selected == nil)

            statusLine
        }
        .onChange(of: selected) { wp in
            Task { await loadActivities(for: wp) }
        }
        .onChange(of: query) { _ in if searchAll { scheduleRemoteSearch() } }
        .onChange(of: searchAll) { on in
            selected = nil
            if on {
                scheduleRemoteSearch(immediate: true)
            } else {
                searchTask?.cancel()
                remoteResults = []
                loading = false
            }
        }
    }

    /// Bascule « mes WP » ↔ « tous les WP ».
    private var scopeToggle: some View {
        Toggle(isOn: $searchAll) {
            Text("Tous les work packages (assignés à d'autres inclus)")
                .font(.caption).foregroundStyle(.secondary)
        }
        .toggleStyle(.checkbox)
    }

    private var activityPicker: some View {
        HStack(spacing: 8) {
            Image(systemName: "tag").foregroundStyle(.secondary)
            Picker("Activité", selection: $selectedActivity) {
                ForEach(activities) { activity in
                    Text(activity.name).tag(Activity?.some(activity))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .disabled(activities.isEmpty)
            Spacer(minLength: 0)
        }
        .padding(8)
        .cardBackground()
    }

    /// Proposition de clôture affichée après l'arrêt du chrono : passer le WP en
    /// « Traité » et le réaffecter à son créateur (voir `TimerManager.pendingCompletion`).
    @State private var applying = false

    @ViewBuilder private var completionCard: some View {
        if let pending = timer.pendingCompletion {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal")
                        .foregroundStyle(Palette.accent)
                    Text("Clôturer #\(pending.wp.id) ?")
                        .font(.callout.weight(.medium))
                }
                Text(completionDetail(pending))
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("Ignorer") { timer.dismissPendingCompletion() }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .disabled(applying)
                    Spacer(minLength: 0)
                    if applying {
                        ProgressView().controlSize(.small)
                    }
                    Button("Confirmer") {
                        Task {
                            applying = true
                            await timer.applyPendingCompletion(using: settings.api)
                            applying = false
                        }
                    }
                    .disabled(applying)
                }
            }
            .padding(12)
            .cardBackground(Palette.cardStrong)
        }
    }

    /// Détaille les actions de la proposition (« → statut … · réaffecter à … »).
    private func completionDetail(_ p: TimerManager.PendingCompletion) -> String {
        var parts: [String] = []
        if p.statusHref != nil { parts.append("statut « \(p.statusName) »") }
        if let name = p.assigneeName { parts.append("réaffecter à \(name)") }
        else if p.assigneeHref != nil { parts.append("réaffecter au créateur") }
        return parts.isEmpty ? "" : "→ " + parts.joined(separator: "  ·  ")
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Rechercher (ID, client, libellé)", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            Button { reload() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help(searchAll ? "Relancer la recherche" : "Recharger mes work packages")
        }
        .padding(8)
        .cardBackground()
    }

    @ViewBuilder private var resultsList: some View {
        if loading {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Chargement…").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 10)
        } else {
            let results = filtered
            if results.isEmpty {
                Text(emptyMessage)
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 10)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(results) { wp in
                            WorkPackageRow(
                                wp: wp,
                                isSelected: selected?.id == wp.id,
                                url: settings.workPackageURL(id: wp.id)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { selected = (selected?.id == wp.id) ? nil : wp }
                        }
                    }
                }
                .frame(height: min(CGFloat(results.count) * 44 + 4, 224))
            }
        }
    }

    @ViewBuilder private var statusLine: some View {
        if let msg = loadError ?? timer.lastError {
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.red)
        }
        if let saved = timer.lastSaved {
            Label(saved, systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        }
    }

    // MARK: - Données

    /// Résultats affichés : en mode élargi, ceux de la recherche serveur ; sinon un
    /// filtre local où chaque terme doit se retrouver dans « <id> <libellé> <client> ».
    private var filtered: [WorkPackage] {
        if searchAll { return remoteResults }
        let terms = query
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .split(separator: " ")
            .map(String.init)
        guard !terms.isEmpty else { return workPackages }
        return workPackages.filter { wp in
            let haystack = "\(wp.id) \(wp.subject) \(wp.projectName ?? "")"
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            return terms.allSatisfy { haystack.contains($0) }
        }
    }

    /// Message affiché quand la liste est vide, selon le mode et l'état de la saisie.
    private var emptyMessage: String {
        let hasQuery = !query.trimmingCharacters(in: .whitespaces).isEmpty
        if searchAll {
            return hasQuery ? "Aucun résultat pour « \(query) »."
                            : "Tape pour rechercher parmi tous les work packages."
        }
        return hasQuery ? "Aucun résultat pour « \(query) »." : "Aucun work package assigné et ouvert."
    }

    /// Recharge : recherche serveur en mode élargi, sinon rechargement de mes WP.
    private func reload() {
        if searchAll { scheduleRemoteSearch(immediate: true) }
        else { Task { await load() } }
    }

    /// Planifie une recherche serveur, avec un léger debounce pour la frappe.
    private func scheduleRemoteSearch(immediate: Bool = false) {
        searchTask?.cancel()
        let q = query
        searchTask = Task {
            if !immediate {
                try? await Task.sleep(nanoseconds: 350_000_000)
                if Task.isCancelled { return }
            }
            await runRemoteSearch(q)
        }
    }

    private func runRemoteSearch(_ q: String) async {
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { remoteResults = []; loading = false; return }
        guard let api = settings.api else {
            loadError = "Token manquant — ouvre les Préférences."
            return
        }
        loading = true
        loadError = nil
        do {
            remoteResults = try await api.searchWorkPackages(matching: trimmed)
        } catch {
            if !Task.isCancelled { loadError = error.localizedDescription }
        }
        loading = false
    }

    private func load() async {
        guard let api = settings.api else {
            loadError = "Token manquant — ouvre les Préférences."
            return
        }
        loading = true
        loadError = nil
        do {
            workPackages = try await api.myWorkPackages()
        } catch {
            loadError = error.localizedDescription
        }
        loading = false
    }

    /// Charge les activités autorisées pour le WP sélectionné et présélectionne
    /// « Développement » si disponible, sinon la première.
    private func loadActivities(for wp: WorkPackage?) async {
        guard let wp, let api = settings.api else {
            activities = []
            selectedActivity = nil
            return
        }
        let list = (try? await api.activities(forWorkPackageHref: wp.href)) ?? []
        activities = list
        selectedActivity = list.first { $0.name.localizedCaseInsensitiveContains("Développement") }
            ?? list.first
    }
}

/// Ligne de résultat de recherche : libellé + ID/client, lien OpenProject, coche si sélectionné.
private struct WorkPackageRow: View {
    let wp: WorkPackage
    let isSelected: Bool
    let url: URL?

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(wp.subject).font(.callout).lineLimit(1)
                HStack(spacing: 5) {
                    Text("#\(wp.id)").monospacedDigit()
                    if let client = wp.projectName, !client.isEmpty {
                        Text("· \(client)").lineLimit(1)
                    }
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if let url { OpenProjectLink(url: url, compact: true) }
            if isSelected {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 6).padding(.horizontal, 8)
        .background(
            isSelected ? Color.accentColor.opacity(0.12) : Palette.card,
            in: RoundedRectangle(cornerRadius: 6)
        )
    }
}
