#!/usr/bin/env python3
"""Live driver: verifies the target project is Niswah Staging, then
fetches its metadata and NEW-FORMAT (publishable/secret) API keys via
the Supabase Management API and writes them directly to their
gitignored destination files. Never prints a secret value.

Run manually: `python3 scripts/provision_staging_secrets.py`

Safety invariants this script enforces (see
scripts/lib/supabase_management_api.py and
scripts/test_secret_redaction.py for the regression guard):
  - Refuses to proceed unless the fetched project identity matches the
    known Niswah Staging ref/name exactly, and explicitly refuses if it
    ever matches the production ref.
  - allow_legacy_fallback=False: never retrieves the legacy anon/
    service_role keys, even if the API still returns them -- fails
    loudly instead.
  - SUPABASE_ACCESS_TOKEN (read from supabase/functions/.env) is a local
    Management API tooling credential only. It is never written to any
    destination this script targets and must never be deployed as an
    Edge Function runtime secret.
"""
from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from scripts.lib.supabase_management_api import (  # noqa: E402
    Secret,
    build_connection_strings,
    fetch_and_store_api_keys,
    fetch_project_summary,
    load_access_token,
    read_plain_env_var,
    upsert_env_file,
)

FUNCTIONS_ENV = REPO_ROOT / "supabase" / "functions" / ".env"
APP_STAGING_ENV = REPO_ROOT / ".env.staging"

EXPECTED_STAGING_REF = "ovgvevzrcefloitgcsia"
EXPECTED_STAGING_NAME = "Niswah Staging"
PRODUCTION_REF = "jkmjobvxfrmuwafczvtw"


def assert_is_staging_project(summary: dict) -> None:
    if summary.get("ref") == PRODUCTION_REF:
        raise RuntimeError(
            "REFUSING TO PROCEED: fetched project identity matches the PRODUCTION ref. "
            "Stopping -- production must never be the target of this script."
        )
    if summary.get("ref") != EXPECTED_STAGING_REF or summary.get("name") != EXPECTED_STAGING_NAME:
        raise RuntimeError(
            "REFUSING TO PROCEED: project identity does not match known Niswah Staging "
            f"(expected ref={EXPECTED_STAGING_REF!r} name={EXPECTED_STAGING_NAME!r}; "
            f"got ref={summary.get('ref')!r} name={summary.get('name')!r})."
        )


def main() -> None:
    ref = read_plain_env_var(str(FUNCTIONS_ENV), "STAGING_PROJECT_REF")
    token = load_access_token(str(FUNCTIONS_ENV))

    summary = fetch_project_summary(ref, token)
    assert_is_staging_project(summary)
    print(
        f"==> Verified target project: ref={summary['ref']} name={summary['name']!r} "
        f"region={summary['region']} status={summary['status']}"
    )

    non_secret_written = upsert_env_file(
        str(FUNCTIONS_ENV), {"STAGING_SUPABASE_URL": Secret(f"https://{ref}.supabase.co")}
    )
    non_secret_written += upsert_env_file(
        str(APP_STAGING_ENV),
        {
            "SUPABASE_URL": Secret(f"https://{ref}.supabase.co"),
            "APP_ENV": Secret("staging"),
        },
    )
    print(f"==> Wrote non-secret config: {', '.join(sorted(set(non_secret_written)))}")

    result = fetch_and_store_api_keys(
        ref, token, str(FUNCTIONS_ENV), str(APP_STAGING_ENV), allow_legacy_fallback=False
    )
    print(f"==> Wrote API keys: {', '.join(result['written_vars'])}")
    print(
        f"==> Key types used: anon_slot={result['anon_slot_key_type']} "
        f"service_slot={result['service_slot_key_type']}"
    )

    db_password = Secret(read_plain_env_var(str(FUNCTIONS_ENV), "STAGING_DB_PASSWORD"))
    connection_strings = build_connection_strings(ref, summary["region"], db_password)
    db_written = upsert_env_file(
        str(FUNCTIONS_ENV),
        {
            "STAGING_SUPABASE_DB_URL": connection_strings["direct"],
            "STAGING_SUPABASE_DB_POOLED_URL": connection_strings["pooled"],
        },
    )
    print(f"==> Wrote DB connection strings: {', '.join(db_written)}")


if __name__ == "__main__":
    main()
