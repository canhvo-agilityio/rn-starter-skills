# Default conventions (only when the project has none)

Existing code always wins: match its file naming, folder layout, export style and styling approach. Use these for anything the project hasn't decided — and for new projects, which use this layout from the start.

## Layout: layered

The full rationale and the ESLint rules that enforce it are in rn-starter's `references/structure.md`; this is the part you need while generating screens.

```
src/
  app/                          routes only — each file re-exports a screen
    (tabs)/index.tsx            export { HomeScreen as default } from '@/screens/home';
    product/[id].tsx            export { ProductDetailScreen as default } from '@/screens/product-detail';
  screens/<name>/
    index.tsx                   the screen — export const ProductDetailScreen = () => …
    components/                 UI used only by this screen
    hooks.ts                    the screen's own state and handlers, only if needed
    types.ts / utils.ts         only if needed
    __tests__/                  index.test.tsx, utils.test.ts
  components/                   shared UI used by 2+ screens; button.tsx or product-card/index.tsx
    icons/                      icon components generated from the design's SVGs (svg-icons.sh) + index.ts
  hooks/                        shared hooks — use-products.ts wraps services/ with TanStack Query
  services/                     data access — products.ts returns mocks until the API exists
  mocks/                        mock data, imported only by services/ and tests
  stores/                       app state (Zustand), only if needed
  types/                        domain types, shaped like the future API data
  constants/                    app-wide constants
  theme/                        tokens, useTheme, ThemedText (theme.md)
  lib/                          query client, http client, env
  utils/                        pure logic and helpers (pricing, validation, format)
```

Deciding where something goes:

| It's… | Put it in |
|---|---|
| A screen | `screens/<name>/index.tsx` + a one-line route file in `app/` |
| UI used by one screen | `screens/<name>/components/` |
| UI used by 2+ screens (button, card shell, rating stars) | `components/` — when a new screen needs UI from another screen's `components/`, move it here (`follow-up.md`) |
| Data that one screen changes and others show (favorites, cart) | a mutable mock in `services/` + a mutation hook (Data seams → Data that screens change) |
| Data a screen shows (products, user, delivery status) | `services/<domain>.ts` → `hooks/use-<domain>.ts`; mock in `mocks/<domain>.ts`; type in `types/<domain>.ts` |
| A calculation (totals, fees, discounts, validation) | `utils/<logic>.ts`, tested |
| An icon | `components/icons/<name>.tsx`, generated from its SVG by `svg-icons.sh`; never a PNG in `assets/` |
| A library-backed component (map, sheet, chart, player) | a wrapper in `components/` (`special-components.md`) |
| Session / signed-in user | `stores/auth.ts` (or `services/auth.ts` + a hook when it comes from an API) |
| Infrastructure used everywhere but not UI (query client, env access) | `lib/` |

Imports: use the `@/` alias across folders (`@/components/button`, `@/hooks/use-products`) and relative imports inside one screen folder (`./components/order-summary`). UI files never import `services/` or `mocks/`; shared folders never import `screens/`.

## Naming and code style

- **Files and folders: kebab-case** (`product-card.tsx`, `use-products.ts`, `screens/product-detail/`), as in the Expo templates. Follow the project when it already uses another style.
- A simple component is one file (`components/button.tsx`). A component with its own subcomponents becomes a folder with `index.tsx` and a `components/` folder inside, so the import path doesn't change.
- **Components are arrow functions with named exports**, props (when there are any) typed with an `interface` named after the component:
  ```tsx
  interface ProductCardProps {
    product: Product;
    onPress: (id: string) => void;
    style?: StyleProp<ViewStyle>;
  }

  export const ProductCard = ({ product, onPress, style }: ProductCardProps) => { … };
  ```
- Screens export `<Name>Screen` (`export const CartScreen = () => …`). Route files are the only default exports (expo-router requires them).
- Hooks: `use-<name>.ts` exporting `useName`. Services: plain async functions (`getProducts`). Mock data: `mockProducts`, typed with the interface from `types/`.
- Constants: `UPPER_SNAKE_CASE` (`MAX_CART_ITEMS`). Magic numbers in a component become a named constant at the top of the file.
- Styles live at the bottom of the component file, written the way the project's theme setup expects (`theme.md`): with plain StyleSheet, a module-level `StyleSheet.create` for layout and tokens, plus `createThemedStyles` for colors (built once per scheme); with Unistyles, `StyleSheet.create((theme) => …)`; with NativeWind, `className`; with a UI library, its components and theme.
- Comments explain *why* something is done, not what the next line does.

