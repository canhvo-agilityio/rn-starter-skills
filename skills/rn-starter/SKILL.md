---
name: rn-starter
description: Step-by-step wizard that takes a developer's machine — even a brand-new one with nothing installed — to a running React Native app. Checks Node/package manager/Android/Xcode tooling, installs what is missing, asks the dev which framework (Expo or React Native CLI), bundler (Metro or Re.Pack), template, libraries and run target they want, scaffolds the project with a clean folder structure (and, when the dev describes screens or shares a screenshot/Figma design, builds those screens via the rn-design-import skill), and runs it on a phone (Expo Go on iPhone or Android), iOS Simulator, Android emulator or web. Use this whenever someone wants to start, create, init, bootstrap or scaffold a React Native / Expo app, set up a machine for React Native development, onboard a new mobile dev, or asks "how do I get a RN app running" — even if they don't say "wizard" or name a specific tool.
---

# React Native starter wizard

Goal: the dev ends this session with a React Native app **running on their screen**, on a machine that may have had nothing installed. Scope is local development only: real phones through Expo Go, the iOS Simulator, the Android emulator, or web. No code signing, no paid Apple developer account, no store builds. Xcode is only installed when the dev picks the iOS Simulator.

The dev may be new to React Native. Talk to them in their own language (if they write Vietnamese, ask every question in Vietnamese), keep jargon light, and explain in one short line *why* a step is needed when it is not obvious.

## How the wizard works

Run the phases below in order. Each phase either checks something, asks one round of questions, or does work — then confirms it worked before moving on. Never skip the verification at the end of a phase: a step that "probably worked" is the main reason onboarding scripts fail on someone else's machine.

Ask questions with the `AskUserQuestion` tool (up to 4 questions per call, 2–4 options each, the recommended option first and labelled "(Recommended)"). The dev can always pick "Other". Every question has a sensible default so a dev who just accepts the recommendation every time still ends up with a working app.

**"Other" answers** are real requirements, not noise. For each one: (1) turn it into a concrete command or config, (2) show the dev exactly what you'll apply and get a yes — free text is easy to misread, (3) check it against `references/compatibility.md`; if it can't work, say why and offer the closest valid option instead of silently dropping it, (4) verify it like a built-in option, (5) record it in `.rn-starter.json` and the README. `references/quality.md` has worked examples (Jira-style commit messages, branch-name rules).

Only offer combinations that work together. `references/compatibility.md` is the source of truth — read it before Phase 2 and filter options with it, so the dev is never offered something that will fail later. `AskUserQuestion` shows all questions of one call at once, so **a question whose options depend on another answer goes in a later call** than that answer (e.g. run targets after the framework). Never put both in the same call and hope to filter afterwards.

Keep a running record of the dev's answers (framework, bundler, template, package manager, libraries, run target, app name, location, design input). You will show it in Phase 5 and write it into the project README in Phase 8.

### Shell environment

Scripts live in `scripts/` next to this file. Claude's Bash tool does not reload `~/.zshrc` between calls, so tools installed during this session (fnm/Node, JDK, Android SDK, Homebrew) are not on PATH yet. Prefix every command that needs them with:

```bash
source "<skill-dir>/scripts/env.sh" && <command>
```

`env.sh` is safe to source repeatedly and silently skips tools that are not installed.

Long-running commands (Android SDK or iOS runtime download, first Gradle/Xcode build, `pnpm install` on a slow network) can exceed the Bash timeout: run them with `run_in_background` and tell the dev what is happening while they wait.

---

## Phase 0 — Inspect the machine

Run:

```bash
bash "<skill-dir>/scripts/doctor.sh"
```

It prints one line per tool: `ok`, `warn` or `missing`, plus a summary. It only reads; it installs nothing. On macOS also add `--ios`, and add `--android` if an Android SDK might already be there. Knowing what's already installed lets you recommend the run target that needs the least setup in Phase 2.

Show the dev a short table of the result (tool → status → version). If the OS is Windows (not WSL), stop and explain that this wizard currently supports macOS and Linux only.

## Phase 1 — Base tools (Node + package manager)

Required for every path: **git**, **Node LTS** (current React Native / Expo need `^22.13 || ^24.3 || >=26`; odd-numbered Node versions are not supported), and a package manager.

