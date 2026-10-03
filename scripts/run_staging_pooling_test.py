#!/usr/bin/env python3
"""Connection-pooling check (Phase 10 of STAGING_PROVISIONING_AND_VALIDATION_PLAN.md),
run against the real deployed staging Edge Functions with real concurrent
requests, each using a fresh synthetic Supabase Auth session. Prints only
aggregate pass/fail/latency numbers -- never a credential.

Usage: python3 scripts/run_staging_pooling_test.py <concurrency> <total_requests>
"""
from __future__ import annotations

import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from scripts.lib.staging_acceptance_client import StagingClient  # noqa: E402

QUESTION = "What is the minimum duration of haid?"


def one_request(client: StagingClient, token) -> dict:
    """Takes a pre-created session token rather than minting one per call --
    Supabase Auth's own password-grant rate limit (separate from, and much
    lower than, Postgres connection-pool capacity) otherwise dominates the
    measurement at higher concurrency, as discovered when a first version
    of this test created a fresh account per concurrent request and saw
    HTTP 429s from /auth/v1/token, not from the DB-backed function at all.
    Pre-creating sessions isolates what this test actually needs to measure:
    the Postgres/Supavisor pool's behavior under concurrent Edge Function
    invocations, not Auth's sign-in rate limit."""
    start = time.monotonic()
    try:
        status, payload, elapsed = client.call_function(
            "fiqh-advisor-chat", token,
            {"question": QUESTION, "madhhab": "hanafi", "madhhab_state": "selected", "clientFiqhState": "tahara"},
            timeout=45,
        )
        ok = status == 200 and bool(payload.get("text"))
        return {"ok": ok, "status": status, "elapsed": elapsed, "total_elapsed": time.monotonic() - start, "stage": "fn"}
    except Exception as exc:  # noqa: BLE001
        return {"ok": False, "status": None, "elapsed": None, "total_elapsed": time.monotonic() - start,
                "error": type(exc).__name__, "stage": "fn"}


def main() -> None:
    concurrency = int(sys.argv[1]) if len(sys.argv) > 1 else 10
    total = int(sys.argv[2]) if len(sys.argv) > 2 else 10

    client = StagingClient()
    session_pool_size = min(10, concurrency)
    print(f"==> Pre-creating {session_pool_size} synthetic sessions sequentially (avoids Auth's own sign-in rate limit)")
    sessions = [client.create_synthetic_session() for _ in range(session_pool_size)]

    print(f"==> Running {total} requests at concurrency {concurrency} against fiqh-advisor-chat (staging)")
    results = []
    start = time.monotonic()
    with ThreadPoolExecutor(max_workers=concurrency) as pool:
        futures = [pool.submit(one_request, client, sessions[i % len(sessions)]) for i in range(total)]
        for future in as_completed(futures):
            results.append(future.result())
    wall = time.monotonic() - start

    successes = [r for r in results if r["ok"]]
    failures = [r for r in results if not r["ok"]]
    latencies = sorted(r["elapsed"] for r in successes if r["elapsed"] is not None)

    def pct(p):
        if not latencies:
            return None
        idx = min(len(latencies) - 1, int(len(latencies) * p))
        return latencies[idx]

    print(f"==> Success: {len(successes)}/{total} ({100 * len(successes) / total:.1f}%)")
    print(f"==> Wall clock: {wall:.2f}s")
    if latencies:
        print(f"==> p50={pct(0.5):.2f}s p95={pct(0.95):.2f}s max={max(latencies):.2f}s")
    if failures:
        error_types = {}
        for f in failures:
            key = (f.get("stage"), f.get("error") or f.get("status"))
            error_types[key] = error_types.get(key, 0) + 1
        print(f"==> Failure breakdown (stage, error): {error_types}")


if __name__ == "__main__":
    main()
