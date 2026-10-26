#!/usr/bin/env bash
# Check a docs/tickets/<id>.md file against the contract in references/ticket-template.md.
# Read-only. Prints JSON: counts, and one problem per line in "problems".
#
# Usage: check-ticket.sh <docs/tickets/<id>.md>
#
# Checks: frontmatter (ticket, type, status); R# unique and numbered R1..Rn without gaps (struck
# through = dropped); every active R# in Traceability with a valid status (covered | gap C<n> | n/a);
# every concern a gap names exists; every concern has a severity (blocking | decide | note |
# resolved), owners among PO / design / backend / dev, and Affects naming existing R#; every
# blocking/decide concern is asked in a "**Q<n>** (C<n>)" item, with "Recommended:" for decide;
# no blocking concern left when status is ready or later.
#
# Exit codes: 0 valid · 1 error (no file) · 3 problems found

set -euo pipefail
file="${1:-}"
[ -n "$file" ] && [ -f "$file" ] || { echo "{\"error\":\"usage: check-ticket.sh <docs/tickets/<id>.md>\"}"; exit 1; }
command -v node >/dev/null 2>&1 || { echo '{"error":"node not found — source rn-starter/scripts/env.sh first"}'; exit 1; }

node - "$file" <<'EOF'
const fs = require('fs');
const file = process.argv[2];
const text = fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n');
const problems = [];

