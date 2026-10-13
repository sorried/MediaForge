# Media Forge

**English** · [Русский](<README.ru.md>)

A native, local-first media converter for macOS 14+, built with SwiftUI and AppKit. Convert video, audio and images without a browser shell, cloud uploads or a separate media server.

**In development.** [Native CI run38442505822](https://github.com/sorried/MediaForge/actions/runs/38442505822) produced verified Apple Silicon ZIP/DMG artifacts after72XCTest checks. They are ad-hoc signed, not notarized. Intel built the app but failed two VideoToolbox hardware-dependent conversions; automatic-mode fallback is being verified. Manual GUI review and actual macOS14 runtime acceptance remain outstanding. No public release has been published.

[Builds and checks](https://github.com/sorried/MediaForge/actions) · [Releases](https://github.com/sorried/MediaForge/releases) · [Verification status](<docs/STATUS.md>)

## Features

- File picker, drag-and-drop and optional recursive folder import.
- Queue with 1–4 concurrent jobs, cancellation, retries and real FFmpeg progress.
- History, custom presets, themes, diagnostics and per-job output folders.
- Persistent queue: pending jobs restore paused; interrupted jobs require a manual retry.
- Trimming, resolution, aspect ratio, frame rate and bitrate; audio channels and sample rate.
- Approximate one-pass target size for MP4/MOV, with measured deviation—not an exact-size guarantee.
- Native ImageIO PNG/JPEG conversion with aspect-fit resizing, JPEG quality, transparency handling and loss warnings.

These describe implemented code. Native ImageIO and app-model tests passed on Apple Silicon with real conversions; manual UI/accessibility review and Intel acceptance remain outstanding.

## Formats

| Media | Core output profiles |
| --- | --- |
| Video | MP4, MOV, MKV, WebM, AVI, M4V, TS |
| Audio | MP3, M4A, AAC, AIFF, OGG, Opus, FLAC, WAV |
| Images | PNG, JPEG, WebP single-frame exports |

All 18 profiles have been converted with a test engine. Application support depends on the actual bundled encoders and muxers. The minimal LGPL configuration lacks MP3, OGG, Opus, WebM and WebP; unavailable options are disabled.

Image exports can discard animation, extra pages, metadata and color information. HEIC/TIFF/BMP support exists in the service layer but is not exposed in the main interface.

## Safety and privacy

Processing is local; no application account or cloud service is required. Originals are never intentionally overwritten or deleted. Jobs encode into private staging directories. The engine checks metadata and fully decodes staged media before exclusive publication; existing destination files are not replaced. Verification adds processing time, and cancellation remains available before publication.

## Requirements and installation

- Target OS: macOS 14 Sonoma or later. A deployment target alone does not prove Sonoma compatibility.
- Apple Silicon: `arm64`; Intel: `x86_64`.
- Release bundles are intended to include FFmpeg and FFprobe, without requiring Homebrew.

After successful macOS CI, open the run’s **Artifacts** section. Planned distribution names:

```text
MediaForge-macOS-14+-AppleSilicon.zip
MediaForge-macOS-14+-AppleSilicon.dmg
MediaForge-macOS-14+-Intel.zip
MediaForge-macOS-14+-Intel.dmg
```

Choose your architecture, open the DMG and drag Media Forge into Applications. These are intended installation steps, not a claim that verified downloads already exist.

**Ad-hoc builds may be blocked by Gatekeeper.** Developer ID signing and notarization require separate Apple credentials and successful verification. Do not disable Gatekeeper globally.

## Development and verification

Native builds and packaging require macOS and Xcode. The portable core can be tested with a compatible Swift toolchain. Full verification requires explicit paths to real FFmpeg and FFprobe:

```sh
MEDIAFORGE_FFMPEG=/absolute/path/to/ffmpeg \
MEDIAFORGE_FFPROBE=/absolute/path/to/ffprobe \
bash scripts/verify-development.sh
```

The command runs real conversion tests, import and persistence checks, Python tests and Swift syntax checks. On Linux it does **not** typecheck Apple frameworks or verify native distributions. A plain `swift test` may skip integration when tools are absent.

See [build instructions](<docs/BUILD.md>), [release acceptance](<docs/ACCEPTANCE.md>), [contributing](<CONTRIBUTING.md>) and the [development log](<DEVELOPMENT_LOG.md>) for commands and evidence.

## License and releases

The existing [GPLv3 application license](<LICENSE>) is unchanged. FFmpeg has separate redistribution obligations. The release engine uses pinned source and an LGPL-only configuration without GPL/nonfree components; see [FFmpeg build and licensing](<docs/FFMPEG.md>).

Branch builds do not publish releases. Version-tag releases must wait for both architecture builds, tests and archive verification. Tags and public publication require the repository owner’s authorization.
