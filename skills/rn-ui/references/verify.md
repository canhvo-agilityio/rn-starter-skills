# Verify against the design

Build logs prove the code compiles, not that it looks right. Look at every screen.

## 1. Static checks

```bash
npx tsc --noEmit          # compare with the baseline; only your new errors matter
npx expo-doctor           # Expo
npx expo lint || npm run lint   # if lint is set up
```

## 2. Run and open each screen

Do this on each run target in turn (main target first; see SKILL.md Phase 5 for how deep each pass goes). Start the app on that target (see rn-starter Phase 7 for commands: `start-simulator.sh` / `start-emulator.sh`, then `expo start --ios|--android` or `react-native run-*`) in the background. With Expo, stop the dev server before starting it for the next target.

- Don't set `CI=1` on `expo start`: it disables reloads, and you will be reloading after every fix. Without a TTY Expo already runs non-interactively.
- If Expo Go shows "The request timed out", it was opened with the LAN IP; open `exp://127.0.0.1:<port>` instead.
- **Reload after a fix:** re-opening the same URL does not reload. Terminate and reopen Expo Go: `xcrun simctl terminate booted host.exp.Exponent` (Android: `adb shell am force-stop host.exp.exponent`), then open the URL again. CLI apps: Fast Refresh applies JS edits; native changes need a rebuild.
- Expo Go draws a floating dev-menu (gear) button over every screen; ignore it in comparisons.

Then for each screen in the spec:

```bash
# open it (URLs: navigation.md → Deep links for verification)
xcrun simctl openurl booted "exp://127.0.0.1:8081/--/search"
sleep 2
xcrun simctl io booted screenshot <shots>/verify-search.png
# Android
adb shell am start -a android.intent.action.VIEW -d "exp://127.0.0.1:8081/--/search"
adb exec-out screencap -p > <shots>/verify-search.png
```

`<shots>` is your scratchpad directory, or a folder you made once with `mktemp -d` — not a fixed `/tmp` path. Read each screenshot. If it shows a red error screen, fix the error first.

## 3. Compare with the design

Put the design image (dev's screenshot, or the Figma frame image) and the app screenshot side by side and check, in this order:

1. **Structure** — same sections in the same order; nothing missing.
2. **Spacing & alignment** — margins, gaps between sections, alignment of text/icons.
3. **Typography** — font family visibly correct (custom vs system), weights, sizes, line breaks.
4. **Colors** — backgrounds, primary actions, text hierarchy. Use `palette.py --at X,Y` on both images when unsure.
5. **Components** — corner radius, borders, shadows, icon choice.

Fix the biggest differences first; prefer fixing tokens or shared components (fixes many screens at once) over one-off screen tweaks. Re-capture after fixing. Stop after 2–3 passes; list remaining differences in the spec's Open points rather than chasing pixels.

Platform differences are fine and not bugs: status bar, safe-area insets, native tab bar style, system font metrics.

**Device in the other scheme.** Phones run in dark mode as often as light, whatever the design shows. Switch the simulator/emulator to the scheme the design doesn't have, reopen one screen with a header or tab bar, and screenshot it:

```bash
xcrun simctl ui booted appearance dark        # iOS; back with: appearance light
adb shell cmd uimode night yes                 # Android; back with: night no
```

- Design with only one scheme → the screen must look exactly as before: same background, readable status bar, design-colored header and tab bar. If not, the app isn't locked to the design's scheme (`theme.md` section 2).
- Design with both schemes → compare the screen with the design's dark frame, like the other screens.

Switch the device back afterwards.

## 4. Tap the main flow once

E.g. Login → Home → open an item → back → switch tabs → Profile → log out. Navigation bugs (wrong stack, missing back button, tab state lost, "Unmatched Route" after logout) only show up this way.

To tap: on Android `adb shell input tap <x> <y>` (device pixels from the screenshot). On iOS use a simulator-control tool if your environment has one (e.g. an iOS Simulator MCP with `tap`); otherwise ask the dev to tap through once and tell you what happens, and cover the rest with deep links.

## 5. Record

Set each screen's status to `verified` in `docs/design-spec.md`, with the targets it was checked on (e.g. `verified (iOS, Android)`). Keep the final screenshots out of the repo unless the dev wants them (e.g. `docs/design/screens/`).
