// Tests for guard.mjs, next to it. Run: node --test skills/rn-starter/assets/claude/guard.test.mjs
// Each case builds a throwaway git repo (optionally with .rn-starter.json and a bug-fix test lock)
// and feeds the hook one tool call.
import { execFileSync, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import assert from 'node:assert/strict';

const HOOK = path.resolve(import.meta.dirname, 'guard.mjs');

const project = ({ branches, branch = 'feat/cart', lock } = {}) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'guard-'));
  if (branches) fs.writeFileSync(path.join(dir, '.rn-starter.json'), JSON.stringify({ protectedBranches: branches }));
  execFileSync('git', ['init', '-q', '-b', branch], { cwd: dir });
  if (lock) {
    fs.mkdirSync(path.join(dir, '.claude'), { recursive: true });
    fs.writeFileSync(path.join(dir, '.claude', 'fix-task.json'), JSON.stringify({ files: lock }));
  }
  return dir;
};

const guard = (dir, tool, input) => {
  const r = spawnSync('node', [HOOK], {
    input: typeof input === 'string' ? input : JSON.stringify({ tool_name: tool, tool_input: input }),
    env: { ...process.env, CLAUDE_PROJECT_DIR: dir }, cwd: dir, encoding: 'utf8',
  });
  if (!r.stdout.trim()) return { decision: 'allow', reason: '' };
  const out = JSON.parse(r.stdout).hookSpecificOutput;
  return { decision: out.permissionDecision, reason: out.permissionDecisionReason };
};
const bash = (dir, command) => guard(dir, 'Bash', { command });

// ---------------------------------------------------------------- protected branches
test('pushes to the default protected branches are denied', () => {
  const dir = project();
  assert.equal(bash(dir, 'git push origin main').decision, 'deny');
  assert.equal(bash(dir, 'git push origin feat/cart:master').decision, 'deny');
  assert.equal(bash(dir, 'git push origin feat/cart').decision, 'allow');
});

test('the protected list comes from .rn-starter.json', () => {
  const dir = project({ branches: ['main', 'dev', 'stag', 'prod'] });
  for (const b of ['dev', 'stag', 'prod']) assert.equal(bash(dir, `git push origin HEAD:${b}`).decision, 'deny');
  assert.equal(bash(dir, 'git push origin feat/cart:refs/heads/dev').decision, 'deny');
  assert.equal(bash(dir, 'git push --force --no-verify origin x:prod').decision, 'deny');
});

test('a bare push, HEAD, --all and -C follow the branch they really target', () => {
  const onMain = project({ branch: 'main' });
  assert.equal(bash(onMain, 'git push').decision, 'deny');
  assert.equal(bash(onMain, 'git push origin HEAD').decision, 'deny');
  const onFeature = project();
  assert.equal(bash(onFeature, 'git push').decision, 'allow');
  assert.equal(bash(onFeature, 'git push --all origin').decision, 'deny');
  assert.equal(bash(onFeature, `git -C ${onMain} push`).decision, 'deny');
  assert.match(bash(onMain, 'git push').reason, /pull request/);
});

// ---------------------------------------------------------------- secret files
test('reading or editing secret files is denied; templates are allowed', () => {
  const dir = project();
  for (const f of ['.env', '.env.local', '.env.production', 'AuthKey_ABC123.p8', 'dist.p12', 'upload.jks', 'release.keystore', 'credentials.json', 'service-account-play.json']) {
    assert.equal(guard(dir, 'Read', { file_path: path.join(dir, f) }).decision, 'deny', f);
  }
  assert.equal(guard(dir, 'Edit', { file_path: path.join(dir, '.env') }).decision, 'deny');
  assert.equal(guard(dir, 'Read', { file_path: path.join(dir, '.env.example') }).decision, 'allow');
  assert.equal(guard(dir, 'Read', { file_path: path.join(dir, 'app.json') }).decision, 'allow');
  assert.equal(guard(dir, 'Grep', { pattern: 'KEY', path: path.join(dir, '.env') }).decision, 'deny');
});

test('reading secrets through the shell is denied, including inline scripts and redirects', () => {
  const dir = project();
  assert.equal(bash(dir, 'cat .env').decision, 'deny');
  assert.equal(bash(dir, 'grep API_URL .env.local').decision, 'deny');
  assert.equal(bash(dir, 'node -e "console.log(require(\'fs\').readFileSync(\'.env\',\'utf8\'))"').decision, 'deny');
  assert.equal(bash(dir, 'wc -l < .env').decision, 'deny');
  assert.equal(bash(dir, 'cat .env.example').decision, 'allow');
  assert.equal(bash(dir, 'ls -la').decision, 'allow');
});

// ---------------------------------------------------------------- generated files
test('hand edits to generated files are denied; reading them is fine', () => {
  const dir = project();
  const file = path.join(dir, 'src/types/api.gen.ts');
  assert.match(guard(dir, 'Edit', { file_path: file }).reason, /generated/);
  assert.equal(guard(dir, 'Write', { file_path: file }).decision, 'deny');
  assert.equal(guard(dir, 'Read', { file_path: file }).decision, 'allow');
});

// ---------------------------------------------------------------- the bug-fix test lock
test('a locked bug test and the lock itself only change through lock-tests.sh', () => {
  const dir = project({ lock: ['src/utils/__tests__/pricing.test.ts'] });
  const file = path.join(dir, 'src/utils/__tests__/pricing.test.ts');
  assert.match(guard(dir, 'Edit', { file_path: file }).reason, /reproduces the bug/);
  assert.equal(bash(dir, 'sed -i "" "s/2/3/" src/utils/__tests__/pricing.test.ts').decision, 'deny');
  assert.equal(bash(dir, 'echo x > src/utils/__tests__/pricing.test.ts').decision, 'deny');
  assert.equal(bash(dir, 'rm .claude/fix-task.json').decision, 'deny');
  assert.equal(guard(dir, 'Read', { file_path: file }).decision, 'allow');
  assert.equal(guard(dir, 'Edit', { file_path: path.join(dir, 'src/utils/pricing.ts') }).decision, 'allow');
  assert.equal(bash(dir, 'bash scripts/lock-tests.sh unlock').decision, 'allow');
});

// ---------------------------------------------------------------- fail-open by design
test('input it cannot parse, and other tools, are allowed', () => {
  const dir = project();
  assert.equal(guard(dir, null, 'not json').decision, 'allow');
  assert.equal(guard(dir, 'WebFetch', { url: 'https://example.com' }).decision, 'allow');
  assert.equal(bash(dir, '').decision, 'allow');
});
