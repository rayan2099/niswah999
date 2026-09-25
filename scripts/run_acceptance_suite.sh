#!/usr/bin/env bash
# Runs EVERY persona (integration_test/p*_test.dart) against the current
# .env backend on one device/emulator, records one structured result per
# persona under <results-dir>/<test>.json, and lets
# scripts/verify_acceptance_results.py decide the exit code. A crashed
# run, a missing result, a BLOCKED/FAIL persona all fail the suite — there
# is no path from "flutter drive exited" to a pass.
#
#   scripts/run_acceptance_suite.sh <device-id> [results-dir]
#
# The production kill switch runs first (and again per persona). Persona F
# needs the host to stop/start the local backend around its own markers, so
# it is run through scripts/run_persona_f_offline.sh, which also verifies
# the persisted rows with independent SQL.
set -uo pipefail
DEVICE="${1:?Usage: $0 <device-id> [results-dir]}"
OUT="${2:-acceptance/results}"
cd "$(dirname "$0")/.."

python3 scripts/assert_test_backend.py --env-file .env || exit 3
mkdir -p "$OUT" acceptance/logs acceptance/screenshots/suite

for f in integration_test/p*_test.dart; do
  id="$(basename "$f" .dart)"
  # Optional subset (space-separated id prefixes), used only to time/probe a
  # new runner. The verifier still judges the full catalogue, so a subset
  # run can never be mistaken for a passing suite.
  if [ -n "${ACCEPTANCE_ONLY:-}" ]; then
    keep=0
    for pre in $ACCEPTANCE_ONLY; do case "$id" in "$pre"*) keep=1 ;; esac; done
    [ "$keep" = 1 ] || continue
  fi
  echo "::group::$id"
  rm -f build/integration_response_data.json
  if [ "$id" = "pF_offline_save_test" ]; then
    bash scripts/run_persona_f_offline.sh "$DEVICE" > "acceptance/logs/$id.log" 2>&1
  else
    SHOT_DIR=acceptance/screenshots/suite \
      bash scripts/run_persona_local.sh "$DEVICE" "$f" > "acceptance/logs/$id.log" 2>&1
  fi
  drive_exit=$?
  tail -n 40 "acceptance/logs/$id.log" | grep -E "RESULT_JSON|BACKEND GATE|F RESULT|HOST DB" | cut -c1-300 || true
  if [ -f build/integration_response_data.json ]; then
    cp build/integration_response_data.json "$OUT/$id.json"
  else
    printf '{"test_id": "%s", "status": "MISSING_RESULT", "drive_exit_code": %s}' "$id" "$drive_exit" > "$OUT/$id.json"
    echo "no result file for $id (exit $drive_exit) — the verifier will fail it"
  fi
  echo "::endgroup::"
done

python3 scripts/verify_acceptance_results.py "$OUT" integration_test
