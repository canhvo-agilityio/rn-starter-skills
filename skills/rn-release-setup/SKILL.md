---
name: rn-release-setup
description: Sets up a React Native / Expo app, once, so it can be built for the App Store and Google Play with EAS and shipped to testers through TestFlight and Google Play internal testing — Expo account and EAS project, bundle id / package, build profiles and versioning, API URLs per environment, iOS and Android signing credentials (App Store Connect API key, distribution certificate and provisioning profile, upload keystore, Google service account), push / Sign in with Apple / Google Sign-In / Maps / Firebase / Sentry setup for store builds, and OTA update channels. Works from the files the developer or their client provides, without secrets passing through the conversation, and ends with a store-signed build that succeeds. Use this whenever someone wants to set up EAS Build, prepare an app for TestFlight or the Play Store, configure signing, certificates, provisioning profiles or a keystore, use credentials a client sent (.p8, .p12, .jks, service account JSON), or "get the app ready to release" — before the first release.
---

# Release setup (EAS)

Goal: an app that can be built for the stores and shipped to testers, **set up once**. Every later release only builds, submits and updates (the `rn-release` skill); this one leaves it a `docs/release-plan.md` and a store-signed build that succeeded.

Talk to the dev in their language. Keep them in the loop at the decisions that are theirs: the EAS owner, the app's identity (permanent once released), the plan, and anything that needs their accounts or passwords.

**Secrets never pass through the conversation.** Never open, print or copy the contents of credential files (`.p8`, `.p12`, `.jks`/`.keystore`, service-account `.json`, `credentials.json`) or of `.env` files. Refer to files by path; `scripts/scan-credentials.sh` identifies them without reading their secrets. Passwords are typed by the developer in their own terminal, never in the chat. Values go to EAS (environment variables, credentials), not into the repo.

## Phase 0 — Understand the project

```bash
source <rn-starter-skill-dir>/scripts/env.sh 2>/dev/null; bash "<skill-dir>/scripts/release-inventory.sh" <project-dir>
```

JSON: Expo or React Native CLI, the resolved app config (name, slug, owner, version, bundle id, package, build numbers, EAS project id, updates, encryption flag, icon/splash, plugins), native ids from `ios/` `android/`, `eas.json`, Fastlane, the **release features** the app uses (push, Sign in with Apple, Google Sign-In, domain links, maps, Firebase, Sentry, permission-using modules), credential files in the project and whether git tracks or ignores them, and `docs/release-plan.md`.

- **Exit 3 — credential files tracked by git or not ignored**: stop and tell the dev first. Not ignored → add the rules to `.gitignore` (list in `references/credentials.md` → Git). Tracked → `git rm --cached` them, and if they were ever pushed, tell the dev to treat them as leaked and ask the owner to revoke and reissue them.
- `ignoreRulesMissing` lists patterns `.gitignore` doesn't cover yet: add them now, before any file arrives.
- **`docs/release-plan.md` exists** → a follow-up run (new credentials, a new feature, a profile change). Read it, confirm what changed with the dev, and do only that part.
- **Fastlane or another release setup exists** → say this skill adds EAS next to it and removes nothing; replacing it is out of scope.

## Phase 1 — EAS

Read `references/eas.md`. Tell the dev plainly, in their language: this skill builds and submits with **EAS** (Expo Application Services) — for Expo and React Native CLI alike; it needs a free Expo account; cloud builds on the free plan are limited per month, local builds aren't. A dev who doesn't want EAS: say it's out of scope and stop.

```bash
bash "<skill-dir>/scripts/eas-status.sh" <project-dir>
```

- **Exit 2, not logged in**: relay its ACTION REQUIRED lines — the dev logs in themselves (`! npx eas-cli login`), then rerun.
- **Owner** — one `AskUserQuestion`, options from `accounts` in the output: *the client's or company's organization (Recommended)* / *my personal account* / Other. If the project is already linked (`project.linked`), only confirm its owner; never relink without the dev's explicit yes.
- **Where to build** — same call: *EAS cloud (Recommended)* / *this computer (`--local`)*. Local needs macOS + Xcode + fastlane + CocoaPods for iOS, the Android SDK + JDK 17 (rn-starter `doctor.sh --android --ios`), and **~15 GB free disk** (`df -h ~`); Windows and Linux build iOS in the cloud only. Use the dev's choice for every build in this skill, including your checks.

Then link and configure: `eas init --account <owner> --non-interactive`, and `eas.json` from `references/eas.md`.

## Phase 2 — Identity

