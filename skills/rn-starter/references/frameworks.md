# Frameworks, templates and create commands

**Contents:** Expo (templates to offer, create, Ignite, verify) · React Native CLI (templates to offer, create, Re.Pack, verify)

All commands must be non-interactive: a prompt inside a Bash call hangs until timeout. Always pass the template and a target directory explicitly. If a flag fails, run the tool's `--help` and adapt — flags change between releases.

Prefix commands with `source <skill-dir>/scripts/env.sh &&` when Node was installed during this session.

## Expo

### Templates to offer

| Template | What it gives | Offer as |
|---|---|---|
| `default` | TypeScript, **expo-router** (file-based routing) with routes in `src/app`, `@/` alias already configured, tab layout, example screens, themed components, React Compiler on, web support | Recommended |
| `blank-typescript` | TypeScript, single `App.tsx`, nothing else — you add navigation yourself | For devs who want to choose everything |
| `tabs` | Like default, tab navigation with expo-router | Only if they explicitly want tabs |
| Ignite (boilerplate) | Opinionated full app: navigation, i18n, theming, generators, demo screens | "Batteries included" option |

Don't offer `blank` (JavaScript) unless the dev asks for plain JS, and don't offer `bare-minimum` (it generates native folders, which pushes the dev toward a native build they didn't ask for).

If the template is `default` or `tabs`, navigation is already decided (expo-router) — skip the navigation question in Phase 3.

### Create

```bash
# npm
npx create-expo-app@latest <name> --template <template>
# pnpm
pnpm create expo-app <name> --template <template>
# yarn / bun
yarn create expo-app <name> --template <template>
bun create expo-app <name> --template <template>
```

For pnpm: the create command installs dependencies immediately. To get the hoisted layout in place first, use `--no-install`, write `pnpm-workspace.yaml`, then `pnpm install`:

```bash
pnpm create expo-app <name> --template <template> --no-install
cd <name> && printf 'nodeLinker: hoisted\nstrictDepBuilds: false\n' > pnpm-workspace.yaml && pnpm install
```

`strictDepBuilds: false`: pnpm 11+ refuses to run dependencies' install scripts unless approved, and by default **fails the install** over it (`ERR_PNPM_IGNORED_BUILDS` — seen with `unrs-resolver` from Expo's ESLint config and `@parcel/watcher` from Jest). With this setting it keeps skipping them (safe default; these packages ship prebuilt binaries) and only warns. pnpm then adds `allowBuilds:` entries with the value "set this to true or false"; `setup-quality.sh` turns them into `false`. Only switch one to `true` if a package actually doesn't work, and tell the dev — that lets it run its install script.

`create-expo-app` also writes an `AGENTS.md` and `.claude/settings.json` into the project (helpful for working with Claude later) — leave them unless the dev asks otherwise (`--no-agents-md`).

### Ignite

Ignite asks many questions by default. Use its non-interactive flags:

```bash
npx ignite-cli@latest new <Name> --yes --packager=<npm|pnpm|yarn|bun> --workflow=cng --remove-demo=false
```

If those flags are rejected, check https://github.com/infinitered/ignite/blob/master/docs/cli/Ignite-CLI.md. Ignite already decides navigation (React Navigation), state and folder structure — skip the library and structure questions, only mention what it includes.

### Verify

```bash
cd <name>
npx expo-doctor                                    # dependency/config health — must pass
npx expo export --platform android --output-dir .expo/export-check   # proves Metro can bundle the app, no device needed
```

TypeScript: `expo-env.d.ts` (CSS module / asset type declarations) is only generated the first time `expo start` runs, so `tsc --noEmit` right after create reports false errors like `Cannot find module './x.module.css'`. Start the dev server once (Phase 7 does this anyway) before relying on `tsc`.

Templates sometimes ship with a type error of their own (seen in SDK 58: `src/components/app-tabs.web.tsx` ref type). Record the `tsc` output right after creating as the baseline; only errors that appear after your changes are yours to fix. Mention pre-existing ones to the dev rather than hacking around them.

## React Native CLI (bare)

### Templates to offer

| Template | What it gives | Offer as |
|---|---|---|
| Default (`@react-native-community/template`) | TypeScript, single `App.tsx`, `android/` and `ios/` | Recommended |
| Custom (npm package or git URL) | Team template | Only if the dev provides one via "Other" |

### Create

App name must be letters and digits only (no dashes/spaces), e.g. `MyApp`. Suggest one derived from what the dev typed.

```bash
# npm / yarn / bun
npx @react-native-community/cli@latest init <Name> --pm <npm|yarn|bun> --skip-git-init --install-pods false

# pnpm (init doesn't accept --pm pnpm)
npx @react-native-community/cli@latest init <Name> --skip-install --skip-git-init --install-pods false
cd <Name> && printf 'nodeLinker: hoisted\nstrictDepBuilds: false\n' > pnpm-workspace.yaml && pnpm install
```

`--install-pods false`: CocoaPods install is deferred. If the iOS Simulator is a target, run `cd ios && pod install` after libraries are added (needs CocoaPods from `setup-ios.sh --cocoapods`). If it's Android-only, skip pods entirely. After creating, run `git init && git add -A` yourself so the first commit is clean.

Optional `--package-name com.company.app` if the dev cares about the Android package id.

The init output ends with "Run instructions" that say `bundle install` / `bundle exec pod install`. Don't follow those on a fresh Mac: they need a newer Ruby than macOS ships. Use `cd ios && pod install` with CocoaPods from Homebrew (`setup-ios.sh --cocoapods`).

### Re.Pack (only if chosen as bundler)

Run inside the project after install:

```bash
npx @callstack/repack-init
```

It replaces Metro config with `rspack.config.mjs` and rewires `start`/`bundle` commands. Then `npx react-native start` uses Rspack. Docs: https://re-pack.dev

### Verify

```bash
npx tsc --noEmit
```

The real check is the first `run-android` build in Phase 7.
