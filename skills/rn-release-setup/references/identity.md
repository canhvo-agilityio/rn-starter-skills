# Identity: ids, name, version, encryption flag

Two apps (`variants.md`): the production app's ids below, and the dev app's the same plus `.dev`. Everything here applies to each.

## Bundle id and package

| | Where (Expo) | Where (RN CLI) | Can change later? |
|---|---|---|---|
| iOS bundle identifier | `expo.ios.bundleIdentifier` | `PRODUCT_BUNDLE_IDENTIFIER` in the Xcode project | not once the app record exists on App Store Connect |
| Android package | `expo.android.package` | `applicationId` in `android/app/build.gradle` | never, once uploaded to Google Play |

Propose `com.<company-or-dev-domain-reversed>.<app>` — lowercase, letters and digits, no dashes in the Android package (`com.example.coffeeshop`). Same value on both platforms unless the dev wants otherwise. Ask for the domain if you don't know it; never invent a company name.

Existing app on a store (the dev says so; a `.mobileprovision` or `google-services.json` shows ids; `native` in the inventory has them): use exactly those ids. An app id that differs from the store's is a different app to Apple and Google.

RN CLI: if the native projects already have the ids the dev wants, change nothing. Changing them in `ios/` and `android/` (Xcode target, Gradle namespace, Java/Kotlin package folders) is a separate step the dev approves, and it must be done before the first store upload.

Expo projects with `ios/` and `android/` folders checked in (prebuilt): the native files win over `app.json` at build time. Either change both, or say so to the dev — EAS warns about it.

## Name and version

- Display name: `expo.name` (under the icon). Keep it short (≈12 characters show fully on a home screen).
- `expo.version` (or `versionName` / `MARKETING_VERSION` on RN CLI): the version users see, `1.0.0` for a first release. Store builds raise only the build number (`autoIncrement`); the marketing version is bumped by releases.

## Export compliance (iOS)

Every TestFlight build asks whether the app uses non-exempt encryption; until someone answers in App Store Connect, testers can't install it. Answer once in the app:

```json
"ios": { "infoPlist": { "ITSAppUsesNonExemptEncryption": false } }
```

`false` is right when the app only uses HTTPS and the encryption built into iOS — almost every app. Ask the dev if the app implements its own encryption (end-to-end messaging, a custom crypto library): then `true`, and the export-compliance documents are theirs to handle. RN CLI: the same key in `ios/<App>/Info.plist`.

## Icon and splash

The inventory shows `icon` and `splash`. A store build needs a 1024×1024 icon without transparency for iOS (App Store Connect rejects an alpha channel) and an adaptive icon for Android. If the project still has the template's icon, say so — publishing Expo's logo is a common first-release mistake — and ask the dev for the real one (rn-ui may have exported it into `assets/images/`). Splash: the `expo-splash-screen` plugin config.
