#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:?$'Usage: bundle-ffmpeg.sh app-path architecture'}"
ARCH="${2:?Architecture required}"
PREFIX="$ROOT/build/ffmpeg/$ARCH/install"
TOOLS="$APP/Contents/Resources/Tools"
LICENSES="$APP/Contents/Resources/Licenses/FFmpeg"
mkdir -p "$TOOLS/lib" "$LICENSES"
cp "$PREFIX/bin/ffmpeg" "$PREFIX/bin/ffprobe" "$TOOLS/"
for library in "$PREFIX"/lib/*.dylib; do
  cp -P "$library" "$TOOLS/lib/"
done
for binary in "$TOOLS/ffmpeg" "$TOOLS/ffprobe" "$TOOLS"/lib/*.dylib; do
  [[ -L "$binary" ]] && continue
  [[ "$binary" != *.dylib ]] || install_name_tool -id "@loader_path/$(basename "$binary")" "$binary"
  while IFS= read -r dependency; do
    case "$dependency" in
      /System/Library/*|/usr/lib/*) ;;
      *libav*.dylib|*libsw*.dylib)
        name="$(basename "$dependency")"
        [[ -f "$TOOLS/lib/$name" ]] || { echo "Missing bundled library: $name" >&2; exit 1; }
        if [[ "$binary" == *.dylib ]]; then replacement="@loader_path/$name"; else replacement="@executable_path/lib/$name"; fi
        install_name_tool -change "$dependency" "$replacement" "$binary"
        ;;
      *) echo "Unapproved FFmpeg dependency: $dependency" >&2; exit 1 ;;
    esac
  done < <(otool -L "$binary" | tail -n +2 | awk '{print $1}')
done
for binary in "$TOOLS"/lib/*.dylib "$TOOLS/ffmpeg" "$TOOLS/ffprobe"; do
  [[ -L "$binary" ]] && continue
  codesign --force --sign - "$binary"
done
cp -R "$PREFIX/redistribution/." "$LICENSES/"
"$TOOLS/ffmpeg" -L > "$LICENSES/runtime-license.txt" 2>&1
"$TOOLS/ffmpeg" -hide_banner -encoders > "$LICENSES/encoders.txt" 2>&1
"$TOOLS/ffmpeg" -hide_banner -buildconf > "$LICENSES/buildconf.txt" 2>&1
python3 "$ROOT/scripts/verify-bundle.py" "$APP" "$ARCH"
