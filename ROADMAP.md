# Roadmap

What to build next, in order, and what's still open from the last round. Start here in a new session, together with [spec.md](spec.md) and [DESIGN.md](DESIGN.md).

Last updated: 2026-10-23.

## 1. Open work on the current release (do first)

The layered structure, Claude Code files, theme setups, UI library option and SVG icons are on `dev` (version stays `1.0.0` until the owner asks for a bump).

- [ ] Re-run icons in the tester's app `~/training/test/coffee-shop` with the new flow: Figma icons → SVG in `docs/design/icons/` → `svg-icons.sh` → replace the PNG icons and Ionicons look-alikes, delete `assets/icons/`.
- [ ] Have a subagent follow `skills/rn-starter/SKILL.md` and `skills/rn-design-import/SKILL.md` literally on a fresh app and report every wrong, ambiguous or missing instruction (the method that found the most bugs before).
- [ ] Not yet run for real, only checked with tsc/lint/bundle or written from official docs:
  - Unistyles with an Expo development build (`devBuild: true`, `npx expo run:ios|android`) and the theme sample in `theme.md` §4.
  - NativeWind CSS-variable theme (`theme.md` §5).
  - `svg-icons.sh` on SVGs exported from a real Figma file, and the icons on a simulator.
  - Light-only design on a device in dark mode (the new step in `verify.md`).
  - `setup-claude.sh` and the format hook on Windows (Git Bash + node).
