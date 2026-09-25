#!/usr/bin/env bash
# Sets the app's OS-level location permission (and a fixed GPS fix) on a
# simulator/emulator BEFORE a persona runs, because a native permission
# dialog cannot be tapped from inside an integration test.
#   scripts/set_location_permission.sh <device-id> grant|revoke
set -euo pipefail
DEVICE="${1:?Usage: $0 <device-id> grant|revoke}"
MODE="${2:?Usage: $0 <device-id> grant|revoke}"
PKG=com.niswah.niswah
case "$DEVICE" in
  emulator-*)
    if [ "$MODE" = grant ]; then
      adb -s "$DEVICE" shell pm grant "$PKG" android.permission.ACCESS_FINE_LOCATION || true
      adb -s "$DEVICE" shell pm grant "$PKG" android.permission.ACCESS_COARSE_LOCATION || true
      adb -s "$DEVICE" shell settings put secure location_mode 3 || true
      adb -s "$DEVICE" emu geo fix 46.6753 24.7136   # Riyadh (lon lat)
    else
      adb -s "$DEVICE" shell pm revoke "$PKG" android.permission.ACCESS_FINE_LOCATION || true
      adb -s "$DEVICE" shell pm revoke "$PKG" android.permission.ACCESS_COARSE_LOCATION || true
    fi ;;
  *)
    if [ "$MODE" = grant ]; then
      xcrun simctl privacy "$DEVICE" grant location "$PKG"
      xcrun simctl location "$DEVICE" set 24.7136,46.6753
    else
      xcrun simctl privacy "$DEVICE" revoke location "$PKG"
    fi ;;
esac
echo "location permission: $MODE on $DEVICE"
