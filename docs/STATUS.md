# Product status

This ledger separates implemented code from verified native behavior. Update it after actual tests.

## Implemented core vertical slice

- Foundation Swift6 library, FFmpeg/FFprobe subprocess arguments, concurrent pipe drains, progress parser.
- Bundled-tool discovery by default; external tools are test/development opt-in.
- Media metadata and runtime encoder/container capabilities.
- Profiles include MP4/MOV/MKV/WebM/AVI/M4V/TS video; MP3/M4A/AAC/AIFF/OGG/Opus/FLAC/WAV audio; PNG/JPEG/WebP single-frame exports. Each requires a compatible real encoder/container composition; unsupported bundled codecs remain disabled. All18 profiles have been converted and probed successfully with the test engine.
- Trim, dimensions, frame rate, audio removal and bitrate settings. Default aspect preservation with centered padding is verified through real converted/decode RGB pixels; explicit stretching is optional.
- Latest pinned-LGPL Linux verification:51 core XCTest passes,1 explicit ImageIO skip; scanner6/6, app persistence/preset catalog17/17, portable packaging/version/localization/signing/release36/36. Strict Swift6 core compilation and native source syntax parse pass; no Apple SDK typecheck claim.
- Job-local temporary output, real post-conversion probing and exclusive publication without overwrite.
- Deadline/cancellation with child termination and kill escalation.

Pinned LGPL8.0.1 Linux source-build verification also passed the complete suite with13supported profiles; five optional profiles explicitly unavailable. This is a minimal static Linux configuration, not the shipped shared macOS configuration. See [pinned engine verification](<PINNED_ENGINE_VERIFICATION.md>).

Latest all18-profile Linux verification passed50coretests plus1explicitImageIOskip, scanner6/6, persistence17/17 andPython33/33. All18-profile Linux XCTest verification uses Swift6.0.3 and locally extracted Debian FFmpeg/FFprobe5.1.9 **test-only GPL-enabled** binaries. Initial tests also used FFmpeg7.0.2; its FFprobe crashed on MPEG-TS, so the complete expanded suite uses the stable Debian pair. Neither test tool pair is shipped or copied into release dependencies. It does not validate the separate macOS LGPL8.0.1 configuration.

## Native application under review

SwiftUI/AppKit import, queue, history, custom presets, settings, Finder/open actions, diagnostics and localizable Russian strings are implemented in source. Syntax parsing is possible on Linux; Apple module typechecking and native interaction require macOS. Do not interpret source presence as a successful native build.

## Not established yet

- Working artifacts for Intel/Apple Silicon are not established. Actual dual-architecture CI has started: native toolchain/project checks and standalone import/persistence test gates passed. Pinned LGPL FFmpeg 8.0.1 source compilation succeeded on both architectures in run38440847674. The application build failed on a duplicate verification entrypoint; the exact source exclusion fix is under CI verification. Application tests and package stages are not yet verified.
- Additional profile mappings are implemented, but optional MP3/OGG/Opus/WebM/WebP encoders are absent in the minimal bundled LGPL configuration. No promise those options work without an appropriate compliant engine build.
- ImageIO HEIC/TIFF/BMP service exists with seven native tests; those formats are not exposed in the main UI yet and macOS tests have not run.
- Target-size retries: implemented one-pass bitrate estimate with real measured deviation; exact size is not promised. Multi-attempt refinement remains optional follow-up.
- Audio sample rate/channels and encoder preference are implemented and tested in the core; native UI execution remains unverified.
- Native PNG/JPEG ImageIO quality, aspect-fit, alpha flatten/preservation and explicit loss warnings are integrated, but macOS runtime remains unverified. Native synchronous ImageIO encoding cannot be interrupted mid-call; cancellation is checked before publication. Image bounds now accept integer1...16384 independently from video alignment; odd dimensions are covered by portable draft validation and actual7x5 PNG/JPEG/WebP FFmpeg conversion/decode tests. Native ImageIO execution remains untested here.
- Portable app settings/history/preset/queue persistence/preset catalog has seventeen real tests; core queue transitions have tests. Fourteen macOS app-model tests and seven ImageIO tests are added but not executed here. Actual GUI queue behavior, crash recovery and VoiceOver/keyboard review remain unverified.
- Queue snapshots now persist along with history/settings/presets. Pending jobs restore paused; interrupted running/probing jobs become failed with manual retry required and possible output paths preserved. Duplicate IDs and more than10000 jobs are rejected. Portable serialization/recovery tests pass; real app relaunch behavior still requires macOS.
- Interrupted job directories are not automatically cleaned after abnormal termination; normal cancellation cleanup is tested.
- Core QueueState/HistoryStore are separately tested primitives; app currently owns its MainActor scheduler and versioned StateStore, so core tests alone do not verify native scheduling.
- macOS14 runtime on both architectures; Gatekeeper/notarization.

These are real remaining product requirements, not disabled-looking placeholders claimed complete. Release acceptance is described in ACCEPTANCE.md.
