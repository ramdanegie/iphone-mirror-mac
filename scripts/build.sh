#!/bin/bash
# Builds build/Cermin.app (SwiftPM + ad-hoc signature). Works with Command Line Tools only; Xcode not required.
#   ./scripts/build.sh          release build
#   ./scripts/build.sh --run    build, then open the app
#   ./scripts/build.sh --test   run unit tests first
set -euo pipefail
cd "$(dirname "$0")/.."

# --disable-sandbox: SwiftPM's macro-plugin sandbox fails when nested in another sandbox (CI, agents)
if [[ " $* " == *" --test "* ]]; then swift test --disable-sandbox; ./scripts/check-strings.sh; fi

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Cermin"
APP=build/Cermin.app

if [[ ! -f build/AppIcon.icns || scripts/make-icon.swift -nt build/AppIcon.icns ]]; then
    rm -rf build/AppIcon.iconset
    swift scripts/make-icon.swift build/AppIcon.iconset
    iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Cermin"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/*.lproj "$APP/Contents/Resources/"   # English + Indonesian
# The UxPlay installer (a script, not UxPlay itself) ships in the app for DMG users.
install -m 0755 scripts/install-uxplay.sh "$APP/Contents/Resources/install-uxplay.sh"
# Ad-hoc by default: macOS asks for Camera permission again after each rebuild.
# CERMIN_SIGN_IDENTITY="Apple Development: …" signs with a certificate so permissions survive updates.
codesign --force --sign "${CERMIN_SIGN_IDENTITY:--}" --timestamp=none --options runtime --entitlements Resources/Cermin.entitlements "$APP"
echo "Built $APP"

if [[ " $* " == *" --run "* ]]; then open "$APP"; fi
