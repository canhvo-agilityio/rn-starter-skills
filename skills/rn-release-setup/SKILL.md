---
name: rn-release-setup
description: Sets up an app once for TestFlight and Google Play with EAS: Expo project, bundle id / package, build profiles, and every credential on EAS — build (certificate, profile, keystore), submit (App Store Connect API key, Google service account) and push (APNs, FCM) — from files the developer or client provides, without secrets in the chat. Use when someone wants to set up EAS, prepare an app for TestFlight or the Play Store, configure signing or push keys, or use credentials a client sent (.p8, .p12, .jks, service account JSON).
---

# Release setup (EAS)

Goal: when the developer opens the project's **Credentials** page on expo.dev, everything the app needs is there — build, submit and (if the app uses push) push credentials, for iOS and Android — and they know exactly what's left outside EAS. Nothing is built here unless the developer asks for a test build at the end; releasing comes after.

Talk to the dev in their language. Say early how this works: **the developer provides the files (and types passwords into one local file); you do the rest** — scanning, uploading to EAS (`scripts/eas-credentials.sh` drives EAS's interactive credential menus without reading or typing any secret) and checking.

**Secrets never pass through the conversation.** Never open, print or copy the contents of credential files (`.p8`, `.p12`, `.jks`/`.keystore`, service-account `.json`, `credentials.json`) or of `.env` files. Refer to files by path; `scripts/scan-credentials.sh` identifies them without reading their secrets. Passwords are typed by the developer in their own terminal, never in the chat.

## Phase 0 — Understand the project

```bash
source "<skill-dir>/../rn-starter/scripts/env.sh"; bash "<skill-dir>/scripts/release-inventory.sh" <project-dir>
```

JSON: Expo or React Native CLI, the resolved app config (name, slug, owner, version, bundle id, package, EAS project id, updates, encryption flag, icon/splash, plugins), native ids from `ios/` `android/`, `eas.json`, Fastlane, **whether the app uses push** (`features.push`) and other features, credential files in the project and whether git tracks or ignores them, and `docs/release-plan.md`.

- **Exit 3 — credential files tracked by git or not ignored**: stop and tell the dev first (`references/credentials.md` → Git).
- `ignoreRulesMissing`: add those patterns to `.gitignore` now, before any file arrives.
- **`docs/release-plan.md` exists** → a follow-up run (new credentials, push added, a profile change): read it, confirm what changed, do only that part.
- **Fastlane or another release setup exists** → this skill adds EAS next to it and removes nothing.

## Phase 1 — EAS

Read `references/eas.md`. Tell the dev: this skill uses **EAS** (Expo Application Services), for Expo and React Native CLI alike, with a free Expo account. A dev who doesn't want EAS: out of scope — say so and stop.

```bash
bash "<skill-dir>/scripts/eas-status.sh" <project-dir>
```

- **Exit 2, not logged in**: relay its ACTION REQUIRED lines; the dev logs in themselves, then rerun.
- One `AskUserQuestion`: the **owner** (options from `accounts`: *the client's or company's organization (Recommended)* / *my personal account*); already linked → only confirm, never relink without an explicit yes. And **where builds will run** later: *EAS cloud (Recommended)* / *this computer* — recorded in the plan, used for releases and the optional test build.

Then `eas init --account <owner> --non-interactive` and `eas.json` from `references/eas.md`.

## Phase 2 — Identity and environments

Read `references/identity.md`. One `AskUserQuestion` round (max 4):
- **Files already in hand?** *Yes — give the folder (Recommended when a client sent them)* / *Not yet*. With a folder, run the scan (Phase 5 step 3) now: a `.mobileprovision` and `google-services.json` name the bundle id / package the files were made for, so propose **those** ids instead of inventing new ones.
- iOS bundle id and Android package (`com.<company>.<app>`, or the ids from the files), stating that **they can't change once the app is on a store**; an app already on a store keeps its ids.
- Whether test builds use the production API or a staging one (a `staging` profile, `references/eas.md` → Profiles) — skip it when the app reads no API URL (`grep -rn "process.env.EXPO_PUBLIC_" src` finds none): one `production` profile.
- The API URL per environment, if the app reads one (names from `.env.example`, values from the dev).

## Phase 3 — Plan → dev approval

Write `docs/release-plan.md` from `references/plan-template.md`: owner, build location, identity, profiles and environments, and the credential checklist — **build**, **submit**, **push** (if used), per platform — with what each item needs from the dev and its status, plus what's needed outside EAS. Ask: "Set up EAS and the credentials from this plan?" → *Yes (Recommended)* / *Change something*. Nothing changes before a yes.

## Phase 4 — Profiles and environments

From `references/eas.md`: `eas.json` (`appVersionSource: "remote"`, `production` + optional `staging`, `production-simulator`, submit profiles), EAS environment variables per environment (`eas env:set`; never read `.env`), `expo-updates` with a `fingerprint` runtime version, identity and `ITSAppUsesNonExemptEncryption` in the app config. Run `npx expo-doctor` (Expo) and `npx tsc --noEmit`; fix what you introduced.

## Phases 5–7 — Credentials, in three rounds

Read `references/credentials.md` once, then for each round:

1. **List what this round needs**, in the dev's language, one line per item on what it's for.
2. The dev puts the files in **one folder** (outside the project is best) and gives you its path; ask for the non-secret ids in the chat now — key ids, issuer id, team id, **keystore alias** — so they never have to be typed into a file.
3. **Scan**: `bash "<skill-dir>/scripts/scan-credentials.sh" <folder> <project-dir> --bundle-id <id> --package <name>` — classifies every file and reports problems. Two `.p8` keys can't be told apart by content: ask which key id is which.
4. **Missing items**: where they come from and a message for the client (`references/client-request.md`). Stop until the dev has them.
5. **Upload** with `bash "<skill-dir>/scripts/eas-credentials.sh" <project-dir> <ios|android> <profile> <task> [--key … --key-id … --issuer-id … --team-id …]` (tasks and the `credentials.json` step in `credentials.md` → Uploading). It drives EAS's menus and prints each choice. Exit 0 → tick the item in the plan; exit 3 → it stopped on purpose (something already set up, a key Apple rejects, a menu it doesn't know) — read its message and decide with the dev; exit 2 → a password or Apple login prompt, or no `expect` on this machine: give the dev the printed command to run themselves.

