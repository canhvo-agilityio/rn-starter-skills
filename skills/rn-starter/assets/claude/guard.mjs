#!/usr/bin/env node
// Claude Code PreToolUse hook (installed by rn-starter): blocks three things before they happen,
// and tells Claude why and what to do instead.
//   1. git push to a protected branch (protectedBranches in .rn-starter.json, default main/master)
//   2. reading or writing secret files: .env files (not the committed templates), signing keys,
//      keystores, credentials.json, service-account keys
//   3. hand edits to generated files (*.gen.ts, e.g. src/types/api.gen.ts)
// It guards against mistakes, not against someone determined to get around it: the real push
// protection is branch protection on the server. Anything it can't parse is allowed, so a bug
// here never blocks normal work. Plain Node with no dependencies, so it runs the same on Windows.
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const root = process.env.CLAUDE_PROJECT_DIR || process.cwd();

let input = {};
try {
  input = JSON.parse(fs.readFileSync(0, 'utf8') || '{}');
} catch {
  process.exit(0);
}
const tool = input.tool_name || '';
const args = input.tool_input || {};

const deny = (reason) => {
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'deny', permissionDecisionReason: reason },
  }));
  process.exit(0);
};

// ---------------------------------------------------------------- secrets
const TEMPLATES = /^\.env\.(example|sample|template)$/;
const isSecret = (p) => {
  const base = path.basename(String(p).replace(/["']/g, ''));
  if (base === '.env' || (base.startsWith('.env.') && !TEMPLATES.test(base))) return true;
  if (/\.(p8|p12|pfx|jks|keystore|key)$/i.test(base)) return true;
  if (base === 'credentials.json' || /service[-_]?account.*\.json$/i.test(base)) return true;
  return /^id_(rsa|ed25519|ecdsa)$/.test(base);
};
const SECRET_REASON = (p) => `${p} holds secrets, so it stays closed: never read, print, copy or edit it. `
  + 'Ask the developer for the value you need, use the committed template (.env.example) for variable names, '
  + 'and refer to credential files by path only.';

// ---------------------------------------------------------------- generated files
const isGenerated = (p) => /\.gen\.(ts|tsx|js)$/.test(String(p));
const GENERATED_REASON = (p) => `${p} is generated, never edited by hand. Change its source instead `
  + '(for src/types/api.gen.ts: refresh docs/api/openapi.json, then run the api:types script) or fix the mapper that uses it.';

// ---------------------------------------------------------------- protected branches
const protectedBranches = () => {
  try {
    const b = JSON.parse(fs.readFileSync(path.join(root, '.rn-starter.json'), 'utf8')).protectedBranches;
    if (Array.isArray(b) && b.length) return b;
  } catch {}
  return ['main', 'master'];
};
// symbolic-ref also answers on a branch with no commits yet, where rev-parse fails.
const currentBranch = (cwd) => {
  try {
    return execFileSync('git', ['symbolic-ref', '--short', 'HEAD'], { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch {
    return null;
  }
};

// Split a shell command into simple commands (on ; && || | and newlines), then into words.
// Good enough for what Claude writes; quoted separators are rare in these commands.
const segments = (cmd) => cmd.split(/;|&&|\|\||\||\n/).map((s) => s.trim()).filter(Boolean);
const words = (seg) => (seg.match(/"[^"]*"|'[^']*'|\S+/g) || []).map((w) => w.replace(/^["']|["']$/g, ''));

// Targets of one `git push`: explicit refspecs (src:dst → dst), else the current branch.
const pushTargets = (w) => {
  const gi = w.indexOf('git');
  let i = gi + 1;
  let cwd = root;
  while (i < w.length && w[i] !== 'push') {
    if (w[i] === '-C') { cwd = path.resolve(root, w[i + 1] || '.'); i += 2; } else i += 1;
  }
  const rest = w.slice(i + 1);
  if (rest.some((a) => a === '--all' || a === '--mirror')) return ['--all'];
  const positional = [];
  for (let j = 0; j < rest.length; j += 1) {
    const a = rest[j];
    if (a.startsWith('-')) {
      if (['-o', '--push-option', '--repo', '--receive-pack', '--exec'].includes(a)) j += 1;
      continue;
    }
    positional.push(a);
  }
  const refspecs = positional.slice(1); // the first positional is the remote
  if (!refspecs.length) return [currentBranch(cwd)].filter(Boolean);
  return refspecs.map((r) => {
    const dst = r.includes(':') ? r.split(':').pop() : r;
    const name = dst.replace(/^\+/, '').replace(/^refs\/heads\//, '');
    return name === 'HEAD' ? currentBranch(cwd) : name;
  }).filter(Boolean);
};

const READERS = new Set(['cat', 'less', 'more', 'head', 'tail', 'grep', 'rg', 'egrep', 'awk', 'sed', 'cut', 'sort',
  'strings', 'xxd', 'od', 'hexdump', 'base64', 'source', '.', 'cp', 'mv', 'scp', 'rsync', 'tee', 'openssl', 'keytool',
  'jq', 'bat', 'nl', 'diff', 'zip', 'tar', 'curl', 'printenv', 'dotenv', 'code', 'open', 'vi', 'vim', 'nano']);

const checkBash = (cmd) => {
  for (const seg of segments(cmd)) {
    const w = words(seg);
    if (!w.length) continue;

    // git push
    const gi = w.indexOf('git');
    if (gi !== -1 && w.slice(gi + 1).includes('push')) {
      const prot = protectedBranches();
      const targets = pushTargets(w);
      const hit = targets.find((t) => t === '--all' || prot.includes(t));
      if (hit) {
        deny(`Pushing ${hit === '--all' ? 'every branch' : `to ${hit}`} is blocked: protected branches (${prot.join(', ')}) `
          + 'only change through a reviewed pull request. Push a feature branch and open a pull request instead; '
          + "don't retry with --no-verify or --force.");
      }
    }

    // reading a secret file through the shell
    const secretWord = w.find((x) => isSecret(x) || isSecret(x.replace(/^<+/, '')));
    const redirected = /<\s*\S*\.env\b/.test(seg) && !/\.env\.(example|sample|template)\b/.test(seg);
    const cmdName = path.basename(w[0]);
    // Inline scripts (node -e "...readFileSync('.env')") hide the name inside one word.
    const inlineSecret = ['node', 'python', 'python3', 'ruby', 'perl', 'deno', 'bun'].includes(cmdName)
      && (seg.match(/[\w./~-]*(\.env(\.\w+)?|\.(p8|p12|pfx|jks|keystore)|credentials\.json|service[-_]?account[\w.-]*\.json)\b/g) || [])
        .find((m) => isSecret(m));
    if (redirected || inlineSecret || (secretWord && READERS.has(cmdName))) {
      deny(SECRET_REASON(secretWord || inlineSecret || '.env'));
    }
  }
};

if (tool === 'Bash') {
  checkBash(String(args.command || ''));
} else if (['Read', 'Edit', 'MultiEdit', 'Write', 'NotebookEdit'].includes(tool)) {
  const file = args.file_path || args.notebook_path || '';
  if (isSecret(file)) deny(SECRET_REASON(path.basename(file)));
  const rel = path.relative(root, file);
  if (tool !== 'Read' && isGenerated(file)) deny(GENERATED_REASON(rel && !rel.startsWith('..') ? rel : file));
} else if (tool === 'Grep' || tool === 'Glob') {
  const target = args.path || '';
  if (target && isSecret(target)) deny(SECRET_REASON(path.basename(target)));
}
process.exit(0);
