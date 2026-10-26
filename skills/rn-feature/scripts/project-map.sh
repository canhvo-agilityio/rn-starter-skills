#!/usr/bin/env bash
# Map a React Native / Expo project for ticket analysis: what screens, routes, components and data
# domains it has, and which design / API / ticket docs already exist. Read-only. Prints JSON.
#
# Usage: project-map.sh [project-dir]   (default: current directory)
#
# Builds on rn-ui's detect-project.sh (stack, navigation, structure) and rn-api-connect's
# api-inventory.sh (data domains and whether each is still on mocks), then adds:
#   routes      each route file with its URL path and the screen it re-exports
#   screens     src/screens/<name>/ folders with their routes and own components
#   components  shared components in src/components/
#   auth        signs of sign-in: an (auth) route group, a guard, token storage, a token getter
#   docs        design-spec.md, api-plan.md, api/openapi.json, and every docs/tickets/*.md with its
#               ticket, status and the files its Scope says it touches
# structure is the layout the code has now; recordedStructure is what .rn-starter.json recorded.
# Never opens .env files.
#
# Exit codes: 0 done · 1 error (no package.json / not an RN project)

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dir="$(cd "${1:-.}" && pwd)"
[ -f "$dir/package.json" ] || { echo "{\"error\":\"no package.json in $dir\"}"; exit 1; }
command -v node >/dev/null 2>&1 || { echo '{"error":"node not found — source rn-starter/scripts/env.sh first"}'; exit 1; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
bash "$here/../../rn-ui/scripts/detect-project.sh" "$dir" > "$tmp/detect.json" 2>/dev/null || true
bash "$here/../../rn-api-connect/scripts/api-inventory.sh" "$dir" > "$tmp/api.json" 2>/dev/null || true   # exit 3 = no service seam, still useful

node - "$dir" "$tmp/detect.json" "$tmp/api.json" <<'EOF'
const fs = require('fs');
const path = require('path');
const [dir, detectFile, apiFile] = process.argv.slice(2);
const readJson = (f) => { try { return JSON.parse(fs.readFileSync(f, 'utf8')); } catch { return null; } };
const rel = (p) => path.relative(dir, p).split(path.sep).join('/');
const exists = (p) => fs.existsSync(path.join(dir, p));

const detect = readJson(detectFile);
const pkg = readJson(path.join(dir, 'package.json')) || {};
const deps = { ...pkg.dependencies, ...pkg.devDependencies };
if (!deps['react-native'] && !deps.expo) {
  console.log(JSON.stringify({ error: 'not a React Native / Expo project (no react-native or expo dependency)' }));
  process.exit(1);
}
const api = readJson(apiFile) || {};

const walk = (d, out = []) => {
  if (!fs.existsSync(d)) return out;
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    if (e.name === 'node_modules' || e.name.startsWith('.')) continue;
    const p = path.join(d, e.name);
    if (e.isDirectory()) walk(p, out); else out.push(p);
  }
  return out;
};

