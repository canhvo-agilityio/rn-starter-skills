# rn-starter

A Claude Code plugin for React Native developers, with six skills:

| Skill | Use when | Result |
|---|---|---|
| **`rn-starter`** | There's no project yet, often on a brand-new machine | Environment installed, project running on a simulator, emulator or phone |
| **`rn-feature`** | A ticket arrives (Jira, GitHub issue, pasted text), with or without a design and an API spec | `docs/tickets/<id>.md`: numbered requirements (R1, R2…) traced to design and API, concerns with who decides, questions ready to send; then, on request, a plan accepted in plan mode, commits per step, bugs fixed test-first, every R# verified, and a PR mapping each R# to its evidence |
| **`rn-ui`** | A project exists (or `rn-starter` just created one) | Theme, fonts, components, screens and navigation built from a design |
| **`rn-api-connect`** | Screens run on mocks and the backend has a Swagger / OpenAPI spec | Types generated from the spec, a typed client, services switched to the API one domain at a time, loading / error / empty states — screens otherwise unchanged |
| **`rn-e2e`** | A screen or a ticket's requirements need proof in the running app | Maestro flows (one per R#), `testID`s on the elements they use, green on the simulator against mocks, JUnit report and screenshots, ready for CI |
| **`rn-release-setup`** | The app runs and is about to go to testers on TestFlight / Google Play internal testing | EAS project, identity, build profiles and environments, build / submit / push credentials on EAS from the files the developer or client provides, a list of what's left outside EAS |

Developers just describe what they want. For example, *"Create a new RN app with 5 screens: Login, Home, Search, Detail, Profile"*: `rn-starter` scaffolds the project, runs the empty app, then hands over to `rn-ui` to build the screens.

The wizard talks to the developer in the language they write in.

## rn-starter: clean machine → running app

1. Inspect the machine (git, Node, package manager, plus JDK/Android SDK and Xcode/iOS Simulator when needed)
2. Install what's missing (Node via fnm, no Homebrew or sudo needed)
3. Ask the developer: **Expo / RN CLI** → **Metro / Re.Pack** → template → libraries (navigation, state, data, styling, UI library, lint, structure) → **code quality** (Jest + React Native Testing Library, Husky + lint-staged with pre-commit/pre-push rules and protected branches, commitlint, Claude Code files) → run on **a real iPhone/Android phone (Expo Go) / iOS Simulator / Android emulator / web** → is there a design
4. Install the platform toolchain if needed:
   - Android: JDK 17, Android SDK, emulator, AVD. No Android Studio.
   - iOS Simulator (macOS only): Xcode, iOS runtime, simulator; CocoaPods for RN CLI.
5. Summarize the choices; the developer confirms
6. Scaffold the project with a standard folder structure, verify the build, write `.rn-starter.json`, set up tests and git hooks. With ESLint it adds code rules against sloppy shortcuts (`any`, casts through `unknown`, `@ts-ignore`, leftover `console.log`, empty `catch`, color literals in UI files). The Claude Code files add `CLAUDE.md` with a *Verifying your work* table, a format hook, a guard hook (no pushes to protected branches, no `.env` or credential files, no hand edits to generated files), and two subagents: `code-reviewer` and `verifier` (runs the app and checks the change, report only)
7. Run the app and confirm the developer sees the first screen; hand over to `rn-ui` if there's a design

## rn-feature: ticket → analysis → pull request

Give it a ticket: a GitHub issue, Jira (through a connected Jira connector, or pasted), or plain text, plus the design and the API spec when there are any (links in the ticket are picked up).

**Analyze** ("analyze this ticket"):
1. Map the project: routes with their URL paths and screens, shared components, data domains, signs of sign-in, and the docs already there, including other tickets and the files they touch (`scripts/project-map.sh`).
2. Read the ticket: title, body, comments, the acceptance criteria it can spot and the Figma / image / Swagger links (`scripts/fetch-ticket.sh`). The ticket is never edited.
3. Number the acceptance criteria R1…Rn: one testable behavior each, in the ticket's words. Nothing is invented: what seems missing becomes a question.
4. Match each R# to the design (frames, elements, states) and the API (endpoint, parameters, fields shown vs returned, auth, errors).
5. Write `docs/tickets/<id>.md`: traceability table, concerns C# (between what, severity, owner), questions Q# grouped by owner with a recommended answer, scope (screens, components, data, files likely touched). `scripts/check-ticket.sh` checks the file's contract.
6. Several tickets: one subagent each, then the overlaps between them and the order to build them in.

