# Sign-in: session, token storage, refresh, sign-out

**Contents:** What to find in the spec · Storage · The auth service · The session store · Client: token and refresh · Starting the app · Signing out · Social sign-in · Tests · Verify

rn-ui builds the sign-in screens on a mock session (`src/stores/session.ts`, `useSession` with `isSignedIn`, `signIn()`, `signOut()`; the `(auth)` group behind `Stack.Protected`). This file replaces the mock with a real session **behind the same store and fields** (`useSession`, `isSignedIn`), so the `Stack.Protected` guard and the layout don't change. Two handlers do: `signIn` now takes credentials, is async and can fail, and `signOut` is async (Signing out, below). The session signs in against the API, keeps its tokens in the device's secure storage, refreshes them when they expire, and clears everything on sign-out.

Do it as its own domain, `auth`, in the plan, before the domains whose endpoints need a token.

## What to find in the spec

From the `fetch-openapi.sh` summary (`auth`, the endpoints) and the spec itself:

| Need | Look for | If missing |
|---|---|---|
| Scheme | `securitySchemes`: `http bearer` (JWT), `oauth2`, `apiKey` | ask the backend team; don't guess |
| Sign in | `POST /auth/login`, `/sessions`, `/token`, `/oauth/token` taking email/password or a code | Open point |
| Refresh | `POST /auth/refresh`, `/token` with `grant_type=refresh_token` | without it the session ends when the access token expires: say so in the plan |
| Current user | `GET /me`, `/users/me`, `/auth/me` | the user comes from the sign-in response only |
| Sign out | `POST /auth/logout` (revokes the refresh token) | sign-out is local only |
| Social | `POST /auth/apple`, `/auth/google` taking the provider's token | social buttons stay on the mock |

Write down the token lifetimes if the spec or the backend states them; they decide whether refresh is urgent.

## Storage

Tokens go in the platform keychain, never in AsyncStorage, MMKV without encryption, Zustand persist or logs.

- Expo: `npx expo install expo-secure-store` (in Expo Go, no rebuild).
- RN CLI: `expo-secure-store` through `npx install-expo-modules`, or `react-native-keychain`. Both need `cd ios && pod install` and a rebuild.

Store one JSON value under one key, and only the tokens: the user profile can be fetched again. Keep the value small: secure storage isn't meant for large values (check the current `expo-secure-store` docs for its size guidance); if the access token is a large JWT, store only the refresh token and get a fresh access token at start.

## The auth service

`src/services/auth.ts`, like any other domain: DTOs mapped to the app's types, mocks behind the flag. The calls use a second client **without** the token middleware and refresh logic, so a failing refresh can't loop:

```ts
// src/lib/api-client.ts (addition)
export const authApi = createClient<paths>({ baseUrl: env.apiUrl, fetch: fetchWithTimeout });
```

```ts
// src/services/auth.ts
import { authApi, unwrap } from '@/lib/api-client';
import { env } from '@/lib/env';
import { MOCK_SESSION } from '@/mocks/auth';
import type { components } from '@/types/api.gen';
import type { Session } from '@/types/auth';

type LoginResponseDto = components['schemas']['LoginResponse']; // the spec's schema name

export const toSession = (dto: LoginResponseDto): Session => ({
  accessToken: dto.access_token,
  refreshToken: dto.refresh_token,
  user: { id: String(dto.user.id), name: dto.user.full_name, email: dto.user.email },
});

export const signInWithPassword = async (email: string, password: string): Promise<Session> => {
  if (env.useMocks) return MOCK_SESSION;
  return toSession(await unwrap(authApi.POST('/auth/login', { body: { email, password } })));
};

export const refreshSession = async (refreshToken: string): Promise<Session> =>
  toSession(await unwrap(authApi.POST('/auth/refresh', { body: { refresh_token: refreshToken } })));
```