// Frontmatter
const fm = {};
const fmMatch = text.match(/^---\n([\s\S]*?)\n---/);
if (!fmMatch) problems.push('frontmatter missing (--- block with ticket, type, status)');
else for (const line of fmMatch[1].split('\n')) {
  const kv = line.match(/^(\w+):\s*(.*?)\s*(#.*)?$/);
  if (kv) fm[kv[1]] = kv[2];
}
const STATUSES = ['questions-open', 'ready', 'planned', 'in-progress', 'done'];
if (fmMatch) {
  if (!fm.ticket) problems.push('frontmatter: ticket is missing');
  if (!['feature', 'bug'].includes(fm.type)) problems.push(`frontmatter: type must be feature or bug (got "${fm.type ?? ''}")`);
  if (!STATUSES.includes(fm.status)) problems.push(`frontmatter: status must be one of ${STATUSES.join(', ')} (got "${fm.status ?? ''}")`);
}

// Sections and their first table, as rows keyed by lower-case header
const sections = {};
let current = null;
for (const line of text.split('\n')) {
  const h = line.match(/^##\s+(.+?)\s*$/);
  if (h) { current = h[1].toLowerCase(); sections[current] = []; continue; }
  if (current) sections[current].push(line);
}
const table = (name) => {
  const lines = (sections[name] || []).filter((l) => /^\s*\|/.test(l));
  if (lines.length < 2) return null;
  const cells = (l) => l.trim().replace(/^\||\|$/g, '').split('|').map((c) => c.trim());
  const header = cells(lines[0]).map((c) => c.toLowerCase());
  return lines.slice(2).map(cells).map((row) => Object.fromEntries(header.map((k, i) => [k, row[i] ?? ''])));
};
for (const name of ['requirements', 'traceability', 'concerns', 'questions', 'scope']) {
  if (!(name in sections)) problems.push(`section "## ${name[0].toUpperCase()}${name.slice(1)}" is missing`);
}

// Requirements
const reqRows = table('requirements') || [];
if ('requirements' in sections && !reqRows.length) problems.push('Requirements: no table rows (| # | Requirement | From |)');
const active = [];
const dropped = [];
const seen = new Set();
for (const row of reqRows) {
  const id = row['#'] || '';
  const m = id.match(/^(~~)?R(\d+)(~~)?$/);
  if (!m) { problems.push(`Requirements: "${id}" is not R<n> (or ~~R<n>~~ when dropped)`); continue; }
  const n = Number(m[2]);
  if (seen.has(n)) problems.push(`Requirements: R${n} appears twice`);
  seen.add(n);
  (m[1] ? dropped : active).push(n);
  if (!m[1] && !(row.requirement || '').trim()) problems.push(`Requirements: R${n} has no text`);
}
const all = [...seen].sort((a, b) => a - b);
all.forEach((n, i) => { if (n !== i + 1) problems.push(`Requirements: numbering has a gap before R${n} (keep dropped ones as ~~R<n>~~, never renumber)`); });

// Concerns
const concernRows = table('concerns') || [];
const concerns = {};
const affects = {};
const SEVERITIES = ['blocking', 'decide', 'note', 'resolved'];
const OWNERS = ['po', 'design', 'backend', 'dev'];
for (const row of concernRows) {
  const id = row['#'] || '';
  if (!/^C\d+$/.test(id)) { if (id) problems.push(`Concerns: "${id}" is not C<n>`); continue; }
  const severity = (row.severity || '').toLowerCase();
  if (!SEVERITIES.includes(severity)) problems.push(`Concerns: ${id} severity must be one of ${SEVERITIES.join(', ')} (got "${row.severity ?? ''}")`);
  const owners = (row.owner || '').split(/\s*[,/&+]\s*|\s+and\s+/).map((o) => o.trim()).filter(Boolean);
  if (!owners.length) problems.push(`Concerns: ${id} has no owner`);
  for (const o of owners) if (!OWNERS.includes(o.toLowerCase())) problems.push(`Concerns: ${id} owner "${o}" must be one of PO, design, backend, dev`);
  if (concerns[id]) problems.push(`Concerns: ${id} appears twice`);
  concerns[id] = severity;
  affects[id] = [...(row.affects || '').matchAll(/R(\d+)/g)].map((m) => Number(m[1]));
}

// Traceability
const traceRows = table('traceability') || [];
const traced = new Set();
for (const row of traceRows) {
  const m = (row['#'] || '').match(/^R(\d+)$/);
  if (!m) continue;
  const n = Number(m[1]);
  traced.add(n);
  if (dropped.includes(n)) continue;
  if (!active.includes(n)) problems.push(`Traceability: R${n} isn't in Requirements`);
  const status = (row.status || '').trim();
  if (/^covered$/i.test(status) || /^n\/a\b/i.test(status)) continue;
  const gap = status.match(/^gap\s+(C\d+(?:\s*,\s*C\d+)*)$/i);
  if (!gap) { problems.push(`Traceability: R${n} status "${status}" must be covered, gap C<n>[, C<n>…] or n/a: <reason>`); continue; }
  for (const c of gap[1].split(/\s*,\s*/)) if (!(c in concerns)) problems.push(`Traceability: R${n} points to ${c}, which isn't in Concerns`);
}
for (const n of active) if (!traced.has(n)) problems.push(`Traceability: R${n} has no row`);

for (const [c, rs] of Object.entries(affects)) {
  for (const n of rs) if (!seen.has(n)) problems.push(`Concerns: ${c} affects R${n}, which isn't in Requirements`);
}

// Questions: each "**Q<n>**" item, with its continuation lines, up to the next item or heading
const questions = [];
for (const line of sections.questions || []) {
  const q = line.match(/^\s*[-*]\s*\*\*Q(\d+)\*\*(.*)$/);
  if (q) questions.push({ id: `Q${q[1]}`, text: q[2] });
  else if (/^\s*#/.test(line) || /^\s*[-*]\s/.test(line)) questions.push(null);
  else if (questions.length && questions[questions.length - 1] && line.trim()) questions[questions.length - 1].text += ` ${line.trim()}`;
}
const asked = new Set();
const qSeen = new Set();
for (const q of questions.filter(Boolean)) {
  if (qSeen.has(q.id)) problems.push(`Questions: ${q.id} appears twice`);
  qSeen.add(q.id);
  const refs = [...q.text.matchAll(/\((C\d+(?:\s*,\s*C\d+)*)\)/g)].flatMap((m) => m[1].split(/\s*,\s*/));
  if (!refs.length) problems.push(`Questions: ${q.id} names no concern (start it with "(C<n>)")`);
  for (const c of refs) {
    asked.add(c);
    if (!(c in concerns)) problems.push(`Questions: ${q.id} refers to ${c}, which isn't in Concerns`);
  }
  if (refs.some((c) => concerns[c] === 'decide') && !/Recommended:/.test(q.text)) {
    problems.push(`Questions: ${q.id} is about a decide concern but has no "Recommended:" answer`);
  }
}
for (const [c, sev] of Object.entries(concerns)) {
  if ((sev === 'blocking' || sev === 'decide') && !asked.has(c)) problems.push(`Questions: ${c} is ${sev} but no question asks about it (a "**Q<n>** (${c})" item)`);
}
const questionCount = qSeen.size;

// Status consistency
const blocking = Object.entries(concerns).filter(([, s]) => s === 'blocking').map(([c]) => c);
if (['ready', 'planned', 'in-progress', 'done'].includes(fm.status) && blocking.length) {
  problems.push(`status is ${fm.status} but ${blocking.join(', ')} still blocking (resolve them or set status: questions-open)`);
}

const count = (s) => Object.values(concerns).filter((x) => x === s).length;
console.log(JSON.stringify({
  file, ticket: fm.ticket ?? null, type: fm.type ?? null, status: fm.status ?? null,
  requirements: { active: active.length, dropped: dropped.length },
  coverage: {
    covered: traceRows.filter((r) => /^covered$/i.test((r.status || '').trim())).length,
    gaps: traceRows.filter((r) => /^gap\b/i.test((r.status || '').trim())).length,
  },
  concerns: { blocking: count('blocking'), decide: count('decide'), note: count('note'), resolved: count('resolved') },
  questions: questionCount,
  problems,
}, null, 2));
process.exitCode = problems.length ? 3 : 0;
EOF
