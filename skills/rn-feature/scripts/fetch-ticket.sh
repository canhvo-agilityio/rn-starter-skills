#!/usr/bin/env bash
# Read a ticket and print it as JSON, with the acceptance criteria and the links it can spot.
# Read-only: never comments on, edits or transitions the ticket.
#
# Usage: fetch-ticket.sh <github-issue-url | owner/repo#N | #N>
#        fetch-ticket.sh --text-file <file> --id <id>     (a board ticket read in the browser, a pasted ticket, a document)
#
# Prints: id, source, title, state, labels, type (feature | bug), body, comments, acceptanceCriteria,
# links { figma, images, api, other }.
#
# Exit codes: 0 done · 1 error · 2 waiting on the developer (gh not signed in: prints ACTION REQUIRED)

set -euo pipefail
command -v node >/dev/null 2>&1 || { echo '{"error":"node not found — source rn-starter/scripts/env.sh first"}'; exit 1; }

text_file=""; id=""; ref=""
while [ $# -gt 0 ]; do
  case "$1" in
    --text-file) text_file="${2:-}"; shift 2 ;;
    --id) id="${2:-}"; shift 2 ;;
    -*) echo "{\"error\":\"unknown option: $1\"}"; exit 1 ;;
    *) ref="$1"; shift ;;
  esac
done

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

if [ -n "$text_file" ]; then
  [ -f "$text_file" ] || { echo "{\"error\":\"no such file: $text_file\"}"; exit 1; }
  [ -n "$id" ] || { echo '{"error":"--text-file needs --id (the ticket key, or a short slug)"}'; exit 1; }
  node -e '
    const fs = require("fs");
    const [file, id] = process.argv.slice(1);
    const text = fs.readFileSync(file, "utf8");
    const title = (text.match(/^#\s+(.+)$/m) || text.match(/^(.+)$/m) || [, id])[1].trim();
    fs.writeFileSync(process.argv[3], JSON.stringify({ id, source: null, title, state: null, labels: [], body: text, comments: [] }));
  ' "$text_file" "$id" "$tmp/raw.json"
elif [ -n "$ref" ]; then
  command -v gh >/dev/null 2>&1 || { echo '{"error":"gh (GitHub CLI) not found"}'; exit 1; }
  if ! gh auth status >/dev/null 2>&1; then
    echo "ACTION REQUIRED: the GitHub CLI isn't signed in. Ask the developer to run, in their own terminal:" >&2
    echo "  gh auth login" >&2
    exit 2
  fi
  repo=""; num=""
  if [[ "$ref" =~ github\.com/([^/]+/[^/]+)/(issues|pull)/([0-9]+) ]]; then
    repo="${BASH_REMATCH[1]}"; num="${BASH_REMATCH[3]}"
  elif [[ "$ref" =~ ^([^/#[:space:]]+/[^/#[:space:]]+)#([0-9]+)$ ]]; then
    repo="${BASH_REMATCH[1]}"; num="${BASH_REMATCH[2]}"
  elif [[ "$ref" =~ ^#?([0-9]+)$ ]]; then
    num="${BASH_REMATCH[1]}"
  else
    echo "{\"error\":\"not a GitHub issue reference: $ref (use a URL, owner/repo#N or #N; any other board: save the ticket text and use --text-file <file> --id <id>)\"}"; exit 1
  fi
  args=(issue view "$num" --json number,title,body,state,labels,url,comments)
  [ -n "$repo" ] && args+=(--repo "$repo")
  if ! gh "${args[@]}" > "$tmp/gh.json" 2> "$tmp/gh.err"; then
    echo "{\"error\":$(node -e 'console.log(JSON.stringify(require("fs").readFileSync(process.argv[1],"utf8").trim()))' "$tmp/gh.err")}"
    exit 1
  fi
  node -e '
    const fs = require("fs");
    const g = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    fs.writeFileSync(process.argv[2], JSON.stringify({
      id: `gh-${g.number}`, source: g.url, title: g.title, state: g.state,
      labels: (g.labels || []).map((l) => l.name), body: g.body || "",
      comments: (g.comments || []).map((c) => ({ author: c.author?.login ?? null, createdAt: c.createdAt, body: c.body })),
    }));
  ' "$tmp/gh.json" "$tmp/raw.json"
else
  echo '{"error":"usage: fetch-ticket.sh <github-issue-url | owner/repo#N | #N> | --text-file <file> --id <id>"}'; exit 1
fi

node - "$tmp/raw.json" <<'EOF'
const fs = require('fs');
const t = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const all = [t.body, ...t.comments.map((c) => c.body)].join('\n');

// Acceptance criteria: list items under an AC-like heading (until the next heading), plus checkboxes.
const AC_HEADING = /^(#{1,6}\s*|\*\*|__)?\s*(acceptance criteria|acceptance|a\.?c\.?|definition of done|criteria|tiêu chí( chấp nhận)?|điều kiện chấp nhận)\b.*$/i;
const criteria = [];
let inAc = false;
for (const raw of (t.body || '').split('\n')) {
  const line = raw.trim();
  if (/^#{1,6}\s/.test(line) || /^(\*\*|__).+(\*\*|__):?$/.test(line)) inAc = AC_HEADING.test(line);
  else if (AC_HEADING.test(line) && line.length < 60) { inAc = true; continue; }
  const item = line.match(/^(?:[-*+]|\d+[.)])\s+(?:\[[ xX]\]\s+)?(.+)$/);
  const box = line.match(/^[-*+]\s+\[[ xX]\]\s+(.+)$/);
  if ((inAc && item) || box) criteria.push((box || item)[1].trim());
}

const urls = [...new Set(all.match(/https?:\/\/[^\s)>\]"'`]+/g) || [])].map((u) => u.replace(/[.,;:]+$/, ''));
const links = { figma: [], images: [], api: [], other: [] };
for (const u of urls) {
  if (/figma\.com\//.test(u)) links.figma.push(u);
  else if (/\.(png|jpe?g|gif|webp)(\?|$)/i.test(u) || /user-images\.githubusercontent|github\.com\/user-attachments/.test(u)) links.images.push(u);
  else if (/swagger|openapi|api-docs|redoc/i.test(u)) links.api.push(u);
  else links.other.push(u);
}
// Local spec paths named in the text ("docs/api/openapi.json", "api/swagger.yaml") are API inputs too.
for (const m of all.match(/(?:^|[\s(`'"])((?:\.{0,2}\/)?[\w./-]*(?:openapi|swagger)[\w.-]*\.(?:json|ya?ml))\b/gim) || []) {
  const p = m.trim().replace(/^[(`'"]/, '');
  if (!/^https?:/.test(p) && !links.api.includes(p)) links.api.push(p);
}
const bugWords = /\b(bug|defect|regression|crash|lỗi)\b/i;
const type = t.labels.some((l) => bugWords.test(l)) || bugWords.test(t.title || '') ? 'bug' : 'feature';

console.log(JSON.stringify({ ...t, type, acceptanceCriteria: [...new Set(criteria)], links }, null, 2));
EOF
