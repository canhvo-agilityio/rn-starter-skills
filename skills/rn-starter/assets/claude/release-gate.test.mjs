// Tests for release-gate.mjs, next to it. Run: node --test skills/rn-starter/assets/claude/release-gate.test.mjs
// Each case builds a throwaway project (git repo, app.json, eas.json, the release block) and a fake
// `gh` that prints the release PRs a case describes, then feeds the hook a Bash command.
import { execFileSync, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import assert from 'node:assert/strict';

const HOOK = path.resolve(import.meta.dirname, 'release-gate.mjs');

const EAS = {
  cli: { version: '>= 25.0.0', appVersionSource: 'remote' },
  build: {
    dev: { distribution: 'store', environment: 'preview', channel: 'dev', autoIncrement: true, env: { APP_VARIANT: 'dev' } },
    production: { distribution: 'store', environment: 'production', channel: 'production', autoIncrement: true, env: { APP_VARIANT: 'production' } },
    'dev-simulator': { extends: 'dev', distribution: 'internal', channel: 'dev', ios: { simulator: true } },
    'production-simulator': { extends: 'production', distribution: 'internal', channel: 'production', ios: { simulator: true } },
  },
};
const RELEASE = (approvers = []) => ({
  apps: [
    { name: 'dev', variant: 'dev', production: false, profiles: ['dev', 'dev-simulator'], channels: ['dev'] },
    { name: 'production', variant: 'production', production: true, profiles: ['production', 'production-simulator'], channels: ['production'] },
  ],
  releaseBranchPrefix: 'release/',
  approvers,
});

const git = (dir, ...args) => execFileSync('git', args, { cwd: dir, encoding: 'utf8' }).trim();

// A project at version `version`; `prs(head)` returns the fake gh output for the HEAD commit.
const project = ({ version = '1.4.0', approvers = [], release = true, prs = () => [], gh = true } = {}) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'release-gate-'));
  fs.writeFileSync(path.join(dir, 'app.json'), JSON.stringify({ expo: { version } }));
  fs.writeFileSync(path.join(dir, 'eas.json'), JSON.stringify(EAS));
  if (release) fs.writeFileSync(path.join(dir, '.rn-starter.json'), JSON.stringify({ release: RELEASE(approvers) }));
  git(dir, 'init', '-q');
  git(dir, '-c', 'user.email=t@t', '-c', 'user.name=t', 'add', '-A');
  git(dir, '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'init');
  const head = git(dir, 'rev-parse', 'HEAD');
  const bin = path.join(dir, '.bin');
  fs.mkdirSync(bin);
  fs.writeFileSync(path.join(dir, '.gh.json'), JSON.stringify(prs(head)));
  fs.writeFileSync(path.join(bin, 'gh'), gh
    ? `#!/bin/sh\n[ "$1 $2" = "pr list" ] && cat "${path.join(dir, '.gh.json')}" && exit 0\nexit 1\n`
    : '#!/bin/sh\necho "not logged in" >&2\nexit 1\n', { mode: 0o755 });
  return { dir, head, bin };
};

const gate = (p, command, tool = 'Bash') => {
  const r = spawnSync('node', [HOOK], {
    input: JSON.stringify({ tool_name: tool, tool_input: { command } }),
    env: { ...process.env, CLAUDE_PROJECT_DIR: p.dir, PATH: `${p.bin}:${process.env.PATH}` },
    cwd: p.dir, encoding: 'utf8',
  });
  if (!r.stdout.trim()) return { decision: 'allow', reason: '' };
  const out = JSON.parse(r.stdout).hookSpecificOutput;
  return { decision: out.permissionDecision, reason: out.permissionDecisionReason };
};

const pr = (head, { version = '1.4.0', state = 'OPEN', reviews, merge = null } = {}) => ({
  number: 12, url: 'https://github.com/acme/shop/pull/12', state,
  headRefName: `release/${version}`, headRefOid: head, mergeCommit: merge ? { oid: merge } : null,
  author: { login: 'dev-anna' },
  reviews: reviews ?? [{ author: { login: 'lead-ni' }, state: 'APPROVED', commit: { oid: head } }],
});
const approved = (opts) => ({ prs: (head) => [pr(head, opts)] });

// ---------------------------------------------------------------- dev app
test('dev builds and updates pass', () => {
  const p = project();
  assert.equal(gate(p, 'eas build --profile dev -p ios --non-interactive').decision, 'allow');
  assert.equal(gate(p, 'APP_VARIANT=dev npx --yes eas-cli@25.3.0 update --channel dev --message "fix"').decision, 'allow');
  assert.equal(gate(p, 'eas update --channel dev --message x').decision, 'allow');
});

