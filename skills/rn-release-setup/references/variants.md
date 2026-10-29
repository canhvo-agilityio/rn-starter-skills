# Two apps: dev and production

**Contents:** Why two apps · app.config.js · eas.json · Environments and API URLs · Credentials per app · OTA updates per app · The release block in .rn-starter.json · Outside EAS

## Why two apps

Every app this skill sets up ships as **two store apps from one codebase and one EAS project**: a dev app (`com.acme.coffeeshop.dev`, "Coffee Dev") that testers get often, and the production app (`com.acme.coffeeshop`, "Coffee") that users get through a release. Both install side by side on one phone, and push, deep links and analytics never mix.

The two apps differ only by **`APP_VARIANT`** (`dev` or `production`), which the app config reads. The build profile sets it for builds; OTA commands pass it on the command line. Unset means **dev**, so a stray build or `expo start` never targets production.

What's shared and what's per app:

| | Shared | Per app |
|---|---|---|
| iOS | distribution certificate (one per Apple team), APNs key, App Store Connect API key | bundle id, provisioning profile, App Store Connect app record |
| Android | Google service account key (invited to both apps) | package, upload keystore, Play Console app |
| EAS | project, owner, environment variables per environment | build profile, update channel |
| Firebase (push) | one project, `google-services.json` listing both packages | an Android app per package |

## app.config.js

Static values (`version`, plugins, icons, splash) stay in `app.json`; the variant overrides only what differs. The marketing `version` lives in `app.json` and is the same for both apps.

```js
// app.config.js — one codebase, two store apps. APP_VARIANT comes from the build profile
// (eas.json) or the command line; unset means the dev app, so nothing targets production by accident.
const VARIANT = process.env.APP_VARIANT === 'production' ? 'production' : 'dev';

const APPS = {
  dev: { name: 'Coffee Dev', id: 'com.acme.coffeeshop.dev', scheme: 'coffeeshop-dev' },
  production: { name: 'Coffee', id: 'com.acme.coffeeshop', scheme: 'coffeeshop' },
};
const app = APPS[VARIANT];

module.exports = ({ config }) => ({
  ...config,
  name: app.name,
  scheme: app.scheme,
  ios: { ...config.ios, bundleIdentifier: app.id },
  android: { ...config.android, package: app.id },
  extra: { ...config.extra, appVariant: VARIANT },
});
```

- Remove `name`, `scheme`, `ios.bundleIdentifier` and `android.package` from `app.json` so there's one place for each.
- A distinct dev icon (a "DEV" badge) avoids testers opening the wrong app: `icon` per variant when the dev provides one (`./assets/images/icon-dev.png`); otherwise both use the same icon, and say so.
- Check both: `APP_VARIANT=dev npx expo config --type public` and `APP_VARIANT=production …` (with `EXPO_NO_DOTENV=1`) show the right name and ids.
- `eas init` can't edit a dynamic config: put the `extra.eas.projectId` and `owner` it prints into `app.json`.
- rn-e2e: flows on a build use the **dev** app's id (`APP_ID=com.acme.coffeeshop.dev`) and scheme.
- React Native CLI: the same split is done with product flavors (Android) and a second target or configuration (iOS). That's a larger native change the dev approves first; this file covers Expo.

## eas.json

```json
{
  "cli": { "version": ">= 25.0.0", "appVersionSource": "remote" },
  "build": {
    "dev": {
      "distribution": "store", "environment": "preview", "channel": "dev",
      "autoIncrement": true, "env": { "APP_VARIANT": "dev" }
    },
    "production": {
      "distribution": "store", "environment": "production", "channel": "production",
      "autoIncrement": true, "env": { "APP_VARIANT": "production" }
    },
    "dev-simulator": {
      "extends": "dev", "distribution": "internal", "channel": "dev", "autoIncrement": false,
      "ios": { "simulator": true }, "android": { "buildType": "apk" }
    },
    "production-simulator": {
      "extends": "production", "distribution": "internal", "channel": "production", "autoIncrement": false,
      "ios": { "simulator": true }, "android": { "buildType": "apk" }
    }
  },
  "submit": {
    "dev": {
      "ios": { "ascAppId": "<dev app's Apple ID>", "appleTeamId": "<TEAMID>" },
      "android": { "track": "internal", "releaseStatus": "draft" }
    },
    "production": {
      "ios": { "ascAppId": "<production app's Apple ID>", "appleTeamId": "<TEAMID>" },
      "android": { "track": "internal", "releaseStatus": "draft" }
    }
  }
}
```

