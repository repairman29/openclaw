#!/usr/bin/env bash
# Toggle "Run Linux terminal on Android" on Pixel when the Settings toggle is unresponsive.
# Usage: ./scripts/toggle-pixel-linux-terminal.sh [on|off|cycle]
# Requires: device connected via USB with USB debugging enabled.
#
# Pixel 8 Pro / Android 16 QPR beta: if the menu stays hidden after activation, try turning
# off Identity Check in Settings (reported workaround).

set -e
DEVICE="${ANDROID_SERIAL:-}"
if [[ -z "$DEVICE" ]]; then
  DEVICE=$(adb devices -l | awk '/device usb/{print $1; exit}')
fi
if [[ -z "$DEVICE" ]]; then
  echo "No Android device found. Connect Pixel via USB and ensure USB debugging is on." >&2
  exit 1
fi

# Packages that may control the Linux terminal (virt APEX). Try both.
PKGS="com.google.android.virtualmachine.res com.google.android.microdroid.empty_payload"

cmd() { adb -s "$DEVICE" shell "$@"; }

case "${1:-cycle}" in
  on)
    for p in $PKGS; do cmd "pm enable $p" 2>/dev/null || true; done
    echo "Linux terminal packages enabled. Open Settings > search 'Linux terminal' to confirm."
    ;;
  off)
    for p in $PKGS; do cmd "pm disable-user --user 0 $p" 2>/dev/null || true; done
    echo "Linux terminal packages disabled."
    ;;
  cycle)
    for p in $PKGS; do
      cmd "pm disable-user --user 0 $p" 2>/dev/null || true
    done
    sleep 1
    for p in $PKGS; do
      cmd "pm enable $p" 2>/dev/null || true
    done
    cmd "am force-stop com.android.settings"
    echo "Cycled Linux terminal (off then on). Open Settings > search 'Linux terminal' and check the toggle."
    ;;
  *)
    echo "Usage: $0 [on|off|cycle]" >&2
    exit 1
    ;;
esac