| Round | iOS | Android | Reference |
|---|---|---|---|
| **5 — Build** | distribution certificate + App Store provisioning profile: the dev's `.p12` + `.mobileprovision` uploaded when provided; otherwise created by EAS from an App Store Connect API key or Apple ID | upload keystore: generated by EAS for a new app, the existing one for an app already on Google Play | `credentials-ios.md`, `credentials-android.md` → Build |
| **6 — Submit** | App Store Connect API key on EAS | Google service account key on EAS | same files → Submit |
| **7 — Push** (only if `features.push`) | APNs key on EAS | FCM V1 service account key on EAS, plus `google-services.json` and the app's push config | `push.md` |

**Android keystore without asking when it's clear**: a keystore in the dev's folder → upload it; no keystore and no `releaseSigns` in the inventory (a new project) → EAS generates one. Ask "is this app already on Google Play?" only when there's no keystore **and** `releaseSigns` isn't empty — generating a new keystore for a published app can't be undone (`credentials-android.md` → Build).

## Phase 8 — Check and hand off

Follow `references/verify.md`:
1. **The Credentials page**: go through the checklist with the dev (they look at expo.dev → the project → Credentials, or run `npx eas-cli credentials -p ios|android` in their terminal) — every item present, for the right bundle id / package, not expiring soon.
2. **Outside EAS**: the list of what isn't on the Credentials page but blocks the first submit (App Store Connect app record, Play Console app and its first manual upload, the service account's Play Console permissions, the API key's role). Mark each as done / for the dev / for the client.
3. **Optional test build** — ask: *Run a test build and submit now to prove the credentials work (Recommended)* / *Leave it for the first release*. A present credential can still be wrong (a service account without Play permissions, a keystore that isn't the published app's). If skipped, the hand-off says "set up, not proven by a build".

Update `docs/release-plan.md`, tell the dev briefly what's on EAS, what's left outside, and the next step: the first TestFlight / internal testing release (`eas build --profile production` then `eas submit`). Offer to commit (`chore(release): set up EAS and store credentials`; body wrapped at 72 columns; follow the project's own pre-commit rules). Don't commit without a yes.

## Principles

- **The Credentials page is the finish line**, with what's outside EAS listed next to it.
- **Ask for files, not account details.** Guidance only for what's missing.
- **Secrets stay out of the chat and the repo.** Paths, not contents; the developer uploads and types passwords.
- **Identity and keystores are permanent.** Infer from the files and the project; ask only when a wrong guess can't be undone.
- **Present isn't proven.** Offer the test build; say plainly when it wasn't run.
