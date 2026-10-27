#!/usr/bin/env bash
# Set a plan step's status in a ticket file, whatever padding the table has (Prettier aligns the
# columns, so a plain text replacement of "| todo |" misses rows silently).
#
# Usage: set-step.sh <docs/tickets/<id>.md> <step> <todo|doing|done|blocked|skipped>
#
# Prints the step's old and new status. Exit codes: 0 done · 1 error (no file, no Plan table,
# no such step, bad status)

set -euo pipefail
file="${1:-}"; step="${2:-}"; status="${3:-}"
[ -n "$file" ] && [ -f "$file" ] && [ -n "$step" ] && [ -n "$status" ] \
  || { echo "usage: set-step.sh <docs/tickets/<id>.md> <step> <todo|doing|done|blocked|skipped>" >&2; exit 1; }
case "$status" in todo|doing|done|blocked|skipped) ;; *) echo "error: status must be todo, doing, done, blocked or skipped" >&2; exit 1 ;; esac
command -v node >/dev/null 2>&1 || { echo "error: node not found — source rn-starter/scripts/env.sh first" >&2; exit 1; }

node - "$file" "$step" "$status" <<'EOF'
const fs = require('fs');
const [file, step, status] = process.argv.slice(2);
const lines = fs.readFileSync(file, 'utf8').split('\n');
const start = lines.findIndex((l) => /^##\s+Plan\s*$/i.test(l));
if (start === -1) { console.error('error: no "## Plan" section'); process.exit(1); }
let header = null; let statusCol = -1; let done = false;
for (let i = start + 1; i < lines.length && !/^##\s/.test(lines[i]); i += 1) {
  if (!/^\s*\|/.test(lines[i])) continue;
  const cells = lines[i].trim().replace(/^\||\|$/g, '').split('|');
  if (!header) {
    header = cells.map((c) => c.trim().toLowerCase());
    statusCol = header.indexOf('status');
    if (statusCol === -1) { console.error('error: the Plan table has no Status column'); process.exit(1); }
    continue;
  }
  if (/^[\s:-]+$/.test(cells.join(''))) continue; // separator row
  if (cells[0].trim() !== String(step)) continue;
  const old = cells[statusCol].trim();
  cells[statusCol] = ` ${status} `;
  lines[i] = `|${cells.join('|')}|`;
  fs.writeFileSync(file, lines.join('\n'));
  console.log(`step ${step}: ${old} → ${status}`);
  done = true;
  break;
}
if (!header) { console.error('error: no table in the Plan section'); process.exit(1); }
if (!done) { console.error(`error: no step ${step} in the Plan table`); process.exit(1); }
EOF
