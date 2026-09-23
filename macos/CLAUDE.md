# CLAUDE.md — OpenTimer / macOS

App macOS native, **référence fonctionnelle** du projet : le port Windows
(`windows/`) la suit. Lire d'abord le `CLAUDE.md` racine.

## Build & lancement

```bash
./build.sh        # swift build -c release + assemble OpenTimer.app + signature ad-hoc
open OpenTimer.app
```

- `Package.swift` : cible exécutable unique `OpenTimer`, sources dans `Sources/OpenTimer`.
- `build.sh` compile en release, assemble le bundle `.app` (copie binaire, `Info.plist`,
  les deux `.icns`) puis **signe en ad-hoc** (`codesign --sign -`) pour un lancement local.
- **Version courante** : `Resources/Info.plist` (`CFBundleShortVersionString`, source de
  vérité pour la release).
- Cible macOS 13+ (`.macOS(.v13)`). Pas de suite de tests : la vérification se fait en
  lançant l'app.

## Présence

App à la fois dans la **barre de menu** (`MenuBarExtra`) et dans le **Dock**
(`LSUIElement = false`). L'icône du Dock est alternée quand le chrono tourne.

## Architecture

Découpage classique Models / Services / Views, avec deux `ObservableObject` injectés
dans l'environnement SwiftUI (`TimerManager`, `SettingsStore`).

### Point d'entrée — `Sources/OpenTimer/OpenTimerApp.swift`
- `@main struct OpenTimerApp: App` : déclare un `MenuBarExtra` (style `.menu`) et trois
  fenêtres flottantes (`Window`) identifiées par `WindowID` : `new`, `history`, `preferences`.
- `AppDelegate` (via `NSApplicationDelegateAdaptor`) gère le **clic sur l'icône du Dock**
  (`applicationShouldHandleReopen`) pour rouvrir la fenêtre « Nouveau ».
- `MenuBarLabel` : affiche le chrono qui défile (`● H:MM:SS` / `⏸ …`) ou l'icône `timer`.

### Services — `Sources/OpenTimer/Services/`
- **`TimerManager.swift`** (`@MainActor ObservableObject`) : pilote le chrono. Gère
  démarrage/pause/reprise/arrêt via un modèle **segments cumulés** (`accumulated` +
  `segmentStart`), un ticker `Timer.publish` à 1 s, l'écriture du time entry à l'arrêt,
  et l'alternance de l'icône du Dock (`OpenTimerRunning.icns` quand actif). Contient les
  formatteurs de durée statiques `format` (H:MM:SS) et `formatHM` (H:MM arrondi minute).
