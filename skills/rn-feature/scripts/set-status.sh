#!/usr/bin/env bash
# Set a ticket file's status in its frontmatter, so nobody edits it by hand (or with sed -i).
#
# Usage: set-status.sh <docs/tickets/<id>.md> <questions-open|ready|planned|in-progress|done>
#
# Prints the old and new status, then runs check-ticket.sh on the file: a status the file doesn't
# meet yet (done with a step still todo, ready with a blocking concern) is reported and reverted.
# Exit codes: 0 done · 1 error (no file, no frontmatter, bad status) · 3 reverted (check-ticket problems)

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
file="${1:-}"; status="${2:-}"
[ -n "$file" ] && [ -f "$file" ] && [ -n "$status" ] \
  || { echo "usage: set-status.sh <docs/tickets/<id>.md> <questions-open|ready|planned|in-progress|done>" >&2; exit 1; }
case "$status" in questions-open|ready|planned|in-progress|done) ;; *) echo "error: status must be questions-open, ready, planned, in-progress or done" >&2; exit 1 ;; esac
command -v node >/dev/null 2>&1 || { echo "error: node not found — source rn-starter/scripts/env.sh first" >&2; exit 1; }

backup="$(mktemp)"; trap 'rm -f "$backup"' EXIT
cp "$file" "$backup"
node - "$file" "$status" <<'EOF'
const fs = require('fs');
const [file, status] = process.argv.slice(2);
const text = fs.readFileSync(file, 'utf8');
const m = text.match(/^---\n([\s\S]*?)\n---/);
if (!m) { console.error('error: no frontmatter'); process.exit(1); }
const line = m[1].split('\n').find((l) => /^status:/.test(l));
if (!line) { console.error('error: no status: line in the frontmatter'); process.exit(1); }
const old = line.replace(/^status:\s*/, '').replace(/\s*#.*$/, '');
const comment = (line.match(/\s+#.*$/) || [''])[0];
const front = m[1].replace(line, `status: ${status}${comment}`);
fs.writeFileSync(file, text.replace(m[1], front));
console.log(`status: ${old} -> ${status}`);
EOF
if ! out="$(bash "$here/check-ticket.sh" "$file" 2>&1)"; then
  cp "$backup" "$file"
  echo "reverted: the file doesn't meet \"$status\" yet:" >&2
  echo "$out" | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{try{for(const p of JSON.parse(s).problems)console.error('  - '+p)}catch{console.error(s)}})"
  exit 3
fi
