# Déploiement Homebrew (macOS)

Le dépôt public **`agence-absolu/open-timer`** sert à la fois de code source, de
tap Homebrew (dossier `Casks/`, à la racine — contrainte Homebrew) et d'hôte des
artefacts (GitHub Releases).

> Pour la distribution Windows, voir `windows/CLAUDE.md` (tags `windows-vX.Y.Z`,
> artefact zip, manifeste Scoop). Les versions des deux plateformes sont découplées.

## À chaque version

1. **Bumper la version** dans `macos/Resources/Info.plist`
   (`CFBundleShortVersionString`, ex. `0.1.0` → `0.2.0`).

2. **Construire l'artefact + sha256** :
   ```bash
   cd macos && ./release.sh
   ```
   Note la `version` et le `sha256` affichés, et le fichier `OpenTimer-<version>.zip`.

3. **Reporter version + sha256** dans `Casks/opentimer.rb`.

4. **Commit + push** du code et du cask :
   ```bash
   git add -A && git commit -m "Release vX.Y.Z" && git push
   ```

5. **Pousser le tag `vX.Y.Z`** — le workflow `.github/workflows/release.yml` vérifie
   que le tag correspond à l'`Info.plist`, rebuild et publie la release avec le zip :
   ```bash
   git tag vX.Y.Z && git push origin vX.Y.Z
   ```
   (Manuellement si besoin : Releases → Draft a new release → tag `vX.Y.Z` →
   glisser `OpenTimer-<version>.zip` → Publish.)

L'URL du zip dans le cask doit correspondre :
`https://github.com/agence-absolu/open-timer/releases/download/vX.Y.Z/OpenTimer-X.Y.Z.zip`

## Installation (côté utilisateurs)

```bash
# 1) Ajouter le tap (repo à nom libre → on donne l'URL explicite, une seule fois)
brew tap agence-absolu/open-timer https://github.com/agence-absolu/open-timer

# 2) Installer
brew install --cask opentimer
```

L'app étant non signée, le cask retire lui-même la quarantaine (stanza
`postflight`). Le flag `--no-quarantine` n'existe plus depuis Homebrew 4.7.

Lancer ensuite **OpenTimer** (barre de menu). Config : coller l'URL de l'instance
OpenProject et un token API.

## Mise à jour (côté utilisateurs)

```bash
brew update
brew upgrade --cask opentimer     # récupère la nouvelle version
```

## Notes

- **App non signée** : le cask retire la quarantaine via `postflight` (le flag
  `--no-quarantine` a été supprimé de Homebrew en 4.7). Pour supprimer ce bricolage
  à terme : signer avec un Apple Developer ID (99 $/an) puis notariser — le
  `postflight` deviendra alors inutile.
- Le zip est régénéré par `macos/release.sh` avec `ditto` (préserve la signature ad-hoc).
