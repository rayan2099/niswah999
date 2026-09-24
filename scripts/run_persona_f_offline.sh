#!/usr/bin/env bash
# Persona F (offline save / pending state) live runner.
#
# integration_test/pF_offline_save_test.dart runs as one continuous app
# session and prints two literal marker lines the app itself logs via
# `h.note()` (forwarded to this process's own stdout through the VM
# service connection): "F READY FOR OUTAGE" (safe to stop the backend)
# and "F READY FOR RECONNECT" (test's own assertions are done; safe to
# restart the backend for whatever runs next). This script starts
# `flutter drive`, waits for each marker, and stops/restarts the real
# local Supabase backend around them — a genuine outage, never a
# mocked/injected offline flag.
#
# Reconnection replay (does the pending operation actually get synced
# once the backend comes back) is NOT verified by this test — see its
# own doc comment for the disclosed test-infrastructure blocker found
# this session (`binding.handleAppLifecycleStateChanged` hangs here for
# an undetermined reason even after fixing an illegal state-transition
# assertion).
#
# Usage: scripts/run_persona_f_offline.sh <simulator-udid>
set -euo pipefail

UDID="${1:?Usage: $0 <simulator-udid>}"
LOG_FILE="$(mktemp)"
trap 'rm -f "$LOG_FILE"' EXIT

cd "$(dirname "$0")/.."

xcrun simctl uninstall "$UDID" com.niswah.niswah 2>/dev/null || true
rm -f build/integration_response_data.json

flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/pF_offline_save_test.dart \
  -d "$UDID" \
  --dart-define=GIT_SHA="$(git rev-parse HEAD)" \
  --dart-define=ENABLE_DIAGNOSTICS_SCREEN=true \
  --dart-define=BACKEND_ENV=local-test:127.0.0.1:54321 \
  > "$LOG_FILE" 2>&1 &
DRIVE_PID=$!

echo "==> Waiting for 'F READY FOR OUTAGE' marker..."
until grep -q "F READY FOR OUTAGE" "$LOG_FILE" 2>/dev/null; do
  if ! kill -0 "$DRIVE_PID" 2>/dev/null; then
    echo "flutter drive exited before reaching the outage marker" >&2
    cat "$LOG_FILE"
    exit 1
  fi
  sleep 1
done

echo "==> Stopping the local backend (real outage)..."
docker stop supabase_db_Niswah supabase_auth_Niswah supabase_rest_Niswah supabase_kong_Niswah

echo "==> Waiting for 'F READY FOR RECONNECT' marker..."
until grep -q "F READY FOR RECONNECT" "$LOG_FILE" 2>/dev/null; do
  if ! kill -0 "$DRIVE_PID" 2>/dev/null; then
    echo "flutter drive exited before reaching the reconnect marker" >&2
    cat "$LOG_FILE"
    exit 1
  fi
  sleep 1
done

echo "==> Restarting the local backend..."
docker start supabase_db_Niswah supabase_auth_Niswah supabase_rest_Niswah supabase_kong_Niswah

wait "$DRIVE_PID"
DRIVE_EXIT=$?
cat "$LOG_FILE"
exit "$DRIVE_EXIT"
