#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d -t mediaforge-import-tests.XXXXXX)"
trap 'rm -rf "${WORK:?}"' EXIT
swiftc -swift-version 6 -typecheck "$ROOT/Sources/MediaForgeApp/ImportScanner.swift"
swiftc -swift-version 5 "$ROOT/Sources/MediaForgeApp/ImportScanner.swift" "$ROOT/tests/ImportScannerTests.swift" -o "$WORK/import-tests"
"$WORK/import-tests"
