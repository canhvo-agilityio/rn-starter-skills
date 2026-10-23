# Without an OpenAPI spec

Basic support. Everything after Phase 2 is the same; what changes is where the DTO types come from. Before starting, ask the dev once whether the backend can export OpenAPI — most frameworks do it with a package (springdoc, Swashbuckle, NestJS Swagger, FastAPI built-in), and it saves typing every endpoint by hand.

## Postman collection

A Postman export (`.json`, "Collection v2.1") lists requests by folder, with saved example responses when the team recorded them.

1. Read the collection: per request, method, URL (`{{baseUrl}}/coffees/:id` — the variables are in the collection's or environment's `variable` list), query params, body, and `response[]` examples.
2. Base URL from the `baseUrl`-style variable; ask the dev which environment to use if there are several.
3. DTOs: one TypeScript type per example response in `src/types/api.ts` (hand-written, not `.gen`), named after the resource. A request without an example response: ask the dev to send it once in Postman and save the response, or call it with `curl` yourself if it needs no auth.
4. Mark every hand-written type `// From the Postman example "<name>" — fields not in the example are unknown`. Optional vs required can't be known from examples: treat fields that can plausibly be missing as optional.
5. The client: the same `api-client.ts`, but without typed paths — use a small typed wrapper instead of openapi-fetch:

```ts
// src/lib/api-client.ts (no OpenAPI)
export const request = async <T>(path: string, init: RequestInit & { query?: Record<string, string | number | undefined> } = {}): Promise<T> => {
  const url = new URL(path, env.apiUrl);
  for (const [k, v] of Object.entries(init.query ?? {})) if (v !== undefined) url.searchParams.set(k, String(v));
  const token = await getToken?.();
  const headers = new Headers(init.headers);
  headers.set('Accept', 'application/json');
  if (init.body) headers.set('Content-Type', 'application/json');
  if (token) headers.set('Authorization', `Bearer ${token}`);
  let response: Response;
  try {
    response = await fetchWithTimeout(new Request(url.toString(), { ...init, headers }));
  } catch {
    throw new ApiError(0, 'Network request failed');
  }
  const body = response.status === 204 ? undefined : await response.json().catch(() => undefined);
  if (!response.ok) throw toApiError(response.status, body);
  return body as T;
};
```

Services call `request<CoffeeDto[]>('/coffees', { query: { category_id } })`. Everything else (mappers, flags, hooks, states, verification) is unchanged. In the plan, write `Spec: none — Postman collection <name>, types hand-written in src/types/api.ts`.

## A description of the endpoints

The dev lists endpoints in words or pastes docs ("GET /coffees returns a list of coffees with id, name, price"). Same as Postman, with more questions:

- Write the endpoint list you understood into the plan and get it confirmed before any code.
- For each GET, ask for (or fetch with `curl`) one real response before typing its DTO — a description is rarely exact about field names, nesting and nulls.
- Mark the plan `Spec: none — from the developer's description on <date>` and list every guessed shape under Open points.
