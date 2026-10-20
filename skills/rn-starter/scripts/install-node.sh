#!/usr/bin/env bash
# Install fnm + Node LTS into the home directory. No Homebrew, no sudo. Idempotent.
#
# Usage: install-node.sh [node-version]   (default: lts-latest)

set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"
delegate_to_windows install-node.ps1 "$@"

node_version="${1:-lts-latest}"
[ "$(os_name)" = unsupported ] && die "Unsupported OS: $(uname -s)."

fnm_dir="${FNM_DIR:-$FNM_DIR_DEFAULT}"

if [ -x "$fnm_dir/fnm" ]; then
  log "fnm already installed at $fnm_dir"
else
  log "Installing fnm into $fnm_dir"
  # --force-install: download the binary directly instead of going through Homebrew,
  # which a clean machine doesn't have and which needs sudo to install.
  # --skip-shell: we write our own marked rc block below so reruns stay clean.
  curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir "$fnm_dir" --skip-shell --force-install
fi

export PATH="$fnm_dir:$PATH"
eval "$(fnm env --shell bash)"

log "Installing Node ($node_version)"
if [ "$node_version" = lts-latest ]; then
  fnm install --lts   # also creates the `lts-latest` alias
else
  fnm install "$node_version"
fi
fnm default "$node_version"
fnm use "$node_version" >/dev/null

shell_name="$(basename "${SHELL:-bash}")"
case "$shell_name" in zsh|bash|fish) ;; *) shell_name=bash ;; esac
write_rc_block fnm "export PATH=\"$fnm_dir:\$PATH\"
eval \"\$(fnm env --use-on-cd --shell $shell_name)\""

log "node $(node -v), npm $(npm -v)"
log "Open a new terminal (or run: source $(shell_rc_file)) to use node outside this session."
