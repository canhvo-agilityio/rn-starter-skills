#!/usr/bin/env bash
# Check the project's Maestro flows: syntax, and the conventions that keep them portable and
# traceable. Read-only. Prints JSON.
#
# Usage: check-flows.sh <project-dir> [--ticket <docs/tickets/<id>.md>]
#
# Problems: syntax (maestro check-syntax, when Maestro is installed); missing config.yaml; a flow
# without "appId: ${APP_ID}"; a hard-coded exp:// / localhost / 127.0.0.1 / scheme URL outside
# ${APP_URL}; a coordinate tap; a flow in a ticket folder (.maestro/<ticket>/) without the ticket and
# an R<n> tag. With --ticket: "uncovered" lists the active R# with no flow (not a problem by itself:
# some R# are covered by unit tests instead).
#
# Exit codes: 0 fine · 1 error · 3 problems found

set -euo pipefail
dir="${1:-}"; shift || true
ticket=""
while [ $# -gt 0 ]; do case "$1" in --ticket) ticket="${2:-}"; shift 2 ;; *) shift ;; esac; done
[ -n "$dir" ] && [ -d "$dir/.maestro" ] || { echo "{\"error\":\"no .maestro/ folder in ${dir:-?}\"}"; exit 1; }
command -v node >/dev/null 2>&1 || { echo '{"error":"node not found — source rn-starter/scripts/env.sh first"}'; exit 1; }
maestro="$(command -v maestro 2>/dev/null || true)"; [ -z "$maestro" ] && [ -x "$HOME/.maestro/bin/maestro" ] && maestro="$HOME/.maestro/bin/maestro"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
: > "$tmp/syntax"
if [ -n "$maestro" ]; then
  while IFS= read -r f; do
    if ! "$maestro" check-syntax "$f" > "$tmp/one" 2>&1; then
      printf '%s\t%s\n' "${f#"$dir"/}" "$(tr '\n' ' ' < "$tmp/one" | cut -c1-300)" >> "$tmp/syntax"
    fi
  done < <(find "$dir/.maestro" -name '*.yaml' ! -name 'config.yaml' | sort)
fi

node - "$dir" "$ticket" "$tmp/syntax" "${maestro:+yes}" <<'EOF'
const fs = require('fs');
const path = require('path');
const [dir, ticketFile, syntaxFile, hasMaestro] = process.argv.slice(2);
const root = path.join(dir, '.maestro');
const problems = [];
if (!fs.existsSync(path.join(root, 'config.yaml'))) problems.push('.maestro/config.yaml is missing (flows: ["*/*.yaml"], excludeTags: [subflow])');
for (const line of fs.readFileSync(syntaxFile, 'utf8').split('\n').filter(Boolean)) {
  const [file, msg] = line.split('\t');
  problems.push(`${file}: syntax: ${msg}`);
}

const walk = (d, out = []) => {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) walk(p, out); else if (/\.ya?ml$/.test(e.name) && e.name !== 'config.yaml') out.push(p);
  }
  return out;
};
const tagsOf = (header) => {
  const tags = [];
  const block = header.match(/^tags:\s*\n((?:\s+-\s*.+\n?)+)/m);
  if (block) for (const m of block[1].matchAll(/-\s*(.+)/g)) tags.push(m[1].trim().replace(/^["']|["']$/g, ''));
  const inline = header.match(/^tags:\s*\[(.*)\]/m);
  if (inline) tags.push(...inline[1].split(',').map((t) => t.trim().replace(/^["']|["']$/g, '')).filter(Boolean));
  return tags;
};

const flows = [];
for (const f of walk(root)) {
  const rel = path.relative(dir, f).split(path.sep).join('/');
  const text = fs.readFileSync(f, 'utf8');
  const [header, ...rest] = text.split(/^---\s*$/m);
  const body = rest.join('---');
  const tags = tagsOf(header);
  const subflow = tags.includes('subflow');
  if (!/^appId:\s*\$\{APP_ID\}\s*$/m.test(header)) problems.push(`${rel}: appId must be \${APP_ID} (the run sets it per target)`);
  if (/(exp:\/\/|exps:\/\/|localhost|127\.0\.0\.1|10\.0\.2\.2)/.test(body)) problems.push(`${rel}: hard-coded dev server URL; open routes through the open subflow and \${APP_URL}`);
  if (/openLink:\s*["']?[a-z][\w+.-]*:\/\//i.test(body) && !/\$\{APP_URL\}/.test(body)) problems.push(`${rel}: hard-coded deep link; use \${APP_URL}\${ROUTE}`);
  if (/\bpoint:/.test(body)) problems.push(`${rel}: coordinate tap (point:); tap by id`);
  const folder = rel.split('/')[1];
  const inTicketFolder = rel.split('/').length === 3 && !['subflows'].includes(folder);
  const rTags = tags.filter((t) => /^R\d+$/.test(t));
  if (!subflow && inTicketFolder && /^[A-Za-z][\w-]*-\d+$|^\d+$/.test(folder)) {
    if (!tags.includes(folder)) problems.push(`${rel}: missing the ticket tag "${folder}"`);
    if (!rTags.length) problems.push(`${rel}: missing its R<n> tag`);
  }
  if (!subflow) flows.push({ file: rel, tags, requirements: rTags });
}

let uncovered = null;
if (ticketFile) {
  const t = fs.readFileSync(ticketFile, 'utf8');
  const id = ((t.match(/^ticket:\s*(\S+)/m) || [])[1] || '').trim();
  const reqSection = (t.split(/^## /m).find((s) => /^Requirements\b/.test(s)) || '');
  const active = [...reqSection.matchAll(/^\|\s*R(\d+)\s*\|/gm)].map((m) => `R${m[1]}`);
  const covered = new Set(flows.filter((f) => f.tags.includes(id)).flatMap((f) => f.requirements));
  uncovered = active.filter((r) => !covered.has(r));
}

console.log(JSON.stringify({ flows, syntaxChecked: !!hasMaestro, uncovered, problems }, null, 2));
process.exitCode = problems.length ? 3 : 0;
EOF
