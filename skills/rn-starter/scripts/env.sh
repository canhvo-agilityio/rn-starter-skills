# Source this before commands that need tools installed by rn-starter:
#   source scripts/env.sh && node -v
# Safe to source many times; skips anything that is not installed.
# Works in bash and zsh. Does not use `set -e` because it runs in the caller's shell.

_rn_home="${RN_STARTER_HOME:-$HOME/.local/share/rn-starter}"

# CocoaPods and some Ruby/Gradle tooling misbehave without a UTF-8 locale
[ -n "${LANG:-}" ] || export LANG=en_US.UTF-8

# Homebrew (only used for CocoaPods on the RN CLI + iOS path)
for _b in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
  if [ -x "$_b" ]; then
    case ":$PATH:" in *":$(dirname "$_b"):"*) ;; *) eval "$("$_b" shellenv)" ;; esac
    break
  fi
done

# Node via fnm
for _d in "${FNM_DIR:-}" "$HOME/.local/share/fnm" "$HOME/Library/Application Support/fnm" "$HOME/.fnm"; do
  if [ -n "$_d" ] && [ -x "$_d/fnm" ]; then
    export FNM_DIR="$_d"
    case ":$PATH:" in *":$_d:"*) ;; *) export PATH="$_d:$PATH" ;; esac
    eval "$("$_d/fnm" env --shell bash)"
    "$_d/fnm" use --silent-if-unchanged default >/dev/null 2>&1 || true
    break
  fi
done

# JDK 17: prefer the one rn-starter installed, then any system JDK 17 (macOS)
if [ -z "${JAVA_HOME:-}" ] || [ ! -x "${JAVA_HOME:-/nonexistent}/bin/java" ]; then
  if [ -x "$_rn_home/jdk-17/Contents/Home/bin/java" ]; then
    export JAVA_HOME="$_rn_home/jdk-17/Contents/Home"
  elif [ -x "$_rn_home/jdk-17/bin/java" ]; then
    export JAVA_HOME="$_rn_home/jdk-17"
  elif [ -x /usr/libexec/java_home ] && /usr/libexec/java_home -v 17 >/dev/null 2>&1; then
    export JAVA_HOME="$(/usr/libexec/java_home -v 17)"
  fi
fi
[ -n "${JAVA_HOME:-}" ] && case ":$PATH:" in *":$JAVA_HOME/bin:"*) ;; *) export PATH="$JAVA_HOME/bin:$PATH" ;; esac

# Android SDK
if [ -z "${ANDROID_HOME:-}" ]; then
  if [ "$(uname -s)" = Darwin ]; then _sdk="$HOME/Library/Android/sdk"; else _sdk="$HOME/Android/Sdk"; fi
  [ -d "$_sdk" ] && export ANDROID_HOME="$_sdk"
fi
if [ -n "${ANDROID_HOME:-}" ]; then
  for _p in "$ANDROID_HOME/platform-tools" "$ANDROID_HOME/emulator" "$ANDROID_HOME/cmdline-tools/latest/bin"; do
    case ":$PATH:" in *":$_p:"*) ;; *) [ -d "$_p" ] && export PATH="$_p:$PATH" ;; esac
  done
fi

unset _rn_home _d _sdk _p _b
