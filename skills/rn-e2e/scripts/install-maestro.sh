#!/usr/bin/env bash
# Install Maestro (and JDK 17 if no Java 17+ is available), into the home directory. Idempotent.
# Run only after the developer agreed: it downloads and runs Maestro's official installer.
#
# Usage: install-maestro.sh
#
# - Java: keeps any Java 17+ already there; otherwise installs Temurin 17 into rn-starter's folder
#   ($RN_STARTER_HOME/jdk-17), where rn-starter's env.sh already looks for it.
# - Maestro: https://get.maestro.mobile.dev into ~/.maestro (its default), no sudo.
# - PATH: a marked block in the shell rc file (# >>> rn-starter:maestro >>>); env.sh also adds
#   ~/.maestro/bin for this session.
# macOS and Linux. On Windows, install Maestro by its docs (Android flows only).
#
# Exit codes: 0 ready · 1 error

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../rn-starter/scripts/lib.sh
source "$here/../../rn-starter/scripts/lib.sh"
os="$(os_name)"; arch="$(cpu_arch)"
[ "$os" = mac ] || [ "$os" = linux ] || die "Windows: install Maestro by its docs (https://docs.maestro.dev); it runs Android flows there."

# ---------------------------------------------------------------- Java 17+
java_major() { "$1" -version 2>&1 | head -n1 | sed -E 's/.*version "(1\.)?([0-9]+).*/\2/'; }
java_bin=""
if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then java_bin="$JAVA_HOME/bin/java"; else java_bin="$(command -v java 2>/dev/null || true)"; fi
if [ -n "$java_bin" ] && [ "$(java_major "$java_bin")" -ge 17 ] 2>/dev/null; then
  log "Java $(java_major "$java_bin") already available ($java_bin)"
else
  jdk_os="$os"; jdk_arch="$([ "$arch" = arm64 ] && echo aarch64 || echo x64)"
  url="https://api.adoptium.net/v3/binary/latest/17/ga/$jdk_os/$jdk_arch/jdk/hotspot/normal/eclipse"
  log "Downloading JDK 17 (Temurin) for $jdk_os/$jdk_arch"
  tmp="$(mktemp -d)"
  download "$url" "$tmp/jdk.tar.gz"
  rm -rf "$RN_STARTER_HOME/jdk-17"; mkdir -p "$RN_STARTER_HOME/jdk-17"
  tar -xzf "$tmp/jdk.tar.gz" -C "$RN_STARTER_HOME/jdk-17" --strip-components=1
  rm -rf "$tmp"
  if [ -d "$RN_STARTER_HOME/jdk-17/Contents/Home" ]; then export JAVA_HOME="$RN_STARTER_HOME/jdk-17/Contents/Home"; else export JAVA_HOME="$RN_STARTER_HOME/jdk-17"; fi
  export PATH="$JAVA_HOME/bin:$PATH"
  write_rc_block java "export JAVA_HOME=\"$JAVA_HOME\"
export PATH=\"\$JAVA_HOME/bin:\$PATH\""
  log "Installed JDK: $("$JAVA_HOME/bin/java" -version 2>&1 | head -n1)"
fi

# ---------------------------------------------------------------- Maestro
if [ -x "$HOME/.maestro/bin/maestro" ]; then
  log "Maestro already installed: $("$HOME/.maestro/bin/maestro" --version 2>/dev/null | tail -n1)"
else
  log "Installing Maestro (official installer, into ~/.maestro)"
  tmp="$(mktemp -d)"
  download "https://get.maestro.mobile.dev" "$tmp/install.sh"
  bash "$tmp/install.sh"
  rm -rf "$tmp"
  [ -x "$HOME/.maestro/bin/maestro" ] || die "Maestro install failed: ~/.maestro/bin/maestro not found"
fi
write_rc_block maestro 'export PATH="$HOME/.maestro/bin:$PATH"'
export PATH="$HOME/.maestro/bin:$PATH"
log "Maestro $(maestro --version 2>/dev/null | tail -n1) ready. Open a new terminal (or source env.sh) to have it on PATH."