test('submitting the dev app asks', () => {
  const p = project();
  assert.equal(gate(p, 'npx eas-cli@25.3.0 submit --profile dev -p ios --latest').decision, 'ask');
});

test('check builds of the production app reach no user and pass', () => {
  const p = project();
  assert.equal(gate(p, 'eas build --profile production-simulator -p ios --local').decision, 'allow');
});

// ---------------------------------------------------------------- production without approval
test('a production build with no release PR is denied, with the route', () => {
  const p = project();
  const r = gate(p, 'eas build --profile production -p ios');
  assert.equal(r.decision, 'deny');
  assert.match(r.reason, /No release PR covers commit/);
  assert.match(r.reason, /rn-release/);
});

test('eas build with no profile means production', () => {
  const p = project();
  assert.equal(gate(p, 'cd app && eas build -p android').decision, 'deny');
});

test('approval by the author only, or by a bot, does not count', () => {
  const p = project({ prs: (head) => [pr(head, { reviews: [
    { author: { login: 'dev-anna' }, state: 'APPROVED', commit: { oid: head } },
    { author: { login: 'copilot-pull-request-reviewer' }, state: 'APPROVED', commit: { oid: head } },
  ] })] });
  assert.match(gate(p, 'eas build --profile production -p ios').reason, /has no approval on that commit/);
});

test('an approval on an older commit does not cover new commits', () => {
  const p = project({ prs: (head) => [pr(head, { reviews: [{ author: { login: 'lead-ni' }, state: 'APPROVED', commit: { oid: 'a'.repeat(40) } }] })] });
  assert.match(gate(p, 'eas build --profile production -p ios').reason, /has no approval on that commit/);
});

test('a later change request cancels the approval', () => {
  const p = project({ prs: (head) => [pr(head, { reviews: [
    { author: { login: 'lead-ni' }, state: 'APPROVED', commit: { oid: head } },
    { author: { login: 'qa-binh' }, state: 'CHANGES_REQUESTED', commit: { oid: head } },
  ] })] });
  assert.match(gate(p, 'eas build --profile production -p ios').reason, /has no approval on that commit/);
});

test('approvers, when listed, are the only ones who count', () => {
  const p = project({ approvers: ['release-manager'], ...approved() });
  const r = gate(p, 'eas build --profile production -p ios');
  assert.equal(r.decision, 'deny');
  assert.match(r.reason, /release-manager/);
});

test('a closed release PR does not count', () => {
  const p = project(approved({ state: 'CLOSED' }));
  assert.match(gate(p, 'eas build --profile production -p ios').reason, /No release PR covers commit/);
});

test('no GitHub CLI or not signed in: denied, and says how to sign in', () => {
  const p = project({ gh: false });
  const r = gate(p, 'eas submit --profile production -p ios --id abc');
  assert.equal(r.decision, 'deny');
  assert.match(r.reason, /gh auth login/);
});

// ---------------------------------------------------------------- production with approval
test('an approved release PR at HEAD lets the production build, submit and tag through', () => {
  const p = project(approved());
  assert.equal(gate(p, 'eas build --profile production -p ios --non-interactive').decision, 'allow');
  assert.equal(gate(p, 'eas submit --profile production -p ios --id abc').decision, 'allow');
  git(p.dir, 'tag', 'v1.4.0');
  assert.equal(gate(p, 'git push origin v1.4.0').decision, 'allow');
});

test('the merge commit of an approved release PR counts', () => {
  const p = project({ prs: (head) => [pr('b'.repeat(40), { state: 'MERGED', merge: head, reviews: [{ author: { login: 'lead-ni' }, state: 'APPROVED', commit: { oid: 'b'.repeat(40) } }] })] });
  assert.equal(gate(p, 'eas build --profile production -p android').decision, 'allow');
});

test('app.json version must match the release', () => {
  const p = project({ version: '1.3.9', ...approved() });
  const r = gate(p, 'eas build --profile production -p ios');
  assert.equal(r.decision, 'deny');
  assert.match(r.reason, /version is 1\.3\.9/);
});

