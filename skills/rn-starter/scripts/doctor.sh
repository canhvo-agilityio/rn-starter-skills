#!/usr/bin/env bash
# Read-only environment check for React Native development. Installs nothing.
#
# Usage: doctor.sh [--android] [--ios] [--cocoapods]
#   --android     also check JDK 17, Android SDK, emulator and AVDs
#   --ios         also check Xcode, its license/first-launch, iOS Simulator runtime and devices (macOS)
#   --cocoapods   also check CocoaPods (needed for React Native CLI on iOS, not for Expo Go)
#
# Output: one line per check — "ok|warn|missing  <name>  <detail>" — then a summary line:
#   summary missing=<comma list> warn=<comma list>

set -u
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"
delegate_to_windows doctor.ps1 "$@"
# shellcheck source=env.sh
. "$here/env.sh"

check_android=0; check_ios=0; check_pods=0
for arg in "$@"; do
  case "$arg" in
    --android)   check_android=1 ;;
    --ios)       check_ios=1 ;;
    --cocoapods) check_ios=1; check_pods=1 ;;
    *) echo "unknown option: $arg" >&2; exit 64 ;;
  esac
done

missing=()
warns=()
row() {
  # row <status> <name> <detail>
  printf '%-8s %-16s %s\n' "$1" "$2" "$3"
  case "$1" in
    missing) missing+=("$2") ;;
    warn)    warns+=("$2") ;;
  esac
}

version_of() { "$@" 2>/dev/null | head -n1; }

# --- system ---
os="$(os_name)"
if [ "$os" = unsupported ]; then
  row missing os "$(uname -s) is not supported (macOS or Linux only)"
else
  row ok os "$os $(cpu_arch) ($(uname -r))"
fi
row ok shell "$(basename "${SHELL:-unknown}") → $(shell_rc_file)"

if [ "$os" = mac ]; then
  if xcode-select -p >/dev/null 2>&1; then
    row ok xcode-clt "$(xcode-select -p)"
  else
    row missing xcode-clt "Command Line Tools not installed (needed for git) — run: xcode-select --install"
  fi
fi

if command -v git >/dev/null 2>&1 && git --version >/dev/null 2>&1; then
  row ok git "$(git --version | awk '{print $3}')"
else
  row missing git "not installed"
fi

# --- node ---
if command -v node >/dev/null 2>&1; then
  v="$(node -v | sed 's/^v//')"
  major="${v%%.*}"; rest="${v#*.}"; minor="${rest%%.*}"
  # React Native 0.88 / Expo SDK 58 engines: ^22.13 || ^24.3 || >=26 (even majors)
  if { [ "$major" -eq 22 ] && [ "$minor" -ge 13 ]; } || { [ "$major" -eq 24 ] && [ "$minor" -ge 3 ]; } \
     || { [ "$major" -ge 26 ] && [ $((major % 2)) -eq 0 ]; }; then
    row ok node "$v ($(command -v node))"
  else
    row warn node "$v is not supported — need ^22.13, ^24.3 or an even major ≥ 26 (LTS)"
  fi
else
  row missing node "not installed"
fi

if command -v fnm >/dev/null 2>&1; then
  row ok fnm "$(fnm --version | awk '{print $2}')"
elif [ -s "$HOME/.nvm/nvm.sh" ]; then
  row ok nvm "found at ~/.nvm (fnm not needed)"
else
  row warn node-manager "no fnm/nvm — fine if Node is already OK"
fi

# --- package managers (all optional; npm comes with node) ---
for pm in npm pnpm yarn bun; do
  if command -v "$pm" >/dev/null 2>&1; then
    pv="$(version_of "$pm" --version)"
    if [ "$pm" = pnpm ] && [ "${pv%%.*}" = 11 ]; then
      # pnpm 11 keeps registry connections open after installing, so installs never return.
      row warn pnpm "$pv — installs can hang after 'Done'; update: npm install -g pnpm@latest (or brew upgrade pnpm)"
    else
      row ok "$pm" "$pv"
    fi
  else
    printf '%-8s %-16s %s\n' "-" "$pm" "not installed (optional)"
  fi
done

if command -v watchman >/dev/null 2>&1; then
  row ok watchman "$(version_of watchman --version)"
else
  printf '%-8s %-16s %s\n' "-" watchman "not installed (optional; helps with large projects)"
fi

