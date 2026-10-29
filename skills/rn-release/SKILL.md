---
name: rn-release
description: Runs a production release of a React Native / Expo app on release day, behind a human approval gate - gathers what changed since the last release, drafts the store "What's new" and the CHANGELOG, picks the version and the route (a store build when native code changed, else an OTA update), runs the release checklist, opens a release/<version> pull request or merge request into the production branch for a release manager to review and merge, then ships the merged commit (EAS build and submit, or an OTA update), tags v<version> to lock it and lists what's left in the store consoles. Works with GitHub and GitLab. Use when someone says "release", "ship to production", "release day", "prepare release 1.4.0", "push an OTA update to production", or asks for release notes or a release checklist. Needs rn-release-setup done first (the two apps and the release gate).
---

# Production release

Goal: on release day, a release manager reviews one pull request (GitHub) or merge request (GitLab) that says exactly what ships and how, and **merges it into the production branch: that merge is the approval**. Then the merged commit, and nothing else, reaches the production app, and the version is locked so it can't ship again from another commit. The dev app needs none of this: dev builds and updates go out whenever testers need them.

Talk to the dev in their language. **Invoked as a slash command**, the text after the skill's name is the dev's request: read it like any message ("release 1.4.0", "OTA fix for the bag badge", "the release got merged") and ask only for what it leaves out.

**The release gate decides, not you.** `.claude/hooks/release-gate.mjs` checks every production build, submit, OTA update and `v*` tag push: the commit must be on the remote's production branch (`productionBranch` in the release block of `.rn-starter.json`), which only release managers can merge into. When it denies, relay its reason and stop. Never approve or merge the PR / MR, never push to the production branch, never work around a denial (another profile, channel, `APP_VARIANT`, a tag on another commit). The approval is a person's decision; the skill prepares it and carries it out.

Never open `.env` or credential files; production values live in EAS environment variables, and you check their names only.

## Phase 0: Where the release stands

```bash
source "<skill-dir>/../rn-starter/scripts/env.sh"; bash "<skill-dir>/scripts/release-status.sh" <project-dir> --runtime
```

JSON (git only, no GitHub or GitLab CLI needed): the gate and its release block, git (branch, HEAD, clean, last `v*` tag, whether HEAD is already on the production branch), the app's version and the last released one, the commits since the last release with their ticket ids, release branches on the remote not merged yet, what the gate would say about shipping HEAD right now, and the production runtime version at HEAD against the last production build (`nativeChanged`).

- **Exit 3, no gate or no release block**: the project isn't set up for releases. Run `rn-release-setup` first (it sets up the two apps, the gate and the production branch); stop.
- **Exit 2, the remote can't be fetched** (offline, or git isn't signed in): the dev fixes it; the gate needs the remote too. Rerun.
- **`runtime` is null** (expo-updates missing, or not logged in to Expo): say so; Phase 2 then asks the route without a recommendation.
- **A release branch isn't merged yet** (`releaseBranches`) → a follow-up run: tell the dev the release manager still has to merge it, and stop; the dev asks for changes → Phase 4's "changes after review".
- **HEAD is on the production branch with a version not tagged yet** (`git.headOnProduction`, `approval.decision: allow`) → the release was merged: Phase 5.
- **Nothing since the last tag**: nothing to release; say so.

## Phase 1: What's in this release

From `changes`, list what users will notice, grouped (Added / Changed / Fixed), with ticket ids. Read `references/notes.md`, then draft the store "What's new" (per store language) and the `CHANGELOG.md` section. Show both to the dev: they own the wording, so change what they ask, then go on.

## Phase 2: Version and route

