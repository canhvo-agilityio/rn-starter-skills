#!/usr/bin/env bash
# Boot an Android emulator (if none is running) and wait until Android has finished booting.
#
# Usage: start-emulator.sh [avd-name]   (default: rn_pixel, else the first AVD found)
# Emulator output goes to $RN_STARTER_HOME/emulator.log

set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"
# shellcheck source=env.sh
. "$here/env.sh"

[ -n "${ANDROID_HOME:-}" ] && [ -x "$ANDROID_HOME/emulator/emulator" ] \
  || die "Android emulator not installed. Run install-android.sh first."

if adb devices | awk 'NR>1 && $2=="device"' | grep -q .; then
  log "A device/emulator is already connected:"
  adb devices | awk 'NR>1 && NF'
  exit 0
fi

avds="$(emulator -list-avds 2>/dev/null | grep -v '^INFO' || true)"
avd="${1:-}"
if [ -z "$avd" ]; then
  avd="$(echo "$avds" | grep -x rn_pixel || echo "$avds" | head -n1)"
fi
[ -n "$avd" ] || die "No AVD found. Run install-android.sh to create one."

mkdir -p "$RN_STARTER_HOME"
log "Starting emulator '$avd' (log: $RN_STARTER_HOME/emulator.log)"
nohup emulator -avd "$avd" -no-boot-anim -no-snapshot-save >"$RN_STARTER_HOME/emulator.log" 2>&1 &

adb wait-for-device
timeout=300; waited=0
until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
  sleep 3; waited=$((waited + 3))
  if [ "$waited" -ge "$timeout" ]; then
    tail -n 20 "$RN_STARTER_HOME/emulator.log" >&2
    die "Emulator did not finish booting within ${timeout}s."
  fi
done
# A fresh AVD often shows "<system app> isn't responding" on first boot, covering the app.
sleep 5
adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS >/dev/null 2>&1 || true
log "Emulator '$avd' is ready ($(adb devices | awk 'NR==2{print $1}'))"