# --- android ---
if [ "$check_android" -eq 1 ]; then
  if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then
    jv="$("$JAVA_HOME/bin/java" -version 2>&1 | head -n1 | sed -E 's/.*version "([^"]+)".*/\1/')"
    case "$jv" in
      17|17.*) row ok jdk "$jv ($JAVA_HOME)" ;;
      *)       row warn jdk "$jv at $JAVA_HOME — React Native recommends JDK 17" ;;
    esac
  else
    row missing jdk "JDK 17 not found (JAVA_HOME unset)"
  fi

  if [ -n "${ANDROID_HOME:-}" ] && [ -d "$ANDROID_HOME" ]; then
    row ok android-sdk "$ANDROID_HOME"
    [ -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ] \
      && row ok sdkmanager "cmdline-tools/latest" \
      || row missing sdkmanager "cmdline-tools/latest not installed"
    [ -x "$ANDROID_HOME/platform-tools/adb" ] \
      && row ok adb "$("$ANDROID_HOME/platform-tools/adb" version | head -n1 | awk '{print $NF}')" \
      || row missing adb "platform-tools not installed"
    [ -x "$ANDROID_HOME/emulator/emulator" ] \
      && row ok emulator "installed" \
      || row missing emulator "emulator not installed"
    if ls "$ANDROID_HOME/platforms" 2>/dev/null | grep -q android-; then
      row ok platforms "$(ls "$ANDROID_HOME/platforms" | tr '\n' ' ')"
    else
      row missing platforms "no Android platform installed"
    fi
    if [ -x "$ANDROID_HOME/emulator/emulator" ]; then
      avds="$("$ANDROID_HOME/emulator/emulator" -list-avds 2>/dev/null | grep -v '^INFO' | tr '\n' ' ')"
      [ -n "$avds" ] && row ok avd "$avds" || row missing avd "no virtual device created"
    fi
  else
    row missing android-sdk "ANDROID_HOME not set and $(default_android_home) does not exist"
  fi

  if [ "$os" = linux ] && [ ! -e /dev/kvm ]; then
    row warn kvm "/dev/kvm missing — emulator will be very slow or fail; enable virtualization"
  fi
fi

# --- ios ---
if [ "$check_ios" -eq 1 ]; then
  if [ "$os" != mac ]; then
    row missing xcode "iOS Simulator needs macOS"
  elif [ ! -d /Applications/Xcode.app ] && ! ls -d /Applications/Xcode*.app >/dev/null 2>&1; then
    row missing xcode "Xcode not installed (App Store, or the team's .xip)"
  else
    dev_dir="$(xcode-select -p 2>/dev/null)"
    case "$dev_dir" in
      *Xcode*.app/Contents/Developer)
        row ok xcode "$(xcodebuild -version 2>/dev/null | head -n1) ($dev_dir)" ;;
      *)
        row missing xcode-select "points to '$dev_dir', not Xcode — dev runs: sudo xcode-select -s /Applications/Xcode.app" ;;
    esac
    if xcodebuild -license check >/dev/null 2>&1; then
      row ok xcode-license "accepted"
    else
      row missing xcode-license "not accepted — dev runs: sudo xcodebuild -license accept"
    fi
    if xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
      row ok xcode-first-run "done"
    else
      row missing xcode-first-run "first-launch packages missing — dev runs: sudo xcodebuild -runFirstLaunch"
    fi
    runtimes="$(xcrun simctl list runtimes 2>/dev/null | grep -E '^iOS ' | sed -E 's/ \(.*//' | tr '\n' ' ')"
    if [ -n "$runtimes" ]; then
      row ok ios-runtime "$runtimes"
      phones="$(xcrun simctl list devices available 2>/dev/null | grep -E '^ +iPhone' | sed -E 's/^ +//; s/ \(.*//' | head -n3 | paste -sd ',' -)"
      [ -n "$phones" ] && row ok ios-simulator "$phones" || row missing ios-simulator "no iPhone simulator device"
    else
      row missing ios-runtime "no iOS Simulator runtime — run: xcodebuild -downloadPlatform iOS"
    fi
  fi
  if [ "$check_pods" -eq 1 ]; then
    if command -v pod >/dev/null 2>&1; then
      row ok cocoapods "$(pod --version 2>/dev/null)"
    elif command -v brew >/dev/null 2>&1; then
      row missing cocoapods "not installed — run: brew install cocoapods"
    else
      row missing cocoapods "not installed; needs Homebrew first (macOS system Ruby is too old for CocoaPods)"
    fi
  fi
fi

join() { local IFS=,; echo "$*"; }
echo
echo "summary missing=$(join "${missing[@]+"${missing[@]}"}") warn=$(join "${warns[@]+"${warns[@]}"}")"
