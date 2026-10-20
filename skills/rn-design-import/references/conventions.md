# Default conventions (only when the project has none)

Existing code always wins: match its file naming, folder layout, export style and styling approach. Use these for anything the project hasn't decided — and for new projects, which use this layout from the start.

## Layout: feature-first

The full rationale and the ESLint rules that enforce it are in rn-starter's `references/structure.md`; this is the part you need while generating screens.

```
src/
  app/                       routes only — each file re-exports a screen
    (tabs)/index.tsx         export { HomeScreen as default } from '@/features/home';
    product/[id].tsx         export { ProductDetailScreen as default } from '@/features/product';
  features/<name>/
    screens/<x>-screen.tsx   the screens
    components/              UI used only by this feature
    api.ts                   data access — returns mocks until the API exists
    hooks.ts                 TanStack Query hooks over api.ts
    store.ts                 feature state, only if needed
    mocks.ts                 imported only by api.ts and tests
    types.ts                 domain types, shaped like the future API data
    <logic>.ts               pure logic (pricing, validation) with <logic>.test.ts
    index.ts                 public API — explicit named re-exports
  components/                shared UI used by 2+ features; never imports features
  components/icons/          icon components
  theme/                     tokens, useTheme, ThemedText
  lib/                       query client, http client, env
  utils/                     pure helpers
```

Deciding where something goes:

| It's… | Put it in |
|---|---|
| A screen | `features/<domain>/screens/` + a one-line route file in `app/` |
| UI used by one feature | `features/<domain>/components/` |
| UI used by 2+ features (button, card shell, rating stars) | `components/` |
| Data the screen shows (products, user, delivery status) | `features/<domain>/api.ts` → `hooks.ts`; mock in `features/<domain>/mocks.ts` |
| A calculation (totals, fees, discounts, validation) | `features/<domain>/<logic>.ts`, tested |
| A library-backed component (map, sheet, chart, player) | a wrapper in the owning feature's `components/` (`special-components.md`) |
| Session / signed-in user | `features/auth/` |
| Something used everywhere but not UI (query client, env access) | `lib/` |

Pick features by **domain** (coffee/product, order, delivery, auth), not by screen. A "home" feature is fine when the home screen composes other features and has its own pieces (header, banner).

Imports: other features and `app/` import a feature only through `@/features/<name>`; inside a feature use relative imports. Shared folders (`components/`, `theme/`, `lib/`, `utils/`) never import from `features/`.

## Naming

- Files: follow the project. Expo templates use kebab-case (`themed-text.tsx`); CLI projects often use PascalCase (`ProductCard.tsx`). New projects with no files of their own: kebab-case.
- Screens: `<name>-screen.tsx` exporting `<Name>Screen` (named export). Route files are the only default exports (expo-router requires them).
- Components and hooks: named exports.
- Mock data: `mockProducts`, typed with the interface from `types.ts`.

## Component checklist

- Typed props, `style` passthrough for one-off overrides.
- Uses `useTheme()` / theme tokens only.
- Pressables have `accessibilityRole="button"` and a label when there's no visible text.
- Lists use `FlatList` with `keyExtractor`, not `.map` in a `ScrollView`, when they can grow.
- Screens wrap content in a safe-area aware container (`SafeAreaView` from `react-native-safe-area-context`, or the template's screen component). Inside tab navigators use `edges={['top']}` and don't add `insets.top` by hand.

## Data seams

```ts
// src/features/product/api.ts
import { mockProducts } from './mocks';
import type { Product } from './types';

export async function getProducts(): Promise<Product[]> {
  // TODO: replace with API call
  return mockProducts;
}
```

```ts
// src/features/product/hooks.ts
import { useQuery } from '@tanstack/react-query';
import { getProducts } from './api';

export const useProducts = () => useQuery({ queryKey: ['products'], queryFn: getProducts });
```

Screens and components get data only through hooks — never by importing mocks. Then connecting the real API is a change to `api.ts` alone.

## Tests (when Jest + RNTL are installed)

Tests sit next to the file they test: `components/button.tsx` + `components/button.test.tsx`, `features/order/pricing.ts` + `pricing.test.ts`. Shared helpers (e.g. `renderWithProviders`) go in `src/test-utils.tsx` or a root `__tests__/utils.tsx`.

```tsx
// src/components/button.test.tsx
import { render, screen, userEvent } from '@testing-library/react-native';
import { Button } from './button';

test('shows its title and calls onPress', async () => {
  const user = userEvent.setup();
  const onPress = jest.fn();
  await render(<Button title="Add to cart" onPress={onPress} />);
  await user.press(screen.getByRole('button', { name: 'Add to cart' }));
  expect(onPress).toHaveBeenCalledTimes(1);
});
```

React Native Testing Library 14+ is async by default: `await render(...)`, and use `userEvent` (`await user.press/type`) rather than `fireEvent`. Query the way a user perceives the UI (`getByRole`, `getByText`), not by test IDs or style. Components that read the theme work as-is under `jest-expo`; if one needs a provider (navigation, safe area, query client), use a shared `renderWithProviders` helper instead of repeating setup.

What to test: every shared component (renders, main interaction), every logic file (all branches — that's where bugs cost money), and screens' key states once they handle loading/empty/error.

## Placeholder images

Random photo services give unrelated pictures (a mountain on a headphones card). Prefer, in order: assets from the design; a neutral placeholder with the product category icon on a `surface` background; or `https://placehold.co/600x600/png?text=Product` (deterministic). Note placeholders in Open points.

## Self-check before hand-off

```bash
npx eslint src                                   # includes the boundary rules if the project has them
grep -rn "mocks" src --include='*.tsx' | grep -v "\.test\." | grep -v "/api\.ts"   # must print nothing
find src/app -name '*.tsx' -exec wc -l {} + | sort -n | tail -5                     # route files should be tiny (layouts excepted)
```

If the project doesn't have the boundary rules yet and follows this layout, offer to add them (rn-starter `structure.md`).
