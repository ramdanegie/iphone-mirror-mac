#!/bin/bash
# Builds UxPlay (GPL-3.0, https://github.com/FDH2/UxPlay) for Cermin's wireless (AirPlay) mode.
# Installs to ~/Library/Application Support/Cermin/bin/uxplay — Cermin looks there first.
#   ./scripts/install-uxplay.sh                    stable v1.73.7
#   UXPLAY_VERSION=master ./scripts/install-uxplay.sh   development build (needed for the experimental P2P mode)
set -euo pipefail

VERSION="${UXPLAY_VERSION:-v1.73.7}"
DEST="$HOME/Library/Application Support/Cermin/bin"

if ! command -v brew >/dev/null; then
    echo "Homebrew dibutuhkan: https://brew.sh" >&2
    exit 1
fi

echo "==> Memasang dependensi (cmake, pkgconf, libplist, openssl@3, gstreamer)…"
# Don't let this script upgrade unrelated packages.
HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1 \
    brew install cmake pkgconf libplist openssl@3 gstreamer

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Mengunduh UxPlay ${VERSION}…"
git clone --depth 1 --branch "$VERSION" https://github.com/FDH2/UxPlay "$WORK/UxPlay"

echo "==> Build…"
export PKG_CONFIG_PATH="$(brew --prefix openssl@3)/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
cmake -S "$WORK/UxPlay" -B "$WORK/build" -DCMAKE_BUILD_TYPE=Release
cmake --build "$WORK/build" -j "$(sysctl -n hw.ncpu)"

mkdir -p "$DEST"
cp "$WORK/build/uxplay" "$DEST/uxplay"
echo "==> Selesai: $DEST/uxplay"
"$DEST/uxplay" -v 2>/dev/null | head -1 || true
echo "Buka Cermin → Pengaturan → Wireless → Aktifkan wireless."
