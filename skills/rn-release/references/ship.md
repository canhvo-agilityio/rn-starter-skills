# Shipping, locking, rolling back

Every command here that reaches the production app passes through the release gate. If it denies, relay its reason and stop: the reason names what's missing (the merge, a commit added after approval, a version mismatch). Never retry with another profile, channel or `APP_VARIANT` to get past it.

Ship from the production branch as the release manager merged it: `git switch <production branch> && git pull --ff-only`, `git status` clean.

## Store build

Where builds run is in `docs/release-plan.md` (EAS cloud or local).

```bash
eas build --profile production --platform all --non-interactive --json > <scratchpad>/builds.json
```

- Read the build ids and their status from the JSON (or `eas build:list -e production --limit 2 --json`). A failed build: read its logs (`eas build:view <id>`), fix on the base branch, and the fix goes through a new release PR / MR. Never patch the production branch.
- Then submit each build by id, never `--latest` (the latest build may not be this release's):

```bash
eas submit --profile production --platform ios --id <ios build id> --non-interactive
eas submit --profile production --platform android --id <android build id> --non-interactive
```

EAS submit puts the build in **TestFlight** and the **Play internal testing** track (or the track in `eas.json`). Going live is a person's step in the store consoles, listed for them in the hand-off:
- App Store Connect: the build on the version 1.4.0 page → *Add for Review* → *Submit*; choose manual or automatic release, and phased release over 7 days if wanted.
- Play Console: *Testing → Internal testing* → promote the release to *Production* with a staged rollout (e.g. 10 %), then raise it.

## OTA update

```bash
APP_VARIANT=production eas update --channel production --environment production \
  --message "1.4.1: <one-line summary>" --rollout-percentage 10 --non-interactive
```

- Only when `runtime.nativeChanged` is false: the update reaches only builds with the same runtime version, so after a native change it would reach nobody.
- `--rollout-percentage`: start small when the dev wants it; raising it later (`eas update:edit --rollout-percentage 50`) is a channel change the gate asks about.
- The update is live as soon as the command finishes. There's no review step.

## Lock the version

Right after shipping, on the commit that shipped:

```bash
git tag -a v<version> -m "Release <version>" <sha>
git push origin v<version>
```

The gate allows the tag only on a commit that's on the production branch. Once the tag exists, the gate refuses to ship that version from any other commit, so a later change needs a new version and a new approval. Merging the production branch back into the base branch is a person's step (a PR / MR); remind them so `CHANGELOG.md` and the version reach it.

## Rolling back

Say these plainly in the hand-off; run them only when the dev asks, and the gate asks the person for each.

- **OTA**: republish the previous update group to production (`eas update:list --branch production`, then `eas update:republish --group <previous group id>`), or `eas update:roll-back-to-embedded --channel production` to send users back to the code inside their store build.
- **Store build**: Apple has no rollback; pause a phased release in App Store Connect and ship a fixed version. Play: halt the staged rollout in Play Console, then ship a fixed version with a higher build number. A fixed version is a new release through this skill.
