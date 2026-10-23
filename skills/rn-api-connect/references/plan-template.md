# docs/api-plan.md template

The contract for this skill's changes, approved by the dev before any code changes, and the record later runs (and later sign-in or forms work) read. Keep it short; update it in place on later runs.

```markdown
# API plan — <App name>

Spec: docs/api/openapi.json — from <source URL or file>, OpenAPI <version> (<converted from Swagger 2.0>), "<title>" <api version>, saved <date>
Base URL: <EXPO_PUBLIC_API_URL for development> (<team dev server / local>) — the developer sets it in their own .env
Auth: <bearer token on N endpoints — not connected until sign-in exists / none>
Errors: <schema name and shape, e.g. { code, message, errors: { field: [msg] } } / default reader>
Client: openapi-fetch + openapi-typescript (`<pm> run api:types`)
Mocks: EXPO_PUBLIC_USE_MOCKS=1

## Domains

| Domain | Function | Endpoint | Notes | Status |
|---|---|---|---|---|
| coffees | getCategories | GET /categories | id number → string | connected |
| coffees | getCoffees(categoryId) | GET /coffees?category_id= | paginated: _page/_per_page, next from `next`; price_cents → price | verified (iOS, Android) |
| coffees | getCoffee(id) | GET /coffees/{id} | | verified (iOS, Android) |
| favorites | getFavorites / setFavorite | GET /favorites, POST /favorites, DELETE /favorites/{id} | needs auth → stays mocked | mock |
| delivery | getDeliveryStatus | — | no endpoint in the spec | mock |

## Mapping notes

- Coffee: `subtitle` → variant; `image_url` (absolute) → image; `rating` optional in the spec → 0.
- Order: status `IN_PROGRESS | DONE | CANCELLED` → `ongoing | completed | cancelled`.

## Mutations

| Mutation | Endpoint | Invalidates |
|---|---|---|
| place order | POST /orders | ['orders'], ['order-quote'] |

## Open points

- GET /profile has no response schema in the spec — typed from a real response; ask the backend team to add it.
- Every field in `Order` is optional in the spec (no `required` list).
- Delivery status has no endpoint yet — mocked.
```

Status values: `mock` (stays on mocks, with the reason in Notes) → `planned` → `connected` (code switched, type-checked) → `verified (<targets>)` (looked at on the running app against the API).

Statuses are per function, one row each: a domain can be partly connected when the API covers only some of it (order history connected, the order quote mocked because there's no endpoint). That's fine as long as every function is either fully on the API (with the mock behind the flag) or fully on mocks — never a function that mixes both. `check-mocks.sh` lists the functions still on mocks; they all need a `mock` row with a reason.
