#!/usr/bin/env node
// Claude Code PreToolUse hook (installed by rn-starter, configured by rn-release-setup): the release
// gate. Every command that would put the app in front of users is checked before it runs.
//   dev app (eas build / update):              allow
//   dev app (eas submit to TestFlight / Play):  ask the person running the session
//   production app (eas build / submit / update to its channel, pushing a v* tag):
//     deny unless the commit is on the production branch of the remote
//   production channel changes (rollback, republish, rollout): ask
//   pushing to the production branch, merging or approving a PR / MR from this session: always deny
// The approval is a merge: a release manager merges the release/<version> PR or MR into the
// production branch (`productionBranch` in the release block of .rn-starter.json, protected on the
// server so only release managers can merge). The gate checks it with git alone: it fetches that
// branch and asks whether the commit being shipped is on it, so it needs no GitHub or GitLab CLI and
// never takes Claude's word for it. Which profile and channel reach which app also comes from the
// release block (rn-release-setup writes it).
// It stops mistakes in this session, not someone determined to get around it: the real protection
// is the branch protection on the server and who may build, submit and publish on EAS and the stores.
// Commands that aren't releases are always allowed; a release to production it can't check is
// denied. Plain Node, no dependencies.
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
if (input.tool_name !== 'Bash') process.exit(0);
const command = String(input.tool_input?.command || '');

// ---------------------------------------------------------------- output
const RANK = { allow: 0, ask: 1, deny: 2 };
let verdict = { decision: 'allow', reason: '' };
const decide = (decision, reason) => {
  if (RANK[decision] > RANK[verdict.decision]) verdict = { decision, reason };
};
const finish = () => {
  if (verdict.decision !== 'allow' || verdict.reason) {
    try {
      fs.appendFileSync(path.join(root, '.claude', 'release-gate.log'),
        `${new Date().toISOString()} ${verdict.decision} ${JSON.stringify(command)} ${verdict.reason}\n`);
    } catch {}
  }
  if (verdict.decision === 'allow') process.exit(0);
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse', permissionDecision: verdict.decision, permissionDecisionReason: verdict.reason,
    },
  }));
  process.exit(0);
};

// ---------------------------------------------------------------- shell parsing
const segments = (cmd) => cmd.split(/;|&&|\|\||\||\n/).map((s) => s.trim()).filter(Boolean);
const tokenize = (seg) => {
  const out = [];
  let cur = '';
  let quote = null;
  let started = false;
  for (const ch of seg) {
    if (quote) {
      if (ch === quote) quote = null; else cur += ch;
    } else if (ch === '"' || ch === "'") {
      quote = ch; started = true;
    } else if (/\s/.test(ch)) {
      if (started || cur) out.push(cur);
      cur = ''; started = false;
    } else {
      cur += ch; started = true;
    }
  }
  if (started || cur) out.push(cur);
  return out;
};
// Leading VAR=value assignments (and `env VAR=value`) → { env, rest }.
const splitEnv = (tokens) => {
  const env = {};
  let i = 0;
  if (tokens[0] === 'env') i = 1;
  while (i < tokens.length && /^[A-Za-z_][A-Za-z0-9_]*=/.test(tokens[i])) {
    const eq = tokens[i].indexOf('=');
    env[tokens[i].slice(0, eq)] = tokens[i].slice(eq + 1);
    i += 1;
  }
  return { env, rest: tokens.slice(i) };
};
const flag = (args, ...names) => {
  for (let i = 0; i < args.length; i += 1) {
    for (const n of names) {
      if (args[i] === n) return args[i + 1] ?? '';
      if (args[i].startsWith(`${n}=`)) return args[i].slice(n.length + 1);
    }
  }
  return null;
};
const has = (args, ...names) => args.some((a) => names.includes(a));
// Arguments that aren't flags or flag values (`--percent 10` → neither is positional).
const BOOLEAN_FLAGS = ['--non-interactive', '--json', '--auto', '--latest', '--wait', '--no-wait', '--local', '--clear-cache', '--force-end-active-rollout'];
const positionals = (args) => args.filter((a, i) => !a.startsWith('-')
  && !(i > 0 && args[i - 1].startsWith('-') && !args[i - 1].includes('=') && !BOOLEAN_FLAGS.includes(args[i - 1])));

