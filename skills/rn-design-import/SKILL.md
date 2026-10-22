---
name: rn-design-import
description: Turns a design into a working React Native / Expo UI inside an existing project — screens, navigation, theme (colors, typography, spacing), Google Fonts, icons/images and shared components. Accepts any mix of a plain-language list of screens ("the app has Login, Home, Cart, Profile"), screenshots / mockup images, or Figma links. Analyzes the input, writes a design spec for the dev to approve, generates the code following the project's own conventions, then runs the app and compares each screen against the design. Use this whenever someone wants to build screens from a description, a screenshot, an image, or Figma; scaffold app screens and navigation; "make it look like this"; set up a theme, design tokens or fonts from a design; or add new screens to an existing RN/Expo app — also when rn-starter hands off a new project together with a screen list or a design.
---

# Design → React Native UI

Goal: the dev's design becomes **real, navigable screens running in their app**, built on a shared theme and shared components, so the rest of the team can keep building on it. This is the initial UI setup — layouts, styling, navigation, mock data. Business logic and real API calls are out of scope; leave clear seams for them (typed props, a `services/` call returning mock data).

Talk to the dev in their language. Keep them in the loop at the two points that matter: approving the spec (Phase 3) and confirming the result (Phase 6).

## Phase 0 — Understand the project

```bash
source <rn-starter-skill-dir>/scripts/env.sh 2>/dev/null; bash "<skill-dir>/scripts/detect-project.sh" <project-dir>
```

It prints JSON: framework (Expo / CLI), navigation library, styling approach, UI component library, package manager, where routes and theme files live, existing fonts, and whether `docs/design-spec.md` already exists.

- No `package.json` / not an RN project → this skill needs a project. Offer to create one with the **rn-starter** skill first (it hands back here).
- An existing theme or components → **extend them**. Read them before generating anything. Duplicating a design system the project already has is the most common way this goes wrong.
- `docs/design-spec.md` exists, or the app already has screens of its own → this is a feature added to an existing app. Read the spec, and follow `references/follow-up.md` through every phase: update the spec instead of starting over, reuse before creating, and re-verify the existing screens your changes reach.

Record a type-check baseline now: `npx tsc --noEmit > /tmp/tsc-baseline.txt` (templates can ship with errors of their own; in Expo, CSS-module errors disappear after the first `expo start` generates `expo-env.d.ts`). Later checks only count new errors.

If `mismatches` is non-empty, the project doesn't have something rn-starter recorded as chosen (e.g. Zustand). Install it if it's needed for the screens, otherwise follow what's installed — and mention it.

**Folder structure:** if the project follows the layered layout (`structure: "layered"` in the JSON — `src/screens/` exists), or is a fresh scaffold, generate into that layout as described in `references/conventions.md`: thin route files, one folder per screen, shared UI in `components/`, data through `services/` → `hooks/` with `mocks/`, logic in `utils/`. `structure: "feature-first"` or `"partial-features"` (projects from rn-starter 1.x) → keep that layout (end of `conventions.md`). If the project has its own different structure, follow it instead — don't restructure an existing codebase unasked. `structure: "flat"` (screens written inside route files, no `src/screens/`) → tell the dev, and offer to move to the layered layout first (screens out of route files, ESLint rules from rn-starter `structure.md`) as a separate step they approve.

Everything you generate must follow what this JSON says: expo-router vs React Navigation, StyleSheet vs NativeWind, the `@/` alias, `src/` layout. When the project has no opinion yet, use `references/conventions.md`.

## Phase 1 — Collect the design input

Accept any combination — they complement each other:

| Input | What it gives | Read |
|---|---|---|
| Text ("5 screens: Login, Home, …") | screen list, rough purpose, maybe flow | `references/input-text.md` |
| Screenshots / images | layout, components, exact colors (via `palette.py`), approximate type sizes | `references/input-image.md` |
| Figma link(s) | exact tokens, fonts, spacing, assets, every frame — via the Figma MCP, or by reading Figma in a browser when the MCP is missing or out of calls | `references/input-figma.md` |

If the dev hasn't given anything yet, ask once with `AskUserQuestion`: "What should the screens be based on?" → *Figma link* / *Screenshots* / *Just a list of screens* / *No design — suggest a simple app structure*.

