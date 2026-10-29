#!/usr/bin/env bash
# Shared helpers for rn-starter scripts. Source it; don't execute it.

RN_STARTER_HOME="${RN_STARTER_HOME:-$HOME/.local/share/rn-starter}"
# shellcheck disable=SC2034 # used by the scripts that source this file
FNM_DIR_DEFAULT="$HOME/.local/share/fnm"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

os_name() {
  case "$(uname -s)" in
    Darwin) echo mac ;;
    Linux)  echo linux ;;
    MINGW*|MSYS*|CYGWIN*) echo windows ;;   # Git Bash — what Claude Code uses on Windows
    *)      echo unsupported ;;
  esac
}

# On Windows the bash entry scripts hand over to their PowerShell twin in scripts/windows/,
# so the skill runs the same command on every OS. Flags are passed through unchanged.
# Usage (right after sourcing lib.sh): delegate_to_windows <name>.ps1 "$@"
delegate_to_windows() {
  [ "$(os_name)" = windows ] || return 0
  # shellcheck disable=SC2154 # $here is set by the script that sources this file
  local ps1="$here/windows/$1"; shift
  exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$ps1")" "$@"
}

# Normalized CPU arch: arm64 | x64
cpu_arch() {
  case "$(uname -m)" in
    arm64|aarch64) echo arm64 ;;
    x86_64|amd64)  echo x64 ;;
    *)             uname -m ;;
  esac
}

default_android_home() {
  if [ "$(os_name)" = mac ]; then echo "$HOME/Library/Android/sdk"; else echo "$HOME/Android/Sdk"; fi
}

# The rc file the dev's login shell reads.
shell_rc_file() {
  case "$(basename "${SHELL:-}")" in
    zsh)  echo "$HOME/.zshrc" ;;
    bash) if [ "$(os_name)" = mac ]; then echo "$HOME/.bash_profile"; else echo "$HOME/.bashrc"; fi ;;
    *)    echo "$HOME/.profile" ;;
  esac
}

# write_rc_block <name> <content>
# Writes (or replaces) a marked block in the shell rc file so reruns never duplicate lines.
write_rc_block() {
  local name="$1" content="$2" rc begin end tmp
  rc="$(shell_rc_file)"
  begin="# >>> rn-starter:$name >>>"
  end="# <<< rn-starter:$name <<<"
  touch "$rc"
  tmp="$(mktemp)"
  awk -v b="$begin" -v e="$end" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    !skip { print }
  ' "$rc" > "$tmp"
  # Separate from previous content with one blank line, without piling up blanks on reruns.
  if [ -s "$tmp" ] && [ -n "$(tail -n1 "$tmp")" ]; then echo >> "$tmp"; fi
  { cat "$tmp"; printf '%s\n%s\n%s\n' "$begin" "$content" "$end"; } > "$rc"
  rm -f "$tmp"
  log "Updated $rc ($name)"
}

# Download with retries; fails loudly instead of leaving a half file behind.
download() {
  local url="$1" out="$2"
  curl -fL --retry 3 --retry-delay 2 --progress-bar -o "$out.part" "$url" && mv "$out.part" "$out"
}
