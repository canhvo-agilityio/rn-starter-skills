# HTTP client, env and errors

**Contents:** Env · Errors · Client · Query client · Tests · Boundary rule

Four small files in `src/lib/`, written once. If the project already has a client (axios instance, a `fetch` wrapper), keep it and add only what's missing from this list: base URL from env, timeout, auth seam, one error type.

## Env

```ts
// src/lib/env.ts
// The only file that reads process.env. Expo inlines EXPO_PUBLIC_* variables at build time,
// so each one must be read by its full name (process.env[name] stays undefined).
const apiUrl = process.env.EXPO_PUBLIC_API_URL ?? '';

export const env = {
  apiUrl,
  // Mocks when asked for, or in development when no API URL is set (fresh clone, tests).
  // Never silently in a release build: there a missing URL shows the error states instead.
  useMocks: process.env.EXPO_PUBLIC_USE_MOCKS === '1' || (!apiUrl && __DEV__),
  apiTimeoutMs: 15_000,
};
```

```bash
# .env.example — committed; documents every variable, no secrets
EXPO_PUBLIC_API_URL=https://api.example.com/v1
# 1 = run on mock data (offline work, demos)
EXPO_PUBLIC_USE_MOCKS=0
```

**`.env` belongs to the developer — never open it**, not to read, list or edit; it can hold secrets of other services. Everything this skill needs comes from:
- the template (`.env.example` / `.env.sample` / `.env.template` — `template` and `templateVars` in the inventory), which you update;
- the code (`varsInCode`), and git for whether `.env` is ignored (`envIgnoredByGit`);
- the developer, for values: the API URL when the spec has no usable server, a dev token.

Then tell the developer what to put in their own `.env`, in their language, e.g.:

