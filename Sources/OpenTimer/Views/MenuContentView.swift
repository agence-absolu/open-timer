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
    @State private var loading = false
    @State private var loadError: String?
    @State private var panel: Panel = .tracker
    @State private var editingEntry: TimeEntry?
    @State private var historyReload = 0
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    private enum Panel { case tracker, history, settings }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            mainArea
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 360)
        .task { if !settings.token.isEmpty { await load() } }
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
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(Palette.recording).frame(width: 8, height: 8)
                    Text("En cours").font(.caption.weight(.medium)).foregroundStyle(Palette.recording)
                }
                Text(timer.activeWP?.subject ?? "—").font(.headline).lineLimit(2)
                if let client = timer.activeWP?.projectName, !client.isEmpty {
                    Text(client).font(.caption).foregroundStyle(.secondary)
                }
                Text(timer.formattedElapsed)
                    .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .cardBackground(Palette.recording.opacity(0.09), radius: 12)

            Button {
                let c = comment
                Task { await timer.stop(using: settings.api, comment: c); comment = "" }
            } label: {
                Label("Arrêter & enregistrer", systemImage: "stop.fill")
            }
            .buttonStyle(PrimaryButtonStyle(tint: Palette.recording))

            statusLine
        }
    }

    // MARK: - État « tracker » (recherche + démarrage)

    private var trackerView: some View {
        VStack(alignment: .leading, spacing: 10) {
            searchField
            resultsList

            if let wp = selected {
                selectedBanner(wp)
            }

            TextField("Commentaire (optionnel)", text: $comment)
                .textFieldStyle(.roundedBorder)

            Button {
                if let wp = selected { timer.start(wp) }
            } label: {
                Label("Démarrer", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(selected == nil)

            statusLine
        }
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

    private func selectedBanner(_ wp: WorkPackage) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(wp.subject).font(.callout).lineLimit(1)
                if let client = wp.projectName, !client.isEmpty {
                    Text(client).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Text("#\(wp.id)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(8)
        .cardBackground(Color.accentColor.opacity(0.10))
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
