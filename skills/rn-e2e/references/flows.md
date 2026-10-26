# Writing Maestro flows

**Contents:** What a flow covers · testIDs · Layout · Writing flows · Targets and environment · Data and sign-in · Troubleshooting

Checked with Maestro 2.7 on an Expo SDK 58 app in Expo Go on the iOS 26.5 Simulator: deep links through `exp://127.0.0.1:8081/--/<route>` after `stopApp`, `testID` → `id:` selectors, `config.yaml` with `excludeTags`, JUnit output and `--test-output-dir` (about 6 s per flow once the bundle is cached). The Android notes follow the same mechanics and haven't been run here yet.

## What a flow covers

One requirement, from the screen where it starts to the assertion that proves it:

| Requirement | Starts at | Does | Asserts |
|---|---|---|---|
| R1 orders newest first | `/orders` | — | `orders-item-1003` above `orders-item-1001` (the mock's dates) |
| R2 filter by status | `/orders` | taps `orders-tab-delivered` | only delivered rows visible; a shipping row not visible |
| R3 open detail | `/orders` | taps `orders-item-1003` | `order-detail-title` with the order code |
| Sign in fails with a wrong password | `/login` | types email and a wrong password, taps `login-submit` | `login-error` visible, still on login |

Each flow is independent: the open subflow stops the app and deep-links to the flow's start screen, so flows run in any order and alone (`--include-tags R2`). Without the `stopApp`, a deep link while the app is open can leave it where the previous flow ended (seen with native tabs: a link to `/` stayed on the Explore tab). Assert the state the requirement is about; one or two assertions are usually enough. A flow that walks through five screens to check one thing is five flows' worth of fragility.

## testIDs

- `testID` on the element the flow uses: the pressable for taps, the `TextInput` for typing, the `Text` or container whose visibility proves the requirement. On iOS it becomes the accessibility identifier, on Android the view tag Maestro reads; `id: "<testID>"` finds it on both.
- Names: kebab-case `<screen>-<element>` (`orders-list`, `orders-tab-shipping`, `login-email`, `login-submit`, `login-error`); rows `<screen>-item-<id>` with the item's id from the data, so a flow can pick a known mock item.
- Shared components take `testID?: string` and put it on their root or their pressable, the same way they pass `style`. Screens set the id; components don't invent it.
- Pressables keep their `accessibilityLabel` and `accessibilityRole`: a testID doesn't replace accessibility.
- Text components spread their props (`{...rest}`), so `testID` usually passes through already: check before editing.

## Layout

```
.maestro/
  config.yaml              which flows run by default
  README.md                how to run them, the env variables, the tags
  subflows/
    open.yaml              open a route
    sign-in.yaml           only if screens need a session and mocks can't start signed in
  SHOP-27/                 one folder per ticket
    r1-orders-newest-first.yaml
    r2-filter-by-status.yaml
  auth/                    flows without a ticket, by area
    sign-in-wrong-password.yaml
```

```yaml
# .maestro/config.yaml
flows:
  - "*/*.yaml"
excludeTags:
  - subflow
```

```yaml
# .maestro/subflows/open.yaml
appId: ${APP_ID}
tags:
  - subflow
---
# Start from a fresh launch, so a flow doesn't depend on where the previous one left the app.
- stopApp
- openLink: ${APP_URL}${ROUTE}
```

## Writing flows

```yaml
# .maestro/SHOP-27/r2-filter-by-status.yaml
appId: ${APP_ID}
name: "SHOP-27 R2: filter orders by status"
tags:
  - SHOP-27
  - R2
---
- runFlow:
    file: ../subflows/open.yaml
    env:
      ROUTE: /orders
- extendedWaitUntil:
    visible:
      id: "orders-list"
    timeout: 20000
- tapOn:
    id: "orders-tab-delivered"
- assertVisible:
    id: "orders-item-1001"        # delivered in the mock
- assertNotVisible:
    id: "orders-item-1003"        # shipping in the mock
- takeScreenshot: r2-delivered
```

Commands you'll use most:

| Command | For |
|---|---|
| `openLink: ${APP_URL}/route` (via the open subflow) | start on a screen |
| `launchApp` (with `clearState: true` when a flow needs a fresh install state) | start from the app's first screen |
| `extendedWaitUntil: { visible: { id: … }, timeout: 20000 }` | wait for a screen or data; the first open in Expo Go can take seconds while the bundle loads |
| `tapOn: { id: … }` | tap |
| `inputText: "…"` after tapping the input; `eraseText` to clear | type |
| `hideKeyboard` | before tapping something the keyboard covers |
| `assertVisible` / `assertNotVisible` with `id` (and `text` when the text is the requirement; it's a regex) | check |
| `scrollUntilVisible: { element: { id: … } }` | reach a row below the fold |
| `back` | Android back button |
| `takeScreenshot: <name>` | evidence; saved under the run's output folder |
| `runFlow: { file: …, env: { … } }` | reuse a subflow |

Rules:
- `appId: ${APP_ID}` in every flow, never a literal bundle id.
- No `sleep`-style waits, no `tapOn: { point: … }`: coordinates break on another device.
- No hard-coded `exp://`, `127.0.0.1` or scheme: the open subflow builds the URL from `${APP_URL}`.
- Name and tags: `"<ticket> R<n>: <behavior>"`, tags `[<ticket>, R<n>]`, plus `api` for a flow that needs the real backend, `smoke` for the few that should run on every CI build.
- Check syntax with `maestro check-syntax <file>` (`check-flows.sh` does it for all of them).

## Targets and environment

`run-flows.sh` sets these; set them yourself only when running `maestro test` by hand:

| Target | `APP_ID` | `APP_URL` | Before running |
|---|---|---|---|
| Expo Go, iOS Simulator | `host.exp.Exponent` | `exp://127.0.0.1:8081/--` | dev server on 8081, Expo Go installed (`npx expo start --ios` installs it) |
| Expo Go, Android emulator | `host.exp.exponent` | `exp://127.0.0.1:8081/--` | dev server on 8081, `adb reverse tcp:8081 tcp:8081` |
| Development build (`devBuild: true`, RN CLI) | the iOS bundle id / Android package | `<scheme>:/` (so `/orders` becomes `<scheme>://orders`) | the app built and installed (`npx expo run:ios`, `react-native run-ios`), connected to the dev server |
| Release / preview build (CI) | the bundle id / package | `<scheme>:/` | the build installed on the device; no dev server |

The scheme is `expo.scheme` in `app.json` (Expo) or the URL scheme registered in the native project (rn-ui `navigation.md`). Note the Android Expo Go package is lowercase.

## Data and sign-in

- Run against mocks: `EXPO_PUBLIC_USE_MOCKS=1` (rn-api-connect's flag) on the dev server. Flows can then rely on known items (`orders-item-1003`), and an empty or error state can be a dedicated mock the flow switches to through a route parameter or a mock flag the app already has. Don't add test-only branches to screens to make a flow pass.
- Signed-in screens: `EXPO_PUBLIC_MOCK_SIGNED_IN=1` (rn-ui's mock session, kept by rn-api-connect's `auth.md` in mock mode) starts the app signed in. Only flows about signing in itself go through the login screen, with the mock credentials from `src/mocks/`.
- Flows that need the real backend are tagged `api` and excluded by default (`--exclude-tags api` in the scripts); run them only on a dev server, with a test account the dev types in when asked, never with credentials written into a flow.
- Start the dev server with `EXPO_NO_DOTENV=1` and the variables on the command line, as rn-api-connect does: the developer's `.env` stays closed.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| The first flow times out on Expo Go | The bundle was still loading: raise the first `extendedWaitUntil` timeout, or open the app once before the run |
| `id: …` not found but the element is visible | The `testID` isn't on the rendered native view (a wrapper component dropped it): pass it through to the root |
| Works on iOS, not on Android | The Android Expo Go package is `host.exp.exponent`; `adb reverse` was lost when the emulator restarted |
| Deep link opens the home screen | The route doesn't exist at that path (check the project map's routes), or a guard redirected (not signed in) |
| Flaky taps right after navigation | Wait for the new screen's element before tapping |
| A flow passes alone but fails after another | The app was still on the previous flow's screen: open through the subflow (it stops the app first) |
