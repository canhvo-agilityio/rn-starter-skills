# Matching and mapping

The screens were built against `types/<domain>.ts`, shaped for the UI. The API has its own shapes. The service is where the two meet: it calls the endpoint, maps each DTO to the app type, and the rest of the app never sees the DTO.

## Matching functions to endpoints

For each service function (`functions` in the inventory), look for the endpoint by meaning, not by name: `getCoffees(categoryId)` ↔ `GET /products?category=` is a match even though nothing is spelled the same. Use tags, paths, response schemas and the screens that use the hook (`usedBy`) to decide.

| Situation | Do |
|---|---|
| One clear endpoint | match it |
| Several candidates (`GET /coffees` and `GET /menu/items`) | ask (Phase 2), recommending the one whose response covers the most fields the screens use |
| No endpoint | keep the function on mocks; plan status `mock` with "no endpoint in the spec" |
| The function filters or computes on the client (`getCoffees(categoryId)` filtering a list) | prefer the endpoint's query parameter; otherwise fetch and filter in the service, and note it |
| The endpoint returns more than one function needs (an order with its lines) | map once, reuse the mapper |
| A function the mocks merged from two domains (favorites = ids + coffees) | call both endpoints in the service, or the one that embeds the other; keep the signature (Join by id, below) |

## DTO types

```ts
import type { components } from '@/types/api.gen';

type CoffeeDto = components['schemas']['Coffee'];
```

An endpoint with an inline response schema (no name): `paths['/coffees/{id}']['get']['responses'][200]['content']['application/json']`.

A GET with no response schema in the spec (a warning from `fetch-openapi.sh`): call the endpoint once (`curl`), type the DTO by hand in the service next to its mapper, and add an Open point for the backend team. openapi-typescript types such a response as `never`, so cast once at the call:

```ts
// Not in the spec — typed from a real response on 2026-10-22. Ask the backend team for a schema.
interface ProfileDto { full_name: string; city?: string | null; avatar_url?: string | null }

const dto = (await unwrap(api.GET('/profile'))) as unknown as ProfileDto;
```

## Mapper rules

```ts
// src/services/coffees.ts
// apiUrl: image_url is a path on the API server ("/images/coffee-1.jpg").
export const toCoffee = (dto: CoffeeDto, apiUrl: string): Coffee => ({
  id: String(dto.id),
  name: dto.name,
  variant: dto.subtitle ?? '',
  categoryId: String(dto.category_id),
  price: dto.price_cents / 100,
  rating: dto.rating ?? 0,
  reviewCount: dto.review_count ?? 0,
  description: dto.description ?? '',
  image: absoluteUrl(dto.image_url, apiUrl),
});
```

| Difference | Rule |
|---|---|
| Field names (`snake_case`, renamed, nested `dto.pricing.amount`) | map to the app name; never rename the app type to match the API |
| Ids (`number` in the API, `string` in the app) | `String(dto.id)`; convert back when sending (`Number(id)`) |
| Optional / nullable in the DTO, required in the app type | a sensible default (`?? ''`, `?? 0`, `?? []`) when a missing value is normal; if a missing value would make the screen wrong (no price), throw in the mapper so the error state shows — and add an Open point if the spec marks it optional by mistake |
| Money | find out the unit (cents as integer, decimal as string `"4.53"`, currency field); the app keeps whatever the screens and `utils/pricing.ts` use, converted here |
| Dates | ISO strings stay strings unless the app type is `Date`; parse once in the mapper, never in screens |
| Images | the API's URL (`dto.image_url`) where mocks used `require(...)`; the app's image type must accept both (`number \| string`, or `ImageSourcePropType` with `{ uri }`) — widen it in `types/` if needed, that's a type change screens don't see |
| Enums (`"IN_PROGRESS"` vs app `'ongoing'`) | a lookup object in the mapper; an unknown value maps to a safe default and is logged in `__DEV__` |
| Relative URLs (`/media/1.jpg`) | `absoluteUrl(path, apiUrl)` from `src/lib/api-url.ts` (below), with `apiUrl` passed in as a mapper argument — React Native's `URL` is not a reliable way to resolve relative paths |
| A field the screens need and the API doesn't have | Phase 2 question: keep it from the mock / derive it / drop it from the UI (the last one changes a screen — only with the dev's yes) |

Mappers are pure functions: no calls, no `env`, no `Date.now()` — so they're trivial to test. A mapper that needs configuration (the API origin) takes it as an argument, and the service passes `env.apiUrl`.

```ts
// src/lib/api-url.ts
// The API may serve images as paths on its own host. Pure, so mappers stay testable.
export const absoluteUrl = (pathOrUrl: string, origin: string) =>
  /^https?:\/\//.test(pathOrUrl)
    ? pathOrUrl
    : `${origin.replace(/\/+$/, '')}/${pathOrUrl.replace(/^\/+/, '')}`;
```

