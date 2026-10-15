#!/usr/bin/env python3
"""Tests for the acceptance verifier's full-catalogue and shard modes."""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

VERIFIER = Path(__file__).with_name("verify_acceptance_results.py")


def run(results: Path, tests: Path, only=None) -> int:
    cmd = [sys.executable, str(VERIFIER), str(results), str(tests)]
    if only is not None:
        cmd += ["--only", only]
    return subprocess.run(cmd, capture_output=True, text=True).returncode


class VerifierTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.results, self.tests = root / "results", root / "integration_test"
        self.results.mkdir()
        self.tests.mkdir()
        for name in ("pA_test", "pB_test", "pC_test"):
            (self.tests / f"{name}.dart").write_text("")

    def tearDown(self):
        self.tmp.cleanup()

    def put(self, name, status):
        (self.results / f"{name}.json").write_text(json.dumps({"status": status}))

    def test_full_catalogue_needs_every_persona(self):
        self.put("pA_test", "PASS")
        self.put("pB_test", "PASS")
        self.assertEqual(run(self.results, self.tests), 1)  # pC missing
        self.put("pC_test", "PASS")
        self.assertEqual(run(self.results, self.tests), 0)

    def test_shard_is_judged_on_its_own_personas_only(self):
        self.put("pA_test", "PASS")
        self.put("pB_test", "PASS")
        self.assertEqual(run(self.results, self.tests, "pA pB"), 0)

    def test_shard_fails_on_missing_failed_or_blocked(self):
        self.put("pA_test", "PASS")
        self.assertEqual(run(self.results, self.tests, "pA pC"), 1)  # pC missing
        self.put("pC_test", "BLOCKED")
        self.assertEqual(run(self.results, self.tests, "pA pC"), 1)
        self.put("pC_test", "FAIL")
        self.assertEqual(run(self.results, self.tests, "pA pC"), 1)

    def test_shard_selection_matching_nothing_is_an_error_not_a_pass(self):
        self.assertEqual(run(self.results, self.tests, "pZ"), 1)

    def test_shard_pass_never_implies_catalogue_pass(self):
        self.put("pA_test", "PASS")
        self.assertEqual(run(self.results, self.tests, "pA"), 0)
        self.assertEqual(run(self.results, self.tests), 1)


if __name__ == "__main__":
    unittest.main()
