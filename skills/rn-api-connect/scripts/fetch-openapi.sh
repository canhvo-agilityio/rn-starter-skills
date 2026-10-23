#!/usr/bin/env bash
# Get a project's OpenAPI spec, save it as OpenAPI 3.x JSON, and summarize it.
#
# Usage: fetch-openapi.sh <swagger-ui-url | spec-url | file> <project-dir> [--tags tag1,tag2]
#
# - A Swagger UI page is followed to the spec behind it (its initializer config, then the usual
#   paths: /v3/api-docs, /swagger.json, /openapi.json, /swagger/v1/swagger.json, …).
# - YAML is accepted; Swagger 2.0 is converted to OpenAPI 3.0 (swagger2openapi).
# - Writes <project>/docs/api/openapi.json and <project>/docs/api/source.json (where it came from).
# - Prints a JSON summary: servers, auth schemes, error schema, every endpoint with its
#   parameters, request/response schema, list + pagination detection, and quality warnings.
#   --tags limits the endpoint list (the saved spec is always complete).
#
# Exit codes: 0 done · 1 error (not an OpenAPI document, bad arguments)
#             2 waiting on the developer (needs login/VPN, or unreachable — prints ACTION REQUIRED)
#             3 done, but the spec has quality problems the developer should see

set -euo pipefail
[ $# -ge 2 ] || { echo "usage: fetch-openapi.sh <url|file> <project-dir> [--tags a,b]" >&2; exit 1; }
input="$1"; project="$(cd "$2" && pwd)"; shift 2
tags=""
while [ $# -gt 0 ]; do
  case "$1" in
    --tags) tags="${2:-}"; shift 2 ;;
    *) echo "unknown option $1" >&2; exit 1 ;;
  esac
done
command -v node >/dev/null 2>&1 || { echo "node not found — source rn-starter/scripts/env.sh first" >&2; exit 1; }
if [ -f "$input" ]; then input="$(cd "$(dirname "$input")" && pwd)/$(basename "$input")"; fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Step 1 — find and download the document (node: fetch + Swagger UI discovery).
set +e
node - "$input" "$work" <<'EOF'
const fs = require('fs');
const path = require('path');
const [input, work] = process.argv.slice(2);

const looksLikeSpec = (text) => /["']?(openapi|swagger)["']?\s*:\s*["']?[23]\./.test(text.slice(0, 4000));
const isHtml = (text) => /<(!doctype html|html[\s>])/i.test(text.slice(0, 3000));

const done = (text, from) => {
  fs.writeFileSync(path.join(work, 'raw'), text);
  fs.writeFileSync(path.join(work, 'from'), from);
  process.exit(0);
};
const action = (lines) => {
  console.log('ACTION REQUIRED');
  for (const l of lines) console.log(l);
  process.exit(2);
};

if (!/^https?:\/\//.test(input)) {
  if (!fs.existsSync(input)) { console.error(`no such file: ${input}`); process.exit(1); }
  const text = fs.readFileSync(input, 'utf8');
  if (!looksLikeSpec(text)) { console.error(`${input} is not an OpenAPI/Swagger document`); process.exit(1); }
  done(text, input);
}

const get = async (url) => {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), 15000);
  try {
    const res = await fetch(url, { signal: ctrl.signal, headers: { accept: 'application/json, application/yaml, text/yaml, text/html;q=0.5, */*;q=0.1' } });
    return { status: res.status, text: res.ok ? await res.text() : '' };
  } catch (e) {
    return { status: 0, text: '', error: e.cause?.code || e.name || String(e) };
  } finally { clearTimeout(t); }
};