> Add these two lines to your `.env` (create it next to `package.json` if you don't have one), then restart `npx expo start`:
> ```
> EXPO_PUBLIC_API_URL=https://dev-api.example.com/v1
> EXPO_PUBLIC_USE_MOCKS=0
> ```

If `.env` isn't ignored by git (`envIgnoredByGit: false`), add `.env` to `.gitignore` — that file is fine to edit. Without a `.env`, the app keeps running on mocks in development (`useMocks` is true when no URL is set and `__DEV__`), so nothing breaks before the dev adds it. A release build without the URL doesn't fall back to mocks: it shows the error states, so a misconfigured build is noticed instead of shipping fake data.

For your own runs (Phase 5–6), turn `.env` loading off and pass the values on the command line: `EXPO_NO_DOTENV=1 EXPO_PUBLIC_API_URL=http://localhost:3000 EXPO_PUBLIC_USE_MOCKS=0 npx expo start`. Without `EXPO_NO_DOTENV=1` Expo would still load `.env` (variables already in the environment win, but the rest get loaded and their names printed in Metro's log). Expo reads env when the dev server starts — restart it to change them.

`EXPO_PUBLIC_` values end up in the app bundle, readable by anyone with the app — never put a secret there (a server API key, a client secret). A dev token for testing belongs only in the developer's own `.env`, never in the template or the code.

If other files read `process.env` (`readsOutsideEnvFile` in the inventory), move those reads into `env.ts`.

**React Native CLI** has no env loading. Without asking for a library:

```ts
// src/lib/env.ts
// Change API_URL_DEV to your machine's backend; react-native-config adds .env files if you need more environments.
const API_URL_DEV = 'http://localhost:3000';
const API_URL_PROD = 'https://api.example.com/v1';
const USE_MOCKS = false;

export const env = {
  apiUrl: __DEV__ ? API_URL_DEV : API_URL_PROD,
  useMocks: USE_MOCKS,
  apiTimeoutMs: 15_000,
};
```

## Errors

```ts
// src/lib/api-error.ts
// One error type for every failed call, so screens and the query client can tell
// "offline" from "not found" from "server broke" without knowing the backend's format.
export class ApiError extends Error {
  constructor(
    // 0 = no response (offline, timeout, DNS)
    readonly status: number,
    message: string,
    readonly code?: string,
    readonly fieldErrors?: Record<string, string>,
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

const text = (value: unknown) => (typeof value === 'string' && value ? value : undefined);

// Reads the backend's error body. Shaped after the spec's error schema (docs/api-plan.md → Errors);
// the fallbacks cover the common frameworks (Spring, ASP.NET problem details, Laravel, NestJS).
export const toApiError = (status: number, body: unknown): ApiError => {
  const b = (typeof body === 'object' && body !== null ? body : {}) as Record<string, unknown>;
  const message =
    text(b.message) ?? text(b.detail) ?? text(b.title) ?? text(b.error) ?? text(body) ?? `Request failed (${status})`;
  const errors = typeof b.errors === 'object' && b.errors !== null ? (b.errors as Record<string, unknown>) : undefined;
  const fieldErrors = errors
    ? Object.fromEntries(
        Object.entries(errors).map(([field, v]) => [field, Array.isArray(v) ? String(v[0]) : String(v)]),
      )
    : undefined;
  return new ApiError(status, message, text(b.code), fieldErrors);
};
```

When the summary's `errorSchema` names a schema, read its fields in the spec and adjust `toApiError` to them first (e.g. `{ error: { code, message } }` nests one level). Record the format in the plan. `fieldErrors` is what a form layer will put under each field.

## Client

```ts
// src/lib/api-client.ts
import createClient, { type Middleware } from 'openapi-fetch';

import type { paths } from '@/types/api.gen';

import { ApiError, toApiError } from './api-error';
import { env } from './env';

type TokenGetter = () => string | null | undefined | Promise<string | null | undefined>;
let getToken: TokenGetter | null = null;

// Sign-in code registers how to read the current access token (references/auth.md adds refresh).
export const setAuthTokenGetter = (getter: TokenGetter | null) => {
  getToken = getter;
};

const auth: Middleware = {
  async onRequest({ request }) {
    const token = await getToken?.();
    if (token) request.headers.set('Authorization', `Bearer ${token}`);
    return request;
  },
};

// fetch has no timeout of its own; without one a dead server leaves a spinner forever.
// This aborts a request whose headers never come; `withTimeout` in unwrap also covers a body that stalls.
const fetchWithTimeout = (request: Request) => {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), env.apiTimeoutMs);
  return fetch(request, { signal: controller.signal }).finally(() => clearTimeout(timer));
};

const withTimeout = <T,>(call: Promise<T>): Promise<T> =>
  new Promise<T>((resolve, reject) => {
    const timer = setTimeout(() => reject(new ApiError(0, 'Request timed out')), env.apiTimeoutMs);
    call.then(
      (value) => { clearTimeout(timer); resolve(value); },
      (error: unknown) => { clearTimeout(timer); reject(error); },
    );
  });

export const api = createClient<paths>({ baseUrl: env.apiUrl, fetch: fetchWithTimeout });
api.use(auth);

type Result<T> = { data?: T; error?: unknown; response: Response };

const settle = async <T>(call: Promise<Result<T>>): Promise<Result<T>> => {
  let result: Result<T>;
  try {
    result = await withTimeout(call);
  } catch (error) {
    throw error instanceof ApiError ? error : new ApiError(0, 'Network request failed');
  }
  if (result.error !== undefined || !result.response.ok) throw toApiError(result.response.status, result.error);
  return result;
};

// Turns openapi-fetch's { data, error } into a value or a thrown ApiError, which is what
// TanStack Query expects from a queryFn. A 2xx with no body where data was expected is the
// server's fault (500), not the user's: it's retried and shown as a server error.
export const unwrap = async <T>(call: Promise<Result<T>>): Promise<T> => {
  const { data, response } = await settle(call);
  if (data === undefined) throw new ApiError(500, `Empty response from ${response.url || 'the server'}`);
  return data;
};

// For calls that answer with no body (DELETE, 204): resolves when the call succeeded.
export const unwrapVoid = async (call: Promise<Result<unknown>>): Promise<void> => {
  await settle(call);
};
```

Calls are typed by path, checked against the spec:

```ts
await unwrap(api.GET('/coffees/{id}', { params: { path: { id } } }));
await unwrap(api.GET('/coffees', { params: { query: { category_id: categoryId, _page: page } } }));
await unwrap(api.POST('/orders', { body: { coffee_id: coffeeId, size, quantity } }));
await unwrapVoid(api.DELETE('/favorites/{id}', { params: { path: { id } } }));
```

Notes (checked on Expo SDK 58, iOS Simulator and Android emulator in Expo Go):
- openapi-fetch is ESM-only and plain JS: Metro bundles it and `jest-expo` runs it with no config change.
- `fetch`, `Request`, `AbortController` are built into React Native.
- API key auth (`apiKey in header "X-Api-Key"` in the summary): set that header in the middleware instead of `Authorization`, from `env` — and only if the key is meant to be public.

## Query client

Don't retry what can't succeed: a 4xx stays a 4xx.

```ts
// src/lib/query-client.ts
import { QueryClient } from '@tanstack/react-query';

import { ApiError } from './api-error';

const isClientError = (error: unknown) => error instanceof ApiError && error.status >= 400 && error.status < 500;

export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 60_000,
      retry: (failureCount, error) => !isClientError(error) && failureCount < 2,
    },
  },
});
```

Keep the project's existing options (`staleTime`, …) and its retry count (`retry: 1` → `failureCount < 1`); change only what is retried.

## Tests

Write these with the client, so the API branch is covered from the start (`src/lib/__tests__/`). `global.fetch` is replaced per test; no server needed.

```ts
// src/lib/__tests__/api-client.test.ts
import { ApiError } from '../api-error';
import { api, unwrap, unwrapVoid } from '../api-client';

// openapi-fetch needs an absolute base URL; tests don't read .env.
jest.mock('../env', () => ({ env: { apiUrl: 'https://api.test', useMocks: false, apiTimeoutMs: 15_000 } }));

const realFetch = globalThis.fetch;
const respond = (status: number, body?: unknown) =>
  jest.fn().mockResolvedValue(new Response(body === undefined ? null : JSON.stringify(body), {
    status, headers: { 'Content-Type': 'application/json' },
  }));

afterEach(() => { globalThis.fetch = realFetch; });

test('returns the body of a 2xx', async () => {
  globalThis.fetch = respond(200, { id: 1 });
  await expect(unwrap(api.GET('/coffees/{id}', { params: { path: { id: 1 } } }))).resolves.toEqual({ id: 1 });
});

test('a 4xx becomes an ApiError with the status and the backend message', async () => {
  globalThis.fetch = respond(404, { message: 'Not found' });
  await expect(unwrap(api.GET('/coffees/{id}', { params: { path: { id: 9 } } }))).rejects.toMatchObject({ status: 404, message: 'Not found' });
});

test('no response is status 0', async () => {
  globalThis.fetch = jest.fn().mockRejectedValue(new TypeError('Network request failed'));
  await expect(unwrap(api.GET('/coffees'))).rejects.toMatchObject({ status: 0 });
});

test('an empty 2xx where data was expected is a 500; unwrapVoid accepts it', async () => {
  globalThis.fetch = respond(200);
  await expect(unwrap(api.GET('/coffees'))).rejects.toBeInstanceOf(ApiError);
  globalThis.fetch = respond(204);
  await expect(unwrapVoid(api.DELETE('/favorites/{id}', { params: { path: { id: 1 } } }))).resolves.toBeUndefined();
});
```

```ts
// src/lib/__tests__/query-client.test.ts
import { ApiError } from '../api-error';
import { queryClient } from '../query-client';

const retry = queryClient.getDefaultOptions().queries?.retry as (count: number, error: unknown) => boolean;

// Matches the template's `failureCount < 2`; with the project's own count, change MAX.
const MAX = 2;

test('a 4xx is never retried; a 5xx or no response is retried up to MAX times', () => {
  expect(retry(0, new ApiError(404, 'x'))).toBe(false);
  expect(retry(0, new ApiError(500, 'x'))).toBe(true);
  expect(retry(MAX - 1, new ApiError(0, 'x'))).toBe(true);
  expect(retry(MAX, new ApiError(503, 'x'))).toBe(false);
});
```

Adapt the paths to the project's spec (each path in a test must exist in `api.gen.ts`). `globalThis.fetch`, not `global.fetch`: TypeScript 6 doesn't know `global` without Node's types. The timeout is a constant in `env.ts`; a test that needs it uses `jest.useFakeTimers()` and a `fetch` that never resolves.

## Boundary rule

DTO types stay in `services/` and `lib/`. With the layered ESLint rules (rn-starter `structure.md`), add one pattern next to the existing ones:

```js
const apiTypesImport = {
  group: ['@/types/api.gen'],
  message: 'API types (DTOs) stay in services/. Use the app types in types/<domain>.ts.',
};
```

Add it to the existing `restrict(...)` calls — don't add a separate block: in flat config a later block's `no-restricted-imports` replaces the earlier one for the same files, and the mock and screen rules would silently stop applying. With rn-starter's layered config, the result (checked on Expo SDK 58) is:

```js
module.exports = defineConfig([
  expoConfig,
  eslintPluginPrettierRecommended,
  { ignores: ['dist/*', 'src/types/api.gen.ts'] },
  // Every .ts/.tsx outside services — including screens' hooks.ts and utils.ts, which no other block covers.
  { files: ['src/**/*.{ts,tsx}'], ignores: ['src/services/**', ...tests], rules: restrict(mocksImport, apiTypesImport) },
  { files: ['src/**/*.tsx'], ignores: tests, rules: restrict(mocksImport, servicesImport, apiTypesImport) },
  { files: ['src/{hooks,stores,utils,types,constants}/**/*.ts'], ignores: tests, rules: restrict(mocksImport, screensImport, apiTypesImport) },
  // lib/ holds the API client, so it may use the generated types. After the blocks above, so it wins for lib/.
  { files: ['src/lib/**/*.ts'], ignores: tests, rules: restrict(mocksImport, screensImport) },
  { files: ['src/{components,theme}/**', 'src/{hooks,stores,lib,utils}/**/*.tsx'], ignores: tests, rules: restrict(mocksImport, servicesImport, screensImport, apiTypesImport) },
  { files: ['src/services/**'], ignores: tests, rules: restrict(screensImport) },
]);
```

In words: `apiTypesImport` joins every block except `services/`; `lib/` leaves the shared-folders glob for a block of its own placed after the general ones. Adapt the same idea to a project's own config.

Run `npx eslint src` after the change, then prove both directions with throwaway files: `import type { components } from '@/types/api.gen'` in a screen's `hooks.ts` must be reported, the same line in `src/lib/` must not. Delete the probes. `check-mocks.sh` reports the same rule (`api-types`) for projects without ESLint rules.
