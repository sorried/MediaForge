#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="${1:?Usage: package.sh architecture version}"
[[ "$ARCH" == arm64 || "$ARCH" == x86_64 ]] || { echo "Unsupported architecture" >&2; exit 1; }
VERSION="${2:?Version required}"
python3 "$ROOT/scripts/release-version.py" "$VERSION" > /dev/null
APP="$ROOT/build/xcode/$ARCH/Build/Products/Release/MediaForge.app"
python3 "$ROOT/scripts/release-version.py" "$VERSION" --plist "$APP/Contents/Info.plist" > /dev/null
OUT="$ROOT/dist/$ARCH"
NAME="MediaForge-$VERSION-$ARCH"
if [[ "$ARCH" == arm64 ]]; then PLATFORM=AppleSilicon; else PLATFORM=Intel; fi
BINARY_NAME="MediaForge-macOS-14+-$PLATFORM"
mkdir -p "$OUT"
python3 "$ROOT/scripts/verify-bundle.py" "$APP" "$ARCH"
IDENTITY="${APPLE_SIGNING_IDENTITY:-}"
NOTARIZED=false
SIGNING=ad-hoc
if [[ -n "$IDENTITY" ]]; then
  SIGNING=developer-id
  for binary in "$APP"/Contents/Resources/Tools/lib/*.dylib "$APP"/Contents/Resources/Tools/ffmpeg "$APP"/Contents/Resources/Tools/ffprobe; do
    [[ -L "$binary" ]] && continue
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$binary"
  done
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
else
  for binary in "$APP"/Contents/Resources/Tools/lib/*.dylib "$APP"/Contents/Resources/Tools/ffmpeg "$APP"/Contents/Resources/Tools/ffprobe; do
    [[ -L "$binary" ]] && continue
    codesign --force --sign - "$binary"
  done
  codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"
NOTARY_PROFILE="${APPLE_NOTARY_PROFILE:-}"
if [[ -n "$NOTARY_PROFILE" ]]; then
  [[ -n "$IDENTITY" ]] || { echo "Notarization requires Developer ID signing" >&2; exit 1; }
  ditto -c -k --keepParent "$APP" "$OUT/notarization.zip"
  xcrun notarytool submit "$OUT/notarization.zip" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  spctl --assess --type execute --verbose=2 "$APP"
  NOTARIZED=true
fi
python3 "$ROOT/scripts/verify-bundle.py" "$APP" "$ARCH"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/$BINARY_NAME.zip"
STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE:?}"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Media Forge" -srcfolder "$STAGE" -ov -format UDZO "$OUT/$BINARY_NAME.dmg"
hdiutil verify "$OUT/$BINARY_NAME.dmg"
MOUNT="$STAGE/mounted"
mkdir -p "$MOUNT"
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT" "$OUT/$BINARY_NAME.dmg"
trap 'hdiutil detach "$MOUNT"; rm -rf "${STAGE:?}"' EXIT
python3 "$ROOT/scripts/verify-bundle.py" "$MOUNT/MediaForge.app" "$ARCH"
codesign --verify --deep --strict "$MOUNT/MediaForge.app"
[[ -L "$MOUNT/Applications" && $(readlink "$MOUNT/Applications") == /Applications ]]
hdiutil detach "$MOUNT"
trap 'rm -rf "${STAGE:?}"' EXIT
if [[ -n "$IDENTITY" ]]; then
  codesign --force --timestamp --sign "$IDENTITY" "$OUT/$BINARY_NAME.dmg"
fi
if [[ "$NOTARIZED" == true ]]; then
  xcrun notarytool submit "$OUT/$BINARY_NAME.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$OUT/$BINARY_NAME.dmg"
  xcrun stapler validate "$OUT/$BINARY_NAME.dmg"
fi
SOURCE="$APP/Contents/Resources/Licenses/FFmpeg"
ditto -c -k --keepParent "$SOURCE" "$OUT/$NAME-FFmpeg-source.zip"
printf 'architecture=%s\nversion=%s\nsigning=%s\nnotarized=%s\n' "$ARCH" "$VERSION" "$SIGNING" "$NOTARIZED" > "$OUT/$NAME-status.txt"
cd "$OUT"
shasum -a 256 "$BINARY_NAME.zip" "$BINARY_NAME.dmg" "$NAME-FFmpeg-source.zip" "$NAME-status.txt" > "$NAME-SHA256SUMS.txt"
shasum -a 256 -c "$NAME-SHA256SUMS.txt"
UNPACK="$(mktemp -d "$STAGE/unpack.XXXXXX")"
ditto -x -k "$BINARY_NAME.zip" "$UNPACK"
python3 "$ROOT/scripts/verify-bundle.py" "$UNPACK/MediaForge.app" "$ARCH"
codesign --verify --deep --strict "$UNPACK/MediaForge.app"