- **git missing on macOS** → run `xcode-select --install`. This opens a system dialog: tell the dev to click *Install* (it is the small Command Line Tools package, ~1 GB, not Xcode and no Apple ID). Wait for them to confirm, then re-check with `git --version`. On Linux, ask the dev to install git with their distro package manager (needs sudo, so they run it themselves).
- **Node missing or too old** → ask before installing (one question: "Install Node LTS via fnm? (Recommended)" / "I'll install Node myself"). Then run `bash "<skill-dir>/scripts/install-node.sh"`. It installs [fnm](https://github.com/Schniz/fnm) into the home directory (no Homebrew, no sudo), installs Node LTS and adds a marked block to the shell rc file.
- **Package manager** → ask which one, offering only those that make sense:
  - `npm` — already comes with Node, zero extra setup.
  - `pnpm` (Recommended if the dev has no preference) — faster, less disk. Install with `source env.sh && npm install -g pnpm`. If `doctor.sh` warns about pnpm 11, offer to update it first (installs hang on 11.x); if the dev declines, recommend npm instead.
  - `yarn` / `bun` — offer only if already installed.

Verify: `source env.sh && node -v && <pm> -v` prints versions. Re-run `doctor.sh` if anything looks off.

## Phase 2 — Choose the stack

Read `references/compatibility.md` and `references/frameworks.md` first.

**Round 1 — framework only (its own `AskUserQuestion` call):**

1. **Framework**
   - Expo (Recommended) — runs on a real phone through Expo Go with no Android/iOS toolchain; the official React Native recommendation.
   - React Native CLI (bare) — full native `android/` and `ios/` folders; always needs a native build, so it runs only on the Android emulator or iOS Simulator (Expo Go can't load it).

The run-target options depend on this answer, so it must come back before you build the next question.

**Round 2 — built from the framework answer (only the questions that still have more than one valid answer):**

2. **Run target** — `multiSelect: true` (a dev may want both iOS and Android). Offer only what works for the chosen framework and OS:
   - **Expo:**
     - Phone via Expo Go (Recommended) — iPhone or Android; scan a QR code, phone and computer on the same Wi-Fi. No toolchain at all.
     - iOS Simulator — macOS only. Needs Xcode (~15 GB + ~8 GB iOS runtime). The dev downloads Xcode themselves (App Store with a free Apple ID, or the team's `.xip`). Running in the simulator needs no Apple ID or signing.
     - Android emulator — installs JDK 17 + Android SDK (~5–8 GB, 20–40 min).
     - Web browser — fastest, but not a real native environment.
   - **RN CLI:** only iOS Simulator (macOS only) and Android emulator — never Expo Go or web. Recommend whichever matches a toolchain `doctor.sh` already found (on a Mac with Xcode installed, the iOS Simulator is the quicker start). On Linux that leaves only the Android emulator: say so instead of asking.
3. **Bundler** — skip for Expo (Metro is the only supported bundler; say so in one line). For CLI:
   - Metro (Recommended) — default, simplest.
   - Re.Pack (Rspack) — for code splitting / Module Federation / super-apps; more config.
4. **Template** — see `references/frameworks.md` for the list per framework and what each contains.
5. **App name + location** — ask in plain text (not a multiple choice): app name (for CLI it must be alphanumeric, no dashes — suggest a valid one) and parent folder (default: current directory). Refuse to overwrite a non-empty folder; ask for another name instead.
6. **Design input** — if the dev's request already mentions screens ("with 5 screens: Login, Home…"), a screenshot, an image or a Figma link, record it as the design input and **don't ask**. Otherwise ask once: "Should the app start with real screens?" → *No, empty app for now (Recommended for first-timers)* / *I'll list the screens* / *I have screenshots* / *I have a Figma link*. Collect the list / images / link right after the answer. The screens are built in Phase 7b, after the empty app is proven to run.

## Phase 3 — Choose libraries

Read `references/libraries.md`. Some templates already include some of these (e.g. Expo `default` already has expo-router) — don't ask about what the template already decided; mention it instead.

One `AskUserQuestion` call, up to four questions:

- **Navigation** — expo-router (Recommended for Expo) / React Navigation (Recommended for CLI) / none
- **State** — Zustand (Recommended) / Redux Toolkit / Jotai / none
- **Server data** — TanStack Query (Recommended) / none
- **Styling** — StyleSheet only (Recommended for beginners) / NativeWind / Unistyles (RN CLI only — it needs a native build, so it doesn't run in Expo Go)

Then a second, smaller call:

- **Lint & format** — ESLint + Prettier (Recommended) / Biome / none
- **Folder structure** — Feature-first team structure from `references/structure.md` (Recommended) / keep the template as is. Ask this even with a design input: the structure is set up here during scaffolding, and rn-design-import then builds the screens inside it.
- **Code quality** (`multiSelect: true`) — Unit tests: Jest + React Native Testing Library (Recommended) / Git hooks: Husky + lint-staged (Recommended) / Commit message rules: Conventional Commits via commitlint (Recommended).

If git hooks or commit rules were chosen, one more call (`references/quality.md` lists what each option runs):

- **Before each commit** (`multiSelect: true`, staged files only) — Lint + auto-fix (Recommended) / Format (Recommended) / Related unit tests (Recommended) / Type check (slower).
- **Before each push** (`multiSelect: true`) — Type check (Recommended) / All unit tests (Recommended) / Block direct pushes to main.
- **Commit message format** — Conventional Commits, e.g. `feat: add cart` (Recommended) / No check. Custom formats (Jira keys, required scope) come in through "Other".

Offer lint/format items only if a linter was chosen above, test items only if unit tests were.

## Phase 4 — Platform toolchain (only if needed)

Skip this phase entirely when the run targets are only Expo Go and/or web. Do Android and iOS independently — whichever targets were picked.

### Android emulator

1. Explain what will be installed and roughly how big it is: JDK 17 ~200 MB, Android SDK + emulator + system image ~3–4 GB. For RN CLI, the first Gradle build also pulls the NDK, CMake and Gradle caches, another ~3 GB. Check free disk space first (`df -h ~`) and warn if under ~15 GB.
2. The Android SDK requires accepting Google's license terms. Ask the dev explicitly: "The Android SDK requires accepting the Android SDK License Agreement (https://developer.android.com/studio/terms). Do you accept?" Only continue on a clear yes — that acceptance is theirs to give, not yours.
3. Run in the background (it can take a long time):
   ```bash
   bash "<skill-dir>/scripts/install-android.sh" --accept-licenses
   ```
   It installs JDK 17 (Temurin) if no JDK 17 exists, the Android command-line tools, platform-tools, emulator, Android 15 (API 35) platform and system image, creates an AVD named `rn_pixel`, and writes `JAVA_HOME` / `ANDROID_HOME` to the shell rc file. It is idempotent — rerunning only fills gaps.
4. Verify with `bash "<skill-dir>/scripts/doctor.sh" --android` — every Android line must be `ok`.

### iOS Simulator (macOS only)

Xcode is the only way to get the iOS Simulator. Three steps belong to the dev, because they need an Apple ID or the Mac's admin password: downloading Xcode, pointing `xcode-select` at it, and accepting Apple's Xcode license. Everything else the script does.

1. Run:
   ```bash
   bash "<skill-dir>/scripts/setup-ios.sh"            # Expo
   bash "<skill-dir>/scripts/setup-ios.sh" --cocoapods  # React Native CLI
   ```
2. **Exit code 2** means it is waiting on the dev. It prints the exact steps under `ACTION REQUIRED`. Relay them in plain words:
   - **Xcode missing**: the dev installs it from the App Store (a free Apple ID is enough; no paid developer account) or from the team's `.xip`. Then they open Xcode once. The download is ~15 GB, so say it will take a while and that you'll continue when they're back.
   - **`sudo xcode-select …` / `sudo xcodebuild -license accept` / `sudo xcodebuild -runFirstLaunch`**: the dev runs these in their own terminal (they ask for the Mac password). Point out that `-license accept` means *they* accept Apple's Xcode license. Never run `sudo` yourself, and never accept the license on their behalf.
   - **Homebrew missing** (only with `--cocoapods`): macOS's built-in Ruby is too old for CocoaPods, so the dev installs Homebrew with the printed command. The script then installs CocoaPods with it.

   When the dev says they're done, rerun the same command. Repeat until it exits 0.
3. Run the iOS Simulator runtime download in the background. If it is missing, the script downloads it (~8 GB).
4. Verify with `bash "<skill-dir>/scripts/doctor.sh" --ios` (`--cocoapods` for CLI). Every iOS line must be `ok`.

## Phase 5 — Confirm the plan

Show the dev a summary of every choice and every command you are about to run, e.g.:

| | |
|---|---|
| Framework | Expo SDK (latest) |
| Package manager | pnpm |
| Template | default (expo-router, TypeScript) |
| Libraries | zustand, @tanstack/react-query |
| Styling | StyleSheet |
| Lint | ESLint + Prettier |
| Run on | Phone via Expo Go |
| Location | ./my-app |

Ask one question: "Create the project? (Recommended: Yes)" / "Change something". If they want to change something, go back to the relevant phase only.

## Phase 6 — Scaffold

Follow `references/frameworks.md` for the exact create command for the chosen framework + package manager, then:

1. Create the project (non-interactive flags only — prompts inside a Bash call will hang). Right after creating, record a baseline of any errors the template itself has (see "Verify" in `frameworks.md`), so later checks only flag problems you introduced.
2. If pnpm: create `pnpm-workspace.yaml` containing `nodeLinker: hoisted` and `strictDepBuilds: false` (exact command and why in `references/frameworks.md`) **before** installing (React Native's Metro and autolinking expect a flat `node_modules`). Use this file rather than `.npmrc` — npm prints a warning on every `npx` call when it sees pnpm-only keys in `.npmrc`.
3. Install chosen libraries using the commands in `references/libraries.md`. For Expo always use `npx expo install <pkg>` so versions match the SDK.
4. Apply the folder structure from `references/structure.md` if chosen: move the template's theme into `src/theme/`, turn the demo home into the first feature with a one-line route file, and add the ESLint boundary rules. Move existing template files rather than duplicating them, update imports, and run `npx eslint src`.
5. Set up lint/format if chosen.
   - CLI with the iOS Simulator as a target: install the iOS native dependencies with `cd ios && pod install`. It was skipped at create time with `--install-pods false`. Run it after adding libraries, because new native modules need it too. The first run downloads React Native's prebuilt core and takes ~3–5 min, so run it in the background. The CLI's own output suggests `bundle install && bundle exec pod install`; ignore that and use plain `pod install` from Homebrew (macOS's Ruby is too old for the bundler path).
6. Verify before running it — the exact commands are under "Verify" in `references/frameworks.md`:
   - Expo: `npx expo-doctor` must pass, and `npx expo export --platform android` must bundle. Together they prove the dependencies line up and the JS compiles, without needing a phone.
   - CLI: `npx tsc --noEmit` (compare against the baseline); the first native build in Phase 7 is the real check.

If a step fails, read `references/troubleshooting.md` before improvising. Fix, then rerun the same verification.

Write `.rn-starter.json` at the project root with the recorded choices, so later skills (rn-design-import) generate code that matches:

```json
{ "framework": "expo", "template": "default", "packageManager": "pnpm", "bundler": "metro",
  "navigation": "expo-router", "state": "zustand", "serverData": "tanstack-query",
  "styling": "stylesheet", "lint": "eslint-prettier", "runTargets": ["ios-simulator"],
  "quality": { "unitTests": "jest-rntl", "preCommit": ["lint", "format", "related-tests"],
               "prePush": ["typecheck", "test"], "commitMsg": "conventional" },
  "createdWith": "rn-starter 0.2.0" }
```

Make sure the project is a git repo (Expo already ran `git init`; for CLI, created with `--skip-git-init`, run `git init` now). Then, if any code-quality option was chosen, set it up with `scripts/setup-quality.sh` and run the checks in "Verify" — both in `references/quality.md`. Apply any custom ("Other") rules on top of the generated files before verifying.

Commit the scaffold as the first commit with the message `chore: scaffold app with rn-starter`. With hooks installed, this commit runs through them — it is the end-to-end check that they work.

## Phase 7 — Run it

Run the app on **every** target the dev picked in Phase 2, not just the first one — a dev who selected iOS Simulator, Android emulator and Expo Go expects to see the app in all three. Go through them one at a time, in the order they were listed:

- **Expo:** start the dev server for one target, confirm the first screen, stop it, then start it for the next (`--ios`, then `--android`, then plain `npx expo start` for a phone). Sequential runs avoid two Metro servers competing for port 8081. Leave the dev's main target running at the end.
- **RN CLI:** one `npx react-native start` serves both platforms; run `run-ios` and `run-android` against it one after the other.
- **Phone via Expo Go:** you can't see the phone. Show the QR code/`exp://` URL and ask the dev (one `AskUserQuestion`: *I see the app* / *It doesn't load* / *Skip the phone for now*). "It doesn't load" → `--tunnel` and troubleshooting.

Keep a small checklist of targets with their status (✓ running / ✗ failed + why / skipped by the dev) and show it in Phase 8.

| Target | Command | What the dev does |
|---|---|---|
| Expo Go | `npx expo start` (background) | Install **Expo Go** from App Store / Play Store, scan the QR code shown in the terminal. If the phone cannot connect, retry with `npx expo start --tunnel`. |
| Web | `npx expo start --web` (background) | Open the printed localhost URL. |
| Android emulator (Expo) | `bash scripts/start-emulator.sh` then `npx expo start --android` | Watch the emulator open the app. |
| Android emulator (CLI) | `bash scripts/start-emulator.sh`, then `npx react-native start` (background) and `npx react-native run-android --no-packager` | First build takes 5–15 min (Gradle, NDK and CMake download; ~7 min measured on a fast Mac). |
| iOS Simulator (Expo) | `bash scripts/start-simulator.sh` then `npx expo start --ios` (background) | Nothing, usually. Expo installs Expo Go into the simulator (~100 MB download the first time) and opens the app. If iOS shows "Open in Expo Go?" (Expo pre-approves this, but it can fail; look for `Could not update simulator linking permissions` in the log), the dev clicks *Open* once. |
| iOS Simulator (CLI) | `bash scripts/start-simulator.sh`, then `npx react-native start` (background) and `npx react-native run-ios --udid <udid printed by start-simulator.sh> --no-packager` (background) | First build takes 5–10 min (Xcode compiles all native code). |

Long-running servers (`expo start`, `react-native start`) go in the background. Don't set `CI=1` on them (it disables reloads). For CLI, always pass `--no-packager` to `run-ios`/`run-android`: without it the CLI opens a separate Terminal window to start its own Metro, which collides with the one you already started. Expo Go's QR code is printed in the dev server output — show the dev the URL (`exp://…`) too, since they can type it into Expo Go if scanning fails.

The run is done when the app's first screen is visible **on every selected target**. If one can't be done (missing toolchain, build failure you couldn't fix, the dev skipped it), it stays ✗ or skipped in the checklist — say so plainly in the hand-off and offer to finish it; never report the run as complete with a selected target untried. A white screen or a "Downloading x%" bar right after launch just means the JS bundle is still loading; wait ~10 s and look again before debugging. Ask the dev to confirm they can see it (or take a screenshot and look at it yourself: Android `adb exec-out screencap -p > screen.png`, iOS `xcrun simctl io booted screenshot screen.png`). Do not declare success from a build log alone.

## Phase 7b — Build the screens (only with a design input)

The empty app now runs, so the toolchain is proven. Hand over to the **rn-design-import** skill with the recorded design input (screen list, image paths, or Figma link) and the project path. It reads `.rn-starter.json`, writes `docs/design-spec.md` for the dev to approve, generates theme, fonts, components, screens and navigation, and verifies each screen on the already-running simulator/emulator. Continue with Phase 8 when it reports back.

If the skill isn't available, tell the dev the screens weren't generated and finish the hand-off with the empty app.

## Phase 8 — Hand-off

1. Append a **"Getting started"** section to the project README with: the stack chosen, how to start the app next time, how to run tests, and how to open a new terminal so PATH changes apply (`source ~/.zshrc` or open a new terminal window). If hooks or commit rules were set up, add the **commit rules** section from `references/quality.md`, so the whole team knows what runs on commit and push.
2. Show the run-target checklist from Phase 7 (each target ✓ / ✗ / skipped).
3. Tell the dev in 3–5 lines: what was installed, where the project is, the command to run it again on each target, and one suggested next step (e.g. "edit `src/app/index.tsx` and save — the app reloads").

## When things go wrong

- Read `references/troubleshooting.md` — it covers the errors that show up most on fresh machines (Expo Go SDK mismatch, phone can't reach Metro, port 8081 busy, `SDK location not found`, `JAVA_HOME` wrong, emulator won't boot, pnpm "Unable to resolve module", too many open files).
- Anything needing `sudo` or a password: give the dev the exact command to run in their own terminal and wait. Never try to work around a password prompt.
- If a download source or CLI flag seems to have changed, check `<tool> --help` or the official docs before guessing — these tools change often.
