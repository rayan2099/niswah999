#!/usr/bin/env python3
"""Regression guard for scripts/lib/supabase_management_api.py.

Added after a real incident (2026-10-02): fetching a staging Supabase
project's API keys and attempting to redact the response with a one-off
`sed` pattern left most of the legacy `anon`/`service_role` JWTs exposed
in plaintext tool output (the pattern only masked the first ~10
characters of each). These tests run the real extraction/storage code
against synthetic fixture data -- never real credentials -- and assert
that no secret value, or any contiguous fragment of one, ever reaches
anything printed, regardless of where in the value a future redaction
bug might truncate.
"""
import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest.mock import patch

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from scripts.lib.supabase_management_api import (  # noqa: E402
    Secret,
    extract_preferred_api_keys,
    fetch_and_store_api_keys,
    fetch_project_summary,
    upsert_env_file,
)

FAKE_ANON_JWT = (
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
    "FAKEPAYLOADSEGMENTABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789."
    "FAKESIGNATURESEGMENTzyxwvutsrqponmlkjihgfedcba9876543210"
)
FAKE_SERVICE_ROLE_JWT = (
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
    "FAKESERVICEROLEPAYLOAD9876543210ZYXWVUTSRQPONMLKJIHGFED."
    "FAKESERVICEROLESIGNATUREabcdefghijklmnopqrstuvwxyz0123456789"
)
FAKE_PUBLISHABLE_KEY = "sb_publishable_FAKEKEYVALUE1234567890abcdefghijklmnop"
FAKE_SECRET_KEY = "sb_secret_FAKESECRETVALUE0987654321zyxwvutsrqponmlkji"

FAKE_RAW_API_KEYS_RESPONSE = [
    {"name": "anon", "api_key": FAKE_ANON_JWT},
    {"name": "service_role", "api_key": FAKE_SERVICE_ROLE_JWT},
    {"type": "publishable", "api_key": FAKE_PUBLISHABLE_KEY},
    {"type": "secret", "api_key": FAKE_SECRET_KEY},
]


def _secret_fragments(value, chunk_len=8):
    """Substrings sampled across the whole value, not just its start --
    catches a redaction bug that masks only the first N characters and
    leaves the remainder exposed, which is exactly what happened in the
    real incident this test file guards against."""
    return [value[i:i + chunk_len] for i in range(0, len(value), chunk_len) if value[i:i + chunk_len]]


class SecretWrapperTest(unittest.TestCase):
    def test_repr_and_str_never_reveal_the_value(self):
        secret = Secret(FAKE_SERVICE_ROLE_JWT)
        self.assertNotIn(FAKE_SERVICE_ROLE_JWT, repr(secret))
        self.assertNotIn(FAKE_SERVICE_ROLE_JWT, str(secret))
        self.assertEqual(secret.reveal(), FAKE_SERVICE_ROLE_JWT)

    def test_no_fragment_of_the_value_survives_fstring_interpolation(self):
        secret = Secret(FAKE_SERVICE_ROLE_JWT)
        rendered = f"token={secret!r} again={secret}"
        for fragment in _secret_fragments(FAKE_SERVICE_ROLE_JWT):
            self.assertNotIn(fragment, rendered)


class ExtractPreferredApiKeysTest(unittest.TestCase):
    def test_prefers_new_publishable_and_secret_keys_over_legacy(self):
        result = extract_preferred_api_keys(FAKE_RAW_API_KEYS_RESPONSE)
        self.assertEqual(result["anon_slot"]["type"], "publishable")
        self.assertEqual(result["anon_slot"]["value"].reveal(), FAKE_PUBLISHABLE_KEY)
        self.assertEqual(result["service_slot"]["type"], "secret")
        self.assertEqual(result["service_slot"]["value"].reveal(), FAKE_SECRET_KEY)

    def test_falls_back_to_legacy_keys_when_new_ones_absent(self):
        raw = [
            {"name": "anon", "api_key": FAKE_ANON_JWT},
            {"name": "service_role", "api_key": FAKE_SERVICE_ROLE_JWT},
        ]
        result = extract_preferred_api_keys(raw)
        self.assertEqual(result["anon_slot"]["type"], "anon")
        self.assertEqual(result["anon_slot"]["value"].reveal(), FAKE_ANON_JWT)
        self.assertEqual(result["service_slot"]["type"], "service_role")
        self.assertEqual(result["service_slot"]["value"].reveal(), FAKE_SERVICE_ROLE_JWT)

    def test_rejects_unexpected_shape_instead_of_guessing(self):
        with self.assertRaises(ValueError):
            extract_preferred_api_keys([{"no_api_key_field": True}])
        with self.assertRaises(ValueError):
            extract_preferred_api_keys("not-a-list")
        with self.assertRaises(ValueError):
            extract_preferred_api_keys([{"api_key": "x"}])  # missing type/name


