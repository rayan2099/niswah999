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
  # Personas that need an OS-level precondition the test cannot set itself
  # (a native permission dialog cannot be tapped from a Flutter test). The
  # permission must be set AFTER the app is installed and survive the drive's
  # own reinstall, so the app is installed first if needed (a throwaway
  # warm-up run of p0) and the persona is then run with --keep-app.
  KEEP=""
  case "$id" in
    pL1_*|pL2_*)
      mode=grant; [ "${id#pL2_}" != "$id" ] && mode=revoke
      APK=build/app/outputs/flutter-apk/app-debug.apk
      case "$DEVICE" in
        emulator-*)
          # `flutter drive` uninstalls the app when it finishes, and a runtime
          # permission can only be set on an INSTALLED app. Build/install it
          # explicitly (a throwaway warm-up run of p0 produces the APK).
          if [ ! -f "$APK" ]; then
            bash scripts/run_persona_local.sh "$DEVICE" integration_test/p0_build_identity_test.dart \
              > "acceptance/logs/${id}_warmup.log" 2>&1 || true
          fi
          adb -s "$DEVICE" install -r -t "$APK" >/dev/null 2>&1 || true ;;
        *)
          if ! xcrun simctl get_app_container "$DEVICE" com.niswah.niswah >/dev/null 2>&1; then
            bash scripts/run_persona_local.sh "$DEVICE" integration_test/p0_build_identity_test.dart \
              > "acceptance/logs/${id}_warmup.log" 2>&1 || true
          fi ;;
      esac
      bash scripts/set_location_permission.sh "$DEVICE" "$mode" || true
      KEEP="--keep-app"
      # An emulator only delivers a fresh GPS fix when one is injected while
      # the app is asking; keep injecting one for the duration of the run.
      case "$DEVICE:$mode" in
        emulator-*:grant)
          ( while true; do adb -s "$DEVICE" emu geo fix 46.6753 24.7136 >/dev/null 2>&1; sleep 2; done ) &
          GEO_PID=$! ;;
      esac ;;
  esac
  if [ "$id" = "pF_offline_save_test" ]; then
    bash scripts/run_persona_f_offline.sh "$DEVICE" > "acceptance/logs/$id.log" 2>&1
  elif [ "$id" = "pO_outage_honesty_test" ]; then
    SHOT_DIR=acceptance/screenshots/suite \
      bash scripts/run_persona_outage.sh "$DEVICE" "$f" > "acceptance/logs/$id.log" 2>&1
  else
    SHOT_DIR=acceptance/screenshots/suite \
      bash scripts/run_persona_local.sh "$DEVICE" "$f" $KEEP > "acceptance/logs/$id.log" 2>&1
  fi
  drive_exit=$?
  if [ -n "${GEO_PID:-}" ]; then kill "$GEO_PID" 2>/dev/null; wait "$GEO_PID" 2>/dev/null; GEO_PID=""; fi
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