// eas invoked directly, through npx / pnpm dlx / yarn dlx / bunx, or as eas-cli@<version>.
const easArgs = (tokens) => {
  for (let i = 0; i < tokens.length; i += 1) {
    const t = tokens[i];
    if (t === 'eas' || /(^|\/)eas$/.test(t) || /^eas-cli(@[^\s]+)?$/.test(t)) return tokens.slice(i + 1);
  }
  return null;
};

// ---------------------------------------------------------------- project config
const readJson = (f) => {
  try { return JSON.parse(fs.readFileSync(path.join(root, f), 'utf8')); } catch { return null; }
};
const easJson = readJson('eas.json');
const release = readJson('.rn-starter.json')?.release ?? null;
const apps = release?.apps ?? [];
const prefix = release?.releaseBranchPrefix || 'release/';
const remote = release?.remote || 'origin';
const prodBranch = release?.productionBranch || 'main';

const profileConfig = (name, seen = new Set()) => {
  const p = easJson?.build?.[name];
  if (!p || seen.has(name)) return p ? { ...p } : null;
  seen.add(name);
  const base = p.extends ? profileConfig(p.extends, seen) ?? {} : {};
  return { ...base, ...p, env: { ...base.env, ...p.env }, ios: { ...base.ios, ...p.ios }, android: { ...base.android, ...p.android } };
};
// Without a release block (a project set up before the gate), names decide: prod* is production.
const looksProduction = (name) => /^prod/i.test(name || '');
const fallbackApp = (prod) => ({ name: prod ? 'production' : 'dev', production: prod });
const appByVariant = (v) => apps.find((a) => a.variant === v) ?? (v ? fallbackApp(looksProduction(v)) : null);
const appByProfile = (name) => {
  const listed = apps.find((a) => (a.profiles || []).includes(name));
  if (listed) return listed;
  const cfg = profileConfig(name);
  if (cfg?.env?.APP_VARIANT) return appByVariant(cfg.env.APP_VARIANT);
  if (cfg?.channel) return appByChannel(cfg.channel);
  if (!apps.length && cfg) return fallbackApp(looksProduction(name));
  return null;
};
function appByChannel(channel) {
  const listed = apps.find((a) => (a.channels || []).includes(channel));
  if (listed) return listed;
  return apps.length ? null : fallbackApp(looksProduction(channel));
}

// ---------------------------------------------------------------- git
const run = (cmd, args, timeout = 15000) => {
  try {
    return execFileSync(cmd, args, { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], timeout }).trim();
  } catch {
    return null;
  }
};
const ROUTE = (what) => `To release ${what}, run the rn-release skill: it opens a ${prefix}<version> pull request (or merge request) into ${prodBranch}. `
  + `Once a release manager merges it, ship from ${prodBranch} and run the command again. Never merge it or push to ${prodBranch} from this session.`;

// The production branch as the remote has it now (fetched once per command).
let fetched;
const prodRef = `refs/remotes/${remote}/${prodBranch}`;
const fetchProd = () => {
  if (fetched === undefined) {
    fetched = run('git', ['fetch', '--quiet', '--no-tags', remote, `+refs/heads/${prodBranch}:${prodRef}`], 20000) !== null;
  }
  return fetched;
};
// Null when `sha` is on the production branch (a release manager merged it); else the reason.
const notApproved = (sha, what) => {
  if (!sha) return `Can't read the commit to ship (not a git repository?). ${ROUTE(what)}`;
  if (!fetchProd()) {
    return `Can't fetch ${prodBranch} from ${remote} to check the approval (offline, no such branch, or git isn't signed in to the remote). Run again once it's reachable.`;
  }
  if (run('git', ['merge-base', '--is-ancestor', sha, prodRef]) === null) {
    return `Commit ${sha.slice(0, 7)} isn't on ${remote}/${prodBranch}, so no release manager has merged it. ${ROUTE(what)}`;
  }
  return null;
};
const tagCommit = (tag) => run('git', ['rev-parse', '-q', '--verify', `refs/tags/${tag}^{commit}`])
  || (run('git', ['ls-remote', '--tags', remote, `refs/tags/${tag}`, `refs/tags/${tag}^{}`], 10000) || '')
    .split('\n').filter(Boolean).map((l) => l.split(/\s+/)[0]).pop() || null;
const appVersion = () => readJson('app.json')?.expo?.version ?? readJson('package.json')?.version ?? null;
const dirtyTracked = () => {
  const s = run('git', ['status', '--porcelain', '--untracked-files=no']);
  return s === null ? false : s.length > 0;
};

