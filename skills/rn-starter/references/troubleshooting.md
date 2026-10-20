# Troubleshooting (fresh machines)

Find the symptom, apply the fix, rerun the step that failed. If nothing here matches, read the full error output, then check the official docs before guessing.

## Environment

| Symptom | Cause | Fix |
|---|---|---|
| `node: command not found` right after install-node.sh | the current shell hasn't loaded fnm | `source <skill-dir>/scripts/env.sh`; for the dev's own terminal: open a new window |
| `Unsupported engine` / `EBADENGINE` for react-native or expo | Node too old or an odd major | `fnm install --lts && fnm default lts-latest` |
| `xcrun: error: invalid active developer path` | Command Line Tools missing (after a macOS update too) | `xcode-select --install` (dev clicks Install) |
| `EACCES` on `npm install -g` | Node from the system/pkg installer, global dir owned by root | install Node via fnm (install-node.sh) instead of using sudo |
| `EMFILE: too many open files` | file watcher limit | macOS: install watchman (needs Homebrew — dev runs `brew install watchman` themselves) or `ulimit -n 65536` in that shell; Linux: raise `fs.inotify.max_user_watches` (needs sudo — give the dev the command) |

## Expo Go / Metro

| Symptom | Cause | Fix |
|---|---|---|
| Expo Go: "Project is incompatible with this version of Expo Go" | Expo Go on the phone supports one SDK; project uses another | update Expo Go from the store; project created with `@latest` should match the current store version. If the dev's Expo Go is newer, upgrade the project: `npx expo install expo@latest && npx expo install --fix` |
| Phone stuck on "Opening project…" / timeout | phone can't reach the computer (different Wi-Fi, guest/corporate network isolation, VPN, firewall) | `npx expo start --tunnel` (first run installs `@expo/ngrok`) |
| `Port 8081 is being used by another process` | an old Metro is still running | `lsof -ti :8081 | xargs kill` or start on another port `--port 8082` |
| `ERR_PNPM_IGNORED_BUILDS: Ignored build scripts: <pkg>` (pnpm 11) | pnpm blocks dependency install scripts that aren't approved, and fails | add `strictDepBuilds: false` to `pnpm-workspace.yaml` (skips the scripts, warns instead of failing), reinstall. Only if the package then doesn't work, set `allowBuilds: { <pkg>: true }` and tell the dev |
| pnpm prints `Done in …` but the command never returns (pnpm 11.x) | pnpm 11 keeps HTTPS connections to the registry open after installing, so the process doesn't exit; `expo install` waits on it forever | update pnpm: `npm install -g pnpm@latest` (12.x exits normally). If pnpm comes from Homebrew, the dev runs `brew upgrade pnpm`. As a stopgap, once `Done` is printed the install is complete and the process can be stopped |
| `Unable to resolve module …` after adding a lib | Metro cache or pnpm's symlinked layout | ensure `pnpm-workspace.yaml` has `nodeLinker: hoisted`, reinstall, then `npx expo start -c` / `npx react-native start --reset-cache` |
| `@/…` import not found (CLI) | Babel alias missing | see structure.md → Path alias |
| Red screen "Invariant Violation: … has not been registered" | app name mismatch between `index.js` and native project, or wrong entry after moving `App.tsx` | check `AppRegistry.registerComponent(appName, …)` matches `app.json` name; check `index.js` import path |

## Android build / emulator

