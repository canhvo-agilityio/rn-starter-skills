#!/usr/bin/env bash
# Identify the signing / store files in a folder the developer points to. Read-only.
#
# Usage: scan-credentials.sh <folder> [project-dir] [--bundle-id <id>] [--package <name>]
#
# Each file is classified by name, extension and its first bytes — secrets are never printed:
#   apple-p8          a .p8 private key (App Store Connect API key OR APNs key — the file can't
#                     tell which; the key id comes from the AuthKey_<KEYID>.p8 name)
#   pkcs12            a .p12/.pfx (distribution or APNs certificate; needs its password to tell)
#   provisioning      a .mobileprovision — public, so it is parsed: name, team, bundle id, type
#                     (app-store / ad-hoc / development / enterprise), expiry, push entitlement
#   keystore          a .jks / .keystore (JKS or PKCS#12 format); its alias needs the password
#   google-service-account   a .json with "type": "service_account" (no value printed)
#   google-services   google-services.json — public config; its Android package names are listed
#   googleservice-info       GoogleService-Info.plist — its BUNDLE_ID is listed
#   eas-credentials   an EAS credentials.json (contains passwords — not parsed)
#   unknown
# Problems reported per file: inside the project but not ignored by git, tracked by git, wrong
# header for its extension, a provisioning profile that is expired / expires within 30 days /
# isn't App Store / is for another bundle id, Firebase files for another bundle id or package.
#
# Exit codes: 0 done, no problems · 1 error · 3 done, with problems (decision or fix needed)

set -euo pipefail
[ $# -ge 1 ] || { echo "usage: scan-credentials.sh <folder> [project-dir] [--bundle-id id] [--package name]" >&2; exit 1; }
folder="$(cd "$1" && pwd)"; shift
project=""; bundle=""; package=""
while [ $# -gt 0 ]; do
  case "$1" in
    --bundle-id) bundle="${2:-}"; shift 2 ;;
    --package) package="${2:-}"; shift 2 ;;
    *) project="$(cd "$1" && pwd)"; shift ;;
  esac
done
command -v node >/dev/null 2>&1 || { echo "node not found — source rn-starter/scripts/env.sh first" >&2; exit 1; }

node - "$folder" "$project" "$bundle" "$package" <<'EOF'
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const [folder, project, bundle, pkgName] = process.argv.slice(2);

const head = (file, n) => {
  const fd = fs.openSync(file, 'r');
  const buf = Buffer.alloc(n);
  const len = fs.readSync(fd, buf, 0, n, 0);
  fs.closeSync(fd);
  return buf.subarray(0, len);
};
const git = (cwd, ...args) => {
  try { execFileSync('git', args, { cwd, stdio: 'ignore' }); return 0; }
  catch (e) { return typeof e.status === 'number' ? e.status : -1; }
};
const insideProject = (f) => project && path.relative(project, f) && !path.relative(project, f).startsWith('..');

// Public plist values from a .mobileprovision (a CMS envelope around an XML plist).
const plistValue = (xml, key) => {
  const m = xml.match(new RegExp(`<key>${key}</key>\\s*<(string|date|true|false|integer)\\s*/?>([^<]*)`));
  return m ? (m[1] === 'true' ? true : m[1] === 'false' ? false : m[2]) : undefined;
};
const parseProvisioning = (file) => {
  const text = fs.readFileSync(file).toString('latin1');
  const xml = text.slice(text.indexOf('<?xml'), text.indexOf('</plist>') + 8);
  if (!xml.startsWith('<?xml')) return null;
  const appId = plistValue(xml, 'application-identifier') ?? '';
  const team = (xml.match(/<key>TeamIdentifier<\/key>\s*<array>\s*<string>([^<]+)/) || [])[1] ?? null;
  const devices = /<key>ProvisionedDevices<\/key>/.test(xml);
  const allDevices = plistValue(xml, 'ProvisionsAllDevices') === true;
  const getTaskAllow = plistValue(xml, 'get-task-allow') === true;
  const type = allDevices ? 'enterprise' : devices ? (getTaskAllow ? 'development' : 'ad-hoc') : 'app-store';
  const expires = plistValue(xml, 'ExpirationDate') ?? null;
  return {
    name: plistValue(xml, 'Name') ?? null, team,
    bundleId: appId && team ? appId.replace(`${team}.`, '') : appId || null,
    type, expires, push: /<key>aps-environment<\/key>/.test(xml),
  };
};

const files = fs.readdirSync(folder).filter((f) => !f.startsWith('.')).sort()
  .flatMap((f) => {
    const full = path.join(folder, f);
    if (fs.statSync(full).isDirectory()) return fs.readdirSync(full).filter((g) => !g.startsWith('.')).map((g) => path.join(full, g)).filter((g) => fs.statSync(g).isFile());
    return [full];
  });