(async () => {
  const first = await get(input);
  if (first.status === 0) {
    action([
      `Could not reach ${input} (${first.error}).`,
      'If the API is on a VPN or an internal network, connect and run this again,',
      'or download the spec file (the link under the title on the Swagger page, e.g. /v3/api-docs)',
      'and pass its path instead of the URL.',
    ]);
  }
  if (first.status === 401 || first.status === 403) {
    action([
      `${input} needs a login (HTTP ${first.status}).`,
      'Open it in your browser while signed in, download the spec (the link under the title,',
      'e.g. /v3/api-docs or swagger.json), save it in the project (docs/api/), and pass that path.',
    ]);
  }
  if (first.text && looksLikeSpec(first.text)) done(first.text, input);

  // A Swagger UI page (or a 404 on a guessed URL): look for the spec behind it.
  const base = new URL(input);
  const pageDir = base.pathname.replace(/\/(index\.html)?$/, '').replace(/\/[^/]*\.html$/, '');
  const candidates = [];
  const add = (u) => { try { const abs = new URL(u, base).href; if (!candidates.includes(abs)) candidates.push(abs); } catch {} };

  const html = isHtml(first.text) ? first.text : '';
  if (base.searchParams.get('url')) add(base.searchParams.get('url')); // swagger-ui/?url=<spec>
  const fromConfig = (text) => {
    for (const m of text.matchAll(/\b(?:url|configUrl)\s*:\s*["'`]([^"'`]+)["'`]/g)) add(m[1]);
    for (const m of text.matchAll(/"url"\s*:\s*"([^"]+)"/g)) add(m[1]);
    // Spec URLs held in variables or lists: any .json/.yaml/api-docs URL, this host first.
    const urls = [...text.matchAll(/(https?:\/\/[^\s"'`,;=]+|\.{0,2}\/[\w./-]+)(?:\.json|\.ya?ml|api-docs)\b/g)].map((m) => m[0]);
    for (const u of urls.sort((a, b) => Number(!a.includes(base.host)) - Number(!b.includes(base.host)))) add(u);
  };
  if (html) {
    fromConfig(html);
    for (const m of html.matchAll(/<script[^>]+src=["']([^"']*(?:initializer|init)[^"']*\.js)["']/gi)) {
      const js = await get(new URL(m[1], base).href);
      if (js.text) fromConfig(js.text);
    }
  }
  const prefixes = [...new Set([pageDir.replace(/\/(swagger-ui|swagger|docs|api-docs|redoc)$/, ''), pageDir, ''])];
  const known = ['/v3/api-docs', '/v2/api-docs', '/swagger.json', '/openapi.json', '/swagger/v1/swagger.json',
    '/api-docs', '/api-json', '/openapi.yaml', '/swagger.yaml', '/api/openapi.json', '/docs/openapi.json', '/swagger/doc.json'];
  for (const p of prefixes) for (const k of known) add(`${p}${k}`);
  if (base.pathname.length > 1) add(`${base.pathname.replace(/\/$/, '')}-json`); // NestJS: docs at /api → spec at /api-json

  const tried = [];
  for (const url of candidates) {
    if (url === input) continue;
    const res = await get(url);
    tried.push(`${res.status || res.error} ${url}`);
    if (!res.text) continue;
    if (looksLikeSpec(res.text)) done(res.text, url);
    // springdoc swagger-config: { urls: [{ url, name }] } or { url }
    try {
      const cfg = JSON.parse(res.text);
      const next = cfg.url || cfg.urls?.[0]?.url;
      if (next) {
        const spec = await get(new URL(next, url).href);
        if (spec.text && looksLikeSpec(spec.text)) done(spec.text, new URL(next, url).href);
      }
    } catch {}
  }
  const needsLogin = tried.some((t) => /^(401|403) /.test(t));
  action([
    `No OpenAPI spec found behind ${input}${needsLogin ? ' (some URLs need a login)' : ''}.`,
    'On the Swagger page, the spec link is the small URL under the API title (e.g. /v3/api-docs).',
    'Pass that URL, or download the file into the project (docs/api/) and pass its path.',
    'Tried:',
    ...tried.slice(0, 20).map((t) => `  ${t}`),
  ]);
})();
EOF
status=$?
set -e
[ $status -eq 0 ] || exit $status

