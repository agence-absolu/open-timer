# OpenTimer

Petit time tracker macOS pour **OpenProject**, qui vit dans la barre de menu.
Choisis un work package parmi ceux qui te sont assignés, lance le chrono (le temps
défile directement dans la barre de menu), et à l'arrêt un *time entry* est créé
automatiquement dans OpenProject via l'API REST v3.

- App **menu-bar-only** (pas d'icône dans le Dock).
- Token stocké dans le **trousseau macOS**.
- Zéro dépendance externe, binaire natif ~quelques Mo.

## Prérequis

- macOS 13+
- Swift toolchain (Command Line Tools suffisent : `xcode-select --install`)

## Build

```bash
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
2. Lance OpenTimer, ouvre les **Réglages** (icône engrenage).
3. Saisis l'URL de ton instance (`https://…openproject.com`), colle le token,
   clique **Tester** — tu dois voir ton nom — puis **Enregistrer**.

## Utilisation

1. Choisis un work package dans la liste (tes WP assignés, statut ouvert).
2. **Démarrer** → le chrono défile dans la barre de menu (`▶ 0:01:23`).
3. **Arrêter & enregistrer** → time entry créé sur le WP (durée arrondie à la
   minute, activité = première autorisée, date du jour).

## Corriger une saisie (oubli d'arrêt)

Icône **horloge** dans l'entête → **Dernières saisies**. Clique une saisie pour
l'éditer : **Début** et **Fin** ajustables, la **Durée se recalcule** (Fin − Début).
Pratique quand on a oublié d'arrêter : on corrige la Fin, la durée suit.

> Les heures de début/fin ne sont écrites dans OpenProject que si l'admin a activé
> l'option *« heures de début et de fin »* (Administration → Suivi du temps). Sinon,
> seules la **durée** et la **date** sont enregistrées (l'app te le signale).

## Installer dans /Applications

```bash
cp -R OpenTimer.app /Applications/
```

## Pistes suivantes

- Notarisation Developer ID + **cask Homebrew** publié (nécessite un compte Apple
  Developer, 99 $/an).
- Choix de l'activité, édition/suppression de time entries, reprise après crash,
  raccourci clavier global, lancement au démarrage.
