# Team folder structure

**Contents:** The rules · Enforce the rules with ESLint · Path alias `@/` · Moving template files · Env vars

Layered: code is grouped by what it is — routes, screens, shared components, hooks, services, state — the way Expo's own guidance, Ignite and most team RN codebases do it. A new dev can guess where any file lives from its kind alone. Three things keep it from turning into a tangle: routes are thin, UI never touches data access directly, and shared code never depends on a screen.

```
<project>/
├── src/
│   ├── app/                        routes only (expo-router) — each file a few lines
│   │   ├── _layout.tsx             providers, fonts, auth guard
│   │   ├── (tabs)/_layout.tsx      tab navigator
│   │   ├── (tabs)/index.tsx        export { HomeScreen as default } from '@/screens/home';
│   │   └── product/[id].tsx        export { ProductDetailScreen as default } from '@/screens/product-detail';
│   ├── screens/
│   │   └── <name>/                 kebab-case, one folder per screen
│   │       ├── index.tsx           export const <Name>Screen = () => …
│   │       ├── components/         UI used only by this screen
│   │       ├── hooks.ts            the screen's state and handlers, only if needed
│   │       ├── types.ts, utils.ts  only if needed
│   │       └── __tests__/
│   ├── components/                 shared UI (button.tsx, product-card/index.tsx), no screen knowledge
│   │   └── icons/                  icon components generated from SVG (rn-design-import `svg-icons.sh`), with index.ts
│   ├── hooks/                      shared hooks: use-products.ts (TanStack Query over services/)
│   ├── services/                   data access: products.ts (returns mocks until the API exists)
│   ├── mocks/                      mock data, imported only by services/ and tests
│   ├── stores/                     app state (Zustand etc.), only if needed
│   ├── types/                      domain types, shaped like the future API data
│   ├── constants/                  app-wide constants
│   ├── theme/                      colors.ts, tokens.ts, typography.ts, use-theme.ts, create-themed-styles.ts, themed-text.tsx (theme.md)
│   ├── lib/                        app-wide infrastructure: query-client.ts, http client, env.ts
│   └── utils/                      pure logic and helpers (pricing, validation, format)
├── assets/                         images, fonts, icons
├── .env.example                    documented env vars (no secrets)
└── README.md
```

Files and folders are kebab-case, as in the Expo templates. Components are arrow functions with named exports; route files are the only default exports. The full naming and code-style list is in rn-design-import's `references/conventions.md`.

Tests go in a `__tests__/` folder beside the code they test, named after the file (`components/__tests__/button.test.tsx`, `utils/__tests__/pricing.test.ts`, `screens/cart/__tests__/index.test.tsx`). Shared test helpers (`renderWithProviders`) go in `src/test-utils.tsx`.

Create only folders that will have something in them right away (a small real file, not `.gitkeep`). On a fresh scaffold that means one screen (`screens/home/index.tsx`) wired to the first route, plus the theme.

## The rules

