# docs/design-spec.md template

Keep it short and scannable — the dev approves it in a minute, and the next import reads it. Update in place on later imports; don't create a second spec.

```markdown
# Design spec — <App name>

Source: <Figma link(s) / screenshots in docs/design/ / description from <date>>
Stack: <Expo SDK 58 · expo-router · StyleSheet>   ← from detect-project.sh

## Navigation

(auth)        Login → Register
(tabs)        Home · Search · Profile
stack         Detail          ← from Home list item
modal         —

Initial route: Login (mock: "Log in" goes straight to Home)

## Screens

| Screen | Route | Content | Status |
|---|---|---|---|
| Login | /(auth)/login | logo, email, password, primary button, "Forgot password" link | planned |
| Home | /(tabs) | greeting header, horizontal category chips, product card list | planned |
| ... | | | |

## Theme

Colors        primary #2563EB · primaryText #FFFFFF · background #FFFFFF · surface #F8FAFC
              text #0F172A · textMuted #64748B · border #E2E8F0 · danger #DC2626
Dark mode     yes / no
Typography    Inter 400/500/600/700 — display 32 · title 24 · heading 18 · body 16 · caption 13
Spacing       4-pt scale (4, 8, 12, 16, 24, 32, 48)
Radius        sm 6 · md 10 · lg 16 · full 999

## Special components

| Component | Library | Setup done | Left for the dev | Verified on |
|---|---|---|---|---|
| Delivery map | react-native-maps | Polyline route + markers from mocks, location permission text | Google Maps API key for Android builds | iOS, Android |

## Shared components

Button (primary, secondary, ghost) · TextField · Card · ListItem · Avatar · ScreenHeader

## Assets

logo.png (Figma) · empty-cart.png (Figma) · icons: home, heart, bag, bell, search (Iconly Bulk, SVG → src/components/icons)

## Data (mocked)

products, cart, profile: types/ → mocks/ → services/ → hooks/ (TanStack Query). Cart is mutable in memory (mutation hooks). Totals in utils/pricing.ts (tested).

## Open points

- Font guessed from screenshot (Inter) — confirm with designer
- Pressed/disabled button states not in design — derived from primary color
```

Status values: `planned` → `built` → `verified` (after Phase 5 comparison). `existing` marks screens that were in the app before the spec was started.

## Later imports

The spec covers the whole app, so a later import edits the same file:

- **Source:** add a line per import with its date and input (`2026-11-03 — Favorites & Order History, text description`). Keep the earlier lines.
- **Screens:** add rows with status `planned`; a screen without a design frame gets `— (text)` or `— (screenshot)` in the frame column. Update rows of existing screens you change (a placeholder replaced by a real screen).
- **Navigation:** redraw the whole tree with the new routes in place, not a separate tree for the feature.
- **Theme:** add new tokens, and a line mapping the new design's colors that were merged into existing tokens (`#C67C4F → primary`). Existing values stay unless the dev chose to change them.
- **Shared components, Data, Assets:** add to the lists; note components that moved or gained variants.
- **Open points:** remove the ones the new import resolves; add new ones.
