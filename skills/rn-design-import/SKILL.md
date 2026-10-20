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

It prints JSON: framework (Expo / CLI), navigation library, styling approach, package manager, where routes and theme files live, existing fonts, and whether `docs/design-spec.md` already exists.

- No `package.json` / not an RN project → this skill needs a project. Offer to create one with the **rn-starter** skill first (it hands back here).
- An existing theme or components → **extend them**. Read them before generating anything. Duplicating a design system the project already has is the most common way this goes wrong.
- `docs/design-spec.md` exists → this is a follow-up import. Read it; add to it rather than starting over.

Record a type-check baseline now: `npx tsc --noEmit > /tmp/tsc-baseline.txt` (templates can ship with errors of their own; in Expo, CSS-module errors disappear after the first `expo start` generates `expo-env.d.ts`). Later checks only count new errors.

If `mismatches` is non-empty, the project doesn't have something rn-starter recorded as chosen (e.g. Zustand). Install it if it's needed for the screens, otherwise follow what's installed — and mention it.

**Folder structure:** if the project already follows the feature-first layout (`structure: "feature-first"` in the JSON — `src/features/*/index.ts` exist), or is a fresh scaffold, generate into that layout as described in `references/conventions.md`: thin route files, one folder per domain feature with its screens, components, `api.ts`, `hooks.ts`, mocks and logic, and a public `index.ts`. If the project has its own different structure, follow it instead — don't restructure an existing codebase unasked. `structure: "partial-features"` (a `features/` folder without public `index.ts` files, screens still inside route files) means it's halfway there: tell the dev, and offer to complete the layout first (move screens into features, add `index.ts` files and the ESLint boundary rules) as a separate step they approve.

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
3. **Tokens** — colors (with semantic names: `primary`, `background`, `surface`, `text`, `textMuted`, `border`, `danger`, …), typography scale, spacing scale, radii, shadows, light/dark.
4. **Fonts** — families and weights used.
5. **Shared components** — anything appearing on 2+ screens (buttons, inputs, cards, list rows, headers).
6. **Assets** — logos, illustrations, icons (map icons to `@expo/vector-icons` / the project's icon set when they're standard glyphs; export only custom ones).
7. **Special components** — maps, bottom sheets, carousels, charts, video, camera/QR, pickers, calendars, Lottie, swipeable rows, web views: anything that needs a library rather than layout. Read `references/special-components.md`, check candidates with `scripts/lib-info.sh` (maintained, New Architecture, Expo Go / SDK version), and suggest the library that fits the project's framework (Expo vs RN CLI differ).

Then ask what you cannot infer, in one `AskUserQuestion` round (max 4 questions), each with your best guess as the recommended option. Typical gaps:
- navigation shape when names are ambiguous ("A, B, C" tells you nothing — ask what each screen is for in plain text);
- the font when you only have a screenshot (offer your closest Google Fonts matches);
- theme when there's no visual design (primary color, light/dark);
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
3. **Assets** — save images/icons into `assets/images` (and `assets/icons`), named in kebab-case after what they are, not after Figma layer ids. Use the project's icon library (`icons` in the detect output); placeholders as in `references/conventions.md`.
4. **Shared components** — `src/components/` (or the project's equivalent): only UI used by 2+ features. Typed props, themed, no feature knowledge. If the project has Jest + React Native Testing Library (`package.json` has `jest` and `@testing-library/react-native`), give each shared component a small test next to it (`button.tsx` + `button.test.tsx`, unless the project keeps tests elsewhere): it renders, shows its label/content, and fires its main callback (`await user.press(...)` — RNTL 14 APIs are async). These double as examples for the team. Run `npx jest` at the end of the step.
5. **Feature data layer** — per domain feature (`features/<domain>/`): `types.ts` shaped like the future API data, `mocks.ts`, `api.ts` returning the mocks, `hooks.ts` wrapping `api.ts` with TanStack Query (or plain hooks if the project has no query library). Calculations the screens need (totals, fees, discounts, validation) go in a pure `<logic>.ts` in the feature with a test covering every branch — never inline in a screen.
6. **Special components** — install the chosen libraries (Expo: `npx expo install`; CLI: `<pm> add`, `cd ios && pod install`), do the native setup (permissions, API key placeholders, config plugins), and wrap each library in a component of the owning feature that takes app data as props — screens never import the library. Details per library in `references/special-components.md`. CLI: rebuild the app before continuing.
7. **Screens** — `features/<domain>/screens/<name>-screen.tsx`, composed from shared and feature components, getting data only through the feature's hooks (never importing mocks). Export each screen from the feature's `index.ts`; the route file in `app/` is a one-line re-export. Keep each screen readable: if it grows past ~150 lines, split sections into feature components.
8. **Navigation** — `references/navigation.md`. Every screen reachable by tapping through the app, and by deep link for verification.

After each step, run the type checker (`npx tsc --noEmit`) and fix what you introduced before moving on. Before Phase 5, run the structure self-check at the end of `references/conventions.md` (ESLint boundary rules, no mock imports outside `api.ts`, thin route files). If the project has git hooks (`.husky/`), your code must pass them too: run `npx lint-staged` on your changes before offering a commit.

## Phase 5 — Verify against the design

Follow `references/verify.md` on **every run target the dev uses** — `runTargets` in `.rn-starter.json`, or ask if there's no record:

1. **Main target** (the first listed, usually the iOS Simulator): open every screen by deep link, take a screenshot of each, and compare it side by side with the design (the screenshot the dev gave, or the Figma frame image). Fix visible differences — spacing, colors, font weight, alignment — and re-check. Two or three passes are normal.
2. **Each other simulator/emulator:** open every screen again and screenshot it. Not a full design comparison — look for what breaks per platform: custom fonts not applied, shadows/elevation, safe-area and status-bar overlap, text wrapping, native tab bar differences. Fix in shared code where possible.
   Special components get checked on every target: the map shows tiles (not a grey grid), the sheet drags, the video plays a frame. Grant permissions and fake locations from the command line (`references/special-components.md` → Verify).
3. **Phone via Expo Go:** ask the dev to open the app and check the main screens (you can't see the phone). Record their answer.

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
