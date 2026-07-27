#!/usr/bin/env bash
# Construit l'app, la zippe pour distribution et calcule le sha256 pour le cask.
set -euo pipefail
cd "$(dirname "$0")"

APP="OpenTimer"
BUNDLE="$APP.app"

# Version lue depuis l'Info.plist (source de vérité).
VERSION="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)"
ZIP="${APP}-${VERSION}.zip"

echo "▸ Build…"
./build.sh >/dev/null

echo "▸ Compression de ${BUNDLE} -> ${ZIP}…"
rm -f "$ZIP"
# ditto préserve la structure du bundle et la signature ad-hoc (mieux que zip).
ditto -c -k --sequesterRsrc --keepParent "$BUNDLE" "$ZIP"

SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"

echo
echo "✓ Artefact : $ZIP  ($(du -h "$ZIP" | cut -f1))"
echo "  version  : $VERSION"
echo "  sha256   : $SHA"
echo
echo "── À reporter dans le cask (Casks/opentimer.rb) ──"
echo "  version \"$VERSION\""
echo "  sha256 \"$SHA\""
echo
echo "Puis : créer une release GitHub taggée v$VERSION et y joindre $ZIP."
