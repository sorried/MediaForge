#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/Config/ffmpeg.env"
[[ $(uname -s) == Darwin ]] || { echo "FFmpeg builds require macOS and Xcode." >&2; exit 1; }
ARCH="${1:-$(uname -m)}"
[[ "$ARCH" == arm64 || "$ARCH" == x86_64 ]] || exit 1
[[ $(uname -m) == "$ARCH" ]] || { echo "Native architecture mismatch" >&2; exit 1; }
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
export MACOSX_DEPLOYMENT_TARGET
export LC_ALL=C
export SOURCE_DATE_EPOCH=1764806400
unset CPATH LIBRARY_PATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH DYLD_LIBRARY_PATH PKG_CONFIG_PATH
SDK="$(xcrun --sdk macosx --show-sdk-path)"
WORK="$ROOT/build/ffmpeg/$ARCH"
PREFIX="$WORK/install"
ARCHIVE="$ROOT/build/downloads/ffmpeg-$FFMPEG_VERSION.tar.xz"
mkdir -p "$ROOT/build/downloads" "$WORK"
if [[ ! -f "$ARCHIVE" ]]; then
  curl --fail --location --proto '=https' --tlsv1.2 "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz" -o "$ARCHIVE.partial"
  mv "$ARCHIVE.partial" "$ARCHIVE"
fi
printf '%s  %s
' "$FFMPEG_SHA256" "$ARCHIVE" | shasum -a 256 -c -
SOURCE="$WORK/ffmpeg-$FFMPEG_VERSION"
[[ ! -e "$SOURCE" ]] || { echo "Use a clean build/ffmpeg/$ARCH directory before rebuilding." >&2; exit 1; }
tar -xf "$ARCHIVE" -C "$WORK"
cd "$SOURCE"
FLAGS="-arch $ARCH -isysroot $SDK -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET"
./configure --prefix="$PREFIX" --arch="$ARCH" --target-os=darwin \
  --cc="$(xcrun -f clang)" --sysroot="$SDK" \
  --extra-cflags="$FLAGS" --extra-ldflags="$FLAGS -Wl,-headerpad_max_install_names" \
  --disable-autodetect --disable-gpl --disable-nonfree --disable-version3 \
  --disable-static --enable-shared --disable-doc --disable-debug --disable-x86asm \
  --disable-network --disable-audiotoolbox --disable-securetransport \
  --enable-zlib --enable-videotoolbox --enable-ffmpeg --enable-ffprobe \
  --install-name-dir='@rpath'
make -j "$(sysctl -n hw.logicalcpu)"
make install
mkdir -p "$PREFIX/redistribution"
cp "$ARCHIVE" "$PREFIX/redistribution/"
cp COPYING.LGPLv2.1 LICENSE.md "$PREFIX/redistribution/"
cp ffbuild/config.mak config.h "$PREFIX/redistribution/"
cp "$ROOT/scripts/build-ffmpeg.sh" "$ROOT/Config/ffmpeg.env" "$PREFIX/redistribution/"
printf 'Unmodified official FFmpeg %s source. No source patches. SHA-256: %s
' "$FFMPEG_VERSION" "$FFMPEG_SHA256" > "$PREFIX/redistribution/CHANGES.txt"
