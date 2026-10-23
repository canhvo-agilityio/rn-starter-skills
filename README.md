# rn-starter

A Claude Code plugin for React Native developers, with four skills:

| Skill | Use when | Result |
|---|---|---|
| **`rn-starter`** | There's no project yet, often on a brand-new machine | Environment installed, project running on a simulator, emulator or phone |
| **`rn-design-import`** | A project exists (or `rn-starter` just created one) | Theme, fonts, components, screens and navigation built from a design |
| **`rn-api-connect`** | Screens run on mocks and the backend has a Swagger / OpenAPI spec | Types generated from the spec, a typed client, services switched to the API one domain at a time, loading / error / empty states — screens otherwise unchanged |
| **`rn-release-setup`** | The app runs and is about to go to testers on TestFlight / Google Play internal testing | EAS project, identity, build profiles and environments, build / submit / push credentials on EAS from the files the developer or client provides, a list of what's left outside EAS |

Developers just describe what they want. For example, *"Create a new RN app with 5 screens: Login, Home, Search, Detail, Profile"*: `rn-starter` scaffolds the project, runs the empty app, then hands over to `rn-design-import` to build the screens.

The wizard talks to the developer in the language they write in.

More: [spec.md](spec.md) (intent, scope, acceptance criteria, test status) · [DESIGN.md](DESIGN.md) (architecture and design decisions) · [docs/evidence/](docs/evidence/) (screenshots and recordings of real runs).

## rn-starter: clean machine → running app

1. Inspect the machine (git, Node, package manager, plus JDK/Android SDK and Xcode/iOS Simulator when needed)
2. Install what's missing (Node via fnm, no Homebrew or sudo needed)
3. Ask the developer: **Expo / RN CLI** → **Metro / Re.Pack** → template → libraries (navigation, state, data, styling, UI library, lint, structure) → **code quality** (Jest + React Native Testing Library, Husky + lint-staged with pre-commit/pre-push rules, commitlint, Claude Code files) → run on **a real iPhone/Android phone (Expo Go) / iOS Simulator / Android emulator / web** → is there a design
4. Install the platform toolchain if needed:
   - Android: JDK 17, Android SDK, emulator, AVD. No Android Studio.
   - iOS Simulator (macOS only): Xcode, iOS runtime, simulator; CocoaPods for RN CLI.
5. Summarize the choices; the developer confirms
6. Scaffold the project with a standard folder structure, verify the build, write `.rn-starter.json`, set up tests and git hooks
7. Run the app and confirm the developer sees the first screen; hand over to `rn-design-import` if there's a design

## rn-design-import: design → working screens

Accepts one or a mix of:
- **A description:** *"it has Login, Home, Cart…"*
- **Screenshots / images:** exact colors read from pixels; fonts can only be guessed, so the developer confirms them.
- **Figma links:** through the Figma MCP, or by reading Figma in a browser when the MCP is out of calls. Exact colors, fonts, spacing and assets.

Steps:
1. Read the project (`.rn-starter.json` or `package.json`) so generated code follows its conventions: expo-router vs React Navigation, StyleSheet vs NativeWind.
2. Analyze the design and ask only for what's missing (how screens connect, which font).
3. Write `docs/design-spec.md` with screens, navigation tree, theme, fonts and components. **The developer approves it before any code is generated.**
4. Generate in order: theme → Google Fonts → assets → shared components (with tests when Jest is set up) → data layer (types, mocks, services, hooks) → special components → screens (mock data) → navigation.
   Special components (maps, bottom sheets, charts, camera, video…) get a real library, suggested per framework (Expo vs RN CLI) after a live check of maintenance, New Architecture and Expo Go support (`scripts/lib-info.sh`), or a placeholder if the dev prefers.
5. Run the app, open each screen by deep link, screenshot it and compare with the design; fix the differences.

UI only. Code is layered: route files are one-line re-exports of `src/screens/<name>/`, shared UI lives in `src/components/`, and screens get data through hooks in `src/hooks/` that call `src/services/` (mocked for now). ESLint stops UI files from importing services or mocks, so switching to the real API is a change to `src/services/`.

Local development only: no code signing, no paid Apple Developer account. Supports macOS, Windows and Linux (the iOS Simulator is macOS-only; on Windows the scripts run through PowerShell twins in `scripts/windows/`, installing per user without admin rights).

**Steps the developer does themselves with `rn-starter`** (the skill stops, explains, and waits):
- Download Xcode from the App Store (a free Apple ID is enough), or install it from the team's `.xip`.
- Run the `sudo` commands, e.g. `sudo xcodebuild -license accept`.
- Install Homebrew (only for RN CLI + iOS).
- Windows: turn on *Windows Hypervisor Platform* for the Android emulator (admin PowerShell command + reboot, once).
- Accept the Android SDK license.

## rn-api-connect: mocks → real API

