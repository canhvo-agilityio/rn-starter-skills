#!/usr/bin/env bash
# Run the project's Maestro flows on a simulator or emulator and print a JSON summary.
#
# Usage: run-flows.sh <project-dir> [--platform ios|android] [--build] [--tags T1,T2] [--exclude-tags T]
#                     [--out <dir>] [flow files or folders…]
#   --platform      ios (default on macOS) or android
#   --build         the app is a development / release build (APP_ID = bundle id or package,
#                   APP_URL = <scheme>:/); default: Expo Go (needs the dev server on :8081)
#   --tags          only flows with these tags (e.g. a ticket id, or R2)
#   --exclude-tags  default: api (flows that need the real backend)
#   --out           where the JUnit report and the run folder go (default: a new temp folder)
#   --start-server  Expo Go only: when nothing listens on :8081, start the dev server for the run
#                   (EXPO_NO_DOTENV=1 plus the variables in .maestro/dev-server.env) and stop it after
#   flows           default: .maestro (its config.yaml decides which flows run)
#
# .maestro/dev-server.env lists the dev-server variables the flows rely on (EXPO_PUBLIC_* only, no
# secrets), e.g. EXPO_PUBLIC_MOCK_SIGNED_IN=1. A dev server that's already running can't be
# checked: the JSON repeats the variables so a red run can be traced to a server started without them.
#
# Prints JSON: target, appId, appUrl, report path, and per flow: name, file, tags, status
# (pass | fail), failure message, artifacts folder (screenshots, hierarchy, logs).
#
# Exit codes: 0 all passed · 1 error (no Maestro, no device, no dev server…) · 3 some flows failed

set -euo pipefail
command -v node >/dev/null 2>&1 || { echo '{"error":"node not found — source rn-starter/scripts/env.sh first"}'; exit 1; }
dir=""; platform=""; build=0; tags=""; exclude="api"; out=""; start_server=0; flows=()
while [ $# -gt 0 ]; do
  case "$1" in
    --platform) platform="${2:-}"; shift 2 ;;
    --build) build=1; shift ;;
    --tags) tags="${2:-}"; shift 2 ;;
    --exclude-tags) exclude="${2:-}"; shift 2 ;;
    --out) out="${2:-}"; shift 2 ;;
    --start-server) start_server=1; shift ;;
    -*) echo "{\"error\":\"unknown option: $1\"}"; exit 1 ;;
    *) if [ -z "$dir" ]; then dir="$1"; else flows+=("$1"); fi; shift ;;
  esac
done
[ -n "$dir" ] && [ -f "$dir/package.json" ] || { echo '{"error":"usage: run-flows.sh <project-dir> [options] [flows…]"}'; exit 1; }
cd "$dir"
[ -z "$platform" ] && { [ "$(uname -s)" = Darwin ] && platform=ios || platform=android; }
maestro="$(command -v maestro 2>/dev/null || true)"; [ -z "$maestro" ] && [ -x "$HOME/.maestro/bin/maestro" ] && maestro="$HOME/.maestro/bin/maestro"
[ -n "$maestro" ] || { echo '{"error":"Maestro not installed: run install-maestro.sh (with the developer'"'"'s yes)"}'; exit 1; }
[ ${#flows[@]} -gt 0 ] || flows=(.maestro)
[ -e "${flows[0]}" ] || { echo "{\"error\":\"no flows at ${flows[0]}\"}"; exit 1; }

# Device
if [ "$platform" = ios ]; then
  xcrun simctl list devices booted 2>/dev/null | grep -q Booted || { echo '{"error":"no booted iOS Simulator: run rn-starter scripts/start-simulator.sh"}'; exit 1; }
else
  adb devices 2>/dev/null | awk 'NR>1 && $2=="device"' | grep -q . || { echo '{"error":"no Android device: run rn-starter scripts/start-emulator.sh"}'; exit 1; }
fi

# APP_ID / APP_URL for the target
read -r app_id app_url < <(node -e '
  const fs = require("fs");
  const [platform, build] = process.argv.slice(1);
  const app = (() => { try { return JSON.parse(fs.readFileSync("app.json", "utf8")).expo || {}; } catch { return {}; } })();
  if (build !== "1") { console.log(`${platform === "ios" ? "host.exp.Exponent" : "host.exp.exponent"} exp://127.0.0.1:8081/--`); process.exit(0); }
  let id = platform === "ios" ? app.ios?.bundleIdentifier : app.android?.package;
  if (!id && platform === "android") id = ((() => { try { return fs.readFileSync("android/app/build.gradle", "utf8"); } catch { return ""; } })().match(/applicationId\s+["\x27]([^"\x27]+)/) || [])[1];
  if (!id && platform === "ios" && fs.existsSync("ios")) for (const f of fs.readdirSync("ios").filter((f) => f.endsWith(".xcodeproj"))) {
    id = (fs.readFileSync(`ios/${f}/project.pbxproj`, "utf8").match(/PRODUCT_BUNDLE_IDENTIFIER = "?([^";]+)"?;/) || [])[1]; if (id) break;
  }
  const scheme = Array.isArray(app.scheme) ? app.scheme[0] : app.scheme;
  console.log(`${id || "-"} ${scheme ? scheme + ":/" : "-"}`);
' "$platform" "$build")
[ "$app_id" != "-" ] || { echo '{"error":"no bundle id / package found for the build (app.json or the native project)"}'; exit 1; }
[ "$app_url" != "-" ] || { echo '{"error":"no URL scheme found (expo.scheme in app.json, or pass flows that launch the app instead)"}'; exit 1; }

# Dev-server variables the flows rely on (non-secret EXPO_PUBLIC_* only)
server_env=()
if [ -f .maestro/dev-server.env ]; then
  while IFS= read -r line; do
    line="${line%%#*}"; line="$(printf '%s' "$line" | tr -d '[:space:]')"
    [ -n "$line" ] || continue
    case "$line" in
      EXPO_PUBLIC_*=*) server_env+=("$line") ;;
      *) echo "{\"error\":\".maestro/dev-server.env: only EXPO_PUBLIC_* variables belong here (got ${line%%=*})\"}"; exit 1 ;;
    esac
  done < .maestro/dev-server.env
