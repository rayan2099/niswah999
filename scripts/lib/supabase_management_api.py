#!/usr/bin/env python3
"""Safe primitives for calling the Supabase Management API and handling
whatever secret-bearing data it returns.

Added after a real incident (2026-10-02): a one-off `sed` redaction
pattern applied to a raw API-keys response only masked the first ~10
characters of each legacy `anon`/`service_role` JWT, leaving the rest of
both exposed in plaintext in agent tool output. The fix here is not a
better mask -- it is removing the class of bug: a secret value is wrapped
in `Secret` the moment it is read out of a parsed response and is never
unwrapped except at the one point it is written into its destination
env file. Every other path (printing, string formatting, exceptions,
logging) sees only `<redacted>`.

Rules this module exists to enforce (do not weaken these to make a
caller more convenient):
  - Never return or log a raw API response body from a secret-bearing
    endpoint. Extraction functions return only explicitly allowlisted
    fields (project ref/name/region/status) or `Secret`-wrapped values.
  - Never pass a secret as a subprocess/CLI argument (visible via
    `ps`/process listings) -- all file writes here are direct Python
    file I/O, no subprocess involved.
  - Prefer the new `publishable`/`secret` API key types over the legacy
    `anon`/`service_role` JWTs when both are present in a response.
"""
from __future__ import annotations

import json
import os
import urllib.error
import urllib.request

MANAGEMENT_API_BASE = "https://api.supabase.com/v1"


class Secret:
    """Wraps a sensitive string so printing, f-string interpolation,
    logging, or an exception message never reveals it by accident.
    `reveal()` is the one explicit escape hatch -- callers must opt in
    deliberately, and only `upsert_env_file` below should ever need to.
    """

    __slots__ = ("_value",)

    def __init__(self, value: str):
        self._value = value

    def reveal(self) -> str:
        return self._value

    def __repr__(self) -> str:
        return "<redacted>"

    def __str__(self) -> str:
        return "<redacted>"

    def __eq__(self, other):
        if isinstance(other, Secret):
            return self._value == other._value
        return NotImplemented

    def __hash__(self):
        return hash((self.__class__.__name__, id(self)))


class ManagementApiError(Exception):
    """Carries only the HTTP status code and request path -- never the
    response body, which may itself be secret-bearing on some endpoints."""

    def __init__(self, status_code: int, path: str):
        self.status_code = status_code
        super().__init__(f"Supabase Management API request to {path} failed with HTTP {status_code}")


