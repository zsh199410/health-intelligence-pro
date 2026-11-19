#!/usr/bin/env python3
"""Regression checks for the read-only bundle identifier audit.

Uses temporary fixture projects; never reads signing files or real devices.
Run: python3 -m unittest discover -s scripts/tests -p 'test_bundle_audit.py'
"""
import pathlib
import subprocess
import sys
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "audit_bundle_identifiers.py"


def project(iphone="app.example.health", watch="app.example.health.watchkitapp",
            companion="app.example.health"):
    return f"""name: HealthIntelligence
targets:
  HealthIntelligence:
    type: application
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: {iphone}
  HealthWatch:
    type: application.watchapp2
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: {watch}
        INFOPLIST_KEY_WKCompanionAppBundleIdentifier: {companion}
"""


class BundleAuditTests(unittest.TestCase):
    def run_audit(self, config):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            (root / "scripts").mkdir()
            (root / "project.yml").write_text(config, encoding="utf-8")
            (root / "scripts" / SCRIPT.name).write_bytes(SCRIPT.read_bytes())
            return subprocess.run(
                [sys.executable, str(root / "scripts" / SCRIPT.name)],
                capture_output=True, text=True, check=False,
            )

    def test_consistent_identifiers_pass(self):
        result = self.run_audit(project())
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("PASS:", result.stdout)

    def test_wrong_companion_is_rejected(self):
        result = self.run_audit(project(companion="com.example.other"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("WKCompanionAppBundleIdentifier", result.stderr)

    def test_watch_outside_parent_namespace_is_rejected(self):
        result = self.run_audit(project(watch="com.example.watch"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Watch PRODUCT_BUNDLE_IDENTIFIER", result.stderr)

    def test_missing_watch_target_is_rejected(self):
        result = self.run_audit(project().replace("  HealthWatch:", "  OtherWatch:"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Missing target HealthWatch", result.stderr)


if __name__ == "__main__":
    unittest.main()
