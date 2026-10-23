#!/usr/bin/env bash
# Describe what a React Native / Expo project already has for release builds. Read-only. Prints JSON.
#
# Usage: release-inventory.sh [project-dir]   (default: current directory)
#
# Reports: framework and package manager; the resolved app config (Expo: `expo config` with .env
# loading OFF, so the developer's .env is never read) — name, slug, owner, version, bundle id,
# package, build numbers, EAS project id, updates/runtime version, encryption flag, icon/splash;
# for RN CLI the native ids from android/ and ios/; eas.json profiles; Fastlane; the release
# features the app uses (from its dependencies and config plugins); credential files that git
# tracks or doesn't ignore; signs that the app was already released (releaseSigns — empty for a new
# project); and whether docs/release-plan.md exists.
#
# Never opens .env files or credential files.
#
# Exit codes: 0 done · 1 error · 3 done, but credential files are tracked by git or not ignored
#             (decision needed before anything else)

set -euo pipefail
dir="$(cd "${1:-.}" && pwd)"
[ -f "$dir/package.json" ] || { echo "{\"error\":\"no package.json in $dir\"}"; exit 1; }
command -v node >/dev/null 2>&1 || { echo '{"error":"node not found — source rn-starter/scripts/env.sh first"}'; exit 1; }

# Resolved Expo config, if this is an Expo project. EXPO_NO_DOTENV=1: app.config.js may read
# process.env, but the developer's .env stays unloaded.
expo_config=""
if node -e "const p=require('$dir/package.json');process.exit({...p.dependencies,...p.devDependencies}.expo?0:1)" 2>/dev/null; then
  expo_config="$(cd "$dir" && EXPO_NO_DOTENV=1 npx expo config --json --type public 2>/dev/null || true)"
fi

EXPO_CONFIG="$expo_config" node - "$dir" <<'EOF'
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const dir = process.argv[2];
const exists = (p) => fs.existsSync(path.join(dir, p));
const read = (p) => fs.readFileSync(path.join(dir, p), 'utf8');
const pkg = JSON.parse(read('package.json'));
const deps = { ...pkg.dependencies, ...pkg.devDependencies };
const has = (n) => Object.prototype.hasOwnProperty.call(deps, n);
const git = (...args) => {
  try { return execFileSync('git', args, { cwd: dir, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }); }
  catch (e) { return e.status === 1 ? '' : null; }
};

const framework = has('expo') ? 'expo' : 'react-native-cli';
const pm = exists('pnpm-lock.yaml') ? 'pnpm' : exists('yarn.lock') ? 'yarn'
  : (exists('bun.lockb') || exists('bun.lock')) ? 'bun' : 'npm';

let config = null;
try { config = process.env.EXPO_CONFIG ? JSON.parse(process.env.EXPO_CONFIG) : null; } catch {}
const dynamicConfig = ['app.config.js', 'app.config.ts', 'app.config.mjs', 'app.config.cjs'].find(exists) ?? null;

