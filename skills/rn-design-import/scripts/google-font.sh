#!/usr/bin/env bash
# Add a Google Font to a React Native / Expo project.
#
# Usage: google-font.sh "<Family Name>" <weights> [project-dir]
#   weights: comma list of 100..900, optional "i" suffix for italic, e.g. 400,500,600,700,400i
#
# Expo:  installs @expo-google-fonts/<slug> + expo-font (loaded at runtime with useFonts,
#        works in Expo Go).
# CLI:   copies static TTFs from the same npm package into assets/fonts, renamed to each
#        font's PostScript name (so `fontFamily` is identical on iOS and Android), and links
#        them with react-native-asset.
#
# Prints one line per weight at the end:  font <weight> <fontFamily value> [<import name>]

set -euo pipefail
family="${1:?family name required, e.g. \"Be Vietnam Pro\"}"
weights="${2:?weights required, e.g. 400,500,700}"
dir="$(cd "${3:-.}" && pwd)"
here="$(cd "$(dirname "$0")" && pwd)"

slug="$(echo "$family" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-|-$//g')"
pkg="@expo-google-fonts/$slug"
ident="$(echo "$family" | sed -E 's/[^A-Za-z0-9]+//g; s/^([0-9])/_\1/')"  # e.g. BeVietnamPro

npm view "$pkg" version >/dev/null 2>&1 || {
  echo "error: '$family' is not available as $pkg." >&2
  echo "It may not be a Google Font (commercial fonts like Gilroy or SF Pro must come from the dev)," >&2
  echo "or the name is spelled differently — check https://fonts.google.com" >&2
  exit 3
}

weight_name() {
  case "$1" in
    100) echo Thin ;; 200) echo ExtraLight ;; 300) echo Light ;; 400) echo Regular ;;
    500) echo Medium ;; 600) echo SemiBold ;; 700) echo Bold ;; 800) echo ExtraBold ;;
    900) echo Black ;; *) return 1 ;;
  esac
}
# "400" -> "400Regular", "700i" -> "700Bold_Italic"
variant() {
  local w="${1%i}" suffix=""
  [ "$w" != "$1" ] && suffix="_Italic"
  echo "$w$(weight_name "$w")$suffix"
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
tarball="$(npm view "$pkg" dist.tarball)"
curl -fsSL "$tarball" | tar -xz -C "$tmp"
available="$(cd "$tmp/package" && ls -d */ 2>/dev/null | tr -d / | tr '\n' ' ')"

IFS=, read -r -a wanted <<< "$weights"
for w in "${wanted[@]}"; do
  v="$(variant "$w")" || { echo "error: bad weight '$w'" >&2; exit 1; }
  [ -f "$tmp/package/$v/${ident}_$v.ttf" ] || {
    echo "error: $family has no $v. Available: $available" >&2; exit 1; }
done

cd "$dir"
if node -e "process.exit(require('./package.json').dependencies?.expo ? 0 : 1)" 2>/dev/null; then
  echo "==> Expo project: installing $pkg"
  # Output stays visible on purpose: a silent pnpm install looks exactly like a hang.
  npx expo install "$pkg" expo-font
  for w in "${wanted[@]}"; do
    v="$(variant "$w")"
    echo "font $w ${ident}_$v import { ${ident}_$v } from '$pkg/$v'"
  done
else
  echo "==> React Native CLI project: copying TTFs into assets/fonts"
  mkdir -p assets/fonts
  for w in "${wanted[@]}"; do
    v="$(variant "$w")"
    src="$tmp/package/$v/${ident}_$v.ttf"
    ps="$(python3 "$here/ttf-name.py" "$src")"
    cp "$src" "assets/fonts/$ps.ttf"
    echo "font $w $ps"
  done
  if [ ! -f react-native.config.js ]; then
    printf "module.exports = {\n  assets: ['./assets/fonts'],\n};\n" > react-native.config.js
  elif ! grep -q "assets/fonts" react-native.config.js; then
    echo "warn: add './assets/fonts' to the assets array in react-native.config.js" >&2
  fi
  npx -y react-native-asset
  echo "==> Linked. iOS: run 'cd ios && pod install' again; rebuild both platforms (fonts are native assets)."
fi
