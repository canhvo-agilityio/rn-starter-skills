#!/usr/bin/env bash
# Turn a ticket file into a pull request title and body: summary and link, every requirement with
# its evidence and result, the decisions and assumptions, what isn't verified, and the plan's steps.
# Read-only. The body is written in the ticket file's language for the content it copies.
#
# Usage: ticket-pr.sh <docs/tickets/<id>.md> [--type-prefix] [--title-only | --body-only]
#   --type-prefix   start the title with feat: / fix: (Conventional Commits); otherwise "<title> (<id>)"
#
# Prints "TITLE: <title>", a blank line, then the Markdown body.
# Exit codes: 0 done · 1 error · 3 printed, but some requirement has no evidence or isn't passing

set -euo pipefail
file=""; mode=""; prefix=0
for a in "$@"; do
  case "$a" in
    --type-prefix) prefix=1 ;;
    --title-only|--body-only) mode="$a" ;;
    *) file="$a" ;;
  esac
done
[ -n "$file" ] && [ -f "$file" ] || { echo "usage: ticket-pr.sh <docs/tickets/<id>.md> [--type-prefix] [--title-only | --body-only]" >&2; exit 1; }
command -v node >/dev/null 2>&1 || { echo "error: node not found — source rn-starter/scripts/env.sh first" >&2; exit 1; }

node - "$file" "$mode" "$prefix" <<'EOF'
const fs = require('fs');
const [file, mode, prefix] = process.argv.slice(2);
const text = fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n');

const fm = {};
const m = text.match(/^---\n([\s\S]*?)\n---/);
if (m) for (const line of m[1].split('\n')) {
  const kv = line.match(/^(\w+):\s*(.*?)\s*(#.*)?$/);
  if (kv) fm[kv[1]] = kv[2];
}
const title = (text.match(/^#\s+(.+)$/m) || [, fm.ticket || ''])[1].trim();

const sections = {};
let current = null;
for (const line of text.split('\n')) {
  const h = line.match(/^##\s+(.+?)\s*$/);
  if (h) { current = h[1].toLowerCase(); sections[current] = []; continue; }
  if (current) sections[current].push(line);
}
const prose = (name) => (sections[name] || []).join('\n').trim();
const table = (name) => {
  const lines = (sections[name] || []).filter((l) => /^\s*\|/.test(l));
  if (lines.length < 2) return [];
  const cells = (l) => l.trim().replace(/^\||\|$/g, '').split('|').map((c) => c.trim());
  const header = cells(lines[0]).map((c) => c.toLowerCase());
  return lines.slice(2).map(cells).map((row) => Object.fromEntries(header.map((k, i) => [k, row[i] ?? ''])));
};

const reqs = table('requirements').filter((r) => /^R\d+$/.test(r['#']));
const evidence = Object.fromEntries(table('evidence').filter((r) => /^R\d+$/.test(r['#'])).map((r) => [r['#'], r]));
const concerns = table('concerns').filter((r) => /^C\d+$/.test(r['#']));
const steps = table('plan').filter((r) => (r.step || '').trim());

const icon = (result) => (/^pass$/i.test(result) ? '✅' : /^fail$/i.test(result) ? '❌' : /^n\/a$/i.test(result) ? '➖' : '⚠️');
let incomplete = false;
const reqRows = reqs.map((r) => {
  const e = evidence[r['#']] || {};
  const result = e.result || 'not verified: no evidence recorded';
  if (!/^(pass|n\/a)$/i.test(result)) incomplete = true;
  return `| ${r['#']} | ${r.requirement} | ${e.evidence || '—'} | ${icon(result)} ${result} |`;
});

const decided = concerns.filter((c) => /resolved/i.test(c.severity)).map((c) => `- ${c['#']}: ${c.concern}`);
const assumed = concerns.filter((c) => /decide/i.test(c.severity) && /assumed/i.test(c.concern)).map((c) => `- ${c['#']} (${c.owner} to confirm): ${c.concern}`);
const open = concerns.filter((c) => /blocking|decide/i.test(c.severity) && !/assumed/i.test(c.concern)).map((c) => `- ${c['#']} (${c.severity}, ${c.owner}): ${c.concern}`);
const targetNotes = (sections.evidence || []).filter((l) => /^\s*(-\s*)?not verified\b/i.test(l)).map((l) => `- ${l.replace(/^\s*-?\s*not verified:?\s*/i, '')}`);
const notVerified = reqs.filter((r) => /^not verified/i.test(evidence[r['#']]?.result || 'not verified')).map((r) => `- ${r['#']}: ${(evidence[r['#']]?.result || 'no evidence recorded').replace(/^not verified:?\s*/i, '')}`);

const id = fm.ticket || '';
const bare = `${title.replace(new RegExp(`^${id}:?\\s*`), '')} (${id})`;
// commitlint's subject-case rejects a capitalized subject (and a squash commit takes the PR title).
const lowerFirst = (t) => t.charAt(0).toLocaleLowerCase() + t.slice(1);
const prTitle = prefix === '1' ? `${fm.type === 'bug' ? 'fix' : 'feat'}: ${lowerFirst(bare)}` : bare;
const source = fm.source && /^https?:/.test(fm.source) ? `[${id}](${fm.source})` : id;
const summary = prose('summary').split('\n').filter((l) => l.trim()).join('\n');

const body = [
  `${source}. Analysis, plan and evidence: \`${file.replace(/^.*?(docs\/tickets\/)/, '$1')}\`.`,
  '',
  summary,
  '',
  '## Requirements',
  '',
  '| # | Requirement | Evidence | Result |',
  '|---|---|---|---|',
  ...reqRows,
  ...(decided.length ? ['', '## Decisions', '', ...decided] : []),
  ...(assumed.length ? ['', '## Built on assumptions (not yet confirmed by their owner)', '', ...assumed] : []),
  ...(open.length ? ['', '## Still open', '', ...open] : []),
  ...(notVerified.length || targetNotes.length ? ['', '## Not verified', '', ...notVerified, ...targetNotes] : []),
  ...(steps.length ? ['', '## Steps', '', ...steps.map((s) => `${s.step}. ${s.what} (${s.skill}; ${s['r#']})${/done/i.test(s.status) ? '' : ` — ${s.status}`}`)] : []),
].join('\n');

if (mode === '--title-only') console.log(prTitle);
else if (mode === '--body-only') console.log(body);
else console.log(`TITLE: ${prTitle}\n\n${body}`);
process.exitCode = incomplete ? 3 : 0;
EOF
