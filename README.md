# rn-starter

A Claude Code plugin for React Native developers, with two skills:

| Skill | Use when | Result |
|---|---|---|
| **`rn-starter`** | There's no project yet, often on a brand-new machine | Environment installed, project running on a simulator, emulator or phone |
| **`rn-design-import`** | A project exists (or `rn-starter` just created one) | Theme, fonts, components, screens and navigation built from a design |

Developers just describe what they want. For example, *"Create a new RN app with 5 screens: Login, Home, Search, Detail, Profile"*: `rn-starter` scaffolds the project, runs the empty app, then hands over to `rn-design-import` to build the screens.

The wizard talks to the developer in the language they write in.

## rn-starter: clean machine → running app

1. Inspect the machine (git, Node, package manager, plus JDK/Android SDK and Xcode/iOS Simulator when needed)
2. Install what's missing (Node via fnm, no Homebrew or sudo needed)
3. Ask the developer: **Expo / RN CLI** → **Metro / Re.Pack** → template → libraries (navigation, state, data, styling, lint) → **code quality** (Jest + React Native Testing Library, Husky + lint-staged with pre-commit/pre-push rules, commitlint) → run on **a real iPhone/Android phone (Expo Go) / iOS Simulator / Android emulator / web** → is there a design
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
4. Generate in order: theme → Google Fonts → assets → shared components (with tests when Jest is set up) → feature data layer → special components → screens (mock data) → navigation.
   Special components (maps, bottom sheets, charts, camera, video…) get a real library, suggested per framework (Expo vs RN CLI) after a live check of maintenance, New Architecture and Expo Go support (`scripts/lib-info.sh`), or a placeholder if the dev prefers.
5. Run the app, open each screen by deep link, screenshot it and compare with the design; fix the differences.

UI only. Code is feature-first: each feature owns its screens, components, `api.ts` (mocked for now), hooks and logic, and exposes a public `index.ts`; route files are one-line re-exports, and ESLint enforces the boundaries. Switching a feature to the real API is a change to its `api.ts`.

Local development only: no code signing, no paid Apple Developer account. Supports macOS and Linux (no iOS Simulator on Linux).

**Steps the developer does themselves with `rn-starter`** (the skill stops, explains, and waits):
- Download Xcode from the App Store (a free Apple ID is enough), or install it from the team's `.xip`.
- Run the `sudo` commands, e.g. `sudo xcodebuild -license accept`.
- Install Homebrew (only for RN CLI + iOS).
- Accept the Android SDK license.

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

In Claude Code, type `/rn-starter` or just ask, e.g. *"create a new React Native app"*, *"new laptop, set it up for RN"*, *"build these screens from this Figma link"*.

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
```

**Figma:** Figma's Starter/free plans allow very few MCP calls per month. The skill makes the minimum: one call for the frame list, one for variables, one per screen. When the MCP is out of calls or not connected, it **opens Figma in a browser** (Claude in Chrome or the built-in browser; the developer signs in). It selects frames and layers and reads exact values (hex colors, fonts, sizes, dimensions, corner radii) from the properties panel with `scripts/figma-panel.js`. This costs no API calls.

Scripts write to the shell rc file inside marked blocks (`# >>> rn-starter:<name> >>>`), so reruns never duplicate lines. Delete a block to undo it.

## Quick machine check

```bash
bash skills/rn-starter/scripts/doctor.sh --android --ios --cocoapods
```

## Updating versions

The verified versions are listed at the top of `skills/rn-starter/references/compatibility.md` (currently Expo SDK 58, React Native 0.88, Node 24 LTS, JDK 17, Android API 35, Xcode 26 / iOS 26.5). When upgrading, update that file first, then rerun the flow on a clean machine (a VM or a new macOS user).
