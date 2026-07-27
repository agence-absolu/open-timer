import AppKit
import SwiftUI

/// Panneau déroulant de la barre de menu.
struct MenuContentView: View {
    @EnvironmentObject var timer: TimerManager
    @EnvironmentObject var settings: SettingsStore

    @State private var workPackages: [WorkPackage] = []
    @State private var selected: WorkPackage?
    @State private var query: String = ""
    @State private var comment: String = ""
    @State private var activities: [Activity] = []
    @State private var selectedActivity: Activity?
    @State private var loading = false
    @State private var loadError: String?
    @State private var panel: Panel = .tracker
    @State private var editingEntry: TimeEntry?
    @State private var historyReload = 0
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    private enum Panel { case tracker, history, settings }

    var body: some View {
        panelStack
            .frame(width: 360)
            .task { if !settings.token.isEmpty { await load() } }
    }

    /// Pile principale. L'`.id(screenKey)` force la fenêtre de `MenuBarExtra` à
    /// se redimensionner à chaque changement d'écran : sans lui, sur macOS récents
    /// (Tahoe), la fenêtre conserve la hauteur du plus grand panneau déjà affiché
    /// (Historique/Réglages) et laisse une zone vide ombrée sous le tracker.
    /// Le `.task` de chargement reste attaché au parent, donc non relancé ici.
    private var panelStack: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            mainArea
            Divider()
            footer
        }
        .padding(14)
        .id(screenKey)
    }

    /// Identité de l'écran affiché dans `mainArea`, pour piloter le redimensionnement.
    private var screenKey: String {
        if settings.token.isEmpty || panel == .settings { return "settings" }
        if editingEntry != nil { return "edit" }
        if panel == .history { return "history" }
        if timer.isRunning { return "running" }
        return "tracker"
    }

    // MARK: - Entête

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
                .foregroundStyle(timer.isRunning ? Palette.recording : Color.accentColor)
            Text("OpenTimer").font(.headline)

            if timer.isRunning {
                Text(timer.formattedElapsed)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Palette.recording)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Palette.recording.opacity(0.14), in: Capsule())
            }

            Spacer()

            if !settings.token.isEmpty {
                navButton(icon: "clock.arrow.circlepath", target: .history, help: "Dernières saisies")
            }
            navButton(icon: "gearshape", target: .settings, help: "Réglages")
        }
    }

    private func navButton(icon: String, target: Panel, help: String) -> some View {
        Button {
            editingEntry = nil
            panel = (panel == target) ? .tracker : target
        } label: {
            Image(systemName: icon)
                .foregroundStyle(panel == target ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Zone principale

    @ViewBuilder private var mainArea: some View {
        if settings.token.isEmpty || panel == .settings {
            SettingsView(onSaved: { panel = .tracker; Task { await load() } })
        } else if let entry = editingEntry {
            TimeEntryEditView(entry: entry, api: settings.api) {
                editingEntry = nil
                historyReload += 1
            }
        } else if panel == .history {
            HistoryView(api: settings.api, reloadToken: historyReload) { editingEntry = $0 }
        } else if timer.isRunning {
            runningView
        } else {
            trackerView
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
                }
                Text(timer.activeWP?.subject ?? "—").font(.headline).lineLimit(2)
                if let client = timer.activeWP?.projectName, !client.isEmpty {
                    Text(client).font(.caption).foregroundStyle(.secondary)
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
            searchField
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

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Rechercher (ID, client, libellé)", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Recharger mes work packages")
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
                Text(query.isEmpty ? "Aucun work package assigné et ouvert." : "Aucun résultat pour « \(query) ».")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 10)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(results) { wp in
                            WorkPackageRow(wp: wp, isSelected: selected?.id == wp.id)
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

    // MARK: - Pied

    private var footer: some View {
        HStack {
            Toggle(isOn: $launchAtLogin) {
                Text("Lancer au démarrage").font(.caption)
            }
            .toggleStyle(.checkbox)
            .onChange(of: launchAtLogin) { newValue in
                do { try LaunchAtLogin.set(newValue) }
                catch { launchAtLogin = LaunchAtLogin.isEnabled }
            }
            Spacer()
            Button { NSApplication.shared.terminate(nil) } label: {
                Label("Quitter", systemImage: "power").font(.caption)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
        }
    }

    // MARK: - Données

    /// Filtre local : chaque terme doit se retrouver dans « <id> <libellé> <client> ».
    private var filtered: [WorkPackage] {
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

    private func load() async {
        guard let api = settings.api else {
            loadError = "Token manquant — ouvre les Réglages."
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

/// Ligne de résultat de recherche : libellé + ID/client, coche si sélectionné.
private struct WorkPackageRow: View {
    let wp: WorkPackage
    let isSelected: Bool

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
