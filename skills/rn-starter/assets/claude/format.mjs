#!/usr/bin/env node
// Claude Code PostToolUse hook (installed by rn-starter): formats and lint-fixes the file Claude
// just wrote, with the project's own Prettier / ESLint / Biome. Problems --fix can't solve go back
// to Claude on stderr with exit 2, so it fixes them in the same turn instead of at commit time.
// Plain Node with no dependencies, so it runs the same on macOS, Linux and Windows.
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const root = process.env.CLAUDE_PROJECT_DIR || process.cwd();

let input = {};
try {
  input = JSON.parse(fs.readFileSync(0, 'utf8') || '{}');
} catch {
  process.exit(0);
}
const file = input.tool_input?.file_path;
if (!file || !fs.existsSync(file)) process.exit(0);

const rel = path.relative(root, file);
const outside = rel.startsWith('..') || path.isAbsolute(rel);
const generated = /(^|[\\/])(node_modules|ios|android|\.expo|dist|coverage)[\\/]/.test(rel);
if (outside || generated) process.exit(0);

const isCode = /\.(c|m)?(j|t)sx?$/.test(file);
const isFormattable = isCode || /\.(json|md|ya?ml|css)$/.test(file);
if (!isFormattable) process.exit(0);

// Resolve a tool's bin script from the project's node_modules and run it with this Node, which
// avoids npx startup time and the .cmd shims on Windows.
const binOf = (pkg, name) => {
  const dir = path.join(root, 'node_modules', pkg);
  try {
    const { bin } = JSON.parse(fs.readFileSync(path.join(dir, 'package.json'), 'utf8'));
    const rel = typeof bin === 'string' ? bin : bin?.[name];
    return rel ? path.join(dir, rel) : null;
  } catch {
    return null;
  }
};
const run = (script, args) => {
  const r = spawnSync(process.execPath, [script, ...args], { cwd: root, encoding: 'utf8' });
  return { ok: r.status === 0, out: `${r.stdout ?? ''}${r.stderr ?? ''}`.trim() };
};

const problems = [];
const biome = binOf('@biomejs/biome', 'biome');
const hasBiomeConfig = ['biome.json', 'biome.jsonc'].some((f) => fs.existsSync(path.join(root, f)));

if (biome && hasBiomeConfig) {
  const r = run(biome, ['check', '--write', '--no-errors-on-unmatched', file]);
  if (!r.ok) problems.push(r.out);
} else {
  const prettier = binOf('prettier', 'prettier');
  if (prettier) {
    const r = run(prettier, ['--write', '--ignore-unknown', '--log-level', 'warn', file]);
    if (!r.ok) problems.push(r.out);
  }
  const eslint = binOf('eslint', 'eslint');
  if (eslint && isCode) {
    const r = run(eslint, ['--fix', '--no-warn-ignored', file]);
    if (!r.ok) problems.push(r.out);
  }
}

if (problems.length) {
  process.stderr.write(`Lint/format problems left in ${rel} — fix them:\n${problems.join('\n')}\n`);
  process.exit(2);
}
