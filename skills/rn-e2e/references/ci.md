# Flows in CI

The flows written here run unchanged in CI; only the environment differs. No skill sets the CI job up yet: this file is what a job needs from the flows, the usual options, and what to tell the dev, so the dev (or Claude, on request) can write it for GitHub Actions or GitLab CI.

## What CI needs

- **An installable build, not Expo Go.** CI has no dev server and no Expo Go: it installs a build of the app (an iOS Simulator build, an Android APK) and runs the flows with `APP_ID` = the bundle id / package and `APP_URL` = `<scheme>:/`. Building it is the slow part of an E2E job, so E2E usually runs on pull requests to the main branch or nightly, not on every push.
- **Mock data in that build.** The build is made with `EXPO_PUBLIC_USE_MOCKS=1` (and `EXPO_PUBLIC_MOCK_SIGNED_IN=1` when the flows rely on it), as an EAS environment or build profile of its own (`e2e`), so the flows see the same data as locally.
- **A report.** `maestro test .maestro --format junit --output <dir>/report.xml --test-output-dir <dir>/run`: the JUnit file feeds the CI's test summary; the run folder (screenshots, hierarchy, logs per failing flow) is uploaded as an artifact.
- **Tags to choose what runs.** `--include-tags smoke` for a quick job, everything but `api` for the full one (`--exclude-tags api`).

## The usual options

| Option | How | Good for |
|---|---|---|
| EAS Workflows | a workflow with a build job (simulator / APK, `e2e` profile) followed by a Maestro job on that build; flows read from `.maestro/` | Expo projects already on EAS (`rn-release-setup`); no macOS runners to maintain |
| GitHub Actions, Android | an Ubuntu runner with an Android emulator action, the APK built in the job or downloaded from EAS, Maestro installed with its script | teams on GitHub without iOS E2E in CI |
| GitHub Actions, iOS | a macOS runner, a simulator build, the simulator booted with `xcrun simctl` | when iOS must be covered in CI; macOS minutes cost more |
| Maestro Cloud | `maestro cloud <app> .maestro/` | parallel devices without running them yourself; paid |

Check each option's current docs when writing the job: job names and parameters change.

## What to keep in the repo

- `.maestro/` with `config.yaml`, the subflows, the flows, and `README.md`.
- `package.json` scripts the dev and CI share:
  ```json
  {
    "e2e:ios": "maestro --platform ios test .maestro --exclude-tags api -e APP_ID=host.exp.Exponent -e APP_URL=exp://127.0.0.1:8081/--",
    "e2e:android": "maestro --platform android test .maestro --exclude-tags api -e APP_ID=host.exp.exponent -e APP_URL=exp://127.0.0.1:8081/--"
  }
  ```
  (For a development-build project, the bundle id / package and `<scheme>:/` instead.) CI calls `maestro test` with its own `APP_ID` / `APP_URL` and report options.
- Nothing generated: run folders and reports go to a temporary folder or a CI artifact, never into the repo.
