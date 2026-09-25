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
# The test itself asserts the full sequence: offline save -> pending state
# visible -> connectivity restored -> the app's real resume trigger ->
# pending cleared -> exactly one canonical episode+observation -> UI
# synced. This script then independently re-verifies the persisted rows
# with host-side SQL, and bounds the wait so a hang can never stall a run.
#
# Usage: scripts/run_persona_f_offline.sh <simulator-udid>
set -euo pipefail

UDID="${1:?Usage: $0 <simulator-udid>}"
LOG_FILE="$(mktemp)"
trap 'rm -f "$LOG_FILE"' EXIT

cd "$(dirname "$0")/.."

# Production kill switch — before the app is even installed. Exits
# non-zero, creating nothing, unless .env points at an approved backend.
python3 scripts/assert_test_backend.py --env-file .env

xcrun simctl uninstall "$UDID" com.niswah.niswah 2>/dev/null || true
rm -f build/integration_response_data.json

flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/pF_offline_save_test.dart \
  -d "$UDID" \
  --dart-define=GIT_SHA="$(git rev-parse HEAD)" \
  --dart-define=ENABLE_DIAGNOSTICS_SCREEN=true \
  --dart-define=ACCEPTANCE_TEST=true \
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

# Bounded wait for the test to finish its own replay assertions.
DEADLINE=$(( $(date +%s) + 240 ))
while kill -0 "$DRIVE_PID" 2>/dev/null; do
  if [ "$(date +%s)" -ge "$DEADLINE" ]; then
    echo "==> TIMEOUT: flutter drive did not finish within 240s of reconnect - killing it" >&2
    kill -9 "$DRIVE_PID" 2>/dev/null || true
    pkill -9 -f "Runner.app/Runner" 2>/dev/null || true
    cat "$LOG_FILE"
    exit 124
  fi
  sleep 2
done
set +e; wait "$DRIVE_PID"; DRIVE_EXIT=$?; set -e
cat "$LOG_FILE"

# Independent host-side verification of what actually persisted.
EMAIL="$(grep -o 'LOOKUP_EMAIL=[^ ]*' "$LOG_FILE" | head -1 | cut -d= -f2)"
if [ -z "$EMAIL" ]; then echo "HOST DB VERIFY: no LOOKUP_EMAIL in log" >&2; exit 1; fi
COUNTS="$(docker exec -i supabase_db_Niswah psql -U postgres -d postgres -At -F' ' -c "
  select (select count(*) from bleeding_episodes e join auth.users u on u.id=e.user_id where u.email=lower('$EMAIL')),
         (select count(*) from bleeding_observations o join auth.users u on u.id=o.user_id where u.email=lower('$EMAIL'));")"
echo "HOST DB VERIFY ($EMAIL): episodes observations = $COUNTS"
if [ "$COUNTS" != "1 1" ]; then echo "HOST DB VERIFY FAILED: expected exactly '1 1'" >&2; exit 1; fi
exit "$DRIVE_EXIT"
