# docs/release-plan.md template

Written in Phase 3, approved by the dev, updated at the end. `rn-release` reads it for every release; later runs of this skill update it in place.

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

| Item | For | Where it lives | Status |
|---|---|---|---|
| App Store Connect API key (Key ID ABC123DEF4) | iOS certificates, profiles, submit | EAS | on EAS |
| Distribution certificate + App Store profile | iOS signing | EAS (managed by EAS) | on EAS — profile expires 2027-10-20 |
| Upload keystore (alias upload, SHA-1 AB:CD:…) | Android signing | EAS (generated) — backup in the team vault | on EAS |
| Google service account | eas submit (Play) | EAS | needed — asked the client on <date> |
| APNs key | push (Expo push service) | EAS | provided |

## Store records

- App Store Connect app: <created, Apple ID 1234567890 / needed>
- Google Play app: <created / needed>; first upload by hand: <done on <date> / needed>; release status for submits: draft until the first rollout

## Release features

- Push: APNs key on EAS; FCM V1 key on EAS; device check: <done / not verified>
- Google Sign-In: Android OAuth clients with SHA-1 of the upload key and the Play app signing key; iOS client …

## Verified

- production-simulator: Android ✓ (screenshots), iOS ✓
- production store build: Android ✓ (.aab signed with SHA-1 AB:CD:…), iOS — not run (no credentials yet)

## Open items

- Service account key from the client.
- Play: the first upload by hand, then rn-release for the first internal testing release.
```

Status values for credentials: `needed` → `provided` (in the dev's folder, scanned) → `on EAS`. Never write a secret, a password or a file's contents into this file — only what the item is, its public id or fingerprint, and where it lives.
