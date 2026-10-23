#!/usr/bin/env bash
# List the data domains of a React Native / Expo project and how each one gets its data today.
# Read-only. Prints JSON to stdout.
#
# Usage: api-inventory.sh [project-dir]   (default: current directory)
#
# A domain is a service file (src/services/<domain>.ts, or src/features/<domain>/api.ts on the
# older feature-first layout). For each one: its exported functions, the hooks that wrap it,
# the screens that use those hooks, its mock, and its source:
#   mock       imports mocks only
#   connected  calls the API client and falls back to mocks behind the env flag
#   api        calls an API (client, fetch, axios) without mocks
#   mixed      imports mocks and calls an API with no flag (check by hand)
#   unknown    neither
#
# Never opens .env / .env.local: those hold the developer's secrets. Env information comes from
# the documented templates (.env.example, .env.sample, .env.template), the code, and git (whether
# .env is ignored). Ask the developer for anything else.
#
# Exit codes: 0 done · 1 error · 3 done, but the project has no service seam (decision needed)

set -euo pipefail
dir="$(cd "${1:-.}" && pwd)"
[ -f "$dir/package.json" ] || { echo "{\"error\":\"no package.json in $dir\"}"; exit 1; }
command -v node >/dev/null 2>&1 || { echo '{"error":"node not found — source rn-starter/scripts/env.sh first"}'; exit 1; }

node - "$dir" <<'EOF'
const fs = require('fs');
const path = require('path');
const dir = process.argv[2];
const exists = (p) => fs.existsSync(path.join(dir, p));
const read = (p) => fs.readFileSync(path.join(dir, p), 'utf8');
const pkg = JSON.parse(read('package.json'));
const deps = { ...pkg.dependencies, ...pkg.devDependencies };
const has = (name) => Object.prototype.hasOwnProperty.call(deps, name);

let starter = null;
if (exists('.rn-starter.json')) {
  try { starter = JSON.parse(read('.rn-starter.json')); } catch {}
}

const SKIP = new Set(['node_modules', '.git', '.expo', 'ios', 'android', 'dist', 'build']);
const walk = (p, out = []) => {
  if (!exists(p)) return out;
  for (const e of fs.readdirSync(path.join(dir, p)).sort()) {
    if (SKIP.has(e)) continue;
    const rel = path.posix.join(p, e);
    if (fs.statSync(path.join(dir, rel)).isDirectory()) walk(rel, out);
    else if (/\.(ts|tsx|js|jsx)$/.test(e)) out.push(rel);
  }
  return out;
};
const isTest = (f) => /__tests__|\.test\.|\.spec\.|test-utils/.test(f);

const srcRoot = exists('src') ? 'src' : '.';
const files = walk(srcRoot === '.' ? '' : 'src').filter((f) => !isTest(f));
const src = Object.fromEntries(files.map((f) => [f, read(f)]));

const framework = has('expo') ? 'expo' : 'react-native-cli';
const pm = exists('pnpm-lock.yaml') ? 'pnpm' : exists('yarn.lock') ? 'yarn'
  : (exists('bun.lockb') || exists('bun.lock')) ? 'bun' : 'npm';
const queryLibrary = has('@tanstack/react-query') ? 'tanstack-query'
  : has('swr') ? 'swr' : has('@reduxjs/toolkit') ? 'redux-toolkit' : 'none';
const layout = exists('src/services') ? 'layered'
  : exists('src/features') ? 'feature-first' : 'none';

// Service files per layout.
const serviceFiles = layout === 'layered'
  ? files.filter((f) => /^src\/services\/[^/]+\.(ts|js)$/.test(f) && !/index\.(ts|js)$/.test(f))
  : layout === 'feature-first'
    ? files.filter((f) => /^src\/features\/[^/]+\/api\.(ts|js)$/.test(f))
    : [];
const domainOf = (f) => layout === 'feature-first' ? f.split('/')[2] : path.basename(f).replace(/\.(ts|js)$/, '');

