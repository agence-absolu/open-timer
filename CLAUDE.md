# CLAUDE.md — OpenTimer

Guide de référence pour travailler dans ce dépôt. Décrit ce qu'est l'app, l'organisation
du monorepo, et les conventions communes aux deux plateformes.

**Ce fichier ne couvre pas le détail d'une plateforme.** Avant de toucher au code, lire
aussi le `CLAUDE.md` du dossier concerné :

| Plateforme | Dossier | Stack |
|---|---|---|
| macOS (référence) | [`macos/`](macos/CLAUDE.md) | Swift + SwiftUI + AppKit, SwiftPM |
| Windows | [`windows/`](windows/CLAUDE.md) | C# / .NET 10 + WPF + WinForms (tray) |

## Vue d'ensemble

**OpenTimer** est un time tracker natif pour **OpenProject**. Il vit dans la barre de menu
(macOS) ou la zone de notification (Windows) : on choisit un work package, on lance le
chrono, et à l'arrêt un *time entry* est créé automatiquement dans OpenProject via l'API
REST v3.

- **Bundle id / produit** : `com.lmwr.opentimer`.
- **Langue** : interface et commentaires du code en **français** (accents inclus).
- **macOS est la référence fonctionnelle.** Une fonctionnalité se conçoit et se valide
  d'abord côté macOS ; le port Windows la suit. En cas de divergence de comportement non
  documentée, macOS fait foi.

> Note : le `README.md` décrit encore l'app comme « menu-bar-only, token dans le
> trousseau » — c'est obsolète. Ces `CLAUDE.md` font foi sur l'état actuel.

## Organisation du dépôt

```
.
├── macos/            app Swift : Package.swift, Sources/, Resources/, build.sh, release.sh
├── windows/          app C# : OpenTimer.sln, src/, build.ps1, release.ps1
├── Casks/            tap Homebrew (macOS) — doit rester à la racine (contrainte Homebrew)
├── bucket/           bucket Scoop (Windows) — même contrainte de chemin côté Scoop
├── .github/workflows/  ci.yml (build des deux plateformes) + release.yml (tags)
├── DEPLOY.md         distribution macOS détaillée
└── CLAUDE.md         ce fichier
```

Le dépôt public **`agence-absolu/open-timer`** est à la fois code source, tap Homebrew et
hôte des artefacts (GitHub Releases).

## Le contrat partagé, c'est l'API — pas le code

Les deux apps ne partagent **aucune ligne de code**. SwiftUI et AppKit n'existent pas sur
Windows, et mutualiser les ~400 lignes de client HTTP coûterait plus cher en plomberie
(toolchain Swift sur Windows, interop C#, CI) que de maintenir deux ports.

Ce qui est partagé, c'est la **surface d'API OpenProject** : mêmes endpoints, mêmes filtres,
mêmes utilitaires ISO 8601. `windows/…/Services/OpenProjectApi.cs` est un port fidèle de
`macos/…/Services/OpenProjectAPI.swift`, méthode par méthode.

**Toute évolution du client API doit être répercutée des deux côtés**, en gardant les noms
alignés (`myWorkPackages` ↔ `MyWorkPackagesAsync`). Idem pour `TimerManager`, dont le modèle
« segments cumulés » est identique.

## Versions et releases

Les versions sont **découplées par plateforme** — forcer la parité bloquerait dès la
première divergence de fonctionnalités.

| Plateforme | Source de vérité de la version | Tag |
|---|---|---|
| macOS | `macos/Resources/Info.plist` (`CFBundleShortVersionString`) | `vX.Y.Z` |
| Windows | `windows/src/OpenTimer.Windows/OpenTimer.Windows.csproj` (`<Version>`) | `windows-vX.Y.Z` |

`.github/workflows/release.yml` vérifie que le tag correspond à la version déclarée, rebuild
et publie la release. Le détail de chaque procédure est dans le `CLAUDE.md` de la plateforme.

**Aucune des deux apps n'est signée** : macOS contourne la quarantaine via un `postflight`
de cask, Windows affiche un avertissement SmartScreen. C'est un arbitrage assumé
(certificat Apple 99 $/an, certificat de signature de code Windows 200-600 $/an).

## Conventions

- Français partout (UI, commentaires, messages), accents corrects obligatoires.
- **Zéro dépendance externe** : rester sur les frameworks système — Foundation, SwiftUI,
  AppKit, Security, ServiceManagement côté macOS ; WPF, WinForms, System.Drawing et P/Invoke
  côté Windows (aucun paquet NuGet).
- Parsing API en HAL manuel (`JSONSerialization` / `JsonDocument`) — pas de décodage typé.
- Messages de commit : `vX.Y.Z — description courte en français` pour une release,
  description courte en français sinon.