# Step 2 — YAML → JSON, Swagger 2.0 → OpenAPI 3.0.
raw="$work/raw"
if ! node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$raw" 2>/dev/null; then
  echo "converting YAML to JSON (js-yaml)…" >&2
  npx --yes js-yaml@4.1.0 "$raw" > "$work/spec.json" || { echo "could not parse the spec as JSON or YAML" >&2; exit 1; }
else
  cp "$raw" "$work/spec.json"
fi
original_version="$(node -e 'const s=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));console.log(s.openapi||("swagger "+s.swagger))' "$work/spec.json")"
case "$original_version" in
  3.*) ;;
  "swagger 2.0")
    echo "converting Swagger 2.0 to OpenAPI 3.0 (swagger2openapi)…" >&2
    npx --yes swagger2openapi@7.0.8 --patch --warnOnly -o "$work/spec3.json" "$work/spec.json" >&2 \
      || { echo "Swagger 2.0 conversion failed" >&2; exit 1; }
    mv "$work/spec3.json" "$work/spec.json" ;;
  *) echo "unsupported spec version: $original_version" >&2; exit 1 ;;
esac

# Step 3 — save and summarize.
mkdir -p "$project/docs/api"
node - "$work/spec.json" "$project" "$(cat "$work/from")" "$original_version" "$tags" <<'EOF'
const fs = require('fs');
const path = require('path');
const [specFile, project, from, originalVersion, tagFilter] = process.argv.slice(2);
const spec = JSON.parse(fs.readFileSync(specFile, 'utf8'));

fs.writeFileSync(path.join(project, 'docs/api/openapi.json'), JSON.stringify(spec, null, 2) + '\n');
fs.writeFileSync(path.join(project, 'docs/api/source.json'),
  JSON.stringify({ source: from, originalVersion }, null, 2) + '\n');

const resolve = (node, seen = new Set()) => {
  if (!node || typeof node !== 'object' || !node.$ref) return node;
  if (seen.has(node.$ref) || !node.$ref.startsWith('#/')) return {};
  seen.add(node.$ref);
  const target = node.$ref.slice(2).split('/').reduce((o, k) => o?.[k.replace(/~1/g, '/').replace(/~0/g, '~')], spec);
  return resolve(target, seen);
};
const refName = (node) => node?.$ref ? node.$ref.split('/').pop() : null;
const jsonContent = (content) => {
  if (!content) return null;
  const key = Object.keys(content).find((k) => /json/.test(k)) ?? Object.keys(content)[0];
  return key ? { type: key, schema: content[key].schema } : null;
};
const describe = (schema) => {
  if (!schema) return null;
  const name = refName(schema);
  const s = resolve(schema);
  if (s.type === 'array' || s.items) return `${describe(s.items) ?? 'unknown'}[]`;
  if (name) return name;
  if (s.allOf || s.oneOf || s.anyOf) return (s.allOf || s.oneOf || s.anyOf).map(describe).join(s.allOf ? ' & ' : ' | ');
  if (s.type === 'object' || s.properties) {
    const props = Object.keys(s.properties ?? {});
    return props.length ? `{ ${props.slice(0, 8).join(', ')}${props.length > 8 ? ', …' : ''} }` : 'object (no properties)';
  }
  return s.type ?? 'unknown';
};

const LIST_KEYS = ['items', 'data', 'results', 'content', 'records', 'list', 'rows', 'edges', 'nodes'];
const PAGE = /^_?(page|pageNumber|pageNo|pageIndex|p)$/i;
const SIZE = /^_?(limit|size|pageSize|perPage|per_page|_per_page|take|count|page_size)$/i;
const OFFSET = /^_?(offset|skip|start)$/i;
const CURSOR = /^(cursor|after|before|next|nextToken|pageToken|page_token|continuation|startingAfter|starting_after)$/i;

