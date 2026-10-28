# docs/release-plan.md template

Written in Phase 3, approved by the dev, updated at the end. Every release reads it; later runs of this skill update it in place.

```markdown
# Release plan — <App name>

EAS: @<owner>/<slug> (project <id>) — <organization of the client / personal account>
Builds: <EAS cloud / local on <dev's OS>>
Apps (one codebase, APP_VARIANT): dev "<name> Dev" <id>.dev · production "<name>" <id> · version <x.y.z> (build numbers per app on EAS, auto-increment)
Release managers (production releases need their approval on a release PR): <@user, @user / anyone but the author>

## Profiles

| Profile | App | Distribution | Environment | Update channel | API |
|---|---|---|---|---|---|
| dev | dev | store | preview | dev | https://staging-api.example.com/v1 |
| production | production | store | production | production | https://api.example.com/v1 |
| dev-simulator / production-simulator | each | internal (simulator / APK, checks only) | as above | as above | — |

Runtime version: fingerprint. Testers: the dev app on TestFlight + Google Play internal testing. Production: through `rn-release` and the release gate.

## Credentials

| Round | Item | App | Platform | Where it lives | Status |
|---|---|---|---|---|---|
| Build | Distribution certificate (shared, created from the API key) | both | iOS | EAS | on EAS — expires 2027-10-20 |
| Build | App Store profile | dev | iOS | EAS | on EAS |
| Build | App Store profile | production | iOS | EAS | on EAS |
| Build | Upload keystore (generated, SHA-1 87:1E:…:AF:B3) | dev | Android | EAS — backup in the team vault | on EAS |
| Build | Upload keystore (generated, SHA-1 4C:02:…:9D:11) | production | Android | EAS — backup in the team vault | on EAS |
| Submit | App Store Connect API key (Key ID ABC123DEF4, App Manager) | both | iOS | EAS | on EAS |
| Submit | Google service account key | both | Android | EAS | needed — asked the client on <date> |
| Push | APNs key (Key ID XYZ987) | both | iOS | EAS | provided |
| Push | FCM V1 key + google-services.json (both packages) | both | Android | EAS / repo | needed |

Push sent by: <Expo push service / the backend (keys handed to <team>) / Firebase / —>

## Outside EAS

| Item | Owner | Status |
|---|---|---|
| App Store Connect app records: "<name> Dev" (Apple ID 1234567890) and "<name>" (Apple ID 1234567891), in eas.json | client | done |
| Play Console apps (dev, production) + first .aab of each uploaded by hand to internal testing | dev | needed |
| Service account invited on both Play apps (Release to testing tracks) | client | needed |

## Checked

- Credentials page reviewed with the dev on <date>: iOS <complete / missing …>, Android <complete / missing …>
- Test build and submit: <Android ✓ build 4, .aab signed with SHA-1 87:1E:…, submitted as draft / not run — "set up, not proven by a build">
- Other features found (set up outside this skill): <Google Sign-In, Maps — need the fingerprints above>

## Open items

- Service account key from the client.
- Play: the first upload by hand, then the first internal testing release.
```

Status values for credentials: `needed` → `provided` (in the dev's folder, scanned) → `on EAS` (the dev confirmed it on the Credentials page). Never write a secret, a password or a file's contents into this file — only what the item is, its public id or fingerprint, and where it lives.
