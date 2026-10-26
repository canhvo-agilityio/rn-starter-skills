# docs/tickets/<id>.md template

`check-ticket.sh` checks this shape, so keep the headings, the table columns and the frontmatter keys. Write the content in the ticket's language; the headings, column names, frontmatter values, severity values, owner names (`PO`, `design`, `backend`, `dev`), Between labels and the `Recommended:` label stay in English so the script can read them. The example is one feature; shape yours after the ticket in front of you, not after it.

```markdown
---
ticket: PROJ-412
source: https://company.atlassian.net/browse/PROJ-412
type: feature            # feature | bug
status: questions-open   # questions-open | ready | planned | in-progress | done
analyzed: 2026-10-26
design: figma https://www.figma.com/design/… frames "Orders", "Order detail"   # or: screenshots docs/design/… | none
api: docs/api/openapi.json (from https://api.dev.example.com/swagger)            # or: none
---

# PROJ-412: Order history

## Summary

Two or three sentences in your own words: what the user can do after this ticket, and why. Link to the ticket.

## Requirements

| # | Requirement | From |
|---|---|---|
| R1 | A signed-in user sees their orders, newest first | AC 1 |
| R2 | The user can filter orders by status | AC 2 |
| R3 | Tapping an order opens its detail | AC 3 |
| R4 | The list loads 20 orders at a time | description |

## Traceability

| # | Design | In the app | API | Status |
|---|---|---|---|---|
| R1 | frame "Orders": list | new screen `orders` | `GET /orders` | covered |
| R2 | frame "Orders": 4 status tabs | new screen `orders` | `GET /orders?status=` | gap C1 |
| R3 | frame "Order detail" | new screen `order-detail` | `GET /orders/{id}` | gap C2 |
| R4 | — | new screen `orders` | `page`, `limit` | covered |

## Concerns

| # | Concern | Between | Severity | Owner | Affects |
|---|---|---|---|---|---|
| C1 | The design has 4 status tabs; the API's `status` enum has 3 (no `cancelled`) | design ↔ API | blocking | PO, backend | R2 |
| C2 | The detail frame shows the courier's name; `GET /orders/{id}` doesn't return it | design ↔ API | decide | backend | R3 |
| C3 | No frame for an empty order list | ticket ↔ design | decide | design | R1 |

## Questions

### PO
- **Q1** (C1) Should "Cancelled" orders be filterable? Recommended: yes, if backend adds `cancelled` to the `status` enum; otherwise drop the tab for this ticket.

### Backend
- **Q2** (C1) Can `GET /orders` accept `status=cancelled`? Recommended: add `cancelled` to the `OrderStatus` enum; the app maps it to the "Cancelled" tab.
- **Q3** (C2) Can `GET /orders/{id}` return the courier's name? Recommended: add `courier.name`; until then the detail screen hides the row.

### Design
- **Q4** (C3) What does the list show when the user has no orders? Recommended: the app's standard empty state with a "Start shopping" button.

## Scope

- Screens: new `orders`, new `order-detail`; changed `profile` (adds an "Orders" row).
- Shared components: `order-card` (new), `status-badge` (new), `empty-state` (existing).
- Data: domain `orders` (new): `getOrders(page, status)`, `getOrder(id)`.
- Files likely touched: `src/app/orders/*`, `src/screens/orders/*`, `src/screens/order-detail/*`, `src/screens/profile/index.tsx`, `src/services/orders.ts`, `src/hooks/use-orders.ts`, `src/types/orders.ts`.
- Overlaps: none.
- Out of scope: reordering, order tracking map (ticket says so).
- Work by skill: rn-ui (R1–R3 screens, R4 load more), rn-api-connect (domain `orders`), rn-e2e (R1–R4 flows).

## Plan

_Added when the ticket is built, after the questions are answered._

## Evidence

_Filled when the ticket is built: each R# with the test, flow or screenshot that proves it._

## History

- 2026-10-26: analyzed (design: Figma 2 frames; API: openapi.json from dev). 4 questions open.
```

## Rules the script checks

- Frontmatter has `ticket`, `type` (`feature` / `bug`) and `status` (`questions-open` / `ready` / `planned` / `in-progress` / `done`).
- R# in Requirements are unique and numbered without gaps from R1. A dropped requirement keeps its row with the number struck through: `| ~~R4~~ | dropped: … (PO, 2026-10-28) | AC 4 |`.
- Every active R# has a row in Traceability. Status is `covered`, `gap C<n>[, C<n>…]`, or `n/a: <reason>`.
- Every concern a gap points to exists. Every concern has a severity (`blocking` / `decide` / `note` / `resolved`), an owner among `PO`, `design`, `backend`, `dev` (one or more, comma-separated), and Affects naming R# that exist.
- Every `blocking` or `decide` concern is asked in at least one question: a `**Q<n>**` line with `(C<n>)` in it. A question about a `decide` concern has a `Recommended:` answer.
- `status: ready` (or later) with a concern still `blocking` is an error.

## Bug tickets

Put this above Requirements, and make each R# an expected behavior:

```markdown
## Bug

- Steps: 1. Open Orders. 2. Pull to refresh twice quickly.
- Expected: the list refreshes once.
- Actual: every order shows twice.
- Seen on: iOS 26, app 1.4.0 (from the ticket). Reproduced: not yet.
```
