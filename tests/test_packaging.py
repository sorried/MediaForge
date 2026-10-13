import importlib.util
from pathlib import Path
import struct
import plistlib
import tempfile
from unittest.mock import patch
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("verify_bundle", ROOT / "scripts/verify-bundle.py")
VERIFY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERIFY)


class PackagingTests(unittest.TestCase):
    def test_dependency_paths_use_main_executable_not_dylib_directory(self):
        with tempfile.TemporaryDirectory() as folder:
            contents = Path(folder) / "Contents"
            executable = contents / "MacOS/MediaForge"
            binary = contents / "Resources/Tools/lib/libavcodec.dylib"
            executable.parent.mkdir(parents=True)
            binary.parent.mkdir(parents=True)
            binary.write_bytes(b"library")
            tool = contents / "Resources/Tools/ffmpeg"
            self.assertEqual(VERIFY.resolve_dependency("@executable_path/lib/libavcodec.dylib", binary, tool, contents).resolve(), binary)
            dependency = "@executable_path/../Resources/Tools/lib/libavcodec.dylib"
            self.assertEqual(VERIFY.resolve_dependency(dependency, binary, executable, contents).resolve(), binary)
            self.assertEqual(VERIFY.resolve_dependency("@loader_path/libavcodec.dylib", binary, executable, contents), binary)
            with self.assertRaisesRegex(SystemExit, "Unresolved bundle dependency"):
                VERIFY.resolve_dependency("@loader_path/../../../../escape", binary, executable, contents)
            with self.assertRaisesRegex(SystemExit, "Non-system or unresolved"):
                VERIFY.resolve_dependency("/opt/homebrew/lib/libavcodec.dylib", binary, executable, contents)

    def test_engine_versions_must_match_source_pin_exactly(self):
        for tool in ("ffmpeg", "ffprobe"):
            VERIFY.verify_engine_version(f"{tool} version 8.0.1 Copyright FFmpeg", tool, "8.0.1")
            for actual in ("7.0.2", "8.0.10", "8.0.1-custom", "N-12345", ""):
                with self.subTest(tool=tool, actual=actual), self.assertRaisesRegex(SystemExit, "pinned version"):
                    VERIFY.verify_engine_version(f"{tool} version {actual} Copyright FFmpeg", tool, "8.0.1")
        with self.assertRaises(SystemExit):
            VERIFY.verify_engine_version("ffmpeg version 8.0.1", "ffprobe", "8.0.1")

    def test_license_flags_are_tokens_not_substrings(self):
        flags = "--disable-gpl --disable-nonfree --disable-version3 --disable-autodetect --disable-network"
        VERIFY.verify_license_configuration("configuration:\n  " + flags + " --prefix='/path with spaces'")
        for bad in (flags.replace("--disable-gpl", "--disable-gpl-fake"),
                    flags + " --enable-gpl", flags + " --enable-libx264", flags + " --enable-nonfree=yes",
                    flags.replace("--disable-network", ""), flags + " --enable-network"):
            with self.subTest(configuration=bad), self.assertRaises(SystemExit):
                VERIFY.verify_license_configuration(bad)

    def test_deployment_platform_must_be_macos(self):
        for platform in ("1", "macos", "MACOS"):
            VERIFY.verify_deployment_platform(f"cmd LC_BUILD_VERSION\n platform {platform}\n minos 14.0\n", "app")
        VERIFY.verify_deployment_platform("cmd LC_VERSION_MIN_MACOSX\n version 14.0\n", "app")
        for platform in ("2", "ios", "7", "macCatalyst", ""):
            with self.subTest(platform=platform), self.assertRaises(SystemExit):
                VERIFY.verify_deployment_platform(f"cmd LC_BUILD_VERSION\n platform {platform}\n minos 14.0\n", "app")

    def test_each_deployment_command_needs_a_valid_minimum(self):
        valid = "Load command 1\ncmd LC_BUILD_VERSION\nplatform 1\nminos 14.0\n"
        for malformed in ("cmd LC_BUILD_VERSION\nplatform 1\nsdk 14.0\n",
                          "cmd LC_VERSION_MIN_MACOSX\nsdk 14.0\n",
                          "cmd LC_BUILD_VERSION\nplatform 1\nminos 15.0\n"):
            with self.subTest(command=malformed), self.assertRaises(SystemExit):
                VERIFY.verify_deployment_platform(valid + "Load command 2\n" + malformed, "app")

    def test_version_comparison_normalizes_components(self):
        self.assertEqual(VERIFY.version_tuple("14"), (14, 0, 0))
        self.assertEqual(VERIFY.version_tuple("14.0"), (14, 0, 0))
        self.assertGreater(VERIFY.version_tuple("14.1"), (14, 0, 0))
        self.assertGreater(VERIFY.version_tuple("26.0"), (14, 0, 0))

    def test_rejects_invalid_version(self):
        with self.assertRaises(ValueError):
            VERIFY.version_tuple("not-a-version")

    def test_verification_subprocess_has_deadline(self):
        with patch.object(VERIFY.subprocess, "check_output", return_value="verified") as command:
            self.assertEqual(VERIFY.output("ffprobe", "-version"), "verified")
            command.assert_called_once_with(("ffprobe", "-version"), text=True, stderr=VERIFY.subprocess.STDOUT, timeout=60)

    def test_require_fails_closed(self):
        VERIFY.require(True, "unused")
        with self.assertRaisesRegex(SystemExit, "missing binary"):
            VERIFY.require(False, "missing binary")

    def test_native_validation_does_not_succeed_on_linux(self):
        import sys
        if sys.platform == "darwin":
            self.skipTest("Linux-only guard test")
        with self.assertRaisesRegex(SystemExit, "requires macOS"):
            VERIFY.verify(ROOT, "arm64")

    def test_shared_xcode_scheme_is_valid_xml(self):
        import xml.etree.ElementTree as ET
        scheme = ROOT / "MediaForge.xcodeproj/xcshareddata/xcschemes/MediaForge.xcscheme"
        tree = ET.parse(scheme)
        self.assertEqual(tree.getroot().tag, "Scheme")
        self.assertIsNotNone(tree.find("BuildAction"))

    def test_bundle_rejects_wrong_architecture_and_newer_os(self):
        with tempfile.TemporaryDirectory() as folder:
            app = Path(folder) / "MediaForge.app"
            executable = app / "Contents/MacOS/MediaForge"
            tools = app / "Contents/Resources/Tools"
            executable.parent.mkdir(parents=True)
            tools.mkdir(parents=True)
            for binary in (executable, tools / "ffmpeg", tools / "ffprobe"):
                binary.write_bytes(b"mock Mach-O")
                binary.chmod(0o755)
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
                "LSMinimumSystemVersion": "14.0", "CFBundleExecutable": "MediaForge"
            }))

            def wrong_architecture(*command):
                if command[0] == "file":
                    return "Mach-O 64-bit executable"
                if command[0] == "lipo":
                    return "x86_64"
                raise AssertionError(command)

            with patch.object(VERIFY.sys, "platform", "darwin"), patch.object(VERIFY, "output", side_effect=wrong_architecture):
                with self.assertRaisesRegex(SystemExit, "Incorrect architecture"):
                    VERIFY.verify(app, "arm64")

            def newer_os(*command):
                if command[0] == "file":
                    return "Mach-O 64-bit executable"
                if command[0] == "lipo":
                    return "arm64"
                if command[0] == "otool":
                    return "Load command 1\ncmd LC_BUILD_VERSION\nplatform 1\nminos 15.0\nsdk 26.0\n"
                raise AssertionError(command)

            with patch.object(VERIFY.sys, "platform", "darwin"), patch.object(VERIFY, "output", side_effect=newer_os):
                with self.assertRaisesRegex(SystemExit, "Deployment target exceeds"):
                    VERIFY.verify(app, "arm64")

    def test_bundle_rejects_escaping_symlink(self):
        with tempfile.TemporaryDirectory() as folder:
            app = Path(folder) / "MediaForge.app"
            executable = app / "Contents/MacOS/MediaForge"
            tools = app / "Contents/Resources/Tools"
            executable.parent.mkdir(parents=True)
            tools.mkdir(parents=True)
            for binary in (executable, tools / "ffmpeg", tools / "ffprobe"):
                binary.write_bytes(b"mock Mach-O")
                binary.chmod(0o755)
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
                "LSMinimumSystemVersion": "14.0", "CFBundleExecutable": "MediaForge"
            }))
            (tools / "escape").symlink_to(Path(folder))
            with patch.object(VERIFY.sys, "platform", "darwin"), patch.object(VERIFY, "output", return_value="Mach-O"):
                with self.assertRaisesRegex(SystemExit, "Escaping symlink"):
                    VERIFY.verify(app, "arm64")

    def test_encoder_gate_uses_names_not_descriptions(self):
        names = ("aac", "h264_videotoolbox", "hevc_videotoolbox", "png", "mjpeg")
        encoders = "\n".join(f" V..... {name} Encoder description" for name in names)
        VERIFY.verify_encoders(encoders)
        for name in names:
            with self.subTest(encoder=name), self.assertRaises(SystemExit):
                VERIFY.verify_encoders(encoders.replace(f" {name} Encoder", f" other description {name} Encoder"))
        with self.assertRaisesRegex(SystemExit, "GPL encoder"):
            VERIFY.verify_encoders(encoders + "\n V..... libx264 GPL encoder\n")
        VERIFY.verify_encoders(encoders + "\n V..... unrelated description mentioning libx264\n")

    def test_bundle_gate_requires_output_verification_components(self):
        decoders = "\n".join(f" V..... {name} Decoder description" for name in ("h264", "hevc", "aac", "png", "mjpeg", "mpeg4"))
        VERIFY.verify_decode_components(decoders, " E null Null output\n")
        for name in ("h264", "hevc", "aac", "png", "mjpeg", "mpeg4"):
            with self.subTest(decoder=name), self.assertRaises(SystemExit):
                VERIFY.verify_decode_components(decoders.replace(f" {name} Decoder", " other Decoder"), " E null output\n")
        with self.assertRaises(SystemExit):
            VERIFY.verify_decode_components(decoders, " E other description null output\n")
        with self.assertRaises(SystemExit):
            VERIFY.verify_decode_components("description h264 hevc aac png mjpeg mpeg4 ", " E null output\n")

    def test_verification_harness_is_excluded_from_app_target(self):
        project = (ROOT / "MediaForge.xcodeproj/project.pbxproj").read_text()
        self.assertIn("membershipExceptions = (generate_icon.py, __pycache__, Verification)", project)
        harness = (ROOT / "Resources/Verification/ImportScannerChecks.swift").read_text()
        self.assertIn("@main", harness)

    def test_native_logs_preserve_failure_status(self):
        script = (ROOT / "scripts/build-app.sh").read_text()
        self.assertIn("set -euo pipefail", script)
        self.assertIn('build 2>&1 | tee "$ROOT/build/logs/$ARCH/xcodebuild.log"', script)
        self.assertIn('swift test --parallel 2>&1 | tee "$ROOT/build/logs/$ARCH/swift-tests.log"', script)
        workflow = (ROOT / ".github/workflows/build.yml").read_text()
        diagnostics = workflow.split("      - name: Preserve native build diagnostics\n", 1)[1].split("      - name:", 1)[0]
        self.assertIn("if: always()", diagnostics)
        self.assertIn("name: native-diagnostics-${{ matrix.arch }}", diagnostics)

    def test_review_branch_build_does_not_enable_release(self):
        workflow = (ROOT / ".github/workflows/build.yml").read_text()
        self.assertIn("branches: [main, mediaforge/native-verification]", workflow)
        release = workflow.split("  release:\n", 1)[1]
        self.assertIn("if: startsWith(github.ref, 'refs/tags/v')", release)

    def test_isolated_engine_explicitly_enables_system_zlib(self):
        script = (ROOT / "scripts/build-ffmpeg.sh").read_text()
        self.assertIn("--disable-autodetect", script)
        self.assertIn("--enable-zlib", script)
        self.assertIn("--enable-videotoolbox", script)

    def test_icon_png_integrity(self):
        icon = (ROOT / "Resources/AppIcon.png").read_bytes()
        self.assertEqual(icon[:8], b"\x89PNG\r\n\x1a\n")
        offset = 8
        compressed = bytearray()
        width = height = 0
        while offset < len(icon):
            length = struct.unpack(">I", icon[offset:offset + 4])[0]
            kind = icon[offset + 4:offset + 8]
            content = icon[offset + 8:offset + 8 + length]
            crc = struct.unpack(">I", icon[offset + 8 + length:offset + 12 + length])[0]
            self.assertEqual(crc, zlib.crc32(kind + content) & 0xffffffff)
            if kind == b"IHDR":
                width, height = struct.unpack(">II", content[:8])
            if kind == b"IDAT":
                compressed.extend(content)
            offset += length + 12
        self.assertEqual((width, height), (1024, 1024))
        self.assertEqual(len(zlib.decompress(compressed)), height * (1 + width * 4))


if __name__ == "__main__":
    unittest.main()