def _http_post(path: str, token: Secret, body: dict):
    """Internal. Same contract as `_http_get` -- callers must not print
    this return value directly without an allowlist for any endpoint
    that can carry secrets."""
    data = json.dumps(body).encode("utf-8")
    request = urllib.request.Request(
        f"{MANAGEMENT_API_BASE}{path}",
        data=data,
        headers={"Authorization": f"Bearer {token.reveal()}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        raise ManagementApiError(exc.code, path) from None


def apply_migration(ref: str, token: Secret, sql: str, name: str, rollback: str, idempotency_key: str):
    """Applies real DDL/DML via the platform's own migration-apply
    endpoint (/database/migrations, POST) -- no DB password or
    service-role key is ever needed. This is a genuine WRITE, unlike
    `run_readonly_query`; callers must only use this with deliberate,
    reviewed SQL and explicit authorization to mutate the target
    project. `idempotency_key` should be stable per logical migration
    (e.g. its filename) so an accidental retry can never double-apply
    it."""
    body = {"query": sql, "name": name, "rollback": rollback}
    data = json.dumps(body).encode("utf-8")
    request = urllib.request.Request(
        f"{MANAGEMENT_API_BASE}/projects/{ref}/database/migrations",
        data=data,
        headers={
            "Authorization": f"Bearer {token.reveal()}",
            "Content-Type": "application/json",
            "Idempotency-Key": idempotency_key,
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        raise ManagementApiError(exc.code, f"/projects/{ref}/database/migrations") from None


def run_readonly_query(ref: str, token: Secret, sql: str):
    """Runs SQL via the platform's own dedicated read-only query endpoint
    (/database/query/read-only) -- no DB password or service-role key is
    ever needed for this. The endpoint itself enforces read-only (no
    mutation is possible through it), but callers must still only ever
    pass SELECT/introspection queries: this is a schema/metadata
    inspection primitive, not a general escape hatch, and must never be
    used to read actual row CONTENT from user/health tables -- counts
    and schema metadata only."""
    return _http_post(f"/projects/{ref}/database/query/read-only", token, {"query": sql})


def _http_get(path: str, token: Secret):
    """Internal. Returns the parsed JSON body. Callers must not print
    this return value directly for any endpoint that can carry secrets
    -- extract only allowlisted/`Secret`-wrapped fields from it."""
    request = urllib.request.Request(
        f"{MANAGEMENT_API_BASE}{path}",
        headers={"Authorization": f"Bearer {token.reveal()}"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        raise ManagementApiError(exc.code, path) from None


def fetch_raw_bytes(path: str, token: Secret) -> bytes:
    """Like `_http_get` but for endpoints that return a non-JSON binary
    body (e.g. an Edge Function's deployed bundle via `.../body`).
    Returns raw bytes -- callers must not assume this is safe to print
    or decode as text; it is a deploy artifact, not a secret, but is
    still opaque binary data."""
    request = urllib.request.Request(
        f"{MANAGEMENT_API_BASE}{path}",
        headers={"Authorization": f"Bearer {token.reveal()}"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.read()
    except urllib.error.HTTPError as exc:
        raise ManagementApiError(exc.code, path) from None


def read_plain_env_var(env_file_path: str, var_name: str) -> str:
    """For genuinely non-secret config values only (e.g. a project ref).
    Do not use this for anything that should be wrapped in `Secret`."""
    with open(env_file_path, "r", encoding="utf-8") as f:
        for line in f:
            stripped = line.strip()
            if stripped.startswith(f"{var_name}="):
                return stripped.split("=", 1)[1].strip()
    raise RuntimeError(f"{var_name} not found in {env_file_path}")


def load_access_token(env_file_path: str) -> Secret:
    value = read_plain_env_var(env_file_path, "SUPABASE_ACCESS_TOKEN")
    if not value:
        raise RuntimeError(f"SUPABASE_ACCESS_TOKEN is empty in {env_file_path}")
    return Secret(value)


EXPECTED_PRODUCTION_REF = "jkmjobvxfrmuwafczvtw"
EXPECTED_PRODUCTION_NAME = "Niswah"
EXPECTED_STAGING_REF = "ovgvevzrcefloitgcsia"
EXPECTED_STAGING_NAME = "Niswah Staging"


def assert_is_production_project(summary: dict) -> None:
    """Call before every production read operation. Raises rather than
    proceeding if identity is anything but an exact match -- including
    if it matches the known staging ref instead."""
    if summary.get("ref") == EXPECTED_STAGING_REF:
        raise RuntimeError(
            "REFUSING: fetched project identity matches the STAGING ref, not production. Stopping."
        )
    if summary.get("ref") != EXPECTED_PRODUCTION_REF or summary.get("name") != EXPECTED_PRODUCTION_NAME:
        raise RuntimeError(
            "REFUSING: project identity does not match known production "
            f"(expected ref={EXPECTED_PRODUCTION_REF!r} name={EXPECTED_PRODUCTION_NAME!r}; "
            f"got ref={summary.get('ref')!r} name={summary.get('name')!r})."
        )


def fetch_project_summary(ref: str, token: Secret) -> dict:
    """Returns ONLY an allowlisted set of fields. Anything else present
    in the real response (there is no reason there should be a secret
    on a project-details object, but this is an allowlist, not a
    blocklist, specifically so a future unexpected field can't leak)."""
    data = _http_get(f"/projects/{ref}", token)
    if not isinstance(data, dict):
        raise ValueError("Unexpected project response shape: expected an object")
    return {
        "ref": data.get("id"),
        "name": data.get("name"),
        "region": data.get("region"),
        "status": data.get("status"),
    }


def extract_preferred_api_keys(raw_keys, allow_legacy_fallback: bool = True) -> dict:
    """Given the parsed array from GET /projects/{ref}/api-keys?reveal=true,
    selects the new-format `publishable`/`secret` keys when present.

    If `allow_legacy_fallback` is True (the default, for general reuse),
    falls back to the legacy `anon`/`service_role` keys when the new ones
    are absent. Callers that must never touch legacy keys -- e.g. after
    those legacy keys have been deliberately disabled -- pass
    `allow_legacy_fallback=False`, which raises instead of retrieving
    them, even if they are still present in the response.

    Fails loudly on an unrecognized shape rather than guessing. Returned
    values are `Secret`-wrapped; only `type` (the key kind, e.g.
    "publishable" or "anon") is a plain string -- that label is not
    sensitive and is safe to log."""
    if not isinstance(raw_keys, list):
        raise ValueError("Unexpected api-keys response shape: expected a list")

    by_identity: dict[str, Secret] = {}
    for entry in raw_keys:
        if not isinstance(entry, dict) or "api_key" not in entry:
            raise ValueError("Unexpected api-keys response shape: entry missing 'api_key'")
        identity = (entry.get("type") or entry.get("name") or "").strip().lower()
        if not identity:
            raise ValueError("Unexpected api-keys response shape: entry missing 'type'/'name'")
        by_identity[identity] = Secret(entry["api_key"])

    if "publishable" in by_identity:
        anon_slot_type, anon_slot_value = "publishable", by_identity["publishable"]
    elif allow_legacy_fallback and "anon" in by_identity:
        anon_slot_type, anon_slot_value = "anon", by_identity["anon"]
    elif not allow_legacy_fallback:
        raise ValueError("No publishable key present and legacy anon fallback is disabled")
    else:
        raise ValueError("No publishable or legacy anon key present in api-keys response")

    if "secret" in by_identity:
        service_slot_type, service_slot_value = "secret", by_identity["secret"]
    elif allow_legacy_fallback and "service_role" in by_identity:
        service_slot_type, service_slot_value = "service_role", by_identity["service_role"]
    elif not allow_legacy_fallback:
        raise ValueError("No secret key present and legacy service_role fallback is disabled")
    else:
        raise ValueError("No secret or legacy service_role key present in api-keys response")

    return {
        "anon_slot": {"type": anon_slot_type, "value": anon_slot_value},
        "service_slot": {"type": service_slot_type, "value": service_slot_value},
    }


def upsert_env_file(path: str, values: dict) -> list:
    """Replaces (in place) or appends KEY=value lines in a gitignored env
    file, given `values: dict[str, Secret]`. Pure file I/O -- no
    subprocess is ever spawned, so a secret value never becomes visible
    in a process listing. Returns only the sorted list of variable NAMES
    written, never their values, so a caller can log the return value
    safely."""
    existing_lines = []
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as f:
            existing_lines = f.readlines()

    remaining_keys = set(values.keys())
    new_lines = []
    for line in existing_lines:
        stripped = line.rstrip("\n")
        matched_key = next((k for k in remaining_keys if stripped.startswith(f"{k}=")), None)
        if matched_key is not None:
            new_lines.append(f"{matched_key}={values[matched_key].reveal()}\n")
            remaining_keys.discard(matched_key)
        else:
            new_lines.append(line if line.endswith("\n") else line + "\n")

    for key in sorted(remaining_keys):
        new_lines.append(f"{key}={values[key].reveal()}\n")

    with open(path, "w", encoding="utf-8") as f:
        f.writelines(new_lines)

    return sorted(values.keys())


def build_connection_strings(ref: str, region: str, db_password: Secret) -> dict:
    """Constructs the direct and Supavisor/pooler Postgres connection
    strings from their publicly-documented, stable format (ref, region,
    and the project's own DB password -- never retrieved from the API,
    since Supabase never returns a project's DB password after
    creation). Returns `Secret`-wrapped connection strings; the password
    component is URL-encoded defensively even though this project's
    generated password contains no URL-unsafe characters.

    Three variants, matching Supabase's own guidance:
      - direct: db.{ref}.supabase.co:5432 -- IPv6 only unless the paid
        IPv4 add-on is purchased (it is not, per the approved staging
        budget). Not reachable from an IPv4-only network/admin box.
      - pooled_session: the Supavisor pooler on port 5432 (session
        mode) -- IPv4-compatible, behaves like a direct connection
        (prepared statements, one session per client). Use this for
        schema migrations/admin tooling.
      - pooled_transaction: the same pooler host on port 6543
        (transaction mode) -- the right choice for short-lived
        serverless/Edge Function runtime connections, not for
        migrations.
    """
    from urllib.parse import quote

    encoded_password = quote(db_password.reveal(), safe="")
    direct = f"postgresql://postgres:{encoded_password}@db.{ref}.supabase.co:5432/postgres"
    pooler_host = f"aws-0-{region}.pooler.supabase.com"
    pooled_session = f"postgresql://postgres.{ref}:{encoded_password}@{pooler_host}:5432/postgres"
    pooled_transaction = f"postgresql://postgres.{ref}:{encoded_password}@{pooler_host}:6543/postgres"
    return {
        "direct": Secret(direct),
        "pooled_session": Secret(pooled_session),
        "pooled_transaction": Secret(pooled_transaction),
    }


def fetch_and_store_api_keys(
    ref: str,
    token: Secret,
    functions_env_path: str,
    app_env_path: str,
    allow_legacy_fallback: bool = True,
) -> dict:
    """Fetches the project's API keys and writes the preferred (new-format
    where available) anon/service-role-equivalent values directly to
    their destination files. Returns only safe-to-log identifiers --
    never a value. See `extract_preferred_api_keys` for
    `allow_legacy_fallback`."""
    raw = _http_get(f"/projects/{ref}/api-keys?reveal=true", token)
    extracted = extract_preferred_api_keys(raw, allow_legacy_fallback=allow_legacy_fallback)

    written = []
    written += upsert_env_file(
        functions_env_path,
        {"STAGING_SUPABASE_SERVICE_ROLE_KEY": extracted["service_slot"]["value"]},
    )
    written += upsert_env_file(
        app_env_path,
        {"SUPABASE_ANON_KEY": extracted["anon_slot"]["value"]},
    )
    return {
        "written_vars": written,
        "anon_slot_key_type": extracted["anon_slot"]["type"],
        "service_slot_key_type": extracted["service_slot"]["type"],
    }
