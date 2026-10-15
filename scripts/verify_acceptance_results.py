#!/usr/bin/env python3
"""Host-side acceptance-result verifier.

Reads one JSON result file per persona test file (written by
`h.reportResult()` in `integration_test/support/harness.dart`, copied out
of `build/integration_response_data.json` after each `flutter drive`
invocation — see `.github/workflows/acceptance.yml`).

Exits non-zero (failing the CI job) unless EVERY `p*_test.dart` file in
the integration_test directory has a corresponding result file whose
top-level `status` field is exactly "PASS". A missing file, unparsable
JSON, a crashed/blocked/skipped/failed persona, or a status of anything
other than "PASS" is a failure — there is no code path that lets a
missing or broken result count as a pass.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path


def discover_required_test_ids(integration_test_dir: Path) -> list[str]:
    return sorted(p.stem for p in integration_test_dir.glob("p*_test.dart"))


def verify(
    results_dir: Path,
    integration_test_dir: Path,
    only: list[str] | None = None,
) -> int:
    required = discover_required_test_ids(integration_test_dir)
    if not required:
        print(f"::error::No p*_test.dart files found under {integration_test_dir}")
        return 1
    if only:
        # Shard mode: judge ONLY the personas this shard was asked to run
        # (space-separated id prefixes, the same list the suite runner used).
        # A shard is never the catalogue-level verdict — the final job runs
        # this script WITHOUT --only. A selection that matches nothing is an
        # error, never a vacuous pass.
        required = [t for t in required if any(t.startswith(p) for p in only)]
        if not required:
            print(f"::error::--only {only!r} matched no persona file")
            return 1

    failures: list[str] = []
    rows: list[str] = []

    for test_id in required:
        result_path = results_dir / f"{test_id}.json"
        if not result_path.is_file():
            failures.append(f"{test_id}: MISSING result file ({result_path})")
            rows.append(f"| {test_id} | (missing) | FAIL — no result file |")
            continue

        try:
            data = json.loads(result_path.read_text())
        except (json.JSONDecodeError, OSError) as exc:
            failures.append(f"{test_id}: unreadable/malformed result file ({exc})")
            rows.append(f"| {test_id} | (malformed) | FAIL — {exc} |")
            continue

        status = data.get("status")
        if status != "PASS":
            failures.append(
                f"{test_id}: status={status!r} "
                f"(expected 'PASS') — {data.get('actual_outcome', '')}"
            )
            rows.append(f"| {test_id} | {status} | FAIL |")
            continue

        rows.append(f"| {test_id} | PASS | ok |")

    print("| Test | Status | Verdict |")
    print("|---|---|---|")
    for row in rows:
        print(row)
    print()

    if failures:
        print(f"::error::{len(failures)} of {len(required)} required "
              f"acceptance persona(s) did not report PASS:")
        for f in failures:
            print(f"::error::  - {f}")
        return 1

    print(f"All {len(required)} required acceptance personas reported PASS.")
    return 0


if __name__ == "__main__":
    args = sys.argv[1:]
    only: list[str] | None = None
    if len(args) == 4 and args[2] == "--only":
        only = args[3].split()
        args = args[:2]
    if len(args) != 2:
        print(
            "Usage: verify_acceptance_results.py <results_dir> "
            "<integration_test_dir> [--only \"<id-prefix> <id-prefix> ...\"]",
            file=sys.stderr,
        )
        sys.exit(2)
    sys.exit(verify(Path(args[0]), Path(args[1]), only))
