# rn-starter-skills

Claude Code plugin (`rn-starter`) with two skills for React Native developers. User docs are in `README.md`. Everything in this repo is written in English; the skills themselves talk to each developer in the language that developer uses.

- `skills/rn-starter/` — wizard: clean machine → running RN app. Checks env (`doctor.sh`), installs Node via fnm (no Homebrew/sudo), asks framework (Expo / RN CLI; Rock deliberately excluded), bundler (Metro / Re.Pack), template, libraries, run target (Expo Go on phone / iOS Simulator / Android emulator / web), scaffolds, writes `.rn-starter.json`, runs the app. Phase 7b hands off to rn-design-import when the dev gave a screen list, screenshots or a Figma link.
- `skills/rn-design-import/` — design → themed, navigable screens in an existing RN/Expo project. Inputs: text list of screens, screenshots (`palette.py` for exact colors), Figma (MCP first; when MCP is missing or rate-limited, read Figma in a browser with `scripts/figma-panel.js`). Writes `docs/design-spec.md` for approval, then theme → Google Fonts (`google-font.sh`) → shared components → feature data layer → screens → navigation, then verifies each screen by deep link + screenshot.
- Structure (both skills): feature-first — thin route files re-exporting screens, `features/<domain>/{screens,components,api.ts,hooks.ts,store.ts,mocks.ts,types.ts,index.ts}`, shared `components/ theme/ lib/ utils/`, tests next to code, boundaries enforced by `no-restricted-imports` (see `skills/rn-starter/references/structure.md`).

## Decisions already made (don't relitigate)

- Expo is the default; RN CLI is the advanced option. Re.Pack only with CLI.
- pnpm uses `pnpm-workspace.yaml` with `nodeLinker: hoisted` (not `.npmrc`, which makes npm warn).
- iOS: Xcode download, `sudo xcode-select`, `sudo xcodebuild -license accept` are the dev's steps; `setup-ios.sh` exits 2 with exact commands. CocoaPods via Homebrew (`brew install cocoapods`); macOS system Ruby 2.6 is too old.
- Android: JDK 17 (Temurin) + command-line tools, no Android Studio; the dev must explicitly accept the SDK license before `install-android.sh --accept-licenses`.
- Code quality is part of the wizard (Phase 3 questions, `setup-quality.sh` in Phase 6): Jest + RNTL 14 (async API: `await render`, `userEvent`), Husky with pre-commit (lint-staged: eslint --fix, prettier, related tests), pre-push (tsc, jest, protect main), commitlint (conventional, or custom like Jira keys via "Other"). Commit the scaffold BEFORE installing hooks (templates may fail lint). Never leave a type-check hook on a project that fails tsc (script exits 3).
- pnpm: `strictDepBuilds: false` in `pnpm-workspace.yaml` (pnpm 11+ otherwise fails on skipped install scripts). pnpm 11.x hangs after "Done" (keeps registry sockets open) — doctor warns, recommend updating to 12.
- TypeScript 6 doesn't auto-load `@types/*`: `jest-env.d.ts` with `/// <reference types="jest" />`.
- Special components (map, sheet, charts, camera…): real library chosen with the dev, per framework (Expo vs CLI), checked live with `lib-info.sh` (unmaintained → never; New Arch required on RN 0.82+), wrapped in a feature component. `@react-native-community/geolocation` is unmaintained — on CLI use `expo-location` via `install-expo-modules`.
- Figma Starter/free plans allow ~6 MCP calls/month → frugal call plan, browser fallback reads the properties panel (HTML) for exact values.
- Versions verified 2026-10: Expo SDK 58, RN 0.88, Node 24 LTS, JDK 17, Android API 35, Xcode 26.6 / iOS 26.5 (see top of `skills/rn-starter/references/compatibility.md`).

## Testing done

- Simulated clean machine with `env -i HOME=<empty dir> PATH=/usr/bin:/bin bash <script>`: install-node, install-android (+ AVD), Expo + pnpm, RN CLI + pod install + run-ios, Expo/CLI on Android emulator — all reached the app's first screen.
- rn-design-import, text input ("5 screens: Login, Home, Search, Detail, Profile") run end to end by a subagent on the iOS Simulator; its 14 findings were fixed in the references.
- Figma browser fallback tried manually on the dev's "Grocery App" file (palette #33907C/#F6F9FF…, Montserrat): works.

## Not tested yet / next steps

1. The user is testing the full flow in Claude desktop (Code tab), scenarios: A) new app, no design; B) 5 screens by text; C) Figma link via browser fallback. Fix the skills from their feedback.
2. Untested branches: Re.Pack, Ignite, NativeWind, Unistyles, Linux, Figma via MCP end to end, screenshot input end to end, a truly clean Mac (new macOS user or Tart VM).
3. Quality tooling tested on an Expo SDK 58 + pnpm 12 project (hooks, commitlint incl. a Jira rule, RNTL tests) — not yet on RN CLI or npm/yarn.
4. Nothing is committed yet (branch `feat/rn-starter-skill`).

## Working on this repo

- Validate after edits: `claude plugin validate .` and `bash -n skills/*/scripts/*.sh`.
- Users install locally with `claude plugin marketplace add <repo path>` + `claude plugin install rn-starter@rn-starter-skills`; after changes they run `claude plugin marketplace update rn-starter-skills` and `claude plugin update rn-starter@rn-starter-skills`.
- Keep test projects and downloads in a scratch folder, never in this repo.
