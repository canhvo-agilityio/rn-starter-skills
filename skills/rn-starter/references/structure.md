# Team folder structure

Feature-first. Each feature owns everything it needs — screens, components, data access, state, mocks, tests — and exposes a small public API. Routes are thin. Shared code never depends on features. The goal: a new dev can guess where any file lives, and deleting or changing a feature means touching one folder.

```
<project>/
├── src/
│   ├── app/                        routes only (expo-router) — each file a few lines
│   │   ├── _layout.tsx             providers, fonts, auth guard
│   │   ├── (tabs)/_layout.tsx      tab navigator
│   │   ├── (tabs)/index.tsx        export { HomeScreen as default } from '@/features/home';
│   │   └── product/[id].tsx        export { ProductDetailScreen as default } from '@/features/product';
│   ├── features/
│   │   └── <feature>/
│   │       ├── screens/            <name>-screen.tsx — the actual screens
│   │       ├── components/         UI used only by this feature
│   │       ├── api.ts              data access (returns mocks until the API exists)
│   │       ├── hooks.ts            TanStack Query hooks / feature hooks over api.ts
│   │       ├── store.ts            feature state (Zustand etc.), only if needed
│   │       ├── mocks.ts            mock data, imported only by api.ts and tests
│   │       ├── types.ts            domain types (shaped like the future API data)
│   │       ├── <logic>.ts          pure logic (pricing, validation…) + <logic>.test.ts
│   │       └── index.ts            public API — the only file other code imports
│   ├── components/                 shared UI (Button, TextField, Card…), no feature knowledge
│   │   └── icons/                  icon components, kept apart from regular components
│   ├── theme/                      tokens.ts, use-theme.ts, themed-text.tsx (see theme.md in rn-design-import)
│   ├── lib/                        app-wide infrastructure: query-client.ts, http client, storage
│   └── utils/                      pure helpers (format, dates)
├── assets/                         images, fonts, icons
├── .env.example                    documented env vars (no secrets)
└── README.md
```

Tests sit **next to the file they test** (`button.tsx` + `button.test.tsx`, `pricing.ts` + `pricing.test.ts`), so changing a file shows its test right beside it. A root `__tests__/` only holds shared test helpers (`__tests__/utils.tsx` with `renderWithProviders`).

Create only folders that will have something in them right away (a small real file, not `.gitkeep`). On a fresh scaffold that means one example feature (e.g. `home` with `screens/home-screen.tsx` and `index.ts`) wired to the first route.

## The three rules

1. **`app/` files only declare routes.** A route file re-exports a screen from a feature's public API; at most it adds route-only exports (`unstable_settings`, `generateStaticParams`) or a layout. No UI, no data fetching, no logic.
2. **Features talk to each other only through `index.ts`.** `import { CoffeeCard, useCoffee } from '@/features/coffee'` — never `@/features/coffee/components/coffee-card`. Inside a feature, use relative imports (`./components/coffee-card`).
3. **Shared code doesn't import features.** `components/`, `theme/`, `lib/`, `utils/` must not import from `@/features/*`. If shared code needs something from a feature, the thing belongs in shared code.

Plus one data rule: **only `api.ts` (and tests) import `mocks.ts`.** Screens and components get data through hooks, so swapping in the real API is a change to `api.ts` only.

`index.ts` exports only what other code uses — screens for the routes, and whatever another feature genuinely needs. Prefer explicit named re-exports over `export *` (keeps the public surface visible and avoids accidental cycles):

```ts
// src/features/coffee/index.ts
export { ProductDetailScreen } from './screens/product-detail-screen';
export { CoffeeCard } from './components/coffee-card';
export { useCoffee, useCoffees } from './hooks';
export type { Coffee, CoffeeSize } from './types';
```

App-wide state that isn't a feature (the signed-in session) lives in its own feature, e.g. `features/auth/` (`store.ts`, `screens/onboarding-screen.tsx`, `index.ts`).

## Enforce the rules with ESLint

Add to `eslint.config.js` (flat config) after the existing entries. Later entries override earlier ones for matching files, which is why the shared-code block repeats the deep-import pattern.

```js
const deepFeatureImport = {
  group: ['@/features/*/*'],
  message: "Import from the feature's public API ('@/features/<name>'); inside a feature use relative imports.",
};
const mocksImport = {
  group: ['**/mocks', './mocks', '../mocks'],
  message: 'Only api.ts and tests may import mocks — get data through the feature hooks.',
};

// in the defineConfig([...]) array:
{
  files: ['src/**/*.{ts,tsx}'],
  ignores: ['src/features/*/api.ts', 'src/**/*.test.{ts,tsx}'],
  rules: { 'no-restricted-imports': ['error', { patterns: [deepFeatureImport, mocksImport] }] },
},
{
  files: ['src/components/**', 'src/theme/**', 'src/lib/**', 'src/utils/**'],
  rules: {
    'no-restricted-imports': ['error', {
      patterns: [deepFeatureImport, mocksImport, { group: ['@/features', '@/features/*'], message: 'Shared code must not depend on features.' }],
    }],
  },
},
```

Run `npx eslint src` after adding it; it must pass on the scaffold. (Verified: it flags deep feature imports, shared code importing features, and screens importing mocks, and allows `api.ts`/tests to import mocks.)

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
  - Move the theme into `src/theme/`: `src/constants/theme.ts` → `src/theme/tokens.ts`, `src/hooks/use-theme.ts` → `src/theme/use-theme.ts`, `src/components/themed-text.tsx` / `themed-view.tsx` → `src/theme/`. Keep their export names and fix the imports (`grep -rl "@/constants/theme\|@/hooks/use-theme\|themed-" src`).
  - Turn the demo home route into the first feature: `src/features/home/screens/home-screen.tsx` + `index.ts`, and make `src/app/index.tsx` a one-line re-export. Delete the `explore` demo route and its demo components only when replacing them (or when the dev wants a blank start; the template's `npm run reset-project` does this too).
  - If an older template puts routes in `app/` at the root, move them under `src/` (expo-router detects `src/app` automatically).
- **CLI template**: create `src/features/home/screens/home-screen.tsx` from `App.tsx`'s content, keep a small `src/app/App.tsx` that sets up providers and navigation, and point `index.js` at it.

After moving, run `npx tsc --noEmit`, `npx eslint src`, and start the app once to confirm nothing broke.

## Env vars

- Expo: variables prefixed `EXPO_PUBLIC_` in `.env` are available as `process.env.EXPO_PUBLIC_…`. Put documented placeholders in `.env.example`; add `.env` to `.gitignore`. Read them in one place (`src/lib/env.ts`) rather than throughout the code.
- CLI: no built-in env loading. Don't add a library unless the dev asks; mention `react-native-config` as the usual choice.