test('a version already tagged on another commit is denied', () => {
  const p = project(approved());
  git(p.dir, 'tag', 'v1.4.0');
  fs.writeFileSync(path.join(p.dir, 'x.txt'), 'x');
  git(p.dir, 'add', 'x.txt');
  git(p.dir, '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'more');
  const head = git(p.dir, 'rev-parse', 'HEAD');
  fs.writeFileSync(path.join(p.dir, '.gh.json'), JSON.stringify([pr(head)]));
  const r = gate(p, 'eas build --profile production -p ios');
  assert.equal(r.decision, 'deny');
  assert.match(r.reason, /already released/);
});

test('uncommitted changes are denied even with an approval', () => {
  const p = project(approved());
  fs.writeFileSync(path.join(p.dir, 'app.json'), JSON.stringify({ expo: { version: '1.4.0', name: 'changed' } }));
  const r = gate(p, 'eas build --profile production -p ios');
  assert.equal(r.decision, 'deny');
  assert.match(r.reason, /Uncommitted changes/);
});

// ---------------------------------------------------------------- OTA updates
test('production OTA: needs the variant, then the approval', () => {
  const p = project();
  assert.match(gate(p, 'eas update --channel production --message x').reason, /APP_VARIANT=production/);
  assert.equal(gate(p, 'APP_VARIANT=production eas update --channel production --environment production --message x').decision, 'deny');
  const ok = project(approved());
  assert.equal(gate(ok, 'APP_VARIANT=production eas update --channel production --environment production --message x').decision, 'allow');
});

test('a variant that contradicts the profile or channel is denied', () => {
  const p = project(approved());
  assert.match(gate(p, 'APP_VARIANT=dev eas update --channel production --message x').reason, /contradicts/);
  assert.match(gate(p, 'APP_VARIANT=production eas build --profile dev').reason, /contradicts/);
});

test('eas update --auto and an update with no channel are denied', () => {
  const p = project();
  assert.equal(gate(p, 'eas update --auto').decision, 'deny');
  assert.equal(gate(p, 'eas update --message x').decision, 'deny');
});

test('rollbacks and rollouts on the production channel ask', () => {
  const p = project();
  assert.equal(gate(p, 'eas channel:rollout production --percent 10').decision, 'ask');
  assert.equal(gate(p, 'eas update:rollback --channel production').decision, 'ask');
  assert.equal(gate(p, 'eas channel:rollout dev --percent 10').decision, 'allow');
  assert.match(gate(p, 'eas update:edit --rollout-percentage 50 --group abc').reason, /an update channel serves/);
});

test('a production submit must name the build', () => {
  const p = project(approved());
  assert.match(gate(p, 'eas submit --profile production --platform ios --latest').reason, /by build id/);
  assert.match(gate(p, 'eas submit --profile production --platform ios').reason, /by build id/);
  assert.equal(gate(p, 'eas submit --profile dev --platform ios --latest').decision, 'ask');
});

// ---------------------------------------------------------------- tags, approvals, other commands
test('pushing a release tag without approval, or every tag, is denied', () => {
  const p = project();
  git(p.dir, 'tag', 'v1.4.0');
  assert.match(gate(p, 'git push origin v1.4.0').reason, /marks a production release/);
  assert.match(gate(p, 'git push --tags').reason, /Push the release tag by name/);
});

test('a tag that differs from the approved version is denied', () => {
  const p = project(approved());
  git(p.dir, 'tag', 'v1.5.0');
  assert.match(gate(p, 'git push origin v1.5.0').reason, /Tag it v1\.4\.0/);
});

test('approving a PR from the session is always denied', () => {
  const p = project();
  assert.equal(gate(p, 'gh pr review 12 --approve').decision, 'deny');
  assert.equal(gate(p, 'gh api repos/acme/shop/pulls/12/reviews -f event=APPROVE').decision, 'deny');
  assert.equal(gate(p, 'gh pr review 12 --comment -b "looks fine"').decision, 'allow');
});

test('an unknown profile is denied; other commands and tools pass', () => {
  const p = project();
  assert.match(gate(p, 'eas build --profile qa').reason, /doesn't know which app/);
  assert.equal(gate(p, 'git push origin feat/cart').decision, 'allow');
  assert.equal(gate(p, 'ls -la && pnpm test').decision, 'allow');
  assert.equal(gate(p, 'eas whoami').decision, 'allow');
  assert.equal(gate(p, 'eas build --profile production', 'Read').decision, 'allow');
});

test('without a release block, prod* names are production', () => {
  const p = project({ release: false });
  assert.equal(gate(p, 'eas build --profile production -p ios').decision, 'deny');
  assert.equal(gate(p, 'eas build --profile dev -p ios').decision, 'allow');
});
