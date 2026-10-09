#!/bin/bash
# Build Getto.app UNIVERSAL (x86_64 + arm64) Release + codesign ad-hoc
# (termasuk binary pendukung per-arch di Resources/bin/)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

cd "$ROOT"
bash scripts/fetch-binaries.sh || echo "WARN: lanjut tanpa semua binary"

# Tanpa -arch: pakai ARCHS proyek (universal). Debug build lokal otomatis
# hanya arch aktif (ONLY_ACTIVE_ARCH=YES), Release membangun keduanya.
xcodebuild -project Getto.xcodeproj \
  -scheme Getto \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  CONFIGURATION_BUILD_DIR="$ROOT/build/Getto.app/.." \
  build

APP="$ROOT/build/Getto.app"
echo "Codesign binary pendukung..."
find "$APP/Contents/MacOS" -type f -perm +111 -exec codesign --force -s - --options runtime {} \; || true
codesign --force --deep -s - --options runtime "$APP" || true
echo "OK: $APP"
codesign -dv "$APP" 2>&1 | head -5 || true
