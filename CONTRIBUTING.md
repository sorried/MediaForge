# Contributing

Media Forge is a native macOS application, not a web service. Keep UI concerns in MediaForgeApp and media/file operations in MediaForgeCore. The repository’s existing GPLv3 license applies to the application. Bundled FFmpeg has separate license notices and source redistribution requirements.

## Before changing code

1. Inspect `git status --short`; preserve unrelated changes.
2. Read the build and FFmpeg documentation in `docs/`.
3. Use a stable Xcode toolchain and macOS 14 deployment target.
4. Keep profile availability based on discovered encoders and muxers. Never assume Homebrew or an externally installed engine in release builds.

## Verification

Run `swift test` for the core. Integration tests require a real FFmpeg and FFprobe supplied through the documented test environment; skipped integrations are not evidence of a working conversion. Run the architecture build workflow on both macOS runner architectures before a release. A Linux core test does not validate SwiftUI, AppKit, Mach-O dependencies, DMG or Gatekeeper.

Test malformed media, cancellation, pipes exceeding OS buffers, Unicode paths, conflicting output names, inaccessible destinations, settings round trips and no modification of originals. Update tests with behavior changes. Avoid shell command interpolation in the conversion engine, unbounded task creation, suppressed errors and fake progress.

## Changes and commits

Make focused conventional commits after checks and diff review. Stage explicit paths, never media files, private logs, signing credentials or build outputs. Do not change the existing license without maintainer approval. Do not force-push or publish a release without authorization.

Native UI changes require manual keyboard and VoiceOver review, light/dark appearances and compact windows. Do not mark a feature tested until it was actually exercised.
