# CLAUDE.md — OpenTimer / Windows

Port Windows d'OpenTimer. Lire d'abord le `CLAUDE.md` racine (vue d'ensemble, conventions
communes) puis `macos/CLAUDE.md` : l'app macOS est la **référence fonctionnelle**, ce port
la suit.

## Build & lancement

```powershell
./build.ps1        # dotnet publish -> dist/OpenTimer.exe (exécutable unique autonome)
./dist/OpenTimer.exe
```

- Ouverture dans Visual Studio / Rider : `OpenTimer.sln`.
- **Version courante** : `<Version>` dans `src/OpenTimer.Windows/OpenTimer.Windows.csproj`
  (source de vérité pour la release, pendant du `CFBundleShortVersionString`).
- Pas de suite de tests. La vérification se fait en lançant l'app.
- **Build impossible sur macOS** (pas de targeting pack WindowsDesktop) : sans machine
  Windows, c'est le job `windows` de la CI (`ci.yml`) qui valide la compilation.
- `ImplicitUsings` ne couvre pas `System.Net.Http` pour ce SDK : l'importer explicitement.
  WPF **et** WinForms étant actifs, `MessageBox` est ambigu → écrire
  `System.Windows.MessageBox`.

## Stack

- **.NET 10 (`net10.0-windows`)**, C# `latest`, nullable activé.
- **WPF** pour les fenêtres, **WinForms** (`NotifyIcon`) pour la zone de notification et
  **System.Drawing** pour le rendu de l'icône. Les trois viennent du runtime
  WindowsDesktop : **aucun paquet NuGet**, conformément au « zéro dépendance externe » du projet.
- Publication en `win-x64`, `SelfContained`, `PublishSingleFile` — l'utilisateur n'installe
  aucun runtime. Pas de trimming : WPF ne le supporte pas.

## Architecture

Miroir du découpage macOS. Deux objets partagés créés dans `App.OnStartup` et exposés en
statique (`App.Settings`, `App.Timer`) — pendant de l'injection dans l'environnement SwiftUI.

### Point d'entrée — `App.xaml` / `App.xaml.cs`
`ShutdownMode="OnExplicitShutdown"`, pas de `StartupUri` : l'app vit dans la zone de
notification. `Show<T>` garde **une instance par type de fenêtre** ; la fermeture masque au
lieu de détruire, ce qui préserve la saisie en cours.

### Services — `src/OpenTimer.Windows/Services/`
- **`OpenProjectApi.cs`** : port fidèle de `OpenProjectAPI.swift`. `HttpClient` statique,
  parsing HAL manuel via `JsonDocument` (pas de `Codable`/`JsonSerializer` typé, comme côté
  Swift). Mêmes endpoints, mêmes utilitaires ISO 8601.
- **`TimerManager.cs`** : port de `TimerManager.swift`, modèle **segments cumulés**
  (`_accumulated` + `_segmentStart`) repris tel quel, ticker `DispatcherTimer` à 1 s.
- **`SettingsStore.cs`** : `%APPDATA%\OpenTimer\settings.json`, token chiffré via DPAPI.
- **`Dpapi.cs`** : `CryptProtectData` / `CryptUnprotectData` en P/Invoke direct.
- **`TrayService.cs`** : `NotifyIcon` + menu contextuel, pendant de `MenuBarMenu.swift`.
- **`TrayIconRenderer.cs`** : dessine le chrono **dans** l'icône (voir ci-dessous).
- **`LaunchAtLogin.cs`** : clé de registre `HKCU\…\CurrentVersion\Run`.

### Modèles — `src/OpenTimer.Windows/Models/`
`WorkPackage`, `Activity`, `TimeEntry` — `record` C#, équivalents des `struct` Swift.

### Vues — `src/OpenTimer.Windows/Views/`
`Theme.xaml` (palette, styles), `TrackerWindow`, `HistoryWindow`, `PreferencesWindow`.
Code-behind classique, pas de MVVM formel : les fenêtres sont petites et l'app macOS ne
sépare pas davantage.

## Points d'attention / décisions non évidentes

