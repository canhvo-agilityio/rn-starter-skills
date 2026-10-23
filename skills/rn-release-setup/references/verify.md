# Verify the setup

Three proofs, in this order. Each platform is "set up" only when its store-signed build succeeded.

## 1. The production configuration, on a simulator / emulator

Build the `production-simulator` profile — same environment variables, channel and app config as `production`, but runnable here:

Where the dev chose to build (Phase 1):

```bash
# EAS cloud: build, then download and install the result on the running emulator / simulator
eas build -p android --profile production-simulator --non-interactive && eas build:run -p android --latest
eas build -p ios --profile production-simulator --non-interactive && eas build:run -p ios --latest

# this computer (check `df -h ~` first — eas.md → Builds)
source <rn-starter-skill-dir>/scripts/env.sh
eas build -p android --profile production-simulator --local --output build/check.apk
eas build -p ios --profile production-simulator --local --output build/check.tar.gz   # macOS + Xcode + fastlane
```

Install and open:

```bash
adb install -r build/check.apk && adb shell monkey -p <package> -c android.intent.category.LAUNCHER 1
tar -xzf build/check.tar.gz -C build/ && xcrun simctl install booted build/*.app && xcrun simctl launch booted <bundle id>
```

Screenshot and look:
- **Home screen**: the app's name and icon (not Expo's template icon). `adb exec-out screencap -p > shot.png`, `xcrun simctl io booted screenshot shot.png`.
- **The first screens**: data from the environment's API — a value only that API has — not mocks, no red error screen, no dev menu (it's a release build).
- **Version**: Android `adb shell dumpsys package <package> | grep -E "versionName|versionCode"`; iOS `plutil -p build/*.app/Info.plist | grep -E "CFBundleShortVersionString|CFBundleVersion|ITSAppUsesNonExemptEncryption"`.
- **Permission strings** (iOS) from the same `plutil` output, when the app uses any (`release-features.md`).

A release build has no Metro: if it opens to a blank or red screen, read the device log (`adb logcat -d | grep -iE "ReactNativeJS|FATAL"`, `xcrun simctl spawn booted log show --last 2m --predicate 'process == "<App>"'`).

## 2. Store-signed builds

```bash
eas build -p android --profile production --non-interactive      # cloud; add --local --output build/app.aab for this computer
eas build -p ios --profile production --non-interactive          # needs the iOS credentials
```

Cloud builds: download the artifact from the build page (or the URL in `eas build:view <id> --json`) into `build/` to inspect it.

- Android: `keytool -printcert -jarfile build/app.aab` prints the signer's SHA-1/SHA-256 — it must match the upload key on EAS (`eas credentials -p android`), and for an app already on Play, the upload key Play Console shows. No password involved: these are public.
- iOS: the build passes its signing step and writes the `.ipa`.
- These consume build numbers (`autoIncrement`) — failed attempts too (a run whose first three tries failed produced versionCode 4). That's expected; Play and TestFlight only need numbers to grow.
- Network errors while Gradle downloads dependencies (`bad_record_mac`, timeouts from Maven) are transient: run the build again before looking for a configuration problem.

A platform whose credentials aren't there yet is reported as **not set up**, with what's missing — never as done.

## 3. What EAS holds

`eas credentials -p android` and `-p ios` (interactive menus print the current state first; when it needs a TTY, ask the dev to run it and tell you what it shows): keystore, service account key, FCM key; certificate, profile (expiry), API key, push key. `eas env:list production` (and `preview`) for the variables.

Record all three in `docs/release-plan.md`.
