#!/usr/bin/env bash
# Runs the notification continuity suite under a matrix of machine time
# zones. Each pinned-clock scenario in the test is a LOCAL DateTime, so
# the machine zone supplies the UTC offset: UTC itself (what CI runs
# in), Riyadh (+3, the app's home market), Kolkata (+5:30), Lord Howe
# (+10:30/+11 half-hour DST), Kiritimati (+14, the furthest-ahead zone —
# its local date is a full day ahead of UTC for most of the day),
# Los Angeles (-8) and Pago Pago (-11, furthest behind).
#
# Usage: scripts/run_notification_clock_matrix.sh [repeats-per-zone]
set -euo pipefail
cd "$(dirname "$0")/.."
REPEATS="${1:-1}"
ZONES=(UTC Asia/Riyadh Asia/Kolkata Australia/Lord_Howe Pacific/Kiritimati America/Los_Angeles Pacific/Pago_Pago)
fail=0
for zone in "${ZONES[@]}"; do
  for i in $(seq 1 "$REPEATS"); do
    if out=$(TZ="$zone" flutter test test/notification_multi_day_continuity_test.dart test/bleeding_episode_repository_test.dart 2>&1); then
      echo "PASS  TZ=$zone run $i"
    else
      echo "FAIL  TZ=$zone run $i"; echo "$out" | tail -25; fail=1
    fi
  done
done
exit $fail