const listShape = (schema) => {
  const s = resolve(schema);
  if (!s) return null;
  if (s.type === 'array' || s.items) return { wrapper: null, field: null };
  const props = s.properties ?? {};
  for (const k of LIST_KEYS) {
    const p = resolve(props[k]);
    if (p && (p.type === 'array' || p.items)) {
      // Type next to each name: "items:integer" is a total count, not the list.
      const meta = Object.keys(props).filter((x) => x !== k).map((x) => `${x}:${resolve(props[x])?.type ?? 'object'}`);
      return { wrapper: refName(schema) ?? 'inline', field: k, meta };
    }
  }
  return null;
};

const warnings = [];
const noOpId = [];
const noSchema = [];
const freeForm = new Set();
const errorSchemas = {};
const endpoints = [];
const globalSecurity = (spec.security ?? []).length > 0;

for (const [p, item] of Object.entries(spec.paths ?? {})) {
  const shared = item.parameters ?? [];
  for (const method of ['get', 'post', 'put', 'patch', 'delete']) {
    const op = item[method];
    if (!op) continue;
    const params = [...shared, ...(op.parameters ?? [])].map(resolve);
    const byIn = (where) => params.filter((x) => x.in === where).map((x) => `${x.name}${x.required ? '' : '?'}`);
    const query = params.filter((x) => x.in === 'query').map((x) => x.name);
    const okCode = Object.keys(op.responses ?? {}).find((c) => /^2/.test(c));
    const ok = okCode ? resolve(op.responses[okCode]) : null;
    const okContent = jsonContent(ok?.content);
    if (!op.operationId) noOpId.push(`${method.toUpperCase()} ${p}`);
    if (method === 'get' && okCode !== '204' && !okContent?.schema) noSchema.push(`${method.toUpperCase()} ${p}`);
    const responseSchema = resolve(okContent?.schema);
    if (responseSchema && (responseSchema.type === 'object' || !responseSchema.type) && !responseSchema.properties
      && !responseSchema.items && !responseSchema.allOf && !responseSchema.oneOf && !responseSchema.anyOf
      && !responseSchema.additionalProperties && !refName(okContent.schema)) freeForm.add(`${method.toUpperCase()} ${p}`);
    for (const [code, r] of Object.entries(op.responses ?? {})) {
      if (!/^(4|5|default)/.test(code)) continue;
      const c = jsonContent(resolve(r)?.content);
      const name = refName(c?.schema) ?? (c?.schema ? describe(c.schema) : null);
      if (name) errorSchemas[name] = (errorSchemas[name] ?? 0) + 1;
    }
    const list = method === 'get' && okContent?.schema ? listShape(okContent.schema) : null;
    let pagination = null;
    if (list) {
      const page = query.filter((q) => PAGE.test(q));
      const size = query.filter((q) => SIZE.test(q));
      const offset = query.filter((q) => OFFSET.test(q));
      const cursor = query.filter((q) => CURSOR.test(q));
      const style = cursor.length ? 'cursor' : page.length ? 'page' : offset.length ? 'offset' : size.length ? 'limit-only' : null;
      if (style) pagination = { style, params: [...cursor, ...page, ...offset, ...size], wrapperMeta: list.meta ?? [] };
      else if (list.meta?.some((m) => /next|total|page|cursor|hasMore|has_more/i.test(m.split(':')[0])))
        pagination = { style: 'unknown', params: [], wrapperMeta: list.meta };
    }
    const security = op.security ?? (globalSecurity ? spec.security : []);
    const ep = {
      method: method.toUpperCase(),
      path: p,
      operationId: op.operationId ?? null,
      tag: op.tags?.[0] ?? '(untagged)',
      summary: op.summary ?? null,
      path_params: byIn('path'),
      query: byIn('query'),
      body: describe(jsonContent(resolve(op.requestBody)?.content)?.schema),
      response: okContent ? describe(okContent.schema) : okCode === '204' ? '(no content)' : null,
      list: list ? (list.field ? `${list.wrapper}.${list.field}` : 'array') : null,
      pagination,
      auth: security.some((s) => Object.keys(s).length > 0),
    };
    for (const k of Object.keys(ep)) if (ep[k] === null || (Array.isArray(ep[k]) && !ep[k].length)) delete ep[k];
    endpoints.push(ep);
  }
}

