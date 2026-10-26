# Input: screenshots / mockup images

## Get exact values, don't eyeball colors

```bash
python3 "<skill-dir>/scripts/palette.py" design.png --top 12      # dominant colors + share
python3 "<skill-dir>/scripts/palette.py" design.png --at 120,340  # exact color at a point
```

Look at the image, find the element you care about (primary button, background, card, text), read its approximate pixel position (image pixels, not scaled), and sample it with `--at`. Background and surface colors are usually the top entries of the dominant list; brand color is typically a high-saturation entry with a small share.

Text colors are anti-aliased; sample the thickest part of a heading, or use the darkest dominant entry close to the text hue.

`palette.py` needs Python 3. A clean Windows has none (`python3` opens the Microsoft Store): read colors from the image yourself and say they're approximate, or offer to install Python (`winget install Python.Python.3.12`). macOS has it once the Command Line Tools are installed.

## Measure

Screenshots are usually @2x or @3x. Determine the scale from the image width: 1170/1179/1206/1290 px wide → iPhone @3x (390–430 pt); 750/828 → @2x; Android 1080 px → ~@2.6x (411 dp). Divide pixel measurements by the scale to get RN units, then snap to the spacing scale (4/8 grid) — consistent spacing beats replicating a designer's 13 px.

Type sizes: measure cap height or line height in pixels, divide by scale, round to the nearest step of the type scale in `theme.md`.

## Fonts

You can't read a font name from pixels. Look at distinguishing glyphs (a, g, R, t, digits) and offer 2–3 closest Google Fonts in `AskUserQuestion`, plus "I'll tell you the font". Common matches:

| Looks like | Candidates |
|---|---|
| Neutral geometric/grotesque UI (iOS-like) | Inter, Roboto, Manrope |
| Rounded friendly | Nunito, Quicksand, Poppins |
| Geometric with circular o, single-storey a | Poppins, Montserrat, Outfit |
| Vietnamese marketing / brand | Be Vietnam Pro, Lexend |

System font look (SF Pro / Roboto) → use the platform default (no custom font) and say so.

## Multiple screenshots

Process them all before writing the spec: tokens are only reliable when the same color/size shows up on several screens. Name each screen from its content (title bar, tab label), confirm names in the spec.

## Limits to state in the spec

Hidden states (pressed, disabled, errors), scroll content below the fold, and animations aren't visible — build reasonable defaults and list them under "Open points".
