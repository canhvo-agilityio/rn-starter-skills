# docs/release-plan.md template

Written in Phase 3, approved by the dev, updated at the end. Every release reads it; later runs of this skill update it in place.

```markdown
# Release plan — <App name>

EAS: @<owner>/<slug> (project <id>) — <organization of the client / personal account>
Builds: <EAS cloud / local on <dev's OS>>
Identity: iOS <bundle id> · Android <package> · name "<name>" · version <x.y.z> (build numbers on EAS, auto-increment)

## Profiles

| Profile | Distribution | Environment | Update channel | API |
|---|---|---|---|---|
| production | store | production | production | https://api.example.com/v1 |
| staging | store | preview | staging | https://staging-api.example.com/v1 |
| production-simulator | internal (simulator / APK, checks only) | production | production | — |

Runtime version: fingerprint. Testers: TestFlight internal + Google Play internal testing.

## Credentials

| Round | Item | Platform | Where it lives | Status |
|---|---|---|---|---|
| Build | Distribution certificate + App Store profile (created from the API key) | iOS | EAS | on EAS — profile expires 2027-10-20 |
| Build | Upload keystore (generated, SHA-1 87:1E:…:AF:B3) | Android | EAS — backup in the team vault | on EAS |
| Submit | App Store Connect API key (Key ID ABC123DEF4, App Manager) | iOS | EAS | on EAS |
| Submit | Google service account key | Android | EAS | needed — asked the client on <date> |
| Push | APNs key (Key ID XYZ987) | iOS | EAS | provided |
| Push | FCM V1 key + google-services.json | Android | EAS / repo | needed |

Push sent by: <Expo push service / the backend (keys handed to <team>) / Firebase / —>

## Outside EAS

| Item | Owner | Status |
|---|---|---|
| App Store Connect app record (Apple ID 1234567890 in eas.json) | client | done |
| Play Console app + first .aab uploaded by hand to internal testing | dev | needed |
| Service account invited in Play Console (Release to testing tracks) | client | needed |

## Checked

- Credentials page reviewed with the dev on <date>: iOS <complete / missing …>, Android <complete / missing …>
- Test build and submit: <Android ✓ build 4, .aab signed with SHA-1 87:1E:…, submitted as draft / not run — "set up, not proven by a build">
- Other features found (set up outside this skill): <Google Sign-In, Maps — need the fingerprints above>

## Open items

- Service account key from the client.
- Play: the first upload by hand, then the first internal testing release.
```

Status values for credentials: `needed` → `provided` (in the dev's folder, scanned) → `on EAS` (the dev confirmed it on the Credentials page). Never write a secret, a password or a file's contents into this file — only what the item is, its public id or fingerprint, and where it lives.
