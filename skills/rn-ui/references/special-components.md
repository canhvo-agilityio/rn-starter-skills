# Special components (maps, sheets, media, charts…)

**Contents:** 1. Detect (Phase 2) · 2. Check candidates live (don't trust this file's versions) · 3. Ask the dev (one `AskUserQuestion`, one question per special component, max 4) · 4. Catalog · 5. Wrap the library in a component · 6. Verify

Some parts of a design aren't layout + text + images: a map with a route, a draggable bottom sheet, a camera view, a chart. Drawing them with static images and absolute-positioned SVG looks right in a screenshot and is useless in the app. Detect them, pick a real library with the dev, wrap it, and verify it renders.

## 1. Detect (Phase 2)

Look for these in the design and list each one under **Special components** in `docs/design-spec.md`:

| Signal in the design | Need |
|---|---|
| Map tiles, pins, a route line, "my location" button | map (+ location) |
| Panel with a grab handle over content, half-height sheets | bottom sheet |
| Swipeable banners/cards with page dots | carousel / pager |
| Line/bar/pie charts, progress rings with data | charts |
| Video thumbnail with play button, inline player | video |
| Camera viewfinder, QR/barcode frame | camera / scanner |
| "Upload photo", avatar picker | image picker |
| Date/time fields, booking calendars | date picker / calendar |
| Animated illustrations (Lottie-style) | animation |
| Row actions revealed by swiping | swipeable rows |
| Very long or infinite lists | high-performance list |
| Embedded web content, payment pages | web view |
| "Continue with Google / Apple / Facebook" buttons | social sign-in |

Don't over-detect: a static illustration of a map in a marketing banner is an image.

## 2. Check candidates live (don't trust this file's versions)

```bash
bash "<skill-dir>/scripts/lib-info.sh" <project-dir> react-native-maps expo-location
```

It prints, per package: latest npm version, the version pinned by the project's Expo SDK (`not bundled` = not part of the SDK), React Native Directory's New Architecture and Expo Go status, whether it's maintained, and the last push.

Rules:
- **Unmaintained → don't propose it** (pick the alternative; mention why if the dev asked for it).
- **New Architecture**: React Native 0.82+ only runs the New Architecture. `true`/`new-arch-only` is fine; `unknown` → tell the dev it's untested and check the library's README/issues before committing to it.
- **Expo + "not bundled" + native code** → not available in Expo Go; needs a development build (`npx expo run:ios|android`, i.e. the simulator/emulator toolchain). If the dev only runs in Expo Go, prefer a bundled option or a placeholder. Pure-JS libraries (e.g. `@gorhom/bottom-sheet`, built on bundled reanimated/gesture-handler) work in Expo Go even though they're "not bundled".

## 3. Ask the dev (one `AskUserQuestion`, one question per special component, max 4)

Options per component:
1. **The recommended library (Recommended)** — one line on what it gives and what it needs (API key, permission, dev build).
2. **Static placeholder for now** — image/mock UI clearly marked `// TODO: replace with <library>`; useful when the screen is only a UI preview.
3. **Other** — the dev names a library (e.g. Mapbox). Run `lib-info.sh` on it before agreeing.

Say the requirements up front, e.g. "Android needs a Google Maps API key to show tiles in a native build — do you have one?" The dev adds keys themselves (in `.env` / native config); never ask them to paste secrets into the chat.

## 4. Catalog

Defaults per framework. Expo projects use `npx expo install` (SDK-matched versions) and config plugins in `app.json`; RN CLI projects use `<pm> add`, then `cd ios && pod install`, then a **rebuild** — native code doesn't arrive through a Metro reload.

| Need | Expo | RN CLI | Native setup on CLI |
|---|---|---|---|
| Map | `react-native-maps` (in Expo Go) | `react-native-maps` | Android: Google Maps API key in `AndroidManifest.xml` (`<meta-data android:name="com.google.android.geo.API_KEY" …/>`), else the map is a grey grid. iOS: Apple Maps, no key |
| Location | `expo-location` | `expo-location` via `npx install-expo-modules` (Recommended), or `react-native-nitro-geolocation` | `NSLocationWhenInUseUsageDescription` in `Info.plist`; `ACCESS_FINE_LOCATION` in `AndroidManifest.xml`. Avoid `@react-native-community/geolocation` and `react-native-geolocation-service` (unmaintained) |
| Runtime permissions | handled by each `expo-*` module | `react-native-permissions` (unless using Expo modules) | its own Podfile setup — follow its README |
| Bottom sheet | `@gorhom/bottom-sheet` | same | needs `react-native-reanimated` + `react-native-gesture-handler` (CLI: install both, `GestureHandlerRootView` at the root) |
| Carousel / pager | `react-native-reanimated-carousel`; simple cases: `FlatList` + `pagingEnabled` | same | — |
| Charts | `victory-native` (on `@shopify/react-native-skia`) or `react-native-gifted-charts` (on `react-native-svg`) | same | install Skia or SVG; pods + rebuild |
| Video | `expo-video` | `react-native-video`, or `expo-video` via Expo modules | — |
| Camera / QR | `expo-camera` | `react-native-vision-camera` | `NSCameraUsageDescription`; `CAMERA` permission |
| Image picker | `expo-image-picker` | `expo-image-picker` via Expo modules, or `react-native-image-crop-picker` | `NSPhotoLibraryUsageDescription` (+ camera keys if it can shoot) |
| Date/time picker | `@react-native-community/datetimepicker` | same | — |
| Calendar | `react-native-calendars` (pure JS) | same | — |
| Animation | `lottie-react-native` | same | with Re.Pack, check that `.json` animations are bundled as assets |
| Swipeable rows | `react-native-gesture-handler` `Swipeable` | same | — |
| Long lists | `@shopify/flash-list` | same | — |
| Web view | `react-native-webview` | same | — |
| Sign in with Apple | `expo-apple-authentication` (iOS) | `expo-apple-authentication` via Expo modules, or `@invertase/react-native-apple-authentication` | the *Sign in with Apple* capability on the App ID; `usesAppleSignIn: true` in `app.json` (Expo) |
| Google sign-in | `@react-native-google-signin/google-signin` with its config plugin (development build, not Expo Go) | same | iOS: the reversed client id as a URL scheme; Android: the SHA-1 of each signing key registered in Google Cloud. A web client id for the backend's token check |
| Facebook login | `react-native-fbsdk-next` with its config plugin (development build) | same | app id and client token in the native config |

