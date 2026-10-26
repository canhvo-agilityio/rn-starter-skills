#!/usr/bin/env bash
# Add unit tests, git hooks and commit-message rules to a React Native / Expo project.
# Idempotent: rerunning rewrites the hook files and config from the options given.
#
# Usage: setup-quality.sh [options] [project-dir]
#   --test                         Jest + React Native Testing Library (+ jest-expo on Expo), sample test
#   --pre-commit <list>            comma list: lint,format,related-tests,typecheck   (needs a git repo)
#   --pre-push <list>              comma list: typecheck,test,protect   (protect: refuse pushes to the
#                                  branches in .rn-starter.json "protectedBranches", default main,master;
#                                  protect-main is accepted as an old name)
#   --commit-msg conventional|none commitlint with @commitlint/config-conventional
#
# Custom rules the dev asked for ("Other" answers) are not options here: run this with the
# closest defaults, then edit the generated files (.husky/*, commitlint.config.mjs,
# package.json "lint-staged") — they're small and meant to be edited.
#
# Prints a summary of what each hook runs at the end.
# Exit 3 = set up, but the project currently fails tsc while a type-check hook is enabled.

set -euo pipefail

want_test=0; pre_commit=""; pre_push=""; commit_msg="none"; dir="."
while [ $# -gt 0 ]; do
  case "$1" in
    --test) want_test=1 ;;
    --pre-commit) pre_commit="$2"; shift ;;
    --pre-push) pre_push="$2"; shift ;;
    --commit-msg) commit_msg="$2"; shift ;;
    -*) echo "unknown option: $1" >&2; exit 64 ;;
    *) dir="$1" ;;
  esac
  shift
done

cd "$dir"
[ -f package.json ] || { echo "error: no package.json in $(pwd)" >&2; exit 1; }
log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
has_item() { case ",$1," in *",$2,"*) return 0 ;; *) return 1 ;; esac; }
dep() { node -e "const p=require('./package.json');process.exit({...p.dependencies,...p.devDependencies}['$1']?0:1)"; }
pkg_set() { # pkg_set <js expression mutating p>
  node -e "const fs=require('fs');const p=JSON.parse(fs.readFileSync('package.json','utf8'));$1;fs.writeFileSync('package.json',JSON.stringify(p,null,2)+'\n')"
}

if [ -f pnpm-lock.yaml ]; then pm=pnpm; elif [ -f yarn.lock ]; then pm=yarn
elif [ -f bun.lockb ] || [ -f bun.lock ]; then pm=bun; else pm=npm; fi
add_dev() {
  case "$pm" in
    npm) npm install --save-dev "$@" ;;
    pnpm) pnpm add -D "$@" ;;
    yarn) yarn add -D "$@" ;;
    bun) bun add -d "$@" ;;
  esac
}
is_expo=0; dep expo && is_expo=1

