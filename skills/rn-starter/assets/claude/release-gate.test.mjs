// Tests for release-gate.mjs, next to it. Run: node --test skills/rn-starter/assets/claude/release-gate.test.mjs
// Each case builds a throwaway project (git repo, app.json, eas.json, the release block) with a bare
// repository as its remote, so "a release manager merged it" is a push to the remote's production
// branch, then feeds the hook a Bash command.
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
const RELEASE = {
  apps: [
    { name: 'dev', variant: 'dev', production: false, profiles: ['dev', 'dev-simulator'], channels: ['dev'] },
    { name: 'production', variant: 'production', production: true, profiles: ['production', 'production-simulator'], channels: ['production'] },
  ],
  releaseBranchPrefix: 'release/',
  productionBranch: 'prod',
};

const git = (dir, ...args) => execFileSync('git', ['-c', 'user.email=t@t', '-c', 'user.name=t', ...args], { cwd: dir, encoding: 'utf8' }).trim();
const write = (dir, file, data) => fs.writeFileSync(path.join(dir, file), typeof data === 'string' ? data : JSON.stringify(data));
const commit = (p, file, msg) => { write(p.dir, file, msg); git(p.dir, 'add', file); git(p.dir, 'commit', '-qm', msg); return git(p.dir, 'rev-parse', 'HEAD'); };
// What a release manager does on the server: the commit lands on the production branch.
const merge = (p, branch = 'prod') => git(p.dir, 'push', '-q', 'origin', `HEAD:refs/heads/${branch}`);

// A project at `version` whose remote's production branch holds the first commit.
const project = ({ version = '1.4.0', release = true } = {}) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'release-gate-'));
  const remote = fs.mkdtempSync(path.join(os.tmpdir(), 'release-gate-remote-'));
  git(remote, 'init', '-q', '--bare', '-b', 'main');
  write(dir, 'app.json', { expo: { version } });
  write(dir, 'eas.json', EAS);
  if (release) write(dir, '.rn-starter.json', { release: RELEASE });
  write(dir, '.gitignore', '.claude/\n');
  git(dir, 'init', '-q', '-b', 'main');
  git(dir, 'add', '-A');
  git(dir, 'commit', '-qm', 'init');
  git(dir, 'remote', 'add', 'origin', remote);
  git(dir, 'push', '-q', 'origin', 'main', 'main:prod');
  return { dir, remote };
};

const gate = (p, command, tool = 'Bash') => {
  const r = spawnSync('node', [HOOK], {
    input: JSON.stringify({ tool_name: tool, tool_input: { command } }),
    env: { ...process.env, CLAUDE_PROJECT_DIR: p.dir }, cwd: p.dir, encoding: 'utf8',
  });
  if (!r.stdout.trim()) return { decision: 'allow', reason: '' };
  const out = JSON.parse(r.stdout).hookSpecificOutput;
  return { decision: out.permissionDecision, reason: out.permissionDecisionReason };
};

// A release branch with one commit, not merged yet.
const releaseBranch = (p) => { git(p.dir, 'switch', '-q', '-c', 'release/1.4.0'); return commit(p, 'CHANGELOG.md', 'chore(release): 1.4.0'); };

// ---------------------------------------------------------------- dev app
test('dev builds and updates pass; submitting the dev app asks', () => {
  const p = project();
  assert.equal(gate(p, 'eas build --profile dev -p ios --non-interactive').decision, 'allow');
  assert.equal(gate(p, 'APP_VARIANT=dev npx --yes eas-cli@25.3.0 update --channel dev --message "fix"').decision, 'allow');
  assert.equal(gate(p, 'npx eas-cli@25.3.0 submit --profile dev -p ios --latest').decision, 'ask');
});

test('check builds of the production app reach no user and pass', () => {
  const p = project();
  releaseBranch(p);
  assert.equal(gate(p, 'eas build --profile production-simulator -p ios --local').decision, 'allow');
});

