#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d -t mediaforge-import-tests.XXXXXX)"
trap 'rm -rf "${WORK:?}"' EXIT
TEST_FLAGS=()
if [[ $(uname -s) == Darwin ]]; then
  FRAMEWORKS="$(xcrun --sdk macosx --show-sdk-platform-path)/Developer/Library/Frameworks"
  SWIFT_TEST_LIBS="$(xcrun --sdk macosx --show-sdk-platform-path)/Developer/usr/lib"
  SHARED_FRAMEWORKS="$(xcode-select -p)/../SharedFrameworks"
  TEST_FLAGS=(-Xlinker -rpath -Xlinker "$SHARED_FRAMEWORKS" -F "$FRAMEWORKS" -I "$SWIFT_TEST_LIBS" -L "$SWIFT_TEST_LIBS" -Xlinker -rpath -Xlinker "$FRAMEWORKS" -Xlinker -rpath -Xlinker "$SWIFT_TEST_LIBS")
fi
swiftc -swift-version 6 -typecheck "$ROOT/Sources/MediaForgeApp/ImportScanner.swift"
swiftc -swift-version 5 "${TEST_FLAGS[@]}" "$ROOT/Sources/MediaForgeApp/ImportScanner.swift" "$ROOT/tests/ImportScannerTests.swift" -o "$WORK/import-tests"
"$WORK/import-tests"
