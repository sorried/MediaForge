#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d -t mediaforge-persistence-tests.XXXXXX)"
trap 'rm -rf "${WORK:?}"' EXIT
TEST_FLAGS=()
if [[ $(uname -s) == Darwin ]]; then
  FRAMEWORKS="$(xcrun --sdk macosx --show-sdk-platform-path)/Developer/Library/Frameworks"
  SWIFT_TEST_LIBS="$(xcrun --sdk macosx --show-sdk-platform-path)/Developer/usr/lib"
  TEST_FLAGS=(-F "$FRAMEWORKS" -I "$SWIFT_TEST_LIBS" -L "$SWIFT_TEST_LIBS" -Xlinker -rpath -Xlinker "$FRAMEWORKS" -Xlinker -rpath -Xlinker "$SWIFT_TEST_LIBS")
fi
if [[ $(uname -s) == Darwin ]]; then EXT=dylib; else EXT=so; fi
swiftc -swift-version 6 -emit-library -emit-module -module-name MediaForgeCore "$ROOT"/Sources/MediaForgeCore/*.swift -emit-module-path "$WORK/MediaForgeCore.swiftmodule" -o "$WORK/libMediaForgeCore.$EXT"
swiftc -swift-version 6 -typecheck -I "$WORK" "$ROOT/Sources/MediaForgeApp/AppPersistence.swift" "$ROOT/Sources/MediaForgeApp/SettingsDraft.swift" "$ROOT/Sources/MediaForgeApp/UserErrors.swift" "$ROOT/Sources/MediaForgeApp/BuiltInPresets.swift"
swiftc -swift-version 5 "${TEST_FLAGS[@]}" -I "$WORK" -L "$WORK" -lMediaForgeCore -Xlinker -rpath -Xlinker "$WORK" "$ROOT/Sources/MediaForgeApp/AppPersistence.swift" "$ROOT/Sources/MediaForgeApp/SettingsDraft.swift" "$ROOT/Sources/MediaForgeApp/UserErrors.swift" "$ROOT/Sources/MediaForgeApp/BuiltInPresets.swift" "$ROOT/tests/AppPersistenceTests.swift" -o "$WORK/persistence-tests"
"$WORK/persistence-tests"
