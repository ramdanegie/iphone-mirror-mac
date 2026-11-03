#!/bin/bash
# Builds UxPlay (GPL-3.0, https://github.com/FDH2/UxPlay) for Cermin's wireless (AirPlay) mode.
# Installs to ~/Library/Application Support/Cermin/bin/uxplay — Cermin looks there first.
#   ./scripts/install-uxplay.sh                       pinned, tested commit (default)
#   UXPLAY_VERSION=<tag|branch|sha> ./scripts/install-uxplay.sh
#
# Why not the v1.73.7 release: its PIN pairing rejects iOS 27's 20-byte SRP proof
# ("Client Authentication Failure (client_proof_len 20 invalid)"), so iOS asks for the code forever.
# Fixed upstream in 60e6430 (Oct 2026); 534e2cc also has the pairing fixes after it and the
# 4-field trusted-device register format Cermin reads.
set -euo pipefail

VERSION="${UXPLAY_VERSION:-534e2cc0e558d6c94bcc66964f8fc13ad73a6cdc}"
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
mkdir -p "$WORK/UxPlay"
curl -fsSL "https://github.com/FDH2/UxPlay/archive/${VERSION}.tar.gz" | tar -xz -C "$WORK/UxPlay" --strip-components 1

echo "==> Build…"
export PKG_CONFIG_PATH="$(brew --prefix openssl@3)/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
cmake -S "$WORK/UxPlay" -B "$WORK/build" -DCMAKE_BUILD_TYPE=Release
cmake --build "$WORK/build" -j "$(sysctl -n hw.ncpu)"

mkdir -p "$DEST"
# Copy then rename: replacing the file in place would crash an uxplay that Cermin is running right now.
cp "$WORK/build/uxplay" "$DEST/uxplay.new"
mv -f "$DEST/uxplay.new" "$DEST/uxplay"
echo "==> Selesai: $DEST/uxplay"
"$DEST/uxplay" -v 2>/dev/null | tail -1 || true
echo "Tutup lalu buka lagi Cermin supaya versi baru dipakai."
