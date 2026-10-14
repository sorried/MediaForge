# Release acceptance

A release is not production-ready solely because it builds. Record results and environment for each gate below. Never replace a failed gate with an unchecked assumption.

## Automated gates

- Core unit tests: settings, commands, capability compatibility, output collision and commit safety, progress parser, history persistence.
- Integration tests with locally generated fixtures: true conversion, readable output, broken input failure, cancellation cleanup, Unicode and shell-special-character paths, large stdout/stderr without deadlock.
- Both runner architectures verified by `uname -m`; app and every bundled Mach-O verified with `file`, `lipo`, `otool` and load commands.
- Deployment target 14.0 throughout app, tools and libraries; no Homebrew/user-machine dependency paths.
- Real ZIP extracted and checked; real DMG mounted and checked; checksums verified.
- License/source artifacts included for the exact FFmpeg configuration.

## Manual macOS checks

- Launch from a downloaded DMG as a normal user, offline and without Homebrew.
- Import by picker, drop and recursive folder selection; duplicate imports and inaccessible files handled clearly.
- Convert video/audio/image, inspect real progress, cancel preparation and processing, retry failures, add jobs while queue runs, change concurrency.
- Output conflict never replaces an existing file. Originals remain byte-for-byte unchanged.
- Restart and confirm settings, custom presets, history and queue snapshots. Pending tasks must stay paused; interrupted probing/running tasks must require explicit retry and preserve possible output paths. Open result and reveal in Finder.
- Export odd-sized images (7×5 and one-pixel bounds), verify decoded dimensions, and confirm video still enforces encoder-compatible even sizes.
- Import a folder beyond queue capacity: scanning must stop with a clear limit error without partially mutating or losing the saved queue. Verify state and recovery backup permissions as a normal user.
- Inspect alpha/animation/metadata warnings and reject conversion when preservation is needed.
- Keyboard-only and VoiceOver navigation; compact window; light/dark mode.
- Observe no orphaned processes or unfinished temporary files after cancellation; recover sensibly after an abnormal app exit. Quit during engine capability discovery, and quit while idle after changing history retention: both paths must await coordinated shutdown and persist the final state, without an unnecessary active-job confirmation when idle.
- Run on real Intel macOS 14 and real Apple Silicon macOS 14. Newer hosted runners cannot establish this gate.
- Verify Gatekeeper separately for unsigned versus Developer ID/notarized packages.

## Current environment

The development host is Linux x86_64. [Native run38442505822](https://github.com/sorried/MediaForge/actions/runs/38442505822) on macOS26/Xcode26.6 passed the Apple Silicon pipeline:72XCTest cases (51core/7ImageIO/14appmodel), built app and bundled LGPL FFmpeg, verified Mach-O architecture/deployment/dependencies, mounted DMG and extracted ZIP, checked ad-hoc signatures and checksums. Downloaded ARM payload checksums were independently verified locally.

[Run38444522229](https://github.com/sorried/MediaForge/actions/runs/38444522229) passed the complete pipeline on both Intel and Apple Silicon, including 72 XCTest cases per architecture and the automatic VideoToolbox software fallback correction. Both ZIP/DMG payloads were downloaded and independently checked against their SHA-256 manifests. No manual GUI/VoiceOver, macOS14 runtime, Gatekeeper or Developer ID/notarization result is established. No tags or public release were created.
