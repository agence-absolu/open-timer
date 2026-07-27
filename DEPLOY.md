# Déploiement Homebrew

Le dépôt public **`agence-absolu/open-timer`** sert à la fois de code source, de
tap Homebrew (dossier `Casks/`) et d'hôte des artefacts (GitHub Releases).

## À chaque version

1. **Bumper la version** dans `Resources/Info.plist`
   (`CFBundleShortVersionString`, ex. `0.1.0` → `0.2.0`).

2. **Construire l'artefact + sha256** :
   ```bash
   ./release.sh
   ```
   Note la `version` et le `sha256` affichés, et le fichier `OpenTimer-<version>.zip`.

3. **Reporter version + sha256** dans `Casks/opentimer.rb`.

4. **Commit + push** du code et du cask :
   ```bash
   git add -A && git commit -m "Release vX.Y.Z" && git push
   ```

5. **Créer la release GitHub** taggée `vX.Y.Z` et y joindre le zip :
   - Via l'interface : Releases → Draft a new release → tag `vX.Y.Z` →
     glisser `OpenTimer-<version>.zip` → Publish.
   - (ou en CLI si tu installes `gh` :
     `gh release create vX.Y.Z OpenTimer-<version>.zip -t "vX.Y.Z"`)

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
- Le zip est régénéré par `release.sh` avec `ditto` (préserve la signature ad-hoc).