- **Pas de texte dans la zone de notification.** Contrairement à la barre de menu macOS,
  Windows n'affiche qu'une icône. Le chrono est donc **dessiné dans l'icône** au format
  `H:MM` (les secondes sont illisibles à 16 px), redessiné à chaque changement de **minute** —
  redessiner chaque seconde ferait clignoter la barre des tâches. Le tooltip, lui, porte
  la durée à la seconde et se met à jour à chaque tick.
- **Fuite GDI.** `Bitmap.GetHicon()` et `Icon.FromHandle` produisent des handles non gérés.
  `TrayIconRenderer` détruit le HICON temporaire (`DestroyIcon`) et `TrayService` dispose
  l'icône précédente avant chaque remplacement. Sans ça : un handle fuité par minute.
- **Token chiffré, contrairement à macOS.** Là-bas le trousseau a dû être abandonné parce que
  la signature ad-hoc change à chaque build. DPAPI est lié au **compte Windows**, pas à la
  signature du binaire : le problème ne se pose pas, le token est donc chiffré au repos.
  Ne pas « aligner » sur le stockage en clair de macOS.
- **P/Invoke plutôt que NuGet.** `System.Security.Cryptography.ProtectedData` ferait le même
  travail que `Dpapi.cs`, mais c'est un paquet externe. Le projet tient au zéro dépendance.
- **Barre finale de l'URL.** `SettingsStore.Api` ajoute un `/` final à la base :
  sans lui, `new Uri(base, "api/v3/…")` **remplace** le dernier segment du chemin au lieu de
  s'y ajouter, ce qui casse les instances servies sous un sous-chemin (`/openproject`).
- **Encodage de la query.** `Uri.EscapeDataString` sur chaque paire clé/valeur (espace → `%20`,
  `+` → `%2B`). Ne pas passer par `HttpUtility.ParseQueryString`, qui réintroduit l'encodage
  `+` que OpenProject réinterprète — c'est exactement le bug contourné côté Swift.

## Parité avec macOS — reste à faire

- `HistoryWindow` est en **lecture seule** : l'éditeur Début/Fin → Durée recalculée
  (`TimeEntryEditView`) et la suppression avec confirmation ne sont pas portés.
  `UpdateTimeEntryAsync` / `DeleteTimeEntryAsync` existent déjà côté API.
- **Thème clair/sombre** : `SettingsStore.Appearance` est persisté mais `Theme.xaml` ne
  définit qu'un jeu de couleurs clair.
- **Heures début/fin** (`StartEndSupportedAsync`) : `TimerManager.StopAsync` envoie `startTime`
  à la création, mais l'historique ne les affiche ni ne les édite pas encore. Voir
  `macos/CLAUDE.md` pour les contraintes de l'API (`endTime` non inscriptible).

## Release

1. Bumper `<Version>` dans `src/OpenTimer.Windows/OpenTimer.Windows.csproj`.
2. Commit + push, puis pousser le tag `windows-vX.Y.Z` — le workflow `release.yml` vérifie
   que le tag correspond au csproj, lance `release.ps1` (build + zip) et publie la release.
3. Reporter `version` + `hash` **du zip publié par la CI**
   (`gh release view windows-vX.Y.Z --json assets`) dans `../bucket/opentimer.json`
   (bucket Scoop, à la racine du dépôt — Scoop impose ce chemin, comme Homebrew impose
   `Casks/`), puis commit + push. Pas le hash d'un `release.ps1` local : la CI recompile,
   les deux zips diffèrent (même piège que le cask, voir `../DEPLOY.md`).

Côté utilisateur : `scoop bucket add open-timer https://github.com/agence-absolu/open-timer`
puis `scoop install opentimer`. Scoop n'exige pas de signature — c'est le pendant naturel du
tap Homebrew. WinGet viendrait après (soumission validée, exigences plus strictes).

L'exécutable n'étant **pas signé**, SmartScreen avertit au premier lancement. Un certificat
de signature de code (OV ~200-400 $/an, EV ~400-600 $/an) est le seul vrai remède —
même arbitrage que la notarisation côté macOS.
