# Check and hand off

## 1. The Credentials page

EAS's CLI can't print the credential state without a terminal (`eas credentials` stops at "Input is required, but stdin is not readable"), so the dev checks: expo.dev → the project → **Credentials** (or `npx eas-cli credentials -p ios|android` in their terminal, which prints the state before its menu). Go through the plan's checklist together and ask them to read back or screenshot each section:

| Section | Expected |
|---|---|
| iOS — each bundle id (`<id>.dev`, `<id>`) | Distribution certificate (expiry > 30 days) · Provisioning profile, App Store, same bundle id · App Store Connect API key (key id) · Push key (if push) |
| Android — each package (`<id>.dev`, `<id>`) | Upload keystore (SHA-1 = Play Console's upload key for an app already on Play) · Google service account key for EAS Submit · FCM V1 service account key (if push) |

Mark each item `on EAS` in the plan, or what's still missing and who provides it. A platform with missing items is **not set up** — say what's missing, never imply it's done.

`eas env:list production` (and `preview`) — you can run it — for the environment variables.

## 2. Outside EAS

Not on the Credentials page, but each one blocks the first submit. List them with an owner:

- App Store Connect **app record** for each bundle id; their Apple IDs in `eas.json` → `submit.dev.ios.ascAppId` and `submit.production.ios.ascAppId`.
- The App Store Connect API key's **role** (App Manager or Admin).
- Google Play Console **app** created; **first `.aab` uploaded by hand** to internal testing.
- The service account **invited in Play Console** with *Release to testing tracks* for this app.
- Push sent by a backend or another provider: the keys handed to them.

## 3. Optional test build and submit

Ask the dev (Phase 8): a test proves what the Credentials page can't — that the keystore is the published app's, the service account has its permissions, the profile matches. It uses their build quota (cloud) or ~15 GB of disk (local — check `df -h ~` first, `eas.md` → Builds).

If yes, where they chose to build, with the **dev app** (it proves the shared credentials and needs no release approval; the production app's own profile and keystore are proven by its first release through `rn-release`):

```bash
eas build -p android --profile dev --non-interactive --auto-submit
eas build -p ios --profile dev --non-interactive --auto-submit
```

- Android, app never uploaded: the submit fails until the first manual upload — download the `.aab` from the build page, the dev uploads it in Play Console, then `eas submit -p android --profile dev --latest` (always name the profile: without it EAS uses `production`, which the release gate blocks).
- The build page shows the signing step; for Android, `keytool -printcert -jarfile app.aab` prints the signer's SHA-1/SHA-256 (public) to compare with the plan.
- Failed attempts consume build numbers too (`autoIncrement`); stores only need them to grow.
- Network errors while Gradle downloads dependencies (`bad_record_mac`, Maven timeouts) are transient: retry before suspecting the configuration.

If no: the hand-off says "credentials set up, not proven by a build" — the first release is the proof.

## 4. Hand-off

Update `docs/release-plan.md` (statuses, fingerprints, profile expiry, outside-EAS list with owners, test build result or "not run"), then tell the dev in a few lines: what's on EAS per platform, what's left and who does it, and that the next step is the first TestFlight / internal testing release.