(Field, schema and path names come from the spec, as in `mapping.md`. When the spec has `GET /me`, add `getMe()` the same way: the store calls it after `hydrate` so `user` isn't empty on a cold start.)

## The session store

Same name and the same fields the mock had, so `_layout.tsx` and the screens keep working:

```ts
// src/stores/session.ts
import * as SecureStore from 'expo-secure-store';
import { create } from 'zustand';

import { ApiError } from '@/lib/api-error';
import { setAuthTokenGetter, setTokenRefresher } from '@/lib/api-client';
import { env } from '@/lib/env';
import { MOCK_SESSION } from '@/mocks/auth';
import { queryClient } from '@/lib/query-client';
import { refreshSession, signInWithPassword } from '@/services/auth';
import type { Session, User } from '@/types/auth';

const KEY = 'session';
let tokens: Pick<Session, 'accessToken' | 'refreshToken'> | null = null;

type SessionState = {
  status: 'loading' | 'signedOut' | 'signedIn';
  isSignedIn: boolean;
  user: User | null;
  hydrate: () => Promise<void>;
  signIn: (email: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
};

const save = async (s: Session | null) => {
  tokens = s && { accessToken: s.accessToken, refreshToken: s.refreshToken };
  if (tokens) await SecureStore.setItemAsync(KEY, JSON.stringify(tokens));
  else await SecureStore.deleteItemAsync(KEY);
};

export const useSession = create<SessionState>((set) => ({
  status: 'loading',
  isSignedIn: false,
  user: null,
  hydrate: async () => {
    if (env.useMocks && env.mockSignedIn) { // rn-ui's EXPO_PUBLIC_MOCK_SIGNED_IN, read through env.ts
      tokens = MOCK_SESSION;
      set({ status: 'signedIn', isSignedIn: true, user: MOCK_SESSION.user });
      return;
    }
    try {
      const raw = await SecureStore.getItemAsync(KEY);
      tokens = raw ? JSON.parse(raw) : null;
    } catch {
      tokens = null; // unreadable or corrupt: start signed out rather than hang on the splash
      await SecureStore.deleteItemAsync(KEY).catch(() => {});
    }
    set({ status: tokens ? 'signedIn' : 'signedOut', isSignedIn: !!tokens });
  },
  signIn: async (email, password) => {
    const session = await signInWithPassword(email, password); // throws ApiError: the form shows it
    await save(session);
    set({ status: 'signedIn', isSignedIn: true, user: session.user });
  },
  signOut: async () => {
    await save(null);
    queryClient.clear(); // the next user must not see this user's cached data
    set({ status: 'signedOut', isSignedIn: false, user: null });
  },
}));

setAuthTokenGetter(() => tokens?.accessToken);
setTokenRefresher(async () => {
  if (!tokens) return null;
  try {
    const session = await refreshSession(tokens.refreshToken);
    await save(session);
    return session.accessToken;
  } catch (e) {
    // Only a refusal means the session is over. Offline (status 0) or a server error keeps the user
    // signed in; the request fails now and the next one tries again.
    if (e instanceof ApiError && [400, 401, 403].includes(e.status)) await useSession.getState().signOut();
    return null;
  }
});
```

Add `mockSignedIn: process.env.EXPO_PUBLIC_MOCK_SIGNED_IN === '1'` to `src/lib/env.ts` (`check-mocks.sh` flags `process.env` reads anywhere else). Without Zustand, the same state lives in a React context provider; the token getter and refresher stay module-level so the client can reach them.

## Client: token and refresh

The token middleware from `client.md` stays. Add one retry on `401`: refresh once (several requests failing at the same moment share one refresh), then resend the original request with the new token.

```ts
// src/lib/api-client.ts: add this, and replace client.md's `export const api = createClient(…)` line
// with the one at the end (it now sends through `send`); keep `api.use(auth)`.
type Refresher = () => Promise<string | null>; // the new access token, or null when the session is over
let refresh: Refresher | null = null;
let refreshing: Promise<string | null> | null = null;

export const setTokenRefresher = (refresher: Refresher | null) => {
  refresh = refresher;
};

const refreshOnce = () => {
  refreshing ??= (refresh ? refresh() : Promise.resolve(null)).finally(() => {
    refreshing = null;
  });
  return refreshing;
};

const send = async (request: Request): Promise<Response> => {
  const retry = request.clone(); // a body can be read once; keep a copy for the second try
  const response = await fetchWithTimeout(request);
  if (response.status !== 401 || !refresh) return response;
  const token = await refreshOnce();
  if (!token) return response; // signed out: the guard sends the user to sign-in
  retry.headers.set('Authorization', `Bearer ${token}`);
  return fetchWithTimeout(retry);
};

export const api = createClient<paths>({ baseUrl: env.apiUrl, fetch: send });
api.use(auth);
```

`403` is not a reason to refresh: the user is signed in but not allowed. Show it as an error.

## Starting the app

The session is `loading` until `hydrate()` reads the keychain. Keep the splash screen up until then, or the app flashes the sign-in screen for a signed-in user:

```tsx
// src/app/_layout.tsx
SplashScreen.preventAutoHideAsync();

export default function RootLayout() {
  const [fontsLoaded] = useFonts(FONTS); // the font loading rn-ui's fonts.md already put here
  const status = useSession((s) => s.status);
  useEffect(() => { useSession.getState().hydrate(); }, []);
  useEffect(() => { if (status !== 'loading' && fontsLoaded) SplashScreen.hideAsync(); }, [status, fontsLoaded]);
  if (status === 'loading' || !fontsLoaded) return null;
  // the Stack.Protected tree from rn-ui's navigation.md, unchanged
}
```

Keep rn-ui's `EXPO_PUBLIC_MOCK_SIGNED_IN` working in mock mode, so verification can still start signed in.

## Signing out

`signOut()` clears the keychain and the query cache; the screen that calls it navigates. Await it first: until `isSignedIn` is false, `Stack.Protected` still hides the sign-in route and `router.replace` lands on "Unmatched Route". The handlers from `navigation.md` become:

```ts
const onLogin = async (values: LoginForm) => {
  try {
    await signIn(values.email, values.password);
    router.replace('/');
  } catch (e) {
    showFormError(e); // ApiError: fieldErrors onto the fields, the message above the button (rn-ui conventions.md → Forms)
  }
};
const onLogout = async () => {
  await signOut();
  router.replace('/login');
};
```

When the spec has a logout endpoint, call it first with the refresh token and sign out locally even if it fails: a dead network must not keep the user signed in.

## Social sign-in

rn-ui's `social-sign-in.tsx` returns the provider's token through `onToken(provider, token)`. Here, add `signInWithProvider(provider, token)` to the service (posting it to the backend's endpoint for that provider) and the store, mapped to the same `Session`. The backend verifies the token with the provider; the app never trusts it on its own. Without a backend endpoint for a provider, its button stays on the mock and goes under Open points.

## Tests

- `toSession` with a realistic DTO (`mapping.md`).
- The store: `signIn` saves and flips `isSignedIn`; `signOut` clears the keychain and the query cache (mock `expo-secure-store` with an in-memory object).
- The client: two requests that get `401` at the same time trigger **one** refresh and are both retried with the new token; a failed refresh signs out and returns the `401`. Mock `fetch`.

## Verify

On the main target, against the dev API, with the dev's own test account (they type the password in the app, never in the chat):
1. Sign in → the protected screens load real data.
2. Close the app completely and reopen → still signed in, no sign-in screen flash.
3. Expired access token → the request succeeds after a refresh (ask the backend for a short token lifetime on dev, or wait it out; if neither is possible, list it as not verified).
4. Sign out → back on sign-in; signing in as another user shows none of the first user's data.
5. Wrong password → the form shows the API's message; no crash, nothing stored.
