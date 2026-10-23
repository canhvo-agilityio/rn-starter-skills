# rn-starter — Spec

What this plugin is for, who it serves, and what "done" means. The how is in [DESIGN.md](DESIGN.md).

## Intent

Getting a React Native project from nothing to a running, well-structured app is slow and error-prone: a new developer spends a day installing toolchains, picks a stack by guesswork, and the first screens are built on whatever structure happened first. Design hand-off then repeats by hand — copying colors, guessing fonts, rebuilding the same navigation patterns.

`rn-starter` turns that into a conversation. A developer says *"create a new React Native app"* or *"build these screens from this Figma link"*, and Claude Code takes the machine, the stack choices, the scaffold, the screens and the verification all the way to an app running on the targets they picked — asking only what a human has to decide.

## Users

| User | Situation | What they need |
|---|---|---|
| New mobile developer | Fresh laptop, little RN experience | Environment installed for them; plain-language questions with safe defaults; an app that runs |
| Experienced developer | Starting a new project | Fast stack selection, the team's structure and quality tooling, no boilerplate typing |
| Developer on an existing app | Designer sent new screens | Screens built from a description, screenshot or Figma, matching the project's own conventions |
| Developer shipping to testers | The app runs; testers install builds from TestFlight and Google Play internal testing; the store accounts often belong to the client | EAS set up once, every credential on EAS from the files the client provides, a clear list of what's left |
| Developer whose backend is ready | Screens run on mocks; the backend team shared a Swagger/OpenAPI link | Typed calls to the real API without touching the screens; mocks kept for offline work and tests |
| Team lead | Onboarding several people | The same structure, tooling and conventions in every project |

## Goals

1. **Clean machine → running app** on macOS, Windows and Linux, installing missing tools itself (per user, no admin where possible).
2. **Stack chosen by the developer, guided:** every question has a recommended answer; only combinations that work are offered.
3. **Team-quality scaffold:** layered structure with enforced import rules, theme tokens, unit tests, git hooks, commit rules, and Claude Code files (`CLAUDE.md`, format-on-edit hook, review subagent).
4. **Design → screens:** from text, screenshots or Figma to themed, navigable screens with mock data behind a clean data seam, approved by the developer as a spec before code is written.
5. **Mocks → real API:** services switched to the backend one domain at a time from its OpenAPI spec, with types generated from it, so a backend change shows up as a type error, not a crash on a user's phone.
6. **Store-ready credentials:** EAS, identity, profiles, and build / submit / push credentials set up once from whatever the developer or the client provides — the Credentials page complete — without secrets passing through the conversation.
7. **Verified, not assumed:** the app is run and looked at (screenshots) on every selected target before anything is reported as done.

## Non-goals

- Store listing content (screenshots, descriptions), App Review, in-app purchases. Store accounts themselves: the skills use the developer's or client's accounts and never create or pay for them.
- Sign-in, token storage and refresh (`rn-auth`, planned), forms and validation (`rn-forms`, planned). `rn-api-connect` only leaves a seam for the auth header.
- Real-time (websockets), offline sync, file uploads beyond a plain multipart call, GraphQL.
- Per-build environments (dev / staging / prod builds): one `EXPO_PUBLIC_API_URL` in `.env`; build profiles belong to `rn-release`.
- Pixel-perfect reproduction at any cost — close to the design, on tokens, with approximations written down.
- Restructuring an existing codebase without the developer asking.

## Scope

### Skill 1 — `rn-starter`

| Area | Requirement |
|---|---|
| Environment | Detect OS/arch and tools (`doctor`); install Node LTS, package manager, JDK 17, Android SDK + emulator + AVD, Xcode runtime/simulator setup, CocoaPods. macOS/Linux via bash, Windows via PowerShell twins called automatically. |
| Human steps | Stop only for what needs a person (admin/sudo, Apple ID, reboot, license acceptance, file access), print the exact steps, and keep doing everything else meanwhile. |
| Questions | Framework (Expo / RN CLI) → run targets filtered by framework and OS → bundler (Metro / Re.Pack, CLI only) → template → app name/location → design input → libraries (navigation, state, server data, styling) → lint/format → structure → UI component library (React Native Paper, only with StyleSheet) → code quality (tests, hooks, commit rules, Claude Code files). Dependent questions asked in a later round than the answer they depend on. "Other" answers are turned into concrete config, shown to the developer, verified. |
| Scaffold | Create the project non-interactively; pnpm workarounds; layered structure with ESLint import rules; `.rn-starter.json` recording every choice. |
| Quality | Jest + React Native Testing Library, Husky (pre-commit via lint-staged, pre-push), commitlint; refuse to leave a type-check hook on a project that fails `tsc`. Claude Code files: `CLAUDE.md`, a `PostToolUse` format/lint hook, a `code-reviewer` subagent. |
| Run | Every selected target, one by one; checklist ✓/✗/skipped in the hand-off. |
| Hand-off | README "Getting started" and commit rules; hand over to `rn-design-import` when there's a design. |

