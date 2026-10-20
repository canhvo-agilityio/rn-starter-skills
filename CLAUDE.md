# rn-starter-skills

Claude Code plugin `rn-starter` with two skills for React Native developers:

- `skills/rn-starter/` — wizard: clean machine (macOS, Windows, Linux) → running RN app, with stack questions, toolchain installs, feature-first scaffold, quality tooling, and a run on every selected target.
- `skills/rn-design-import/` — text / screenshots / Figma → themed, navigable screens in an RN/Expo project, via an approved `docs/design-spec.md`.

Read before changing anything:
- [spec.md](spec.md) — intent, scope, acceptance criteria, current test status.
- [DESIGN.md](DESIGN.md) — architecture, contracts between the skills, script conventions, cross-platform strategy, and the **key decisions table**. Don't relitigate a decision listed there without new evidence; most came from real test failures.

## Rules for this repo

- Everything in the repo is English. The skills talk to each developer in that developer's language.
- Keep each `SKILL.md` short; detail goes in `references/` and is pointed to from the phase that needs it.
- Deterministic work belongs in a script with stable output and the exit-code convention (0 done · 1 error · 2 waiting on the developer · 3 done with a decision needed). Every script must be idempotent and non-interactive.
- Every bash entry script that installs or checks tools has a PowerShell twin in `skills/rn-starter/scripts/windows/` (Windows PowerShell 5.1 syntax only) and calls `delegate_to_windows` right after sourcing `lib.sh`.
- When options depend on an earlier answer, ask them in a later `AskUserQuestion` call.
- Bump `version` in `.claude-plugin/plugin.json` on every push — testers' `claude plugin update` only sees version changes.

## Validate before committing

```bash
claude plugin validate .
for f in skills/*/scripts/*.sh; do bash -n "$f" || echo "BAD $f"; done
node --check skills/rn-design-import/scripts/figma-panel.js
```

PowerShell files: parse them with `pwsh` (`[System.Management.Automation.Language.Parser]::ParseFile`) if it's available; on macOS a portable pwsh in a scratch folder works.

## How to test changes

- Clean machine, simulated: `env -i HOME=<empty dir> SHELL=/bin/zsh PATH=/usr/bin:/bin:/usr/sbin:/sbin bash <script>`. System-wide installs (Xcode, `/Library/Java`) still leak through — say so when reporting.
- End to end: create a test app in a scratch folder (never in this repo), follow the skill, run it on the simulators/emulators, and read the screenshots back.
- Skill instructions: have a subagent follow a `SKILL.md` literally on a test project and report every instruction that was wrong, ambiguous or missing — that found more bugs than anything else.
- Windows: no Windows machine here. Real runs happen on the tester's machine; they send screenshots.

## Publishing

- Repo: github.com/canhvo-agilityio/rn-starter-skills (public). `main` holds only an init commit; work goes to `feat-rn-starter-skill` until the PR is merged.
- Testers: `claude plugin marketplace add canhvo-agilityio/rn-starter-skills#feat-rn-starter-skill`, then `claude plugin install rn-starter@rn-starter-skills`; after a push, `claude plugin marketplace update rn-starter-skills`.
- Evidence of runs (screenshots, recordings) goes in `docs/evidence/`.

## Traps already hit

- pnpm 11 hangs after "Done" and fails on skipped build scripts → doctor warns; `strictDepBuilds: false`.
- Expo templates ship type and lint errors → take baselines; commit the scaffold before hooks.
- `Stack.Protected` doesn't redirect → navigate explicitly after sign-in/out.
- avdmanager and the emulator disagree on the AVD folder → `ANDROID_USER_HOME` pinned.
- zsh treats `===` as a command and doesn't word-split `$var` — quote test commands accordingly.