const results = [];
for (const full of files) {
  const name = path.basename(full);
  const ext = path.extname(name).toLowerCase();
  const h = head(full, 64);
  const problems = [];
  const r = { file: path.relative(folder, full), kind: 'unknown', details: {}, problems };

  if (ext === '.p8') {
    r.kind = 'apple-p8';
    if (!h.toString('latin1').startsWith('-----BEGIN PRIVATE KEY-----')) problems.push('not a PEM private key (wrong file or corrupted download)');
    const id = name.match(/^AuthKey_([A-Z0-9]{10})\.p8$/i)?.[1];
    r.details.keyId = id ?? null;
    r.details.note = 'App Store Connect API key or APNs key — ask which (both download as AuthKey_<KEYID>.p8)';
  } else if (ext === '.p12' || ext === '.pfx') {
    r.kind = 'pkcs12';
    if (h[0] !== 0x30) problems.push('not a PKCS#12 file');
    r.details.note = 'distribution certificate or APNs certificate — its password (typed by the developer) is needed to use it';
  } else if (ext === '.mobileprovision') {
    r.kind = 'provisioning';
    const p = parseProvisioning(full);
    if (!p) problems.push('not a provisioning profile');
    else {
      r.details = p;
      if (p.type !== 'app-store') problems.push(`${p.type} profile — TestFlight and the App Store need an App Store distribution profile`);
      if (p.expires) {
        const days = Math.floor((new Date(p.expires) - Date.now()) / 86400000);
        r.details.daysLeft = days;
        if (days < 0) problems.push(`expired on ${p.expires.slice(0, 10)}`);
        else if (days < 30) problems.push(`expires in ${days} days`);
      }
      if (bundle && p.bundleId && p.bundleId !== bundle && p.bundleId !== '*') problems.push(`profile is for ${p.bundleId}, the app is ${bundle}`);
    }
  } else if (ext === '.jks' || ext === '.keystore') {
    r.kind = 'keystore';
    r.details.format = h.readUInt32BE(0) === 0xfeedfeed ? 'JKS' : h[0] === 0x30 ? 'PKCS12' : 'unknown';
    if (r.details.format === 'unknown') problems.push('not a JKS or PKCS#12 keystore');
    r.details.note = 'alias and passwords come from the developer; the alias is not secret';
  } else if (ext === '.json') {
    let j = null;
    try { j = JSON.parse(fs.readFileSync(full, 'utf8')); } catch { problems.push('not valid JSON'); }
    if (j && j.type === 'service_account') {
      r.kind = 'google-service-account';
      r.details.note = 'used by eas submit for Google Play, or by EAS for FCM V1 push — ask which';
    } else if (j && j.project_info && Array.isArray(j.client)) {
      r.kind = 'google-services';
      r.details.packages = j.client.map((c) => c.client_info?.android_client_info?.package_name).filter(Boolean);
      if (pkgName && !r.details.packages.includes(pkgName)) problems.push(`no client for ${pkgName} (has: ${r.details.packages.join(', ')})`);
    } else if (j && (j.android || j.ios) && name === 'credentials.json') {
      r.kind = 'eas-credentials';
      r.details.platforms = Object.keys(j).filter((k) => ['android', 'ios'].includes(k));
      r.details.note = 'contains passwords — not read further';
    }
  } else if (name === 'GoogleService-Info.plist') {
    r.kind = 'googleservice-info';
    const xml = fs.readFileSync(full, 'utf8');
    r.details.bundleId = plistValue(xml, 'BUNDLE_ID') ?? null;
    if (bundle && r.details.bundleId && r.details.bundleId !== bundle) problems.push(`for ${r.details.bundleId}, the app is ${bundle}`);
  }

  if (insideProject(full)) {
    const rel = path.relative(project, full);
    if (git(project, 'ls-files', '--error-unmatch', rel) === 0) problems.push('TRACKED BY GIT — remove it from the repo and rotate it if it was pushed');
    else if (git(project, 'check-ignore', '-q', rel) === 1) problems.push('inside the project and not ignored by git');
  }
  results.push(r);
}

const byKind = (k) => results.filter((r) => r.kind === k).map((r) => r.file);
const out = {
  folder,
  insideProject: !!(project && insideProject(path.join(folder, 'x'))),
  files: results,
  summary: {
    'apple-p8': byKind('apple-p8'), pkcs12: byKind('pkcs12'), provisioning: byKind('provisioning'),
    keystore: byKind('keystore'), 'google-service-account': byKind('google-service-account'),
    'google-services': byKind('google-services'), 'googleservice-info': byKind('googleservice-info'),
    'eas-credentials': byKind('eas-credentials'), unknown: byKind('unknown'),
  },
  problems: results.reduce((n, r) => n + r.problems.length, 0),
};
console.log(JSON.stringify(out, null, 2));
process.exitCode = out.problems ? 3 : 0;
EOF
