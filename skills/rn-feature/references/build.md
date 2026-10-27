# Building a ticket

**Contents:** Before you start · The plan (plan mode) · Branch and commits · Running the steps · Bug tickets: the failing test first · Verify · Pull request · When things change

The ticket file is the contract: R# say what to deliver, the concerns and their decisions say what changed since the ticket was written, Scope says what it touches. Building turns it into a plan the dev accepts, then into commits, each step proven, ending in a pull request whose body maps every R# to its evidence.

## Before you start

Run `project-map.sh` and `check-ticket.sh` on the ticket file, then:

| Situation | Do |
|---|---|
| No ticket file | Analyze first (the analysis phases), then come back |
| A `blocking` concern | Stop. Tell the dev which concern and whose answer it waits for |
| `decide` concerns still open | One `AskUserQuestion`: *Build with the recommended answers (Recommended)* / *Wait for the answers*. Building with them is the dev's call, not the owner's answer: record each one in the ticket file as `assumed` in the concern's text (severity stays `decide`), and list them in the PR so the owner can still object |
| The ticket changed since the analysis (new comments, edited criteria) | Run a follow-up analysis first |
| Another ticket `in-progress` touches the same files (`filesTouched`) | Tell the dev; build after it or agree who touches the shared file |
| Uncommitted changes other than the ticket file you just updated | Ask the dev to commit or stash them first. The ticket file goes into the plan's first commit, on the feature branch (Phase 10); nothing is committed on `main` or another protected branch |
| Claude Code wasn't started from the project folder | The project's hooks (format, guard) and its subagents (`code-reviewer`, `verifier`) load only when the session's working directory is the project. Say so: the dev restarts Claude Code there, or you go on knowing the guard isn't active and do the subagents' checklists yourself |

## The plan (plan mode)

Enter plan mode (`EnterPlanMode`), where nothing can be edited, and read the code the ticket touches: the screens and components named in Scope, the services and hooks of the domains, the navigation layout, the theme, the tests nearby. Then write the plan and present it with `ExitPlanMode`. The dev accepting it is the approval; nothing is edited before.

The plan is a table of steps, each small enough to verify on its own and to commit:

| Step | What | Skill | R# | Files | Check |
|---|---|---|---|---|---|
| 1 | Sign-in session behind the mock's interface | rn-api-connect (`auth.md`) | — | `src/stores/session.ts`, `src/services/auth.ts`, `src/lib/api-client.ts` | store + refresh tests; sign in on the simulator |
| 2 | Orders tab in the tab bar, then the orders and order detail screens on mocks shaped like the API | rn-ui | R1, R3, R5, R6 | `src/components/app-tabs.tsx`, `src/screens/orders/*`, `src/screens/order-detail/*` | screenshots against the theme; tsc, lint, tests |
| 3 | Pull to refresh on the list | direct | R1 | `src/screens/orders/index.tsx` | refresh test |
| 4 | Domain `orders` on the API: list with paging and status, detail | rn-api-connect | R1, R2, R4, R7, R8 | `src/services/orders.ts`, `src/hooks/use-orders.ts` | mapper tests; real data on screen |
| 5 | Flows for R1–R8 | rn-e2e | R1, R2, R3, R5, R6, R8 | `.maestro/SHOP-27/*`, `testID`s in the new screens | flows pass on the iOS Simulator |
| 6 | Verify every R# | verifier | all | — | Evidence table |