### Skill 2 — `rn-design-import`

| Area | Requirement |
|---|---|
| Inputs | Text description, screenshots/images, Figma (MCP; browser reading when the MCP is missing or out of calls; duplicate request for Community/foreign files) — any mix. |
| Understanding the project | Read `.rn-starter.json` / `package.json` / file tree; follow existing conventions; keep 1.x feature-first projects as they are; offer to move a flat project to the layered layout instead of restructuring silently. |
| Spec | `docs/design-spec.md` (screens, navigation tree, tokens, fonts, special components, shared components, assets, open points) approved before code generation. |
| Generation | Theme tokens → Google Fonts → assets → shared components (+ tests) → data layer (types, mocks, services, hooks, tested logic) → special components (real libraries, wrapped) → screens → navigation. |
| Special components | Maps, sheets, charts, camera, video, pickers…: library suggested per framework, checked live for maintenance, New Architecture and Expo Go support. |
| Verification | Deep link to every screen, screenshot, compare with the design on the main target; platform check on every other target; tap through the main flow. |

### Skill 3 — `rn-api-connect`

| Area | Requirement |
|---|---|
| Inputs | **OpenAPI 3.x or Swagger 2.0** — a Swagger UI link, a spec URL or a file (main path, tested for real). Postman collection or a plain description of endpoints: basic support, types written by hand. |
| Understanding the project | Read `.rn-starter.json` and the layout; list every domain (`services/<domain>.ts`) with its hook, mock and whether it already calls an API. Works on projects not made by rn-starter if they have a service seam; otherwise offer to add one first. |
| Spec handling | Find the spec behind a Swagger UI page, convert 2.0 to 3.x, save it in the project (`docs/api/openapi.json`), report quality problems (missing response schemas, missing `operationId`, everything optional) instead of generating wrong types silently. URL behind VPN or login → ask the dev for the file. |
| Plan | `docs/api-plan.md`: per domain the endpoints, the DTO → app-type mapping, pagination, mutations and cache invalidation, what stays mocked and why. Approved before code changes. |
| Generation | Infrastructure once (`env.ts`, `.env.example`, generated `types/api.gen.ts` + `api:types` script, HTTP client, `ApiError`, mock flag); then per domain: mappers with tests → service → hook (pagination, mutations) → loading / error / empty states on the screens that show it. |
| Mocks | Kept behind `EXPO_PUBLIC_USE_MOCKS`; still used by tests; imported nowhere else. |
| Verification | App against the real API (or a local server) on the main target: every affected screen opened and screenshotted with real data; error state with the server unreachable; one mutation round-trip; then the platform pass on the other targets. |

### Skill 4 — `rn-release-setup`

