import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("release_version", ROOT / "scripts/release-version.py")
VERSION = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERSION)


class ReleaseVersionTests(unittest.TestCase):
    def test_tag_and_prerelease_marketing_versions(self):
        for version in ("2.3.4", "v2.3.4", "v2.3.4-rc.1", "2.3.4-dev"):
            self.assertEqual(VERSION.marketing_version(version), "2.3.4")

    def test_rejects_malformed_or_shell_versions(self):
        for version in ("", "1.2", "01.2.3", "v1.2.3-", "v1.2.3..rc", "1.2.3;touch x", "1.2.3\n"):
            with self.subTest(version=version), self.assertRaises(ValueError):
                VERSION.marketing_version(version)

    def test_packaging_rejects_wrong_application_version(self):
        with tempfile.TemporaryDirectory() as folder:
            plist = Path(folder) / "Info.plist"
            plist.write_bytes(plistlib.dumps({"CFBundleShortVersionString": "2.3.4"}))
            self.assertEqual(VERSION.verify_app_version(plist, "v2.3.4-rc.1"), "2.3.4")
            with self.assertRaisesRegex(ValueError, "does not match"):
                VERSION.verify_app_version(plist, "v2.3.5")
            plist.write_bytes(plistlib.dumps({}))
            with self.assertRaises(ValueError):
                VERSION.verify_app_version(plist, "v2.3.4")