Rerun it when answers come back: R# keep their numbers, answered concerns become `resolved`.

**Build** ("build / implement / fix this ticket"):
1. Ready check: no blocking concern; open `decide` concerns are built on their recommended answers only if the dev says so, and are listed as assumptions.
2. A plan of small steps in **plan mode** (what, which skill, which R#, which files, how it's checked). The dev accepting it is the approval; it goes into the ticket file.
3. A branch in the project's naming; each step handed to `rn-ui` (screens), `rn-api-connect` (data, sign-in) or `rn-e2e` (flows per R#) with one handoff contract (no repeated questions or approvals, a report back), checked and committed in the project's format.
4. Bugs test-first: the failing test is committed and locked (`scripts/lock-tests.sh`; rn-starter's guard refuses edits to it), the fix makes it pass untouched.
5. Verify: the project's checks, `code-reviewer`, then `verifier` in the app R# by R#; the Evidence table records each result.
6. A pull request from the ticket file (`scripts/ticket-pr.sh`: R# → evidence, decisions, assumptions, what's not verified), pushed only on the dev's yes, never merged by the agent.

## rn-ui: design → working screens

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

## rn-e2e: end-to-end flows with Maestro

1. Check Maestro (installs it with the dev's yes: official installer into `~/.maestro`, JDK 17 only if missing), booted devices, how the app opens (Expo Go or a build: bundle id, package, scheme), existing flows (`scripts/e2e-doctor.sh`).
2. One flow per requirement: from a ticket's R# or the dev's list; an R# that isn't visible end to end gets a unit test instead.
3. `testID`s (`<screen>-<element>`) on the elements the flows use; shared components pass a `testID` prop through. Nothing else in the app changes.
4. Flows in `.maestro/<ticket>/r<n>-<slug>.yaml`, tagged with the ticket and the R#, opening their screen through a subflow that restarts the app, waiting with `extendedWaitUntil`, asserting by id. No hard-coded URL, bundle id or coordinate: `${APP_ID}` and `${APP_URL}` come from the run (`scripts/check-flows.sh` checks it, and which R# have no flow).
5. Run on the simulator against mock data (`scripts/run-flows.sh`, `--start-server` starts the dev server with the variables the flows rely on, from `.maestro/dev-server.env`): JUnit report, screenshots, a JSON summary per flow, and a hint when every flow fails at once (usually the setup, not the flows). A red flow is fixed when the flow is wrong and reported when the app is.
6. `e2e:ios` / `e2e:android` scripts and a `.maestro/README.md`; CI runs the same flows on a build (`references/ci.md`, wired by `rn-pipeline`).

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

Needs [Claude Code](https://claude.com/claude-code) (`claude --version`).

```bash
claude plugin marketplace add canhvo-agilityio/rn-starter-skills
claude plugin install rn-starter@rn-starter-skills
```

Restart Claude Code, then check that the four skills are listed: `claude plugin list` shows `rn-starter@rn-starter-skills` as enabled.

To get a newer version later (the version number may not change between pushes, so reinstall):

```bash
claude plugin marketplace update rn-starter-skills
claude plugin uninstall rn-starter@rn-starter-skills
claude plugin install rn-starter@rn-starter-skills
```

Or try it straight from a local checkout:

```bash
claude --plugin-dir /path/to/rn-starter-skills
```

## Usage

In Claude Code, type `/rn-starter` or just ask, e.g. *"create a new React Native app"*, *"new laptop, set it up for RN"*, *"build these screens from this Figma link"*, *"connect the app to the API, here's the Swagger link"*, *"set up EAS so we can ship to TestFlight"*, *"analyze ticket PROJ-412"*, *"build ticket PROJ-412"*, *"write E2E tests for the checkout flow"*.

## Layout

```
.claude-plugin/
  plugin.json            # plugin manifest
  marketplace.json       # lets the team add it with `claude plugin marketplace add`
skills/rn-starter/
  SKILL.md               # wizard flow (phases 0 → 8; phase 7b hands over to rn-ui)
  scripts/
    doctor.sh            # read-only environment check
    env.sh               # puts fnm/JDK/Android/Homebrew on PATH in the current shell
    install-node.sh      # fnm + Node LTS, adds a block to ~/.zshrc
    install-android.sh   # JDK 17 + Android SDK + emulator + AVD
    start-emulator.sh    # boots the Android emulator and waits for it
    setup-ios.sh         # Xcode/license/iOS runtime/simulator (+ CocoaPods); exit 2 = waiting on the developer
    start-simulator.sh   # boots the iOS Simulator and waits for it
    setup-quality.sh     # Jest + RNTL, Husky (pre-commit / pre-push, protected branches), lint-staged, commitlint
    setup-claude.sh      # CLAUDE.md, format + guard hooks, code-reviewer + verifier subagents; --update-agents for older projects
    lib.sh               # shared helpers
    windows/             # PowerShell twins of the scripts above (doctor, env, install-node, install-android, start-emulator), used automatically on Windows
  references/
    compatibility.md     # which combinations work (used to filter options)
    frameworks.md        # create commands per framework/template
    libraries.md         # how to install each library
    structure.md         # standard folder structure
    troubleshooting.md   # common errors on fresh machines
    quality.md           # hook rules, ESLint code rules, custom rule examples (Jira keys, branch names), Claude Code files, verification
  assets/claude/         # CLAUDE.md template, format.mjs, guard.mjs, code-reviewer.md, verifier.md
skills/rn-feature/
  SKILL.md               # analysis (phases 0 → 7) and building (phases 8 → 13)
  scripts/
    project-map.sh       # routes → screens, components, data domains, existing docs and tickets → JSON
    fetch-ticket.sh      # GitHub issue or pasted text → title, body, comments, acceptance criteria, links
    check-ticket.sh      # checks docs/tickets/<id>.md against the contract (plan and evidence too); exit 3 = problems
    lock-tests.sh        # locks the test that reproduces a bug, proves the fix didn't touch it
    set-step.sh          # sets a plan step's status in the ticket file, whatever the table padding
    ticket-pr.sh         # ticket file → PR title and body (R# → evidence, decisions, not verified)
  references/
    ticket-template.md   # docs/tickets/<id>.md template and the rules the check enforces
    analyze.md           # requirements, design, API, cross-check, questions, scope, follow-up runs
    ticket-sources.md    # GitHub, Jira (connector or pasted), plain text
    build.md             # plan mode, branch and commits, steps, bugs test-first, verify, pull request
    handoff.md           # the contract for calling rn-ui and rn-api-connect, and their report back
skills/rn-ui/
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
    special-components.md # maps, sheets, media, charts, social sign-in…: libraries per framework, native setup, verification
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
    auth.md              # sign-in: session in the keychain, refresh on 401, sign-out, social sign-in
    mapping.md           # matching functions to endpoints, DTO → app-type mappers, tests
    data-hooks.md        # pagination, mutations, invalidation, hooks without TanStack Query
    screen-states.md     # loading / error / empty, load-more, mutation errors
    verify.md            # checking against the API on each target, error/empty/mock modes
    plan-template.md     # docs/api-plan.md template
    other-inputs.md      # Postman collections and plain descriptions
skills/rn-e2e/
  SKILL.md               # Maestro flows per requirement (phases 0 → 6)
  scripts/
    e2e-doctor.sh        # Maestro, Java, devices, how the app opens, existing flows, testIDs → JSON; exit 2 = install needed
    install-maestro.sh   # Maestro (official installer) + JDK 17 if missing, PATH block; only with the dev's yes
    run-flows.sh         # runs flows for a target (Expo Go / build, iOS / Android) → JUnit + JSON summary; --start-server uses .maestro/dev-server.env
    check-flows.sh       # syntax and conventions; which R# of a ticket have no flow
  references/
    flows.md             # what a flow covers, testIDs, layout, commands, targets, data and sign-in, troubleshooting
    ci.md                # what CI needs, the usual options, what to keep in the repo
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
