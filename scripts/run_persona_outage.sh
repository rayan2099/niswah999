#!/usr/bin/env bash
# Generic live-outage runner for personas that need the backend to be
# genuinely unreachable for part of the run (Persona F has its own runner
# with extra DB verification). The test prints literal marker lines through
# its own log:  "OUTAGE START <n>"  -> this script stops the local backend;
#               "OUTAGE END <n>"    -> this script starts it again.
# Any number of cycles is supported; the drive is bounded by a deadline and
# the backend is ALWAYS restarted on exit. Local disposable backend only
# (the production kill switch runs first).
#   scripts/run_persona_outage.sh <device-id> <integration_test/pX_test.dart>
set -uo pipefail
DEVICE="${1:?Usage: $0 <device-id> <target.dart>}"
TARGET="${2:?Usage: $0 <device-id> <target.dart>}"
cd "$(dirname "$0")/.."
python3 scripts/assert_test_backend.py --env-file .env || exit 3
BACKEND_HOST="$(python3 -c "import re;u=[l.split('=',1)[1].strip() for l in open('.env') if l.startswith('SUPABASE_URL=')][0];print(re.match(r'https?://([^/@]+)',u).group(1))")"
SVCS="supabase_db_Niswah supabase_auth_Niswah supabase_rest_Niswah supabase_kong_Niswah"
LOG="$(mktemp)"
restore() { docker start $SVCS >/dev/null 2>&1 || true; rm -f "$LOG"; }
trap restore EXIT

case "$DEVICE" in
  emulator-*) adb -s "$DEVICE" uninstall com.niswah.niswah >/dev/null 2>&1 || true ;;
  *) xcrun simctl uninstall "$DEVICE" com.niswah.niswah 2>/dev/null || true ;;
esac
rm -f build/integration_response_data.json

flutter drive --driver=test_driver/integration_test.dart --target="$TARGET" -d "$DEVICE" \
  --dart-define=GIT_SHA="$(git rev-parse HEAD)" --dart-define=ENABLE_DIAGNOSTICS_SCREEN=true \
  --dart-define=ACCEPTANCE_TEST=true --dart-define=BACKEND_ENV="local-test:${BACKEND_HOST}" \
  > "$LOG" 2>&1 &
PID=$!
DEADLINE=$(( $(date +%s) + ${PERSONA_TIMEOUT_SECONDS:-1500} ))
starts=0; ends=0
while kill -0 "$PID" 2>/dev/null; do
  if [ "$(date +%s)" -ge "$DEADLINE" ]; then
    echo "TIMEOUT: killing the drive" >&2; kill -9 "$PID" 2>/dev/null; break
  fi
  s=$(grep -c "OUTAGE START" "$LOG" 2>/dev/null); e=$(grep -c "OUTAGE END" "$LOG" 2>/dev/null)
  if [ "${s:-0}" -gt "$starts" ]; then
    starts=$s; echo "==> outage $starts: stopping the local backend"; docker stop $SVCS >/dev/null
  fi
  if [ "${e:-0}" -gt "$ends" ]; then
    ends=$e; echo "==> outage $ends over: starting the local backend"; docker start $SVCS >/dev/null
  fi
  sleep 1
done
wait "$PID" 2>/dev/null; RC=$?
cat "$LOG"
exit $RC