// expo-router: file path → URL path. Groups "(tabs)" vanish, index is "/", _layout and +html aren't routes.
const routesDir = detect?.routesDir ? path.join(dir, detect.routesDir) : null;
const routes = [];
if (routesDir && fs.existsSync(routesDir) && detect.navigation === 'expo-router') {
  for (const f of walk(routesDir).filter((f) => /\.(t|j)sx?$/.test(f))) {
    const r = path.relative(routesDir, f).split(path.sep).join('/');
    const base = path.basename(r).replace(/\.(web|ios|android|native)?\.?(t|j)sx?$/, '');
    if (base.startsWith('_') || base.startsWith('+')) continue;
    const urlPath = '/' + r.replace(/\.(web|ios|android|native)?\.?(t|j)sx?$/, '').split('/')
      .filter((s) => !/^\(.*\)$/.test(s)).map((s) => (s === 'index' ? '' : s.replace(/^\[\.\.\.(.+)\]$/, '*$1').replace(/^\[(.+)\]$/, ':$1')))
      .filter(Boolean).join('/');
    const src = fs.readFileSync(f, 'utf8');
    const m = src.match(/from\s+['"]@\/screens\/([^'"/]+)/) || src.match(/from\s+['"](?:\.\.\/)+screens\/([^'"/]+)/);
    routes.push({ file: rel(f), path: urlPath, screen: m ? m[1] : null, thin: src.split('\n').filter((l) => l.trim()).length <= 3 });
  }
  routes.sort((a, b) => a.path.localeCompare(b.path));
}

const srcRoot = path.join(dir, detect?.srcRoot || 'src');
const dirs = (d) => (fs.existsSync(d) ? fs.readdirSync(d, { withFileTypes: true }).filter((e) => e.isDirectory()).map((e) => e.name) : []);
const screensDir = path.join(srcRoot, 'screens');
const screens = dirs(screensDir).map((name) => ({
  name, dir: rel(path.join(screensDir, name)),
  routes: routes.filter((r) => r.screen === name).map((r) => r.path),
  components: dirs(path.join(screensDir, name, 'components')).concat(
    walk(path.join(screensDir, name, 'components')).filter((f) => /\.tsx$/.test(f)).map((f) => path.basename(f, '.tsx'))),
}));
const componentsDir = path.join(srcRoot, 'components');
const components = fs.existsSync(componentsDir)
  ? fs.readdirSync(componentsDir, { withFileTypes: true })
    .filter((e) => !['__tests__', 'icons', 'ui'].includes(e.name) && (e.isDirectory() || /\.tsx$/.test(e.name)) && !/\.(web|ios|android)\.tsx$/.test(e.name))
    .map((e) => e.name.replace(/\.tsx$/, ''))
  : [];

// Signs of sign-in, so endpoints that need a token can be judged against what the app has.
const srcFiles = walk(srcRoot).filter((f) => /\.(t|j)sx?$/.test(f));
const grepSrc = (re) => srcFiles.filter((f) => re.test(fs.readFileSync(f, 'utf8'))).map(rel);
const auth = {
  routeGroup: routes.filter((r) => /\/\(auth\)\//.test(r.file)).map((r) => r.file),
  guard: grepSrc(/Stack\.Protected|Tabs\.Protected|<Redirect\b|isSignedIn|useSession\(/),
  tokenStorage: ['expo-secure-store', 'react-native-keychain', '@react-native-async-storage/async-storage'].filter((d) => deps[d]),
  tokenGetter: grepSrc(/setAuthTokenGetter\(|['"]?Authorization['"]?\s*[:,]/),
};

// Ticket files: frontmatter fields, and the "Files likely touched" line of Scope for overlap checks.
const ticketsDir = path.join(dir, 'docs', 'tickets');
const tickets = fs.existsSync(ticketsDir) ? fs.readdirSync(ticketsDir).filter((f) => f.endsWith('.md')).map((f) => {
  const text = fs.readFileSync(path.join(ticketsDir, f), 'utf8');
  const fm = {};
  const m = text.match(/^---\n([\s\S]*?)\n---/);
  if (m) for (const line of m[1].split('\n')) {
    const kv = line.match(/^(\w+):\s*(.*?)\s*(#.*)?$/);
    if (kv) fm[kv[1]] = kv[2];
  }
  const touched = (text.match(/^-\s*Files likely touched:\s*(.+)$/m) || [, ''])[1];
  return {
    file: rel(path.join(ticketsDir, f)), ticket: fm.ticket || f.replace(/\.md$/, ''), type: fm.type || null, status: fm.status || null,
    filesTouched: [...touched.matchAll(/`([^`]+)`/g)].map((x) => x[1]),
  };
}) : [];

console.log(JSON.stringify({
  dir,
  framework: detect?.framework ?? (deps.expo ? 'expo' : 'react-native-cli'),
  navigation: detect?.navigation ?? null,
  structure: detect?.structure ?? null,
  recordedStructure: detect?.rnStarter?.structure ?? null,
  styling: detect?.styling ?? null,
  uiLibrary: detect?.uiLibrary ?? null,
  runTargets: detect?.rnStarter?.runTargets ?? null,
  routes,
  screens,
  components,
  data: {
    queryLibrary: api.queryLibrary ?? null,
    apiClient: api.apiClient ?? null,
    domains: (api.domains || []).map((d) => ({
      name: d.domain, service: d.service, source: d.source,
      functions: (d.functions || []).map((fn) => `${fn.name} (${fn.kind})`),
      hooks: d.hookNames || [], usedBy: d.usedBy || [],
    })),
  },
  auth,
  docs: {
    designSpec: exists('docs/design-spec.md') ? 'docs/design-spec.md' : null,
    apiPlan: exists('docs/api-plan.md') ? 'docs/api-plan.md' : null,
    openapi: exists('docs/api/openapi.json') ? 'docs/api/openapi.json' : null,
    tickets,
  },
}, null, 2));
EOF
