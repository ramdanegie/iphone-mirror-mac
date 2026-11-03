#!/bin/bash
# Builds build/Cermin.app (SwiftPM + ad-hoc signature). Works with Command Line Tools only; Xcode not required.
#   ./scripts/build.sh          release build
#   ./scripts/build.sh --run    build, then open the app
#   ./scripts/build.sh --test   run unit tests first
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ " $* " == *" --test "* ]]; then swift test; fi

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
# Ad-hoc signature: macOS will ask for Camera permission again after each rebuild.
codesign --force --sign - --options runtime --entitlements Resources/Cermin.entitlements "$APP"
echo "Built $APP"

if [[ " $* " == *" --run "* ]]; then open "$APP"; fi
