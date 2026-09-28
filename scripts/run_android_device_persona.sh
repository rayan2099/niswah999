#!/usr/bin/env bash
# Android-emulator personas that need the HOST to act on the device while the
# test runs (a Flutter test cannot press a system notification or change the
# OS time zone). Local disposable backend only (the kill switch runs first).
#
#   scripts/run_android_device_persona.sh <emulator-id> <integration_test/xN_*.dart>
#
# The test prints marker lines through its own log; this script reacts:
#   "HOST TAP NOTIFICATION <text>"  -> wait until a notification containing
#        <text> is posted by the app, pull the shade, and tap it (real
#        uiautomator tap on the real notification).
#   "HOST SET TIMEZONE <Area/City>" -> set the emulator's time zone and let
#        the OS broadcast the change.
#   "HOST CYCLE APP"                -> press HOME, wait, relaunch the app
#        (a real pause/resume, which is what makes the app re-read the zone).
#   "HOST VERIFY ALARMS <Area/City> <HH:MM>" -> the app's pending alarms
#        (dumpsys alarm) must fire at HH:MM LOCAL in that zone; a mismatch
#        fails the run (exit 5) in addition to the test's own verdict.
#   "HOST GRANT <permission>"       -> pm grant (only for permissions a test
#        cannot answer through a native dialog).
# It also pre-grants POST_NOTIFICATIONS and exact-alarm access (the native
# permission dialogs cannot be answered from a Flutter test).
set -uo pipefail
DEVICE="${1:?Usage: $0 <emulator-id> <target.dart>}"
TARGET="${2:?Usage: $0 <emulator-id> <target.dart>}"
cd "$(dirname "$0")/.."
PKG=com.niswah.niswah
python3 scripts/assert_test_backend.py --env-file .env || exit 3
BACKEND_HOST="$(python3 -c "import re;u=[l.split('=',1)[1].strip() for l in open('.env') if l.startswith('SUPABASE_URL=')][0];print(re.match(r'https?://([^/@]+)',u).group(1))")"
LOG="$(mktemp)"; trap 'rm -f "$LOG"; adb -s "$DEVICE" shell service call alarm 3 s16 "${ORIG_TZ:-UTC}" >/dev/null 2>&1' EXIT
ORIG_TZ="$(adb -s "$DEVICE" shell getprop persist.sys.timezone | tr -d '\r')"

# Install the APK (a drive uninstalls the app when it finishes) and pre-grant.
APK=build/app/outputs/flutter-apk/app-debug.apk
[ -f "$APK" ] || bash scripts/run_persona_local.sh "$DEVICE" integration_test/p0_build_identity_test.dart >/dev/null 2>&1
adb -s "$DEVICE" install -r -t "$APK" >/dev/null 2>&1
adb -s "$DEVICE" shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS >/dev/null 2>&1
adb -s "$DEVICE" shell appops set "$PKG" SCHEDULE_EXACT_ALARM allow >/dev/null 2>&1
adb -s "$DEVICE" shell settings put global auto_time_zone 0 >/dev/null 2>&1
rm -f build/integration_response_data.json

flutter drive --driver=test_driver/integration_test.dart --target="$TARGET" -d "$DEVICE" \
  --dart-define=GIT_SHA="$(git rev-parse HEAD)" --dart-define=ENABLE_DIAGNOSTICS_SCREEN=true \
  --dart-define=ACCEPTANCE_TEST=true --dart-define=BACKEND_ENV="local-test:${BACKEND_HOST}" \
  ${XZ_FORCE_DIRECTION:+--dart-define=XZ_FORCE_DIRECTION="$XZ_FORCE_DIRECTION"} \
  > "$LOG" 2>&1 &
PID=$!
DEADLINE=$(( $(date +%s) + ${PERSONA_TIMEOUT_SECONDS:-1800} ))
handled=0

tap_notification() {
  local text="$1" deadline=$(( $(date +%s) + 1500 ))
  echo "==> waiting for a notification containing: $text"
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if adb -s "$DEVICE" shell dumpsys notification --noredact 2>/dev/null | grep -q "pkg=$PKG.*" &&
       adb -s "$DEVICE" shell dumpsys notification --noredact 2>/dev/null | grep -qF "$text"; then
      break
    fi
    sleep 5
  done
  adb -s "$DEVICE" shell cmd statusbar expand-notifications >/dev/null 2>&1; sleep 3
  for attempt in 1 2 3; do
    adb -s "$DEVICE" shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
    adb -s "$DEVICE" pull /sdcard/ui.xml /tmp/ui_notif.xml >/dev/null 2>&1
    XY="$(python3 - "$text" <<'PY'
import re, sys, xml.etree.ElementTree as ET
text = sys.argv[1]
try:
    root = ET.parse('/tmp/ui_notif.xml').getroot()
except Exception:
    sys.exit(0)
for n in root.iter('node'):
    if text in (n.get('text') or '') or text in (n.get('content-desc') or ''):
        m = re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', n.get('bounds', ''))
        if m:
            x1, y1, x2, y2 = map(int, m.groups())
            print((x1 + x2) // 2, (y1 + y2) // 2)
            break
PY
)"
    if [ -n "$XY" ]; then
      echo "==> tapping the notification at $XY"
      adb -s "$DEVICE" shell input tap $XY
      return 0
    fi
    sleep 3
  done
  # Self-contained diagnostic (the app is uninstalled by the time the run
  # finishes, so this cannot be captured after the fact): was the
  # notification actually posted by the OS, and did an exact-alarm exist
  # for it at all? Distinguishes "posted but the uiautomator tap missed
  # it" from "never posted" without needing a live parallel poll.
  echo "==> diagnostic: dumpsys notification for $PKG (raw grep, 5 lines each side)" >&2
  adb -s "$DEVICE" shell dumpsys notification --noredact 2>/dev/null \
    | grep -B5 -A5 "$PKG" >&2
  echo "==> diagnostic: notification listener / dumpsys uiautomator dump root" >&2
  adb -s "$DEVICE" shell dumpsys notification 2>/dev/null | grep -c "NotificationRecord" >&2
  cat /tmp/ui_notif.xml 2>/dev/null | grep -o 'text="[^"]*"' | sort -u >&2
  echo "==> diagnostic: dumpsys alarm for $PKG" >&2
  adb -s "$DEVICE" shell dumpsys alarm 2>/dev/null | grep -A2 "$PKG" >&2
  echo "==> could not find the notification on screen" >&2
  return 1
}

