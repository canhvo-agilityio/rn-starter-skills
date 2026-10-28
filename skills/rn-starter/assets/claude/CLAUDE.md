# {{APP_NAME}}

{{FRAMEWORK}} app scaffolded with rn-starter. Every setup choice is recorded in `.rn-starter.json`; `README.md` has the getting-started steps for people.

{{AGENTS}}

## Stack

{{STACK}}

## Commands

{{COMMANDS}}

<!-- structure:layered -->
## Structure

Layered. Group code by what it is; see `src/` before creating a file.

```
src/app/                 routes only — each file re-exports a screen
src/screens/<name>/      index.tsx (the screen), components/, hooks.ts, types.ts, utils.ts, __tests__/
src/components/          shared UI used by 2+ screens
src/hooks/               shared hooks; data hooks wrap services/ (TanStack Query when installed)
src/services/            data access; returns mocks/ until the real API exists
src/mocks/  src/stores/  src/types/  src/constants/  src/theme/  src/lib/  src/utils/
```

Rules (ESLint enforces 2–4):

1. Route files in `src/app/` only re-export a screen: `export { CartScreen as default } from '@/screens/cart';`.
2. UI files (`.tsx`) never import `@/services` or `@/mocks`. They call a hook; the hook calls the service.
3. Only `src/services/` and tests import `@/mocks`.
4. Shared folders never import `@/screens`. When a second screen needs a screen's component, move it to `src/components/`.
<!-- /structure:layered -->
<!-- structure:template -->
## Structure

Follow the layout already in `src/`: put new code next to code of the same kind, and keep route files thin.
<!-- /structure:template -->

## Code style

- Files and folders are kebab-case (`product-card.tsx`, `use-products.ts`).
- Components are arrow functions with named exports, props (when there are any) typed with an `interface <Name>Props`; route files are the only default exports.
- {{STYLE_RULE}} Colors, spacing and fonts always come from the theme, never literals.
- Icons are components in `src/components/icons/` generated from the design's SVGs in `docs/design/icons/` (rn-ui's `svg-icons.sh`). New icons are never PNGs in `assets/` (the template's own tab icons can stay until the design replaces them).
- Constants are `UPPER_SNAKE_CASE`. Comments explain why, not what.
- Growing lists: `FlatList` with a `memo` item and stable `renderItem` / `keyExtractor`.
- Forms keep the focused input above the keyboard (check Android too) and use `keyboardShouldPersistTaps="handled"`.
- Screens that can lose unsaved input ask before leaving (`usePreventRemove` / `beforeRemove`).
- Tests go in `__tests__/` beside the code, named after the file. React Native Testing Library 14 is async: `await render(…)`, `await user.press(…)`.

## Verifying your work

{{VERIFY}}

Run these before reporting a task complete, and paste the output. A change that hasn't been checked isn't done.
If a test fails, fix the code, not the test. Never skip or delete a failing test.
For a change someone can see or tap, run the `verifier` subagent: it opens the app, checks the change and reports, without editing.

## Working in this repo

- A hook formats and lint-fixes every file you edit (`.claude/hooks/format.mjs`). When it reports problems, fix them before moving on.
- A guard hook (`.claude/hooks/guard.mjs`) blocks pushes to {{PROTECTED}}, reading or editing secret files (`.env`, signing keys, keystores, service-account keys), hand edits to generated `*.gen.ts` files, and changes to a test locked while a bug is being fixed. When it blocks something, do what its message says; don't look for a way around it.
- A release gate (`.claude/hooks/release-gate.mjs`) lets dev-app builds and updates through, asks before submitting the dev app, and blocks shipping the production app (EAS build, submit, OTA update, a `v*` tag) until a `release/<version>` pull request is approved on GitHub for that exact commit. Production releases go through the `rn-release` skill. Never approve a pull request yourself.
- {{INSTALL_RULE}}
- Before calling a change finished or opening a pull request, run the `code-reviewer` subagent on it and fix what it reports.
- When you make the same mistake twice, add the correction to this file.
{{COMMIT_RULE}}
