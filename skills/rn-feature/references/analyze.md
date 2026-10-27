# Analyzing a ticket

**Contents:** Requirements · Design · API · Cross-check · Questions · Scope · Follow-up runs

## Requirements

Turn each acceptance criterion into one or more R#:

- **One testable behavior per R#.** "User can filter and sort orders" is two: R2 filter, R3 sort. Someone should be able to write one test or one Maestro flow for each.
- **Keep the ticket's wording.** Shorten it, don't reinterpret it. If a criterion is ambiguous ("loads fast", "shows relevant orders"), keep it as written and add a question asking what it means in numbers or rules.
- **Record where it came from:** `AC 2`, `description`, `comment by <name>`. Comments that change a criterion win over the original text; say so in the From column.
- **Details that refine a criterion join it.** When the description adds detail to an acceptance criterion ("filter by status" + "4 tabs: All, Shipping, Delivered, Cancelled"), write one R# with both (`R2 | Filter by status with 4 tabs: … | AC 2 + description`). Only a separately testable behavior the criteria don't cover (20 per page, load more on scroll) gets its own R#.
- **No invented requirements.** States, validations or edge cases the ticket doesn't mention (an empty list, a network error, a max length) are questions with a recommended answer, not R#. The one exception: behavior the app already has everywhere needs no question; mention it under Scope. That's only true once the app has it: the shared error state with retry exists after rn-api-connect has added the client and screen states (`data.apiClient` in the project map). Without it, missing states are a concern like any other.
- **Non-functional criteria** (performance, accessibility, analytics events) are R# like any other when the ticket states them; make them measurable through a question when they aren't.

Bug tickets: steps, expected, actual, platform and version first (template → Bug tickets). R1 is the expected behavior in the reported case; add R# only for related behavior the ticket names. Note whether the bug has been reproduced: not during analysis, unless the dev asks.

## Design

What to collect, per input (read the rn-ui reference for the mechanics):

| Input | Collect |
|---|---|
| Figma (`input-figma.md`) | The frames for this ticket only: ask which ones when the file has many. Use `get_metadata` for structure and one frame image per screen; skip variables and tokens, which matter only when building |
| Screenshots (`input-image.md`) | Which screenshot shows which R#; visible elements and texts; what's cut off or missing |
| Text only (`input-text.md`) | Screens implied by the ticket, matched to the app's existing screens |
| None, existing screens only | The screens in the project map this ticket changes; read their `index.tsx` |

For each R#: the frame and the element that satisfy it, or nothing. Also note what the design shows that no R# asks for (an extra button, a sort menu): it's either missing from the ticket or out of scope, and that's a question for the PO.

States: for each screen with data, does the design show loading, empty, error, partial (one item, a very long name)? Missing states are concerns for design, severity `decide`, unless the ticket's criteria depend on them (then `blocking`).

Navigation: how the user reaches each new screen and goes back. A new screen nobody can reach is a concern.

## API

From `docs/api/openapi.json` or the summary `fetch-openapi.sh` prints:

- **Endpoint per R#**: method and path; for a list, the pagination style and parameters; for a filter or a search, whether the parameter exists and which values it accepts (enums).
- **Fields**: list what each screen displays (from the design) and find each field in the response schema. A field the screen shows that the response doesn't have is a concern (design ↔ API). Watch for type and shape: a price as a string or integer cents, a date without time zone, an image as a path not a URL, a nullable field the design always fills.
- **Writes**: for an R# that creates or changes something, the request body, the validation rules the API states, and what the response returns (does the screen need a second request to refresh?).
- **Auth**: which endpoints need a token. If the app has no sign-in yet, that's a concern for the dev (severity `decide`: keep the domain mocked until sign-in exists, or use a dev token).
- **Errors**: the error schema, and status codes the screens must handle differently (404 on a detail, 409 on a duplicate, 422 with field errors on a form).
- **Spec quality**: missing schemas, `{}` responses, undocumented pagination. These are concerns for backend, never guessed around.

