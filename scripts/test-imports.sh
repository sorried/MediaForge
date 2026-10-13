#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d -t mediaforge-import-tests.XXXXXX)"
trap 'rm -rf "${WORK:?}"' EXIT
TEST_FLAGS=()
if [[ $(uname -s) == Darwin ]]; then
  FRAMEWORKS="$(xcrun --sdk macosx --show-sdk-platform-path)/Developer/Library/Frameworks"
  TEST_FLAGS=(-F "$FRAMEWORKS" -Xlinker -rpath -Xlinker "$FRAMEWORKS")
fi
swiftc -swift-version 6 -typecheck "$ROOT/Sources/MediaForgeApp/ImportScanner.swift"
swiftc -swift-version 5 "${TEST_FLAGS[@]}" "$ROOT/Sources/MediaForgeApp/ImportScanner.swift" "$ROOT/tests/ImportScannerTests.swift" -o "$WORK/import-tests"
"$WORK/import-tests"
