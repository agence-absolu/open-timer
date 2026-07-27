#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

APP="OpenTimer"
BUNDLE="$APP.app"

echo "▸ Build release…"
swift build -c release

BIN=".build/release/$APP"

echo "▸ Assemblage de ${BUNDLE} ..."
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN" "$BUNDLE/Contents/MacOS/$APP"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
cp Resources/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"

echo "▸ Signature ad-hoc (lancement local)…"
codesign --force --deep --sign - "$BUNDLE"

echo "✓ $BUNDLE prêt."
echo "  Lance-le :   open $BUNDLE"
echo "  Ou installe : cp -R $BUNDLE /Applications/"
