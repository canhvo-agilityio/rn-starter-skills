---
name: rn-feature
description: Analyzes a ticket for a React Native / Expo app before anyone writes code. It numbers the acceptance criteria (R1, R2…), matches each one to a screen in the design and an endpoint in the API, and writes docs/tickets/<id>.md with the gaps, the concerns (each with who decides) and questions ready to send to the PO, designer or backend team. Use when someone says "analyze this ticket", pastes a user story, a Jira or GitHub issue, asks what a ticket needs, or wants a ticket checked against Figma / screenshots and Swagger before building. Several tickets can be analyzed in parallel. Building from the analysis comes in a later version; to build screens directly use rn-ui, to connect an API rn-api-connect.
---

# Ticket → analysis

Goal: before anyone writes code, the team knows exactly what the ticket asks for, where each part lives in the design and the API, and what's missing or contradictory, written as `docs/tickets/<id>.md`, with the questions ready to send to whoever has to answer them.

**Who owns what.** The ticket and every answer to a question belong to people: the PO, the designer, the backend team, the dev. This skill reads the ticket, never edits it (not in Jira, not in GitHub), and never invents a requirement: something it thinks is missing becomes a question, not an R#. The analysis, the cross-check and the questions are this skill's work, and people review them.

Talk to the dev in their language. Write the ticket file in the ticket's language. This version analyzes and stops: no branch, no code.

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
| Jira | The connected Jira / Atlassian connector, read only. No connector: ask the dev to paste the ticket |
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

Tell the dev briefly: how many requirements, how many fully covered by design and API, the blocking concerns, and the questions per owner (offer to copy each group as a message). Then stop: no branch, no code.

Next steps to mention: once the answers are in, run this skill again on the same ticket to update the file; to build, use rn-ui (screens) and rn-api-connect (data) with the ticket file as their input. Offer to commit the ticket file (`docs(tickets): analyze <id>`); don't commit without a yes.

## Principles

- **The ticket is the people's.** Read it, quote it, ask about it; never rewrite it or add to it.
- **Every R# is testable and traceable.** It maps to a screen, an endpoint and later a test, or it says why not.
- **Gaps are reported, not filled.** A missing state, field or rule is a question with a recommended answer, never a silent assumption.
- **Every concern has an owner.** A problem nobody owns doesn't get answered.
- **Analysis changes nothing** in the app, the ticket or the API.