## Phase 2 — Analyze and ask only what's missing

Read the reference file for each input type and extract:

1. **Screens** — name, purpose, main sections, key components, states that matter (empty, loading, error) only if the design shows them.
2. **Navigation** — which screens are tabs, which push on a stack, which are modals, what's behind auth. Infer from names and design (a bottom bar in a screenshot = tabs).
3. **Tokens** — colors (with semantic names: `primary`, `background`, `surface`, `text`, `textMuted`, `border`, `danger`, …), typography scale, spacing scale, radii, shadows, light/dark. When the project already has a theme, match every design color against its tokens first (`references/theme.md` → Colors from a later design).
4. **Fonts** — families and weights used.
5. **Shared components** — anything appearing on 2+ screens (buttons, inputs, cards, list rows, headers).
6. **Assets** — logos, illustrations (images), and icons. Icons come from the design as SVG (Figma) and become components in `src/components/icons/` — standard glyphs too, so the screens show the design's icon set rather than an icon-font look-alike. Only when the design has no vector source (text input, screenshots) map icons to the project's icon library (`icons` in the detect output) and list each substitution under Open points.
7. **Special components** — maps, bottom sheets, carousels, charts, video, camera/QR, pickers, calendars, Lottie, swipeable rows, web views: anything that needs a library rather than layout. Read `references/special-components.md`, check candidates with `scripts/lib-info.sh` (maintained, New Architecture, Expo Go / SDK version), and suggest the library that fits the project's framework (Expo vs RN CLI differ).

Then ask what you cannot infer, in one `AskUserQuestion` round (max 4 questions), each with your best guess as the recommended option. Typical gaps:
- navigation shape when names are ambiguous ("A, B, C" tells you nothing — ask what each screen is for in plain text);
- the font when you only have a screenshot (offer your closest Google Fonts matches);
- theme when there's no visual design and no existing theme (primary color, light/dark);
- which Figma frames to build when the file has many.

Special components get their own `AskUserQuestion` round (one question each, max 4): the recommended library with what it requires (API key, permission, dev build on Expo, native rebuild on CLI) / a static placeholder for now / Other.

## Phase 3 — Design spec → dev approval

Write `docs/design-spec.md` using `references/spec-template.md`. It is the contract for code generation and stays in the repo for the next import.

Show the dev a short summary (screens + navigation tree + palette + fonts) and ask: "Generate the UI from this spec?" → *Yes (Recommended)* / *Change something*. Don't generate before a yes: rebuilding screens after a misunderstood navigation structure costs far more than a question.

## Phase 4 — Generate

Order matters — each step builds on the previous:

1. **Theme** — `references/theme.md`. Tokens in one place; screens never hard-code colors or sizes.
2. **Fonts** — for each Google Font family:
   ```bash
   bash "<skill-dir>/scripts/google-font.sh" "<Family>" 400,500,600,700 <project-dir>
   ```
   Run it in the background: on pnpm the install can take minutes. It prints the exact `fontFamily` string per weight. Wire them into the typography tokens as in `references/fonts.md`. Non-Google fonts (exit code 3): ask the dev for the font files (they must have a license), or agree on a Google alternative.
