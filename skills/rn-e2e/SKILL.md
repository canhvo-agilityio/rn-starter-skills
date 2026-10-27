---
name: rn-e2e
description: Writes and runs end-to-end tests for a React Native / Expo app with Maestro - one flow per requirement (R1, R2… from a ticket, or the behaviors the dev lists), stable testIDs on the elements they use, run on the iOS Simulator or Android emulator against mock data, with JUnit reports and screenshots as evidence, and flows driven by environment variables so CI can run them on a build. Use when someone wants E2E / UI tests, Maestro flows, to "test this flow in the app", to prove a ticket's acceptance criteria, or to reproduce a bug end to end. Also called by rn-feature for a ticket's flows.
---

# End-to-end flows (Maestro)

Goal: each behavior that matters has a Maestro flow that opens the app where the behavior starts, does what a user does, and asserts what they should see; the flows pass on the simulator, run with one command, and work unchanged in CI. A flow is the evidence for one requirement, so its name and tags say which.

Talk to the dev in their language. **Invoked as a slash command**, the text after the skill's name is the dev's request: read it like any message, use what it gives (links, names, files, constraints) and ask only for what it leaves out. Flows test the app; they never change what it does. The only app code this skill touches is `testID` props and accessibility labels (a pressable card needs one for its content to be readable at all, by VoiceOver and by Maestro).

**Called by rn-feature** (the arguments start with `Called by rn-feature`): follow `../rn-feature/references/handoff.md`. Scope is the R# list; write the flows into `.maestro/<ticket-id>/`, run them on the main target, don't commit, and end with the report block, one line per R# with the flow file and pass / fail. A flow that fails because the app is wrong is reported as `fail` for that R#, never weakened to pass.

## Phase 0: Check the machine and the project

```bash
source "<skill-dir>/../rn-starter/scripts/env.sh"; bash "<skill-dir>/scripts/e2e-doctor.sh" <project-dir>
```

JSON: Maestro (path, version), Java (Maestro needs 17+), booted simulators and emulators, how the app is opened (Expo Go, or a development / release build with its bundle id, package and scheme), the `.maestro/` folder with its flows and tags, and how many `testID`s the code has.

