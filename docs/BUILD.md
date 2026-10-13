# Building Media Forge

## Requirements

macOS 14+ and full stable Xcode are required. CI pins **Xcode 26.6 (17F113)** using `DEVELOPER_DIR=/Applications/Xcode_26.6.app/Contents/Developer`, not the moving default or a beta. Deployment is macOS 14.0; Swift language mode is 6.

The hand-maintained [Xcode project](../MediaForge.xcodeproj/project.pbxproj) has a real MediaForgeCore static Swift library and MediaForge SwiftUI app, an explicit target dependency, and a library link entry. Synchronized source/resource groups include the two Sources directories and Resources assets/localization; the resource generator and its bytecode cache are excluded. No XcodeGen is needed. Core and macOS app-model XCTest run through the Swift package, not a fictitious Xcode test target. The Verification resource subtree is excluded from app membership because it contains a standalone test entry point.

The Swift package executable is a compile/test product, not an assembled distributable: `swift run MediaForge` has no bundled tools/resources and will report the missing engine. Run the Xcode-built `.app` assembled by build-app for actual interactive conversion. Tests explicitly provide engine paths; production discovery does not use them.

## Native build

From the checkout on Apple Silicon:

```bash
export DEVELOPER_DIR=/Applications/Xcode_26.6.app/Contents/Developer
scripts/build-ffmpeg.sh arm64
scripts/build-app.sh arm64 1.0.0
scripts/package.sh arm64 1.0.0
```

Pass the same release version to build-app and package. The shared version parser strips the optional v prefix/prerelease suffix for the three-component app marketing version; packaging fails if Info.plist disagrees. CI resolves the tag version once before compiling the app. On Intel use `x86_64` for all commands. Scripts reject mismatched actual `uname -m` rather than silently using Rosetta. FFmpeg builds reject stale source build directories: start with a clean ignored `build/ffmpeg/<architecture>` directory when rebuilding. Cached source is checksum-checked on every run.

Outputs under `dist/<architecture>` include `MediaForge-macOS-14+-AppleSilicon.zip` / `.dmg` or `MediaForge-macOS-14+-Intel.zip` / `.dmg`, a versioned FFmpeg-source ZIP, actual signing-status text and SHA-256 manifest. The application is built under `build/xcode/<architecture>/Build/Products/Release`.

[build-app.sh](../scripts/build-app.sh) builds the app, bundles FFmpeg, then runs package XCTest with `MEDIAFORGE_FFMPEG`, `MEDIAFORGE_FFPROBE`, and `REQUIRE_MEDIA_INTEGRATION=1` so a missing bundled engine cannot silently skip integration tests. An IDE-only Xcode build compiles the app but does not inject FFmpeg; run the script to assemble it. Missing tools must show an error, not fall back to Homebrew.

## CI and tag publication

[The workflow](../.github/workflows/build.yml) uses `macos-26` (arm64) and `macos-26-intel` (x86_64), checks actual architecture and exact Xcode version/build, validates project/scripts, runs Python packaging tests, compiles FFmpeg, builds the app, runs core/integration tests, and packages both architectures. Action references are immutable commit SHAs resolved from official action repositories. `v*` releases wait for the entire matrix and recheck both checksum manifests before publishing. No partial architecture release is published.

Official documents consulted on 2026-10-13:

- [GitHub-hosted runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [arm64 macOS 26 manifest](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)
- [Intel macOS 26 manifest](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md)

Both manifests listed stable Xcode 26.6 build 17F113. Runner labels are not immutable images; a removed installation fails closed. Update pin and build checks together after testing both platforms.

## Artifact validation

[verify-bundle.py](../scripts/verify-bundle.py) requires actual executable Mach-O app/ffmpeg/ffprobe, checks every Mach-O architecture and macOS deployment load command, bundle-local dependency resolution, system-library allowlist, Homebrew path absence, exact pinned runtime versions for both tools, tokenized FFmpeg configuration/license and registered native encoders, and matching corresponding source/archive/configuration pin. Verifier subprocesses have60-second deadlines. It runs before/after signing and on the extracted ZIP. DMGs are verified, mounted read-only, checked for the app and Applications link, and the mounted app is revalidated before detaching. Release checksums identify the exact assets.

This is a source/configuration-pinned repeatable recipe, **not a bit-for-bit reproducibility claim for signed ZIPs/DMGs**. Apple SDK/toolchain changes, Mach-O UUIDs, archive/filesystem metadata, signing timestamps and notarization tickets can change bytes. macOS 14 deployment metadata is not proof of runtime compatibility: test actual artifacts on macOS 14 and verify hardware encoders on real devices.

## Optional Apple credentials

No secrets means ad-hoc signing and status `signing=ad-hoc`, `notarized=false`. Those builds are **not Developer ID signed, notarized or Gatekeeper trusted**.

Tag builds alone can import these repository secrets:

- `APPLE_CERTIFICATE_BASE64`: exported Developer ID Application certificate/private key P12, base64 encoded.
- `APPLE_CERTIFICATE_PASSWORD`: P12 export password.
- `APPLE_SIGNING_IDENTITY`: exact Developer ID Application identity.

Optional notarization additionally requires the complete trio `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD` (app-specific password). Partial configurations fail. The temporary runner keychain is deleted in an always-run cleanup; the P12 is removed by script cleanup. Pull requests do not import credentials. Libraries/tools/app are signed inside-out, with hardened runtime and timestamps for Developer ID. App ZIP and DMG notarization both wait for success and staple/validate tickets; the app receives a Gatekeeper assessment. Status says notarized only after successful commands.

Locally use `APPLE_SIGNING_IDENTITY` from your existing keychain and optionally `APPLE_NOTARY_PROFILE` for credentials stored by `notarytool`. See [Apple hardened runtime](https://developer.apple.com/documentation/xcode/configuring-the-hardened-runtime) and [notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Validation boundary

Infrastructure was developed on Linux without Xcode. Shell/Python syntax and project/workflow structure can be checked here. No macOS app compilation, hardware encoding with this pinned LGPL build, DMG creation, Developer ID signing or notarization has been executed here; those need successful macOS CI and real-device acceptance logs.
