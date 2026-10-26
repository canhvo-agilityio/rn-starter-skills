# Libraries

Install rule:
- **Expo**: `npx expo install <pkgs>` — picks versions that match the project's Expo SDK. Never plain `npm install` for packages with native code.
- **RN CLI**: `<pm> add <pkgs>` (`npm install` for npm). On Android, autolinking picks up native modules at the next build.

For setup steps longer than a few lines, fetch the linked official guide and follow it — it is more current than anything copied here. After setup, the app must still start; check that before moving on.

## Navigation

| Option | Install | Setup | Expo Go |
|---|---|---|---|
| **expo-router** (Expo) | already in `default`/`tabs` templates. For `blank-typescript`: follow https://docs.expo.dev/router/installation/#manual-installation | file-based routes under `app/` (or `src/app/`) | ✓ |
| **React Navigation** | Expo: `npx expo install @react-navigation/native @react-navigation/native-stack react-native-screens react-native-safe-area-context` · CLI: `<pm> add` same list | wrap root in `NavigationContainer`, create a native stack with one `Home` screen. Guide: https://reactnavigation.org/docs/getting-started | ✓ |

## State

| Option | Install | Minimal setup |
|---|---|---|
| **Zustand** | `zustand` | `src/stores/<name>.ts` with `create()` exporting `use<Name>Store`; use it in one screen so the dev sees the pattern |
| **Redux Toolkit** | `@reduxjs/toolkit react-redux` | `src/lib/store.ts` with `configureStore`, slices in `src/stores/<name>-slice.ts`, `<Provider>` at root, typed `useAppDispatch`/`useAppSelector` hooks |
| **Jotai** | `jotai` | atoms in `src/stores/<name>.ts`, used in one screen |

All pure JS — work in Expo Go.

## Server data

| Option | Install | Minimal setup |
|---|---|---|
| **TanStack Query** | `@tanstack/react-query` | `QueryClient` in `src/lib/query-client.ts`, `QueryClientProvider` at root (`src/app/_layout.tsx` for expo-router, or `App.tsx`); one `useQuery` example in `src/hooks/` over a service in `src/services/` |

## Styling

| Option | Install | Notes |
|---|---|---|
| **StyleSheet** | nothing | add `src/theme/` with colors + spacing tokens |
| **NativeWind** | follow https://www.nativewind.dev/docs/getting-started/installation (Expo and CLI sections differ) | touches babel, metro and tailwind config — do it exactly as the guide says, then restart Metro with cache clear (`npx expo start -c` / `npx react-native start --reset-cache`) |
| **Unistyles** | follow https://www.unistyl.es/v3/start/getting-started exactly (it pins the `react-native-nitro-modules` version; on Expo install with `npx expo install`) | needs New Architecture, RN 0.81+ / Expo SDK 54+ and `react-native-nitro-modules` → **never runs in Expo Go**. RN CLI, or Expo with a development build (`devBuild: true`). Only offer when no run target is Expo Go. Theme setup: rn-ui `theme.md` §4 |

## UI component library

Asked only when styling is StyleSheet. The library's theme becomes the app's only theme — set it up as rn-ui `theme.md` §6 describes, with the design's tokens in `src/theme/colors.ts` / `tokens.ts` fed into the library's config.

| Option | Install | Minimal setup |
|---|---|---|
| **None** (Recommended) | — | shared components in `src/components/` on the theme (`theme.md` §3) |
| **React Native Paper** (Material 3) | Expo: `npx expo install react-native-paper react-native-safe-area-context` (icons come with Expo). CLI: `<pm> add react-native-paper react-native-safe-area-context @react-native-vector-icons/material-design-icons`, then `cd ios && pod install` | `PaperProvider` with the light/dark theme from `theme.md` §6 at the root; navigation theme built from the same tokens (§2 — not `adaptNavigationTheme`, see below); `react-native-paper/babel` under `env.production.plugins` in `babel.config.js` for a smaller bundle |

Paper 5.15 was verified on Expo SDK 58: it installs, the §6 theme type-checks, and `expo export` bundles. It's pure JS, so it runs in Expo Go. Its `adaptNavigationTheme` fails type checking against the React Navigation version Expo SDK 58 ships (Paper types navigation colors as `string`, React Navigation 7 as `ColorValue`). Build the navigation theme from the tokens instead.

Not offered by the wizard (tested on Expo SDK 58, October 2026). For a dev who asks via "Other", explain the problem and offer to set the library up by hand after the empty app runs:
- **gluestack-ui** — `npx gluestack-ui@latest init -y --nativewind` ignored `--nativewind`: it installed gluestack-ui v5 alpha with NativeWind v5 RC, added `./*` to the `@/*` alias (so `@/components/…` resolved to the new root `components/` and the bundle broke), and hard-coded `mode="dark"`.
- **Tamagui 3** — the default config failed type checking (token and `ref` types), and the Metro plugin's static evaluation stopped on a missing `@tamagui/react-native-web-lite`.
- **React Native Reusables** — its CLI creates a new project rather than adding to one.

Recheck these with `lib-info.sh` and a scratch app before adding them back; record the result here.

## Lint & format

| Option | Expo | RN CLI |
|---|---|---|
| **ESLint + Prettier** | `npx expo lint` (creates the Expo ESLint config) then `npx expo install prettier eslint-config-prettier eslint-plugin-prettier --dev` and add `.prettierrc` | template already has ESLint + Prettier configured — keep it |
| **Biome** | `<pm> add -D @biomejs/biome` then `npx biome init`; remove ESLint/Prettier configs if present | same |

Add scripts to `package.json`: `"lint"`, `"format"`, `"typecheck": "tsc --noEmit"`. Run `lint` once and fix what it reports in the generated code.
