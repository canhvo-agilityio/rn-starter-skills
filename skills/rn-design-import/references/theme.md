# Theme

One source of truth for colors, typography, spacing, radii and shadows. Screens and components read from it; nothing else hard-codes a visual value.

## Where it goes

- **Project already has a theme** (e.g. Expo SDK 58's `default` template ships `src/constants/theme.ts`, `src/hooks/use-theme.ts` and `src/components/themed-text.tsx`): extend those and keep their existing exports and return shapes — the template's components depend on them. Concretely, for the SDK 58 template:
  - `useTheme()` returns the color object directly (`const colors = useTheme()`), not `{ colors }`. Keep that; add new color names to both its light and dark palettes, and export typography/radius/shadow as separate constants next to it.
  - Its spacing scale (2/4/8/16/24/32/64, named keys) wins over the numeric scale below — reuse it, add steps only if the design needs them.
  - Add the design's text variants to `ThemedText` (and adjust its sizes, e.g. its `title` is 48) instead of creating a second Text component.
  The samples below are for projects **without** a theme.
- **Feature-first projects** set up by rn-starter have these template files moved to `src/theme/` (`tokens.ts`, `use-theme.ts`, `themed-text.tsx`) with the same exports — same rules apply.
- **No theme yet** → create `src/theme/` as below.
- **NativeWind** → tokens live in `tailwind.config.js` (`theme.extend`), see the end of this file.

## StyleSheet projects

```
src/theme/
  colors.ts       light + dark palettes with semantic names
  typography.ts   text variants built on font tokens
  tokens.ts       spacing, radius, shadow
  index.ts        useTheme() + re-exports
```

`colors.ts` — semantic names first; raw scales only if the design defines them:

```ts
export const palette = {
  light: {
    primary: '#2563EB',
    onPrimary: '#FFFFFF',
    background: '#FFFFFF',
    surface: '#F8FAFC',
    text: '#0F172A',
    textMuted: '#64748B',
    border: '#E2E8F0',
    danger: '#DC2626',
    success: '#16A34A',
  },
  dark: {
    primary: '#3B82F6',
    onPrimary: '#FFFFFF',
    background: '#0B1120',
    surface: '#111827',
    text: '#F1F5F9',
    textMuted: '#94A3B8',
    border: '#1F2937',
    danger: '#F87171',
    success: '#4ADE80',
  },
} as const;

export type ColorName = keyof typeof palette.light;
```

If the design has no dark version and the dev didn't ask for one, still keep the `light`/`dark` shape but make `dark` equal to `light` and note it in Open points — adding dark mode later is then only a palette change.

`tokens.ts`:

```ts
export const spacing = { 0: 0, 1: 4, 2: 8, 3: 12, 4: 16, 5: 20, 6: 24, 8: 32, 10: 40, 12: 48 } as const;
export const radius = { sm: 6, md: 10, lg: 16, xl: 24, full: 999 } as const;
export const shadow = {
  card: { boxShadow: '0 2px 8px rgba(15, 23, 42, 0.08)' },
} as const;
```

`typography.ts` — each variant sets `fontFamily` for its weight (see `fonts.md`), size and line height:

```ts
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

`index.ts`:

```ts
import { useColorScheme } from 'react-native';
import { palette } from './colors';
import { spacing, radius, shadow } from './tokens';
import { typography } from './typography';

export function useTheme() {
  const scheme = useColorScheme() === 'dark' ? 'dark' : 'light';
  return { colors: palette[scheme], spacing, radius, shadow, typography, scheme };
}
export { palette, spacing, radius, shadow, typography };
```

Styles that depend on colors are created inside the component (`const { colors } = useTheme()`), or with a small `makeStyles(theme => StyleSheet.create(...))` helper if the project prefers that. Static layout-only styles can stay in a module-level `StyleSheet.create`.

If the project has no themed Text component yet, generate one (`src/components/text.tsx` or the project's naming) with a `variant` prop and an optional `color` prop typed as `ColorName` — screens then never touch font families directly. If it has one (e.g. `ThemedText`), extend it.

## Default scales when the design doesn't define them

- Spacing: 4-pt grid above.
- Type: 32 / 24 / 18 / 16 / 13, line height ≈ 1.3–1.5×.
- Neutrals: slate-like grays (as in the palette above); derive `primary` pressed/disabled by darkening 10% / 40% opacity.
- Contrast: body text vs background ≥ 4.5:1. If a design color fails, keep it but note it in Open points.

## NativeWind projects

```js
// tailwind.config.js
theme: {
  extend: {
    colors: { primary: '#2563EB', surface: '#F8FAFC', muted: '#64748B', border: '#E2E8F0' },
    fontFamily: {
      sans: ['Inter_400Regular'],
      medium: ['Inter_500Medium'],
      semibold: ['Inter_600SemiBold'],
      bold: ['Inter_700Bold'],
    },
    borderRadius: { md: '10px', lg: '16px' },
  },
},
```

Use `font-bold` etc. only if mapped to the family per weight as above (RN doesn't synthesize weights from one family). Dark mode: `dark:` variants, or CSS variables per the NativeWind docs. Restart Metro with cache clear after editing the config.