Rules for the plan:
- **Order**: sign-in before the domains that need a token; types and mocks before screens; screens before connecting them; the bug's failing test first (below). Read-only data before mutations. **A new screen gets its navigation entry in the same step** (or the step before): until it has one it can't be opened, not by tapping and, under native tabs, not even by deep link, so it can't be checked when it's built.
- **Data on mocks only** (no API in this ticket, or the API isn't ready): rn-ui's data layer (types shaped after the spec, mocks, services, hooks) is part of the first screen step; there is no rn-api-connect step.
- **One-time setup belongs to a step.** The first rn-api-connect step includes its Phase 4 infrastructure (client, `env.ts`, generated types) unless the project map shows an API client already, plus the base URL to develop against and the `.env` lines the dev must add. A library with native code, or a switch to a development build (maps, camera, social sign-in), is its own step the dev sees in the plan: a called skill stops rather than add one on its own.
- **Skill per step**: screens, components, theme, navigation → rn-ui. Data, sign-in, client → rn-api-connect. A Maestro flow per R# that a user can see or do → rn-e2e, after the screens exist (the flows are the strongest evidence; R# that aren't visible end to end get a unit test instead). A small change that follows the project's conventions (one navigation entry, a util with its test) → `direct`, done here.
- **Every active R#** appears in at least one step, except those marked `n/a` in Traceability. Every decision and assumption that shapes a step is cited in it (`C3: courier row hidden`).
- **Risks**: say which step could break existing screens (shared components, the theme, navigation) and how its check covers them.
- Good enough when a dev who never saw this conversation could build the ticket from the plan alone.

After the dev accepts: copy the table into the ticket file's Plan section with a Status column (`todo`) and the approval line (who, when, the branch name), set `status: planned`, add a History line, and run `check-ticket.sh`.

Without plan mode (a non-interactive run): write the plan into the ticket file and ask the dev to approve it with one `AskUserQuestion` before anything else.

## Branch and commits

- **Branch**: follow the project's naming (look at `git branch -a`, `CONTRIBUTING.md`, the commit rules in its README). Without one: `feat/<id>-<slug>`, `fix/<id>-<slug>` for a bug. Branch from the up-to-date base branch; ask which one if the project has several (`dev`, `main`).
- **Commits**: one per plan step, in the project's format (commitlint, an issue-key prefix: read `commitlint.config.*` and `git log --oneline`). Include the ticket id where the format has a place for it. Accepting the plan covers these local commits; pushing still needs the dev's yes.
- The git hooks run on every commit. Never `--no-verify`: a failing hook is a failing check, fix it.
- After creating the branch, set `status: in-progress` in the ticket file; the first commit is the ticket file with its plan and that status (`docs(tickets): plan <id>` or the project's equivalent), so the plan is reviewed with the code. Step statuses and Evidence are updated in each step's commit.

## Running the steps

For each step, in order:

1. Set its Status to `doing` with `bash "<skill-dir>/scripts/set-step.sh" <ticket file> <step> doing` (Prettier pads the table, so editing the row by text misses it).
2. Do it: invoke rn-ui or rn-api-connect with the handoff arguments (`handoff.md`), or do a `direct` step here following `CLAUDE.md` and rn-ui's `conventions.md`.
3. Read the skill's report. `blocked`, or something needed outside the step's scope → stop and go to When things change.
4. Run the project's checks (`CLAUDE.md` → Verifying your work). Only new errors count, against the baseline you took before step 1.
5. Set Status to `done` (`set-step.sh … <step> done`), note the evidence the step produced (tests, screenshots) for the Evidence table, and commit the step with its status.

Keep the dev posted in one line per step (step 2 of 5 done: orders screens on mocks).

## Bug tickets: the failing test first

A bug fix is proven by a test that failed before the fix and that the fix wasn't allowed to change. The project's pre-commit hook runs related tests, so a failing test can't be committed alone; it's locked instead, and committed with the fix.

1. **Reproduce it as a test** that fails for the reason in the ticket: a unit test for logic (`utils/`, a mapper, a hook), a React Native Testing Library test for a component or screen, a Maestro flow (rn-e2e) when the bug only shows end to end. Run it and read the failure: it must fail on the expected assertion, not on a typo or a missing mock. Keep that output: it's the "before" half of the evidence.
2. Lock the test files (and any snapshot file they use) so the fix can't weaken them. From the project root:
   ```bash
   bash "<skill-dir>/scripts/lock-tests.sh" lock <test files>
   ```
   It records their content and keeps the lock out of git (`.git/info/exclude`). With rn-starter's guard hook installed, edits to locked files are refused; without it, the check below still catches them.
3. Fix the code. The locked test must pass without being touched; other tests may be added.
4. Prove it: `bash "<skill-dir>/scripts/lock-tests.sh" check` (exit 0: the locked files are unchanged) and the test suite passes. If check reports a change, `lock-tests.sh restore` puts the locked content back; then fix the code instead.
5. Commit the test and the fix together, then `lock-tests.sh unlock`. In the Evidence table the bug's R# cites the test, its failing output before the fix and the passing run after.

When the bug can't be reproduced in a test (native-only behavior, a device-specific crash): say so, record the manual reproduction steps and a screenshot or log as the evidence, and ask the dev whether to go on.

## Verify

After the last step:

1. Every check in `CLAUDE.md` → Verifying your work, on the whole branch.
2. The `code-reviewer` subagent on the branch (`git diff <base>...HEAD`). Fix what it reports and rerun it; commit the fixes. In build mode this one review of the whole branch replaces the project's "review before each commit" rule for the step commits: they're reviewed together here, before anything leaves the machine.
3. The ticket's flows: `run-flows.sh <project> --tags <ticket id>` (rn-e2e), all green.
4. The `verifier` subagent with the ticket file: it opens the app on the main target and checks each R#, reporting pass / fail / not verified with screenshots. A fail goes back to the step that owns that R#.

   A project rn-starter didn't set up may not have these subagents (`.claude/agents/`). Then do the same work yourself, following rn-starter's `assets/claude/code-reviewer.md` and `verifier.md` as the checklists, and say so in the PR.
5. Fill the Evidence table, one row per active R#: the evidence (Maestro flow, test name, screenshot path, the verifier's finding) and a result: `pass`, `fail`, `not verified: <reason>` or `n/a`. Never mark an R# `pass` without evidence you saw. Commit it.

   Where evidence lives: flows and tests are in the repo and anyone can rerun them, so they're the evidence the PR cites first. Screenshots from the verifier and from Maestro runs are in temporary folders; cite them only as supporting detail, or ask the dev once whether to keep a few in `docs/tickets/<id>/evidence/` (small PNGs, committed with the Evidence table). Targets you didn't check (Android, a phone, the real API) go in a `Not verified:` line under the Evidence table; the PR body copies it.
6. `check-ticket.sh` must pass. No R# may be left `fail`; a `not verified` is allowed only with its reason, and the PR lists it.

Other run targets (Android emulator, a phone): run the verifier there too when the project lists them, or list them as not verified.

## Pull request

1. Generate the body from the ticket file:
   ```bash
   bash "<skill-dir>/scripts/ticket-pr.sh" <project-dir>/docs/tickets/<id>.md            # add --type-prefix for feat:/fix: titles
   ```
   Shape the title to the project's format (its commit or PR rules, recent PR titles). It prints a title and a body: the summary and ticket link, each R# with its evidence and result, the decisions and the assumptions, what's not verified, and the plan's steps. Use the project's PR template if it has one (`.github/PULL_REQUEST_TEMPLATE*`, `merge_request_templates/`), filling it from this output.
2. Show the dev the branch, the commits, the remote and the base branch, and ask before pushing. Pushing is visible to the team.
3. On a yes: push the branch (never to a protected branch) and open the PR with the tool the project has (`gh pr create`, `glab mr create`), against the base branch. Without one, give the dev the title and body to paste.
4. Keep `status: in-progress`; don't add a commit just to record the PR link (that would need another push). When the PR is merged, rerun this skill on the ticket: it records the PR in History and sets `status: done` in a small follow-up change the dev commits.

Never merge the PR yourself.

## When things change

- **A step needs something outside its scope** (another screen, a new endpoint, a library): stop, explain it, update the plan with the dev (a new step, or a changed one), and record it in the ticket file's History.
- **A requirement turns out wrong or impossible**: that's a new concern for its owner, not a quiet change. The build pauses on that R# while the others go on.
- **The dev asks for something extra**: a new R# only if the ticket's owner agrees; otherwise a follow-up ticket.
