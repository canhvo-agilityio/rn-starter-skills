# iOS credentials

> Not run on this machine (no Apple Developer account here): this file follows Expo's documentation. Mark iOS items "set up, not run" in the hand-off until a run with real credentials confirms them.

EAS stores iOS credentials per project and bundle id. The Credentials page shows them under the bundle id: **Distribution certificate**, **Provisioning profile** (build), **App Store Connect API key** (submit), **Push key** (push).

Menu labels below are as of eas-cli 25 and may be worded differently in other versions — pick the matching entry. Commands the dev runs in their own terminal (interactive menus; they may ask for an Apple login or a password). Give them the exact command, which profile to pick (`production`), and what to choose.

## Build: distribution certificate + App Store provisioning profile

**Use what the dev provided.** A distribution `.p12` + an App Store `.mobileprovision` in the folder → upload them (*From a certificate and a profile*, below), even when an API key is there too; the key is then for submit only. Don't run `credentials:configure-build` with the key in that case: EAS could create a new certificate and profile in the client's team instead of using the ones they gave. Only when no certificate + profile was provided does EAS create them from the key or an Apple ID.

### From an App Store Connect API key (no certificate + profile provided)

The dev has `AuthKey_<KEYID>.p8`, its Key ID, the Issuer ID and the Team ID; the key's role is Admin or App Manager.

```bash
EXPO_ASC_API_KEY_PATH=<folder>/AuthKey_<KEYID>.p8 EXPO_ASC_KEY_ID=<KEYID> EXPO_ASC_ISSUER_ID=<issuer> \
EXPO_APPLE_TEAM_ID=<TEAMID> EXPO_APPLE_TEAM_TYPE=COMPANY_OR_ORGANIZATION \
npx eas-cli credentials:configure-build -p ios -e production
```

The variables let EAS talk to Apple with the key instead of an Apple ID login (`EXPO_APPLE_TEAM_TYPE=INDIVIDUAL` for a personal developer account). EAS registers the bundle id, creates or reuses a distribution certificate, and creates an App Store provisioning profile — no build needed. If the team already has the maximum number of distribution certificates, EAS asks to reuse or revoke one: **never revoke without the client's yes** (another app or a CI may sign with it); ask for that certificate's `.p12` instead.

Repeat with `-e staging` when there's a staging profile with the same bundle id: it reuses the same certificate and profile.

### From a certificate and a profile (provided by the dev)

The dev has a distribution `.p12` (and its password) and an **App Store** `.mobileprovision` for the bundle id — the scan shows `type: app-store`, the bundle id and the expiry.

1. Write `credentials.json` in the project root (gitignored) with paths only:
   ```json
   {
     "ios": {
       "provisioningProfilePath": "<folder>/<profile>.mobileprovision",
       "distributionCertificate": { "path": "<folder>/<cert>.p12", "password": "TYPE-IT-HERE" }
     }
   }
   ```
2. The dev replaces `TYPE-IT-HERE`, then runs `npx eas-cli credentials -p ios` → `production` → *credentials.json: Upload/Download credentials between EAS servers and your local json* → *Upload credentials from credentials.json to EAS*.
3. The dev deletes `credentials.json` (or you `rm` it — without reading it).

EAS doesn't renew an uploaded profile: write its expiry date in the plan.

### From an Apple ID only

The dev belongs to the client's team (Admin or App Manager) but has no key: `npx eas-cli credentials:configure-build -p ios -e production`, log in when asked (Apple ID, password, 2-factor code). Works; recommend asking for an API key anyway — each new machine and CI needs the login again, and submit is simpler with the key.

## Submit: App Store Connect API key on EAS

The same `.p8` as above (or a separate key with App Manager access). The dev runs:

```
npx eas-cli credentials -p ios
```

→ `production` → *App Store Connect: Manage your API Key* → *Set up an App Store Connect API Key* → use an existing key → the `.p8` path, Key ID, Issuer ID (give them these; they aren't secret). It's then used by `eas submit` from any machine, so `eas.json` needs no key path.

Also needed for the first submit, outside EAS: the **app record** on App Store Connect (*Apps → + → New App*, with the bundle id) — App Store Connect's API can't create apps. Its **Apple ID** (a number on the App Information page) goes into `eas.json` → `submit.production.ios.ascAppId`, with `appleTeamId`.

## Push: APNs key

See `push.md`.

## Checking

On the Credentials page, under the bundle id: a distribution certificate (serial, expiry), a provisioning profile (App Store, expiry, matching the certificate), the App Store Connect API key (key id), and the push key if the app uses push. Or the dev runs `npx eas-cli credentials -p ios` and reads the summary it prints before the menu.
