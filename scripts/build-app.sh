#!/bin/bash
set -euo pipefail
ulimit -c 0
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ $(uname -s) == Darwin ]] || { echo "Xcode builds require macOS." >&2; exit 1; }
ARCH="${1:-$(uname -m)}"
[[ $(uname -m) == "$ARCH" ]] || { echo "Native architecture mismatch" >&2; exit 1; }
cd "$ROOT"
VERSION="${2:-1.0.0-dev}"
MARKETING_VERSION="$(python3 "$ROOT/scripts/release-version.py" "$VERSION")"
mkdir -p "$ROOT/build/logs/$ARCH"
xcodebuild -project MediaForge.xcodeproj -scheme MediaForge -configuration Release \
  -destination "platform=macOS,arch=$ARCH" -derivedDataPath "$ROOT/build/xcode/$ARCH" \
  ARCHS="$ARCH" ONLY_ACTIVE_ARCH=YES MARKETING_VERSION="$MARKETING_VERSION" CODE_SIGNING_ALLOWED=NO build 2>&1 | tee "$ROOT/build/logs/$ARCH/xcodebuild.log"
if [[ "$ARCH" == arm64 ]]; then
  codesign --force --sign - "$ROOT/build/xcode/$ARCH/Build/Products/Release/MediaForge.app/Contents/MacOS/MediaForge"
fi
APP="$ROOT/build/xcode/$ARCH/Build/Products/Release/MediaForge.app"
"$ROOT/scripts/bundle-ffmpeg.sh" "$APP" "$ARCH"
export MEDIAFORGE_FFMPEG="$APP/Contents/Resources/Tools/ffmpeg"
export MEDIAFORGE_FFPROBE="$APP/Contents/Resources/Tools/ffprobe"
REQUIRE_MEDIA_INTEGRATION=1 swift test --parallel 2>&1 | tee "$ROOT/build/logs/$ARCH/swift-tests.log"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/Licenses/MediaForge.txt"
python3 "$ROOT/scripts/verify-bundle.py" "$APP" "$ARCH"
