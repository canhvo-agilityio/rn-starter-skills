#!/usr/bin/env bash
# Add Claude Code project files to a React Native / Expo project:
#   CLAUDE.md                        stack, commands, structure and code-style rules for Claude
#   .claude/hooks/format.mjs         PostToolUse hook: Prettier/ESLint (or Biome) on every edited file
#   .claude/hooks/guard.mjs          PreToolUse hook: blocks pushes to protected branches, secret files,
#                                    hand edits to generated files
#   .claude/settings.json            registers both hooks (merged into an existing file)
#   .claude/agents/code-reviewer.md  read-only review subagent
#   .claude/agents/verifier.md       runs the app and checks the change, report only
#
# Usage: setup-claude.sh [--force] [project-dir]
#   --force   overwrite an existing CLAUDE.md and the two agent files
#
# Idempotent: the hook scripts are always refreshed, each hook is registered once, and files the
# team may have edited (CLAUDE.md, the agents) are only created when missing unless --force.
# Reads .rn-starter.json when present, else package.json. Needs node (always there in an RN project).
# Plain bash + node, so it runs as-is in Git Bash on Windows.
#
# Exit 0 = done · 1 = error · 3 = done, but an existing CLAUDE.md was kept (merge decision needed).

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
assets="$here/../assets/claude"

force=0; dir="."
while [ $# -gt 0 ]; do
  case "$1" in
    --force) force=1 ;;
    -*) echo "unknown option: $1" >&2; exit 64 ;;
    *) dir="$1" ;;
  esac
  shift
done

cd "$dir"
[ -f package.json ] || { echo "error: no package.json in $(pwd)" >&2; exit 1; }
command -v node >/dev/null || { echo "error: node not found — source env.sh first" >&2; exit 1; }
log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

mkdir -p .claude/hooks .claude/agents
written=(.claude/settings.json)

log "Format and guard hooks"
cp "$assets/format.mjs" .claude/hooks/format.mjs
cp "$assets/guard.mjs" .claude/hooks/guard.mjs
node - <<'EOF'
const fs = require('fs');
const file = '.claude/settings.json';
let settings = {};
if (fs.existsSync(file)) settings = JSON.parse(fs.readFileSync(file, 'utf8'));
settings.hooks ??= {};
const register = (event, matcher, script, timeout) => {
  const command = `node "$CLAUDE_PROJECT_DIR/.claude/hooks/${script}"`;
  settings.hooks[event] ??= [];
  const registered = settings.hooks[event].some((entry) =>
    (entry.hooks || []).some((h) => h.command === command));
  if (!registered) settings.hooks[event].push({ matcher, hooks: [{ type: 'command', command, timeout }] });
  console.log(`${script}: ${registered ? 'already registered' : 'registered'} (${event})`);
};
register('PostToolUse', 'Edit|MultiEdit|Write', 'format.mjs', 60);
register('PreToolUse', 'Bash|Read|Edit|MultiEdit|Write|NotebookEdit|Grep|Glob', 'guard.mjs', 10);
fs.writeFileSync(file, JSON.stringify(settings, null, 2) + '\n');
EOF

# Personal overrides stay out of git; the shared settings, hook, agent and CLAUDE.md go in.
if [ -f .gitignore ] && ! grep -qx '.claude/settings.local.json' .gitignore; then
  printf '\n# Claude Code personal settings\n.claude/settings.local.json\n' >> .gitignore
fi

log "Subagents"
for agent in code-reviewer verifier; do
  if [ "$force" -eq 1 ] || [ ! -f ".claude/agents/$agent.md" ]; then
    cp "$assets/$agent.md" ".claude/agents/$agent.md"
    written+=(".claude/agents/$agent.md")
    echo "wrote .claude/agents/$agent.md"
  else
    echo "kept existing .claude/agents/$agent.md (--force to replace)"
  fi
done

log "CLAUDE.md"
kept=0
if [ "$force" -eq 1 ] || [ ! -f CLAUDE.md ]; then
  node - "$assets/CLAUDE.md" <<'EOF'
const fs = require('fs');
const path = require('path');
const read = (f) => { try { return JSON.parse(fs.readFileSync(f, 'utf8')); } catch { return null; } };

const pkg = read('package.json');
const starter = read('.rn-starter.json') || {};
const deps = { ...pkg.dependencies, ...pkg.devDependencies };
const scripts = pkg.scripts || {};

