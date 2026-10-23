#!/usr/bin/env bash
# EAS readiness: eas-cli, the Expo login, the accounts it can use, and the project link. Read-only.
#
# Usage: eas-status.sh [project-dir]   (default: current directory)
#
# Uses the project's eas-cli if it has one, a global `eas` if it is the latest release, else
# `npx eas-cli@<latest>` (EAS servers reject old CLIs, so it isn't pinned to an older one). Prints JSON: cli version and how it was run,
# logged-in user, accounts (personal + organizations, with role), and the project's EAS project id
# and owner from app.json (Expo) — never .env.
#
# Exit codes: 0 logged in · 1 error · 2 waiting on the developer (not logged in — prints
#             ACTION REQUIRED with the command they run themselves)

set -euo pipefail
dir="$(cd "${1:-.}" && pwd)"
command -v node >/dev/null 2>&1 || { echo "node not found — source rn-starter/scripts/env.sh first" >&2; exit 1; }

# A global eas that lags behind the latest release is skipped: EAS rejects old CLIs, and flags differ.
latest="$(npm view eas-cli version 2>/dev/null || true)"
if [ -x "$dir/node_modules/.bin/eas" ]; then eas_cmd=("$dir/node_modules/.bin/eas"); how="project devDependency"
elif command -v eas >/dev/null 2>&1 && { [ -z "$latest" ] || eas --version 2>/dev/null | grep -q "eas-cli/$latest "; }; then
  eas_cmd=(eas); how="global eas"
else eas_cmd=(npx --yes "eas-cli@${latest:-latest}"); how="npx eas-cli@${latest:-latest}"
fi

cd "$dir"
version="$("${eas_cmd[@]}" --version 2>/dev/null | grep -o 'eas-cli/[0-9.]*' | head -1 || true)"
[ -n "$version" ] || { echo "could not run eas-cli ($how)" >&2; exit 1; }
set +e
who="$("${eas_cmd[@]}" whoami 2>/dev/null)"
who_status=$?
set -e

WHO="$who" VERSION="$version" HOW="$how" node - "$dir" <<'EOF'
const fs = require('fs');
const path = require('path');
const dir = process.argv[2];
const lines = (process.env.WHO || '').split('\n').map((l) => l.trim()).filter(Boolean);
const loggedIn = lines.length > 0 && !/^not logged in/i.test(lines[0]);
const accounts = lines.filter((l) => l.startsWith('•')).map((l) => {
  const m = l.match(/^•\s*(\S+)\s*\(Role:\s*([^)]+)\)/);
  return m ? { name: m[1], role: m[2] } : { name: l.replace(/^•\s*/, ''), role: null };
});
let projectId = null, owner = null, slug = null;
try {
  const app = JSON.parse(fs.readFileSync(path.join(dir, 'app.json'), 'utf8')).expo ?? {};
  projectId = app.extra?.eas?.projectId ?? null; owner = app.owner ?? null; slug = app.slug ?? null;
} catch {}
const out = {
  cli: process.env.VERSION, runVia: process.env.HOW,
  loggedIn, user: loggedIn ? lines[0] : null, accounts,
  project: { slug, projectId, owner, linked: !!projectId },
};
console.log(JSON.stringify(out, null, 2));
if (!loggedIn) {
  console.log('ACTION REQUIRED');
  console.log('Log in to Expo yourself (the password never goes through Claude):');
  console.log('  in this session: ! npx eas-cli login');
  console.log('  or in your own terminal: npx eas-cli login');
  console.log('No Expo account yet? Create one free at https://expo.dev/signup, then log in.');
  process.exitCode = 2;
}
EOF