- **Exit 2, Maestro missing**: ask once (*Install Maestro (Recommended)* / *I'll install it myself*). On a yes: `bash "<skill-dir>/scripts/install-maestro.sh"`. It uses Maestro's official installer into `~/.maestro`, adds JDK 17 into rn-starter's folder only if no Java 17+ exists, and puts both on PATH through a marked block in the shell rc file. Windows: Maestro runs Android flows only; follow its docs, don't run the script.
- **No booted device**: boot one with rn-starter's `scripts/start-simulator.sh` or `start-emulator.sh`.
- **No `.maestro/`**: first run here; Phase 3 creates the layout.

**Invoked as a slash command with nothing else** (`/rn-e2e`): after Phase 0, ask once what to cover: each `docs/tickets/*.md` whose active R# have no flow yet (`check-flows.sh --ticket`), *A screen or flow I'll describe*, or *Rerun the existing flows* (straight to Phase 4).

## Phase 1: Decide what each flow proves

From the ticket file (`docs/tickets/<id>.md`: Requirements and Traceability) or the dev's list: one flow per R#, named after it. An R# that isn't visible end to end (a mapper rule, a header sent to the API) is covered by a unit test instead: name that test in the report rather than forcing a flow.

Read `references/flows.md` → What a flow covers. Each flow states where it starts (a route), the user's actions, and the assertions that prove the R#, including the state that matters for it (empty list, error message, the item after a mutation).

## Phase 2: testIDs

Flows find elements by `testID`, not by text, which changes with copy and language. Read `references/flows.md` → testIDs:

- Add `testID` to each element a flow taps, types into or checks: kebab-case `<screen>-<element>` (`orders-list`, `orders-tab-shipping`, `login-email`), list rows `<screen>-item-<id>`.
- Shared components accept a `testID` prop and pass it to their root (or the pressable), so screens set ids without new components.
- A pressable card hides its children on iOS: give it an `accessibilityLabel` with its content and assert that (`references/flows.md` → testIDs).
- Nothing else changes in the component. Run `npx tsc --noEmit` and the related unit tests after.

## Phase 3: Write the flows

Follow `references/flows.md` → Layout and Writing flows:

- `.maestro/config.yaml` (runs `*/*.yaml`, skips the `subflow` tag), `.maestro/subflows/open.yaml` (stops the app, then opens `${APP_URL}${ROUTE}`, so every flow starts fresh), a sign-in subflow when screens need a session.
- One file per flow: `.maestro/<ticket-id>/r<n>-<slug>.yaml` with `appId: ${APP_ID}`, `name: "<ticket> R<n>: <behavior>"` and `tags: [<ticket>, R<n>]`. Flows without a ticket go in `.maestro/<area>/<slug>.yaml` tagged with the area.
- Wait with `extendedWaitUntil`, never fixed sleeps. Assert by id; check text only where the text is the requirement.
- Never a hard-coded URL, bundle id or coordinate: `${APP_ID}` and `${APP_URL}` come from the run, so the same flows run in Expo Go here and on a build in CI.

Check them:

```bash
bash "<skill-dir>/scripts/check-flows.sh" <project-dir> [--ticket <project-dir>/docs/tickets/<id>.md]
```

Exit 3 lists problems (syntax, a missing `${APP_ID}`, a hard-coded URL, a coordinate tap, a flow without its R# tag) and, with `--ticket`, which R# have no flow yet.

## Phase 4: Run them

Flows run against mock data, so runs are repeatable. Write the dev-server variables they rely on into `.maestro/dev-server.env` (one `EXPO_PUBLIC_…=value` per line, never a secret), e.g. `EXPO_PUBLIC_MOCK_SIGNED_IN=1` when the screens need a session; an app whose services return mocks without a flag may need none. Prefer flows that don't depend on it at all: a flow that needs a session can sign in through a subflow with the mock credentials. Then:

```bash
bash "<skill-dir>/scripts/run-flows.sh" <project-dir> --platform ios --start-server [--tags SHOP-27] [--out <dir>]
```

With `--start-server` and nothing on port 8081, it starts the dev server with `EXPO_NO_DOTENV=1` and those variables, and stops it after; a server already running is used as is (the JSON lists the variables it should have been started with). Flows that need the real API are tagged `api` and run only when asked.

It picks `APP_ID` and `APP_URL` for the target (Expo Go on the iOS Simulator, Expo Go on the Android emulator after `adb reverse`, or a development build with `--build`), runs Maestro with a JUnit report, and prints JSON: each flow with its tags, pass / fail, the failure message and its screenshots folder.

A failing flow: read the failure and the screenshot. When every flow fails at its first wait, suspect the setup before the flows (the JSON's `hint`): a dev server without the variables, the app on its sign-in screen, an Expo Go sheet over the app. A wrong selector or a missing wait is the flow's fault; fix the flow. Wrong app behavior is a finding: report it (or, building a ticket, it goes back to the step that owns the R#). Don't loosen an assertion to get green.

Run on every target in `runTargets` that Maestro supports (iOS Simulator, Android emulator); a phone through Expo Go isn't one of them, so list it as not covered.

## Phase 5: Ready for CI

Read `references/ci.md`. Add `package.json` scripts so anyone runs the flows with one command (`e2e:ios`, `e2e:android`), and a short `.maestro/README.md` (how to run, the dev-server variables from `dev-server.env`, what `APP_ID` / `APP_URL` mean, which tags exist). CI builds the e2e app with the same `dev-server.env` values. CI runs the same flows on an installable build, not Expo Go; `rn-pipeline` wires it.

## Phase 6: Hand-off

Tell the dev: the flows written (per R#), where they passed (per target), what isn't covered and why, how to run them. Offer to commit (`test(e2e): flows for <ticket or area>`); don't commit without a yes. Called by rn-feature: the report block instead.

## Principles

- **One flow, one requirement.** The name and tags say which R# it proves.
- **ids, not text or coordinates.** Copy and layout change; ids don't.
- **Mocks by default.** A flow that depends on live data fails for reasons unrelated to the app.
- **Same flows everywhere.** Environment variables pick the target; the flow files never change between a laptop and CI.
- **A red flow is information.** Fix the flow when it's wrong, report the app when it's wrong, never weaken the check.
