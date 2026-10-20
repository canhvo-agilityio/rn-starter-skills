# Compatibility matrix

Use this to decide which options to show. If a combination is marked ✗, don't offer it; if the dev asks for it anyway via "Other", explain why it won't work and offer the closest valid choice.

Last verified: 2026-10 (Expo SDK 58, React Native 0.88, @react-native-community/cli 20, Re.Pack 5, Xcode 26.6, CocoaPods 1.17). Tested end to end: Expo + pnpm on the iOS Simulator; RN CLI + pnpm + pod install + run-ios on the iOS Simulator; install-android.sh from a clean home, then Expo and RN CLI (run-android) on the Android emulator.

## Framework × bundler

| | Metro | Re.Pack (Rspack) |
|---|---|---|
| Expo | ✓ (only option) | ✗ — Expo's CLI, dev server and Expo Go are built on Metro |
| RN CLI | ✓ default | ✓ via `npx @callstack/repack-init` after init |

## Framework × run target

| | Expo Go (iPhone / Android phone) | iOS Simulator | Android emulator | Web |
|---|---|---|---|---|
| Expo | ✓ no toolchain needed | ✓ macOS + Xcode; Expo Go is auto-installed in the simulator; no CocoaPods | ✓ needs JDK + Android SDK; Expo Go is auto-installed on the emulator | ✓ `default` template already includes `react-dom` + `react-native-web`; for others `npx expo install react-dom react-native-web` |
| RN CLI | ✗ Expo Go only loads Expo projects | ✓ macOS + Xcode + **CocoaPods** (via Homebrew) | ✓ native build with Gradle | ✗ not set up by default |

What needs an Apple ID or a password, and who does it:

| Step | Needs | Who |
|---|---|---|
| Download Xcode | Apple ID (a free one is fine) via App Store. Or the team's `.xip`, which needs none | dev |
| `sudo xcode-select -s`, `sudo xcodebuild -license accept`, `sudo xcodebuild -runFirstLaunch` | Mac admin password; accepting Apple's license | dev |
| Install Homebrew (RN CLI + iOS only) | Mac admin password | dev |
| iOS runtime download, simulator create/boot, `brew install cocoapods`, building and running in the simulator | nothing | Claude |
| Installing a **native build on a real iPhone** | Apple ID + code signing | out of scope. Use Expo Go on the iPhone instead |

## Expo Go × libraries

Expo Go ships a fixed set of native modules. A library with its own native code that is **not** in Expo Go needs a development build (`npx expo run:android`, i.e. the emulator toolchain). Everything in `libraries.md` works in Expo Go except where noted there.

## Package manager notes

| | Expo | RN CLI |
|---|---|---|
| npm | ✓ | ✓ (`--pm npm`, default) |
| pnpm | ✓ use `pnpm create expo-app`; set `nodeLinker: hoisted` in `pnpm-workspace.yaml` | ✓ but `init --pm` doesn't accept pnpm: init with `--skip-install`, add `pnpm-workspace.yaml` with `nodeLinker: hoisted`, then `pnpm install` |
| yarn | ✓ `yarn create expo` | ✓ `--pm yarn` |
| bun | ✓ `bun create expo` | ✓ `--pm bun` |

## Node versions

React Native 0.88 and Expo SDK 58 require `^22.13.0 || ^24.3.0 || >=26` (LTS lines). Odd majors (23, 25) are rejected by engine checks.

## Android

- JDK 17 (React Native's documented recommendation).
- Compile/target SDK comes from the template; the emulator image is Android 15 (API 35). Gradle downloads any other platform/build-tools the project needs, as long as the license was accepted.
- Apple Silicon Macs need `arm64-v8a` system images; Intel/Linux x86 need `x86_64`. `install-android.sh` picks automatically.

## iOS

- Xcode 26 (verified with 26.6 and the iOS 26.5 runtime). Xcode no longer bundles the simulator runtime; `setup-ios.sh` downloads it with `xcodebuild -downloadPlatform iOS`.
- CocoaPods: macOS's built-in Ruby 2.6 can't install current CocoaPods dependencies (e.g. `ffi` needs Ruby ≥ 3.0). Use `brew install cocoapods`, which brings its own Ruby. The RN template's `Gemfile`/`bundle exec pod install` path also needs a modern Ruby, so the plain `pod install` from Homebrew is simpler for beginners.
