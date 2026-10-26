# Calling rn-ui and rn-api-connect from rn-feature

When rn-feature builds a ticket, it hands each part to the skill that knows how to do it: screens to rn-ui, data to rn-api-connect. The handoff is one contract, the same for both, so neither skill re-asks what the dev already approved and rn-feature gets back what it needs to fill the Evidence table.

## Calling

Invoke the skill (the Skill tool) with arguments that start with `Called by rn-feature` and carry four things:

```text
Called by rn-feature for ticket SHOP-27 (docs/tickets/SHOP-27.md, plan approved, step 2 of 5).
Scope: R1, R5, R6. Screens orders (new), order-detail (new); shared component order-card (new).
Inputs: design none (follow src/theme; decided in C9/Q10); types from docs/api/openapi.json schemas OrderSummary, OrderDetail.
Decisions: C2 → pending orders show only under "All" with a badge (PO, 2026-10-28). C3 → hide the courier row until the API has it.
```

- **Ticket and step**: the ticket file and which plan step this is.
- **Scope**: the R# this step delivers and the screens, components, domains or endpoints it may touch, from the plan.
- **Inputs**: the design (Figma frames, screenshot paths, or none) and the API spec, as the ticket file records them.
- **Decisions**: the resolved concerns that change what to build, so the skill doesn't build the ticket's original wording.

## What the called skill does differently

| | Called by rn-feature | Called by the dev |
|---|---|---|
| Questions | Only what the ticket file and the decisions don't answer, and only if it blocks the step. Everything else uses the recorded decision or the skill's recommended default, noted in the report | Its usual question rounds |
| Approval | **Skipped**: the dev approved the plan in plan mode. Still write or update the skill's own document (`docs/design-spec.md`, `docs/api-plan.md`), tagging what this step added with the ticket id | The skill's spec / plan approval |
| Scope | Stays inside the step's scope. Something outside it that the step needs (another screen, a new endpoint, a library with native code, a development build) → stop and report it; rn-feature updates the plan with the dev | Whatever the dev asked |
| Verification | Its own checks on the main target, including its boundary checks (rn-ui: the structure self-check; rn-api-connect: mock mode still works and `check-mocks.sh`), not every target: rn-feature runs the verifier at the end | Every run target |
| Commit | **None**: rn-feature commits per step | Offers to commit |
| Hand-off | The report below, instead of its usual hand-off message | Its usual hand-off |

The skill's principles don't change: tokens not literals, screens get data through hooks, mocks stay behind the flag, `.env` stays closed.

## Report back

End with this block, so rn-feature can update the plan and the Evidence table without rereading the work:

```text
Step 2 of 5 for SHOP-27: done | partly done | blocked
Files: src/screens/orders/index.tsx (new), src/components/order-card.tsx (new), src/app/orders/index.tsx (new), …
R1: done (screen renders 3 mock orders; screenshot <dir>/r1.png)
R5: done (tabs All / Shipping / Delivered; Cancelled hidden per C1)
R6: partly (courier row hidden per C3)
Checks: tsc pass · eslint pass · jest 4 passed
Deviations from the plan: none | what changed and why
Out of scope, needed: none | what the step needs that the plan doesn't cover
Assumed: what was decided by default because nobody answered (with the question number)
```

`done` means every R# in scope is done or explicitly partly done for a recorded decision. `blocked` stops the build until rn-feature and the dev decide.
