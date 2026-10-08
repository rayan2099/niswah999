#!/usr/bin/env python3
"""Runs the shared kill-switch vectors against the host-side checker."""
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import assert_test_backend as gate  # noqa: E402

with open(os.path.join(HERE, "..", "test", "fixtures", "backend_gate_vectors.json")) as f:
    VECTORS = json.load(f)["vectors"]


class SharedVectors(unittest.TestCase):
    def test_vectors(self):
        for v in VECTORS:
            with self.subTest(v["name"]):
                allowed, host, reason = gate.evaluate_env(
                    v["env"], set(v.get("approved_hosts", []))
                )
                self.assertEqual(allowed, v["expected"] == "allowed", f"{host} {reason}")

    def test_cli_exit_codes_and_no_secrets_logged(self):
        def run(env_text):
            with tempfile.NamedTemporaryFile("w", suffix=".env", delete=False) as f:
                f.write(env_text)
            try:
                return subprocess.run(
                    [sys.executable, os.path.join(HERE, "assert_test_backend.py"), "--env-file", f.name],
                    capture_output=True, text=True,
                )
            finally:
                os.unlink(f.name)

        ok = run("SUPABASE_URL=http://127.0.0.1:54321\nSUPABASE_ANON_KEY=LOCALKEY\n")
        self.assertEqual(ok.returncode, 0)
        prod = run(
            "APP_ENV=development\nSUPABASE_URL=https://jkmjobvxfrmuwafczvtw.supabase.co\n"
            "SUPABASE_ANON_KEY=SUPERSECRETKEY\n"
        )
        self.assertEqual(prod.returncode, 3)
        self.assertNotIn("SUPERSECRETKEY", prod.stdout + prod.stderr)
        self.assertIn("BLOCKED", prod.stderr)
        missing = subprocess.run(
            [sys.executable, os.path.join(HERE, "assert_test_backend.py"), "--env-file", "/nonexistent/.env"],
            capture_output=True, text=True,
        )
        self.assertEqual(missing.returncode, 3)


if __name__ == "__main__":
    unittest.main()