const pm = starter.packageManager
  || (fs.existsSync('pnpm-lock.yaml') ? 'pnpm' : fs.existsSync('yarn.lock') ? 'yarn'
    : fs.existsSync('bun.lockb') || fs.existsSync('bun.lock') ? 'bun' : 'npm');
const isExpo = !!deps.expo;
const pmRun = (name) => (pm === 'npm' && !['start', 'test'].includes(name) ? `npm run ${name}` : `${pm} ${name}`);

const labels = {
  'expo-router': 'expo-router', 'react-navigation': 'React Navigation', zustand: 'Zustand',
  'redux-toolkit': 'Redux Toolkit', jotai: 'Jotai', 'tanstack-query': 'TanStack Query',
  stylesheet: 'StyleSheet + theme tokens', nativewind: 'NativeWind', unistyles: 'Unistyles',
  'eslint-prettier': 'ESLint + Prettier', biome: 'Biome', 'jest-rntl': 'Jest + React Native Testing Library',
};
const label = (v) => labels[v] || v;
const stack = [
  ['Framework', isExpo ? `Expo SDK ${String(deps.expo).replace(/^[~^]/, '')}` : `React Native ${deps['react-native'] || ''} (CLI)`],
  ['Bundler', starter.bundler === 'repack' ? 'Re.Pack (Rspack)' : 'Metro'],
  ['Navigation', starter.navigation || (deps['expo-router'] ? 'expo-router' : deps['@react-navigation/native'] ? 'react-navigation' : null)],
  ['State', starter.state || (deps.zustand ? 'zustand' : null)],
  ['Server data', starter.serverData || (deps['@tanstack/react-query'] ? 'tanstack-query' : null)],
  ['Styling', starter.styling || (deps.nativewind ? 'nativewind' : 'stylesheet')],
  ['Lint / format', starter.lint || (deps['@biomejs/biome'] ? 'biome' : deps.eslint ? 'eslint-prettier' : null)],
  ['Tests', starter.quality?.unitTests || (deps.jest ? 'jest-rntl' : null)],
  ['Package manager', pm],
].filter(([, v]) => v && v !== 'none').map(([k, v]) => `- ${k}: ${label(v)}`).join('\n');

const commands = [
  ['Start dev server', scripts.start && pmRun('start')],
  ['iOS Simulator', scripts.ios && pmRun('ios')],
  ['Android emulator', scripts.android && pmRun('android')],
  ['Web', scripts.web && pmRun('web')],
  ['Lint', scripts.lint ? pmRun('lint') : deps.eslint && 'npx eslint src'],
  ['Type check', fs.existsSync('tsconfig.json') && 'npx tsc --noEmit'],
  ['Unit tests', scripts.test && pmRun('test')],
  ['Related tests only', deps.jest && 'npx jest --findRelatedTests <files>'],
].filter(([, c]) => c).map(([k, c]) => `| ${k} | \`${c}\` |`);

// Each check with what a healthy run looks like, so "it passed" is something Claude can see.
const biome = fs.existsSync('biome.json') || fs.existsSync('biome.jsonc');
const verify = [
  fs.existsSync('tsconfig.json') && ['Type check', 'npx tsc --noEmit', 'prints nothing, exit 0'],
  biome ? ['Lint', 'npx biome check src', 'no errors']
    : deps.eslint && ['Lint', 'npx eslint src', 'prints nothing, exit 0'],
  deps.jest && ['Tests for what changed', 'npx jest --findRelatedTests <changed files> --passWithNoTests', '"Tests: N passed", no failures'],
  scripts.test && ['All unit tests', pmRun('test'), 'every suite passes'],
  isExpo && ['After adding or upgrading a package', 'npx expo-doctor', 'every check passes'],
].filter(Boolean).map(([k, c, ok]) => `| ${k} | \`${c}\` | ${ok} |`);
let protectedList = ['main', 'master'];
if (Array.isArray(starter.protectedBranches) && starter.protectedBranches.length) protectedList = starter.protectedBranches;

const layered = (starter.structure || (fs.existsSync('src/screens') ? 'layered' : 'template')) === 'layered';
const commitlint = fs.readdirSync('.').some((f) => /^commitlint\.config\./.test(f));
const husky = fs.existsSync('.husky');

