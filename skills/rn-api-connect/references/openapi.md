# OpenAPI / Swagger

Swagger and OpenAPI are the same thing: OpenAPI is the specification's name since 2016 (version 3.x), "Swagger" the older name (2.0) and the tool family — Swagger UI is the docs page with "Try it out". Every Swagger UI page is drawn from a spec file (`openapi.json`, `swagger.json`, `/v3/api-docs`); that file is what this skill uses.

## Getting the spec

```bash
bash "<skill-dir>/scripts/fetch-openapi.sh" <input> <project-dir> [--tags pet,store]
```

| Input | What happens |
|---|---|
| Swagger UI page (`https://api.example.com/swagger-ui/index.html`, `/docs`, `/api`) | reads the page's initializer for the spec URL, then tries the usual paths (Spring `/v3/api-docs`, ASP.NET `/swagger/v1/swagger.json`, FastAPI `/openapi.json`, NestJS `/api-json`, …) |
| Spec URL or file, JSON or YAML | used directly; YAML converted with js-yaml |
| Swagger 2.0 | converted to OpenAPI 3.0 with swagger2openapi (`openapi-typescript` only reads 3.x) |

It writes `docs/api/openapi.json` (always OpenAPI 3.x JSON) and `docs/api/source.json` (where it came from). Both are committed: the types are generated from the saved file, so builds never depend on the backend being reachable.

| Exit | Meaning | Do |
|---|---|---|
| 0 | saved, no warnings | continue |
| 2 | unreachable or needs a login (VPN, SSO-protected docs) | relay the ACTION REQUIRED lines; when the dev gives a file path, run again with it |
| 3 | saved, with warnings | show the warnings to the dev in plain words (below), continue |
| 1 | not an OpenAPI document, conversion failed | show the error; ask for another link or the file |

Docs behind a login: ask the dev to open the spec link (the small URL under the title on the Swagger page) in their signed-in browser, save it into `docs/api/`, and give you the path. Never ask for their password.

## Reading the summary

- `servers` — base URLs. Relative ones are resolved against where the spec was served. None → ask the dev.
- `auth` — security schemes (`bearer`, `apiKey in header "X-Api-Key"`, `oauth2`). Endpoints with `auth: true` need a token: until sign-in exists (rn-auth), keep those domains mocked or use a dev token from `.env` (Phase 2 question).
- `errorSchema` — the schema(s) used by 4xx/5xx responses, most used first. It shapes `toApiError` (`client.md`). Empty → the default reader (`message`, `detail`, `title`, `error`).
- `endpoints` — per endpoint: `path_params`, `query` (`?` = optional), `body`, `response` (schema name, `X[]` for arrays, `{ a, b }` for inline objects), `list` (`array` or `Wrapper.field` when the list sits inside an object), `pagination` (`style`: `page` / `offset` / `cursor` / `limit-only` / `unknown`, its `params`, and the wrapper's other fields such as `total`, `next`).
- `listsWithoutPagination` — lists that return everything at once. Fine for short lists (categories); worth raising with the backend team for long ones.

## Warnings, in words for the dev

| Warning | Tell the dev | Effect |
|---|---|---|
| No server URL | "The spec doesn't say where the API runs — which URL should the app use?" | Phase 2 question |
| GET without a response schema | "The API doesn't describe what X returns. I'll type it from a real response; worth asking the backend team to add it." | type the DTO by hand next to the mapper (`mapping.md`), Open point |
| Schemas with no required fields | "Every field in X is marked optional, probably a missing `required` list in the backend. The app will handle missing values; the backend team can fix it in their annotations." | mappers give defaults (`mapping.md`) |
| Bare object responses | "X's response has no fields described." | as a missing schema |
| Missing operationId | usually nothing; openapi-fetch calls by path | names in the plan chosen by you |
| Schema properties that aren't schemas | "The spec has a broken line in X (a description split by a comma or colon) — harmless for the app; worth fixing in their YAML." | ignore the stray key in mappers |

The spec is what the backend says it returns. Before mapping, call each GET you connect once (`curl`, dev or local server only) — with and without its paging parameters — and compare: a list that comes back as a plain array instead of the documented wrapper, a field that's always null. Map what the server actually returns, and list the differences under Open points.

## Types

```bash
<pm> add openapi-fetch
<pm> add -D openapi-typescript
```

```json
// package.json → scripts
"api:types": "openapi-typescript docs/api/openapi.json -o src/types/api.gen.ts"
```

`<pm> run api:types` writes `src/types/api.gen.ts`: `paths` (every endpoint, used by the client) and `components['schemas']` (DTOs, used by mappers). Never edit it by hand. Exclude it from formatting and linting — it's long and its style is the generator's:

- `.prettierignore`: `src/types/api.gen.ts`
- ESLint flat config: add `'src/types/api.gen.ts'` to the `ignores` entry (`{ ignores: ['dist/*', 'src/types/api.gen.ts'] }`).

Use `^` ranges when installing (the package manager does this by default) — pnpm with `save-exact` pins them; that's fine too. Two things to tell the dev before they see them: openapi-typescript declares `typescript ^5` as a peer, so a TypeScript 6 project prints a peer warning (generation works); and the install can rewrite a large part of the lockfile (shared transitive versions move).

## When the backend changes

1. Rerun `fetch-openapi.sh` with the link from `docs/api/source.json` (or replace `docs/api/openapi.json` with the new file).
2. `<pm> run api:types`.
3. `npx tsc --noEmit` — errors point at the mappers and calls that no longer match. Fix them there; screens keep their types.
4. Diff `docs/api/openapi.json` in git to see what changed, and tell the dev about removed or renamed fields.