class UpsertEnvFileTest(unittest.TestCase):
    def test_replaces_existing_key_in_place_without_duplicating(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / ".env"
            path.write_text("EXISTING=old\nOTHER=unchanged\n", encoding="utf-8")
            written = upsert_env_file(str(path), {"EXISTING": Secret("new-value")})
            content = path.read_text(encoding="utf-8")
            self.assertEqual(written, ["EXISTING"])
            self.assertIn("EXISTING=new-value", content)
            self.assertIn("OTHER=unchanged", content)
            self.assertEqual(content.count("EXISTING="), 1)

    def test_appends_new_key_when_absent(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / ".env"
            path.write_text("OTHER=unchanged\n", encoding="utf-8")
            upsert_env_file(str(path), {"NEWKEY": Secret("value")})
            self.assertIn("NEWKEY=value", path.read_text(encoding="utf-8"))

    def test_creates_file_when_it_does_not_exist_yet(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "new.env"
            upsert_env_file(str(path), {"KEY": Secret("value")})
            self.assertIn("KEY=value", path.read_text(encoding="utf-8"))


class EndToEndRedactionRegressionTest(unittest.TestCase):
    """The core regression guard: runs the real fetch-and-store path
    against a mocked HTTP layer returning a fixture shaped like the real
    incident's response, and asserts none of the four fake secrets --
    in full or in any contiguous fragment -- ever reaches stdout/stderr,
    while confirming the correct (new-format) values really do land in
    their destination files."""

    def _run_with_fixture(self):
        with tempfile.TemporaryDirectory() as tmp:
            functions_env = Path(tmp) / "functions.env"
            app_env = Path(tmp) / "app.env"
            functions_env.write_text("", encoding="utf-8")
            app_env.write_text("", encoding="utf-8")

            out, err = io.StringIO(), io.StringIO()
            with patch(
                "scripts.lib.supabase_management_api._http_get",
                return_value=FAKE_RAW_API_KEYS_RESPONSE,
            ):
                with redirect_stdout(out), redirect_stderr(err):
                    result = fetch_and_store_api_keys(
                        "fake-ref", Secret("fake-token"), str(functions_env), str(app_env)
                    )
            captured = out.getvalue() + err.getvalue()
            functions_env_content = functions_env.read_text(encoding="utf-8")
            app_env_content = app_env.read_text(encoding="utf-8")
            return result, captured, functions_env_content, app_env_content

    def test_no_secret_value_or_fragment_reaches_output(self):
        _, captured, _, _ = self._run_with_fixture()
        for secret_value in (FAKE_ANON_JWT, FAKE_SERVICE_ROLE_JWT, FAKE_PUBLISHABLE_KEY, FAKE_SECRET_KEY):
            self.assertNotIn(secret_value, captured)
            for fragment in _secret_fragments(secret_value):
                self.assertNotIn(fragment, captured, f"fragment {fragment!r} of a secret leaked into output")

    def test_preferred_new_format_values_land_in_their_destination_files(self):
        _, _, functions_env_content, app_env_content = self._run_with_fixture()
        self.assertIn(FAKE_SECRET_KEY, functions_env_content)
        self.assertIn(FAKE_PUBLISHABLE_KEY, app_env_content)

    def test_superseded_legacy_values_are_never_written_anywhere(self):
        _, _, functions_env_content, app_env_content = self._run_with_fixture()
        self.assertNotIn(FAKE_ANON_JWT, functions_env_content)
        self.assertNotIn(FAKE_ANON_JWT, app_env_content)
        self.assertNotIn(FAKE_SERVICE_ROLE_JWT, functions_env_content)
        self.assertNotIn(FAKE_SERVICE_ROLE_JWT, app_env_content)

    def test_only_safe_identifiers_are_returned_for_logging(self):
        result, _, _, _ = self._run_with_fixture()
        self.assertEqual(result["anon_slot_key_type"], "publishable")
        self.assertEqual(result["service_slot_key_type"], "secret")
        self.assertEqual(
            sorted(result["written_vars"]),
            sorted(["STAGING_SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_ANON_KEY"]),
        )


class ProjectSummaryAllowlistTest(unittest.TestCase):
    def test_only_allowlisted_fields_survive_even_if_response_has_extra_fields(self):
        fake_response = {
            "id": "fake-ref",
            "name": "Fake Staging",
            "region": "ap-southeast-1",
            "status": "ACTIVE_HEALTHY",
            "jwt_secret": "SHOULD_NEVER_SURVIVE_EXTRACTION",
            "db_pass_hint": "SHOULD_NEVER_SURVIVE_EXTRACTION_EITHER",
        }
        with patch("scripts.lib.supabase_management_api._http_get", return_value=fake_response):
            summary = fetch_project_summary("fake-ref", Secret("fake-token"))
        self.assertEqual(
            summary,
            {"ref": "fake-ref", "name": "Fake Staging", "region": "ap-southeast-1", "status": "ACTIVE_HEALTHY"},
        )
        self.assertNotIn("jwt_secret", summary)
        self.assertNotIn("SHOULD_NEVER_SURVIVE_EXTRACTION", json.dumps(summary))


if __name__ == "__main__":
    unittest.main()