| Area | Requirement |
|---|---|
| EAS first | States up front that it builds and submits with EAS (Expo and RN CLI); checks eas-cli and the login (the developer logs in themselves); asks which account or organization owns the project (client's organization recommended); `eas init`, `eas.json`; cloud or local builds. Projects that don't want EAS: out of scope, said plainly. |
| Identity | Bundle id / package proposed from the app name and the developer's domain, with the warning that it can't change after a store release; an app already on a store keeps its bundle id and keystore. |
| Profiles and environments | `production`, plus `staging` when test builds use another API; `appVersionSource: remote` + `autoIncrement`; API URLs asked and stored as EAS environment variables (`.env` never opened); `expo-updates` with a channel per profile and a fingerprint runtime version; `ITSAppUsesNonExemptEncryption`. |
| Credentials | The skill lists what it needs (iOS: App Store Connect API key `.p8` + key id + issuer id + team id, or `.p12` + App Store `.mobileprovision`; Android: the upload keystore when the app is already on Play, a service account key; per feature: APNs key, `google-services.json`…). The developer puts the files in a folder; `scan-credentials.sh` identifies them by name, extension and header without printing contents, checks git ignores them, reads only public data (`.mobileprovision` bundle id and expiry). Missing items → how to get them, and a message for the client. Passwords are typed by the developer into EAS, never into the chat. |
| Credential rounds | Build (certificate + profile / upload keystore), then submit (App Store Connect API key / Google service account), then push only if the app uses it (APNs key / FCM V1 key + `google-services.json` + the app's push config). The developer uploads anything secret; the skill prepares the command and checks. |
| Done when | The project's Credentials page on expo.dev has every item of the plan for each platform (checked with the developer), and what blocks the first submit outside EAS (app records, the first manual Play upload, the service account's Play permissions) is listed with an owner. A test build + submit is offered, not required; skipped → "set up, not proven by a build". Other features needing store setup (Google Sign-In, Maps, links, Sentry) are listed, not set up. |
| Hand-off | `docs/release-plan.md` for `rn-release`: owner, profiles, environments, credentials per round with status, outside-EAS items with owners, fingerprints, test build result. |

## Acceptance criteria

A run is successful when:

- [ ] A developer who accepts every recommended answer ends with a running app on every target they selected, without installing anything by hand except the documented human steps.
- [ ] No offered option leads to a combination that can't work (e.g. RN CLI + Expo Go, iOS Simulator on Windows).
- [ ] The generated project passes `tsc --noEmit`, ESLint (including boundary rules) and its unit tests; hooks block a bad commit message and pass a good one.
- [ ] Route files are one-line re-exports; UI files import data only through hooks; no mock imports outside `services/` and tests.
- [ ] With the Claude Code option: the format hook fixes an edited file and returns an import-rule violation to Claude; `code-reviewer` is listed as a subagent.
- [ ] With a design input, `docs/design-spec.md` exists and was approved, every screen opens by deep link, and each screen's verification status lists the targets it was checked on.
- [ ] With `rn-api-connect`: no screen file changes except loading / error / empty states and load-more on paginated lists; `tsc` passes against the generated API types; every switched domain is verified against the API on the main target; with `EXPO_PUBLIC_USE_MOCKS=1` the app still runs fully offline; regenerating types after a backend change reports the affected mappers as type errors.
- [ ] With `rn-release-setup`: no credential file is opened or printed and none is committed; the Credentials page holds every planned item for the platforms the developer has files for; a new keystore is never generated for an app that is already on Google Play.
- [ ] Anything not done or approximated is stated in the hand-off — never implied as done.

## Status

| Area | macOS | Windows | Linux |
|---|---|---|---|
| Environment install (Node, Android) | ✓ verified on a simulated clean home | ✓ clean machine, end to end | scripts shared with macOS, not run |
| Expo on iOS Simulator / Android emulator | ✓ | ✓ Android emulator | pending |
| RN CLI on iOS Simulator / Android emulator | ✓ | pending | pending |
| Quality tooling (Jest, Husky, commitlint, custom rule) | ✓ on Expo + pnpm | pending | pending |
| Design import from Figma | ✓ (browser panel reading) | ✓ clean machine, end to end | — |
| Design import from text | ✓ (subagent run, 14 findings fixed) | pending | — |
| Figma via browser panel reading | ✓ manual | — | — |
| API connect (`rn-api-connect`) | ✓ two subagent runs on coffee-shop against a local OpenAPI test API (iOS Simulator + Android emulator: API data, favorites mutation, 404, unreachable API, empty list, mock mode; `.env` left unopened); scripts also checked on Petstore (Swagger UI, 2.0, YAML). Not run: a phone, iOS taps, Postman/description inputs | pending | — |
| Release setup (`rn-release-setup`) | Android **build** credentials ✓ on a prototype (personal Expo account): `eas init`, profiles, EAS env var, expo-updates, EAS-generated upload keystore, cloud store build → `.aab` signed with it. **Not run**: the Google service account for EAS Submit (needs a Play Console app), the FCM V1 key and push (the test app doesn't use push), iOS (needs an Apple Developer account), a client-provided keystore, a subagent run of the whole SKILL.md | pending | — |
| Not yet exercised anywhere | Re.Pack, Ignite, NativeWind, Unistyles, Figma MCP end to end, screenshot input end to end, special-components flow, a truly clean Mac | | |

Evidence (screenshots, recordings) goes in [`docs/evidence/`](docs/evidence/).
