# iOS credentials

Needed for a store build: a **distribution certificate** and an **App Store provisioning profile** for the bundle id, in the client's Apple Developer team. Needed for TestFlight: an **app record** on App Store Connect and a way for EAS to submit (API key or Apple ID). EAS stores the certificate and profile per project and bundle id.

> Not run on this machine (no Apple Developer account here): this file follows Expo's documentation. Mark iOS steps "not run" in the hand-off until a run with real credentials confirms them.

## With an App Store Connect API key (recommended)

The dev has `AuthKey_<KEYID>.p8`, the Key ID, the Issuer ID and the Team ID; the key's role is Admin or App Manager.

1. **Register the key on EAS** so cloud builds and submits can use it — the dev runs, in their own terminal:
   ```
   npx eas-cli credentials -p ios
   ```
   → choose the `production` build profile → *App Store Connect: Manage your API Key* → *Set up an App Store Connect API Key* → *use an existing key* → give the `.p8` path, Key ID, Issuer ID. Give the dev the exact path and ids to type; they're not secret.
2. **Create the certificate and profile** with the first build. Interactive builds ask how to log in to Apple; pass the key instead of an Apple ID:
   ```bash
   EXPO_ASC_API_KEY_PATH=<path>/AuthKey_<KEYID>.p8 EXPO_ASC_KEY_ID=<KEYID> EXPO_ASC_ISSUER_ID=<issuer> \
   EXPO_APPLE_TEAM_ID=<TEAMID> EXPO_APPLE_TEAM_TYPE=COMPANY_OR_ORGANIZATION \
   eas build -p ios --profile production
   ```
   `EXPO_APPLE_TEAM_TYPE` is `INDIVIDUAL` for a personal developer account. EAS registers the bundle id, creates (or reuses) a distribution certificate and an App Store profile, and stores them. If the team already has the maximum number of distribution certificates, EAS asks to reuse or revoke one: **never revoke without the client's yes** — another app or CI may be signing with it; ask for that certificate's `.p12` instead.
3. **App record**: App Store Connect's API can't create apps. Someone with access creates it once: *App Store Connect → Apps → + → New App*, platform iOS, the bundle id from step 2, a name, the primary language and an SKU. Then copy its **Apple ID** (App Information page) into `submit.production.ios.ascAppId` in `eas.json`, with `appleTeamId`.

## With a certificate and a profile

The dev has a distribution `.p12` (and knows its password) and an **App Store** `.mobileprovision` for the bundle id (the scan shows `type: app-store`, the bundle id and the expiry).

1. Write `credentials.json` in the project root (gitignored) with paths only:
   ```json
   {
     "ios": {
       "provisioningProfilePath": "<folder>/<profile>.mobileprovision",
       "distributionCertificate": { "path": "<folder>/<cert>.p12", "password": "TYPE-IT-HERE" }
     }
   }
   ```
2. The dev replaces `TYPE-IT-HERE` with the password themselves, then runs `npx eas-cli credentials -p ios` → *credentials.json: Upload/Download credentials between EAS servers and your local json* → *Upload credentials from credentials.json to EAS*.
3. The dev deletes `credentials.json` afterwards (or you `rm` it — without reading it).
4. Submitting still needs the API key (above, step 1 only) or an Apple ID login. Profiles expire after a year and aren't renewed by EAS in this mode: note the expiry date in the plan.

## With an Apple ID only

The dev is a member of the client's team (Admin or App Manager) but has no key. They run the first `eas build -p ios --profile production` in their own terminal and log in when asked (Apple ID, password, 2-factor code) — EAS creates the certificate and profile. Recommend asking the client for an API key anyway: every new machine and CI needs this login again.

## Push (APNs)

When the app uses push (`release-features.md`): the APNs key `.p8` + its Key ID, added in `eas credentials -p ios` → *Push Notifications: Manage your Apple Push Notifications Key* (dev runs it). If a backend sends the pushes itself, the key goes to the backend team instead — tell the dev; don't send it anywhere yourself. A team can have at most two APNs keys: reuse the existing one rather than creating a third.

## Checking

- `npx eas-cli credentials -p ios` (dev, or you with `--non-interactive` where it prints): certificate serial and expiry, profile id and expiry, push key, API key.
- The store build finishes its signing step; the `.ipa` is produced.
