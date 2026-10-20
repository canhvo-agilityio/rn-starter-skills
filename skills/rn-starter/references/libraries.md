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
| **Zustand** | `zustand` | `src/features/<feature>/store.ts` with `create()`, exported from the feature's `index.ts`; use it in one screen so the dev sees the pattern |
| **Redux Toolkit** | `@reduxjs/toolkit react-redux` | `src/lib/store.ts` with `configureStore`, slices in `src/features/<feature>/slice.ts`, `<Provider>` at root, typed `useAppDispatch`/`useAppSelector` hooks |
| **Jotai** | `jotai` | atoms in `src/features/<feature>/atoms.ts`, used in one screen |

All pure JS — work in Expo Go.

## Server data

| Option | Install | Minimal setup |
|---|---|---|
| **TanStack Query** | `@tanstack/react-query` | `QueryClient` in `src/lib/query-client.ts`, `QueryClientProvider` at root (`src/app/_layout.tsx` for expo-router, or `App.tsx`); one `useQuery` example in a feature's `hooks.ts` over its `api.ts` |

## Styling

| Option | Install | Notes |
|---|---|---|
| **StyleSheet** | nothing | add `src/theme/` with colors + spacing tokens |
| **NativeWind** | follow https://www.nativewind.dev/docs/getting-started/installation (Expo and CLI sections differ) | touches babel, metro and tailwind config — do it exactly as the guide says, then restart Metro with cache clear (`npx expo start -c` / `npx react-native start --reset-cache`) |
| **Unistyles** | follow https://www.unistyl.es/v3/start/getting-started | needs `react-native-nitro-modules` → **does not run in Expo Go**; requires a dev build (emulator). Only offer when run target is the emulator |

## Lint & format

| Option | Expo | RN CLI |
|---|---|---|
| **ESLint + Prettier** | `npx expo lint` (creates the Expo ESLint config) then `npx expo install prettier eslint-config-prettier eslint-plugin-prettier --dev` and add `.prettierrc` | template already has ESLint + Prettier configured — keep it |
| **Biome** | `<pm> add -D @biomejs/biome` then `npx biome init`; remove ESLint/Prettier configs if present | same |

Add scripts to `package.json`: `"lint"`, `"format"`, `"typecheck": "tsc --noEmit"`. Run `lint` once and fix what it reports in the generated code.
