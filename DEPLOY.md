# Déploiement Homebrew (macOS)

Le dépôt public **`agence-absolu/open-timer`** sert à la fois de code source, de
tap Homebrew (dossier `Casks/`, à la racine — contrainte Homebrew) et d'hôte des
artefacts (GitHub Releases).

> Pour la distribution Windows, voir `windows/CLAUDE.md` (tags `windows-vX.Y.Z`,
> artefact zip, manifeste Scoop). Les versions des deux plateformes sont découplées.

## À chaque version

> ⚠️ **Le sha256 du cask doit être celui du zip publié par la CI**, pas celui d'un zip
> construit en local : le workflow recompile l'app, et deux builds (signature ad-hoc,
> horodatages) ne donnent jamais le même zip. Un sha256 local ferait échouer
> `brew upgrade` sur une erreur de checksum. D'où les deux commits ci-dessous.

1. **Bumper la version** dans `macos/Resources/Info.plist` :
   `CFBundleShortVersionString` (ex. `0.7.0` → `0.7.1`) et `CFBundleVersion` (+1).
   ```bash
   cd macos
   /usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString X.Y.Z" -c "Set CFBundleVersion N" Resources/Info.plist
   ./build.sh    # vérifie que ça compile
   ```

2. **Commit + push du code, puis du tag** — le cask n'est **pas** encore touché :
   ```bash
   git commit -m "vX.Y.Z — description courte" && git push
   git tag vX.Y.Z && git push origin vX.Y.Z
   ```
   Le workflow `.github/workflows/release.yml` exécute `macos/release.sh`, vérifie que le
   tag correspond à l'`Info.plist` et publie la release avec `OpenTimer-X.Y.Z.zip`.
   Suivi : `gh run list --workflow release.yml`.

3. **Récupérer le sha256 du zip publié** :
   ```bash
   gh release view vX.Y.Z --json assets --jq '.assets[] | "\(.name) \(.digest)"'
   ```

4. **Reporter `version` + `sha256`** dans `Casks/opentimer.rb`, puis commit + push
   (`Cask opentimer X.Y.Z`). C'est ce commit qui rend la version visible pour
   `brew upgrade`.

L'URL du zip dans le cask doit correspondre :
`https://github.com/agence-absolu/open-timer/releases/download/vX.Y.Z/OpenTimer-X.Y.Z.zip`

`macos/release.sh` reste utilisable en local pour tester l'empaquetage ; le sha256 qu'il
affiche ne doit simplement pas finir dans le cask.

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