Read `references/identity.md`. Propose the iOS bundle id and Android package (`com.<company>.<app>`, from the dev's domain and the app name), the display name, and the marketing version. Say clearly that **the bundle id and package can't change once the app is on a store**. If the app is already on a store (the dev says so, or the client's files show it), use the existing ids — never new ones. RN CLI: keep the ids in `ios/` and `android/`; changing them there is a separate step the dev approves.

Ask only what you can't infer, in one `AskUserQuestion` (max 4): identity; whether test builds use the production API or a staging one (decides a `staging` profile, `references/eas.md` → Profiles); the API URL per environment if the app reads one (names from `.env.example`, values from the dev).

## Phase 3 — Plan → dev approval

Write `docs/release-plan.md` from `references/plan-template.md`: owner and project, build location, identity, profiles with their environments and update channels, release features to set up, the credentials needed per platform with their status (`needed` / `provided` / `on EAS`), and open items.

Show a short summary and ask: "Set up the release from this plan?" → *Yes (Recommended)* / *Change something*. Don't change the project before a yes.

## Phase 4 — Profiles, environments, updates

From `references/eas.md`:
1. `eas.json`: `cli.appVersionSource: "remote"`, profiles `production` (+ `staging`) with `distribution: "store"`, `autoIncrement`, `channel`, `environment`; `production-simulator` for verification; submit profiles.
2. API URLs and other `EXPO_PUBLIC_*` values as EAS environment variables (`eas env:create`), per environment. Never read or write `.env`.
3. `expo-updates` with a `fingerprint` runtime version, so an OTA update only reaches builds with the same native code.
4. `app.json`: identity, `ITSAppUsesNonExemptEncryption` (`references/identity.md`), icon and splash present.

Run `npx expo-doctor` (Expo) and `npx tsc --noEmit`; fix what you introduced.

## Phase 5 — Credentials

Read `references/credentials.md` and, per platform, `credentials-ios.md` / `credentials-android.md`.

1. **List what's needed** for this app, in the dev's language, with each item's purpose — iOS, Android, and per release feature found in Phase 0 (APNs key, `google-services.json`, …). Ask the dev to put the files in **one folder** (outside the project is best) and give you its path; non-secret values (key ids, issuer id, team id, keystore alias) can be typed in the chat.
2. **Scan it**: `bash "<skill-dir>/scripts/scan-credentials.sh" <folder> <project-dir> --bundle-id <id> --package <name>`. It classifies every file and reports problems (wrong type, expired or wrong profile, not ignored by git, Firebase files for another app). Two `.p8` keys can't be told apart by content — ask which key id is the App Store Connect API key and which is the APNs key.
3. **Only for what's missing**, explain where it comes from (`references/client-request.md`) and draft the message the dev can send to the client. Then stop: exit 2 territory — the dev comes back with the files and you rerun the scan.
4. **Put them on EAS** the way each platform's reference says. Steps that need a password or an Apple login are run by the dev in their own terminal; give them the exact command and what to choose.

**Never let EAS generate a new Android keystore for an app that's already on Google Play** — ask first whenever no keystore was provided (`credentials-android.md`).

## Phase 6 — Release features

For each feature Phase 0 found, follow `references/release-features.md`: what it needs in a store build, where each value comes from, and how to check it. Several need the signing certificates' fingerprints (Google Sign-In, Maps, Android App Links) — take them from `eas credentials` / Play Console, which show public fingerprints only. Features the app doesn't use: skip.

## Phase 7 — Verify and hand off

Follow `references/verify.md`:
1. **Same configuration on a simulator/emulator**: build `production-simulator`, install, open, screenshot. Check the app's name and icon, the version, that it talks to the API of that environment (a value only the API has), and that it isn't on mocks.
2. **Store-signed builds**: `production` for each platform the dev has credentials for. Android: the `.aab` is signed with the expected key (fingerprint matches the one on EAS / Play). iOS: the build finishes signing. A platform without credentials yet is listed as not done — never implied.
3. **Credentials summary**: what `eas credentials` holds per platform.

Then update `docs/release-plan.md` (statuses, where each credential lives, what's missing, the next step: `rn-release` for the first TestFlight / internal testing release), tell the dev briefly what's set up and what's left, and offer to commit (`chore(release): set up EAS builds and store credentials`; body wrapped at 72 columns; follow the project's own pre-commit rules, e.g. its code-reviewer). Don't commit without a yes.

## Principles

- **EAS only, set up first.** Everything else lives on the EAS project.
- **Ask for files, not account details.** What matters is what the dev can provide; guidance only for what's missing.
- **Secrets stay out of the chat and the repo.** Paths, not contents; passwords typed by the dev; values on EAS.
- **Identity and keystores are permanent.** Confirm before creating; reuse what a published app already has.
- **A store-signed build that succeeds is the proof.** A platform not built is not set up.