One `AskUserQuestion` round:
- **Version**: propose from the changes and the last released version: a new feature → minor (`1.4.0`), fixes only → patch (`1.3.3`), a breaking change for users or the backend → major. *<proposal> (Recommended)* / the other two.
- **Route**: `nativeChanged: true` or no production build yet → **store build**, no choice to offer (an OTA update would reach nobody); say why in one line. `nativeChanged: false` → *Store build (Recommended for planned releases)* / *OTA update (Recommended for an urgent fix: live at once, no store review)*. With OTA, also ask *full rollout* / *start at 10 %*.

An OTA release keeps the store build's `version` in `app.json`; its version is the release's own label (`1.4.1`) in the changelog and the tag.

## Phase 3: Checklist

On HEAD, before anything is pushed, run what `CLAUDE.md` → Verifying your work lists (type check, lint, unit tests), then the Maestro flows (`rn-e2e`'s `run-flows.sh --start-server`), and check:
- EAS production variables: `eas env:list production` has every name in `.env.example` (names only).
- Credentials: from `docs/release-plan.md`, nothing on the production app expires within 30 days.
- Store answers: new permissions or newly collected data since the last release (`git diff <last tag> -- app.json app.config.* package.json`) mean the App Store privacy answers and the Play data safety form change: a person updates them before review.
- What isn't verified: the "Not verified" lines of the merged work, plus this release's own gaps.

A red check stops the release: fix it on the base branch through its own PR / MR, then start again. If the dev insists on going on, the PR / MR shows it as failing, in its first line, for the release manager to decide.

## Phase 4: The release PR / MR

Read `references/pr-template.md`. Branch `release/<version>` from the base branch, change only `app.json`'s version (store build) and `CHANGELOG.md`, commit in the project's format (`chore(release): <version>`), then show the dev the branch, the commit and the description, and push the branch on their yes (`git push -u origin release/<version>`). Open it **into the production branch** with the tool the project has: `gh pr create --base <production branch> …` on GitHub, `glab mr create --target-branch <production branch> …` on GitLab; without either, give the dev the title, the description and the link to open it (the push output prints GitLab's; GitHub's is `https://github.com/<owner>/<repo>/compare/<production branch>...release/<version>`).

Then stop and tell the dev: a release manager reviews it and merges it; come back (or rerun the skill) once it's merged.

**Changes after review**: a reviewer asks for a change → make it on the base branch through its own PR / MR when it's code, or on the release branch when it's the notes or the version; push. Nothing ships until the release branch is merged, so there's nothing to re-approve separately.

## Phase 5: Ship

Check out the production branch as merged (`git switch <production branch> && git pull --ff-only`), rerun `release-status.sh` and read `approval`. `deny` → relay the reason, stop. `allow` → follow `references/ship.md`:
- **Store build**: `eas build --profile production --platform all`, then `eas submit` per platform with each build's id. The builds land in TestFlight and Play internal testing.
- **OTA**: `APP_VARIANT=production eas update --channel production --environment production --message "<version>: …"` (with `--rollout-percentage` if chosen).

A failed build or submit: read why (`ship.md`), fix on the base branch, and the fix goes through a new release PR / MR. Never patch the production branch.

## Phase 6: Lock and hand off

1. Tag the commit that shipped and push the tag (`ship.md` → Lock the version). The gate checks the commit is on the production branch.
2. Tell the dev, briefly: what shipped (version, route, build ids or update group, links), what a person does next in the store consoles (App Store review and release type; Play promotion and staged rollout), that the production branch should be merged back into the base branch (a person's PR / MR, so `CHANGELOG.md` and the version reach it), and how to roll back (`ship.md` → Rolling back). What wasn't verified is listed, not hidden.

## Principles

- **A person approves by merging; the gate enforces; the skill prepares and carries out.** It never approves, never merges, never pushes to the production branch, never works around the gate.
- **Exactly the merged commit ships.** Anything not on the production branch needs its own release PR / MR.
- **One version, one commit.** The tag locks it; a fix is a new version.
- **Store build when native code changed.** OTA only for a matching runtime, and only for what can go live without review.
- **Say what's left to people** (store review, rollout, merging back) and what wasn't checked.