# ------------------------------------------------------------------ unit tests
if [ "$want_test" -eq 1 ]; then
  log "Unit tests: Jest + React Native Testing Library"
  if [ "$is_expo" -eq 1 ]; then
    # expo install picks the jest-expo matching the SDK; args after -- go to the package manager
    npx expo install jest-expo jest @types/jest -- -D
    add_dev @testing-library/react-native test-renderer
    pkg_set "p.scripts=p.scripts||{};p.scripts.test=p.scripts.test||'jest';p.jest=p.jest||{preset:'jest-expo'}"
  else
    # The RN CLI template already ships Jest with the react-native preset.
    add_dev @testing-library/react-native test-renderer
    pkg_set "p.scripts=p.scripts||{};p.scripts.test=p.scripts.test||'jest'"
  fi
  # TypeScript 6 no longer auto-loads @types/* packages, so test globals (test, expect, jest)
  # need an explicit reference or tsc rejects every test file.
  if [ -f tsconfig.json ] && [ ! -f jest-env.d.ts ]; then
    printf '/// <reference types="jest" />\n' > jest-env.d.ts
  fi
  mkdir -p __tests__
  if ! ls __tests__/*.test.* >/dev/null 2>&1; then
    cat > __tests__/example.test.tsx <<'EOF'
import { render, screen } from '@testing-library/react-native';
import { Text } from 'react-native';

// Sample test proving the setup works. Replace with tests for real components.
// React Native Testing Library 14+: render and user events are async — always await them.
test('renders text', async () => {
  await render(<Text>Hello</Text>);
  expect(screen.getByText('Hello')).toBeOnTheScreen();
});
EOF
  fi
fi

# ------------------------------------------------------------------ hooks
if [ -n "$pre_commit$pre_push" ] || [ "$commit_msg" != none ]; then
  git rev-parse --git-dir >/dev/null 2>&1 || { echo "error: not a git repository — run git init first" >&2; exit 1; }
  log "Git hooks: Husky"
  add_dev husky
  npx husky init >/dev/null      # adds "prepare": "husky" and .husky/
  rm -f .husky/pre-commit .husky/pre-push .husky/commit-msg
fi

if [ -n "$pre_commit" ]; then
  add_dev lint-staged
  code_cmds=()
  if has_item "$pre_commit" lint; then
    if [ -f biome.json ] || [ -f biome.jsonc ]; then code_cmds+=("biome check --write --no-errors-on-unmatched")
    elif dep eslint || ls eslint.config.* .eslintrc* >/dev/null 2>&1; then code_cmds+=("eslint --fix")
    else echo "warn: 'lint' requested but no ESLint/Biome setup found — set up lint first; skipping" >&2; fi
  fi
  format_cmd=""
  if has_item "$pre_commit" format; then
    if dep prettier; then format_cmd="prettier --write --ignore-unknown"
    elif [ -f biome.json ] || [ -f biome.jsonc ]; then :   # biome check --write already formats
    else echo "warn: 'format' requested but Prettier isn't installed — skipping" >&2; fi
  fi
  [ -n "$format_cmd" ] && code_cmds+=("$format_cmd")
  if has_item "$pre_commit" related-tests; then
    if dep jest; then code_cmds+=("jest --bail --findRelatedTests --passWithNoTests")
    else echo "warn: 'related-tests' requested but Jest isn't installed — skipping" >&2; fi
  fi
  node - "$format_cmd" "${code_cmds[@]+"${code_cmds[@]}"}" <<'EOF'
const fs = require('fs');
const [formatCmd, ...codeCmds] = process.argv.slice(2);
const p = JSON.parse(fs.readFileSync('package.json', 'utf8'));
const cfg = {};
if (codeCmds.length) cfg['*.{js,jsx,ts,tsx}'] = codeCmds;
if (formatCmd) cfg['*.{json,md,yml,yaml,css}'] = [formatCmd];
p['lint-staged'] = cfg;
fs.writeFileSync('package.json', JSON.stringify(p, null, 2) + '\n');
EOF
  { echo "npx lint-staged"
    has_item "$pre_commit" typecheck && echo "npx tsc --noEmit"
  } > .husky/pre-commit
fi

if [ -n "$pre_push" ]; then
  {
    if has_item "$pre_push" protect || has_item "$pre_push" protect-main; then
      # Git gives pre-push one "<local ref> <local sha> <remote ref> <remote sha>" line per ref
      # being pushed, so `git push origin feature:main` is caught too, not only pushes from main.
      # The list lives in .rn-starter.json (protectedBranches), shared with the Claude guard hook.
      cat <<'EOF'
protected="$(node -e "try{const b=require('./.rn-starter.json').protectedBranches;if(Array.isArray(b)&&b.length){console.log(b.join(' '));process.exit(0)}}catch{}console.log('main master')")"
while read -r _local_ref _local_sha remote_ref _remote_sha; do
  branch="${remote_ref#refs/heads/}"
  for p in $protected; do
    if [ "$branch" = "$p" ]; then
      echo "Pushing directly to $branch is blocked (protectedBranches in .rn-starter.json). Push a feature branch and open a pull request." >&2
      exit 1
    fi
  done
done
EOF
    fi
    has_item "$pre_push" typecheck && echo "npx tsc --noEmit"
    has_item "$pre_push" test && echo "npx jest --passWithNoTests"
  } > .husky/pre-push
fi

if [ "$commit_msg" = conventional ]; then
  add_dev @commitlint/cli @commitlint/config-conventional
  cat > commitlint.config.mjs <<'EOF'
// Conventional Commits: type(scope?): subject — e.g. "feat(cart): add quantity stepper"
// Types: build, chore, ci, docs, feat, fix, perf, refactor, revert, style, test
export default { extends: ['@commitlint/config-conventional'] };
EOF
  echo 'npx --no -- commitlint --edit "$1"' > .husky/commit-msg
fi

# ------------------------------------------------------------------ pnpm housekeeping
# pnpm writes "<pkg>: set this to true or false" for dependencies whose install scripts it
# skipped. Record the decision (false = keep skipping; they ship prebuilt binaries) so the file
# is valid and the warning stops.
if [ "$pm" = pnpm ] && [ -f pnpm-workspace.yaml ]; then
  sed -i.bak -E 's/: set this to true or false$/: false/' pnpm-workspace.yaml && rm -f pnpm-workspace.yaml.bak
fi

# ------------------------------------------------------------------ type check baseline
typecheck_hook=0
{ has_item "$pre_commit" typecheck || has_item "$pre_push" typecheck; } && typecheck_hook=1
tsc_errors=0
if [ "$typecheck_hook" -eq 1 ] && [ -f tsconfig.json ]; then
  # Expo generates expo-env.d.ts (asset/CSS module types) on the first `expo start`;
  # create it now so tsc doesn't report false errors. The template already gitignores it.
  if [ "$is_expo" -eq 1 ] && [ ! -f expo-env.d.ts ]; then
    printf '/// <reference types="expo/types" />\n\n// NOTE: This file should not be edited and should be in your git ignore\n' > expo-env.d.ts
  fi
  tsc_errors="$(npx tsc --noEmit 2>/dev/null | grep -c 'error TS' || true)"
fi

# ------------------------------------------------------------------ summary
echo
log "Summary"
[ "$want_test" -eq 1 ] && echo "test:        $pm test  (Jest + @testing-library/react-native)"
for h in pre-commit pre-push commit-msg; do
  [ -f ".husky/$h" ] && { echo "$h:"; sed 's/^/    /' ".husky/$h"; }
done
node -e "const c=require('./package.json')['lint-staged'];if(c){console.log('lint-staged:');for(const[k,v]of Object.entries(c))console.log('    '+k+' → '+v.join(' && '))}"
if [ "$tsc_errors" -gt 0 ]; then
  echo
  echo "WARNING: tsc reports $tsc_errors error(s) right now, so the type-check hook will block every"
  echo "commit/push until they're fixed. Run 'npx tsc --noEmit' to see them (templates sometimes ship"
  echo "with their own). Fix them, or remove 'npx tsc --noEmit' from the hook until they are."
  exit 3
fi
exit 0
