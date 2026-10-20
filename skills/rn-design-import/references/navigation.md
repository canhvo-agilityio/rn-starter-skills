# Navigation

Build the tree from the spec. Every screen must be reachable by tapping, and by URL so Phase 5 can open it directly.

## expo-router (Expo default)

Routes are files. Groups in parentheses don't appear in the URL. Route files stay thin: layouts hold navigators and providers; every other route file re-exports a screen from its feature (`conventions.md`).

```
src/app/
  _layout.tsx              root Stack + providers + font loading + auth guard
  (auth)/_layout.tsx       Stack, no header
  (auth)/login.tsx         /login        export { LoginScreen as default } from '@/features/auth';
  (auth)/register.tsx      /register
  (tabs)/_layout.tsx       Tabs
  (tabs)/index.tsx         /             export { HomeScreen as default } from '@/features/home';
  (tabs)/search.tsx        /search
  (tabs)/profile.tsx       /profile
  detail/[id].tsx          /detail/123   (pushed on top of tabs)
  settings.tsx             /settings
```

Screens read route params with `useLocalSearchParams()` inside the screen component; nothing extra is needed in the route file.

Auth with a mock session — `Stack.Protected` keeps signed-out users on auth screens:

```tsx
// src/app/_layout.tsx (inside RootLayout, after fonts are loaded)
const isSignedIn = useSession((s) => s.isSignedIn); // mock store, see below
return (
  <Stack screenOptions={{ headerShown: false }}>
    <Stack.Protected guard={!isSignedIn}>
      <Stack.Screen name="(auth)" />
    </Stack.Protected>
    <Stack.Protected guard={isSignedIn}>
      <Stack.Screen name="(tabs)" />
      <Stack.Screen name="detail/[id]" options={{ headerShown: true, title: '' }} />
    </Stack.Protected>
  </Stack>
);
```

Mock session: `src/features/auth/store.ts` (exported from `@/features/auth`) with Zustand if the project uses it (`signIn()` / `signOut()` flip a boolean), else a small React context. Mark both with `// TODO: real auth`.

`Stack.Protected` hides routes; it does **not** redirect. A signed-out deep link to a protected route, or signing out while on a protected screen, shows "Unmatched Route". So navigate explicitly:

```ts
const onLogin = () => { signIn(); router.replace('/'); };
const onLogout = () => { signOut(); router.replace('/login'); };
```

Let verification start signed in without tapping through Login — initialize the mock from an env flag:

```ts
// src/features/auth/store.ts
const initiallySignedIn = process.env.EXPO_PUBLIC_MOCK_SIGNED_IN === '1';
```

`EXPO_PUBLIC_MOCK_SIGNED_IN=1 npx expo start` then opens directly on the tabs (env vars are read at server start).

Tabs:

```tsx
// src/app/(tabs)/_layout.tsx
import { Tabs } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useTheme } from '@/theme';

export default function TabsLayout() {
  const { colors } = useTheme();
  return (
    <Tabs screenOptions={{ headerShown: false, tabBarActiveTintColor: colors.primary }}>
      <Tabs.Screen name="index" options={{ title: 'Home', tabBarIcon: ({ color, size }) => <Ionicons name="home" color={color} size={size} /> }} />
      {/* one per tab */}
    </Tabs>
  );
}
```

**Icons:** use the icon library the project already has (`detect-project.sh` → `icons`). Expo SDK 58's `default` template uses `expo-symbols` with native tabs (`sf` names on iOS, `md` Material names on Android) and does **not** include `@expo/vector-icons`. The example above assumes `@expo/vector-icons`; install it with `npx expo install @expo/vector-icons` only when the project has no icon set.

**Native tabs** (`nativeTabs: true`, e.g. the SDK 58 template's `src/components/app-tabs.tsx`): adapt that file instead of adding a second tab system. Screens inside native tabs must not add `insets.top` manually — the tab container already accounts for part of it and you get a double gap. Use `SafeAreaView` from `react-native-safe-area-context` with `edges={['top']}`.

Remove the template's demo routes and demo components (`explore.tsx`, splash/logo overlays, hint rows) when the design replaces them, and list anything left behind in Open points.

Links: `router.push('/detail/42')`, `<Link href="/settings">`.

## React Navigation (CLI default, or Expo without router)

```
src/navigation/
  RootNavigator.tsx    native-stack: Auth | Main | Detail …, chosen by mock session
  MainTabs.tsx         bottom-tabs
  linking.ts           deep link config
  types.ts             typed param lists
```

Install: `@react-navigation/native @react-navigation/native-stack @react-navigation/bottom-tabs react-native-screens react-native-safe-area-context` (Expo: `npx expo install …`). Type the param lists and use `NativeStackScreenProps` in screens.

`linking.ts`:

```ts
export const linking = {
  prefixes: ['<scheme>://'],
  config: {
    screens: {
      Login: 'login',
      Main: { screens: { Home: '', Search: 'search', Profile: 'profile' } },
      Detail: 'detail/:id',
    },
  },
};
```

CLI apps need the scheme registered natively for deep links: iOS `Info.plist` → `CFBundleURLTypes` with the scheme; Android `AndroidManifest.xml` → an `intent-filter` with `<data android:scheme="<scheme>" />` on MainActivity. Use the app's slug as scheme. Rebuild after editing native files.

## Deep links for verification

| Setup | iOS Simulator | Android emulator |
|---|---|---|
| Expo Go | `xcrun simctl openurl booted "exp://127.0.0.1:8081/--/detail/1"` | `adb shell am start -a android.intent.action.VIEW -d "exp://127.0.0.1:8081/--/detail/1"` |
| CLI / dev build | `xcrun simctl openurl booted "<scheme>://detail/1"` | `adb shell am start -a android.intent.action.VIEW -d "<scheme>://detail/1" <package>` |

Use the dev server's actual port, and `127.0.0.1` rather than the LAN IP Expo prints (the simulator/emulator reaches Metro on localhost; the LAN address can time out on corporate Wi-Fi). Capture auth screens signed out, then restart with `EXPO_PUBLIC_MOCK_SIGNED_IN=1` (see above) for the rest.
