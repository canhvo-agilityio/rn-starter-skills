#!/usr/bin/env bash
# Boot an iPhone simulator (if none is booted), show the Simulator window and wait until it is ready.
#
# Usage: start-simulator.sh [device-name]   (default: an already booted iPhone, else the newest iPhone)
# Prints the booted device's UDID on the last line.

set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

[ "$(os_name)" = mac ] || die "The iOS Simulator only runs on macOS."
command -v xcrun >/dev/null 2>&1 || die "Xcode not set up. Run setup-ios.sh first."

udid_re='[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}'
booted="$(xcrun simctl list devices booted | grep -E '^ +iPhone' | grep -oE "$udid_re" | head -n1 || true)"

if [ -n "$booted" ]; then
  udid="$booted"
  log "Using already booted simulator"
else
  name="${1:-}"
  if [ -n "$name" ]; then
    udid="$(xcrun simctl list devices available | grep -E "^ +$name \(" | grep -oE "$udid_re" | head -n1 || true)"
    [ -n "$udid" ] || die "No available simulator named '$name'. See: xcrun simctl list devices available"
  else
    # Newest runtime is listed last; pick its first iPhone.
    udid="$(xcrun simctl list devices available | awk '/^-- iOS/ {sec=$0} /^ +iPhone/ {last[sec]=last[sec] ? last[sec] : $0; order=sec} END {print last[order]}' | grep -oE "$udid_re" || true)"
    [ -n "$udid" ] || die "No iPhone simulator available. Run setup-ios.sh first."
  fi
  log "Booting $(xcrun simctl list devices | grep "$udid" | sed -E 's/^ +//; s/ \(.*//')"
  xcrun simctl boot "$udid" 2>/dev/null || true
fi

open -a Simulator --args -CurrentDeviceUDID "$udid"
xcrun simctl bootstatus "$udid" -b >/dev/null
log "Simulator ready"
echo "$udid"
