#!/usr/bin/env bash
# Where the next production release stands. Read-only. Prints JSON.
#
# Usage: release-status.sh [project-dir] [--runtime]
#   --runtime   also compare the production app's runtime version (fingerprint) at HEAD with the last
#               finished production build on EAS, to tell a store build from an OTA update (slower;
#               needs the Expo login)
#
# Reports:
#   gate        whether .claude/hooks/release-gate.mjs is installed and .rn-starter.json has its
#               release block (apps, branch prefix, approvers, base branch)
#   git         current branch, HEAD, clean or not, the base branch, the last v* tag and its date
#   version     app.json's version and the last released version
#   changes     commits since the last tag (subject, author, ticket ids found in it) and the merged
#               pull requests since then, from GitHub when gh is signed in
#   releasePrs  open release/<version> pull requests (url, head, approved by whom)
#   approval    what the release gate would say right now about shipping the production app from
#               HEAD (the gate itself, run with a dry command; nothing is shipped)
#   runtime     with --runtime: HEAD's production runtime version, the last production build's, and
#               whether they differ (native change → store build)
# Never opens .env files.
#
# Exit codes: 0 done · 1 error · 2 waiting on the dev (gh not signed in) · 3 a decision needed
#             (no release gate or release block: run rn-release-setup first)

set -uo pipefail
dir="."; runtime=0
for a in "$@"; do case "$a" in --runtime) runtime=1 ;; *) dir="$a" ;; esac; done
dir="$(cd "$dir" && pwd)" || exit 1
[ -f "$dir/package.json" ] || { echo "{\"error\":\"no package.json in $dir\"}"; exit 1; }
command -v node >/dev/null 2>&1 || { echo '{"error":"node not found — source rn-starter/scripts/env.sh first"}'; exit 1; }
cd "$dir"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# What the gate would decide for a production submit from HEAD.
if [ -f .claude/hooks/release-gate.mjs ]; then
  printf '{"tool_name":"Bash","tool_input":{"command":"eas submit --profile production --platform all --id release-status-check"}}' \
    | CLAUDE_PROJECT_DIR="$dir" node .claude/hooks/release-gate.mjs > "$tmp/gate.json" 2>/dev/null || true
fi

gh_ok=0
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  gh_ok=1
  gh pr list --state all --limit 100 --json number,url,state,title,headRefName,headRefOid,mergedAt,author,reviews \
    > "$tmp/prs.json" 2>/dev/null || echo '[]' > "$tmp/prs.json"
fi

if [ "$runtime" -eq 1 ]; then
  APP_VARIANT=production EXPO_NO_DOTENV=1 npx --no-install expo-updates runtimeversion:resolve --platform ios \
    > "$tmp/runtime.json" 2>/dev/null || true
  npx --yes eas-cli build:list --platform ios -e production --status finished --limit 1 --json --non-interactive \
    > "$tmp/builds.json" 2>/dev/null || true
fi

GH_OK="$gh_ok" node - "$dir" "$tmp" <<'EOF'
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const [dir, tmp] = process.argv.slice(2);
const readJson = (f) => { try { return JSON.parse(fs.readFileSync(f, 'utf8')); } catch { return null; } };
const git = (...args) => { try { return execFileSync('git', args, { cwd: dir, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim(); } catch { return null; } };

const release = readJson(path.join(dir, '.rn-starter.json'))?.release ?? null;
const prefix = release?.releaseBranchPrefix || 'release/';
const gate = {
  installed: fs.existsSync(path.join(dir, '.claude/hooks/release-gate.mjs')),
  releaseBlock: Boolean(release),
  apps: (release?.apps || []).map((a) => ({ name: a.name, production: a.production, ios: a.ios, android: a.android })),
  prefix, approvers: release?.approvers ?? [], baseBranch: release?.baseBranch ?? 'main',
};

const lastTag = git('describe', '--tags', '--abbrev=0', '--match', 'v[0-9]*');
const status = git('status', '--porcelain', '--untracked-files=no');
const gitInfo = {
  branch: git('rev-parse', '--abbrev-ref', 'HEAD'), head: git('rev-parse', 'HEAD'),
  clean: status === '', lastTag, lastTagDate: lastTag ? git('log', '-1', '--format=%cI', lastTag) : null,
};

const appVersion = readJson(path.join(dir, 'app.json'))?.expo?.version ?? readJson(path.join(dir, 'package.json'))?.version ?? null;
const TICKET = /\b[A-Z][A-Z0-9]+-\d+\b|#\d+\b/g;
const log = git('log', ...(lastTag ? [`${lastTag}..HEAD`] : []), '--no-merges', '--format=%H%x1f%s%x1f%an') || '';
const commits = log.split('\n').filter(Boolean).map((l) => {
  const [sha, subject, author] = l.split('\x1f');
  return { sha: sha.slice(0, 7), subject, author, tickets: [...new Set(subject.match(TICKET) || [])] };
});

const prs = process.env.GH_OK === '1' ? readJson(path.join(tmp, 'prs.json')) || [] : null;
const since = gitInfo.lastTagDate ? new Date(gitInfo.lastTagDate) : null;
const merged = prs ? prs.filter((p) => p.mergedAt && !p.headRefName.startsWith(prefix) && (!since || new Date(p.mergedAt) > since))
  .map((p) => ({ number: p.number, title: p.title, url: p.url, tickets: [...new Set((p.title.match(TICKET) || []))] })) : null;
const releasePrs = prs ? prs.filter((p) => p.state === 'OPEN' && p.headRefName.startsWith(prefix)).map((p) => ({
  number: p.number, url: p.url, version: p.headRefName.slice(prefix.length), head: p.headRefOid.slice(0, 7),
  approvedBy: [...new Set((p.reviews || []).filter((r) => r.state === 'APPROVED' && r.commit?.oid === p.headRefOid).map((r) => r.author?.login))],
})) : null;

const g = readJson(path.join(tmp, 'gate.json'))?.hookSpecificOutput;
const approval = gate.installed ? { decision: g?.permissionDecision ?? 'allow', reason: g?.permissionDecisionReason ?? 'approved' } : null;

let runtime = null;
const rt = readJson(path.join(tmp, 'runtime.json'));
const builds = readJson(path.join(tmp, 'builds.json'));
if (rt || builds) {
  const last = Array.isArray(builds) ? builds[0] : null;
  const head = rt?.runtimeVersion ?? null;
  runtime = { head, lastBuild: last ? { id: last.id, runtimeVersion: last.runtimeVersion, appVersion: last.appVersion, commit: last.gitCommitHash } : null,
    nativeChanged: head && last?.runtimeVersion ? head !== last.runtimeVersion : null };
}

const out = {
  dir, gate, git: gitInfo,
  version: { app: appVersion, lastReleased: lastTag ? lastTag.replace(/^v/, '') : null },
  changes: { commits, mergedPrs: merged },
  releasePrs, approval, runtime,
  gh: process.env.GH_OK === '1' ? 'signed in' : 'not available — the dev runs `gh auth login`',
};
console.log(JSON.stringify(out, null, 2));
process.exitCode = !gate.installed || !gate.releaseBlock ? 3 : process.env.GH_OK !== '1' ? 2 : 0;
EOF