while kill -0 "$PID" 2>/dev/null; do
  if [ "$(date +%s)" -ge "$DEADLINE" ]; then echo "TIMEOUT: killing the drive" >&2; kill -9 "$PID" 2>/dev/null; break; fi
  n="$(grep -c "HOST TAP NOTIFICATION" "$LOG" 2>/dev/null)"
  if [ "${n:-0}" -gt "$handled" ]; then
    handled=$n
    text="$(grep "HOST TAP NOTIFICATION" "$LOG" | tail -1 | sed 's/.*HOST TAP NOTIFICATION //' | tr -d '\r')"
    tap_notification "$text"
  fi
  tz="$(grep "HOST SET TIMEZONE" "$LOG" 2>/dev/null | tail -1 | sed 's/.*HOST SET TIMEZONE //' | tr -d '\r')"
  if [ -n "$tz" ] && [ "$tz" != "${LAST_TZ:-}" ]; then
    LAST_TZ="$tz"; echo "==> setting the emulator time zone to $tz"
    adb -s "$DEVICE" shell service call alarm 3 s16 "$tz" >/dev/null 2>&1
    adb -s "$DEVICE" shell am broadcast -a android.intent.action.TIMEZONE_CHANGED >/dev/null 2>&1
  fi
  c="$(grep -c "HOST CYCLE APP" "$LOG" 2>/dev/null)"
  if [ "${c:-0}" -gt "${cycled:-0}" ]; then
    cycled=$c; echo "==> cycling the app (HOME, then relaunch)"
    adb -s "$DEVICE" shell input keyevent KEYCODE_HOME; sleep 6
    adb -s "$DEVICE" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  fi
  v="$(grep -c "HOST VERIFY ALARMS" "$LOG" 2>/dev/null)"
  if [ "${v:-0}" -gt "${verified:-0}" ]; then
    verified=$v
    line="$(grep "HOST VERIFY ALARMS" "$LOG" | tail -1 | sed 's/.*HOST VERIFY ALARMS //' | tr -d '\r')"
    zone="${line%% *}"; want="${line##* }"
    adb -s "$DEVICE" shell dumpsys alarm > /tmp/alarms.txt 2>/dev/null
    python3 - "$zone" "$want" "$PKG" <<'PY' || ALARM_FAIL=1
import re, sys, datetime
from zoneinfo import ZoneInfo
zone, want, pkg = sys.argv[1:4]
txt = open('/tmp/alarms.txt', errors='ignore').read()
# every "when" belonging to a pending alarm of the app
times = []
for block in re.split(r'\n(?=\s*(?:RTC|ELAPSED)(?:_WAKEUP)?\s+#)', txt):
    if pkg in block:
        # The header line reads "...origWhen 1790568000000 whenElapsed...
        # <pkg>}" (a SPACE, not "=") on this dumpsys version; a later,
        # separate line repeats it as "origWhen=<human date>" (no epoch
        # digits at all). Match the actual header format first, and keep
        # the "=" form as a fallback for other dumpsys versions/wordings.
        m = (
            re.search(r'origWhen\s+(\d{13})', block)
            or re.search(r'\bwhen[= ]\s*(\d{13})', block)
            or re.search(r'origWhen=(\d{13})', block)
        )
        if m:
            times.append(int(m.group(1)))
if not times:
    print(f"ALARM VERIFY FAILED: no pending alarm found for {pkg}")
    sys.exit(1)
# The package legitimately schedules SEVERAL independent reminder types
# (this test's own check-in reminder, plus e.g. a fixed-hour wellbeing
# reminder) under the same shared receiver tag, at DIFFERENT times by
# design -- found live, this run had 30 alarms at "want" and 1 unrelated
# one at a different fixed hour. The claim under test is "the check-in
# reminder re-derived to want local", i.e. AT LEAST ONE alarm at "want",
# not that every alarm the app owns shares one time.
at_want = []
other = []
for t in sorted(set(times)):
    local = datetime.datetime.fromtimestamp(t / 1000, ZoneInfo(zone))
    (at_want if local.strftime('%H:%M') == want else other).append(local.isoformat())
print(
    f"ALARM VERIFY: {len(set(times))} pending alarm(s) for {pkg}; "
    f"{len(at_want)} at {want} {zone}; {len(other)} at another time "
    f"(other reminder types, tolerated): {other}"
)
sys.exit(0 if at_want else 1)
PY
  fi
  sleep 2
done
wait "$PID" 2>/dev/null; RC=$?
[ "${ALARM_FAIL:-0}" = 1 ] && { echo "ALARM VERIFICATION FAILED" >&2; cat "$LOG"; exit 5; }
cat "$LOG"
exit $RC