let md = fs.readFileSync(process.argv[2], 'utf8')
  .replace('{{APP_NAME}}', pkg.name || path.basename(process.cwd()))
  .replace('{{FRAMEWORK}}', isExpo ? 'Expo' : 'React Native CLI')
  // Expo templates ship AGENTS.md (versioned-docs and EAS guidance); Claude Code reads it through an import.
  .replace('{{AGENTS}}', fs.existsSync('AGENTS.md') ? 'Framework guidance from the template: @AGENTS.md' : '')
  .replace('{{STACK}}', stack)
  .replace('{{COMMANDS}}', ['| | |', '|---|---|', ...commands].join('\n'))
  .replace('{{VERIFY}}', ['| Check | Command | Healthy output |', '|---|---|---|', ...verify].join('\n'))
  .replace('{{PROTECTED}}', `protected branches (${protectedList.map((b) => `\`${b}\``).join(', ')})`)
  .replace('{{STYLE_RULE}}', ({
    'react-native-paper': 'UI comes from React Native Paper; style through its theme (`useAppTheme()`), not a second theme.',
    tamagui: 'UI comes from Tamagui; use its components and theme values the way existing components do, not a second theme.',
    '@gluestack-ui/core': 'UI comes from gluestack-ui; style with `className` and its CSS-variable tokens.',
  })[['react-native-paper', 'tamagui', '@gluestack-ui/core'].find((d) => deps[d])]
    || (deps.nativewind ? 'Style with `className`; colors are CSS variables per scheme (`theme.md` in rn-ui).'
    : deps['react-native-unistyles'] ? 'Style with `StyleSheet.create((theme) => …)` from react-native-unistyles at the bottom of the file; avoid `useUnistyles()`.'
    : 'Styles go at the bottom of the file: a module-level `StyleSheet.create` for layout and tokens, and `createThemedStyles` from `src/theme` for colors (built once per scheme, shared by every instance).'))
  .replace('{{INSTALL_RULE}}', isExpo
    ? 'Add packages with `npx expo install <pkg>` so versions match the SDK.'
    : `Add packages with \`${pm} add <pkg>\`; after a native dependency, run \`cd ios && pod install\` and rebuild.`)
  .replace('{{COMMIT_RULE}}', [
    husky && '- Git hooks run lint, format and tests on commit and push. Never bypass them with `--no-verify`.',
    commitlint && '- Commit messages follow Conventional Commits (`feat: …`, `fix: …`, `chore: …`); commitlint checks them.',
  ].filter(Boolean).join('\n'));

// Keep the structure section that applies, drop the other one and the markers.
const keep = layered ? 'layered' : 'template';
md = md.replace(/<!-- structure:(\w+) -->\n([\s\S]*?)<!-- \/structure:\1 -->\n/g,
  (_, name, body) => (name === keep ? body : ''));
fs.writeFileSync('CLAUDE.md', md.replace(/\n{3,}/g, '\n\n').trimEnd() + '\n');
console.log(`wrote CLAUDE.md (${layered ? 'layered structure' : 'template structure'})`);
EOF
  written+=(CLAUDE.md)
else
  kept=1
  echo "kept existing CLAUDE.md (--force to replace)"
fi

# Format the generated files with the project's Prettier now, so lint-staged doesn't rewrite them
# in the first commit.
if [ -f node_modules/prettier/package.json ]; then
  npx --no-install prettier --write --log-level warn "${written[@]}" >/dev/null 2>&1 || true
fi

echo
log "Summary"
echo "CLAUDE.md                         $([ "$kept" -eq 1 ] && echo 'existing file kept' || echo 'written')"
echo ".claude/settings.json             PostToolUse (Edit|MultiEdit|Write) → node .claude/hooks/format.mjs"
echo ".claude/hooks/format.mjs          $( [ -f biome.json ] || [ -f biome.jsonc ] && echo 'biome check --write' || echo 'prettier --write, eslint --fix') on the edited file"
echo ".claude/settings.json             PreToolUse (Bash|Read|Edit|Write|…) → node .claude/hooks/guard.mjs"
echo ".claude/hooks/guard.mjs           blocks pushes to: $(node -e "try{const b=require('./.rn-starter.json').protectedBranches;if(b&&b.length){console.log(b.join(', '));process.exit(0)}}catch{}console.log('main, master')"); secret files; edits to *.gen.ts"
echo ".claude/agents/code-reviewer.md   subagent 'code-reviewer' (read-only)"
echo ".claude/agents/verifier.md        subagent 'verifier' (runs the app, reports only)"
[ "$kept" -eq 1 ] && exit 3
exit 0
