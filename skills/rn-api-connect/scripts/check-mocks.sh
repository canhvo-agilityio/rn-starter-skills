#!/usr/bin/env bash
# Check the data boundaries after connecting an API. Read-only.
#
# Usage: check-mocks.sh [project-dir]   (default: current directory)
#
# Reports, one finding per line ("<rule> <file> <detail>"):
#   mock-import      a file outside services/ and tests imports mocks
#   api-types        a file outside services/ and lib/ imports the generated API types (DTOs);
#                    screens and hooks use the app types in types/<domain>.ts
#   env-read         process.env read outside src/lib/env.ts
#   unflagged-mock   a service that calls the API also returns mocks without the USE_MOCKS flag
#   still-mocked     an exported service function that returns mocks with no USE_MOCKS branch
#                    (informational: list it in the hand-off) — reported per function, so a
#                    half-connected service still shows the functions left on mocks
# and a final "summary errors=<n> mocked=<n>" line.
#
# Exit codes: 0 clean (still-mocked domains allowed) · 1 error · 3 boundary violations found

set -euo pipefail
dir="$(cd "${1:-.}" && pwd)"
[ -d "$dir/src" ] || { echo "no src/ in $dir" >&2; exit 1; }
command -v node >/dev/null 2>&1 || { echo "node not found — source rn-starter/scripts/env.sh first" >&2; exit 1; }

node - "$dir" <<'EOF'
const fs = require('fs');
const path = require('path');
const dir = process.argv[2];
const walk = (p, out = []) => {
  for (const e of fs.readdirSync(path.join(dir, p)).sort()) {
    const rel = path.posix.join(p, e);
    if (fs.statSync(path.join(dir, rel)).isDirectory()) walk(rel, out);
    else if (/\.(ts|tsx|js|jsx)$/.test(e)) out.push(rel);
  }
  return out;
};
const isTest = (f) => /__tests__|\.test\.|\.spec\.|test-utils/.test(f);
const files = walk('src').filter((f) => !isTest(f));
const findings = [];
const add = (rule, file, detail) => findings.push(`${rule} ${file} ${detail}`);

const mockImport = /from\s+['"](@\/mocks[^'"]*|[^'"]*\/mocks(?:\/[^'"]*)?)['"]/;
const apiTypesImport = /from\s+['"][^'"]*types\/api\.gen['"]/;
const clientCall = /from\s+['"](@\/lib\/api-client|[^'"]*\/api-client|openapi-fetch|axios|ky)['"]|\bfetch\(/;
const flag = /USE_MOCKS|useMocks/;
let mocked = 0;

for (const f of files) {
  const code = fs.readFileSync(path.join(dir, f), 'utf8');
  const inServices = /^src\/services\//.test(f) || /^src\/features\/[^/]+\/api\.(ts|js)$/.test(f);
  const inMocks = /^src\/mocks\//.test(f) || /^src\/features\/[^/]+\/mocks\./.test(f);
  if (!inServices && !inMocks && mockImport.test(code)) add('mock-import', f, code.match(mockImport)[1]);
  if (!inServices && !/^src\/lib\//.test(f) && !/^src\/types\/api\.gen\.ts$/.test(f) && apiTypesImport.test(code))
    add('api-types', f, 'imports DTO types; map them in the service and use types/<domain>.ts');
  if (!/^src\/lib\/env\.(ts|js)$/.test(f) && /process\.env\.[A-Z]/.test(code))
    add('env-read', f, (code.match(/process\.env\.\w+/g) || []).join(','));
  if (inServices) {
    const mocks = mockImport.test(code);
    const calls = clientCall.test(code);
    if (mocks && calls && !flag.test(code)) add('unflagged-mock', f, 'calls the API and returns mocks without USE_MOCKS');
    if (mocks) {
      // Names imported from mocks, then each exported function's body up to the next top-level
      // declaration (helpers between exports aren't part of the function above them).
      const mockNames = [...code.matchAll(/import\s*\{([^}]*)\}\s*from\s*['"][^'"]*mocks[^'"]*['"]/g)]
        .flatMap((m) => m[1].split(',').map((n) => n.trim().split(/\s+as\s+/).pop()).filter(Boolean));
      // Module state seeded from a mock (let favoriteIds = [...mockFavoriteIds]) is mock data too.
      for (const m of code.matchAll(/^(?:let|const|var)\s+(\w+)\s*=([^\n]*)$/gm))
        if (mockNames.some((n) => m[2].includes(n))) mockNames.push(m[1]);
      const decls = [...code.matchAll(/^(export\s+)?(?:const|let|var|async\s+function|function|type|interface)\s+(\w+)/gm)];
      decls.forEach((m, i) => {
        if (!m[1]) return;
        const body = code.slice(m.index, decls[i + 1]?.index ?? code.length);
        const usesMock = mockNames.some((n) => new RegExp(`\\b${n}\\b`).test(body));
        if (usesMock && !flag.test(body)) { mocked += 1; console.log(`still-mocked ${f} ${m[2]}`); }
      });
    }
  }
}
for (const line of findings) console.log(line);
console.log(`summary errors=${findings.length} mocked=${mocked}`);
process.exitCode = findings.length ? 3 : 0;
EOF
