#!/usr/bin/env bash
# Get a Mac ready to run apps in the iOS Simulator. Idempotent.
#
# Some steps need the developer (App Store sign-in, admin password). This script never
# asks for a password: when such a step is pending it prints the exact commands under
# "ACTION REQUIRED" and exits 2. Have the dev run them in their own terminal, then rerun.
#
# Usage: setup-ios.sh [--cocoapods]
#   --cocoapods   also install CocoaPods (React Native CLI on iOS needs it; Expo Go doesn't)
#
# Exit codes: 0 ready · 1 error · 2 waiting on the developer

set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"
# shellcheck source=env.sh
. "$here/env.sh"

want_pods=0
for arg in "$@"; do
  case "$arg" in
    --cocoapods) want_pods=1 ;;
    *) die "unknown option: $arg" ;;
  esac
done

[ "$(os_name)" = mac ] || die "The iOS Simulator only runs on macOS."

need_dev() {
  printf '\n\033[1;33mACTION REQUIRED\033[0m — the developer needs to do this, then rerun this script:\n\n%s\n\n' "$1"
  exit 2
}

# ---------------------------------------------------------------- Xcode app
xcode_app="$(ls -d /Applications/Xcode.app 2>/dev/null || ls -d /Applications/Xcode*.app 2>/dev/null | head -n1 || true)"
if [ -z "$xcode_app" ]; then
  need_dev "Install Xcode (free, ~15 GB incl. iOS Simulator):
  • App Store: open \"macappstore://apps.apple.com/app/xcode/id497799835\" and click Get
    (needs an Apple ID — a free one is fine; no paid developer account)
  • or, if your team shares an Xcode .xip: double-click it, then move Xcode.app to /Applications
Then open Xcode once and let it finish installing components."
fi
log "Xcode found: $xcode_app"

# ---------------------------------------------------------------- developer dir, license, first launch
pending=""
case "$(xcode-select -p 2>/dev/null)" in
  *Xcode*.app/Contents/Developer) ;;
  *) pending="${pending}  sudo xcode-select -s \"$xcode_app\"
" ;;
esac
# Before xcode-select points at Xcode, license/first-launch checks run against the CLT and
# report nonsense — so only check them once the developer dir is right.
if [ -z "$pending" ]; then
  xcodebuild -license check >/dev/null 2>&1 || pending="${pending}  sudo xcodebuild -license accept
"
  xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1 || pending="${pending}  sudo xcodebuild -runFirstLaunch
"
fi
if [ -n "$pending" ]; then
  need_dev "Run in Terminal (asks for your Mac password; the license command means you accept Apple's Xcode license):

$pending"
fi
log "$(xcodebuild -version | head -n1) is selected, license accepted, first launch done"

# ---------------------------------------------------------------- iOS Simulator runtime
if xcrun simctl list runtimes 2>/dev/null | grep -qE '^iOS '; then
  log "iOS Simulator runtime: $(xcrun simctl list runtimes | grep -E '^iOS ' | tail -n1 | sed -E 's/ \(.*//')"
else
  log "Downloading the iOS Simulator runtime (~8 GB, can take a while)"
  xcodebuild -downloadPlatform iOS
fi

# ---------------------------------------------------------------- an iPhone device
if xcrun simctl list devices available | grep -qE '^ +iPhone'; then
  log "iPhone simulator available"
else
  runtime_id="$(xcrun simctl list runtimes | grep -E '^iOS ' | tail -n1 | grep -oE 'com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]+')"
  type_id="$(xcrun simctl list devicetypes | grep -E '^iPhone' | tail -n1 | grep -oE 'com\.apple\.CoreSimulator\.SimDeviceType\.[A-Za-z0-9-]+')"
  [ -n "$runtime_id" ] && [ -n "$type_id" ] || die "Could not find an iOS runtime/device type to create a simulator."
  log "Creating simulator 'rn-iphone' ($type_id, $runtime_id)"
  xcrun simctl create rn-iphone "$type_id" "$runtime_id" >/dev/null
fi

# ---------------------------------------------------------------- CocoaPods (RN CLI only)
if [ "$want_pods" -eq 1 ]; then
  if command -v pod >/dev/null 2>&1; then
    log "CocoaPods $(pod --version)"
  elif command -v brew >/dev/null 2>&1; then
    log "Installing CocoaPods via Homebrew"
    brew install cocoapods
    log "CocoaPods $(pod --version)"
  else
    # macOS's built-in Ruby (2.6) is too old for current CocoaPods dependencies, and
    # Homebrew's installer needs an admin password — so the dev runs this one step.
    need_dev "Install Homebrew (asks for your Mac password):

  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"

(This script installs CocoaPods with it on the next run.)"
  fi
fi

log "iOS Simulator ready."