| Symptom | Cause | Fix |
|---|---|---|
| `SDK location not found` | `ANDROID_HOME` not visible to Gradle | `source env.sh` before building, or write `sdk.dir=<ANDROID_HOME>` to `android/local.properties` |
| `Unsupported class file major version` / Gradle complains about Java | wrong JDK on PATH | `java -version` must say 17; `source env.sh` (sets JAVA_HOME) |
| `Failed to install the following SDK components … licenses not accepted` | licenses not recorded | rerun `install-android.sh --accept-licenses` (only after the dev accepted) |
| `No connected devices!` / `adb: no devices` | emulator not booted | `bash scripts/start-emulator.sh` |
| Emulator window black / crashes on Apple Silicon | x86 image on arm64 | AVD must use `arm64-v8a` image; delete and recreate via install-android.sh |
| Emulator very slow on Linux | no KVM | enable virtualization in BIOS; `ls /dev/kvm`; add user to `kvm` group (sudo — dev runs it) |
| First `run-android` seems stuck | Gradle downloading dependencies (can be 5–15 min) | keep waiting; check the background output for progress instead of restarting |
| "<System app> isn't responding" dialog over the app right after first boot | fresh AVD still settling | `start-emulator.sh` closes it automatically; otherwise `adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS` or tap *Wait* |
| AVD created but `emulator -list-avds` is empty | `avdmanager` and the emulator disagree on the home folder (custom `$HOME`, `ANDROID_USER_HOME` or `ANDROID_AVD_HOME`) | rerun `install-android.sh`; it pins `ANDROID_USER_HOME=$HOME/.android`. Check both `~/.android/avd` and `$ANDROID_USER_HOME/avd` |
| `INSTALL_FAILED_INSUFFICIENT_STORAGE` | emulator disk full | `emulator -avd rn_pixel -wipe-data` |
| Expo `--android`: "Expo Go not installed" loop | slow emulator first boot | wait for `start-emulator.sh` to report ready, then retry |

## iOS Simulator

| Symptom | Cause | Fix |
|---|---|---|
| `xcrun: error: unable to find utility "simctl"` / `xcodebuild requires Xcode` | `xcode-select` points at Command Line Tools | dev runs `sudo xcode-select -s /Applications/Xcode.app` |
| `You have not agreed to the Xcode license agreements` | license not accepted | dev runs `sudo xcodebuild -license accept` (their acceptance, not yours) |
| `No iOS runtime` / simulator list empty | Xcode 26 ships without the runtime | `xcodebuild -downloadPlatform iOS` (~8 GB) |
| Expo Go on the simulator/emulator: "The request timed out" | Expo opened the LAN IP (`exp://10.x.x.x:8081`), which some networks block between host and simulator | open `exp://127.0.0.1:<port>` instead: `xcrun simctl openurl booted exp://127.0.0.1:8081` / `adb shell am start -a android.intent.action.VIEW -d exp://127.0.0.1:8081` |
| `expo start --ios` hangs on "Fetching Expo Go" | first download of Expo Go for the simulator | wait; it's cached afterwards. If it fails, retry. Behind a proxy, check network |
| Simulator shows "Open in Expo Go?" | Expo couldn't pre-approve the `exp://` scheme (log: `Could not update simulator linking permissions`) | dev clicks *Open* once; it isn't asked again for that simulator |
| `pod: command not found` / `bundle exec pod install` fails with Ruby version errors | CocoaPods not installed, or system Ruby 2.6 is too old | `setup-ios.sh --cocoapods` (installs via Homebrew), then `cd ios && pod install` |
| `CocoaPods requires your terminal to be using UTF-8 encoding` | no `LANG` set | `export LANG=en_US.UTF-8` (env.sh does this) |
| `run-ios` fails: `No simulator available with name …` | default device name doesn't exist on this Xcode | pass `--udid` from `start-simulator.sh`, or `--simulator "iPhone 17 Pro"` with a name from `xcrun simctl list devices available` |
| Build error after adding a native library | pods not updated | `cd ios && pod install`, then rebuild |
| Simulator very slow / black screen | low disk space, or too many simulators booted | `xcrun simctl shutdown all`; free disk space (Xcode + runtimes need ~25 GB) |

## Re.Pack

| Symptom | Fix |
|---|---|
| App still loads with Metro | check `package.json` `start` script and `react-native.config.js` were updated by `repack-init`; restart the dev server |
| Library fails to bundle under Rspack | check https://re-pack.dev docs for loader config; if blocked, offer to switch back to Metro |
