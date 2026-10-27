# Input: Figma

**Contents:** Files you can't open: Community files and other people's files · Be frugal with calls · URL → ids · Translating the reference code · Assets · Fonts · Fallback: Figma in a browser

Preferred: the **Figma MCP server** connected in the dev's Claude Code (tools like `get_metadata`, `get_variable_defs`, `get_design_context`, `get_screenshot`). If it isn't connected, or it hits its rate limit (Starter / free plans allow only a handful of calls per month), use **Fallback: Figma in a browser** at the end of this file. Last resort: exported PNGs (`input-image.md`).

If a Figma design-to-code skill is available (e.g. `figma-design-to-code`, `figma-implement-design`, or the MCP resource `skill://figma/figma-design-to-code/SKILL.md`), load it before calling `get_design_context` — the Figma server expects it.

## Files you can't open: Community files and other people's files

Figma Community files (links under `figma.com/community/file/…`, or a `/design/` link to a community file) and files owned by someone else usually fail through the MCP with a permission error ("no access" / "can't edit"), even when the dev can view them in the browser. Handle it in one message, early, and keep the rest of the wizard moving:

1. Ask the dev to **duplicate** the file: open the link → *Open in Figma* / *Duplicate* (Community) or *File → Duplicate to your drafts* (shared file) → copy the new link (better: right-click the screens' frame or section → *Copy link to selection*, so it has a `node-id`). The duplicate is theirs, so the MCP can read everything.
2. If they'd rather not, offer the browser fallback below (view access may show fewer values), or exported PNGs.

While waiting for the new link, continue with whatever doesn't need the design — environment setup, scaffolding, running the empty app. Never stop the whole flow for it.

## Be frugal with calls

Figma MCP is rate-limited per plan, and Starter / View seats get very few calls per month. Plan the calls before making them:

1. `get_metadata` on the page (or on the file without `nodeId` to list pages) — **once** — to see all frames, their names and ids.
2. Pick the frames that are real screens (ignore components pages, archives, variants). Confirm the list with the dev if there are more than ~8.
3. `get_variable_defs` on one screen frame — **once** — gives the color/typography/spacing variables used. If the file has no variables, derive tokens from step 4.
4. `get_design_context` per screen frame — one call each. It returns reference code (web/React + Tailwind), a screenshot, and asset download URLs.
5. Only call `get_screenshot` if you need a larger image for comparison in Phase 5.

If a call fails with a rate-limit or permission error, run `whoami` to see the plan/seat, tell the dev, and switch to **Fallback: Figma in a browser** below — keep whatever the successful calls already returned.

## URL → ids

`https://www.figma.com/design/<fileKey>/<name>?node-id=12-345` → `fileKey=<fileKey>`, `nodeId=12:345`. Branch URLs `/design/<fileKey>/branch/<branchKey>/…` → use `branchKey`. A link without `node-id` → call `get_metadata` without `nodeId` to list pages.

## Translating the reference code

`get_design_context` returns **web** code. Treat it as a description of the design, never paste it:

| Web / Tailwind | React Native |
|---|---|
| `div` | `View` |
| text elements | `Text` (all text must be inside `Text`) |
| `img` | `Image` / `expo-image` |
| `flex` default row | RN default is **column**; set `flexDirection: 'row'` explicitly |
| `gap-4` | `gap: theme.spacing[4]` (RN supports `gap`) |
| `px`, `rem` | unitless numbers (1 px in Figma = 1 pt/dp) |
| `font-weight` | a `fontFamily` per weight (see `fonts.md`) |
| `box-shadow` | `boxShadow` style (RN 0.76+) or the theme's shadow tokens |
| absolute-positioned frames | prefer flex layout; use `position: 'absolute'` only for real overlays |
| fixed frame width (375/390) | `flex: 1` / percentage widths; screens must adapt to device size |

Replace raw values with tokens: if a Figma variable exists, its name becomes the token name (`color/primary/500` → `colors.primary500` or a semantic alias).

## Assets

Asset URLs returned by Figma expire — download them right away:

```bash
curl -fsSL "<url>" -o assets/images/<meaningful-name>.png
```

**Images** (photos, illustrations, map backgrounds) → PNG/JPEG in `assets/images/`. Figma hands them over at export size (product photos came back as 2–5 MB PNGs around 1800 px): resize to at most twice the largest size they're shown at (about 960 px for a full-width card) and save photos as JPEG (`sips -Z 960 -s format jpeg in.png --out out.jpg` on macOS). Keep PNG only for images with transparency.

**Icons → SVG, always — including standard glyphs** (home, heart, bag, search, chevron). The design's own icon set (Iconly, a custom set) is what the screens should show; an icon font only approximates it. Export every distinct icon once as SVG into `docs/design/icons/<name>.svg`, named after what it shows (`bag.svg`, `bean.svg`), not the layer id. Then generate components with `scripts/svg-icons.sh` (SKILL.md, Phase 4 step 3). Never put icons in `assets/` as PNG.

- **Figma MCP:** download the icon assets `get_design_context` lists, to `docs/design/icons/<name>.svg` when the asset is SVG (check the first bytes: `<svg`). If an icon only comes back as a raster image, export it through the browser route below or ask the dev. Three things the MCP's assets do that the icon frame doesn't:
  - They're the **inner vectors**, positioned by CSS insets in the reference code, not the 24 px icon frame: wrap each in an `<svg viewBox="0 0 24 24">` with a `<g transform="translate(x y)">` from those insets, and assemble icons made of several vectors (a phone with two parts) into one file.
  - **Rotation and flips live in CSS** (`rotate(90deg)`, `scaleX(-1)`): a chevron drawn once pointing down is used as left, right and up. Apply the transform in the SVG (or rotate the component) so each file points the way it's used, and check them in a screenshot.
  - Some "icons" are **raster masks** (a PNG shape filled with a color). There's no vector to export: ask the dev for SVGs (or the designer), and until then use the PNG tinted with `tintColor` from the theme, listed under Open points as the one exception to "icons are SVG".
- **Browser, file you can edit** (your own file, or the dev's duplicate of a Community file): Figma's Plugin API is available in the page as the global `figma`. Export each icon's top node (the instance or frame that is the whole icon, usually 16–32 px; not its inner vectors):
  ```js
  const node = await figma.getNodeByIdAsync('<node id>');
  await node.exportAsync({ format: 'SVG_STRING' });
  ```
  Collect the ids first (`figma.currentPage.findAll((n) => n.type === 'INSTANCE' && n.width <= 48)` and their `name`s show the icon set, e.g. `Iconly/Bulk/Home`), export one icon per call, and write each returned string to its `.svg` file.
- **View-only access, no plugin API:** ask the dev to select the icons in Figma and use *Export → SVG* (one click for many icons), then drop the files into `docs/design/icons/`.

Each icon's color in the design becomes the component's default; single-color icons are tinted with a theme token (`<BagIcon color={colors.primary} />`).

## Fonts

Figma gives exact family and weight. Google Font → `google-font.sh`. Otherwise ask the dev for the files.

## Fallback: Figma in a browser

When the MCP is unavailable or rate-limited, read the file in a browser instead. Figma's canvas is WebGL (not readable as HTML), but the **properties panel on the right is ordinary HTML**: select a layer and its exact values — hex colors, font family/style/size, line height, letter spacing, width/height, corner radius — can be read as text. Accuracy is close to the MCP; it costs no API calls; it's slower because each value needs a selection.

### Setup

1. Ask the dev which browser: **Claude in Chrome** (their own Chrome, usually already signed in to Figma) or the **built-in browser** (they sign in once; never type their credentials yourself).
2. Open the link. If Figma shows a sign-in page, stop and ask the dev to sign in, then continue.
3. Make the viewport large so frames are legible in screenshots: built-in browser `resize_window` 1600×1400 (reset to `desktop` when done); in Chrome, a maximized window is enough.
4. Paste `scripts/figma-panel.js` into the JavaScript tool once per page load. It defines `figmaPanel.read()`.

### Recipe (per file, not per layer)

1. **Frames** — read the layer list with the page-text tool. Top-level frames (e.g. `Login`, `Home`, `Product Detail`) are the screens. Duplicates and hidden copies (shown greyed / "Toggle layer visibility") are usually old versions — confirm with the dev if unclear.
2. **Per screen:** click the frame's name in the layer list (more reliable than clicking the canvas), press `Shift+2` (zoom to selection), wait ~1 s, take a screenshot → layout and content. Then `figmaPanel.read()` → frame size and its **Selection colors** (the whole palette used in that screen, in one read). If the panel shows "Selection colors" swatches with a `+N` and no hex values, click `+N` once, then read again.
3. **Text styles — one read per style, not per text layer.** Expand the frame in the layer list and click one text layer for each visual style you see (screen title, section heading, body, caption, button label, input placeholder). `figmaPanel.read()` returns `typography: [family, style]`, `Font size`, `Line height`, `Letter spacing`, `Color`.
4. **Components — one read per kind.** Click one primary button, one input, one card, one list row, one tab bar: `Width`/`Height`, corner radius (under `?`), `Color` (fill then stroke), `Stroke weight`. Auto-layout frames also expose padding and gap.
5. Later screens reuse the same styles: only read what looks new.

### Pitfalls seen in practice

- The panel renders lazily: wait ~1 s after selecting before reading, and read again if values look like the previous selection (`nodeId` in the result tells you what is selected).
- The selected row scrolls to the same place in the layer list, so consecutive clicks can land on the same coordinates — that's normal; verify with `nodeId` or a screenshot.
- Never type into the panel's inputs or press keys while a text field is focused (including Figma's AI "Ask for changes" box): you would edit the file. Press `Escape` and click empty canvas first.
- `Cmd+\` toggles Figma's whole UI and can take effect late. If the panels disappear, press `Escape`, click the canvas, press `Cmd+\` again.
- View-only access may show fewer properties. If values are missing, ask the dev for edit access or a duplicate of the file in their drafts.
- Font names come out exactly (`Montserrat`, `Medium`) → straight into `google-font.sh`.

Write what you read into `docs/design-spec.md` as you go (palette, type scale, component specs), then continue with Phase 3 as usual.