Give it the backend's Swagger link (or an OpenAPI/Swagger file; a Postman collection or a description of the endpoints also works, with types written by hand).

1. List the app's data domains (`src/services/*`), their hooks, the screens using them, and whether each is still on mocks (`scripts/api-inventory.sh`).
2. Find the spec behind the Swagger page, convert YAML / Swagger 2.0, save it as `docs/api/openapi.json`, and summarize it: endpoints, pagination, auth, error format, and quality problems to raise with the backend team (`scripts/fetch-openapi.sh`).
3. Match each service function to its endpoint, list the differences between the API's data and the app's types, and ask only what can't be inferred (base URL, missing endpoints, auth).
4. Write `docs/api-plan.md`. **The developer approves it before any code changes.**
5. Add the infrastructure once: types generated with openapi-typescript (`<pm> run api:types`), an openapi-fetch client with timeout and an auth seam, one `ApiError`, `src/lib/env.ts` with `EXPO_PUBLIC_API_URL` and `EXPO_PUBLIC_USE_MOCKS`.
6. Connect one domain at a time: tested mappers (API shape → app type) in the service, the mock kept behind the flag, pagination and mutations in the hooks, loading / error / empty states on the screens.
7. Verify on every target against the API: real data on each screen, mutations, the error state with the API off, 404, empty lists, load-more, mock mode; boundary check (`scripts/check-mocks.sh`).

When the backend changes: refresh the spec, `<pm> run api:types`, and `tsc` points at the mappers to fix.

## rn-release-setup: ready for TestFlight and Google Play

Run once per app, before the first release. Done when the project's **Credentials page on expo.dev** has everything the app needs.

