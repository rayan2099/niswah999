#!/usr/bin/env python3
"""Runs real HTTP calls against the deployed Niswah Staging Edge
Functions, using synthetic (test-only) Supabase Auth users -- never real
user data. Reuses the case patterns from OPENAI_ACCEPTANCE_RESULTS.csv /
FD1_STATE_ACCEPTANCE_RESULTS.csv (the earlier real-model local passes),
rerun here against the real staging endpoint per the staging acceptance
matrix (production-readiness-results/knowledge-base/
STAGING_PROVISIONING_AND_VALIDATION_PLAN.md, Phase 11).

Reads SUPABASE_URL/SUPABASE_ANON_KEY from .env.staging and the service
role key from supabase/functions/.env (STAGING_SUPABASE_SERVICE_ROLE_KEY,
needed only to mint pre-confirmed synthetic test accounts) -- all via
the Secret-wrapped helpers in scripts/lib/supabase_management_api.py, so
no credential is ever printed.

Every synthetic account uses a @niswah-staging.test address and a
random password; nothing here ever touches real user data.
"""
from __future__ import annotations

import json
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(REPO_ROOT))

from scripts.lib.supabase_management_api import Secret, read_plain_env_var  # noqa: E402

APP_STAGING_ENV = REPO_ROOT / ".env.staging"
FUNCTIONS_ENV = REPO_ROOT / "supabase" / "functions" / ".env"


def _secret_env(path: Path, name: str) -> Secret:
    return Secret(read_plain_env_var(str(path), name))


def _post(url: str, headers: dict, body: dict, timeout: int = 30):
    data = json.dumps(body).encode("utf-8")
    request = urllib.request.Request(url, data=data, headers=headers, method="POST")
    start = time.monotonic()
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            elapsed = time.monotonic() - start
            return response.status, json.loads(response.read().decode("utf-8")), elapsed
    except urllib.error.HTTPError as exc:
        elapsed = time.monotonic() - start
        try:
            payload = json.loads(exc.read().decode("utf-8"))
        except Exception:
            payload = {}
        return exc.code, payload, elapsed


class StagingClient:
    def __init__(self):
        self.base_url = read_plain_env_var(str(APP_STAGING_ENV), "SUPABASE_URL")
        self.anon_key = _secret_env(APP_STAGING_ENV, "SUPABASE_ANON_KEY")
        self.service_role_key = _secret_env(FUNCTIONS_ENV, "STAGING_SUPABASE_SERVICE_ROLE_KEY")

    def create_synthetic_session(self) -> Secret:
        """Creates a fresh, pre-confirmed, password-only synthetic test
        account via the Auth admin API (service role), then signs in
        normally to obtain a real user access token. Returns the access
        token wrapped in `Secret` -- never printed."""
        email = f"accept-test-{uuid.uuid4().hex}@niswah-staging.test"
        password = uuid.uuid4().hex + "Aa1!"

        status, create_payload, _ = _post(
            f"{self.base_url}/auth/v1/admin/users",
            {
                "apikey": self.service_role_key.reveal(),
                "Authorization": f"Bearer {self.service_role_key.reveal()}",
                "Content-Type": "application/json",
            },
            {"email": email, "password": password, "email_confirm": True},
        )
        if status not in (200, 201):
            raise RuntimeError(f"Failed to create synthetic test account (status {status}, msg={create_payload.get('msg') or create_payload.get('error_code') or create_payload.get('message')})")

        status, payload, _ = _post(
            f"{self.base_url}/auth/v1/token?grant_type=password",
            {"apikey": self.anon_key.reveal(), "Content-Type": "application/json"},
            {"email": email, "password": password},
        )
        if status != 200 or "access_token" not in payload:
            raise RuntimeError(f"Failed to sign in synthetic test account (status {status})")
        return Secret(payload["access_token"])

    def call_function(self, fn_name: str, access_token: Secret, body: dict, timeout: int = 30):
        status, payload, elapsed = _post(
            f"{self.base_url}/functions/v1/{fn_name}",
            {
                "apikey": self.anon_key.reveal(),
                "Authorization": f"Bearer {access_token.reveal()}",
                "Content-Type": "application/json",
            },
            body,
            timeout=timeout,
        )
        return status, payload, elapsed
