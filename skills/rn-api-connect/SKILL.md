---
name: rn-api-connect
description: Switches a React Native / Expo app from mock data to its real backend, from the backend's Swagger / OpenAPI spec (a Postman collection or a description also works): generated types, a typed client, services switched one domain at a time, pagination, mutations, loading / error / empty states, mocks kept behind a flag. Use when someone wants to connect the app to an API or backend, replace mocks with real data, "hook up the API", or generate an API client or types from Swagger/OpenAPI.
---

# Mock data → real API

Goal: the screens built on mocks run on the real backend, **without the screens noticing** — except that loading, error and empty states now actually happen. Data flows screen → `hooks/` → `services/` → API; the API's shapes (DTOs) are mapped to the app's own types in the service, so a backend change shows up as a type error in a mapper, not a crash on a user's phone.

Talk to the dev in their language. Keep them in the loop at the two points that matter: approving the plan (Phase 3) and confirming the result (Phase 7).

**Never open `.env`, `.env.local` or any other env file except the committed templates** (`.env.example`, `.env.sample`, `.env.template`) — not to read values, not to list names, not to edit. They hold the developer's secrets. What you need from them (the API URL, a dev token) you ask the developer for; what the app needs in them you give the developer as lines to add.

Out of scope: sign-in, token storage and refresh (leave the seam — `client.md` → Auth), forms, websockets, offline sync. Say so if asked, and note it under Open points.

## Phase 0 — Understand the project

```bash
source "<skill-dir>/../rn-starter/scripts/env.sh"; bash "<skill-dir>/scripts/api-inventory.sh" <project-dir>
```

It prints JSON: framework, package manager, layout, query library, env setup (the template file and its variables, the variables the code reads, whether git ignores `.env` — never `.env` itself), an existing API client, and every **domain** (service file) with its functions, hooks, the screens using them, its mocks, and its `source` (`mock` / `connected` / `api` / `mixed`).

- **Exit 3, no service seam** (no `src/services/`, data fetched inside screens): this skill needs one. Offer to add the layered data layer first (rn-design-import `references/conventions.md` → Data seams) as a separate step the dev approves, or stop.
- **`docs/api-plan.md` exists** → a follow-up run (a new domain, a refreshed spec). Read it and continue from its statuses.
- **An API client already exists** (`apiClient` set, `axios` installed): follow it — reuse its base URL, auth and error handling, and adapt the patterns in `references/client.md` to it instead of adding a second client.
- **`queryLibrary: none`** → recommend TanStack Query (cache, retry, invalidation; the hooks pattern assumes it). If the dev declines, keep plain hooks (`references/data-hooks.md` → Without TanStack Query).
- **`mixed` domains**: services that call the API and return mocks with no flag — read them before touching anything.

