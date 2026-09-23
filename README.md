# OpenTimer

Petit time tracker pour **OpenProject**, qui vit dans la barre de menu (macOS) ou la
zone de notification (Windows). Choisis un work package parmi ceux qui te sont assignés,
lance le chrono, et à l'arrêt un *time entry* est créé automatiquement dans OpenProject
via l'API REST v3.

Deux apps natives, une par plateforme — `macos/` (Swift + SwiftUI) et `windows/`
(C# + WPF). Le reste de ce README décrit la version macOS, qui est la référence
fonctionnelle ; pour Windows, voir [`windows/README.md`](windows/README.md).

- Vit dans la **barre de menu** (le chrono y défile) et dispose d'une **icône dans le
  Dock** (alternée quand une session tourne).
- Token stocké dans les **préférences de l'app** (`UserDefaults`) — l'app étant signée
  ad-hoc, sa signature change à chaque build, ce qui rendait le trousseau peu fiable.
- Zéro dépendance externe, binaire natif ~quelques Mo.

## Prérequis

- macOS 13+
- Swift toolchain (Command Line Tools suffisent : `xcode-select --install`)

## Build

```bash
cd macos
./build.sh
open OpenTimer.app
```

Le script compile en release (`swift build -c release`), assemble `OpenTimer.app`
et le signe en ad-hoc pour un lancement local.

> App **non signée avec un Developer ID** : au premier lancement, macOS peut
> bloquer. Fais **clic-droit → Ouvrir** (une seule fois), ou
> Réglages Système → Confidentialité et sécurité → « Ouvrir quand même ».

## Configuration

1. Dans OpenProject : **Mon compte → Jetons d'accès → API** → crée un token.
2. Lance OpenTimer, clique l'icône de la barre de menu → **Préférences…**.
3. Saisis l'URL de ton instance (`https://…openproject.com`), colle le token,
   clique **Tester** — tu dois voir ton nom — puis **Enregistrer**.

Les **Préférences** permettent aussi de choisir le **thème** (Système / Clair / Sombre)
et d'activer le **lancement au démarrage** de la session.

## Utilisation

1. Icône de la barre de menu → **Nouveau** (ou clic sur l'icône du Dock).
2. Choisis un work package dans la liste (tes WP assignés, statut ouvert), une
   **activité** (« Développement » présélectionnée si dispo) et un commentaire optionnel.
   Coche **Tous les work packages** pour élargir la recherche à ceux assignés à
   d'autres (recherche serveur : libellé, ou id exact si tu tapes un numéro).
3. **Démarrer** → le chrono défile dans la barre de menu (`● 0:01:23`). Tu peux
   **mettre en pause / reprendre** ; l'icône du Dock indique la session active.
4. **Arrêter** → time entry créé sur le WP (durée arrondie à la minute). Si l'instance
   autorise les heures de début/fin, la saisie est horodatée : elle se termine à l'arrêt
   et commence « arrêt − durée » (les pauses ne sont pas représentées).
5. L'app propose ensuite de **clôturer le WP** : statut « Traité » et réaffectation à
   son créateur (facultatif).

## Corriger une saisie (oubli d'arrêt)

Icône de la barre de menu → **Historique**. Clique une saisie pour l'éditer :
**Début** et **Fin** ajustables, la **Durée se recalcule** (Fin − Début). Pratique
quand on a oublié d'arrêter : on corrige la Fin, la durée suit. On peut aussi
**supprimer** une saisie.

> Les heures de début/fin ne sont enregistrées dans OpenProject que si un admin a
> activé le **suivi exact du temps** (*Administration → Temps et coûts*, option
> « Autoriser le suivi exact du temps »). Sinon, seules la **durée** et la **date** sont
> enregistrées (l'app te le signale) : l'éditeur reconstitue alors la fin à partir de
> l'heure de création de la saisie, qui correspond à l'arrêt du chrono.

## Installer

### Via Homebrew (recommandé)

```bash
brew tap agence-absolu/open-timer https://github.com/agence-absolu/open-timer
brew install --cask opentimer
```

Mise à jour : `brew update && brew upgrade --cask opentimer`. Voir `DEPLOY.md` pour le
processus de release. L'app étant non signée, le cask retire lui-même la quarantaine.

### Manuellement

```bash
cp -R macos/OpenTimer.app /Applications/
```

## Développement

Pas de hot reload ni de suite de tests : on recompile, on relance, on vérifie dans l'app
contre une vraie instance OpenProject (sur des WP de test — les saisies sont réelles).

```bash
cd macos
./build.sh && open OpenTimer.app      # quitter l'instance précédente avant (menu → Quitter)
```

- **Cohabitation avec la version Homebrew** : pas besoin de la désinstaller. Les deux
  partagent les mêmes préférences (URL, token) ; quitte l'une avant de lancer l'autre et
  lance le build de dev par son chemin (`open macos/OpenTimer.app`).
- **CI** : chaque push compile macOS et/ou Windows selon les fichiers modifiés. Le port
  Windows ne se compile pas sur macOS : la CI fait foi.
- Architecture, conventions et pièges : [`CLAUDE.md`](CLAUDE.md), puis
  [`macos/CLAUDE.md`](macos/CLAUDE.md) / [`windows/CLAUDE.md`](windows/CLAUDE.md).
- Publier une version : [`DEPLOY.md`](DEPLOY.md).

## Pistes suivantes

- Notarisation **Developer ID** (nécessite un compte Apple Developer, 99 $/an) : lèverait
  le blocage au premier lancement, le `postflight` du cask et permettrait de revenir au
  trousseau pour le token.
- Reprise du chrono après crash, raccourci clavier global.
