#!/bin/bash
# Packs Cermin.app into build/Cermin-<version>.dmg (drag to Applications) for public download.
#   CERMIN_SIGN_IDENTITY="Apple Development: …" ./scripts/dmg.sh
# Not notarized: Gatekeeper blocks the first launch; Resources/Install.txt (in the DMG) explains "Open Anyway".
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build.sh
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
STAGE="$(mktemp -d)/Cermin"
mkdir -p "$STAGE"
cp -R build/Cermin.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp Resources/Install.txt "$STAGE/Read me - Baca dulu.txt"

DMG="build/Cermin-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -quiet -volname "Cermin $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
if [[ -n "${CERMIN_SIGN_IDENTITY:-}" ]]; then codesign --sign "$CERMIN_SIGN_IDENTITY" --timestamp=none "$DMG"; fi
rm -rf "$(dirname "$STAGE")"
echo "✓ $DMG ($(du -h "$DMG" | cut -f1))"
