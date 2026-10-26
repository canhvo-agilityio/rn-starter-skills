#!/usr/bin/env bash
# Lock the tests that reproduce a bug, so the fix can't weaken them, and prove afterwards that
# they weren't touched. Works before the test is committed: the project's pre-commit hook runs
# related tests, so a failing test can't be committed on its own; it's committed with the fix.
#
# Usage (from the project root, where .claude/ lives):
#   lock-tests.sh lock <test file> [more files]   record their content (hash + a copy)
#   lock-tests.sh check                          exit 0 if every locked file is unchanged
#   lock-tests.sh restore                        put back the locked content of changed files
#   lock-tests.sh unlock                         remove the lock
#   lock-tests.sh status                         print the lock as JSON
#
# The lock is .claude/fix-task.json plus copies in .claude/fix-task/, both added to
# .git/info/exclude so they're never committed. rn-starter's guard hook (.claude/hooks/guard.mjs)
# reads the lock and refuses edits to the locked files; check works with or without the hook.
#
# Exit codes: 0 done / unchanged · 1 error · 3 a locked file changed (check)

set -euo pipefail
lock=".claude/fix-task.json"
copies=".claude/fix-task"
cmd="${1:-status}"; shift || true
[ -f package.json ] || { echo "error: run from the project root (no package.json in $PWD)" >&2; exit 1; }
command -v node >/dev/null 2>&1 || { echo "error: node not found — source rn-starter/scripts/env.sh first" >&2; exit 1; }

case "$cmd" in
  lock)
    [ $# -gt 0 ] || { echo "usage: lock-tests.sh lock <test file> [more files]" >&2; exit 1; }
    for f in "$@"; do [ -f "$f" ] || { echo "error: no such file: $f" >&2; exit 1; }; done
    rm -rf "$copies"; mkdir -p "$copies"
    if git rev-parse --git-dir >/dev/null 2>&1; then
      exclude="$(git rev-parse --git-path info/exclude)"
      mkdir -p "$(dirname "$exclude")"
      for p in "$lock" "$copies/"; do grep -qxF "$p" "$exclude" 2>/dev/null || printf '%s\n' "$p" >> "$exclude"; done
    fi
    node - "$lock" "$copies" "$@" <<'EOF'
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const [lock, copies, ...files] = process.argv.slice(2);
const entries = files.map((f) => {
  const rel = path.relative(process.cwd(), path.resolve(f)).split(path.sep).join('/');
  const content = fs.readFileSync(f);
  fs.mkdirSync(path.dirname(path.join(copies, rel)), { recursive: true });
  fs.writeFileSync(path.join(copies, rel), content);
  return { path: rel, sha256: crypto.createHash('sha256').update(content).digest('hex') };
});
fs.writeFileSync(lock, JSON.stringify({ lockedAt: new Date().toISOString(), files: entries }, null, 2) + '\n');
console.log(`locked ${entries.length} file(s): ${entries.map((e) => e.path).join(' ')}`);
EOF
    ;;
  check|restore)
    [ -f "$lock" ] || { echo "error: no lock ($lock): run lock-tests.sh lock first" >&2; exit 1; }
    node - "$lock" "$copies" "$cmd" <<'EOF'
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const [lock, copies, cmd] = process.argv.slice(2);
const { files } = JSON.parse(fs.readFileSync(lock, 'utf8'));
const hash = (f) => (fs.existsSync(f) ? crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex') : null);
const changed = files.filter((e) => hash(e.path) !== e.sha256).map((e) => e.path);
if (cmd === 'restore') {
  for (const f of changed) { fs.mkdirSync(path.dirname(f), { recursive: true }); fs.copyFileSync(path.join(copies, f), f); }
  console.log(changed.length ? `restored: ${changed.join(' ')}` : 'nothing to restore');
} else if (changed.length) {
  console.error(`CHANGED since the lock: ${changed.join(' ')}`);
  console.error('The fix must make the locked test pass without editing it. Put it back with: lock-tests.sh restore');
  process.exitCode = 3;
} else {
  console.log(`unchanged since the lock: ${files.map((e) => e.path).join(' ')}`);
}
EOF
    ;;
  unlock)
    rm -rf "$lock" "$copies"; echo "unlocked"
    ;;
  status)
    if [ -f "$lock" ]; then cat "$lock"; else echo '{"locked":false}'; fi
    ;;
  *)
    echo "usage: lock-tests.sh lock <files> | check | restore | unlock | status" >&2; exit 1
    ;;
esac