// Checks for shipping the production app from HEAD; null when it may go. A store build carries the
// version in app.json, so its tag mustn't already mark another commit; an OTA update keeps the store
// build's version and is labelled by its own tag.
const productionCheck = (what, { storeBuild }) => {
  if (dirtyTracked()) {
    return `Uncommitted changes would ship with this build but aren't part of any merged release. Commit or stash them first. ${ROUTE(what)}`;
  }
  const sha = run('git', ['rev-parse', 'HEAD']);
  const why = notApproved(sha, what);
  if (why) return why;
  const version = appVersion();
  if (storeBuild && version) {
    const tagged = tagCommit(`v${version}`);
    if (tagged && tagged !== sha) {
      return `v${version} was already released from commit ${tagged.slice(0, 7)}. A new store build needs a new version: run the rn-release skill.`;
    }
  }
  verdict.reason ||= `commit ${sha.slice(0, 7)} is on ${remote}/${prodBranch}`;
  return null;
};

// ---------------------------------------------------------------- the rules
const PROD_CHANNEL_COMMANDS = ['update:republish', 'update:rollback', 'update:roll-back-to-embedded', 'update:revert-update-rollout',
  'update:edit', 'channel:edit', 'channel:rollout', 'channel:pause', 'channel:resume', 'channel:delete', 'branch:delete'];

const checkEas = (args, env) => {
  const sub = args.find((a) => !a.startsWith('-'));
  if (!sub) return;
  const rest = args.slice(args.indexOf(sub) + 1);
  const variantApp = env.APP_VARIANT ? appByVariant(env.APP_VARIANT) : null;

  if (sub === 'build' || sub === 'submit' || sub === 'build:version:set' || sub === 'build:version:sync') {
    const profile = flag(rest, '--profile', '-e') || 'production';
    const app = appByProfile(profile);
    if (!app) {
      decide('deny', `The release gate doesn't know which app the "${profile}" profile ${sub === 'submit' ? 'submits' : 'builds'}. `
        + 'Add it to the release block of .rn-starter.json (rn-release-setup), then run again.');
      return;
    }
    if (variantApp && variantApp.name !== app.name) {
      decide('deny', `APP_VARIANT=${env.APP_VARIANT} contradicts the "${profile}" profile (the ${app.name} app). Use the profile of the app you mean, without overriding APP_VARIANT.`);
      return;
    }
    if (sub.startsWith('build:version')) {
      if (app.production) decide('ask', `This changes the production app's build number on EAS (${sub}). Approve only if you own this release.`);
      return;
    }
    if (!app.production) {
      if (sub === 'submit') decide('ask', `This submits the ${app.name} app to TestFlight / Google Play for testers. Approve only if it's the build you mean to send.`);
      return;
    }
    if (sub === 'submit' && (has(rest, '--latest') || !flag(rest, '--id', '--path', '--url'))) {
      decide('deny', 'Submit the production app by build id (eas submit --profile production --platform <p> --id <build id>), '
        + 'using the build made from the merged release commit. --latest may pick another build, so the release gate can\'t tell it was approved.');
      return;
    }
    if (sub === 'build') {
      const cfg = profileConfig(profile);
      if (cfg?.ios?.simulator === true || cfg?.distribution === 'internal') return; // a check build: reaches no user
    }
    const why = productionCheck('the production app', { storeBuild: true });
    if (why) decide('deny', `Shipping the production app needs an approved release. ${why}`);
    return;
  }

  if (sub === 'update') {
    if (has(rest, '--auto')) {
      decide('deny', 'eas update --auto picks the channel from the git branch, so the release gate can\'t tell which app it reaches. Name it: --channel <channel> with APP_VARIANT.');
      return;
    }
    const channel = flag(rest, '--channel') || flag(rest, '--branch');
    if (!channel) {
      decide('deny', 'Name the update\'s channel (--channel <channel>) and app (APP_VARIANT=…) so the release gate can tell which app it reaches.');
      return;
    }
    const app = appByChannel(channel);
    if (!app) {
      decide('deny', `The release gate doesn't know which app the "${channel}" channel reaches. Add it to the release block of .rn-starter.json, then run again.`);
      return;
    }
    if (variantApp && variantApp.name !== app.name) {
      decide('deny', `APP_VARIANT=${env.APP_VARIANT} contradicts the "${channel}" channel (the ${app.name} app): the update would be built for one app and sent to the other.`);
      return;
    }
    if (!app.production) return;
    if (!variantApp) {
      decide('deny', `Pass the app: APP_VARIANT=${app.variant || 'production'} eas update --channel ${channel} … Without it the update is computed for the dev app.`);
      return;
    }
    const why = productionCheck('an update to the production app', { storeBuild: false });
    if (why) decide('deny', `An OTA update reaches production users at once, with no store review, so it needs an approved release. ${why}`);
    return;
  }

  if (PROD_CHANNEL_COMMANDS.includes(sub)) {
    const named = flag(rest, '--channel') || flag(rest, '--branch');
    const target = named || (sub.startsWith('channel:') || sub === 'branch:delete' ? positionals(rest)[0] : null);
    const app = target ? appByChannel(target) : null;
    if (!target || !app || app.production) {
      decide('ask', `This changes what ${target ? `the "${target}" channel` : 'an update channel'} serves${app?.production ? ' to production users' : ''} (${sub}). Approve only if you own this release.`);
    }
  }
};

