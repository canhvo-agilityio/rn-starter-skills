# HTTP client, env and errors

**Contents:** Env · Errors · Client · Query client · Boundary rule

Four small files in `src/lib/`, written once. If the project already has a client (axios instance, a `fetch` wrapper), keep it and add only what's missing from this list: base URL from env, timeout, auth seam, one error type.

## Env

```ts
// src/lib/env.ts
// The only file that reads process.env. Expo inlines EXPO_PUBLIC_* variables at build time,
// so each one must be read by its full name (process.env[name] stays undefined).
const apiUrl = process.env.EXPO_PUBLIC_API_URL ?? '';

export const env = {
  apiUrl,
  // Mocks when asked for, and whenever no API URL is set (fresh clone, tests).
  useMocks: process.env.EXPO_PUBLIC_USE_MOCKS === '1' || !apiUrl,
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

If `.env` isn't ignored by git (`envIgnoredByGit: false`), add `.env` to `.gitignore` — that file is fine to edit. Without a `.env`, the app keeps running on mocks (`useMocks` is true when no URL is set), so nothing breaks before the dev adds it.

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
const fetchWithTimeout = (request: Request) => {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), env.apiTimeoutMs);
  return fetch(request, { signal: controller.signal }).finally(() => clearTimeout(timer));
};

export const api = createClient<paths>({ baseUrl: env.apiUrl, fetch: fetchWithTimeout });
api.use(auth);

type Result<T> = { data?: T; error?: unknown; response: Response };

// Turns openapi-fetch's { data, error } into a value or a thrown ApiError, which is what
// TanStack Query expects from a queryFn.
export const unwrap = async <T>(call: Promise<Result<T>>): Promise<T> => {
  let result: Result<T>;
  try {
    result = await call;
  } catch {
    throw new ApiError(0, 'Network request failed');
  }
  const { data, error, response } = result;
  if (error !== undefined || !response.ok) throw toApiError(response.status, error);
  return data as T;
};
```

Calls are typed by path, checked against the spec:

```ts
await unwrap(api.GET('/coffees/{id}', { params: { path: { id } } }));
await unwrap(api.GET('/coffees', { params: { query: { category_id: categoryId, _page: page } } }));
await unwrap(api.POST('/orders', { body: { coffee_id: coffeeId, size, quantity } }));
await unwrap(api.DELETE('/favorites/{id}', { params: { path: { id } } }));
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
