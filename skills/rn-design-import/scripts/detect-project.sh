#!/usr/bin/env bash
# Describe an existing React Native / Expo project so generated code matches its conventions.
# Read-only. Prints JSON to stdout.
#
# Usage: detect-project.sh [project-dir]   (default: current directory)
#
# Prefers .rn-starter.json (written by the rn-starter skill); otherwise infers from package.json
# and the file tree.

set -euo pipefail
dir="$(cd "${1:-.}" && pwd)"
[ -f "$dir/package.json" ] || { echo "{\"error\":\"no package.json in $dir\"}"; exit 1; }
command -v node >/dev/null 2>&1 || { echo '{"error":"node not found — source rn-starter/scripts/env.sh first"}'; exit 1; }

node - "$dir" <<'EOF'
const fs = require('fs');
const path = require('path');
const dir = process.argv[2];
const exists = (p) => fs.existsSync(path.join(dir, p));
const pkg = JSON.parse(fs.readFileSync(path.join(dir, 'package.json'), 'utf8'));
const deps = { ...pkg.dependencies, ...pkg.devDependencies };
const has = (name) => Object.prototype.hasOwnProperty.call(deps, name);

let starter = null;
if (exists('.rn-starter.json')) {
  try { starter = JSON.parse(fs.readFileSync(path.join(dir, '.rn-starter.json'), 'utf8')); } catch {}
}

const framework = has('expo') ? 'expo' : 'react-native-cli';
const navigation = has('expo-router') ? 'expo-router'
  : has('@react-navigation/native') ? 'react-navigation' : 'none';
const styling = has('nativewind') ? 'nativewind'
  : has('react-native-unistyles') ? 'unistyles'
  : has('tamagui') ? 'tamagui' : 'stylesheet';
const state = has('zustand') ? 'zustand' : has('@reduxjs/toolkit') ? 'redux-toolkit' : has('jotai') ? 'jotai' : 'none';
const pm = exists('pnpm-lock.yaml') ? 'pnpm' : exists('yarn.lock') ? 'yarn'
  : (exists('bun.lockb') || exists('bun.lock')) ? 'bun' : 'npm';

const srcRoot = exists('src') ? 'src' : '.';
const routesDir = navigation === 'expo-router'
  ? (exists('src/app') ? 'src/app' : exists('app') ? 'app' : null) : null;

const listDir = (p) => exists(p) ? fs.readdirSync(path.join(dir, p)) : [];
const walk = (p, out = []) => {
  for (const e of listDir(p)) {
    const rel = path.join(p, e);
    if (fs.statSync(path.join(dir, rel)).isDirectory()) walk(rel, out); else out.push(rel);
  }
  return out;
};
const themeCandidates = ['src/theme', 'theme', 'src/constants', 'constants']
  .filter(exists).flatMap((p) => walk(p)).filter((f) => /\.(ts|tsx|js)$/.test(f));
const routes = routesDir ? walk(routesDir).filter((f) => /\.(tsx|ts|jsx|js)$/.test(f)) : [];
const fonts = [...listDir('assets/fonts')].filter((f) => /\.(ttf|otf)$/i.test(f));
const googleFonts = Object.keys(deps).filter((d) => d.startsWith('@expo-google-fonts/'));

const icons = ['@expo/vector-icons', 'expo-symbols', 'lucide-react-native', 'react-native-vector-icons', 'react-native-svg']
  .filter(has);
const nativeTabs = walk(srcRoot === '.' ? (routesDir || 'app') : 'src')
  .filter((f) => /\.(tsx|ts)$/.test(f))
  .some((f) => /unstable-native-tabs|NativeTabs/.test(fs.readFileSync(path.join(dir, f), 'utf8')));

// Choices recorded by rn-starter that aren't actually installed — install them (they were chosen)
// or ask, but don't silently ignore either side.
const mismatches = [];
if (starter) {
  const detected = { navigation, styling, state };
  for (const key of Object.keys(detected)) {
    if (starter[key] && starter[key] !== 'none' && starter[key] !== detected[key]) {
      mismatches.push(`${key}: .rn-starter.json says "${starter[key]}", package.json has "${detected[key]}"`);
    }
  }
}

// Feature-first layout (rn-starter structure.md): src/features/<name>/index.ts as public API.
const featureNames = listDir('src/features').filter((n) => fs.statSync(path.join(dir, 'src/features', n)).isDirectory());
const features = featureNames.map((name) => ({
  name,
  hasIndex: ['index.ts', 'index.tsx'].some((f) => exists(`src/features/${name}/${f}`)),
  hasScreens: exists(`src/features/${name}/screens`),
}));
const structure = !featureNames.length ? 'flat'
  : features.every((f) => f.hasIndex) ? 'feature-first' : 'partial-features';
const eslintConfig = ['eslint.config.js', 'eslint.config.mjs', 'eslint.config.cjs'].find(exists);
const boundaryRules = !!eslintConfig && fs.readFileSync(path.join(dir, eslintConfig), 'utf8').includes('@/features/*/*');

let tsAlias = null;
try {
  const ts = fs.readFileSync(path.join(dir, 'tsconfig.json'), 'utf8');
  const m = ts.match(/"(@\/?\*?)"\s*:\s*\[\s*"([^"]+)"/);
  if (m) tsAlias = { alias: m[1], target: m[2] };
} catch {}

console.log(JSON.stringify({
  dir,
  source: starter ? '.rn-starter.json + package.json' : 'package.json',
  rnStarter: starter,
  framework,
  expoSdk: has('expo') ? deps.expo : null,
  reactNative: deps['react-native'] || null,
  typescript: exists('tsconfig.json'),
  packageManager: pm,
  navigation,
  styling,
  state,
  srcRoot,
  routesDir,
  routes,
  pathAlias: tsAlias,
  structure,
  features,
  boundaryRules,
  themeFiles: themeCandidates,
  fonts: { files: fonts, expoGoogleFonts: googleFonts, expoFont: has('expo-font') },
  icons,
  nativeTabs,
  mismatches,
  designSpec: exists('docs/design-spec.md') ? 'docs/design-spec.md' : null,
}, null, 2));
EOF