// RN CLI (or prebuilt Expo): native identifiers from the projects themselves.
const native = { android: null, ios: null };
for (const f of ['android/app/build.gradle', 'android/app/build.gradle.kts']) {
  if (!exists(f)) continue;
  const g = read(f);
  native.android = {
    file: f,
    applicationId: g.match(/applicationId\s*[= ]\s*["']([^"']+)["']/)?.[1] ?? null,
    versionCode: g.match(/versionCode\s*[= ]\s*(\d+)/)?.[1] ?? null,
    versionName: g.match(/versionName\s*[= ]\s*["']([^"']+)["']/)?.[1] ?? null,
  };
}
if (exists('ios')) {
  const proj = fs.readdirSync(path.join(dir, 'ios')).find((d) => d.endsWith('.xcodeproj'));
  if (proj && exists(`ios/${proj}/project.pbxproj`)) {
    const x = read(`ios/${proj}/project.pbxproj`);
    native.ios = {
      project: `ios/${proj}`,
      bundleIds: [...new Set([...x.matchAll(/PRODUCT_BUNDLE_IDENTIFIER = "?([^";]+)"?;/g)].map((m) => m[1]))],
      marketingVersion: x.match(/MARKETING_VERSION = ([^;]+);/)?.[1] ?? null,
      buildNumber: x.match(/CURRENT_PROJECT_VERSION = ([^;]+);/)?.[1] ?? null,
    };
  }
}

let eas = null;
if (exists('eas.json')) {
  try {
    const e = JSON.parse(read('eas.json'));
    eas = {
      appVersionSource: e.cli?.appVersionSource ?? null,
      cliVersion: e.cli?.version ?? null,
      build: Object.fromEntries(Object.entries(e.build ?? {}).map(([n, p]) => [n, {
        extends: p.extends, distribution: p.distribution, channel: p.channel, environment: p.environment,
        autoIncrement: p.autoIncrement, credentialsSource: p.credentialsSource,
        iosSimulator: p.ios?.simulator, androidBuildType: p.android?.buildType, developmentClient: p.developmentClient,
      }])),
      submit: Object.keys(e.submit ?? {}),
    };
  } catch (err) { eas = { error: `eas.json is not valid JSON: ${err.message}` }; }
}

// Features with store-time setup. Push is set up by this skill (push.md); the others are listed in
// the hand-off as work outside it (they need the keystore fingerprints).
const plugins = (config?.plugins ?? []).map((p) => (Array.isArray(p) ? p[0] : p));
const usesPlugin = (n) => plugins.includes(n);
const any = (...names) => names.some(has);
const features = {
  push: any('expo-notifications', '@react-native-firebase/messaging', 'react-native-onesignal', 'onesignal-expo-plugin'),
  signInWithApple: any('expo-apple-authentication', '@invertase/react-native-apple-authentication') || !!config?.ios?.usesAppleSignIn,
  googleSignIn: any('@react-native-google-signin/google-signin') || (has('expo-auth-session') && /google/i.test(JSON.stringify(deps))),
  domainLinks: !!(config?.ios?.associatedDomains?.length || config?.android?.intentFilters?.some?.((f) => f.autoVerify)),
  maps: any('react-native-maps', '@rnmapbox/maps'),
  firebase: Object.keys(deps).some((d) => d.startsWith('@react-native-firebase/')) || !!config?.ios?.googleServicesFile || !!config?.android?.googleServicesFile,
  sentry: any('@sentry/react-native', 'sentry-expo'),
  permissions: Object.keys(deps).filter((d) => /^(expo-(camera|location|image-picker|media-library|contacts|calendar|av|audio|video|sensors|tracking-transparency|local-authentication)|react-native-(permissions|vision-camera|image-picker))$/.test(d)),
};

// Credential files: anything that looks like one, and whether git tracks it or would ignore it.
const SECRET = /\.(p8|p12|pfx|jks|keystore|mobileprovision|cer)$|^credentials\.json$|^service[-_]?account.*\.json$|^AuthKey_.*\.p8$/i;
const walk = (p, depth = 0, out = []) => {
  if (depth > 3 || !exists(p)) return out;
  for (const e of fs.readdirSync(path.join(dir, p))) {
    if (['node_modules', '.git', 'Pods', 'build', '.expo', '.gradle'].includes(e)) continue;
    const rel = p ? `${p}/${e}` : e;
    const st = fs.statSync(path.join(dir, rel));
    if (st.isDirectory()) walk(rel, depth + 1, out);
    else if (SECRET.test(e)) out.push(rel);
  }
  return out;
};
const candidates = walk('');
const tracked = git('ls-files', '-z')?.split('\0').filter((f) => SECRET.test(path.basename(f))) ?? null;
// git check-ignore: exit 0 = ignored, 1 = not ignored, other = not a git repo.
const ignoreStatus = (...args) => {
  try { execFileSync('git', ['check-ignore', '-q', ...args], { cwd: dir, stdio: 'ignore' }); return 0; }
  catch (e) { return e.status; }
};
const notIgnored = candidates.filter((f) => ignoreStatus(f) === 1);
const ignoreRulesMissing = ['x.p8', 'x.p12', 'x.jks', 'x.keystore', 'x.mobileprovision', 'credentials.json']
  .filter((f) => ignoreStatus('--no-index', f) === 1);

// Signs that the app was already released somewhere: a reason to ask before letting EAS generate
// an Android keystore. A new project shows none of them.
const easJsonRaw = exists('eas.json') ? read('eas.json') : '';
const releaseSigns = [];
if (/"ascAppId"\s*:/.test(easJsonRaw)) releaseSigns.push('eas.json has an App Store Connect app id (ascAppId)');
if (/"serviceAccountKeyPath"|"track"\s*:/.test(easJsonRaw)) releaseSigns.push('eas.json has Google Play submit settings');
const ver = config?.version ?? native.android?.versionName ?? null;
// 0.x and 1 / 1.0 / 1.0.0 are what a project starts with.
if (ver && !/^(0(\.\d+)*|1(\.0)*)$/.test(String(ver))) releaseSigns.push(`version is ${ver}, not a first release`);
const vc = Number(config?.android?.versionCode ?? native.android?.versionCode ?? 0);
if (vc > 1) releaseSigns.push(`Android versionCode is ${vc}`);
const bn = Number(config?.ios?.buildNumber ?? native.ios?.buildNumber ?? 0);
if (bn > 1) releaseSigns.push(`iOS build number is ${bn}`);
if (config?.extra?.eas?.projectId) releaseSigns.push('already linked to an EAS project');
if (exists('fastlane') || exists('android/fastlane') || exists('ios/fastlane')) releaseSigns.push('has a Fastlane setup');

const c = config ?? {};
const result = {
  dir,
  framework,
  packageManager: pm,
  nativeFolders: { ios: exists('ios'), android: exists('android') },
  fastlane: exists('fastlane') || exists('ios/fastlane') || exists('android/fastlane'),
  appConfig: config ? {
    source: dynamicConfig ?? 'app.json',
    name: c.name, slug: c.slug, owner: c.owner ?? null, version: c.version,
    iosBundleIdentifier: c.ios?.bundleIdentifier ?? null, iosBuildNumber: c.ios?.buildNumber ?? null,
    androidPackage: c.android?.package ?? null, androidVersionCode: c.android?.versionCode ?? null,
    easProjectId: c.extra?.eas?.projectId ?? null,
    updatesUrl: c.updates?.url ?? null, runtimeVersion: c.runtimeVersion ?? null,
    nonExemptEncryption: c.ios?.infoPlist?.ITSAppUsesNonExemptEncryption ?? c.ios?.config?.usesNonExemptEncryption ?? null,
    icon: c.icon ?? c.ios?.icon ?? null, splash: c.splash ?? (usesPlugin('expo-splash-screen') ? 'expo-splash-screen plugin' : null),
    plugins,
  } : null,
  dynamicConfig,
  native,
  eas,
  installed: {
    'expo-updates': deps['expo-updates'] ?? null,
    'expo-dev-client': deps['expo-dev-client'] ?? null,
    'eas-cli (devDependency)': deps['eas-cli'] ?? null,
  },
  features,
  credentialFiles: { found: candidates, trackedByGit: tracked, notIgnored, ignoreRulesMissing },
  releaseSigns,
  releasePlan: exists('docs/release-plan.md') ? 'docs/release-plan.md' : null,
};
console.log(JSON.stringify(result, null, 2));
process.exitCode = (tracked?.length || notIgnored.length) ? 3 : 0;
EOF
