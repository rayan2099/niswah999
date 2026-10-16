#!/usr/bin/env python3
"""Regression coverage for select_release_env_secret.sh — the fix for the
release-workflow environment mismatch (a build labeled `staging` was
silently writing the real production .env, since routine-release.yml used
to read EMERGENCY_BUILD_ENV_FILE unconditionally for both choices).

Runs the real script as a subprocess with plain strings standing in for
the two secret values, so this proves the selection logic itself without
needing real secrets. Three properties are proven, matching the task's
own requirement: staging never consumes the production secret, production
never consumes the staging secret, and an absent required secret fails the
build rather than falling back to the other environment's value.
"""
import os
import subprocess
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "select_release_env_secret.sh")

PRODUCTION_MARKER = "PRODUCTION_ENV_CONTENTS_MARKER"
STAGING_MARKER = "STAGING_ENV_CONTENTS_MARKER"


def run(app_env, production_contents="", staging_contents=""):
    env = dict(os.environ)
    env["PRODUCTION_ENV_FILE_CONTENTS"] = production_contents
    env["STAGING_ENV_FILE_CONTENTS"] = staging_contents
    return subprocess.run(
        ["bash", SCRIPT, app_env],
        env=env,
        capture_output=True,
        text=True,
    )


class SelectReleaseEnvSecret(unittest.TestCase):
    def test_production_selects_production_secret(self):
        result = run(
            "production",
            production_contents=PRODUCTION_MARKER,
            staging_contents=STAGING_MARKER,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, PRODUCTION_MARKER)
        self.assertNotIn(STAGING_MARKER, result.stdout)

    def test_staging_selects_staging_secret(self):
        result = run(
            "staging",
            production_contents=PRODUCTION_MARKER,
            staging_contents=STAGING_MARKER,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, STAGING_MARKER)
        self.assertNotIn(PRODUCTION_MARKER, result.stdout)

    def test_staging_never_falls_back_to_production_secret_when_absent(self):
        # The exact defect this fix closes: staging must fail, never
        # silently build against the production secret.
        result = run("staging", production_contents=PRODUCTION_MARKER, staging_contents="")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(PRODUCTION_MARKER, result.stdout)
        self.assertIn("STAGING_BUILD_ENV_FILE", result.stderr)

    def test_production_never_falls_back_to_staging_secret_when_absent(self):
        result = run("production", production_contents="", staging_contents=STAGING_MARKER)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(STAGING_MARKER, result.stdout)
        self.assertIn("EMERGENCY_BUILD_ENV_FILE", result.stderr)

    def test_unknown_app_env_fails_rather_than_defaulting(self):
        result = run("qa", production_contents=PRODUCTION_MARKER, staging_contents=STAGING_MARKER)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(PRODUCTION_MARKER, result.stdout)
        self.assertNotIn(STAGING_MARKER, result.stdout)

    def test_missing_app_env_argument_fails(self):
        result = subprocess.run(
            ["bash", SCRIPT],
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