const checkGitPush = (args) => {
  const PUSH_REASON = `Merging into ${prodBranch} is the release approval, so only a release manager does it, through the release pull request or merge request. `
    + 'Push a release/<version> branch and open the PR / MR instead.';
  if (has(args, '--all', '--mirror')) {
    decide('deny', `Pushing every branch would push ${prodBranch} too. ${PUSH_REASON}`);
    return;
  }
  if (has(args, '--tags', '--follow-tags')) {
    const vtags = (run('git', ['tag', '--list', 'v*']) || '').split('\n').filter(Boolean);
    if (vtags.length) decide('deny', 'Pushing every tag could publish a release tag that was never merged. Push the release tag by name (git push origin v<version>) as the rn-release skill does.');
    return;
  }
  const refs = args.filter((a) => !a.startsWith('-')).slice(1); // after the remote
  const current = run('git', ['rev-parse', '--abbrev-ref', 'HEAD']);
  if (!refs.length && current === prodBranch) { decide('deny', PUSH_REASON); return; }
  for (const ref of refs) {
    const dst = ref.split(':').pop().replace(/^\+/, '');
    if (dst === prodBranch || dst === `refs/heads/${prodBranch}` || (dst === 'HEAD' && current === prodBranch)) {
      decide('deny', PUSH_REASON);
      continue;
    }
    const name = dst.replace(/^refs\/tags\//, '');
    if (!/^v\d/.test(name) || ref.startsWith(':')) continue;
    const sha = run('git', ['rev-parse', '-q', '--verify', `refs/tags/${name}^{commit}`]);
    if (!sha) continue; // not a tag here: nothing to push
    const why = notApproved(sha, `tag ${name}`);
    if (why) decide('deny', `${name} marks a production release. ${why}`);
  }
};

// Approving or merging a PR / MR is a person's decision; with the dev's credentials this session
// could otherwise approve its own release.
const checkReviewTools = (tokens) => {
  const gh = tokens.indexOf('gh');
  if (gh >= 0) {
    const a = tokens.slice(gh + 1);
    if (a[0] === 'pr' && a[1] === 'review' && has(a, '--approve', '-a')) decide('deny', 'Approving a pull request is a person\'s decision; this session never approves one.');
    if (a[0] === 'pr' && a[1] === 'merge') decide('deny', 'Merging a pull request is a person\'s decision; this session never merges one.');
    if (a[0] === 'api' && a.some((x) => /\/(reviews|merge)\b/.test(x))) decide('deny', 'Approving or merging a pull request through the API is a person\'s decision.');
  }
  const gl = tokens.indexOf('glab');
  if (gl >= 0) {
    const a = tokens.slice(gl + 1);
    if (a[0] === 'mr' && ['approve', 'merge'].includes(a[1])) decide('deny', `${a[1] === 'merge' ? 'Merging' : 'Approving'} a merge request is a person's decision; this session never does it.`);
    if (a[0] === 'api' && a.some((x) => /\/(approve|merge)\b/.test(x))) decide('deny', 'Approving or merging a merge request through the API is a person\'s decision.');
  }
};

for (const seg of segments(command)) {
  const { env, rest } = splitEnv(tokenize(seg));
  if (!rest.length) continue;
  const eas = easArgs(rest);
  if (eas) { checkEas(eas, env); continue; }
  const g = rest.indexOf('git');
  if (g >= 0 && rest[g + 1] === 'push') { checkGitPush(rest.slice(g + 2)); continue; }
  if (rest.includes('gh') || rest.includes('glab')) checkReviewTools(rest);
}
finish();
