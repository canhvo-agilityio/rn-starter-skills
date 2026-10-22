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
| Team lead | Onboarding several people | The same structure, tooling and conventions in every project |

## Goals

1. **Clean machine → running app** on macOS, Windows and Linux, installing missing tools itself (per user, no admin where possible).
2. **Stack chosen by the developer, guided:** every question has a recommended answer; only combinations that work are offered.
3. **Team-quality scaffold:** layered structure with enforced import rules, theme tokens, unit tests, git hooks, commit rules, and Claude Code files (`CLAUDE.md`, format-on-edit hook, review subagent).
4. **Design → screens:** from text, screenshots or Figma to themed, navigable screens with mock data behind a clean data seam, approved by the developer as a spec before code is written.
5. **Verified, not assumed:** the app is run and looked at (screenshots) on every selected target before anything is reported as done.

## Non-goals

- Store releases, code signing, provisioning profiles, paid Apple accounts.
- Business logic or real backend integration (screens use mocks behind `src/services/`; connecting APIs is a planned separate skill, see ROADMAP.md).
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

## Acceptance criteria

A run is successful when:

- [ ] A developer who accepts every recommended answer ends with a running app on every target they selected, without installing anything by hand except the documented human steps.
- [ ] No offered option leads to a combination that can't work (e.g. RN CLI + Expo Go, iOS Simulator on Windows).
- [ ] The generated project passes `tsc --noEmit`, ESLint (including boundary rules) and its unit tests; hooks block a bad commit message and pass a good one.
- [ ] Route files are one-line re-exports; UI files import data only through hooks; no mock imports outside `services/` and tests.
- [ ] With the Claude Code option: the format hook fixes an edited file and returns an import-rule violation to Claude; `code-reviewer` is listed as a subagent.
- [ ] With a design input, `docs/design-spec.md` exists and was approved, every screen opens by deep link, and each screen's verification status lists the targets it was checked on.
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
| Not yet exercised anywhere | Re.Pack, Ignite, NativeWind, Unistyles, Figma MCP end to end, screenshot input end to end, special-components flow, a truly clean Mac | | |

Evidence (screenshots, recordings) goes in [`docs/evidence/`](docs/evidence/).