- [ ] Adding a feature to an existing app (rn-design-import, `references/follow-up.md`): the high-priority fixes from the coffee-shop Favorites/Order History run are in. Still open from that run:
  - `verify.md`: pick a free port when 8081 is taken (+ `adb reverse`), target `host.exp.exponent` when opening links on Android, cold-start deep links on iOS landing on the root, Expo Go's gear covering the element under test, text-only input (compare with the spec and existing screens), segment/tab state in the URL so it's deep-linkable, iOS states reachable only by tapping.
  - Baselines in a per-project path (not `/tmp/tsc-baseline.txt`), plus lint and jest baselines; Phase 6 honoring the project's own `CLAUDE.md` rules (e.g. a reviewer before commit); a `renderWithProviders` example; `SKILL.md` points to icon placeholders in `conventions.md` that don't exist.
  - Re-run the same feature on a fresh copy to confirm the fixes, and test on an app not made by rn-starter with one domain on a real API (follow-up.md's real-API row and the "no spec yet" path).
  - The tester's `coffee-shop` still has the status-bar bug in the Bag tab (fixed only in the test copy).
- [ ] rn-design-import, from the second Favorites/Order History run (2026-10-23) — fix on its own branch:
  - `theme.md` → Colors from a later design: "within 3 per channel" must also require the **same role** (`#FDEDED` for a Cancelled badge was merged into `badgeSoft`, the ingredient badges' fill).
  - `follow-up.md`: point to the focused status bar in `theme.md` §2 and check it after switching from a tab with the opposite style; open the filtered/tabbed states (chips) of existing screens that get new data (a lone card stretched full width — give 2-column grid items a `maxWidth`); grep `src/components` too.
  - `verify.md`: `?__expo_disable_fab=1`, cold-start deep links, the Expo Go dev-menu sheet on Android's first launch; baseline lint and jest; Phase 6 follows the project's CLAUDE.md pre-commit steps (its code-reviewer found three real bugs); `renderHook` + QueryClient needs `gcTime: Infinity` and `clear()`; the spec template's Screens table has no frame column.
- [ ] Recheck the UI libraries left out of the wizard (gluestack-ui, Tamagui, React Native Reusables) — reasons in `skills/rn-starter/references/libraries.md`. Add one back only after it installs, type-checks and bundles on the current Expo SDK.

## 2. New skills, in priority order

Each new skill reads `.rn-starter.json` and the layered layout (DESIGN.md → Extending), talks to the developer in their language, puts deterministic work in scripts (exit codes 0/1/2/3), and is tested on a scratch app.

### 2.1 `rn-api-connect` — mocks → real API (next)

**Built** (2026-10-23): `skills/rn-api-connect/`, tested in two subagent runs on coffee-shop against a local OpenAPI test API (json-server + Swagger UI with deliberate spec quirks) and with a decoy `.env` that must stay unopened. Open: a run on an app not made by rn-starter, Postman/description inputs, auth-protected endpoints once rn-auth exists.

The layered structure was built for this: screens get data through `src/hooks/`, hooks call `src/services/`, services return `src/mocks/`. Connecting a backend should only touch `services/` (and hooks when a shape changes).

- Input: an OpenAPI/Swagger file or URL, a Postman collection, or a plain description of endpoints.
- Output: a typed HTTP client in `src/lib/` (base URL from `src/lib/env.ts`, auth header, error mapping), `src/types/` generated or written from the schema, `services/*` switched from mocks to calls one domain at a time, TanStack Query keys and invalidation for mutations, loading/error/empty states the screens already expect.
- Decided: openapi-typescript + openapi-fetch, DTO → app-type mappers, `expo-secure-store` left to rn-auth, mocks kept behind `EXPO_PUBLIC_USE_MOCKS` (DESIGN.md key decisions).
- Test: a public API or a local json-server; screens still render; mocks no longer imported anywhere but tests.

### 2.2 `rn-release-setup` — EAS and store credentials (built, first version)

Owner's decision (2026-10-23): release work comes before auth, forms and e2e, split by time — this skill sets an app up once; `rn-release` (2.3) ships it many times. Done when the project's **Credentials page on expo.dev is complete** (build, submit, push if used), with what's outside EAS listed; a test build is offered, not required.

- Built: `skills/rn-release-setup/` (SKILL.md, 3 scripts, 8 references). Checked for real: scripts on coffee-shop and fake credential files; on a prototype, `eas init`, profiles, env var, expo-updates, an EAS-generated keystore and a cloud store build signed with it.
- Not run yet: a subagent run of the whole SKILL.md; the Google service account (needs a Play Console app); push with a Firebase project (free — doable on an emulator with Google APIs); iOS (needs an Apple Developer account); uploading a client keystore.
- Not in this skill (listed in its hand-off): Google Sign-In, Maps, App Links, Sentry setup.

### 2.3 `rn-release` — test releases, approval gate, production

Reads `docs/release-plan.md` from 2.2. TestFlight internal + Google Play internal for testers (draft releases while a Play app is unpublished), OTA on the test channel for JS-only fixes (fingerprint check), `docs/release-log.md` (build number, OTA updates, commit) so production promotes exactly the build testers approved, an explicit approval gate the skill never passes on its own, App Review / Play production rollout.

### Postponed by the owner (2026-10-23)

- **`rn-auth`** — real sign-in replacing the mock session: own API email/password first (fits rn-api-connect's client seam), Supabase later; secure storage, single-flight refresh on 401, splash until the session is restored, explicit redirects (`Stack.Protected` doesn't redirect), sign-out clears the query cache.
- **`rn-forms`** — react-hook-form + zod, shared themed fields, server errors onto fields (`ApiError.fieldErrors`).
- **`rn-e2e`** — Maestro flows for the main flow, optional CI job.

### 2.6 Smaller candidates (pick when asked)

- **`rn-i18n`** — extract strings from generated screens, `expo-localization` + i18next, the developer's languages.
- **`rn-upgrade`** — Expo SDK / React Native upgrade: `expo install --fix`, breaking-change notes per version, re-run the quality checks and the design screenshots.
- **`rn-observability`** — Sentry (crashes, performance) and analytics events.
- **`rn-ci`** — GitHub Actions / GitLab CI running the same checks as the git hooks (lint, tsc, tests), plus EAS builds once 2.2 exists.

## 3. Improvements to the existing skills

- rn-starter: a wizard option to add i18n/forms/auth skills' setup at scaffold time once those skills exist (a single "Also set up" multi-select).
- rn-design-import: per-screen states (loading/empty/error) generated from the design when frames exist for them; tablet/landscape layouts.
- spec.md Status table: add rows for the layered-structure release features once verified (layered structure, Claude Code files, theme setups, SVG icons, UI library option).