1. **`app/` files only declare routes.** A route file re-exports a screen; at most it adds route-only exports (`unstable_settings`, `generateStaticParams`) or a layout. No UI, no data fetching, no logic.
2. **UI gets data through hooks.** Components and screens (`.tsx` files) never import `@/services` or `@/mocks`. They call a hook (`hooks/use-products.ts`, or the screen's `hooks.ts`), and the hook calls the service. Swapping in the real API is then a change to `services/` only.
3. **Only `services/` and tests import `mocks/`.**
4. **Shared code doesn't import screens.** `components/`, `hooks/`, `services/`, `stores/`, `theme/`, `lib/`, `utils/`, `types/`, `constants/` never import from `@/screens`. If a screen's piece is needed elsewhere, move it to the shared folder it belongs in.

A screen's own `components/` is private to it. When a second screen needs one, move it to `src/components/` instead of importing across screen folders.

## Enforce the rules with ESLint

Add to `eslint.config.js` (flat config) after the existing entries. For files matched by several blocks the last one wins, which is why each block lists every pattern that applies to its files.

```js
const mocksImport = {
  group: ['@/mocks', '@/mocks/*'],
  message: 'Only services and tests import mocks. Get data through a hook.',
};
const servicesImport = {
  group: ['@/services', '@/services/*'],
  message: 'UI gets data through a hook (src/hooks or the screen hooks.ts), not from services.',
};
const screensImport = {
  group: ['@/screens', '@/screens/*'],
  message: 'Shared code must not depend on screens. Move the shared piece out of the screen folder.',
};
const restrict = (...patterns) => ({ 'no-restricted-imports': ['error', { patterns }] });
const tests = ['src/**/__tests__/**', 'src/test-utils.tsx'];

// in the defineConfig([...]) array:
{ files: ['src/**/*.{ts,tsx}'], ignores: ['src/services/**', ...tests], rules: restrict(mocksImport) },
{ files: ['src/**/*.tsx'], ignores: tests, rules: restrict(mocksImport, servicesImport) },
{ files: ['src/{hooks,stores,lib,utils,types,constants}/**/*.ts'], ignores: tests, rules: restrict(mocksImport, screensImport) },
{ files: ['src/{components,theme}/**', 'src/{hooks,stores,lib,utils}/**/*.tsx'], ignores: tests, rules: restrict(mocksImport, servicesImport, screensImport) },
{ files: ['src/services/**'], ignores: tests, rules: restrict(screensImport) },
```

Run `npx eslint src` after adding it; it must pass on the scaffold. (Verified on an Expo SDK app: it flags a screen importing a service or a mock, a hook importing a mock, and shared code importing a screen; it allows hooks to import services, services to import mocks, and tests to import anything.)

## Path alias `@/`

`tsconfig.json`:

```json
{
  "compilerOptions": {
    "baseUrl": ".",
    "paths": { "@/*": ["src/*"] }
  }
}
```

- **Expo**: Expo's Metro reads `tsconfig` paths automatically. Nothing else needed. Jest needs the same alias: `"moduleNameMapper": { "^@/(.*)$": "<rootDir>/src/$1" }` in the `jest` block of `package.json`.
- **RN CLI**: also add `babel-plugin-module-resolver` (`<pm> add -D babel-plugin-module-resolver`) and in `babel.config.js`:
  ```js
  plugins: [['module-resolver', { root: ['./'], alias: { '@': './src' } }]]
  ```
  Restart Metro with `--reset-cache` after changing Babel config.

## Moving template files

- **Expo `default` template (SDK 58+)**: ships `src/app`, `src/components`, `src/hooks`, `src/constants` and the `@/` alias.
  - Move the theme into `src/theme/`: `src/constants/theme.ts` → `src/theme/tokens.ts`, `src/hooks/use-theme.ts` → `src/theme/use-theme.ts`, `src/components/themed-text.tsx` / `themed-view.tsx` → `src/theme/`. Keep their export names and fix the imports (`grep -rl "@/constants/theme\|@/hooks/use-theme\|themed-" src`). With NativeWind, Unistyles or a UI library, set the theme up as rn-design-import `theme.md` describes for it instead.
  - Turn the demo home route into the first screen: `src/screens/home/index.tsx` exporting `HomeScreen`, and make `src/app/index.tsx` a one-line re-export. Delete the `explore` demo route and its demo components only when replacing them (or when the dev wants a blank start; the template's `npm run reset-project` does this too).
  - If an older template puts routes in `app/` at the root, move them under `src/` (expo-router detects `src/app` automatically).
- **CLI template**: create `src/screens/home/index.tsx` from `App.tsx`'s content, keep a small `src/app/App.tsx` that sets up providers and navigation (`src/navigation/` for the navigators), and point `index.js` at it.

After moving, run `npx tsc --noEmit`, `npx eslint src`, and start the app once to confirm nothing broke.

## Env vars

- Expo: variables prefixed `EXPO_PUBLIC_` in `.env` are available as `process.env.EXPO_PUBLIC_…`. Put documented placeholders in `.env.example`; add `.env` to `.gitignore`. Read them in one place (`src/lib/env.ts`) rather than throughout the code.
- CLI: no built-in env loading. Don't add a library unless the dev asks; mention `react-native-config` as the usual choice.
