#!/usr/bin/env bash
# AUTH-09 — session restore across a REAL app relaunch (process killed, data
# kept), on the iOS Simulator or an Android emulator.
#   scripts/run_session_restore.sh <simulator-udid | emulator-NNNN> [results-dir]
#
# `flutter drive` uninstalls the app when it finishes, which erases the
# session, so a naive second run always starts signed out. Instead:
#   phase 1  clean install; sign up -> Today; the app is left INSTALLED and
#            RUNNING (DRIVE_KEEP_APP_RUNNING=1), then its process is killed
#            from the host (simctl terminate / am force-stop);
#   phase 2  the same test file with --keep-app: no pre-uninstall, the app is
#            reinstalled OVER the existing data and started as a new process.
#            It must find the session already restored, before any tap.
# The phase-2 result is the one recorded; a run that never reaches phase 2
# leaves phase 1's deliberately-FAIL result behind.
set -uo pipefail
DEVICE="${1:?Usage: $0 <simulator-udid|emulator-NNNN> [results-dir]}"
OUT="${2:-acceptance/results-x}"
cd "$(dirname "$0")/.."

T=integration_test/xAuth09_session_restore_test.dart
APP=com.niswah.niswah
mkdir -p "$OUT" acceptance/logs
rm -f build/integration_response_data.json

kill_app() {
  case "$DEVICE" in
    emulator-*) adb -s "$DEVICE" shell am force-stop "$APP" ;;
    *) xcrun simctl terminate "$DEVICE" "$APP" 2>/dev/null || true ;;
  esac
}
installed() {
  case "$DEVICE" in
    emulator-*) adb -s "$DEVICE" shell pm list packages "$APP" | grep -q "$APP" ;;
    *) xcrun simctl get_app_container "$DEVICE" "$APP" >/dev/null 2>&1 ;;
  esac
}

DRIVE_KEEP_APP_RUNNING=1 bash scripts/run_persona_local.sh "$DEVICE" "$T" \
  > acceptance/logs/xAuth09_phase1.log 2>&1
grep -E "RESULT_JSON" acceptance/logs/xAuth09_phase1.log | cut -c1-260
cp build/integration_response_data.json "$OUT/xAuth09_phase1.json" 2>/dev/null || true
rm -f build/integration_response_data.json

kill_app
if ! installed; then
  echo "the app is not installed after phase 1 — its data cannot have survived"; exit 1
fi
echo "phase 1 done; app process killed, app + data kept"

bash scripts/run_persona_local.sh "$DEVICE" "$T" --keep-app \
  > acceptance/logs/xAuth09_phase2.log 2>&1
grep -E "RESULT_JSON|S9 phase2" acceptance/logs/xAuth09_phase2.log | cut -c1-360
if [ -f build/integration_response_data.json ]; then
  cp build/integration_response_data.json "$OUT/xAuth09.json"
  python3 - "$OUT/xAuth09.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print(d.get("status"), d.get("actual_outcome", "")[:400])
sys.exit(0 if d.get("status") == "PASS" else 1)
PY
else
  echo "no phase-2 result"; exit 1
fi
