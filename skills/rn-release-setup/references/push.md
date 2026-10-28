# Push credentials

Only when the inventory reports `features.push` (`expo-notifications`, `@react-native-firebase/messaging`, OneSignal). A push key on EAS is half of it: the app also has to be configured to receive pushes, or the keys sit there unused. Both are this round's job.

## Who sends the pushes

Ask once — it decides where the keys go:
- *Expo's push service* (the app sends Expo push tokens to its backend, the backend calls Expo) — **keys on EAS** (Recommended when the app uses `expo-notifications` and nothing says otherwise).
- *The backend sends directly through APNs / FCM* — keys go to the backend team, not EAS. Tell the dev who needs them; never send a key anywhere yourself.
- *Firebase Cloud Messaging for both platforms* (`@react-native-firebase/messaging`) — the APNs key is uploaded to the Firebase project; FCM handles Android.
- *OneSignal or another provider* — keys go to that provider's dashboard.

The rest of this file is the Expo push service path; for the others, list the keys and where they go in the hand-off.

## iOS: APNs key

- File: an APNs key `.p8` + its Key ID (+ the Team ID). Not the App Store Connect API key, even though both are `AuthKey_<KEYID>.p8` — ask which key id is which.
- For each app, the dev runs `npx eas-cli credentials -p ios` → `dev`, then `production` → *Push Notifications: Manage your Apple Push Notifications Key* → use an existing key → path + Key ID. With an App Store Connect API key or Apple ID login, EAS can also create one — but a team has **at most two** APNs keys: reuse the client's existing one when they have it.
- App side: `expo-notifications` adds the `aps-environment` entitlement; EAS turns on the Push capability for the bundle id when it creates the provisioning profile. If the profile was uploaded from a file (`credentials-ios.md` → certificate and profile), it must include push — the scan shows `push: true/false` for a `.mobileprovision`.

## Android: FCM V1 key and google-services.json

- **`google-services.json`** from the Firebase project, with a client for each app's package — register both packages in one Firebase project and the one file serves both builds (the scan lists its packages). In the app config: `"android": { "googleServicesFile": "./google-services.json" }`. It's configuration, not a secret: commit it, or keep it out of git and pass it as a `file` EAS environment variable.
- **FCM V1 service account key** (`.json`) from the same Firebase project: Firebase console → *Project settings → Service accounts → Generate new private key*. Usually not the same service account as the Play submit one — ask which file is which.
- The dev uploads it: `npx eas-cli credentials -p android` → `production` → *Push Notifications (FCM V1)* → upload the key; or *Add a service account key* under *FCM V1 service account key* on the Credentials page.

## Checking

- Credentials page: iOS push key under the bundle id; Android FCM V1 key under the package.
- App config: `googleServicesFile` points at a file for the right package; `expo-notifications` is in the plugins (Expo).
- A push only proves itself on a real device with a build that has these credentials — part of the optional test build (`verify.md`): get the Expo push token on the device, send one with `curl -H 'Content-Type: application/json' -d '{"to":"<token>","title":"Test"}' https://exp.host/--/api/v2/push/send`, and the dev confirms it arrived. Otherwise the hand-off says "push: keys set up, not tested on a device".
