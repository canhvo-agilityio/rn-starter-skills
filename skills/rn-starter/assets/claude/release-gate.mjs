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
// Before anything ships, the release block must record that the production branch is protected
// (productionBranchProtected): until then, being on the branch proves nothing.
// It looks through wrappers (bash -c, sh -c, eval, subshells, $( ), backticks) and global options
// (git -C / -c / --repo, gh / glab -R), counts untracked files as uncommitted, and requires a production
// OTA update's APP_VARIANT and --environment to be the production app's.
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
// Split on command separators and on subshell, group and substitution brackets, so
// `(eas build …)`, `{ eas build …; }`, `$(eas build …)` and backticks are seen as commands.
const segments = (cmd) => cmd.split(/;|&&|\|\||\||\n|\$\(|[(){}`]/).map((s) => s.trim()).filter(Boolean);
// Shells and eval run their argument as a command: check that text too (`bash -c "eas build …"`).
const SHELLS = ['bash', 'sh', 'zsh', 'dash', 'ksh', 'fish'];
const expand = (cmd, depth = 0) => {
  const out = [];
  for (const seg of segments(cmd)) {
    out.push(seg);
    if (depth > 3) continue;
    const t = tokenize(seg);
    const k = t.findIndex((x) => SHELLS.includes(x.split('/').pop()));
    if (k >= 0) {
      const c = t.indexOf('-c', k);
      if (c > k && t[c + 1]) out.push(...expand(t[c + 1], depth + 1));
    }
    if (t[0] === 'eval') out.push(...expand(t.slice(1).join(' '), depth + 1));
  }
  return out;
};
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
// With a release block, a variant it doesn't list is unknown: app.config.js would build the dev app for it.
const appByVariant = (v) => apps.find((a) => a.variant === v) ?? (v && !apps.length ? fallbackApp(looksProduction(v)) : null);
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
  // Until the server stops anyone else from pushing to the production branch, being on it proves nothing.
  if (release && !release.productionBranchProtected) {
    return `The release block doesn't record that ${prodBranch} is protected on the server yet (productionBranchProtected). `
      + 'Until only release managers can merge into it, a commit on it isn\'t an approval. Protect it (rn-release-setup gives the GitHub / GitLab steps), then record the date.';
  }
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
// Untracked files count too: EAS and expo-router bundle every file that isn't ignored.
const dirtyTracked = () => {
  const s = run('git', ['status', '--porcelain']);
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
  if (env.APP_VARIANT && !variantApp) {
    decide('deny', `APP_VARIANT=${env.APP_VARIANT} isn't one of the apps in the release block (${apps.map((a) => a.variant).join(', ')}): app.config.js would build the dev app for it. Use one of those.`);
    return;
  }

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
    const autoSubmit = rest.some((a) => a === '--auto-submit' || a.startsWith('--auto-submit-with-profile'));
    if (!app.production) {
      if (sub === 'submit' || autoSubmit) decide('ask', `This submits the ${app.name} app to TestFlight / Google Play for testers${autoSubmit ? ' (--auto-submit)' : ''}. Approve only if it's the build you mean to send.`);
      return;
    }
    if (sub === 'submit' && (has(rest, '--latest') || !flag(rest, '--id', '--path', '--url'))) {
      decide('deny', 'Submit the production app by build id (eas submit --profile production --platform <p> --id <build id>), '
        + 'using the build made from the merged release commit. --latest may pick another build, so the release gate can\'t tell it was approved.');
      return;
    }
    if (sub === 'build' && !autoSubmit) {
      // Only an iOS Simulator build reaches no one; an Android APK or an internal build installs on real phones.
      const cfg = profileConfig(profile);
      const platform = flag(rest, '--platform', '-p') || 'all';
      if (cfg?.ios?.simulator === true && platform === 'ios') return;
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
    const wantEnv = app.environment || 'production';
    const gotEnv = flag(rest, '--environment');
    if (gotEnv !== wantEnv) {
      decide('deny', `An update to the ${app.name} app must use its EAS environment: --environment ${wantEnv}${gotEnv ? ` (not ${gotEnv})` : ''}. Otherwise it's built with the wrong API URL, or none (and the app falls back to mocks).`);
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

const checkGitPush = (args, cwd = root) => {
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
  // The first positional is the remote, unless --repo named it.
  const repoFlag = args.some((a) => a === '--repo' || a.startsWith('--repo='));
  const positional = args.filter((a, i) => !a.startsWith('-') && !(args[i - 1] === '--repo' || args[i - 1] === '-o' || args[i - 1] === '--push-option'));
  const refs = repoFlag ? positional : positional.slice(1);
  let current = null;
  try { current = execFileSync('git', ['rev-parse', '--abbrev-ref', 'HEAD'], { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim(); } catch {}
  if (!refs.length && current === prodBranch) { decide('deny', PUSH_REASON); return; }
  for (const ref of refs) {
    const dst = ref.split(':').pop().replace(/^\+/, '');
    if (dst === prodBranch || dst === `refs/heads/${prodBranch}` || (dst === 'HEAD' && current === prodBranch)) {
      decide('deny', PUSH_REASON);
      continue;
    }
    const name = dst.replace(/^refs\/tags\//, '');
    if (!/^v\d/.test(name) || ref.startsWith(':')) continue;
    // What the remote tag would point at: an existing local tag, or the source of `src:refs/tags/vX`.
    const src = ref.includes(':') ? ref.split(':')[0].replace(/^\+/, '') : `refs/tags/${name}`;
    const sha = run('git', ['rev-parse', '-q', '--verify', `${src}^{commit}`]);
    if (!sha) {
      decide('deny', `${name} doesn't exist yet as a tag here, so the release gate can't tell which commit it marks. `
        + 'Create the tag on the shipped commit first (git tag -a), then push it by name as its own command.');
      continue;
    }
    const why = notApproved(sha, `tag ${name}`);
    if (why) decide('deny', `${name} marks a production release. ${why}`);
  }
};

// Approving or merging a PR / MR is a person's decision; with the dev's credentials this session
// could otherwise approve its own release.
// Drop a CLI's global flags (`gh -R owner/repo pr merge`) so the subcommand is found.
const stripGlobal = (a, withValue) => {
  const out = [];
  for (let i = 0; i < a.length; i += 1) {
    if (withValue.includes(a[i])) { i += 1; continue; }
    if (withValue.some((f) => f.startsWith('--') && a[i].startsWith(`${f}=`))) continue;
    out.push(a[i]);
  }
  return out;
};
const checkReviewTools = (tokens) => {
  const gh = tokens.indexOf('gh');
  if (gh >= 0) {
    const a = stripGlobal(tokens.slice(gh + 1), ['-R', '--repo', '--hostname']);
    if (a[0] === 'pr' && a[1] === 'review' && has(a, '--approve', '-a')) decide('deny', 'Approving a pull request is a person\'s decision; this session never approves one.');
    if (a[0] === 'pr' && a[1] === 'merge') decide('deny', 'Merging a pull request is a person\'s decision; this session never merges one.');
    if (a[0] === 'api' && a.some((x) => /\/(reviews|merges?)\b/.test(x))) decide('deny', 'Approving or merging a pull request through the API is a person\'s decision.');
  }
  const gl = tokens.indexOf('glab');
  if (gl >= 0) {
    const a = stripGlobal(tokens.slice(gl + 1), ['-R', '--repo']);
    if (a[0] === 'mr' && ['approve', 'merge'].includes(a[1])) decide('deny', `${a[1] === 'merge' ? 'Merging' : 'Approving'} a merge request is a person's decision; this session never does it.`);
    if (a[0] === 'api' && a.some((x) => /\/(approve|merges?)\b/.test(x))) decide('deny', 'Approving or merging a merge request through the API is a person\'s decision.');
  }
};

// git's global options come before the subcommand (`git -C . push`, `git -c x=y push`).
const GIT_GLOBAL_WITH_VALUE = ['-C', '-c', '--git-dir', '--work-tree', '--namespace', '--exec-path'];
const gitPush = (rest) => {
  const g = rest.indexOf('git');
  if (g < 0) return null;
  let cwd = root;
  let i = g + 1;
  while (i < rest.length && rest[i].startsWith('-')) {
    if (rest[i] === '-C') cwd = path.resolve(root, rest[i + 1] || '.');
    i += GIT_GLOBAL_WITH_VALUE.includes(rest[i]) ? 2 : 1;
  }
  return rest[i] === 'push' ? { args: rest.slice(i + 1), cwd } : null;
};

for (const seg of expand(command)) {
  const { env, rest } = splitEnv(tokenize(seg));
  if (!rest.length) continue;
  const eas = easArgs(rest);
  if (eas) { checkEas(eas, env); continue; }
  const push = gitPush(rest);
  if (push) { checkGitPush(push.args, push.cwd); continue; }
  if (rest.includes('gh') || rest.includes('glab')) checkReviewTools(rest);
}
finish();
