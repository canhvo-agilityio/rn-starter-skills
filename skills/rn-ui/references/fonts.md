# Fonts

React Native doesn't pick a weight file from `fontWeight` reliably across platforms. **One `fontFamily` value per weight** is the rule; the typography tokens hide this from screens.

## Add a Google Font

```bash
bash "<skill-dir>/scripts/google-font.sh" "Inter" 400,500,600,700 <project-dir>
```

Weights: `100`–`900`, add `i` for italic (`400i`). Exit code 3 = not a Google Font. Last lines of output:

```
font 400 Inter_400Regular import { Inter_400Regular } from '@expo-google-fonts/inter/400Regular'   ← Expo
font 700 Inter-Bold                                                                           ← CLI
```

## Expo: load at startup

Fonts load at runtime with `expo-font` (works in Expo Go). Load them in the root layout and keep the splash screen up until they're ready:

```tsx
// src/app/_layout.tsx (expo-router) — merge into the existing layout, don't replace it
import * as SplashScreen from 'expo-splash-screen';
import { useFonts } from 'expo-font';
import { Inter_400Regular } from '@expo-google-fonts/inter/400Regular';
import { Inter_500Medium } from '@expo-google-fonts/inter/500Medium';
import { Inter_600SemiBold } from '@expo-google-fonts/inter/600SemiBold';
import { Inter_700Bold } from '@expo-google-fonts/inter/700Bold';
import { useEffect } from 'react';

SplashScreen.preventAutoHideAsync();

export default function RootLayout() {
  const [loaded, error] = useFonts({ Inter_400Regular, Inter_500Medium, Inter_600SemiBold, Inter_700Bold });
  useEffect(() => {
    if (loaded || error) SplashScreen.hideAsync();
  }, [loaded, error]);
  if (!loaded && !error) return null;
  // ...existing layout JSX
}
```

`src/theme/fonts.ts`:

```ts
export const fonts = {
  regular: 'Inter_400Regular',
  medium: 'Inter_500Medium',
  semibold: 'Inter_600SemiBold',
  bold: 'Inter_700Bold',
} as const;
```

The keys passed to `useFonts` are the `fontFamily` names — keep them identical to the import names.

## React Native CLI: native assets

`google-font.sh` copies TTFs to `assets/fonts/<PostScriptName>.ttf`, ensures `react-native.config.js` has `assets: ['./assets/fonts']`, and runs `npx react-native-asset` (adds them to `Info.plist` and `android/app/src/main/assets/fonts`). Then:

```ts
export const fonts = { regular: 'Inter-Regular', medium: 'Inter-Medium', semibold: 'Inter-SemiBold', bold: 'Inter-Bold' } as const;
```

Fonts are native assets: **rebuild** the app (`pod install` + `run-ios`, `run-android`); a Metro reload isn't enough.

## Fonts that aren't on Google Fonts

Ask the dev for the `.ttf`/`.otf` files and confirm they're licensed for app embedding. Then:
- Expo: copy to `assets/fonts/`, load with `useFonts({ 'Brand-Bold': require('../../assets/fonts/Brand-Bold.ttf') })`.
- CLI: copy to `assets/fonts/` named after the PostScript name (`python3 <skill-dir>/scripts/ttf-name.py file.ttf`), run `npx react-native-asset`, rebuild.

## Checking it worked

In the screenshot comparison, headings in a custom font look visibly different from the system font (look at `a`, `g`, `R`). If text still renders in the system font: the `fontFamily` string doesn't match the loaded name (Expo: `useFonts` key; CLI: PostScript name), or the CLI app wasn't rebuilt.