The app's current data: if a domain already exists (`domains` in the project map), say which functions this ticket reuses and which are new. A mock that has fields the API doesn't is a concern too: the screens were built on data that won't exist.

## Cross-check

Go through every R#, then through the design and the API looking for what no R# covers. Each finding is a concern:

| Between | Typical concerns |
|---|---|
| ticket ↔ design | An R# with no frame; a frame element no R# asks for; a missing state; copy in the design that contradicts the ticket |
| design ↔ API | A displayed field the API doesn't return; filter values that differ from the enum; a sort the API can't do; a list the design paginates differently |
| ticket ↔ API | An R# with no endpoint; a rule the ticket states that the API doesn't enforce (or enforces differently) |
| ticket ↔ app | A behavior that conflicts with how the app works today; an existing screen this ticket changes that another open ticket also changes; a new screen with no way to reach it |
| ticket ↔ ticket | Overlap with another open ticket (from the project map's tickets) |

Severity:
- **blocking**: an R# can't be built as written until someone decides (contradiction, missing endpoint, missing enum value).
- **decide**: it can be built, but someone should choose (a missing empty state, an extra field); the question carries a recommended answer the dev can build with if nobody replies.
- **note**: worth knowing, no decision needed (a spec typo, an API quirk you've mapped around).
- **resolved**: answered. Keep the row, and say who decided what and when.

Owner: who can actually answer. `PO` for scope and behavior, `design` for layout and states, `backend` for endpoints and fields, `dev` for technical choices inside the app. A concern can have two owners (`PO, backend`) when both are needed. These four owner names, the severity values and the Between labels stay in English whatever language the file is in, like the headings, so `check-ticket.sh` can read them.

## Questions

One question per decision, grouped by owner, so each group can be pasted to that person as it is:

- Start with the concern number: `**Q3** (C2)`.
- Say what's at stake in one line, then ask one clear thing. Offer the options when there are few.
- End with **Recommended:** your best answer and what you'd build meanwhile. A `decide` question without a recommendation stalls the ticket, so the check rejects it. Keep the label `Recommended:` in English, like the headings.
- No questions about things the code, the spec or the design already answer.

## Scope

What building this ticket touches, as precisely as the analysis allows. It's what Phase 6 compares between tickets and what the build plan starts from:

- Screens: new / changed, by the folder name they have or will have.
- Shared components: new / changed / reused.
- Data: domains and functions, new endpoints the app hasn't called before.
- Files likely touched: paths (globs are fine for new folders), following rn-ui's `conventions.md` (a component used by one screen lives in that screen's `components/`, not `src/components/`). Include shared files explicitly: navigation layouts, the theme, `src/types/api.gen.ts`, `package.json` when a library is needed.
- Overlaps with other open tickets, and the order you'd build them in.
- Out of scope: what the ticket excludes, and what you propose to leave out (that's also a question).
- Work by skill: which parts rn-ui, rn-api-connect and rn-e2e would do.

## Follow-up runs

When `docs/tickets/<id>.md` exists:

1. Read it, then the ticket again (new comments, an edited description) and anything the dev tells you was answered.
2. **R# never change number.** A changed criterion keeps its number with the new wording and a note in From (`AC 2, changed 2026-10-28`). A dropped one keeps its row struck through. A new one takes the next free number.
3. Answered concerns become `resolved` with the decision, who made it and the date; their questions are removed from Questions (the decision stays in the concern). A decision that changes what an R# asks for (a tab dropped, a field hidden) rewords that R# to what will be built, keeping its number, with the reason in From (`AC 2 + description, changed per C1`): the R# must describe what the Evidence proves. Traceability rows whose gap was only that concern become `covered`.
   A `decide` concern the dev chose to build on its recommendation stays `decide` with `assumed:` in its text, and its question stays: the owner can still answer, and the PR lists it.
4. Recheck the traceability rows the answers affect, add concerns the changes create, update Scope.
5. Add a History line, update `status`, run `check-ticket.sh`.

Never resolve a concern on your own judgment: only an answer from its owner, relayed by the dev or written on the ticket, resolves it.