Record baselines now, so later checks count only what you introduce: `npx tsc --noEmit`, `npx eslint src` (not the project's `lint` script: `eslint .` also lints files Expo generates on its first start, so its result changes for reasons unrelated to you) and `npx jest` (if set up) — save each output in your scratchpad directory, or a folder from `mktemp -d` — never a fixed `/tmp` path, which another project's run can overwrite.

## Phase 1 — Get the API description

Ask once if the dev hasn't said: "Where is the API described?" → *Swagger / OpenAPI link (Recommended)* / *An OpenAPI or Swagger file* / *Postman collection* / *I'll describe the endpoints*.

For Swagger / OpenAPI (the main path), and read `references/openapi.md`:

```bash
bash "<skill-dir>/scripts/fetch-openapi.sh" <swagger-ui-url | spec-url | file> <project-dir>
```

It finds the spec behind a Swagger UI page, converts YAML and Swagger 2.0, saves `docs/api/openapi.json`, and prints a summary (servers, auth, error schema, endpoints by tag with list and pagination detection, warnings). Exit 2 = needs the dev (VPN, login): relay its ACTION REQUIRED lines and wait. Exit 3 = saved, with quality warnings to show the dev. Large APIs: pass `--tags` for the tags this app uses.

Postman or a description: `references/other-inputs.md`.

## Phase 2 — Match services to endpoints

For each domain from Phase 0, and each function in its service, find the endpoint that serves it. Read `references/mapping.md`.

Call each GET endpoint you plan to connect once (`curl`, on a dev or local server — never production data), with and without its paging parameters: specs drift from what the server returns (a list documented as a page wrapper that comes back as a plain array without `_page`, a field that's always null). Map what the server returns; list each difference from the spec under Open points.

Also search screens and screen hooks for **mock ids written as literals** (`useState('cappuccino')`, `router.push('/coffee/1')`): the API's ids differ, so those screens open empty. `grep -rn "'<mock id>'" src/screens src/app` for the ids in `mocks/`. Write down per function: endpoint, request parameters, the DTO → app-type differences (id types, null vs undefined, dates, money, image URLs vs bundled assets, enums, renamed or nested fields), and whether it's a paginated list or a mutation.

Then ask what you can't infer, in one `AskUserQuestion` round (max 4), each with your best guess as the recommended option. Typical gaps:
- the base URL when the spec has no server, or several (dev / staging / prod — pick the one to develop against);
- a service function with no endpoint, or two candidate endpoints;
- a field the screens need that the API doesn't return (keep it mocked / derive it / drop it from the UI);
- endpoints that need auth while sign-in doesn't exist yet: *keep this domain mocked (Recommended)* / *use a dev token the dev puts in `.env`*;
- a mock id hard-coded in a screen: what the screen should use instead (*the first item from the API (Recommended)* / a value the dev gives).

Pagination: show the list endpoints with the detected style and parameters (`page` + `limit`, `cursor`, …) and let the dev correct them in the plan — an unrecognized parameter name silently loads only the first page.

## Phase 3 — Plan → dev approval

Write `docs/api-plan.md` using `references/plan-template.md`: base URL, auth, error format, and per domain the endpoints, the mapping notes, pagination, mutations with what they invalidate, and the status (`mock` → `planned` → `connected` → `verified`). Domains without an endpoint stay `mock` with a reason.

Show the dev a short summary (domains to connect, what stays mocked, base URL, open questions) and ask: "Connect the API following this plan?" → *Yes (Recommended)* / *Change something*. Don't change code before a yes.

## Phase 4 — Infrastructure (once)

Read `references/client.md`. In order:

1. Install `openapi-fetch` (dependency) and `openapi-typescript` (dev dependency) with the project's package manager; Expo: `npx expo install` is not needed for these (plain JS). Expect, and tell the dev: a peer warning when the project is on a newer TypeScript than openapi-typescript declares (it works), and a large lockfile diff.
2. `api:types` script in `package.json`, run it → `src/types/api.gen.ts`; exclude the file from ESLint and Prettier.
3. `src/lib/env.ts` and `.env.example` with `EXPO_PUBLIC_API_URL` and `EXPO_PUBLIC_USE_MOCKS`. If git doesn't ignore `.env` (`envIgnoredByGit: false`), add `.env` to `.gitignore`. Give the dev the lines for their own `.env` (`references/client.md` → Env) — don't create or edit it.
4. `src/lib/api-error.ts`, `src/lib/api-client.ts`, the query client's retry rule.
5. The boundary rule: only `services/` and `lib/` import `types/api.gen` (ESLint, when the project has the boundary rules).

Run `npx tsc --noEmit` and fix what you introduced.

## Phase 5 — Connect one domain at a time

Per domain, in the plan's order (read-only domains first, mutations after):

1. **Mappers** in the service (`to<Model>(dto)`), exported, each with a test from a realistic DTO (`references/mapping.md`).
2. **Service** — each function: `if (env.useMocks) return <the existing mock code>;` then the client call, unwrapped and mapped. Signatures don't change.
3. **Hooks** — only where the shape changes: paginated lists, mutations and their invalidation, mutations that read before they write, queries that wait for another (`references/data-hooks.md`).
4. **Screen states** — on every screen that uses this domain's hooks (`usedBy` in the inventory): loading, error with retry, empty; load-more on paginated lists (`references/screen-states.md`). Nothing else in the screens changes.
5. `npx tsc --noEmit`, `npx jest`, `npx eslint src` — only new errors count. Update the functions' statuses in the plan to `connected`.

Run the app on the main target after each domain and open its screens, so a wrong mapping shows up while it's the only change. Start the dev server with `.env` loading turned off and the API values on the command line: `EXPO_NO_DOTENV=1 EXPO_PUBLIC_API_URL=<url> EXPO_PUBLIC_USE_MOCKS=0 npx expo start`. Expo then never loads the developer's `.env` (not even into Metro's log, which otherwise lists its variable names), and the app gets exactly the values you passed. Pass any other `EXPO_PUBLIC_*` variable the app needs the same way — names from the template, values from the developer.

## Phase 6 — Verify

Follow `references/verify.md` on every run target (`runTargets` in `.rn-starter.json`, or ask):

1. **Main target**: every affected screen opened against the API and screenshotted — real data, not mocks (check a value only the API has); each mutation done once and its effect seen on the other screens; the error state with the API unreachable; the empty state where the API can return an empty list.
2. **Mock mode**: restart the dev server with `EXPO_NO_DOTENV=1 EXPO_PUBLIC_USE_MOCKS=1` on the command line; the app runs fully on mocks.
3. **Each other target**: open the affected screens once (Android emulators reach the host differently — `verify.md`).
4. **Phone via Expo Go**: ask the dev to open the main screens.
5. `bash "<skill-dir>/scripts/check-mocks.sh" <project-dir>` — exit 3 lists boundary violations to fix; `still-mocked` lines go in the hand-off.

A target or screen you didn't check is listed as not verified — never implied as done.

## Phase 7 — Hand-off

1. Update `docs/api-plan.md`: statuses, what stays mocked and why, open points (missing endpoints, fields, spec problems to raise with the backend team).
2. Tell the dev briefly: domains connected and verified (per target), what's still mocked, how to switch to mocks (`EXPO_PUBLIC_USE_MOCKS=1`), how to refresh types when the backend changes (rerun this skill with the link, or replace `docs/api/openapi.json` → `<pm> run api:types` → `tsc` lists the mappers to fix), and what's left for sign-in.
3. If the project is a git repo, offer to commit (`feat(api): connect <domains> to the API`, body wrapped at 72 columns — commitlint rejects long lines). Follow the project's own rules before committing: its `CLAUDE.md` (e.g. run its `code-reviewer` subagent first — on a change this size it finds real bugs) and its hooks. Don't commit without a yes.

## Principles

- **Screens don't change** except for loading / error / empty states and load-more. If a screen seems to need more, the mapper is missing something.
- **App types stay the app's.** DTOs live in `types/api.gen.ts` and never leave `services/` and `lib/`.
- **Generated, never hand-edited.** `api.gen.ts` comes from the spec; fixes go to the spec or the mapper.
- **One domain at a time**, verified before the next. A domain may stay partly mocked when the API lacks an endpoint — per function, never a function that mixes both.
- **Mocks stay** behind the flag: offline work, demos, tests, and domains the backend hasn't built.
- **`.env` stays closed.** Templates, code and the developer's answers are enough.
- **Spec problems are reported, not papered over.** A missing schema or a wrong type goes to Open points for the backend team.
