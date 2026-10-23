# Verify against the API

Type checks prove the mappers compile, not that the app shows the backend's data. Look at every affected screen, with the API on, off, and empty.

## 1. Static checks

```bash
npx tsc --noEmit                 # compare with the baseline
npx jest                         # mapper tests, error-message tests
npx eslint src                   # boundary rules, including the api-types rule
bash "<skill-dir>/scripts/check-mocks.sh" <project-dir>
npx expo-doctor                  # Expo
```

## 2. Which server

The plan's base URL. When it's a team server (dev / staging), use it. When the backend runs on the dev's machine or there's none yet, a local server works for checking the app (the team's backend in Docker, or json-server for a demo).

The app reaches a server on the dev's machine differently per target:

| Target | `EXPO_PUBLIC_API_URL` for a server on port 3000 of this machine |
|---|---|
| iOS Simulator | `http://localhost:3000` |
| Android emulator | `http://localhost:3000` after `adb reverse tcp:3000 tcp:3000` (or `http://10.0.2.2:3000` without reverse) |
| Phone (Expo Go) | `http://<this machine's LAN IP>:3000`, same Wi-Fi |

Pass the URL on the command line when you start the dev server, with `.env` loading off — never open or edit the developer's `.env`: `EXPO_NO_DOTENV=1 EXPO_PUBLIC_API_URL=http://localhost:3000 EXPO_PUBLIC_USE_MOCKS=0 npx expo start --port <port>`. Without `EXPO_NO_DOTENV=1`, Expo loads `.env` itself and prints its variable names in Metro's output (`env: export SENTRY_AUTH_TOKEN`), which you would then read. Other `EXPO_PUBLIC_*` values the app needs: names from the template, values from the developer, passed the same way. For both simulators use `localhost` and run `adb reverse` for the API port; `adb reverse` is lost when the emulator restarts — run it again.

Plain `http://` works in Expo Go. In a development or release build Android blocks cleartext HTTP by default: requests fail only on Android with status 0. Use HTTPS, or allow cleartext for development only (`expo-build-properties` → `android.usesCleartextTraffic`) and tell the dev.

## 3. Run the app

Start the dev server the way rn-design-import `verify.md` §2 describes, with these additions learned in real runs:

- **Port**: if 8081 is taken (another project's Metro), start on a free one (`npx expo start --port 8082`) and use that port in every URL; on Android also `adb reverse tcp:8082 tcp:8082`.
- **Env changes need a restart** of the dev server — `EXPO_PUBLIC_*` values are inlined when the bundle is built. Restart with `--clear`, and **after every restart** terminate Expo Go on each device before reopening a link (`xcrun simctl terminate booted host.exp.Exponent`; `adb shell am force-stop host.exp.exponent`) — otherwise it keeps showing the previous bundle and you check the old values.
- **Open links in Expo Go explicitly on Android** — other dev builds on the emulator can claim `exp://` links: `adb shell am start -a android.intent.action.VIEW -d "exp://127.0.0.1:<port>/--/<path>" host.exp.exponent`.
- **Cold start**: the first deep link after Expo Go was terminated opens the initial route (seen on iOS and Android in every run); open the same link a second time. Opening the same route again with different query params keeps the mounted screen and its state — go through another route, or terminate Expo Go first.
- Expo Go's floating gear button covers header-right buttons (the heart on a detail screen). Open the app once as `exp://127.0.0.1:<port>?__expo_disable_fab=1` before the deep links — reported to hide it for the session in a real run; otherwise on Android drag it away (`adb shell input swipe <x> <y> <x> <y+600> 800`).
- On Android, the first launch after Expo Go is installed shows Expo Go's dev-menu sheet over the app; dismiss it with a tap before screenshots.

## 4. Each affected screen, with real data

For every screen in the domains you connected (`usedBy`):

1. Open it by deep link, screenshot, read the screenshot.
2. Prove the data is the API's, not the mock's: find a value only the API has (a name, a price, an item count), or change a record on the server (`curl -X PATCH …` on a local or dev server — never on production data) and pull to refresh / reopen.
3. Images load (remote URLs), prices and dates are formatted as before, nothing shows `undefined`, `NaN` or `[object Object]`.

Paginated lists: scroll to the end once and confirm the next page appends (a footer spinner, more rows), and that the last page stops loading. When the real data fits on one page, lower the page size temporarily (`PAGE_SIZE = 2` in the service), check, and put it back — note it in the hand-off.

## 5. Mutations

Do each mutation in the plan once through the UI (tap the heart, place the order), then:
- the screen updates;
- the other screens showing that data update (favorites tab, order history) — that's the invalidation;
- the server has it (`curl` the GET endpoint).

Android: tap with `adb shell input tap <x> <y>`. iOS without a tap tool: do it on Android, and ask the dev to try one mutation on iOS.

## 6. Error and empty states

- **API unreachable**: restart the dev server with `EXPO_NO_DOTENV=1 EXPO_PUBLIC_API_URL=http://localhost:9` (a closed port) on the command line, reopen one list screen and one detail screen: the error state with "Try again", no endless spinner, no red screen. Then restart with the real URL. Or stop the local server.
- **Not found**: open a detail deep link with an id that doesn't exist (`/coffee/999999`) → the 404 message.
- **Empty**: a filter or category that returns `[]` from the API, or an empty collection on a local server → the empty state.

Screenshot each one.

## 7. Mock mode

Restart the dev server with `EXPO_NO_DOTENV=1 EXPO_PUBLIC_USE_MOCKS=1` on the command line, open the main screens: everything works offline with mock data. Restart without it.

## 8. Other targets, and record

Each other simulator/emulator: open the affected screens once with the API on (catches `adb reverse`, cleartext and URL issues). Phone via Expo Go: ask the dev to open the main screens (their phone uses the LAN IP).

Set each domain's status to `verified` in `docs/api-plan.md` with the targets (`verified (iOS, Android)`). Keep screenshots out of the repo unless the dev wants them.