1. Read the project: identity, versions, EAS config, whether the app uses push, credential files git might pick up (`scripts/release-inventory.sh`).
2. EAS first: the developer logs in to Expo themselves; choose the owner (the client's organization is recommended); `eas init` (`scripts/eas-status.sh`).
3. Identity (bundle id / package — permanent once released), staging or not, already on a store or not, API URLs per environment (asked, never read from `.env`).
4. `docs/release-plan.md` — **the developer approves it before any change.**
5. `eas.json` profiles, remote build numbers with auto-increment, EAS environment variables, `expo-updates` with a fingerprint runtime version, the export-compliance flag.
6. Credentials in three rounds — **build** (certificate + profile, upload keystore), **submit** (App Store Connect API key, Google service account), **push** if the app uses it (APNs key, FCM V1 key). Each round: the skill lists what it needs, the developer drops the files in a folder, `scripts/scan-credentials.sh` identifies them without reading secrets, missing items get instructions and a message for the client; `scripts/eas-credentials.sh` uploads them (the developer only types passwords into a local `credentials.json`). A new Android keystore is never generated for an app already on Google Play.
7. Check the Credentials page with the developer, list what blocks the first submit outside EAS (app records, the first manual Play upload, Play permissions), and offer a test build + submit.

## Step 0 on a clean machine: install Claude Code

The native installer doesn't need Node:

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

## Install the plugin

From the team's git repository (once this repo is pushed):

```bash
claude plugin marketplace add <repo-git-url>
```

```bash
claude plugin install rn-starter@rn-starter-skills
```

Or try it straight from a local checkout:

```bash
claude --plugin-dir /path/to/rn-starter-skills
```

After pulling changes into an installed copy:

```bash
claude plugin marketplace update rn-starter-skills
```

```bash
claude plugin update rn-starter@rn-starter-skills
```

## Usage

In Claude Code, type `/rn-starter` or just ask, e.g. *"create a new React Native app"*, *"new laptop, set it up for RN"*, *"build these screens from this Figma link"*, *"connect the app to the API, here's the Swagger link"*, *"set up EAS so we can ship to TestFlight"*.

## Layout

```
.claude-plugin/
  plugin.json            # plugin manifest
  marketplace.json       # lets the team add it with `claude plugin marketplace add`
skills/rn-starter/
  SKILL.md               # wizard flow (phases 0 → 8; phase 7b hands over to rn-design-import)
  scripts/
    doctor.sh            # read-only environment check
    env.sh               # puts fnm/JDK/Android/Homebrew on PATH in the current shell
    install-node.sh      # fnm + Node LTS, adds a block to ~/.zshrc
    install-android.sh   # JDK 17 + Android SDK + emulator + AVD
    start-emulator.sh    # boots the Android emulator and waits for it
    setup-ios.sh         # Xcode/license/iOS runtime/simulator (+ CocoaPods); exit 2 = waiting on the developer
    start-simulator.sh   # boots the iOS Simulator and waits for it
    setup-quality.sh     # Jest + RNTL, Husky (pre-commit / pre-push), lint-staged, commitlint
    lib.sh               # shared helpers
    windows/             # PowerShell twins of the scripts above (doctor, env, install-node, install-android, start-emulator), used automatically on Windows
  references/
    compatibility.md     # which combinations work (used to filter options)
    frameworks.md        # create commands per framework/template
    libraries.md         # how to install each library
    structure.md         # standard folder structure
    troubleshooting.md   # common errors on fresh machines
    quality.md           # hook rules, custom rule examples (Jira keys, branch names), verification
skills/rn-design-import/
  SKILL.md               # design → UI flow (phases 0 → 6)
  scripts/
    detect-project.sh    # reads the project's stack and conventions → JSON
    palette.py           # exact colors from a screenshot (dominant colors, or the color at a point)
    google-font.sh       # adds a Google Font (Expo: expo-google-fonts; CLI: TTFs + native linking)
    ttf-name.py          # reads a font's PostScript name (so fontFamily matches on iOS and Android)
    figma-panel.js       # reads Figma's properties panel in a browser (when the MCP is out of calls)
    lib-info.sh          # live library check: npm/SDK version, New Architecture, Expo Go, maintained
  references/
    input-text.md        # analyzing a description
    input-image.md       # analyzing screenshots
    input-figma.md       # frugal Figma MCP use, web → RN translation, browser fallback
    spec-template.md     # docs/design-spec.md template
    theme.md             # color/type/spacing token structure
    fonts.md             # loading fonts on Expo / CLI
    navigation.md        # expo-router / React Navigation, deep links for verification
    verify.md            # screenshot each screen and compare with the design
    conventions.md       # defaults when the project has none
    special-components.md # maps, sheets, media, charts…: libraries per framework, native setup, verification
    follow-up.md         # adding a feature to an app that already has screens
skills/rn-api-connect/
  SKILL.md               # mocks → API flow (phases 0 → 7)
  scripts/
    api-inventory.sh     # domains, hooks, screens, mock/API status → JSON
    fetch-openapi.sh     # Swagger UI / URL / file → docs/api/openapi.json + summary; exit 2 = needs the developer
    check-mocks.sh       # boundary check: mock and DTO imports, env reads, unflagged mocks
  references/
    openapi.md           # getting the spec, reading the summary, warnings, generating types
    client.md            # env.ts, ApiError, openapi-fetch client, query retry, ESLint rule
    mapping.md           # matching functions to endpoints, DTO → app-type mappers, tests
    data-hooks.md        # pagination, mutations, invalidation, hooks without TanStack Query
    screen-states.md     # loading / error / empty, load-more, mutation errors
    verify.md            # checking against the API on each target, error/empty/mock modes
    plan-template.md     # docs/api-plan.md template
    other-inputs.md      # Postman collections and plain descriptions
skills/rn-release-setup/
  SKILL.md               # EAS + identity + profiles + build/submit/push credentials (phases 0 → 8)
  scripts/
    release-inventory.sh # identity, versions, eas.json, release features, credential files and git → JSON
    eas-status.sh        # eas-cli, Expo login, accounts, project link; exit 2 = the developer logs in
    scan-credentials.sh  # identifies .p8/.p12/.mobileprovision/keystores/Google keys without reading secrets
    eas-credentials.sh   # uploads them to EAS by driving `eas credentials` menus (expect); stops at any password prompt
    eas-credentials.exp  # the menu driver used by eas-credentials.sh
  references/
    eas.md               # login, owner, eas init, eas.json profiles, environment variables, updates, builds
    identity.md          # bundle id / package, name, version, export compliance, icon
    credentials.md       # rules, what to ask for, the folder, git
    credentials-ios.md   # build (API key / .p12 + profile / Apple ID), submit (API key), app record
    credentials-android.md # build (keystore decision), submit (service account), first upload
    client-request.md    # how each item is made, message for the client
    push.md              # who sends pushes, APNs key, FCM V1 key, google-services.json
    verify.md            # Credentials page checklist, outside-EAS list, optional test build
    plan-template.md     # docs/release-plan.md template
```

**Figma:** Figma's Starter/free plans allow very few MCP calls per month. The skill makes the minimum: one call for the frame list, one for variables, one per screen. When the MCP is out of calls or not connected, it **opens Figma in a browser** (Claude in Chrome or the built-in browser; the developer signs in). It selects frames and layers and reads exact values (hex colors, fonts, sizes, dimensions, corner radii) from the properties panel with `scripts/figma-panel.js`. This costs no API calls.

Scripts write to the shell rc file inside marked blocks (`# >>> rn-starter:<name> >>>`), so reruns never duplicate lines. Delete a block to undo it.

## Quick machine check

```bash
bash skills/rn-starter/scripts/doctor.sh --android --ios --cocoapods
```

## Updating versions

The verified versions are listed at the top of `skills/rn-starter/references/compatibility.md` (currently Expo SDK 58, React Native 0.88, Node 24 LTS, JDK 17, Android API 35, Xcode 26 / iOS 26.5). When upgrading, update that file first, then rerun the flow on a clean machine (a VM or a new macOS user).
