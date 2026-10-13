#!/bin/bash
set -euo pipefail
ulimit -c 0
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
: "${MEDIAFORGE_FFMPEG:?Set MEDIAFORGE_FFMPEG to the real test ffmpeg executable}"
: "${MEDIAFORGE_FFPROBE:?Set MEDIAFORGE_FFPROBE to the real test ffprobe executable}"
[[ "$MEDIAFORGE_FFMPEG" == /* && -x "$MEDIAFORGE_FFMPEG" ]] || { echo "FFmpeg must be an absolute executable path." >&2; exit 1; }
[[ "$MEDIAFORGE_FFPROBE" == /* && -x "$MEDIAFORGE_FFPROBE" ]] || { echo "FFprobe must be an absolute executable path." >&2; exit 1; }
for script in scripts/*.sh; do bash -n "$script"; done
python3 -m py_compile scripts/*.py
python3 -m unittest discover -s tests -v
REQUIRE_MEDIA_INTEGRATION=1 swift test
bash scripts/test-imports.sh
bash scripts/test-persistence.sh
swiftc -frontend -parse Sources/MediaForgeApp/*.swift Tests/MediaForgeAppTests/*.swift
git diff --check
if [[ $(uname -s) != Darwin ]]; then
  echo "Portable verification passed. Apple framework typechecking, ImageIO, VideoToolbox, app launch and macOS distributions remain unverified."
else
  echo "Development tests passed. Packaged-tool validation and real macOS 14 device acceptance are separate required gates."
fi
