# EAS: account, project, profiles, environments, updates

**Contents:** Login and owner · Link the project · eas.json · Environment variables · Updates (OTA) · Builds

Commands below run as `npx --yes eas-cli@<version>` with the version `eas-status.sh` used (`cli` in its output), or the project's own `eas` if it has one. In this file they're written `eas …`.

## Login and owner

The dev logs in themselves: `! npx eas-cli login` (or in their own terminal). Never ask for their Expo password.

The **owner** is the Expo account or organization the project belongs to. Builds, credentials, environment variables and updates live there.
- A client's or company's **organization** is the recommended owner: when people change, nothing is lost and access is managed by the organization.
- A personal account is fine for a personal app or a prototype; the project can be transferred to an organization later on expo.dev.
- The dev must have a role that can create projects and manage credentials in that organization (Admin or Owner; a Developer can build but not always manage credentials). `eas-status.sh` shows the role per account.

## Link the project

```bash
eas init --account <owner> --non-interactive
```

Creates `@<owner>/<slug>` (or links it if it exists) and writes `extra.eas.projectId` and `owner` into `app.json`; it also sets the dashboard icon. With a dynamic `app.config.js/ts` it can't edit the file: it prints the two values — add them to the config by hand.

React Native CLI projects have no `app.json` expo block of their own: `eas init` adds what EAS needs; EAS builds the native projects in `ios/` and `android/` as they are (bare workflow).

**Same slug, existing project.** `eas init` links to `@<owner>/<slug>` if a project with that slug already exists in the account — silently, with `--non-interactive`. Its output says `✔ Created @owner/slug` for a new project; without that line it linked an existing one. Then stop and tell the dev: an unrelated project (an old test, another app with the same slug) would mix credentials. Ask whether it's this app's project; if not, remove `extra.eas.projectId` and `owner`, change `slug` in the app config, and run `eas init` again.

Already linked to another owner (`project.owner` differs from the choice): stop and ask. Relinking moves future builds and credentials to another project; the old project's credentials don't follow.

## eas.json

The profiles for the two apps (`dev`, `production`, their `*-simulator` checks, a submit profile per app) are in `variants.md` → eas.json. What each setting means:

- `cli.version`: the major the skill ran with, as a floor (`>= 25.0.0`), so teammates on an older CLI get a clear error.
- `appVersionSource: "remote"` + `autoIncrement: true`: EAS keeps the build number (iOS `buildNumber`, Android `versionCode`) per app and raises it on every store build — TestFlight and Play reject a number they've seen, and two devs building from different machines would otherwise collide. The first remote value is taken from the project; set it explicitly with `eas build:version:set` when the store already has higher numbers. The marketing `version` (`1.2.0`) stays in `app.json`; releases bump it.
- `env.APP_VARIANT`: which app the profile builds (`variants.md`).
- `*-simulator`: the same configuration (environment, channel, variant) built for the iOS Simulator and as an Android APK, used only for checking before a store build. `autoIncrement: false` so checks don't consume build numbers. Set its `channel` explicitly: `eas update:configure` otherwise writes a channel named after the profile into every profile that has none.
- `submit.<profile>.android.releaseStatus: "draft"`: Google Play refuses non-draft releases for an app that has never been published ("Only releases with status draft may be created on draft app"). Change it to `completed` once that app has had its first rollout.
- `submit.<profile>.ios`: `ascAppId` is that App Store Connect app's Apple ID (a number on the app's App Information page) — the app record must exist (`credentials-ios.md`). The API key for submit is configured on EAS (`credentials-ios.md`), so no key path sits in `eas.json`.

## Environment variables

`EXPO_PUBLIC_*` values (API URL, keys meant to be public) are EAS environment variables, picked by the profile's `environment` (`production`, `preview`, `development` — the three EAS provides; the dev app uses `preview`, the production app `production`):

```bash
eas env:set production --name EXPO_PUBLIC_API_URL --value https://api.example.com/v1 --visibility plaintext --non-interactive
eas env:set preview    --name EXPO_PUBLIC_API_URL --value https://staging-api.example.com/v1 --visibility plaintext --non-interactive
eas env:set production --name EXPO_PUBLIC_USE_MOCKS --value 0 --visibility plaintext --non-interactive
```

- Names come from `.env.example` / `src/lib/env.ts`; values from the developer. Never read `.env`.
- `EXPO_PUBLIC_*` values end up inside the app: `plaintext` or `sensitive` visibility, never real secrets. Build-time secrets (a Sentry auth token) use `--visibility secret` and no `EXPO_PUBLIC_` prefix.
- Check: `eas env:list production`.
- `.env` is gitignored, so EAS doesn't upload it with the project for cloud builds (the upload is the git-tracked project — a few MB); the EAS variables are what the build sees.
- `eas env:create` is deprecated in favour of `eas env:set` (eas-cli 25).

## Updates (OTA)

```bash
npx expo install expo-updates
eas update:configure --non-interactive
```

`update:configure` sets `updates.url` and a `runtimeVersion` policy of `appVersion`. Change it to `fingerprint`:

```json
"runtimeVersion": { "policy": "fingerprint" }
```

With `fingerprint`, the runtime version is a hash of the native side (dependencies, config plugins, native files): an OTA update only reaches builds whose native code it matches, so a JS update that needs a new native module can't break installed apps. `appVersion` would let it through as long as `version` wasn't bumped.

Each build profile's `channel` decides which updates its builds receive; OTA updates are published to those channels with the app's variant (`variants.md` → OTA updates per app).

React Native CLI: `expo-updates` needs `npx install-expo-modules` first and native setup — follow Expo's "Install expo-updates in bare React Native" guide, then build once to check it.

## Builds

```bash
eas build -p android --profile dev --non-interactive                    # cloud, dev app
eas build -p android --profile dev --local --output build/app-dev.aab   # this computer
eas build -p ios --profile dev-simulator --local --output build/sim.tar.gz
```

- Cloud: waits in EAS's queue (free plan: limited builds per month, slower queue).
- Local: needs JDK 17 + Android SDK (source rn-starter's `env.sh` first), and for iOS macOS + Xcode + CocoaPods + fastlane (`brew install fastlane`). It still uses EAS for the project, credentials, environment variables and build numbers — only the compile runs here; a keystore generated during a local build is stored on EAS and reused by cloud builds (seen on eas-cli 25.3). Add `build/` (or wherever outputs go) to `.gitignore`.
- **Disk space for local builds**: a release Android build copies the project to the temp folder and fills `~/.gradle/caches` (several GB the first time); with ~5 GB free it fails with "No space left on device" and leaves the machine without room for anything else. Check `df -h ~` first: under ~15 GB free, recommend the cloud for that build, and never start a local build without telling the dev it needs the space. Clean the leftovers of a failed local build: `rm -rf "${TMPDIR:-/tmp}"/eas-build-local-nodejs`.
- Choosing local or cloud for **your own checks** is the dev's decision too (Phase 1): don't switch to local to save their build quota without asking.
- `--non-interactive` fails instead of prompting when something is missing; read the error, fix the cause, don't remove the flag to "make it work" without knowing what it would have asked.
