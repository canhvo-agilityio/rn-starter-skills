#!/usr/bin/env bash
# Turn design icons (SVG files) into React Native icon components, with SVGR + react-native-svg.
#
# Usage: svg-icons.sh <project-dir> <svg-dir>
#
#   <svg-dir>/<name>.svg  →  <project>/src/components/icons/<name>.tsx  exporting <Name>Icon
#   plus src/components/icons/types.ts (IconProps) and index.ts (re-exports every icon in the folder).
#
# Each component takes `size` (default: the SVG's own width) and the usual SvgProps. An icon drawn
# in one color gets that color replaced by currentColor and a `color` prop defaulting to the original
# value, so screens can tint it with a theme token. Multi-color icons keep their colors.
# A leading "icon-" or trailing "-icon" in the file name is dropped (icon-bean.svg → bean.tsx, BeanIcon).
#
# Idempotent: rerunning regenerates the same files. Hand-written components in the folder are kept
# and included in index.ts. SVGR is installed once into ~/.cache/rn-starter/svgr (pinned versions);
# the project gets no new dev dependency. Needs node and network access on the first run.
#
# Output: one line per icon — "ok <file> <Component> single-color <#hex>" or "ok <file> <Component> multi-color".
# Exit 0 = done · 1 = error · 3 = done, but react-native-svg isn't installed in the project yet.

set -euo pipefail

