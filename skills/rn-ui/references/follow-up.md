# Adding a feature to an app that already has screens

Read this when the project already has screens — `docs/design-spec.md` exists, or detect-project finds screens and a theme. The new design is a feature inside an app people already use: everything already built keeps working and keeps looking the same, unless the dev asks otherwise.

## Spec

- Update `docs/design-spec.md` in place (`spec-template.md` → Later imports). No spec yet but the app has screens: start the spec by recording what exists — current navigation tree, theme tokens, shared components, data domains — with status `existing`, then add the new screens. The approval summary then shows the dev where the feature fits.
- Show the dev only what changes: new screens and where they hang in the navigation, new or changed tokens, new or changed shared components.

## Questions

- The app's theme and fonts are decided. Don't ask for a primary color, light/dark or a font again; a new font only comes up when the new design visibly uses one.
- Colors in the new design go through `theme.md` → Colors from a later design. Mapping to existing tokens is the default; ask only for colors that are close to a token but visibly different.

## Reuse before you create

| The new screens need… | Do |
|---|---|
| UI that already exists in `components/` | use it; add a variant or prop when the design needs one (`Button` gains `outline`), keep existing props and defaults unchanged |
| UI that lives inside one existing screen (`screens/order/components/mode-switch.tsx`) | move it to `components/` under a generic name, update the old screen's import, give it a test |
| Data from a domain that already has a hook (`useCoffees`) | use that hook, or add a function to the same service; never a second mock of the same data |
| A domain served by a real API (the service calls `fetch` or an HTTP client, not `mocks/`) | use its hook as it is; if the new screen needs a field or endpoint the API doesn't have, list it under Open points instead of adding a mock beside the real call |
| State that several screens change (favorites, cart, read flags) | a mutable mock in the service, written through a mutation (`conventions.md` → Data that screens change) |
| New mock records in an existing domain | add them only when the new screens need them, and note in the hand-off which existing screens now show more data |

Keep the data shapes of existing types: add optional fields rather than renaming or removing ones existing screens read.

## Changes that reach existing screens

Track every existing file you touch outside the new screens: tokens, shared components, layouts, navigation, services, mocks. For each one, list the existing screens that use it (`grep -rl "<ComponentName>\|<tokenName>" src/screens src/app`).

Those screens go into Phase 5 too: open them on every target and compare with their screenshots or design frames from the earlier import (`docs/design/`, the spec's frame column). A shared component that looks right on the new screen and shifted by 2 pt on an old one is the usual regression.

## Hand-off

Besides the new screens, tell the dev which existing screens changed and why (moved component, new variant, more mock data), and that they were re-verified.
