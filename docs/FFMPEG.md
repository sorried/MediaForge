# Bundled FFmpeg

## Exact source pin

[The pin](../Config/ffmpeg.env) is FFmpeg **8.0.1**, the [official HTTPS source archive](https://ffmpeg.org/releases/ffmpeg-8.0.1.tar.xz), SHA-256:

```text
05ee0b03119b45c0bdb4df654b96802e909e0a752f72e4fe3794f487229e5a41
```

This digest was computed from the official archive during development and is checked before every extraction. This is a content-integrity pin, **not a claim of verified OpenPGP release-signature provenance**. Review upstream security fixes and update version/hash deliberately; never substitute a floating snapshot, third-party binary, or Homebrew build in releases.

## LGPL-only native build

[build-ffmpeg.sh](../scripts/build-ffmpeg.sh) compiles unmodified source with the Apple SDK, macOS 14 minimum, native architecture, shared FFmpeg libraries and `--disable-gpl --disable-nonfree --disable-version3 --disable-autodetect`. External package discovery is isolated, network support disabled, and no x264, x265, libfdk_aac or external codec libraries are enabled. Standalone x86 assembly is disabled to avoid an unpinned NASM dependency. Header padding allows safe install-name relocation. VideoToolbox is explicitly enabled; AudioToolbox is disabled so AAC uses the built-in `aac` encoder.

The UI must inspect bundled `ffmpeg -encoders` and expose only available encoders. Expected H.264/HEVC encoders are `h264_videotoolbox` and `hevc_videotoolbox`, with native `aac`. Native `mpeg4`, `prores_ks`, `alac` and PCM are useful alternatives. Registration does not prove hardware support for every profile, pixel format or machine: propagate runtime encoder errors. VideoToolbox controls are not x264/x265 CRF controls; never silently substitute GPL codecs.

## Bundle and loader layout

```text
MediaForge.app/Contents/Resources/
  Tools/ffmpeg
  Tools/ffprobe
  Tools/lib/libav*.dylib
  Tools/lib/libsw*.dylib
  Licenses/FFmpeg/
    ffmpeg-8.0.1.tar.xz
    COPYING.LGPLv2.1
    LICENSE.md
    config.mak
    config.h
    build-ffmpeg.sh
    ffmpeg.env
    CHANGES.txt
    runtime-license.txt
    encoders.txt
    buildconf.txt
```

Tools use `@executable_path/lib` references; dylibs use `@loader_path` references, with versioned symlinks preserved. After install-name edits, tools/libraries receive ad-hoc signatures before running on arm64. Only dependencies under `/System/Library` and `/usr/lib` or verified bundle-local paths are allowed. Swift calls subprocesses; FFmpeg is not statically linked into the Swift app. Resolve tools relative to `Bundle.main.resourceURL/Tools`. Missing bundled tools must not select an unrelated Homebrew installation.

## Corresponding source and notices

Every app contains the exact upstream source archive, LGPL text, FFmpeg license notices, configure records, build script/pin and explicit no-source-patches statement. Packaging publishes a separate architecture-specific corresponding-source ZIP alongside binaries. Binary install-name relocation is described above; there are no FFmpeg source changes. Source duplication intentionally supports offline app recipients and direct downloads.

The Media Forge license does not replace FFmpeg LGPL. About and download pages should say: “This software uses FFmpeg under LGPLv2.1 or later; corresponding source is included in the application and alongside its release assets.” Do not forbid reverse engineering needed to debug modifications to the LGPL component. Users can replace/rebuild these tools and libraries; modified bundles require local re-signing and no longer have the distributor notarization guarantee. These scripts introduce no restrictive EULA.

Consult [FFmpeg legal checklist](https://ffmpeg.org/legal.html) and [official downloads](https://ffmpeg.org/download.html). LGPL-only flags are not patent clearance or a blanket legal-compliance claim; release operators must maintain website attribution and distribution obligations.
