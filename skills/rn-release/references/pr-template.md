# The release pull request

Branch `release/<version>` from the base branch (`release.baseBranch` in `.rn-starter.json`, `main` by default), title `Release <version>`, against the base branch. The PR is what the release manager approves, so its body has everything they need to decide without opening anything else. The release gate checks the approval on the PR's head commit: a commit pushed after the approval needs a new one.

What the branch changes:
- `app.json` → `expo.version` = `<version>` (store build only; an OTA release keeps the store build's version).
- `CHANGELOG.md` → the new section (`notes.md`).

Nothing else. A fix found during the release goes to the base branch through its own PR first, then the release branch is cut again (or the fix is merged in and the approval asked again).

## Body

```markdown
## Release 1.4.0

**Route:** store build (native code changed since 1.3.2: runtime 3f9c2a1 → 8be04d7)
**Ships:** the production app, com.acme.coffeeshop, iOS and Android
**From commit:** 4f2c9e1 (this PR's head). Approving approves exactly this commit.

### What's new (store)
<the store text, per language>

### Changes
<the CHANGELOG section>

### Checklist
| Check | Result |
|---|---|
| Type check, lint, unit tests on 4f2c9e1 | pass (jest 112/112) |
| Maestro flows on the dev app / Expo Go | pass 24/24 |
| EAS production variables (names only) | all 3 set: EXPO_PUBLIC_API_URL, EXPO_PUBLIC_USE_MOCKS, EXPO_PUBLIC_SENTRY_DSN |
| Production credentials on EAS | profile expires 2027-10-20; nothing expires within 30 days |
| New permissions or data collected | none → store privacy answers unchanged |
| Store screenshots | unchanged |

### Not verified
<what nobody checked, from the merged PRs' "Not verified" lines and this release: e.g. Android on a real device>

### On approval
The rn-release skill will run:
1. `eas build --profile production --platform all`
2. `eas submit --profile production --platform ios --id <build>` and the same for Android → TestFlight / Play internal testing
3. `git tag v1.4.0 4f2c9e1` and push it

Then a person, in the store consoles: submit 1.4.0 for App Store review and choose the release (manual / phased); promote the Play build from internal testing to production with a staged rollout.

Approvers: @lead-ni (release manager). Approve only if you own this release.
```

For an OTA release, "On approval" is `APP_VARIANT=production eas update --channel production --environment production --message "1.4.1: …"` (with `--rollout-percentage` when the dev chose a staged rollout), and there's no store step.