const schemas = spec.components?.schemas ?? {};
// A property whose value isn't a schema is almost always a YAML slip: an unquoted ", " or ": " in
// a flow-style description splits it into a new key ({ description: Path, e.g. /x } → key "e.g. /x").
const broken = [];
for (const [n, s] of Object.entries(schemas)) {
  for (const [prop, v] of Object.entries(s.properties ?? {})) {
    if (v === null || typeof v !== 'object') broken.push(`${n}.${JSON.stringify(prop)}`);
    else for (const [k, x] of Object.entries(v)) if (x === null) broken.push(`${n}.${prop} key ${JSON.stringify(k)}`);
  }
}
const allOptional = Object.entries(schemas)
  .filter(([, s]) => s.properties && Object.keys(s.properties).length > 1 && !(s.required?.length))
  .map(([n]) => n);

if (!spec.servers?.length || spec.servers.every((s) => !s.url || s.url === '/'))
  warnings.push('No server URL in the spec: the base URL must come from the developer (EXPO_PUBLIC_API_URL).');
if (noOpId.length) warnings.push(`${noOpId.length} endpoint(s) without operationId — fine for openapi-fetch (it calls by path), but names in the plan must be chosen by hand: ${noOpId.slice(0, 5).join(', ')}${noOpId.length > 5 ? ', …' : ''}`);
if (noSchema.length) warnings.push(`${noSchema.length} GET endpoint(s) without a JSON response schema — their data type is unknown; ask the backend team or type it by hand from a real response: ${noSchema.slice(0, 5).join(', ')}${noSchema.length > 5 ? ', …' : ''}`);
if (freeForm.size) warnings.push(`Responses typed as a bare object (no properties): ${[...freeForm].slice(0, 5).join(', ')}`);
if (broken.length) warnings.push(`${broken.length} schema propert(ies) that aren't schemas — usually a description broken by an unquoted comma or colon in the backend's YAML; ignore them in mappers and tell the backend team: ${broken.slice(0, 5).join(', ')}`);
if (allOptional.length) warnings.push(`${allOptional.length} schema(s) with no required fields — every field will be optional in TypeScript, so mappers must handle undefined (often a missing "required" list in the backend's annotations): ${allOptional.slice(0, 8).join(', ')}${allOptional.length > 8 ? ', …' : ''}`);
const listsWithoutPaging = endpoints.filter((e) => e.list && !e.pagination).length;

const wanted = tagFilter ? new Set(tagFilter.split(',').map((t) => t.trim())) : null;
const tagCounts = {};
for (const e of endpoints) tagCounts[e.tag] = (tagCounts[e.tag] ?? 0) + 1;

const summary = {
  saved: 'docs/api/openapi.json',
  source: from,
  originalVersion,
  version: spec.openapi,
  title: spec.info?.title,
  apiVersion: spec.info?.version,
  // Relative server URLs ("/api/v3") are relative to where the spec was served.
  servers: (spec.servers ?? []).map((s) => {
    try { return /^https?:/.test(from) && !/^https?:/.test(s.url) ? new URL(s.url, from).href : s.url; } catch { return s.url; }
  }),
  auth: Object.entries(spec.components?.securitySchemes ?? {}).map(([n, s]) =>
    `${n}: ${s.type}${s.scheme ? ` ${s.scheme}` : ''}${s.in ? ` in ${s.in} "${s.name}"` : ''}${s.bearerFormat ? ` (${s.bearerFormat})` : ''}`),
  errorSchema: Object.entries(errorSchemas).sort((a, b) => b[1] - a[1]).map(([n, c]) => `${n} (${c} responses)`),
  tags: tagCounts,
  endpointCount: endpoints.length,
  listsWithoutPagination: listsWithoutPaging,
  endpoints: wanted ? endpoints.filter((e) => wanted.has(e.tag)) : endpoints,
  warnings,
};
console.log(JSON.stringify(summary, null, 1));
process.exitCode = warnings.length ? 3 : 0;
EOF