project="$(cd "${1:?usage: svg-icons.sh <project-dir> <svg-dir>}" && pwd)"
svg_dir="$(cd "${2:?usage: svg-icons.sh <project-dir> <svg-dir>}" && pwd)"
[ -f "$project/package.json" ] || { echo "error: no package.json in $project" >&2; exit 1; }
command -v node >/dev/null || { echo "error: node not found — source env.sh first" >&2; exit 1; }
ls "$svg_dir"/*.svg >/dev/null 2>&1 || { echo "error: no .svg files in $svg_dir" >&2; exit 1; }

cache="${XDG_CACHE_HOME:-$HOME/.cache}/rn-starter/svgr"
if [ ! -f "$cache/node_modules/@svgr/core/package.json" ]; then
  mkdir -p "$cache"
  (cd "$cache" && { [ -f package.json ] || echo '{"private":true}' > package.json; } \
    && npm install --no-audit --no-fund --silent @svgr/core@8.1.0 @svgr/plugin-svgo@8.1.0 @svgr/plugin-jsx@8.1.0) >&2 \
    || { echo "error: could not install SVGR into $cache" >&2; exit 1; }
fi

SVGR_CACHE="$cache" node - "$project" "$svg_dir" <<'EOF'
const fs = require('fs');
const path = require('path');
const { createRequire } = require('module');

const [project, svgDir] = process.argv.slice(2);
const req = createRequire(path.join(process.env.SVGR_CACHE, 'node_modules', '_'));
const { transform } = req('@svgr/core');
const svgo = req('@svgr/plugin-svgo').default ?? req('@svgr/plugin-svgo');
const jsx = req('@svgr/plugin-jsx').default ?? req('@svgr/plugin-jsx');

const outDir = path.join(project, 'src', 'components', 'icons');
fs.mkdirSync(outDir, { recursive: true });

const kebab = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
const pascal = (s) => s.split('-').filter(Boolean).map((w) => w[0].toUpperCase() + w.slice(1)).join('');

// Paint values that are real colors (not none / currentColor / gradient references), grouped
// case-insensitively; each group keeps the spellings used in the file, since SVGR's attribute
// replacement is case-sensitive.
const paints = (svg) => {
  const found = new Map();
  // Clip paths and masks only cut shapes out (Figma exports them with fill="white"); not paint.
  const painted = svg.replace(/<(clipPath|mask)\b[\s\S]*?<\/\1>/gi, '');
  for (const m of painted.matchAll(/\b(?:fill|stroke|stop-color)\s*[=:]\s*["']?\s*([^"';\s>]+)/gi)) {
    const raw = m[1].trim();
    const v = raw.toLowerCase();
    if (v === 'none' || v === 'currentcolor' || v.startsWith('url(') || v === 'transparent') continue;
    if (!found.has(v)) found.set(v, new Set());
    found.get(v).add(raw);
  }
  return found;
};

const template = (variables, { tpl }) => tpl`
${variables.imports};

export const ${variables.componentName} = (${variables.props}) => (
  ${variables.jsx}
);
`;

(async () => {
  const files = fs.readdirSync(svgDir).filter((f) => f.endsWith('.svg')).sort();
  for (const file of files) {
    const raw = fs.readFileSync(path.join(svgDir, file), 'utf8');
    const base = kebab(path.basename(file, '.svg')).replace(/^icon-/, '').replace(/-icon$/, '');
    const componentName = `${pascal(base)}Icon`;
    const width = Number((raw.match(/<svg[^>]*\swidth=["']?([\d.]+)/i) || [])[1]) || 24;
    const colors = paints(raw);
    const single = colors.size === 1 ? [...colors.keys()][0] : null;
    const replaceAttrValues = single
      ? Object.fromEntries([...colors.get(single)].map((spelling) => [spelling, 'currentColor']))
      : undefined;

    const code = await transform(
      raw,
      {
        plugins: [svgo, jsx],
        native: true,
        jsxRuntime: 'automatic',
        expandProps: 'end',
        dimensions: false,
        svgProps: single
          ? { width: '{size}', height: '{size}', color: '{color}' }
          : { width: '{size}', height: '{size}' },
        replaceAttrValues,
        svgoConfig: {
          plugins: [
            // convertColors would rewrite white → #fff, #808080 → gray before replaceAttrValues runs,
            // so the single color wouldn't match and the icon would ignore its `color` prop.
            { name: 'preset-default', params: { overrides: { removeViewBox: false, convertColors: false } } },
            'removeXMLNS',
            // Icons sit side by side on one screen: keep gradient / clip-path ids unique per icon.
            { name: 'prefixIds', params: { prefix: base } },
          ],
        },
        template,
      },
      { componentName },
    );

    // Typed props with defaults, replacing SVGR's untyped `props`.
    const params = single
      ? `{ size = ${width}, color = '${single}', ...props }: IconProps`
      : `{ size = ${width}, ...props }: IconProps`;
    const out = code
      .replace(/^(import [^\n]*react-native-svg['"];?)$/m, `$1\n\nimport type { IconProps } from './types';\n`)
      .replace(/= \(?props\)? =>/, `= (${params}) =>`)
      .replace(/^\s*\n/, '');
    fs.writeFileSync(path.join(outDir, `${base}.tsx`), out);
    console.log(`ok src/components/icons/${base}.tsx ${componentName} ${single ? `single-color ${single}` : 'multi-color'}`);
  }

  fs.writeFileSync(
    path.join(outDir, 'types.ts'),
    `import type { SvgProps } from 'react-native-svg';\n\nexport interface IconProps extends SvgProps {\n  size?: number;\n  color?: string;\n}\n`,
  );

  // index.ts lists every icon component in the folder, generated or hand-written.
  const exports = fs.readdirSync(outDir)
    .filter((f) => f.endsWith('.tsx') && f !== 'index.tsx')
    .sort()
    .flatMap((f) => {
      const names = [...fs.readFileSync(path.join(outDir, f), 'utf8').matchAll(/export const (\w+)/g)].map((m) => m[1]);
      return names.length ? [`export { ${names.join(', ')} } from './${f.replace(/\.tsx$/, '')}';`] : [];
    });
  fs.writeFileSync(path.join(outDir, 'index.ts'), `${exports.join('\n')}\nexport type { IconProps } from './types';\n`);

  // SVGR prints one long line per icon; format with the project's own Prettier when it has one.
  const prettierPkg = path.join(project, 'node_modules', 'prettier', 'package.json');
  if (fs.existsSync(prettierPkg)) {
    const { bin } = JSON.parse(fs.readFileSync(prettierPkg, 'utf8'));
    const prettierBin = path.join(project, 'node_modules', 'prettier', typeof bin === 'string' ? bin : bin.prettier);
    require('child_process').spawnSync(process.execPath, [prettierBin, '--write', '--log-level', 'warn', outDir], { cwd: project, stdio: 'inherit' });
  }
})().catch((e) => {
  console.error(`error: ${e.message}`);
  process.exit(1);
});
EOF

if ! node -e "const p=require('$project/package.json');process.exit({...p.dependencies,...p.devDependencies}['react-native-svg']?0:1)"; then
  echo "warn: react-native-svg is not installed — Expo: npx expo install react-native-svg · CLI: <pm> add react-native-svg && cd ios && pod install"
  exit 3
fi
exit 0
