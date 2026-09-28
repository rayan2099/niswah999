#!/usr/bin/env python3
"""Host-side production kill switch for the acceptance harness.

Mirrors lib/core/config/test_backend_gate.dart exactly (both are tested
against test/fixtures/backend_gate_vectors.json). Reads the effective
Supabase URL from a `.env` file and exits non-zero unless the backend is
loopback or an explicitly approved non-production test project.

There is deliberately NO flag that bypasses this check, and APP_ENV is
never consulted. It logs only the safe host[:port] identifier — never a
key or secret. Run it BEFORE anything that could sign up or write.

Usage: assert_test_backend.py [--env-file .env]
"""
from __future__ import annotations

import argparse
import sys
from urllib.parse import urlsplit

LOCAL_HOSTS = {"localhost", "127.0.0.1", "::1", "10.0.2.2"}
# Empty until a reviewed change adds an exact hosted non-production host.
APPROVED_TEST_HOSTS: set[str] = set()
PRODUCTION_HOSTS = {"jkmjobvxfrmuwafczvtw.supabase.co"}
HOSTED_SUFFIXES = (".supabase.co", ".supabase.in", ".supabase.net")


def evaluate(raw_url: str | None, approved_hosts: set[str] | None = None):
    approved = APPROVED_TEST_HOSTS if approved_hosts is None else approved_hosts
    url = (raw_url or "").strip()
    if not url:
        return False, "<empty>", "the configured Supabase URL is empty or missing"
    try:
        parts = urlsplit(url)
        host = parts.hostname or ""
        port = parts.port
    except ValueError:
        return False, "<unparseable>", "the configured Supabase URL is malformed"
    if not parts.scheme or not host:
        return False, "<unparseable>", "the configured Supabase URL is malformed"
    ident = f"{host}:{port}" if port is not None else host
    if parts.scheme not in ("http", "https"):
        return False, ident, f'the URL scheme "{parts.scheme}" is not http/https'
    if "@" in parts.netloc:
        return False, ident, "the URL contains userinfo, which is never legitimate here"
    host = host.lower()
    if host in PRODUCTION_HOSTS:
        return False, ident, "this is the PRODUCTION Supabase project"
    if host in LOCAL_HOSTS or host in approved:
        return True, ident, "approved test backend"
    if host.endswith(HOSTED_SUFFIXES):
        return False, ident, "an unapproved hosted Supabase project (could be production)"
    return False, ident, "the host is not loopback and is not on the approved test list"


def evaluate_env(env: dict[str, str], approved_hosts: set[str] | None = None):
    url = env.get("SUPABASE_URL", "").strip() or env.get("VITE_SUPABASE_URL", "").strip()
    return evaluate(url, approved_hosts)


def read_env_file(path: str) -> dict[str, str]:
    env: dict[str, str] = {}
    try:
        with open(path, encoding="utf-8") as handle:
            for line in handle:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, _, value = line.partition("=")
                env[key.strip()] = value.strip().strip('"').strip("'")
    except OSError:
        pass
    return env


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env-file", default=".env")
    args = parser.parse_args(argv)
    allowed, host, reason = evaluate_env(read_env_file(args.env_file))
    if allowed:
        print(f"backend gate: ALLOWED {host}")
        return 0
    print(f"backend gate: REFUSED {host} — {reason}", file=sys.stderr)
    print(
        "BLOCKED: refusing to run the acceptance harness against a backend "
        "that is not explicitly approved for testing. No account was "
        "created and nothing was written.",
        file=sys.stderr,
    )
    return 3


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