- The dev app is a **store** build too: testers install it from TestFlight and Play internal testing, with no device registration (iOS ad hoc builds need every tester's UDID).
- `*-simulator` profiles are checks only (iOS Simulator, Android APK): they reach no user and use no build number.
- Build numbers are per app on EAS (`appVersionSource: "remote"`), so the two apps count separately.
- The rest of `eas.md` → eas.json (draft release status, `ascAppId`) applies to each app.

## Environments and API URLs

The dev app uses EAS's `preview` environment, the production app `production`. Set the variables per environment as in `eas.md` → Environment variables: the dev app talks to the dev / staging API, the production app to the production API. When the backend has only one API, both environments get the same URL; the apps are still separate.

## Credentials per app

Run each round of Phases 5–7 **for both apps**: credentials live per bundle id / package on EAS, and `eas-credentials.sh` picks the app from the profile (`dev` or `production`).

- **Build.** iOS: one distribution certificate for the team, reused for the second app (EAS offers to reuse it), and a provisioning profile per bundle id. Android: a keystore per app; for a new app EAS generates both.
- **Submit.** The same App Store Connect API key and the same Google service account key for both apps; the service account must be invited to both Play Console apps.
- **Push** (if used). The same APNs key uploaded for both bundle ids. One Firebase project with an Android app per package; its `google-services.json` lists both, so one file serves both builds.

Scan once per app: `scan-credentials.sh <folder> <project> --bundle-id <dev id> --package <dev id>`, then with the production ids. A `.mobileprovision` belongs to exactly one of them.

## OTA updates per app

```bash
APP_VARIANT=dev        eas update --channel dev        --environment preview    --message "…"
APP_VARIANT=production eas update --channel production --environment production --message "…"
```

`APP_VARIANT` matters for updates too: the runtime version (`fingerprint`) is computed from the app config, and the two apps' configs differ. Without it, the update is computed for the dev app. Production updates go through `rn-release`; the project's release gate blocks them otherwise.

## The release block in .rn-starter.json

Written in Phase 4 so the release gate (`.claude/hooks/release-gate.mjs`) knows which profile and channel reach which app without guessing:

```json
"release": {
  "apps": [
    { "name": "dev", "variant": "dev", "production": false,
      "ios": "com.acme.coffeeshop.dev", "android": "com.acme.coffeeshop.dev",
      "profiles": ["dev", "dev-simulator"], "channels": ["dev"], "environment": "preview" },
    { "name": "production", "variant": "production", "production": true,
      "ios": "com.acme.coffeeshop", "android": "com.acme.coffeeshop",
      "profiles": ["production", "production-simulator"], "channels": ["production"], "environment": "production" }
  ],
  "releaseBranchPrefix": "release/",
  "productionBranch": "prod",
  "remote": "origin"
}
```

`productionBranch`: the branch whose commits may reach the production app. A release manager merges a `release/<version>` pull request (GitHub) or merge request (GitLab) into it, and **that merge is the approval**: the gate only checks, with git, that the commit being shipped is on this branch of `remote`. Use the team's production branch when it has one (`prod`, `production`); otherwise create `prod` from the last released commit (or from `main` for a first release). Don't use the branch everyday work merges into: every feature merge would then be shippable.

## Protect the production branch

The gate trusts the branch, so the server must make sure only release managers can put commits on it. The dev (or a repository admin) sets this up once in the web UI; it can't be done from here:

- **GitHub** → *Settings → Branches* (or *Rules → Rulesets*) → a rule for the production branch: *Require a pull request before merging* with at least one approval, *Restrict who can push to matching branches* to the release managers (or a team), no force pushes, no deletion.
- **GitLab** → *Settings → Repository → Protected branches* → the production branch: *Allowed to merge*: the release managers (Maintainers or named users), *Allowed to push and merge*: No one, *Allowed to force push*: off. On GitLab Premium, also *Settings → Merge requests → Approval rules* with the release managers as required approvers.

Also add the production branch to `protectedBranches` in `.rn-starter.json`, so the project's guard and git hook refuse direct pushes to it too.

## Outside EAS

Twice the records, once each:

- App Store Connect: an app record per bundle id. App names are unique across the App Store, so the dev app needs its own ("Coffee Dev"); it never leaves TestFlight.
- Play Console: an app per package. The dev app lives in internal testing only; each app needs its first `.aab` uploaded by hand.
- The service account invited with *Release to testing tracks* on both Play apps.
