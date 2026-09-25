#!/usr/bin/env bash
# The ONLY sanctioned way to run one persona locally.
#   scripts/run_persona_local.sh <simulator-udid> <integration_test/pX_test.dart> [--keep-app]
#
# 1. Runs the production kill switch on .env BEFORE anything else — exits
#    non-zero (creating nothing) unless the backend is loopback or an
#    explicitly approved non-production test project.
# 2. Always builds with --dart-define=ACCEPTANCE_TEST=true, which arms the
#    app-side gate too (main.dart refuses before Supabase/Sentry init).
# There is deliberately no option to skip either step.
set -euo pipefail
UDID="${1:?Usage: $0 <udid> <target.dart> [--keep-app]}"
TARGET="${2:?Usage: $0 <udid> <target.dart> [--keep-app]}"
KEEP="${3:-}"
cd "$(dirname "$0")/.."

python3 scripts/assert_test_backend.py --env-file .env

if [ "$KEEP" != "--keep-app" ]; then
  case "$UDID" in
    emulator-*) adb -s "$UDID" uninstall com.niswah.niswah >/dev/null 2>&1 || true ;;
    *) xcrun simctl uninstall "$UDID" com.niswah.niswah 2>/dev/null || true ;;
  esac
fi
rm -f build/integration_response_data.json

HOST="$(python3 - <<'PY'
import re
url=""
for l in open(".env"):
    if l.startswith("SUPABASE_URL="): url=l.split("=",1)[1].strip()
m=re.match(r"https?://([^/:@]+)(?::(\d+))?", url)
print((m.group(1)+(":"+m.group(2) if m.group(2) else "")) if m else "unknown")
PY
)"

# Bounded: a crashed test binary can leave `flutter drive` waiting forever
# (macOS has no `timeout`). Poll to a deadline, then kill the tree and
# report a timeout — never a silent hang. Override with
# PERSONA_TIMEOUT_SECONDS (a cold Android Gradle build alone can be 20 min).
DEADLINE_SECONDS="${PERSONA_TIMEOUT_SECONDS:-1500}"
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target="$TARGET" \
  -d "$UDID" \
  --dart-define=GIT_SHA="$(git rev-parse HEAD)" \
  --dart-define=ENABLE_DIAGNOSTICS_SCREEN=true \
  --dart-define=ACCEPTANCE_TEST=true \
  --dart-define=BACKEND_ENV="local-test:${HOST}" &
DRIVE_PID=$!
END=$(( $(date +%s) + DEADLINE_SECONDS ))
while kill -0 "$DRIVE_PID" 2>/dev/null; do
  if [ "$(date +%s)" -ge "$END" ]; then
    echo "TIMEOUT: $TARGET did not finish within ${DEADLINE_SECONDS}s — killing it" >&2
    pkill -TERM -P "$DRIVE_PID" 2>/dev/null || true
    kill -9 "$DRIVE_PID" 2>/dev/null || true
    pkill -9 -f "flutter_tools.*drive" 2>/dev/null || true
    exit 124
  fi
  sleep 3
done
wait "$DRIVE_PID"
