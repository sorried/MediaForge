import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SECRETS = ("APPLE_CERTIFICATE_BASE64", "APPLE_CERTIFICATE_PASSWORD", "APPLE_SIGNING_IDENTITY",
           "APPLE_ID", "APPLE_TEAM_ID", "APPLE_APP_PASSWORD")


class SigningConfigurationTests(unittest.TestCase):
    def run_configuration(self, supplied):
        with tempfile.TemporaryDirectory() as folder:
            environment = {key: value for key, value in os.environ.items() if key not in SECRETS}
            environment.update(RUNNER_TEMP=folder, GITHUB_ENV=str(Path(folder) / "environment"))
            environment.update(supplied)
            return subprocess.run(["bash", str(ROOT / "scripts/setup-signing.sh")], env=environment,
                                  capture_output=True, text=True, timeout=5)

    def test_no_credentials_explicitly_uses_ad_hoc(self):
        result = self.run_configuration({})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("ad-hoc signed, not notarized", result.stdout)

    def test_partial_notary_credentials_fail_before_certificate_processing(self):
        signing = {"APPLE_CERTIFICATE_BASE64": "invalid-certificate",
                   "APPLE_CERTIFICATE_PASSWORD": "password",
                   "APPLE_SIGNING_IDENTITY": "Developer ID Application: Test"}
        for notary in ({"APPLE_ID": "test@example.invalid"},
                       {"APPLE_TEAM_ID": "TEAM"},
                       {"APPLE_APP_PASSWORD": "password"},
                       {"APPLE_ID": "test@example.invalid", "APPLE_TEAM_ID": "TEAM"}):
            with self.subTest(notary=tuple(notary)):
                result = self.run_configuration({**signing, **notary})
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("required", result.stderr.lower())
                self.assertNotIn("base64", result.stderr)
                self.assertNotIn("add-mask", result.stdout)

    def test_any_partial_credential_configuration_fails(self):
        for secret in SECRETS:
            with self.subTest(secret=secret):
                result = self.run_configuration({secret: "test-placeholder"})
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("packaging will be ad-hoc", result.stdout)
                self.assertIn("required", result.stderr.lower())
