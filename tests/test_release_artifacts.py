import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest


SPEC = importlib.util.spec_from_file_location("verify_release", Path(__file__).resolve().parents[1] / "scripts/verify-release.py")
RELEASE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RELEASE)


class ReleaseArtifactTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name)
        self.version = "v1.2.3"
        for arch, platform in (("arm64", "AppleSilicon"), ("x86_64", "Intel")):
            stem = f"MediaForge-{self.version}-{arch}"
            contents = {f"MediaForge-macOS-14+-{platform}.zip": b"zip",
                        f"MediaForge-macOS-14+-{platform}.dmg": b"dmg",
                        f"{stem}-FFmpeg-source.zip": b"source",
                        f"{stem}-status.txt": f"architecture={arch}\nversion={self.version}\nsigning=ad-hoc\nnotarized=false\n".encode()}
            for name, content in contents.items():
                (self.root / name).write_bytes(content)
            self.write_manifest(arch, contents)

    def write_manifest(self, arch, contents):
        (self.root / f"MediaForge-{self.version}-{arch}-SHA256SUMS.txt").write_text(
            "".join(f"{hashlib.sha256(content).hexdigest()}  {name}\n" for name, content in contents.items()))

    def test_metadata_rejects_symlinks_and_oversized_files(self):
        manifest = self.root / "MediaForge-v1.2.3-arm64-SHA256SUMS.txt"
        target = self.root / "manifest-target"
        target.write_bytes(manifest.read_bytes())
        manifest.unlink()
        manifest.symlink_to(target)
        with self.assertRaises(ValueError):
            RELEASE.verify_release(self.root, self.version)
        manifest.unlink()
        manifest.write_bytes(b"x" * 65537)
        with self.assertRaises(ValueError):
            RELEASE.verify_release(self.root, self.version)

    def test_wildcard_upload_cannot_include_unverified_assets(self):
        (self.root / "MediaForge-old-release.zip").write_bytes(b"stale")
        with self.assertRaisesRegex(ValueError, "Unverified release assets"):
            RELEASE.verify_release(self.root, self.version)

    def test_complete_sets_pass(self):
        RELEASE.verify_release(self.root, self.version)

    def test_empty_partial_or_duplicate_manifests_fail(self):
        manifest = self.root / "MediaForge-v1.2.3-arm64-SHA256SUMS.txt"
        original = manifest.read_text()
        for content in ("", original.splitlines()[0] + "\n", original + original):
            with self.subTest(content=content):
                manifest.write_text(content)
                with self.assertRaises(ValueError):
                    RELEASE.verify_release(self.root, self.version)

    def test_modified_and_symlink_artifacts_fail(self):
        artifact = self.root / "MediaForge-macOS-14+-Intel.zip"
        artifact.write_bytes(b"tampered")
        with self.assertRaises(ValueError):
            RELEASE.verify_release(self.root, self.version)
        artifact.unlink()
        target = self.root / "other"
        target.write_bytes(b"zip")
        artifact.symlink_to(target)
        with self.assertRaises(ValueError):
            RELEASE.verify_release(self.root, self.version)

    def test_status_must_match_and_notarization_cannot_be_ad_hoc(self):
        name = "MediaForge-v1.2.3-arm64-status.txt"
        original = (self.root / name).read_text()
        for text in (original.replace("arm64", "x86_64"), original.replace("v1.2.3", "v1.2.4"),
                     original.replace("notarized=false", "notarized=true"), original + "signing=developer-id\n"):
            with self.subTest(text=text):
                (self.root / name).write_text(text)
                contents = {path.name: path.read_bytes() for path in self.root.iterdir()
                            if path.name in {"MediaForge-macOS-14+-AppleSilicon.zip",
                                             "MediaForge-macOS-14+-AppleSilicon.dmg",
                                             "MediaForge-v1.2.3-arm64-FFmpeg-source.zip", name}}
                self.write_manifest("arm64", contents)
                with self.assertRaises(ValueError):
                    RELEASE.verify_release(self.root, self.version)

    def test_manifest_cannot_reference_outside_directory(self):
        manifest = self.root / "MediaForge-v1.2.3-arm64-SHA256SUMS.txt"
        manifest.write_text("a" * 64 + "  ../external\n")
        with self.assertRaises(ValueError):
            RELEASE.verify_release(self.root, self.version)