## Component checklist

- Typed props, `style` passthrough for one-off overrides.
- Uses `useTheme()` / theme tokens only.
- Pressables have `accessibilityRole="button"` and a label when there's no visible text.
- Screens wrap content in a safe-area aware container (`SafeAreaView` from `react-native-safe-area-context`, or the template's screen component). Inside tab navigators use `edges={['top']}` and don't add `insets.top` by hand.
- **Lists** use `FlatList` (or `SectionList`) with `keyExtractor`, not `.map` in a `ScrollView`, when they can grow. The item is a `memo` component, and `renderItem` / `keyExtractor` are stable (`useCallback` or defined outside the component), so scrolling doesn't re-render every row:
  ```tsx
  const ProductRow = memo(({ product, onPress }: ProductRowProps) => { … });

  const renderItem = useCallback(
    ({ item }: ListRenderItemInfo<Product>) => <ProductRow product={item} onPress={openProduct} />,
    [openProduct],
  );
  ```
- **Forms**: a screen with text inputs keeps the focused input above the keyboard and lets taps through while the keyboard is open. Use `KeyboardAwareScrollView` from `react-native-keyboard-controller` if the project has it; otherwise `KeyboardAvoidingView` (`behavior={Platform.OS === 'ios' ? 'padding' : undefined}`) around a `ScrollView` with `keyboardShouldPersistTaps="handled"`. Check it on Android too: with edge-to-edge (default from Expo SDK 54), `behavior="height"` often leaves the input hidden.
- **Android back**: a screen that can lose unsaved input (a form, a multi-step flow) asks before leaving — the hardware back button and the back gesture as well as the header button. With React Navigation / expo-router use the `beforeRemove` listener (`usePreventRemove` in React Navigation 7), which covers all three; plain `BackHandler` only covers the hardware button. Return the subscription's `remove()` from the effect.

## Data seams

```ts
// src/services/products.ts
import { mockProducts } from '@/mocks/products';
import type { Product } from '@/types/product';

export const getProducts = async (): Promise<Product[]> => {
  // TODO: replace with API call
  return mockProducts;
};
```

```ts
// src/hooks/use-products.ts
import { useQuery } from '@tanstack/react-query';

import { getProducts } from '@/services/products';

export const useProducts = () => useQuery({ queryKey: ['products'], queryFn: getProducts });
```

Screens and components get data only through hooks — never by importing services or mocks. Then connecting the real API is a change to `services/` alone.

Mocks import only types, never other mocks (the boundary rules reject it). When one domain's data refers to another's (favorites are coffee ids, an order line names a coffee), keep ids in the mock and join them in the service, which may call another service.

### Data that screens change

Favorites, a cart, read flags: one screen writes, others show it at once. Don't keep it in a screen's `useState` (other screens can't see it) and don't invent a store for mock data. The service holds the mock in a module variable, standing in for the server, and the hook writes through a mutation that updates the query cache first:

```ts
// src/services/favorites.ts
import { mockFavoriteIds } from '@/mocks/favorites';
import type { Coffee } from '@/types/coffee';

import { getCoffees } from './coffees';

// Stands in for the server until the favorites API exists: kept in memory, reset on reload.
let favoriteIds = [...mockFavoriteIds];

// TODO: replace with API calls (GET /favorites, PUT / DELETE /favorites/:coffeeId)
export const getFavorites = async (): Promise<Coffee[]> => {
  const coffees = await getCoffees();
  return favoriteIds.flatMap((id) => coffees.find((c) => c.id === id) ?? []);
};

export const setFavorite = async (coffeeId: string, favorite: boolean): Promise<void> => {
  const others = favoriteIds.filter((id) => id !== coffeeId);
  favoriteIds = favorite ? [coffeeId, ...others] : others;
};
```

```ts
// src/hooks/use-favorites.ts
const FAVORITES_KEY = ['favorites'] as const;

export const useFavorites = () => useQuery({ queryKey: FAVORITES_KEY, queryFn: getFavorites });

// Same cache, so the heart on Detail and the Favorites tab never disagree.
export const useIsFavorite = (coffeeId?: string) =>
  useQuery({ queryKey: FAVORITES_KEY, queryFn: getFavorites, select: (list) => list.some((c) => c.id === coffeeId) });

// Updates the cached list before the call returns, so every screen changes at once.
export const useSetFavorite = () => {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ coffee, favorite }: { coffee: Coffee; favorite: boolean }) => setFavorite(coffee.id, favorite),
    onMutate: async ({ coffee, favorite }) => {
      await queryClient.cancelQueries({ queryKey: FAVORITES_KEY });
      const previous = queryClient.getQueryData<Coffee[]>(FAVORITES_KEY);
      queryClient.setQueryData<Coffee[]>(FAVORITES_KEY, (list = []) => {
        const others = list.filter((c) => c.id !== coffee.id);
        return favorite ? [coffee, ...others] : others;
      });
      return { previous };
    },
    onError: (_error, _input, context) => queryClient.setQueryData(FAVORITES_KEY, context?.previous),
    onSettled: () => queryClient.invalidateQueries({ queryKey: FAVORITES_KEY }),
  });
};
```

Connecting the API later replaces the two service functions; hooks and screens stay. Without a query library, the same service sits behind the project's store (`stores/`) instead.

## Tests (when Jest + RNTL are installed)

Tests go in a `__tests__/` folder beside the code they test, named after the file: `components/__tests__/button.test.tsx`, `utils/__tests__/pricing.test.ts`, `screens/cart/__tests__/index.test.tsx`. Shared helpers (e.g. `renderWithProviders`) go in `src/test-utils.tsx`.

```tsx
// src/components/__tests__/button.test.tsx
import { render, screen, userEvent } from '@testing-library/react-native';

import { Button } from '../button';

test('shows its title and calls onPress', async () => {
  const user = userEvent.setup();
  const onPress = jest.fn();
  await render(<Button title="Add to cart" onPress={onPress} />);
  await user.press(screen.getByRole('button', { name: 'Add to cart' }));
  expect(onPress).toHaveBeenCalledTimes(1);
});
```

React Native Testing Library 14+ is async by default: `await render(...)`, and use `userEvent` (`await user.press/type`) rather than `fireEvent`. Query the way a user perceives the UI (`getByRole`, `getByText`), not by test IDs or style. Components that read the theme work as-is under `jest-expo`; if one needs a provider (navigation, safe area, query client), use a shared `renderWithProviders` helper instead of repeating setup.

What to test: every shared component (renders, main interaction), every logic file in `utils/` (all branches — that's where bugs cost money), and screens' key states once they handle loading/empty/error.

## Projects on the older feature-first layout

Projects made with rn-starter 1.x may use `src/features/<domain>/` (`structure: "feature-first"` in `.rn-starter.json`, `src/features/*/index.ts` present). Keep that layout there: screens in `features/<domain>/screens/<name>-screen.tsx` exported from the feature's `index.ts`, data in the feature's `api.ts` → `hooks.ts` with `mocks.ts`, logic in the feature; other code imports a feature only through `@/features/<name>`. Don't migrate it unasked.

## Placeholder images

Random photo services give unrelated pictures (a mountain on a headphones card). Prefer, in order: assets from the design; a neutral placeholder with the product category icon on a `surface` background; or `https://placehold.co/600x600/png?text=Product` (deterministic). Note placeholders in Open points.

## Self-check before hand-off

```bash
npx eslint src                                   # includes the boundary rules if the project has them
grep -rln "@/mocks\|@/services" src --include='*.tsx' | grep -v __tests__   # must print nothing
find src/app -name '*.tsx' -exec wc -l {} + | sort -n | tail -5              # route files should be tiny (layouts excepted)
```

If the project doesn't have the boundary rules yet and follows this layout, offer to add them (rn-starter `structure.md`).