fi
server_started=0; server_pid=""
if [ "$build" -eq 0 ]; then
  if ! curl -fs --max-time 3 http://127.0.0.1:8081/status 2>/dev/null | grep -q running; then
    [ "$start_server" -eq 1 ] || { echo "{\"error\":\"no dev server on :8081: start it with EXPO_NO_DOTENV=1 ${server_env[*]-} npx expo start --port 8081, or pass --start-server\"}"; exit 1; }
    env EXPO_NO_DOTENV=1 ${server_env[@]+"${server_env[@]}"} npx expo start --port 8081 > "${TMPDIR:-/tmp}/run-flows-metro.$$.log" 2>&1 &
    server_pid=$!; server_started=1
    trap '[ -n "$server_pid" ] && kill "$server_pid" 2>/dev/null; pkill -P "$server_pid" 2>/dev/null; true' EXIT
    for _ in $(seq 1 90); do curl -fs --max-time 2 http://127.0.0.1:8081/status 2>/dev/null | grep -q running && break; sleep 2; done
    curl -fs --max-time 2 http://127.0.0.1:8081/status 2>/dev/null | grep -q running || { echo '{"error":"the dev server did not start; see '"${TMPDIR:-/tmp}/run-flows-metro.$$.log"'"}'; exit 1; }
  fi
  [ "$platform" = android ] && adb reverse tcp:8081 tcp:8081 >/dev/null
fi

[ -n "$out" ] || out="$(mktemp -d)"
mkdir -p "$out"
args=(--platform "$platform" test "${flows[@]}" -e "APP_ID=$app_id" -e "APP_URL=$app_url"
      --format junit --output "$out/report.xml" --test-output-dir "$out/run" --no-ansi)
[ -n "$tags" ] && args+=(--include-tags "$tags")
[ -n "$exclude" ] && args+=(--exclude-tags "$exclude")
set +e
"$maestro" "${args[@]}" > "$out/maestro.log" 2>&1
code=$?
set -e

node - "$out" "$platform" "$build" "$app_id" "$app_url" "$code" "$server_started" "${server_env[*]-}" <<'EOF'
const fs = require('fs');
const path = require('path');
const [out, platform, build, appId, appUrl, code, serverStarted, serverEnv] = process.argv.slice(2);
const report = path.join(out, 'report.xml');
const xml = fs.existsSync(report) ? fs.readFileSync(report, 'utf8') : '';
const unescape = (s) => s.replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
const runDir = path.join(out, 'run');
const runs = fs.existsSync(runDir) ? fs.readdirSync(runDir).map((d) => path.join(runDir, d)).filter((d) => fs.statSync(d).isDirectory()) : [];
const flows = [...xml.matchAll(/<testcase\b([^>]*)>([\s\S]*?)<\/testcase>|<testcase\b([^>]*)\/>/g)].map((m) => {
  const attrs = m[1] || m[3] || '';
  const body = m[2] || '';
  const attr = (k) => unescape((attrs.match(new RegExp(`\\b${k}="([^"]*)"`)) || [])[1] || '');
  const name = attr('name');
  const tags = unescape((body.match(/name="tags" value="([^"]*)"/) || [])[1] || '').split(',').map((t) => t.trim()).filter(Boolean);
  const failure = body.match(/<(failure|error)[^>]*>([\s\S]*?)<\/\1>/);
  const artifacts = runs.map((r) => path.join(r, name)).find((p) => fs.existsSync(p)) || null;
  return {
    name, file: attr('file') || null, tags,
    status: attr('status') === 'SUCCESS' && !failure ? 'pass' : 'fail',
    failure: failure ? unescape(failure[2]).trim().slice(0, 500) : null,
    seconds: Number(attr('time')) || null,
    artifacts,
  };
});
const summary = {
  target: `${platform}${build === '1' ? ' build' : ' Expo Go'}`, appId, appUrl,
  report: fs.existsSync(report) ? report : null, log: path.join(out, 'maestro.log'),
  passed: flows.filter((f) => f.status === 'pass').length, failed: flows.filter((f) => f.status === 'fail').length,
  flows,
};
if (build !== '1') summary.devServer = { startedByThisRun: serverStarted === '1', expectedEnv: serverEnv ? serverEnv.split(' ') : [] };
if (!flows.length) summary.error = `no results (maestro exit ${code}); read ${summary.log}`;
else if (summary.failed === flows.length && flows.length > 1) {
  summary.hint = 'Every flow failed. If they fail at their first wait, the app is probably not where the flows expect it: '
    + 'a dev server started without .maestro/dev-server.env (e.g. not signed in), the wrong APP_ID, or Expo Go showing a sheet. '
    + 'Look at one failing flow\'s screenshot before changing any flow.';
}
console.log(JSON.stringify(summary, null, 2));
process.exitCode = !flows.length ? 1 : summary.failed ? 3 : 0;
EOF
