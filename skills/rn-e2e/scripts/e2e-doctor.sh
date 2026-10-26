#!/usr/bin/env bash
# Check what end-to-end flows need, on the machine and in the project. Read-only. Prints JSON.
#
# Usage: e2e-doctor.sh [project-dir]   (default: current directory)
#
# Reports: Maestro (path, version), Java (17+ needed), booted iOS simulators and Android devices,
# how the app opens (Expo Go, or a build: bundle id, package, scheme), the .maestro/ folder (config,
# subflows, flows with their tags), and how many testID props the code has.
#
# Exit codes: 0 ready · 1 error · 2 Maestro or Java 17+ missing (install-maestro.sh, with the dev's yes)

set -euo pipefail
dir="$(cd "${1:-.}" && pwd)"
[ -f "$dir/package.json" ] || { echo "{\"error\":\"no package.json in $dir\"}"; exit 1; }
command -v node >/dev/null 2>&1 || { echo '{"error":"node not found — source rn-starter/scripts/env.sh first"}'; exit 1; }

maestro="$(command -v maestro 2>/dev/null || true)"
[ -z "$maestro" ] && [ -x "$HOME/.maestro/bin/maestro" ] && maestro="$HOME/.maestro/bin/maestro"
maestro_version=""; [ -n "$maestro" ] && maestro_version="$("$maestro" --version 2>/dev/null | tail -n1 || true)"

java_bin=""
if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then java_bin="$JAVA_HOME/bin/java"; else java_bin="$(command -v java 2>/dev/null || true)"; fi
java_version=""; [ -n "$java_bin" ] && java_version="$("$java_bin" -version 2>&1 | head -n1 | sed -E 's/.*version "([^"]+)".*/\1/' || true)"

ios_booted=""
command -v xcrun >/dev/null 2>&1 && ios_booted="$(xcrun simctl list devices booted 2>/dev/null | sed -nE 's/^ +(.+) \(([0-9A-F-]{36})\) \(Booted\).*/\1|\2/p' || true)"
android=""
command -v adb >/dev/null 2>&1 && android="$(adb devices 2>/dev/null | awk 'NR>1 && $2=="device" {print $1}' || true)"

node - "$dir" "$maestro" "$maestro_version" "$java_version" "$ios_booted" "$android" <<'EOF'
const fs = require('fs');
const path = require('path');
const [dir, maestro, maestroVersion, javaVersion, iosRaw, androidRaw] = process.argv.slice(2);
const read = (p) => { try { return fs.readFileSync(path.join(dir, p), 'utf8'); } catch { return null; } };
const json = (p) => { try { return JSON.parse(read(p)); } catch { return null; } };

const pkg = json('package.json') || {};
const deps = { ...pkg.dependencies, ...pkg.devDependencies };
const starter = json('.rn-starter.json') || {};
const app = json('app.json')?.expo || {};
const isExpo = !!deps.expo;

// Native ids for builds: app.json first, then the native projects.
let bundleId = app.ios?.bundleIdentifier || null;
let androidPackage = app.android?.package || null;
let scheme = Array.isArray(app.scheme) ? app.scheme[0] : app.scheme || null;
const gradle = read('android/app/build.gradle') || '';
androidPackage ||= (gradle.match(/applicationId\s+["']([^"']+)/) || [])[1] || null;
if (!bundleId && fs.existsSync(path.join(dir, 'ios'))) {
  for (const f of fs.readdirSync(path.join(dir, 'ios')).filter((f) => f.endsWith('.xcodeproj'))) {
    const pbx = read(`ios/${f}/project.pbxproj`) || '';
    bundleId = (pbx.match(/PRODUCT_BUNDLE_IDENTIFIER = "?([^";]+)"?;/) || [])[1] || null;
    if (bundleId) break;
  }
}
const devBuild = !isExpo || starter.devBuild === true || !!deps['expo-dev-client'];
const opensIn = isExpo && !devBuild ? 'expo-go' : 'build';

// .maestro/
const flowsDir = path.join(dir, '.maestro');
const walk = (d, out = []) => {
  if (!fs.existsSync(d)) return out;
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) walk(p, out); else if (/\.ya?ml$/.test(e.name)) out.push(p);
  }
  return out;
};
const flows = walk(flowsDir).filter((f) => !/config\.ya?ml$/.test(f)).map((f) => {
  const text = fs.readFileSync(f, 'utf8');
  const header = text.split(/^---$/m)[0];
  const tags = [];
  const block = header.match(/^tags:\s*\n((?:\s+-\s*.+\n?)+)/m);
  if (block) for (const m of block[1].matchAll(/-\s*(.+)/g)) tags.push(m[1].trim().replace(/^["']|["']$/g, ''));
  const inline = header.match(/^tags:\s*\[(.*)\]/m);
  if (inline) tags.push(...inline[1].split(',').map((t) => t.trim().replace(/^["']|["']$/g, '')).filter(Boolean));
  return {
    file: path.relative(dir, f).split(path.sep).join('/'),
    name: (header.match(/^name:\s*["']?(.+?)["']?\s*$/m) || [])[1] || null,
    tags,
  };
});

// testIDs in the code
const src = path.join(dir, fs.existsSync(path.join(dir, 'src')) ? 'src' : '.');
let testIds = 0;
const scan = (d) => {
  if (!fs.existsSync(d)) return;
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    if (['node_modules', 'ios', 'android', '.expo', '__tests__'].includes(e.name) || e.name.startsWith('.')) continue;
    const p = path.join(d, e.name);
    if (e.isDirectory()) scan(p);
    else if (/\.(t|j)sx$/.test(e.name)) testIds += (fs.readFileSync(p, 'utf8').match(/\btestID=/g) || []).length;
  }
};
scan(src);

const javaMajor = Number((javaVersion.match(/^(1\.)?(\d+)/) || [])[2] || 0);
const result = {
  maestro: maestro ? { path: maestro, version: maestroVersion || null } : null,
  java: javaVersion ? { version: javaVersion, ok: javaMajor >= 17 } : null,
  devices: {
    ios: iosRaw.split('\n').filter(Boolean).map((l) => { const [name, udid] = l.split('|'); return { name, udid }; }),
    android: androidRaw.split('\n').filter(Boolean),
  },
  app: {
    framework: isExpo ? 'expo' : 'react-native-cli',
    opensIn,
    expoGo: opensIn === 'expo-go' ? { ios: 'host.exp.Exponent', android: 'host.exp.exponent', url: 'exp://127.0.0.1:8081/--' } : null,
    bundleId, androidPackage, scheme,
    runTargets: starter.runTargets || null,
  },
  maestroDir: {
    exists: fs.existsSync(flowsDir),
    config: fs.existsSync(path.join(flowsDir, 'config.yaml')),
    subflows: flows.filter((f) => f.tags.includes('subflow')).map((f) => f.file),
    flows: flows.filter((f) => !f.tags.includes('subflow')),
  },
  testIds,
  scripts: Object.fromEntries(Object.entries(pkg.scripts || {}).filter(([k]) => /e2e|maestro/i.test(k))),
};
console.log(JSON.stringify(result, null, 2));
if (!maestro || !(javaMajor >= 17)) {
  console.error('ACTION REQUIRED: Maestro' + (!maestro ? ' is not installed' : '') + (!(javaMajor >= 17) ? `${!maestro ? ' and' : ''} needs Java 17+` : '')
    + '. Ask the developer, then run install-maestro.sh.');
  process.exitCode = 2;
}
EOF
