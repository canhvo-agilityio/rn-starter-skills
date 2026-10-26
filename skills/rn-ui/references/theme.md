# Theme

**Contents:** Pick the setup from the project · 1. Tokens (every setup) · 2. Light, dark and the user's choice (every setup) · 3. StyleSheet only (no UI library) — the default · 4. Unistyles 3 · 5. NativeWind · 6. With a UI library · Default scales when the design doesn't define them

One source of truth for colors, typography, spacing, radii and shadows. Screens and components read from it; nothing else hard-codes a visual value.

## Pick the setup from the project

Read `styling` and `uiLibrary` from `detect-project.sh`. The tokens (section 1) and light/dark handling (section 2) are the same everywhere; only where the theme is registered and how components read it changes.

| Project uses | Theme lives in | Components read it with | Section |
|---|---|---|---|
| A UI library (Paper, Tamagui, gluestack-ui, …) | the library's theme config, filled from the tokens | the library's components, props and theme hook | 6 |
| Unistyles | `StyleSheet.configure({ themes })` | `StyleSheet.create((theme) => …)` | 4 |
| NativeWind | CSS variables per scheme | `className` | 5 |
| StyleSheet only (default) | `src/theme/` | `useTheme()`, theme-aware styles | 3 |

- **Project already has a theme** (e.g. Expo SDK 58's `default` template ships `src/constants/theme.ts`, `src/hooks/use-theme.ts` and `src/components/themed-text.tsx`; rn-starter moves them to `src/theme/`): extend it and keep its exports and return shapes — the template's components depend on them. For the SDK 58 template:
  - `useTheme()` returns the color object directly (`const colors = useTheme()`), not `{ colors }`. Keep that; add new color names to both its light and dark palettes, and export typography/radius/shadow as separate constants next to it.
  - Its spacing scale (2/4/8/16/24/32/64, named keys) wins over the numeric scale below — reuse it, add steps only if the design needs them.
  - Add the design's text variants to `ThemedText` (and adjust its sizes, e.g. its `title` is 48) instead of creating a second Text component.
- **Never run two theme systems.** With a UI library, the library's theme is the theme. A separate `useTheme()` next to it drifts within weeks.

### Colors from a later design

A new design for an app that already has a theme repeats most of its colors, often a step off (exported from another file, picked by hand, rounded). Taking them literally gives `primary2` next to `primary`. Match each color in the new design against the existing tokens, in both palettes when the app has dark mode:

| The new color | Do |
|---|---|
| Every RGB channel within 3 of a token (`#C67C4F` vs `primary #C67C4E`) | use that token; the difference is noise |
| Further off, but in the same role as a token (an error red `#E5484D` next to `danger #ED5151`) | ask the dev: use the existing token (Recommended) / add a new token for this use / change the existing token everywhere |
| No token in that role (a soft green badge fill) | add a semantic token named for the role (`successSoft`, `onDangerSoft`), to light and dark |

Never change the value of an existing token unless the dev picks that option: it repaints every screen built on it. List the mapping (design color → token, or new token) in the spec's Theme section, so the designer can see which colors were merged.

## 1. Tokens (every setup)

Two layers. Raw values (a palette scale, only if the design defines one) feed **semantic** names, and components use only the semantic names. Light and dark have the same keys, enforced by the type:

```ts
// src/theme/colors.ts
const light = {
  primary: '#2563EB',
  onPrimary: '#FFFFFF',
  background: '#FFFFFF',
  surface: '#F8FAFC',
  text: '#0F172A',
  textMuted: '#64748B',
  border: '#E2E8F0',
  danger: '#DC2626',
  success: '#16A34A',
};

export type ThemeColors = typeof light;

const dark: ThemeColors = {
  primary: '#3B82F6',
  onPrimary: '#FFFFFF',
  background: '#0B1120',
  surface: '#111827',
  text: '#F1F5F9',
  textMuted: '#94A3B8',
  border: '#1F2937',
  danger: '#F87171',
  success: '#4ADE80',
};

export const palette = { light, dark };
export type ColorName = keyof ThemeColors;
```

Every fill color that carries text gets an `on…` pair (`primary` / `onPrimary`), so contrast is decided once, in the tokens. If the design has no dark version and the dev didn't ask for one, keep the shape with `dark` equal to `light` (adding dark mode later is then only a palette change), lock the app to light as section 2 describes, and note it in Open points.

Non-color tokens don't change with the scheme:

```ts
// src/theme/tokens.ts
export const spacing = { 0: 0, 1: 4, 2: 8, 3: 12, 4: 16, 5: 20, 6: 24, 8: 32, 10: 40, 12: 48 } as const;
export const radius = { sm: 6, md: 10, lg: 16, xl: 24, full: 999 } as const;
export const shadow = {
  card: { boxShadow: '0 2px 8px rgba(15, 23, 42, 0.08)' },
} as const;
```

```ts
// src/theme/typography.ts — each variant sets the fontFamily for its weight (fonts.md)
import { fonts } from './fonts';

export const typography = {
  display: { fontFamily: fonts.bold, fontSize: 32, lineHeight: 40 },
  title: { fontFamily: fonts.bold, fontSize: 24, lineHeight: 32 },
  heading: { fontFamily: fonts.semibold, fontSize: 18, lineHeight: 26 },
  body: { fontFamily: fonts.regular, fontSize: 16, lineHeight: 24 },
  bodyStrong: { fontFamily: fonts.medium, fontSize: 16, lineHeight: 24 },
  caption: { fontFamily: fonts.regular, fontSize: 13, lineHeight: 18 },
} as const;
export type TextVariant = keyof typeof typography;
```

These files are plain data, so the same values feed any setup below: a UI library's theme, Unistyles' themes, or NativeWind's CSS variables.

## 2. Light, dark and the user's choice (every setup)

- **The design decides the scheme, not the device.**
  - **Design has light and dark** → follow the system. Expo: `"userInterfaceStyle": "automatic"` in `app.json` (the default template has it). CLI: don't pin `UIUserInterfaceStyle` in `Info.plist`, and keep the Android app theme on a `DayNight` parent.
  - **Design has only one scheme** (the usual case) → lock the app to it, so a phone in dark mode still shows the design. Expo: `"userInterfaceStyle": "light"` (or `"dark"` for a dark-only design) in `app.json`; it takes effect after a native rebuild or a restart of Expo Go. CLI: `UIUserInterfaceStyle` = `Light` in `Info.plist` and a `Light` (not `DayNight`) parent for the Android app theme. Then set the status bar style explicitly (`<StatusBar style="dark" />` on a light design), use the light navigation theme only, and skip the user override below. Otherwise, on a phone in dark mode, `style="auto"` puts white status-bar text on the design's white background, and the stock `DarkTheme` recolors headers and tab bars.
- **Let the user override it only when the design has both schemes and a setting for it** (System / Light / Dark). On StyleSheet projects, apply the choice with `Appearance.setColorScheme(choice === 'system' ? 'auto' : choice)`: `useColorScheme()` then returns the override everywhere, and native Alerts and pickers follow it, so no theme context is needed. React Native 0.88 accepts `'auto'`. Older versions use `'unspecified'`, so check what the project's types accept. Unistyles, NativeWind and the UI libraries have their own switch (their sections). Store the choice with the project's storage (MMKV / AsyncStorage) and apply it before the first screen renders. If the project has no storage library, ask before adding one only to remember this.
- **Theme what's around the screens too:**
  - the navigation container: give React Navigation / expo-router's `ThemeProvider` a theme built from the tokens, not the stock `DarkTheme`, so headers and tab bars match:
    ```ts
    const navTheme = {
      ...(scheme === 'dark' ? DarkTheme : DefaultTheme),
      colors: {
        ...(scheme === 'dark' ? DarkTheme : DefaultTheme).colors,
        primary: colors.primary, background: colors.background, card: colors.surface,
        text: colors.text, border: colors.border,
      },
    };
    ```
  - the status bar: `<StatusBar style="auto" />` from `expo-status-bar` (CLI: `barStyle` from the scheme). A screen whose header needs another style (light text on a dark header) sets its own, and **inside tabs only while focused**: tab screens stay mounted after you leave them, and the most recently mounted `StatusBar` wins, so a hidden tab keeps forcing its style onto the visible one. Render it through a small shared component:
    ```tsx
    // src/components/focused-status-bar.tsx
    import { useIsFocused } from 'expo-router'; // React Navigation: '@react-navigation/native'
    import { StatusBar, type StatusBarStyle } from 'expo-status-bar';

    interface FocusedStatusBarProps {
      style: StatusBarStyle;
    }

    export const FocusedStatusBar = ({ style }: FocusedStatusBarProps) =>
      useIsFocused() ? <StatusBar style={style} /> : null;
    ```
    Check it in Phase 5 by switching tabs in both directions (dark-header tab → light tab → back), not only by opening each tab fresh;
  - the root background, so dark mode doesn't flash white on launch or behind modals: `SystemUI.setBackgroundColorAsync(colors.background)` from `expo-system-ui` (Expo), or the native window background (CLI).

## 3. StyleSheet only (no UI library) — the default

What the sources do, and what follows from it:

- React Native: `StyleSheet.create` is an identity function. It type-checks the styles but gives no runtime speed-up, so the only costs worth managing are building style objects and re-rendering.
- Expo's color-themes guide defines a static style per scheme and picks one with the color scheme (`colorScheme === 'light' ? styles.lightContainer : styles.darkContainer`). Nothing is built while rendering.
- React Navigation's theming guide reads `useTheme()` and passes colors inline (`style={{ backgroundColor: colors.card }}`).
- Ignite (Infinite Red) puts the theme in a context with a `themed($style)` helper. That helper builds new style objects on every render.
- `makeStyles` hooks (React Native Elements, many team codebases) memoize per component instance, so a list of 200 rows holds 200 copies.

The setup below keeps Expo's idea (styles built per scheme, not per render) and makes it reusable. Theme-dependent styles are built at most once per scheme for the whole app and shared by every instance.

```
src/theme/
  colors.ts                  light + dark semantic palettes (section 1)
  tokens.ts                  spacing, radius, shadow
  typography.ts              text variants
  fonts.ts                   font family per weight (fonts.md)
  index.ts                   themes + useTheme()
  create-themed-styles.ts    theme-dependent styles, cached per scheme
```

```ts
// src/theme/index.ts
import { useColorScheme } from 'react-native';

import { palette } from './colors';
import { radius, shadow, spacing } from './tokens';
import { typography } from './typography';

// Built once at module load: useTheme() returns the same object for a scheme on every render.
export const themes = {
  light: { scheme: 'light', colors: palette.light, spacing, radius, shadow, typography },
  dark: { scheme: 'dark', colors: palette.dark, spacing, radius, shadow, typography },
} as const;
export type Theme = (typeof themes)[keyof typeof themes];

export const useTheme = (): Theme => themes[useColorScheme() === 'dark' ? 'dark' : 'light'];
export { palette, radius, shadow, spacing, typography };
```

```ts
// src/theme/create-themed-styles.ts
import { type ImageStyle, StyleSheet, type TextStyle, type ViewStyle } from 'react-native';

import { type Theme, useTheme } from './index';

// React Native 0.88 no longer exports StyleSheet.NamedStyles.
type NamedStyles<T> = { [P in keyof T]: ViewStyle | TextStyle | ImageStyle };

// Theme-dependent styles are built at most once per scheme for the whole app and shared by every
// instance, so a long list doesn't build one copy per row or per render.
export const createThemedStyles = <T extends NamedStyles<T>>(factory: (theme: Theme) => T) => {
  const cache = new Map<Theme['scheme'], T>();
  return function useThemedStyles() {
    const theme = useTheme();
    let styles = cache.get(theme.scheme);
    if (!styles) {
      styles = StyleSheet.create(factory(theme));
      cache.set(theme.scheme, styles);
    }
    return styles;
  };
};
```

Writing styles in a component — split by whether the value changes with the scheme:

```tsx
export const ProductCard = ({ product }: ProductCardProps) => {
  const themed = useThemedStyles();
  return (
    <View style={[styles.card, themed.card]}>
      <Text style={[styles.name, themed.name]}>{product.name}</Text>
    </View>
  );
};

// Layout, spacing, radius, typography: never change, built once.
const styles = StyleSheet.create({
  card: { padding: spacing[4], borderRadius: radius.md },
  name: { ...typography.bodyStrong },
});

// Colors: built once per scheme, shared by every ProductCard.
const useThemedStyles = createThemedStyles(({ colors }) => ({
  card: { backgroundColor: colors.surface, borderColor: colors.border },
  name: { color: colors.text },
}));
```

- A component with a single color can skip the helper: `const { colors } = useTheme()` and `style={[styles.name, { color: colors.text }]}`.
- If the project already has its own pattern (`makeStyles`, Ignite's `themed`, inline colors), follow it. Don't introduce a second one.
- Every component that reads the theme re-renders when the scheme changes. That's rare, so it's fine. Don't add a React context for the theme: `useColorScheme()` already updates every consumer, and `Appearance.setColorScheme` handles the user's override (section 2). Only Unistyles (section 4) avoids those re-renders.

If the project has no themed Text component yet, generate one (`src/components/text.tsx` or the project's naming) with a `variant` prop (`TextVariant`) and an optional `color` prop (`ColorName`). Screens then never touch font families directly. If it has one (e.g. `ThemedText`), extend it.

## 4. Unistyles 3

Best when the app doesn't run in Expo Go: styles are plain `StyleSheet.create` calls that read the theme, and a theme change updates them natively without re-rendering components. It needs the New Architecture, React Native 0.81+ / Expo SDK 54+, `react-native-nitro-modules` and a dev build, so it never runs in Expo Go.

```ts
// src/theme/unistyles.ts — imported once, before anything renders (e.g. top of the root layout / index.js)
import { StyleSheet } from 'react-native-unistyles';

import { palette } from './colors';
import { radius, shadow, spacing } from './tokens';
import { typography } from './typography';

const base = { spacing, radius, shadow, typography };
const themes = {
  light: { ...base, colors: palette.light },
  dark: { ...base, colors: palette.dark },
};

type AppThemes = typeof themes;
declare module 'react-native-unistyles' {
  export interface UnistylesThemes extends AppThemes {}
}

StyleSheet.configure({ themes, settings: { adaptiveThemes: true } });
```

```ts
// in a component file
import { StyleSheet } from 'react-native-unistyles';

const styles = StyleSheet.create((theme) => ({
  card: { backgroundColor: theme.colors.surface, padding: theme.spacing[4] },
}));
```

`adaptiveThemes: true` follows the system and needs themes named `light` and `dark`. For a user override, call `UnistylesRuntime.setAdaptiveThemes(false)` then `UnistylesRuntime.setTheme('dark')`; `setTheme` throws while adaptive themes are on. `adaptiveThemes` and `initialTheme` can't both be set. Avoid `useUnistyles()` in components, because it re-renders on every theme change; `StyleSheet.create` is the intended path.

## 5. NativeWind

Colors become CSS variables with a value per scheme, so `bg-surface` switches without `dark:` variants on every element:

```ts
// src/theme/nativewind-vars.ts — values from colors.ts as "R G B" so opacity modifiers (bg-primary/50) work
import { vars } from 'nativewind';

export const themeVars = {
  light: vars({ '--color-primary': '37 99 235', '--color-surface': '248 250 252', '--color-text': '15 23 42' }),
  dark: vars({ '--color-primary': '59 130 246', '--color-surface': '17 24 39', '--color-text': '241 245 249' }),
};
```

```js
// tailwind.config.js
theme: {
  extend: {
    colors: {
      primary: 'rgb(var(--color-primary) / <alpha-value>)',
      surface: 'rgb(var(--color-surface) / <alpha-value>)',
      text: 'rgb(var(--color-text) / <alpha-value>)',
    },
    fontFamily: { sans: ['Inter_400Regular'], medium: ['Inter_500Medium'], semibold: ['Inter_600SemiBold'], bold: ['Inter_700Bold'] },
    borderRadius: { md: '10px', lg: '16px' },
  },
},
```

Apply `themeVars[colorScheme]` as the `style` of the root view (`const { colorScheme } = useColorScheme()` from `nativewind`). For a user override, call `colorScheme.set('light' | 'dark')` from `nativewind`. It uses the `Appearance` API on native, and the Expo app still needs `userInterfaceStyle: "automatic"`. Use `font-bold` etc. only if each weight is mapped to its family as above (RN doesn't synthesize weights from one family). Restart Metro with the cache cleared after editing the config. NativeWind 5 is a release candidate that moves this config into `global.css` (`@theme`); if the project is on v5, follow its docs.

## 6. With a UI library

The library's theme is the single source of truth. Put the design's tokens into its theme config once, use its components, and read its theme hook in your own components. Don't build a parallel `src/theme/useTheme()`: keep `colors.ts` / `tokens.ts` as plain data and import them into the library's config. Map the design's semantic names onto the library's color roles first, and add custom keys only for what has no role.

- **React Native Paper (5.x, Material 3)** — extend `MD3LightTheme` / `MD3DarkTheme`:
  ```ts
  import { MD3DarkTheme, MD3LightTheme, useTheme } from 'react-native-paper';

  export const lightTheme = {
    ...MD3LightTheme,
    colors: { ...MD3LightTheme.colors, primary: palette.light.primary, surface: palette.light.surface, success: palette.light.success },
  };
  export const darkTheme = { ...MD3DarkTheme, colors: { ...MD3DarkTheme.colors, /* same keys from palette.dark */ } };
  export type AppTheme = typeof lightTheme;
  export const useAppTheme = () => useTheme<AppTheme>();
  ```
  `<PaperProvider theme={scheme === 'dark' ? darkTheme : lightTheme}>` at the root. Build the navigation theme from the same colors as in section 2 (`card: colors.surface`, `text: colors.onSurface`, `border: colors.outlineVariant`). Don't use Paper's `adaptNavigationTheme`: on Expo SDK 58 it fails type checking against React Navigation 7. Put fonts in the theme's `fonts` variants (`bodyMedium`, `titleLarge`, …), not on each `Text`. Follow the scheme with `useColorScheme()` / `Appearance.setColorScheme` as in section 2.
- **Tamagui** — put the design's colors into `themes.light` / `themes.dark` of the project's `createTamagui` config (spread over the existing themes), keep the `TamaguiCustomConfig` declaration, and pass the scheme with `<TamaguiProvider config={config} defaultTheme={scheme}>`. How components reference theme values changed between major versions (v3 rejects the `$primary` form older docs show), so copy the form the project's existing components use, and type-check.
- **gluestack-ui** — the tokens are CSS variables per mode in `components/ui/gluestack-ui-provider/config.ts` (`light: vars({ '--color-primary': '37 99 235', … })`, same for `dark`), mapped to Tailwind colors as section 5 describes. Switch with `<GluestackUIProvider mode="system" | "light" | "dark">`. Its init CLI hard-codes `mode="dark"`; set it to `"system"` (or the user's choice).
- **NativeWind-based kits** (React Native Reusables and similar) — CSS variables per scheme, exactly as section 5.
- **Anything else** (React Native Elements `createTheme({ lightColors, darkColors })`, UI Kitten, RN UI Lib, a company kit) — find the library's theme API in its docs, then apply the same rule.

Components the library doesn't have (a rating row, a product card) are built from its primitives and read its theme. Don't fall back to raw `StyleSheet` colors for them.

## Default scales when the design doesn't define them

- Spacing: 4-pt grid above.
- Type: 32 / 24 / 18 / 16 / 13, line height ≈ 1.3–1.5×.
- Neutrals: slate-like grays (as in the palette above); derive `primary` pressed/disabled by darkening 10% / 40% opacity.
- Contrast: body text vs background ≥ 4.5:1. If a design color fails, keep it but note it in Open points.
