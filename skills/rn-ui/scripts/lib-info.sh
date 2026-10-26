#!/usr/bin/env bash
# Facts about candidate libraries before suggesting them — checked live, because library
# support changes faster than any list in this skill.
#
# Usage: lib-info.sh <project-dir> <package> [package ...]
#
# Per package it prints:
#   npm        latest version on npm
#   expoSdk    version pinned by the project's Expo SDK (what `npx expo install` picks), or "not bundled"
#              — a bundled native module is available in Expo Go; an unbundled *native* module needs a dev build
#   newArch    React Native Directory's New Architecture status (true / new-arch-only / unknown)
#   expoGo     React Native Directory's Expo Go flag
#   maintained false when React Native Directory marks it unmaintained
#   pushed     last push to the library's GitHub repo
#
# Needs node ≥ 18 (fetch) and network access. Read-only.

set -euo pipefail
dir="$(cd "${1:?project dir required}" && pwd)"; shift
[ $# -gt 0 ] || { echo "usage: lib-info.sh <project-dir> <package> [package ...]" >&2; exit 64; }

node - "$dir" "$@" <<'EOF'
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const [dir, ...pkgs] = process.argv.slice(2);
const pkgJson = JSON.parse(fs.readFileSync(path.join(dir, 'package.json'), 'utf8'));
const expoRange = (pkgJson.dependencies || {}).expo;

function bundledModules() {
  if (!expoRange) return null;
  try {
    return require(require.resolve('expo/bundledNativeModules.json', { paths: [dir] }));
  } catch {}
  // node_modules not installed yet: read the list from the matching expo package on npm.
  try {
    const tarball = execFileSync('npm', ['view', `expo@${expoRange}`, 'dist.tarball'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] })
      .trim().split('\n').pop().replace(/^.*'(.+)'.*$/, '$1');
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'expo-bundled-'));
    execFileSync('sh', ['-c', `curl -fsSL "${tarball}" | tar -xz -C "${tmp}" package/bundledNativeModules.json`]);
    return JSON.parse(fs.readFileSync(path.join(tmp, 'package/bundledNativeModules.json'), 'utf8'));
  } catch {
    return null;
  }
}

async function directory(pkg) {
  try {
    const res = await fetch(`https://reactnative.directory/api/libraries?search=${encodeURIComponent(pkg)}`);
    const { libraries = [] } = await res.json();
    return libraries.find((l) => l.npmPkg === pkg) || null;
  } catch {
    return null;
  }
}

function npmLatest(pkg) {
  try {
    return execFileSync('npm', ['view', pkg, 'version'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch {
    return 'not on npm';
  }
}

(async () => {
  const bundled = bundledModules();
  console.log(`project: ${pkgJson.name} (${expoRange ? `Expo ${expoRange}` : 'React Native CLI'})`);
  for (const pkg of pkgs) {
    const lib = await directory(pkg);
    const row = {
      npm: npmLatest(pkg),
      expoSdk: !expoRange ? 'n/a (CLI)' : bundled ? bundled[pkg] || 'not bundled' : 'unknown',
      newArch: lib ? String(lib.newArchitecture ?? 'unknown') : 'not in directory',
      expoGo: lib ? String(lib.expoGo ?? 'unknown') : '-',
      maintained: lib ? String(!lib.unmaintained) : '-',
      pushed: lib?.github?.stats?.pushedAt?.slice(0, 10) || '-',
    };
    console.log(`${pkg}\n  ${Object.entries(row).map(([k, v]) => `${k}: ${v}`).join(' | ')}`);
  }
})();
EOF
