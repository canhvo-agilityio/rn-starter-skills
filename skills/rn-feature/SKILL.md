---
name: rn-feature
description: Takes a ticket for a React Native / Expo app from analysis to a pull request. Analyze - numbers the acceptance criteria (R1, R2…), matches each to a screen in the design and an endpoint in the API, and writes docs/tickets/<id>.md with the gaps, the concerns (each with who decides) and questions ready to send. Build - a plan the dev accepts in plan mode, a branch, each step handed to rn-ui (screens), rn-api-connect (data, sign-in) or rn-e2e (Maestro flows per R#) and committed, bugs fixed test-first, every R# verified in the app, and a PR that maps each R# to its evidence. Use when someone says "analyze this ticket", "build / implement / fix this ticket", pastes a user story or a link to a Jira, Linear or GitHub issue, or wants a ticket checked against Figma / screenshots and Swagger. Several tickets can be analyzed in parallel. For screens or an API without a ticket, use rn-ui or rn-api-connect directly.
---

# Ticket → analysis → pull request

Goal: before anyone writes code, the team knows exactly what the ticket asks for, where each part lives in the design and the API, and what's missing or contradictory, written as `docs/tickets/<id>.md`, with the questions ready to send to whoever has to answer them. Then, when the dev says build, that file becomes an accepted plan, commits and a pull request in which every requirement has its evidence.

**Who owns what.** The ticket and every answer to a question belong to people: the PO, the designer, the backend team, the dev. This skill reads the ticket, never edits it (not in Jira, not in GitHub), and never invents a requirement: something it thinks is missing becomes a question, not an R#. The analysis, the cross-check, the questions, the plan and the code are this skill's work, and people review them: the plan before any code, the pull request before any merge.

Talk to the dev in their language. Write the ticket file in the ticket's language.

**Which mode.** "Analyze", "what does this ticket need", "check it against the design": the analysis (Phases 0–7), then stop. "Build", "implement", "fix", "làm ticket này": the analysis first if there's no ticket file yet, then Building (Phases 8–13).

**Invoked as a slash command.** The text after `/rn-feature` is the dev's request, read like any message. Take three things from it:
- **The ticket**: an id (`SHOP-12`), a GitHub / Jira link, or ticket text pasted after the command.
- **The mode**: "analyze", "build", "fix", "continue", "update with the answers". When the request names a ticket and no mode, the ticket file's status decides (below).
- **Instructions that steer the work**: a scope ("only R1–R3", "the badge first"), an input ("use the Figma frame Order", "the Swagger is at …"), a constraint ("no new library", "from the dev branch"). Record them: scope and inputs in the ticket file (Scope, frontmatter), build instructions in the plan. One that contradicts the ticket or a decision is asked about, never applied silently.

| The dev types | Means |
|---|---|
| `/rn-feature` | Nothing given: ask what to build (below) |
| `/rn-feature SHOP-12` | That ticket: analyze if it has no file yet, else the next step its status calls for |
| `/rn-feature build SHOP-12 chỉ làm R1–R3 trước` | Build, with the plan limited to R1–R3 (the rest stays in the ticket for a later plan) |
| `/rn-feature SHOP-12 PO trả lời: bỏ tab Đã hủy` | A follow-up run: record the answer as the decision on its concern, update the analysis |
| `/rn-feature thêm nút share ở màn Detail` | No ticket: the request is the ticket (below) |

**Nothing given.** Tickets live on the team's board (Jira, Linear, Asana, Trello, GitHub…), not in this repo, so on a first run `docs/tickets/` is empty. Ask in plain text, in the dev's language, what they want to build: "What feature do you want to build? Paste the ticket's link (Jira, Asana, Trello, GitHub…), paste its text, or describe the feature in your own words: what the user can do, on which screen, and anything you already know about the design or the API." Then read the answer like a request typed after the command: a link or a key → `references/ticket-sources.md`; text or a description → the ticket (below). Only when `docs/tickets/` already holds tickets that aren't `done` (look before asking: `ls docs/tickets/*.md` and their `status:`), add one line offering to continue them, each with what comes next ("SHOP-12 · in-progress: continue at step 5"). Never pick a ticket for the dev.

**A request with no ticket** (a change described in the dev's words): that description is the ticket. Propose a short id in the team's style (the tracker key if they give one, else a kebab-case slug like `detail-share`), set `source: dev request` in the frontmatter, number the requirements from the dev's words, and show them to the dev before going further: they own what the change is, and a one-line request usually leaves out states and edge cases that become questions. Then continue in the mode the request asks for (analyze when it doesn't say).

What comes next for a ticket follows its status: `questions-open` → update the analysis with the answers you have (follow-up run); `ready` → build; `planned` / `in-progress` → continue the build from the first plan step that isn't `done`. A finished ticket has no file: it was removed in the branch's last commit (Phase 13). When the dev names a ticket with no file, check git before analyzing it as new (`git log --all --oneline -- docs/tickets/<id>.md`): a removal means it's done, so say so and offer to restore it (`git show <commit>^:docs/tickets/<id>.md`) only for review changes or a reopened ticket.

## Phase 0: Understand the project

```bash
source "<skill-dir>/../rn-starter/scripts/env.sh"; bash "<skill-dir>/scripts/project-map.sh" <project-dir>
```

It prints JSON: framework, navigation, structure, every route with its URL path and the screen it renders, the shared components, the data domains (services with their functions and whether they're still on mocks), signs of sign-in (`auth`: an auth route group, a guard, token storage, a token getter on the API client; all empty means the app has no sign-in yet, which matters for any endpoint that needs a token), and the docs already there: `docs/design-spec.md`, `docs/api-plan.md`, `docs/api/openapi.json`, and each `docs/tickets/*.md` with its status and the files it touches.

- **Not an RN project** (exit 1): say so and stop.
- **`docs/tickets/<id>.md` exists for this ticket**: a follow-up run (answers came back, the ticket changed). Read it and follow `references/analyze.md` → Follow-up runs: R# numbers never change.
- **Other tickets in progress** (`status: planned` or `in-progress`): note the screens and files they touch; overlaps go in the Scope section.

## Phase 1: Get the ticket

Read `references/ticket-sources.md`. In short:

| Source | How |
|---|---|
| GitHub issue (URL, `owner/repo#12`, `#12`) | `bash "<skill-dir>/scripts/fetch-ticket.sh" <ref>` |
| A ticket on a board (Jira, Linear, Azure DevOps, Trello, ClickUp, Notion, a GitHub Projects draft) | In order: the board's connector if one is connected; else open the link the dev gave in **Claude in Chrome** (their own browser, already signed in) or the built-in browser (the dev signs in) and read the page; else ask the dev to paste it. Read only |
| A requirement in the dev's words, typed or said | The words are the ticket: short id, `source: dev request`, requirements confirmed with the dev (`references/ticket-sources.md`) |
| Pasted text, a file | Save it in your scratchpad, then `bash "<skill-dir>/scripts/fetch-ticket.sh" --text-file <file> --id <id>` |

The script returns the title, the body, the comments (clarifications often live there), the acceptance criteria it can spot, and the links it finds: Figma, images, Swagger / OpenAPI. Read the body and the comments yourself; the extraction is a starting point.

Ask for anything the ticket doesn't give, in one `AskUserQuestion` round: the ticket id if pasted text has none, the design (*Figma link* / *Screenshots* / *No design: follow the app's existing screens*), the API (*Swagger link* / *Already in docs/api/openapi.json* / *No API change* / *Not available yet*). Inputs the ticket names (links, or a path such as `docs/api/openapi.json`) are used as they are, without asking. "Follow the existing screens" when the app only has the template's demo screens means there's no style to follow: that's a concern for design.

Several tickets at once: Phase 6.

## Phase 2: Number the requirements

Turn the acceptance criteria into R1…Rn, following `references/analyze.md` → Requirements: one testable behavior per R#, the ticket's own wording, compound criteria split, where each one came from. A bug ticket has its steps, expected and actual recorded first; R# are the expected behaviors.

When the ticket has no acceptance criteria, don't write them: list the behaviors the ticket's text clearly states as R# marked "from the description", and put proposed criteria under Questions for the PO.

## Phase 3: Match the design

Read the design with rn-ui's input references (`../rn-ui/references/input-figma.md`: frugal with the Figma MCP, browser fallback; `input-image.md`; `input-text.md`). Here you need structure, not tokens: which frames or screenshots show which R#, which elements, which states (loading, empty, error), and where navigation goes.

For each screen: does the app already have it (`routes` and `screens` in the project map)? New screen, changed screen, or a component inside an existing one.

## Phase 4: Match the API

Get the spec and its summary with rn-api-connect's script. With a link and no saved spec, it saves `docs/api/openapi.json` in the project:

```bash
bash "<skill-dir>/../rn-api-connect/scripts/fetch-openapi.sh" <swagger-url | spec-url | file> <project-dir> --tags <tags this ticket needs>
```

When the project already has `docs/api/openapi.json`, get the summary without touching it: pass the saved file and a folder from `mktemp -d` as the project (`fetch-openapi.sh <project-dir>/docs/api/openapi.json "$(mktemp -d)"`). Only refresh the saved spec when the dev says the API changed. Exit 3 means the summary came with spec-quality warnings: they're concerns for backend.

For each R# that shows or changes data: the endpoint, its parameters (filters, pagination), the fields the screen needs against the fields the response has, auth, and the error format. Read `references/analyze.md` → API. Work from the spec; call an endpoint only on a dev server the dev names, GET only, never production.

## Phase 5: Cross-check and write

Follow `references/analyze.md` → Cross-check: every R# against design, API and the app as it is today. Each problem becomes a concern **C#** with what it's between (ticket ↔ design, design ↔ API, ticket ↔ app…), a severity (*blocking* / *decide* / *note*) and an owner (PO, design, backend, dev). Each concern that needs an answer becomes a question **Q#** for its owner, written to be pasted as it is, with your recommended answer.

Write `docs/tickets/<id>.md` from `references/ticket-template.md`, then check it:

```bash
bash "<skill-dir>/scripts/check-ticket.sh" <project-dir>/docs/tickets/<id>.md
```

Exit 3 lists contract problems (an R# missing from the traceability table, a gap pointing at a concern that doesn't exist, a blocking concern with no question, `status: ready` while something blocks). Fix them and rerun until it exits 0.

Status: `questions-open` while any concern is blocking, else `ready`.

## Phase 6: Several tickets

Analyze each ticket in its own subagent (the Agent tool, one per ticket, in parallel), each running Phases 1–5 for its ticket against the same project map. Analysis only reads the project and writes its own ticket file, so the runs don't collide.

Then compare the Scope sections: tickets that touch the same screen, shared component, domain or file can't be built in parallel. Add an Overlaps line to each affected ticket file and tell the dev which order you'd build them in and why.

## Phase 7: Hand-off

Tell the dev briefly: how many requirements, how many fully covered by design and API, the blocking concerns, and the questions per owner (offer to copy each group as a message). In analyze mode, stop here: no branch, no code.

Next steps to mention: once the answers are in, run this skill again on the same ticket to update the file; then ask it to build the ticket. Don't commit the analysis on `main` or another protected branch: when the ticket is built next, it goes into the plan's first commit on the feature branch; if the team reviews analyses on their own, offer a `docs/<id>-analysis` branch (`docs(tickets): analyze <id>`). Nothing is committed without a yes.

## Building

Read `references/build.md` before starting, and `references/handoff.md` for calling the other skills.

**Phase 8: Ready to build?** `check-ticket.sh` passes and no concern is `blocking`. Open `decide` concerns: the dev chooses to build with the recommended answers (recorded as assumptions) or to wait. No uncommitted changes besides the ticket file (it's committed with the plan, on the feature branch), no other ticket in progress on the same files, and Claude Code running from the project folder so its hooks and subagents load.

**Phase 9: Plan in plan mode.** Enter plan mode, read the code the ticket touches, and present a plan of small steps: what, which skill (rn-ui, rn-api-connect, rn-e2e, or direct), which R#, which files, how each is checked. Every active R# is in a step; sign-in before the domains that need it; for a bug, the failing test is step 1. The dev accepting the plan is the approval. Then write it into the ticket file's Plan section, set `status: planned`.

**Phase 10: Branch.** The project's branch naming, from the up-to-date base branch. Set `status: in-progress`; the first commit is the ticket file with its plan.

**Phase 11: Steps.** For each step: call rn-ui, rn-api-connect or rn-e2e with the handoff arguments (or do a direct step), read its report, run the project's checks, commit in the project's format, mark the step done. A step that needs something outside its scope stops the build until the dev updates the plan.

Bug tickets: reproduce the bug as a test that fails for the reported reason, lock it (`scripts/lock-tests.sh lock <files>`, from the project root), fix the code without touching it, prove it (`lock-tests.sh check`, tests green), commit the test with the fix, unlock.

**Phase 12: Verify.** The checks from `CLAUDE.md`, the `code-reviewer` subagent on the branch, the ticket's Maestro flows (rn-e2e's `run-flows.sh --tags <id>`), then the `verifier` subagent with the ticket file, R# by R#. Fill the Evidence table: every active R# with its evidence and `pass`, `fail`, `not verified: <reason>` or `n/a`. Fails go back to their step; nothing ships `fail`. `check-ticket.sh` passes. Without the two subagents in the project, do their checklists yourself and say so.

**Phase 13: Close the ticket file, then the pull request.** Set `status: done`, `check-ticket.sh` passes, commit. `scripts/ticket-pr.sh` turns the ticket file into a title and body (R# → evidence, decisions, assumptions, what's not verified); save it in your scratchpad. Then remove `docs/tickets/<id>.md` (and `docs/tickets/<id>/` if it has evidence) in the branch's last commit: the ticket file is working notes, the board keeps the requirement, the PR body keeps the evidence, and git history keeps the file. Show the dev the branch, commits, remote and base, and push and open the PR only on a yes. Never merge it.

## Principles

- **The ticket is the people's.** Read it, quote it, ask about it; never rewrite it or add to it.
- **Every R# is testable and traceable.** It maps to a screen, an endpoint and later a test, or it says why not.
- **Gaps are reported, not filled.** A missing state, field or rule is a question with a recommended answer, never a silent assumption.
- **Every concern has an owner.** A problem nobody owns doesn't get answered.
- **Analysis changes nothing** in the app, the ticket or the API.
- **No code before an accepted plan, no merge by the agent.** The plan and the pull request are where people decide.
- **Evidence, not claims.** An R# is done when a test, a flow or a screenshot you saw shows it; anything unchecked says so.