// ---------------------------------------------------------------- production before the merge
test('a production build from a commit nobody merged is denied, with the route', () => {
  const p = project();
  releaseBranch(p);
  const r = gate(p, 'eas build --profile production -p ios');
  assert.equal(r.decision, 'deny');
  assert.match(r.reason, /isn't on origin\/prod/);
  assert.match(r.reason, /rn-release/);
});

test('eas build with no profile means production', () => {
  const p = project();
  releaseBranch(p);
  assert.equal(gate(p, 'cd app && eas build -p android').decision, 'deny');
});

test('an unreachable remote or a missing production branch is denied, not guessed', () => {
  const p = project();
  git(p.dir, 'remote', 'set-url', 'origin', path.join(os.tmpdir(), 'no-such-remote'));
  assert.match(gate(p, 'eas build --profile production -p ios').reason, /Can't fetch prod/);
  const q = project();
  git(q.dir, 'push', '-q', 'origin', ':prod');
  assert.match(gate(q, 'eas build --profile production -p ios').reason, /Can't fetch prod/);
});

// ---------------------------------------------------------------- production after the merge
test('once merged into the production branch, build, submit by id and tag go through', () => {
  const p = project();
  const sha = releaseBranch(p);
  merge(p);
  assert.equal(gate(p, 'eas build --profile production -p ios --non-interactive').decision, 'allow');
  assert.equal(gate(p, 'eas submit --profile production -p ios --id abc').decision, 'allow');
  git(p.dir, 'tag', 'v1.4.0', sha);
  assert.equal(gate(p, 'git push origin v1.4.0').decision, 'allow');
});

test('a production submit must name the build', () => {
  const p = project();
  releaseBranch(p);
  merge(p);
  assert.match(gate(p, 'eas submit --profile production -p ios --latest').reason, /by build id/);
  assert.match(gate(p, 'eas submit --profile production -p ios').reason, /by build id/);
});

test('a commit added after the merge is denied until it is merged too', () => {
  const p = project();
  releaseBranch(p);
  merge(p);
  commit(p, 'late.txt', 'fix: late change');
  assert.match(gate(p, 'eas build --profile production -p ios').reason, /isn't on origin\/prod/);
  merge(p);
  assert.equal(gate(p, 'eas build --profile production -p ios').decision, 'allow');
});

test('uncommitted changes are denied even on a merged commit', () => {
  const p = project();
  releaseBranch(p);
  merge(p);
  write(p.dir, 'app.json', { expo: { version: '1.4.0', name: 'changed' } });
  assert.match(gate(p, 'eas build --profile production -p ios').reason, /Uncommitted changes/);
});

test('a store build of a version already tagged on another commit is denied; an OTA update is not', () => {
  const p = project();
  const first = releaseBranch(p);
  merge(p);
  git(p.dir, 'tag', 'v1.4.0', first);
  commit(p, 'fix.txt', 'fix: bag badge');
  merge(p);
  assert.match(gate(p, 'eas build --profile production -p ios').reason, /already released/);
  assert.equal(gate(p, 'APP_VARIANT=production eas update --channel production --environment production --message 1.4.1').decision, 'allow');
});

// ---------------------------------------------------------------- OTA updates
test('production OTA: needs the variant, then the merge', () => {
  const p = project();
  releaseBranch(p);
  assert.match(gate(p, 'eas update --channel production --message x').reason, /APP_VARIANT=production/);
  assert.equal(gate(p, 'APP_VARIANT=production eas update --channel production --environment production --message x').decision, 'deny');
  merge(p);
  assert.equal(gate(p, 'APP_VARIANT=production eas update --channel production --environment production --message x').decision, 'allow');
});

test('a variant that contradicts the profile or channel is denied', () => {
  const p = project();
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

// ---------------------------------------------------------------- the approval stays a person's
test('pushing to the production branch from the session is denied', () => {
  const p = project();
  releaseBranch(p);
  assert.match(gate(p, 'git push origin HEAD:prod').reason, /release approval/);
  assert.match(gate(p, 'git push origin release/1.4.0:refs/heads/prod').reason, /release approval/);
  assert.equal(gate(p, 'git push --all origin').decision, 'deny');
  git(p.dir, 'switch', '-q', '-c', 'prod');
  assert.equal(gate(p, 'git push').decision, 'deny');
  assert.equal(gate(p, 'git push origin prod').decision, 'deny');
});

test('pushing the release branch and opening the PR / MR pass', () => {
  const p = project();
  releaseBranch(p);
  assert.equal(gate(p, 'git push -u origin release/1.4.0').decision, 'allow');
  assert.equal(gate(p, 'gh pr create --base prod --head release/1.4.0 --title "Release 1.4.0"').decision, 'allow');
  assert.equal(gate(p, 'glab mr create --target-branch prod --source-branch release/1.4.0').decision, 'allow');
});

test('approving or merging a PR / MR from the session is denied', () => {
  const p = project();
  assert.equal(gate(p, 'gh pr review 12 --approve').decision, 'deny');
  assert.equal(gate(p, 'gh pr merge 12 --squash').decision, 'deny');
  assert.equal(gate(p, 'gh api repos/acme/shop/pulls/12/merge -X PUT').decision, 'deny');
  assert.equal(gate(p, 'glab mr approve 7').decision, 'deny');
  assert.equal(gate(p, 'glab mr merge 7').decision, 'deny');
  assert.equal(gate(p, 'gh pr review 12 --comment -b "looks fine"').decision, 'allow');
});

test('release tags: by name, and only on a merged commit', () => {
  const p = project();
  const sha = releaseBranch(p);
  git(p.dir, 'tag', 'v1.4.0', sha);
  assert.match(gate(p, 'git push origin v1.4.0').reason, /marks a production release/);
  assert.match(gate(p, 'git push --tags').reason, /by name/);
  merge(p);
  assert.equal(gate(p, 'git push origin v1.4.0').decision, 'allow');
});

// ---------------------------------------------------------------- everything else
test('an unknown profile is denied; other commands and tools pass', () => {
  const p = project();
  assert.match(gate(p, 'eas build --profile qa').reason, /doesn't know which app/);
  assert.equal(gate(p, 'git push origin feat/cart').decision, 'allow');
  assert.equal(gate(p, 'ls -la && pnpm test').decision, 'allow');
  assert.equal(gate(p, 'eas whoami').decision, 'allow');
  assert.equal(gate(p, 'eas build --profile production', 'Read').decision, 'allow');
});

test('without a release block, prod* names are production and main is the production branch', () => {
  const p = project({ release: false });
  git(p.dir, 'switch', '-q', '-c', 'feat/x');
  commit(p, 'x.txt', 'feat: x');
  assert.equal(gate(p, 'eas build --profile production -p ios').decision, 'deny');
  assert.equal(gate(p, 'eas build --profile dev -p ios').decision, 'allow');
  merge(p, 'main');
  assert.equal(gate(p, 'eas build --profile production -p ios').decision, 'allow');
});
