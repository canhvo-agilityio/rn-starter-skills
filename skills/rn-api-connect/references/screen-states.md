# Loading, error and empty states

**Contents:** Shared components · In screens · Mutations · Checking them

With mocks these states never showed: data arrived instantly and always existed. With the API every screen that uses a connected hook (`usedBy` in the inventory) needs all three. This is the only change screens get from this skill — besides load-more on paginated lists.

## Shared components

If the project already has state components (an `EmptyState`, a `Loading`), use and extend them. Otherwise add three small ones to `src/components/`, on the theme (rn-ui `theme.md`), each with a test:

```tsx
// src/components/query-state.tsx — from a real run on rn-starter's StyleSheet theme
interface StateProps {
  style?: StyleProp<ViewStyle>;
}

interface ErrorStateProps extends StateProps {
  error: unknown;
  onRetry?: () => void;
}

interface EmptyStateProps extends StateProps {
  title: string;
  action?: ReactNode;
}

export const LoadingState = ({ style }: StateProps) => {
  const { colors } = useTheme();
  return (
    <View style={[styles.center, style]} accessibilityRole="progressbar" accessibilityLabel="Loading">
      <ActivityIndicator color={colors.primary} />
    </View>
  );
};

// A 4xx (not found, bad request) won't change on a retry, so no button for those.
const canRetry = (error: unknown) => !(error instanceof ApiError && error.status >= 400 && error.status < 500);

export const ErrorState = ({ error, onRetry, style }: ErrorStateProps) => (
  <View style={[styles.center, style]}>
    <ThemedText variant="body" color="textMuted" style={styles.text}>
      {errorMessage(error)}
    </ThemedText>
    {onRetry && canRetry(error) ? (
      <Button title="Try again" variant="outline" onPress={onRetry} style={styles.button} />
    ) : null}
  </View>
);

export const EmptyState = ({ title, action, style }: EmptyStateProps) => (
  <View style={[styles.center, style]}>
    <ThemedText variant="body" color="textMuted" style={styles.text}>
      {title}
    </ThemedText>
    {action}
  </View>
);

const styles = StyleSheet.create({
  center: { flexGrow: 1, alignItems: 'center', justifyContent: 'center', gap: spacing.four, padding: spacing.screen },
  text: { textAlign: 'center' },
  // Stretched: inside a centered column a button shrink-wraps, and its label can overflow the border.
  button: { alignSelf: 'stretch' },
});
```

(Adapt `useTheme`, `ThemedText`, `Button`, `spacing` and the style helper to the project's theme setup. Check the button on a screenshot: label inside its border.) Visible strings follow the app's language and existing UI text; if the app uses i18n, add keys instead of literals.

```ts
// src/utils/error-message.ts — what the user reads; ApiError.message is for logs and forms
import { ApiError } from '@/lib/api-error';

export const errorMessage = (error: unknown): string => {
  if (!(error instanceof ApiError)) return 'Something went wrong. Please try again.';
  if (error.status === 0) return 'No connection. Check your internet and try again.';
  if (error.status === 401 || error.status === 403) return 'Please sign in again.';
  if (error.status === 404) return 'This item is no longer available.';
  if (error.status >= 500) return 'Something went wrong on our side. Please try again.';
  return error.message;
};
```

Test `errorMessage` for each branch (`utils/__tests__/error-message.test.ts`).

## In screens

The whole screen depends on one query:

```tsx
const { data: coffee, isPending, error, refetch } = useCoffee(id);
if (isPending) return <LoadingState />;
if (error) return <ErrorState error={error} onRetry={() => refetch()} />;
```

`isPending` is TanStack Query v5's "no data yet"; use `isLoading` on v4. Put these lines in the screen's `hooks.ts` return value if the screen already keeps its data logic there, and branch in `index.tsx`.

**Several queries on one screen** (Home: profile, categories, coffees): states per section, not one spinner for the page. A failed profile shouldn't hide the coffee list; the header shows a placeholder, the list section shows its own error with retry.

**Lists:**

```tsx
<FlatList
  data={coffees}
  ListEmptyComponent={isPending ? <LoadingState /> : error ? <ErrorState error={error} onRetry={retry} /> : <EmptyState title="No coffee in this category yet" />}
  refreshControl={<RefreshControl refreshing={isPullRefreshing} onRefresh={refresh} />}
  onEndReached={loadMore}
  onEndReachedThreshold={0.5}
  ListFooterComponent={isFetchingNextPage ? <ActivityIndicator /> : undefined}
/>
```

With the handlers in the screen's `hooks.ts`:

```ts
// Only a pull shows the refresh spinner, not background refetches (isRefetching would).
const [isPullRefreshing, setPullRefreshing] = useState(false);
const refresh = useCallback(() => {
  setPullRefreshing(true);
  refetch().finally(() => setPullRefreshing(false));
}, [refetch]);
const retry = useCallback(() => { refetch(); }, [refetch]); // onPress/onRefresh expect void, refetch returns a Promise
const loadMore = useCallback(() => {
  if (hasNextPage && !isFetchingNextPage) fetchNextPage();
}, [fetchNextPage, hasNextPage, isFetchingNextPage]);
```

`ListFooterComponent` takes `undefined`, not `null`, in React Native 0.88's types.

Pull-to-refresh on lists the user expects to change (orders, notifications); skip it on static ones (categories). Load-more only on paginated hooks.

**Lists inside a `ScrollView`** (a grid rendered with `.map`, a horizontal chip row): states go where the list would be, as plain conditionals.

**Background refetch errors** (data on screen, a refetch failed): keep showing the data. Don't replace a working screen with an error.

## Mutations

The button that triggers it is disabled while `isPending`, and shows the error when it fails — the place depends on the UI: under the button, an inline message, or `Alert.alert` if the screen has nowhere to put it. Optimistic updates (favorites) roll back by themselves; still tell the user once that it didn't save.

## Checking them

`verify.md` → Error and empty states: each one is opened on purpose, not only read in code.
