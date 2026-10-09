#!/bin/bash
# Unduh binary pendukung UNIVERSAL ke Getto/Resources/bin/<arch>/
#   x86_64: yt-dlp (universal), ffmpeg evermeet static, aria2c conda-forge
#   arm64 : yt-dlp (universal), ffmpeg osxexperts static, aria2c conda-forge
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$SCRIPT_DIR/../Getto/Resources/bin"
mkdir -p "$BIN_DIR/x86_64" "$BIN_DIR/arm64"

fix_rpaths() {
  # $1 = dir: ubah @rpath -> @loader_path agar bundel mandiri
  local dir="$1"
  [ -f "$dir/libaria2.0.dylib" ] && install_name_tool -id @loader_path/libaria2.0.dylib "$dir/libaria2.0.dylib" 2>/dev/null || true
  for f in "$dir"/aria2c "$dir"/*.dylib; do
    [ -f "$f" ] || continue
    for dep in $(otool -L "$f" 2>/dev/null | grep '@rpath' | awk '{print $1}'); do
      base=$(basename "$dep")
      install_name_tool -change "$dep" "@loader_path/$base" "$f" 2>/dev/null || true
    done
  done
}

fetch_ytdlp() {
  # yt-dlp_macos adalah binary UNIVERSAL (x86_64+arm64) — satu file untuk dua arch
  for arch in x86_64 arm64; do
    if [ ! -f "$BIN_DIR/$arch/yt-dlp" ]; then
      curl -fL -o "$BIN_DIR/$arch/yt-dlp" "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"
      chmod +x "$BIN_DIR/$arch/yt-dlp"
    fi
  done
  ./x86_64/yt-dlp --version 2>/dev/null || ./arm64/yt-dlp --version 2>/dev/null || echo "WARN: yt-dlp tidak bisa jalan di mesin ini (wajar untuk slice arm64 di Intel)"
}

fetch_ffmpeg_intel() {
  if [ ! -f "$BIN_DIR/x86_64/ffmpeg" ]; then
    if curl -fL -o /tmp/ffmpeg-intel.zip "https://evermeet.cx/ffmpeg/ffmpeg-6.1.zip"; then
      unzip -o -j /tmp/ffmpeg-intel.zip "ffmpeg" -d "$BIN_DIR/x86_64/"
      rm -f /tmp/ffmpeg-intel.zip
      chmod +x "$BIN_DIR/x86_64/ffmpeg"
    else
      echo "WARN: unduh ffmpeg Intel gagal"
    fi
  fi
}

fetch_ffmpeg_arm() {
  # evermeet TIDAK menyediakan build Apple Silicon -> pakai osxexperts static
  if [ ! -f "$BIN_DIR/arm64/ffmpeg" ]; then
    if curl -fL -o /tmp/ffmpeg-arm.zip "https://www.osxexperts.net/ffmpeg80arm.zip"; then
      unzip -o -j /tmp/ffmpeg-arm.zip "ffmpeg" -d "$BIN_DIR/arm64/"
      rm -f /tmp/ffmpeg-arm.zip
      chmod +x "$BIN_DIR/arm64/ffmpeg"
    else
      echo "WARN: unduh ffmpeg ARM gagal"
    fi
  fi
}

fetch_aria2() {
  # $1 = arch dir (x86_64|arm64), $2 = conda subdir (osx-64|osx-arm64)
  local arch="$1" subdir="$2"
  if [ -f "$BIN_DIR/$arch/aria2c" ]; then return 0; fi
  if ! command -v conda >/dev/null 2>&1; then
    echo "WARN: butuh conda untuk aria2 $arch. Lihat README."
    return 0
  fi
  echo "Ambil aria2 $arch dari conda-forge ($subdir)..."
  local scratch
  scratch="$(mktemp -d)/aria2env"
  CONDA_SUBDIR="$subdir" conda create -y -p "$scratch" -c conda-forge aria2
  cp "$scratch/bin/aria2c" "$BIN_DIR/$arch/"
  for d in libaria2.0.dylib libz.1.dylib libxml2.16.dylib libsqlite3.dylib libgmp.10.dylib libssh2.1.dylib libcares.2.dylib libc++.1.dylib libcrypto.3.dylib libssl.3.dylib; do
    [ -f "$BIN_DIR/$arch/$d" ] || cp "$scratch/lib/$d" "$BIN_DIR/$arch/" 2>/dev/null || echo "WARN: $d tak ada ($arch)"
  done
  fix_rpaths "$BIN_DIR/$arch"
  rm -rf "$scratch" "$(dirname "$scratch")"
  chmod +x "$BIN_DIR/$arch/aria2c"
}

cd "$BIN_DIR"
echo "== yt-dlp (universal) =="
fetch_ytdlp
echo "== ffmpeg x86_64 (evermeet static) =="
fetch_ffmpeg_intel
./x86_64/ffmpeg -version 2>/dev/null | head -1 || echo "WARN: ffmpeg Intel belum tersedia"
echo "== ffmpeg arm64 (osxexperts static) =="
fetch_ffmpeg_arm
file ./arm64/ffmpeg 2>/dev/null || echo "WARN: ffmpeg ARM belum tersedia"
echo "== aria2c x86_64 (conda-forge osx-64) =="
fetch_aria2 x86_64 osx-64
./x86_64/aria2c --version 2>/dev/null | head -1 || echo "WARN: aria2c Intel belum tersedia"
echo "== aria2c arm64 (conda-forge osx-arm64) =="
fetch_aria2 arm64 osx-arm64
file ./arm64/aria2c 2>/dev/null || echo "WARN: aria2c ARM belum tersedia"

echo "== Verifikasi =="
file ./x86_64/aria2c ./x86_64/ffmpeg ./arm64/aria2c ./arm64/ffmpeg 2>/dev/null || true
lipo -info ./x86_64/yt-dlp 2>/dev/null | tail -1 || true
echo "Selesai. Binary ada di $BIN_DIR/{x86_64,arm64}"