Always call mappers with an arrow, `data.map((dto) => toCoffee(dto, env.apiUrl))`, never `data.map(toCoffee)`: `map` passes the index as the second argument, and a mapper that takes one silently receives a number.

## Service

Signatures stay the same, so hooks and screens don't change. The mock branch stays as it was:

```ts
// src/services/coffees.ts
import { api, unwrap } from '@/lib/api-client';
import { absoluteUrl } from '@/lib/api-url';
import { env } from '@/lib/env';
import { mockCoffees } from '@/mocks/coffees';
import type { components } from '@/types/api.gen';
import type { Coffee } from '@/types/coffee';

type CoffeeDto = components['schemas']['Coffee'];

export const toCoffee = (dto: CoffeeDto, apiUrl: string): Coffee => ({ /* … */ });

export const getCoffees = async (categoryId?: string): Promise<Coffee[]> => {
  if (env.useMocks) return categoryId ? mockCoffees.filter((c) => c.categoryId === categoryId) : mockCoffees;
  const data = await unwrap(api.GET('/coffees', { params: { query: { category_id: categoryId } } }));
  return data.map((dto) => toCoffee(dto, env.apiUrl));
};

export const getCoffee = async (id: string): Promise<Coffee> => {
  if (env.useMocks) {
    const coffee = mockCoffees.find((c) => c.id === id);
    if (!coffee) throw new Error(`Coffee ${id} not found`);
    return coffee;
  }
  return toCoffee(await unwrap(api.GET('/coffees/{id}', { params: { path: { id: Number(id) } } })), env.apiUrl);
};
```

**Join by id.** When the API returns references (favorites as `{ id, coffee_id }`) and the app type is the full object, the service fetches what it joins:
- Prefer one call: an endpoint that embeds the object (`?_embed=coffee`, `/favorites/expanded`), or the list endpoint filtered by ids (`/coffees?id=1&id=9`), if the spec has one.
- Otherwise one GET per id with `Promise.all`, and say in the plan that it's N+1 calls — fine for a handful of favorites, worth an endpoint from the backend team for long lists.
- A referenced item that's gone (404) is skipped, not a failure of the whole list:
  ```ts
  const coffees = await Promise.all(ids.map((id) => getCoffee(id).catch((e: unknown) => {
    if (e instanceof ApiError && e.status === 404) return null;
    throw e;
  })));
  return coffees.filter((c): c is Coffee => c !== null);
  ```

**Mutable mock state** (a `let` in the service — `mutableState: true` in the inventory, e.g. favorites): keep the variable for the mock branch; the API branch calls the endpoint and returns what the API returns, never touching the variable.

Remove the `// TODO: replace with API call` comments of the functions you connected; keep them on functions that stay mocked, with the reason.

## Tests

One test file per connected service, `services/__tests__/<domain>.test.ts`:

```ts
import { toCoffee } from '../coffees';

const dto = {
  id: 7, name: 'Caffe Mocha', subtitle: 'Deep Foam', category_id: 2, price_cents: 453,
  rating: 4.8, review_count: 230, description: 'A mocha…', image_url: 'https://cdn.example.com/7.jpg',
};

test('maps a coffee from the API', () => {
  expect(toCoffee(dto, 'https://api.test')).toEqual({
    id: '7', name: 'Caffe Mocha', variant: 'Deep Foam', categoryId: '2', price: 4.53,
    rating: 4.8, reviewCount: 230, description: 'A mocha…', image: 'https://cdn.example.com/7.jpg',
  });
});

test('fills defaults for optional fields', () => {
  expect(toCoffee({ ...dto, subtitle: null, rating: null }, 'https://api.test').variant).toBe('');
});

test('makes relative image paths absolute', () => {
  expect(toCoffee({ ...dto, image_url: '/images/7.jpg' }, 'https://api.test/').image).toBe('https://api.test/images/7.jpg');
});
```

Type the fixture as the DTO (`const dto: CoffeeDto = …`) so a backend change breaks the test at compile time too. Take values from a real response when you have one. Cover every rule from the table that the mapper applies (defaults, units, enums, URLs).

To test a service function end to end without a server, stub `globalThis.fetch` (`jest.fn(async () => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } }))`) — and set `EXPO_PUBLIC_API_URL` for that test file, since without it `env.useMocks` is true. Because `env` is read when the module loads, set it before importing: `process.env.EXPO_PUBLIC_API_URL = 'https://api.test'` at the top, then `const { getCoffee } = require('../coffees')`, or `jest.mock('@/lib/env', () => ({ env: { apiUrl: 'https://api.test', useMocks: false, apiTimeoutMs: 1000 } }))`.
