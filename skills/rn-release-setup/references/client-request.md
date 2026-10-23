# Getting what's missing

For each missing item: where it comes from (so a dev with access can make it), and a message the dev can send when the client owns the account. Menus are as of late 2026 — names move; if a step doesn't match, tell the dev what you were looking for rather than guessing.

## How each item is made

**App Store Connect API key** (`.p8`, Key ID, Issuer ID) — needs the Account Holder or an Admin:
App Store Connect → *Users and Access* → *Integrations* → *App Store Connect API* → *Team Keys* → *Generate API Key* → name it (e.g. "EAS"), access *App Manager* (or Admin) → *Generate*. Download the `.p8` (**only once** — Apple doesn't keep a copy). The Key ID is in the list; the Issuer ID is above the list.

**Team ID**: developer.apple.com → *Account* → *Membership details*; also in the top-right team menu of App Store Connect.

**APNs key** (`.p8` for push): developer.apple.com → *Certificates, Identifiers & Profiles* → *Keys* → *+* → enable *Apple Push Notifications service (APNs)* → *Continue* → *Register* → download (once) and note the Key ID. Max two per team: reuse an existing one if the client has it.

**Distribution certificate `.p12` + App Store profile** (only if the client prefers this to an API key): Keychain Access exports the certificate with its private key as `.p12` with a password; the App Store provisioning profile for the bundle id downloads from *Profiles*.

**App record on App Store Connect**: *Apps* → *+* → *New App* → iOS, name, primary language, the bundle id, SKU.

**Google Play app**: Play Console → *Create app* → name, default language, app or game, free or paid, declarations.

**Upload keystore** (app already on Play): whoever built the previous releases has it (`.jks`/`.keystore`, alias, two passwords). Lost: Play Console → the app → *App integrity* → *App signing* → *Request upload key reset* (needs a new keystore's certificate; takes days).

**Google service account key** (`.json`) — needs a Play Console admin and a Google Cloud project:
1. Google Cloud Console → *IAM & Admin* → *Service Accounts* → *Create service account* → *Keys* → *Add key* → *JSON* → download.
2. Enable the *Google Play Android Developer API* for that Cloud project.
3. Play Console → *Users and permissions* → *Invite new users* → the service account's email → app permissions: this app → *Release to testing tracks* (and *Release to production* if the team wants production submits from EAS).

**Firebase files** (`google-services.json`, `GoogleService-Info.plist`): Firebase console → the project → *Project settings* → *Your apps* → the Android app (package) / iOS app (bundle id) → download. If the app isn't registered there yet, *Add app* with the exact package / bundle id.

## Message template

Draft it in the language the dev uses with the client; list only what's missing; include the app's ids so the client can't send the wrong files.

```
Hi <name>,

To set up release builds of <App name> for TestFlight and Google Play internal testing, we need:

iOS (team <Team name or ID>, bundle id <com.x.app>)
- An App Store Connect API key with App Manager access: the .p8 file, its Key ID and the Issuer ID
  (App Store Connect → Users and Access → Integrations → App Store Connect API → Team Keys).
- [if push] The APNs key (.p8) and its Key ID, or the existing one if you already have it.
- [if no app record] An app record for <com.x.app> in App Store Connect (Apps → + → New App).

Android (package <com.x.app>)
- [if already on Play] The upload keystore used for previous releases (.jks/.keystore) and its alias.
  Please send the passwords separately (e.g. through a password manager), not in this thread.
- A Google service account key (.json) invited in Play Console with "Release to testing tracks"
  for this app.
- [if Firebase] google-services.json / GoogleService-Info.plist for these ids.

Please share the files through <the team's secure channel> rather than email.

Thanks!
```

Then stop and tell the dev: put the files in the same folder when they arrive, and run the skill again — the scan picks up from there.
