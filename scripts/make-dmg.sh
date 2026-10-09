#!/bin/bash
# Buat Getto.dmg dengan jendela instalasi (ikon app + shortcut Applications)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/.."
APP="$ROOT/build/Getto.app"
DMG="$ROOT/build/Getto.dmg"
STAGE="$ROOT/build/dmg-stage"

[ -d "$APP" ] || { echo "Getto.app tidak ditemukan. Jalankan scripts/build.sh dulu."; exit 1; }
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# Kewajiban GPL: binary GPL (ffmpeg, aria2c) redistributed di dalam DMG harus
# disertai teks lisensi + Corresponding Source. Teks lisensi sudah ikut
# sebagai resource di dalam Getto.app; dokumentasi penuh di root DMG supaya
# selalu terlihat meski .app tidak dibuka.
cp "$ROOT/LICENSE" "$ROOT/THIRD_PARTY_NOTICES.md" "$STAGE/"
mkdir -p "$STAGE/Source"
{
  echo "Getto — Corresponding Source untuk binary berlisensi GPL"
  echo "(ffmpeg, aria2c). Lihat THIRD_PARTY_NOTICES.md untuk detail."
  echo
  echo "Getto tidak melakukan patch pada binary mana pun; source upstream"
  echo "persis pada versi yang dipakai + konfigurasi build tersedia di:"
  echo
  echo "  aria2 1.37.0   https://github.com/aria2/aria2/releases/tag/release-1.37.0"
  echo "  ffmpeg 6.1     https://ffmpeg.org/releases/ffmpeg-6.1.tar.xz"
  echo "  ffmpeg 8.0     https://ffmpeg.org/releases/  (tag 8.0)"
  echo "  yt-dlp         https://github.com/yt-dlp/yt-dlp/tree/2026.08.19"
  echo "  dylib lain     conda-forge channel, subdir osx-64 / osx-arm64"
  echo
  echo "Source Getto itu sendiri: https://github.com/YandiDesign/getto"
} > "$STAGE/Source/Corresponding-Source.txt"

hdiutil create -volname "Getto" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
echo "OK: $DMG"