const exportsOf = (code) => {
  const names = new Set();
  for (const m of code.matchAll(/export\s+(?:const|let)\s+(\w+)\s*(?::[^=]+)?=\s*(?:async\b|\()/g)) names.add(m[1]);
  for (const m of code.matchAll(/export\s+(?:async\s+)?function\s+(\w+)/g)) names.add(m[1]);
  return [...names];
};
const MUTATION = /^(set|add|create|update|delete|remove|toggle|post|put|patch|save|place|cancel|submit|mark|clear)/i;

const clientPattern = /from\s+['"](@\/lib\/api-client|\.\.?\/.*api-client|openapi-fetch|axios|ky)['"]|\bfetch\(|\baxios\./;
const mockPattern = /from\s+['"](@\/mocks[^'"]*|\.\.?\/(?:\.\.\/)*mocks[^'"]*|\.\/mocks)['"]/;
const flagPattern = /USE_MOCKS|useMocks|EXPO_PUBLIC_USE_MOCKS/;

const importsModule = (code, target) => {
  // target like 'services/coffees' — match @/services/coffees and relative paths ending in it
  const re = new RegExp(`from\\s+['"][^'"]*${target.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}['"]`);
  return re.test(code);
};

const domains = serviceFiles.map((file) => {
  const code = src[file];
  const domain = domainOf(file);
  const modulePath = file.replace(/^src\//, '').replace(/\.(ts|js)$/, '');
  const usesClient = clientPattern.test(code);
  const usesMocks = mockPattern.test(code);
  const usesFlag = flagPattern.test(code);
  const source = usesClient && usesMocks ? (usesFlag ? 'connected' : 'mixed')
    : usesClient ? 'api' : usesMocks ? 'mock' : 'unknown';
  const mockImports = [...code.matchAll(/from\s+['"]([^'"]*mocks[^'"]*)['"]/g)].map((m) => m[1]);
  const hooks = files.filter((f) => f !== file && /hooks/.test(f) && importsModule(src[f], modulePath));
  const hookNames = hooks.flatMap((h) => exportsOf(src[h]).filter((n) => /^use[A-Z]/.test(n)));
  const hookModules = hooks.map((h) => h.replace(/^src\//, '').replace(/\.(ts|tsx|js)$/, ''));
  // Screens import shared hooks from their index.tsx or their own hooks.ts; report the screen folder.
  const usedBy = [...new Set(files
    .filter((f) => !hooks.includes(f) && /^src\/(screens|app|features)\//.test(f)
      && hookModules.some((m) => importsModule(src[f], m)))
    .map((f) => f.replace(/^(src\/(?:screens|features)\/[^/]+)\/.*$/, '$1')))];
  const functions = exportsOf(code).map((name) => ({ name, kind: MUTATION.test(name) ? 'mutation' : 'query' }));
  return {
    domain,
    service: file,
    source,
    functions,
    mutableState: /^\s*let\s+\w+/m.test(code),
    mocks: [...new Set(mockImports)],
    hooks,
    hookNames,
    usedBy,
  };
});

const envReads = files.filter((f) => /process\.env\.\w+/.test(src[f]) && !/lib\/env\.(ts|js)$/.test(f));
// Only the committed templates; never .env itself.
const envTemplate = ['.env.example', '.env.sample', '.env.template'].find(exists) ?? null;
const templateVars = envTemplate
  ? read(envTemplate).split('\n').map((l) => l.match(/^\s*([A-Z0-9_]+)\s*=/)).filter(Boolean).map((m) => m[1]) : [];
const varsInCode = [...new Set(files.flatMap((f) => [...src[f].matchAll(/process\.env\.([A-Z0-9_]+)/g)].map((m) => m[1])))];
// git answers from .gitignore; .env is not opened.
let envIgnored = null;
try {
  require('child_process').execFileSync('git', ['check-ignore', '-q', '.env'], { cwd: dir, stdio: 'ignore' });
  envIgnored = true;
} catch (e) { envIgnored = e.status === 1 ? false : null; } // 1 = not ignored; other = not a git repo
const clientFile = files.find((f) => /lib\/(api-client|http|api)\.(ts|js)$/.test(f))
  || files.find((f) => /from\s+['"](openapi-fetch|axios|ky)['"]/.test(src[f])) || null;

const result = {
  dir,
  framework,
  packageManager: pm,
  layout,
  structure: starter?.structure ?? null,
  queryLibrary,
  installed: {
    'openapi-fetch': deps['openapi-fetch'] ?? null,
    'openapi-typescript': deps['openapi-typescript'] ?? null,
    axios: deps.axios ?? null,
    'react-native-config': deps['react-native-config'] ?? null,
  },
  env: {
    envFile: files.find((f) => /lib\/env\.(ts|js)$/.test(f)) ?? null,
    template: envTemplate,
    templateVars,
    varsInCode,
    envIgnoredByGit: envIgnored,
    readsOutsideEnvFile: envReads,
  },
  apiClient: clientFile,
  apiTypes: exists('src/types/api.gen.ts') ? 'src/types/api.gen.ts' : null,
  openapiSpec: exists('docs/api/openapi.json') ? 'docs/api/openapi.json' : null,
  plan: exists('docs/api-plan.md') ? 'docs/api-plan.md' : null,
  domains,
  summary: Object.fromEntries(['mock', 'connected', 'api', 'mixed', 'unknown']
    .map((s) => [s, domains.filter((d) => d.source === s).map((d) => d.domain)])),
};
console.log(JSON.stringify(result, null, 2));
process.exitCode = layout === 'none' || domains.length === 0 ? 3 : 0;
EOF