3. **Assets** — images go into `assets/images`, named in kebab-case after what they are, not after Figma layer ids. Icons: export them as SVG into `docs/design/icons/` (`references/input-figma.md` → Assets), make sure `react-native-svg` is installed (Expo: `npx expo install react-native-svg` — it's in Expo Go; CLI: `<pm> add react-native-svg`, then `cd ios && pod install`), and generate the components:
   ```bash
   bash "<skill-dir>/scripts/svg-icons.sh" <project-dir> <project-dir>/docs/design/icons
   ```
   It writes `src/components/icons/<name>.tsx` (`<Name>Icon` with `size` and, for single-color icons, `color`), `types.ts` and an `index.ts`; screens import `{ BagIcon } from '@/components/icons'`. Exit 3 = generated, but `react-native-svg` still needs installing. Rerun it whenever icons are added; it's idempotent and keeps hand-written icon components. Use the project's icon library (`icons` in the detect output); placeholders as in `references/conventions.md`.
4. **Shared components** — `src/components/` (or the project's equivalent): only UI used by 2+ screens. Typed props, themed, no screen knowledge. If the project has Jest + React Native Testing Library (`package.json` has `jest` and `@testing-library/react-native`), give each shared component a small test (`components/__tests__/button.test.tsx`, unless the project keeps tests elsewhere): it renders, shows its label/content, and fires its main callback (`await user.press(...)` — RNTL 14 APIs are async). These double as examples for the team. Run `npx jest` at the end of the step.
5. **Data layer** — per domain (products, orders, delivery): `types/<domain>.ts` shaped like the future API data, `mocks/<domain>.ts`, `services/<domain>.ts` returning the mocks, `hooks/use-<domain>.ts` wrapping the service with TanStack Query (or plain hooks if the project has no query library). Calculations the screens need (totals, fees, discounts, validation) go in a pure `utils/<logic>.ts` with a test in `utils/__tests__/` covering every branch — never inline in a screen.
6. **Special components** — install the chosen libraries (Expo: `npx expo install`; CLI: `<pm> add`, `cd ios && pod install`), do the native setup (permissions, API key placeholders, config plugins), and wrap each library in a component that takes app data as props — screens never import the library. Details per library in `references/special-components.md`. CLI: rebuild the app before continuing.
7. **Screens** — `screens/<name>/index.tsx` exporting `<Name>Screen`, composed from shared components and its own `components/`, getting data only through hooks (never importing services or mocks). The route file in `app/` is a one-line re-export. Keep each screen readable: if it grows past ~150 lines, split sections into the screen's `components/` and move state and handlers into its `hooks.ts`.
8. **Navigation** — `references/navigation.md`. Every screen reachable by tapping through the app, and by deep link for verification.

After each step, run the type checker (`npx tsc --noEmit`) and fix what you introduced before moving on. Before Phase 5, run the structure self-check at the end of `references/conventions.md` (ESLint rules, no service or mock imports in UI files, thin route files). If the project has git hooks (`.husky/`), your code must pass them too: run `npx lint-staged` on your changes before offering a commit.

## Phase 5 — Verify against the design

Follow `references/verify.md` on **every run target the dev uses** — `runTargets` in `.rn-starter.json`, or ask if there's no record:

1. **Main target** (the first listed, usually the iOS Simulator): open every screen by deep link, take a screenshot of each, and compare it side by side with the design (the screenshot the dev gave, or the Figma frame image). Fix visible differences — spacing, colors, font weight, alignment — and re-check. Two or three passes are normal.
2. **Each other simulator/emulator:** open every screen again and screenshot it. Not a full design comparison — look for what breaks per platform: custom fonts not applied, shadows/elevation, safe-area and status-bar overlap, text wrapping, native tab bar differences. Fix in shared code where possible.
   Special components get checked on every target: the map shows tiles (not a grey grid), the sheet drags, the video plays a frame. Grant permissions and fake locations from the command line (`references/special-components.md` → Verify).
3. **Phone via Expo Go:** ask the dev to open the app and check the main screens (you can't see the phone). Record their answer.

Existing screens that use a token, shared component, layout or service you changed are checked the same way (`references/follow-up.md` → Changes that reach existing screens).

A target you didn't check is listed as not verified in the hand-off — never implied as done.

Also tap through the main flow once (e.g. Login → Home → Detail → back) to be sure navigation works, not just individual screens.

## Phase 6 — Hand-off

1. Update `docs/design-spec.md`: mark each screen as built, note anything approximated (guessed font, icon substitutions, placeholder images) under "Open points".
2. Tell the dev briefly: screens created and where, which targets each was verified on (✓ / not verified), how to open each one, what's mocked, the open points, and how to add the next screen ("run this skill again with the new frame/screenshot").
3. If the project is a git repo, offer to commit (`feat(ui): import screens from design`). Don't commit without a yes.

## Principles

- **Follow the project, not a template.** Existing patterns beat `conventions.md`.
- **Tokens, not literals.** A screen with `#2563EB` in it is a bug; `theme.colors.primary` is the fix.
- **Close to the design, not pixel-perfect at any cost.** Match spacing, hierarchy, colors and type; don't fight platform differences (status bar, safe areas, native fonts metrics).
- **Approximations are written down,** never silent.
- **Only UI.** Mock data and stub handlers (`onPress={() => {}}` with a `// TODO` naming the intended action) are expected; inventing backend behavior is not.
