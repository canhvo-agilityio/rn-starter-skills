#!/usr/bin/env bash
# Where the next production release stands. Read-only (it fetches the remote). Prints JSON.
#
# Usage: release-status.sh [project-dir] [--runtime]
#   --runtime   also compare the production app's runtime version (fingerprint) at HEAD with the last
#               finished production build on EAS, to tell a store build from an OTA update (slower;
#               needs the Expo login)
#
# Reports:
#   gate        whether .claude/hooks/release-gate.mjs is installed and .rn-starter.json has its
#               release block (apps, branch prefix, production branch, remote)
#   git         current branch, HEAD, clean or not, the last v* tag and its date, and whether HEAD is
#               already on the remote's production branch
#   version     app.json's version and the last released version
#   changes     commits on HEAD since the last release tag (subject, author, ticket ids): what a
#               release cut from here would ship
#   releaseBranches  release/<version> branches on the remote not merged into the production branch yet
#   approval    what the release gate would say right now about shipping the production app from
#               HEAD (the gate itself, run with a dry command; nothing is shipped)
#   runtime     with --runtime: HEAD's production runtime version, the last production build's, and
#               whether they differ (native change → store build)
# Uses git only (no GitHub or GitLab CLI). Never opens .env files.
#
# Exit codes: 0 done · 1 error · 2 waiting on the dev (the remote can't be fetched: offline, or git
#             isn't signed in) · 3 a decision needed (no release gate or release block: run
#             rn-release-setup first)

set -uo pipefail
dir="."; runtime=0
for a in "$@"; do case "$a" in --runtime) runtime=1 ;; *) dir="$a" ;; esac; done
dir="$(cd "$dir" && pwd)" || exit 1
[ -f "$dir/package.json" ] || { echo "{\"error\":\"no package.json in $dir\"}"; exit 1; }
command -v node >/dev/null 2>&1 || { echo '{"error":"node not found — source rn-starter/scripts/env.sh first"}'; exit 1; }
cd "$dir"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

remote="$(node -e "try{console.log(require('./.rn-starter.json').release.remote||'origin')}catch{console.log('origin')}")"
fetched=0
git fetch --quiet --tags "$remote" >/dev/null 2>&1 && fetched=1

# What the gate would decide for a production submit from HEAD.
if [ -f .claude/hooks/release-gate.mjs ]; then
  printf '{"tool_name":"Bash","tool_input":{"command":"eas submit --profile production --platform all --id release-status-check"}}' \
    | CLAUDE_PROJECT_DIR="$dir" node .claude/hooks/release-gate.mjs > "$tmp/gate.json" 2>/dev/null || true
fi

if [ "$runtime" -eq 1 ]; then
  APP_VARIANT=production EXPO_NO_DOTENV=1 npx --no-install expo-updates runtimeversion:resolve --platform ios \
    > "$tmp/runtime.json" 2>/dev/null || true
  npx --yes eas-cli build:list --platform ios -e production --status finished --limit 1 --json --non-interactive \
    > "$tmp/builds.json" 2>/dev/null || true
fi

FETCHED="$fetched" REMOTE="$remote" node - "$dir" "$tmp" <<'EOF'
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const [dir, tmp] = process.argv.slice(2);
const readJson = (f) => { try { return JSON.parse(fs.readFileSync(f, 'utf8')); } catch { return null; } };
const git = (...args) => { try { return execFileSync('git', args, { cwd: dir, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim(); } catch { return null; } };

const release = readJson(path.join(dir, '.rn-starter.json'))?.release ?? null;
const remote = process.env.REMOTE;
const prefix = release?.releaseBranchPrefix || 'release/';
const prodBranch = release?.productionBranch || 'main';
const prodRef = `${remote}/${prodBranch}`;
const gate = {
  installed: fs.existsSync(path.join(dir, '.claude/hooks/release-gate.mjs')),
  releaseBlock: Boolean(release),
  apps: (release?.apps || []).map((a) => ({ name: a.name, production: a.production, ios: a.ios, android: a.android })),
  prefix, productionBranch: prodBranch, remote,
};

const hasProd = git('rev-parse', '--verify', '-q', `refs/remotes/${prodRef}`) !== null;
const lastTag = hasProd ? git('describe', '--tags', '--abbrev=0', '--match', 'v[0-9]*', prodRef) : null;
const head = git('rev-parse', 'HEAD');
const gitInfo = {
  branch: git('rev-parse', '--abbrev-ref', 'HEAD'), head,
  clean: git('status', '--porcelain', '--untracked-files=no') === '',
  fetched: process.env.FETCHED === '1', productionBranch: hasProd ? prodRef : `${prodRef} (not found on the remote)`,
  headOnProduction: hasProd && head ? git('merge-base', '--is-ancestor', head, prodRef) !== null : false,
  lastTag, lastTagDate: lastTag ? git('log', '-1', '--format=%cI', lastTag) : null,
};

const appVersion = readJson(path.join(dir, 'app.json'))?.expo?.version ?? readJson(path.join(dir, 'package.json'))?.version ?? null;
const TICKET = /\b[A-Z][A-Z0-9]+-\d+\b|\b(?:gh|gl|ado|trello|clickup|asana|notion)-[\w]+\b|#\d+\b/g;
// What this release would ship: HEAD (the base branch, or the release branch cut from it) since the last release.
const range = lastTag ? `${lastTag}..HEAD` : 'HEAD';
const log = git('log', range, '--no-merges', '--format=%H%x1f%s%x1f%an') || '';
const commits = log.split('\n').filter(Boolean).map((l) => {
  const [sha, subject, author] = l.split('\x1f');
  return { sha: sha.slice(0, 7), subject, author, tickets: [...new Set(subject.match(TICKET) || [])] };
});

const releaseBranches = hasProd ? (git('branch', '-r', '--list', `${remote}/${prefix}*`, '--no-merged', prodRef) || '')
  .split('\n').map((b) => b.trim()).filter(Boolean)
  .map((b) => ({ branch: b.replace(`${remote}/`, ''), version: b.replace(`${remote}/${prefix}`, ''), head: (git('rev-parse', '--short', b) || '') })) : [];

const g = readJson(path.join(tmp, 'gate.json'))?.hookSpecificOutput;
const approval = gate.installed ? { decision: g?.permissionDecision ?? 'allow', reason: g?.permissionDecisionReason ?? `HEAD is on ${prodRef}` } : null;

let runtime = null;
const rt = readJson(path.join(tmp, 'runtime.json'));
const builds = readJson(path.join(tmp, 'builds.json'));
if (rt || builds) {
  const last = Array.isArray(builds) ? builds[0] : null;
  const headRt = rt?.runtimeVersion ?? null;
  runtime = { head: headRt, lastBuild: last ? { id: last.id, runtimeVersion: last.runtimeVersion, appVersion: last.appVersion, commit: last.gitCommitHash } : null,
    nativeChanged: headRt && last?.runtimeVersion ? headRt !== last.runtimeVersion : null };
}

console.log(JSON.stringify({
  dir, gate, git: gitInfo,
  version: { app: appVersion, lastReleased: lastTag ? lastTag.replace(/^v/, '') : null },
  changes: { range, commits }, releaseBranches, approval, runtime,
}, null, 2));
process.exitCode = !gate.installed || !gate.releaseBlock ? 3 : process.env.FETCHED !== '1' ? 2 : 0;
EOF
