@AGENTS.md

## Claude Code in this repo

- A hook formats and lint-fixes every file you edit (`.claude/hooks/format.mjs`). When it reports problems, fix them before moving on.
- A guard hook (`.claude/hooks/guard.mjs`) blocks pushes to {{PROTECTED}}, reading or editing secret files (`.env`, signing keys, keystores, service-account keys), hand edits to generated `*.gen.ts` files, and changes to a test locked while a bug is being fixed. When it blocks something, do what its message says; don't look for a way around it.
<!-- release-gate -->
- A release gate (`.claude/hooks/release-gate.mjs`) lets dev-app builds and updates through, asks before submitting the dev app, and blocks shipping the production app (EAS build, submit, OTA update, a `v*` tag) unless the commit is on the remote's production branch, where only a release manager merges `release/<version>` pull or merge requests. Production releases go through the `rn-release` skill. Never approve or merge a pull request or merge request, and never push to the production branch.
<!-- /release-gate -->
- For a change someone can see or tap, run the `verifier` subagent: it opens the app, checks the change and reports, without editing.
- Before calling a change finished or opening a pull request, run the `code-reviewer` subagent on it and fix what it reports.
- When you make the same mistake twice, add the correction to `AGENTS.md` (here only if it's about Claude Code itself).