- **`OpenProjectAPI.swift`** : client REST v3 minimal, **sans dépendance** (URLSession +
  `JSONSerialization`, parsing HAL manuel). Auth par token : `Basic base64("apikey:<token>")`.
  Endpoints : `currentUser` (test de connexion), `myWorkPackages` (assignés + statut ouvert),
  `searchWorkPackages(matching:)` (recherche serveur tous WP ouverts : filtre plein-texte `**`,
  ou filtre `id`/`=` si la saisie est numérique), `activities(forWorkPackageHref:)`,
  `createTimeEntry`, `recentTimeEntries`, `updateTimeEntry`, `deleteTimeEntry`,
  `startEndSupported` (détecte l'option admin heures début/fin). `myWorkPackages` et
  `searchWorkPackages` partagent le helper privé `fetchWorkPackages(filters:pageSize:)`. Utilitaires
  ISO 8601 : `isoDuration` (arrondi minute, min 1 min), `isoDurationPrecise`, `seconds(fromISODuration:)`,
  `parseUTC` / `utcString`.
- **`SettingsStore.swift`** (`@MainActor ObservableObject`) : détient `baseURL`, `token`,
  `appearance` (thème), les persiste dans `UserDefaults`, fabrique le client `api`
  (nil si URL/token invalides), et calcule l'URL web d'un WP (`BASE_URL/wp/{id}`).
- **`KeychainStore.swift`** : accès trousseau (`kSecClassGenericPassword`, service
  `com.lmwr.opentimer`). **N'est plus utilisé que pour migrer** un ancien token (voir ci-dessous).
- **`LaunchAtLogin.swift`** : lancement au démarrage via `SMAppService.mainApp` (macOS 13+).
- **`Formatters.swift`** : `Formatters.ymd`, format `yyyy-MM-dd` (locale POSIX) pour OpenProject.

### Modèles — `Sources/OpenTimer/Models/`
- **`WorkPackage`** : `id`, `subject`, `projectName?`. `href` = `/api/v3/work_packages/{id}`.
- **`Activity`** : `href`, `name` (activité de temps autorisée : Développement, Réunion…).
- **`TimeEntry`** : saisie existante (durée en `seconds` parsés depuis l'ISO `hours`,
  `startTime`/`endTime` UTC optionnels, `lockVersion` pour le PATCH optimiste).

### Vues — `Sources/OpenTimer/Views/`
- **`MenuBarMenu.swift`** : menu natif de la barre (Nouveau / Historique / Préférences /
  Quitter), + ligne d'état cliquable quand le chrono tourne.
- **`TrackerView.swift`** : fenêtre « Nouveau ». Trois états : connexion manquante /
  session en cours (chrono, pause, arrêt) / recherche+démarrage (liste des WP, choix de
  l'activité, commentaire). Case **« Tous les work packages »** : off = filtre local sur
  mes WP ; on = recherche serveur (`searchWorkPackages`) avec debounce 350 ms.
- **`HistoryView.swift`** : fenêtre « Historique ». Liste des dernières saisies +
  `TimeEntryEditView` (éditeur Début/Fin → Durée recalculée, corrige un oubli d'arrêt ;
  suppression avec confirmation).
- **`PreferencesView.swift`** : connexion (`SettingsView`) + lancement au démarrage + thème.
- **`SettingsView.swift`** : URL + token + bouton « Tester » (affiche le nom de l'utilisateur).
- **`Components.swift`** : `Palette` (couleurs, dont `recording` rouge), `SectionLabel`,
  `PrimaryButtonStyle`, `OpenProjectLink`, helpers `windowSurface()` / `cardBackground()`.

## Points d'attention / décisions non évidentes

- **Stockage du token = `UserDefaults`, pas le trousseau.** L'app est signée ad-hoc :
  sa signature change à chaque build, ce qui faisait perdre l'accès à l'entrée trousseau
  après mise à jour. `KeychainStore` ne sert plus qu'à **migrer une fois** un token
  legacy vers `UserDefaults` (voir `SettingsStore.init`). Ne pas « rétablir » le trousseau
  sans régler d'abord la signature (Developer ID). Le port Windows **ne partage pas** cette
  contrainte et chiffre son token (DPAPI) : ne pas l'aligner sur macOS.
- **Encodage des filtres API** : `URLComponents` encode l'espace en `+`, or OpenProject
  veut `%2B` — on remplace manuellement dans `percentEncodedQuery` (voir `myWorkPackages`
  et `recentTimeEntries`). Ne pas retirer ce remplacement.
- **Activité requise** : OpenProject exige une activité pour un time entry. Au démarrage
  on prend celle choisie ; sinon la première autorisée. `TrackerView` présélectionne
  « Développement » si disponible.
- **Heures début/fin** : écrites seulement si l'instance active l'option admin
  (`startEndSupported`). Sinon seules durée + date sont envoyées, et l'UI le signale.
  Seul `startTime` est accepté en écriture : OpenProject calcule `endTime` (= début + `hours`)
  et répond 500 si on l'envoie. Les secondes sont tronquées et la date locale de `startTime`
  doit égaler `spentOn`. À l'arrêt du chrono, le début envoyé = arrêt − durée (pauses non
  représentées). Sans heures côté serveur, l'éditeur reconstitue la fin depuis `createdAt`.
- **Concurrence** : `TimerManager` et `SettingsStore` sont `@MainActor` ; les formatteurs
  statiques sont `nonisolated`.

## Release / distribution (Homebrew)

Le dépôt public **`agence-absolu/open-timer`** est à la fois code source, tap Homebrew
(`Casks/opentimer.rb`, **à la racine du dépôt** — Homebrew impose ce chemin) et hôte des
artefacts (GitHub Releases). Détails dans `../DEPLOY.md`.

À chaque version :
1. Bumper `CFBundleShortVersionString` (et `CFBundleVersion`) dans `Resources/Info.plist`.
2. `./release.sh` → build + zip (`ditto`, préserve la signature ad-hoc) + `sha256`.
3. Reporter `version` + `sha256` dans `../Casks/opentimer.rb`.
4. Commit + push, puis pousser le tag `vX.Y.Z` (le workflow `release.yml` vérifie la
   cohérence tag ↔ Info.plist, rebuild et publie la release).

Côté utilisateur : `brew tap agence-absolu/open-timer <url>` puis `brew install --cask opentimer`.
L'app étant **non signée / non notarisée**, le cask retire la quarantaine via un
`postflight` (`xattr -dr com.apple.quarantine`) — le flag `--no-quarantine` a disparu en
Homebrew 4.7. Mise à jour : `brew update && brew upgrade --cask opentimer` (le `brew update`
est obligatoire).

> Piste pour supprimer ce bricolage : signer avec un Apple Developer ID (99 $/an) puis
> notariser → le `postflight` et le stockage `UserDefaults` du token pourraient être revus.