Expo permission strings go in `app.json` through the module's config plugin, e.g.:

```json
{ "expo": { "plugins": [["expo-location", { "locationWhenInUsePermission": "Show nearby coffee shops." }]] } }
```

Write real, specific permission texts — App Store review rejects vague ones.

**Social sign-in** splits in two. This skill builds the buttons, the native setup and a wrapper (`components/social-sign-in.tsx`) that returns the provider's token (an Apple identity token, a Google id token) through a prop like `onToken(provider, token)`; until a backend exists the screen hook signs in the mock session with it. Exchanging that token with the backend and storing the session is rn-api-connect's `references/auth.md`. Two things to raise with the dev before building:
- **App Store rule**: an iOS app whose sign-in uses a third-party service (Google, Facebook…) must also offer an equivalent option that limits data to name and email, lets users hide their email and doesn't track them for ads. Sign in with Apple meets it, so iOS designs with Google or Facebook buttons usually need an Apple button too. Check the current guideline text (App Review Guidelines 4.8) when the design leaves it out, and put it under Open points.
- **Expo Go**: Google and Facebook sign-in need a development build (`devBuild: true`). Apple sign-in opens in Expo Go on iOS, but the token it returns is issued to Expo Go's bundle id, so a backend checking it for your app rejects it: the full flow needs a development build too. When the project runs in Expo Go only, offer a placeholder button for now, or the switch to a development build. Confirm both with `lib-info.sh` (Expo Go flag) before promising either.

**Overlays over every screen** (a toast, a snackbar, an in-app banner): an absolutely positioned view placed after `<Stack>` in the root layout renders *under* native-stack screens on iOS. Wrap it in `FullWindowOverlay` from `react-native-screens` on iOS (a plain `View` on Android), or show it inside the screen that triggers it. Check it on the screen with the highest stack depth.

## 5. Wrap the library in a component

Screens never import the library directly. A wrapper component adapts it to the app's data:

```
src/components/delivery-map.tsx   uses react-native-maps; props: route: LatLng[], courier: LatLng, destination: LatLng
src/types/delivery.ts             LatLng etc. — app types, not the library's
src/services/delivery.ts          returns mock coordinates from src/mocks/delivery.ts (a real route in the design's city)
src/hooks/use-delivery.ts         the screen gets the data here
```

If only one screen uses it, the wrapper can live in that screen's `components/` instead. Switching to Mapbox later is then one file. Keep library-specific props (map style, provider) inside the wrapper. Feed it mock data through a hook like everything else — no coordinates hard-coded in the screen.

If the dev chose the placeholder, keep the same wrapper and props, render the static version inside, and mark it `// TODO: replace with <library>` — swapping later doesn't touch the screen.

## 6. Verify

- The component actually renders: map tiles visible (not a grey grid or blank view), sheet opens and drags, video plays a frame, chart shows data.
- Check **both** platforms when both are run targets: maps use different engines (Apple Maps / Google Maps), sheets and gestures behave differently.
- Permissions on simulators/emulators without tapping:
  - iOS: `xcrun simctl privacy booted grant location <bundle-id>`, fake position `xcrun simctl location booted set 52.37,4.89`.
  - Android: `adb shell pm grant <package> android.permission.ACCESS_FINE_LOCATION`, fake position `adb emu geo fix 4.89 52.37` (longitude first).
  - In Expo Go the bundle/package is Expo Go's (`host.exp.Exponent` / `host.exp.exponent`).
- CLI: verify on a fresh build after `pod install`; a reload after adding a native library proves nothing.

Record each special component in the spec with its library, the native setup done, anything left for the dev (API keys, store permission texts), and the platforms it was verified on.
