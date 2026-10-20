#!/usr/bin/env bash
# Install everything needed to build and run React Native on an Android emulator,
# without Android Studio, Homebrew or sudo:
#   JDK 17 (Eclipse Temurin), Android command-line tools, platform-tools, emulator,
#   Android platform + system image, and one AVD.
# Idempotent: rerun it to fill in whatever is missing.
#
# Usage: install-android.sh --accept-licenses [--api 35] [--avd rn_pixel]
#   --accept-licenses  required: the dev has read and accepted the Android SDK License
#                      Agreement (https://developer.android.com/studio/terms)

set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"
delegate_to_windows install-android.ps1 "$@"

api=35
avd=rn_pixel
accepted=0
while [ $# -gt 0 ]; do
  case "$1" in
    --accept-licenses) accepted=1 ;;
    --api) api="$2"; shift ;;
    --avd) avd="$2"; shift ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

[ "$accepted" -eq 1 ] || die "The Android SDK license must be accepted by the developer first. Ask them, then rerun with --accept-licenses."

os="$(os_name)"; arch="$(cpu_arch)"
[ "$os" = unsupported ] && die "Unsupported OS: $(uname -s)."
mkdir -p "$RN_STARTER_HOME"

# shellcheck source=env.sh
. "$here/env.sh"

# ---------------------------------------------------------------- JDK 17
has_jdk17() {
  [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ] \
    && "$JAVA_HOME/bin/java" -version 2>&1 | head -n1 | grep -qE 'version "17(\.|")'
}

if has_jdk17; then
  log "JDK 17 already available at $JAVA_HOME"
else
  jdk_os="$os"; jdk_arch="$([ "$arch" = arm64 ] && echo aarch64 || echo x64)"
  url="https://api.adoptium.net/v3/binary/latest/17/ga/$jdk_os/$jdk_arch/jdk/hotspot/normal/eclipse"
  log "Downloading JDK 17 (Temurin) for $jdk_os/$jdk_arch"
  tmp="$(mktemp -d)"
  download "$url" "$tmp/jdk.tar.gz"
  rm -rf "$RN_STARTER_HOME/jdk-17"
  mkdir -p "$RN_STARTER_HOME/jdk-17"
  tar -xzf "$tmp/jdk.tar.gz" -C "$RN_STARTER_HOME/jdk-17" --strip-components=1
  rm -rf "$tmp"
  if [ -d "$RN_STARTER_HOME/jdk-17/Contents/Home" ]; then
    export JAVA_HOME="$RN_STARTER_HOME/jdk-17/Contents/Home"
  else
    export JAVA_HOME="$RN_STARTER_HOME/jdk-17"
  fi
  export PATH="$JAVA_HOME/bin:$PATH"
  has_jdk17 || die "JDK 17 install failed (JAVA_HOME=$JAVA_HOME)"
  log "Installed JDK: $("$JAVA_HOME/bin/java" -version 2>&1 | head -n1)"
fi

# ---------------------------------------------------------------- command-line tools
export ANDROID_HOME="${ANDROID_HOME:-$(default_android_home)}"
sdkmanager="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
avdmanager="$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager"

if [ -x "$sdkmanager" ]; then
  log "Android command-line tools already installed"
else
  log "Finding latest Android command-line tools"
  # Google publishes the zip name (with a build number) in the repository manifest.
  zip_name="$(curl -fsSL https://dl.google.com/android/repository/repository2-3.xml \
    | grep -oE "commandlinetools-$os-[0-9]+_latest\.zip" \
    | sort -t- -k3 -n | tail -n1)"
  [ -n "$zip_name" ] || die "Could not find the command-line tools download in Google's manifest."
  log "Downloading $zip_name"
  tmp="$(mktemp -d)"
  download "https://dl.google.com/android/repository/$zip_name" "$tmp/cmdline-tools.zip"
  unzip -q "$tmp/cmdline-tools.zip" -d "$tmp"
  mkdir -p "$ANDROID_HOME/cmdline-tools"
  rm -rf "$ANDROID_HOME/cmdline-tools/latest"
  mv "$tmp/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
  rm -rf "$tmp"
fi

# ---------------------------------------------------------------- SDK packages
abi="$([ "$arch" = arm64 ] && echo arm64-v8a || echo x86_64)"
image="system-images;android-$api;google_apis;$abi"

log "Recording license acceptance"
yes | "$sdkmanager" --sdk_root="$ANDROID_HOME" --licenses >/dev/null 2>&1 || true
[ -f "$ANDROID_HOME/licenses/android-sdk-license" ] || die "sdkmanager did not record the license (check JAVA_HOME / network and rerun)."

log "Installing SDK packages (this is the big download)"
"$sdkmanager" --sdk_root="$ANDROID_HOME" --install \
  "platform-tools" \
  "emulator" \
  "platforms;android-$api" \
  "$image"

# ---------------------------------------------------------------- AVD
# avdmanager (Java) resolves "home" from the OS user record, the emulator from $HOME.
# Pin the location so both always agree.
export ANDROID_USER_HOME="${ANDROID_USER_HOME:-$HOME/.android}"
if "$ANDROID_HOME/emulator/emulator" -list-avds 2>/dev/null | grep -qx "$avd"; then
  log "AVD '$avd' already exists"
else
  log "Creating AVD '$avd' ($image)"
  device="pixel_7"
  "$avdmanager" list device -c 2>/dev/null | grep -qx "$device" || device="pixel"
  echo no | "$avdmanager" create avd -n "$avd" -k "$image" -d "$device" >/dev/null
fi

# ---------------------------------------------------------------- shell rc
write_rc_block android "export JAVA_HOME=\"$JAVA_HOME\"
export ANDROID_HOME=\"$ANDROID_HOME\"
export PATH=\"\$JAVA_HOME/bin:\$ANDROID_HOME/platform-tools:\$ANDROID_HOME/emulator:\$ANDROID_HOME/cmdline-tools/latest/bin:\$PATH\""

log "Android toolchain ready. JAVA_HOME=$JAVA_HOME ANDROID_HOME=$ANDROID_HOME AVD=$avd"
