# Hooks: queries, pagination, mutations

**Contents:** Paginated lists · Queries that wait for another · Mutations · Prefetch and detail from list · Without TanStack Query

Most hooks don't change: `useQuery({ queryKey, queryFn: getX })` works the same whether `getX` returns mocks or calls the API. Change a hook only for the three cases below. Keep the project's existing query keys — screens and other hooks may already invalidate them.

## Paginated lists

Only for list endpoints the plan marks as paginated. The service returns one page in an app type:

```ts
// src/types/page.ts
export interface Page<T> {
  items: T[];
  // What to ask for next: a page number, an offset or a cursor; null on the last page.
  next: number | string | null;
}
```

```ts
// src/services/coffees.ts — json-server style: ?_page=2&_per_page=10 → { data, next, pages, items }
export const getCoffeesPage = async (categoryId: string | undefined, page: number): Promise<Page<Coffee>> => {
  if (env.useMocks) {
    const all = categoryId ? mockCoffees.filter((c) => c.categoryId === categoryId) : mockCoffees;
    return { items: all, next: null };
  }
  const res = await unwrap(
    api.GET('/coffees', { params: { query: { category_id: categoryId, _page: page, _per_page: PAGE_SIZE } } }),
  );
  return { items: res.data.map((dto) => toCoffee(dto, env.apiUrl)), next: res.next ?? null };
};
```

Send the page parameter on every call, the first page too: some APIs (json-server) answer a plain array when it's missing, not the page wrapper the spec describes.

How `next` is computed depends on the API — write it from the spec's wrapper fields:

| API style | `next` |
|---|---|
| page + total pages (`{ items, page, totalPages }`) | `page < totalPages ? page + 1 : null` |
| page + "next" (`{ data, next }`) | `next` |
| offset + total (`{ items, offset, total }`) | `offset + items.length < total ? offset + items.length : null` |
| cursor (`{ items, nextCursor }`, `{ data, has_more }` + last id) | `nextCursor ?? null` / `has_more ? lastItem.id : null` |
| plain array, page + limit params | `items.length === PAGE_SIZE ? page + 1 : null` |
| Spring `Page` (`{ content, number, last }`) | `last ? null : number + 1` (Spring pages start at 0 — `initialPageParam: 0`) |

```ts
// src/hooks/use-coffees.ts
export const useCoffees = (categoryId?: string) =>
  useInfiniteQuery({
    queryKey: ['coffees', categoryId],
    queryFn: ({ pageParam }) => getCoffeesPage(categoryId, pageParam),
    initialPageParam: 1,
    getNextPageParam: (last) => (typeof last.next === 'number' ? last.next : undefined),
    // Screens keep receiving a flat array in `data`.
    select: (data) => data.pages.flatMap((page) => page.items),
  });
```

With `select`, `data` is still `Coffee[]`, so the screen's rendering doesn't change; it gains `fetchNextPage`, `hasNextPage` and `isFetchingNextPage` for load-more (`screen-states.md`). Cursor APIs: `pageParam` is a string, `initialPageParam: undefined as string | undefined`, `getNextPageParam: (last) => last.next ?? undefined`.

Keep the old `getCoffees` if other callers need the whole list (loop over pages until `next` is null) (e.g. favorites joining by id); otherwise replace it.

## Queries that wait for another

A query that needs another's result (coffees of the first category, once categories have loaded) takes `enabled`:

```ts
export const useCoffees = (categoryId?: string, { enabled = true }: { enabled?: boolean } = {}) =>
  useInfiniteQuery({ /* … */ enabled });

// in the screen hook
const categoryId = selectedCategoryId ?? categories[0]?.id;
const coffeesQuery = useCoffees(categoryId, { enabled: categoryId !== undefined });
```

Two traps, both seen in a real run:
- **A disabled query stays `isPending` forever.** If categories come back empty, `categoryId` stays undefined and a screen that shows a spinner on `isPending` spins forever. Derive the screen's loading flag from both: `categoriesQuery.isPending || (categoryId !== undefined && coffeesQuery.isPending)`, and show the empty state when there's nothing to wait for.
- **`refetch()` ignores `enabled`.** A retry button calling `coffeesQuery.refetch()` without a category fetches the unfiltered list. Guard it: `if (categoryId !== undefined) refetchCoffees()`.

## Mutations

Each mutation in the plan lists what it changes. After it succeeds, invalidate those queries so every screen showing them refetches:

```ts
export const usePlaceOrder = () => {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: placeOrder,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['orders'] });
      queryClient.invalidateQueries({ queryKey: ['order-quote'] });
    },
  });
};
```

A mutation hook that already updates the cache optimistically (the mutable-mock pattern from rn-ui: `onMutate` → `setQueryData`, `onError` → roll back, `onSettled` → invalidate) stays as it is — only the service function behind it changes. The rollback now matters: on an API error the heart goes back and the screen should say why (`screen-states.md` → Mutations).

**A mutation that reads before it writes** (removing a favorite needs the favorite's own id, so the service lists favorites first, then DELETEs) races when the user taps twice quickly: the second call reads a list the first hasn't changed yet. Run those one at a time with a mutation scope — TanStack Query queues mutations that share a scope id:

```ts
return useMutation({
  // setFavorite reads the list before it writes: a quick second tap must wait for the first.
  scope: { id: 'favorites' },
  mutationFn: ({ coffee, favorite }: SetFavoriteInput) => setFavorite(coffee.id, favorite),
  // … onMutate / onError / onSettled as before
});
```

Make the write idempotent too: POST only when the item isn't there yet; DELETE every match.

Mutations that need auth while sign-in doesn't exist yet stay mocked unless the plan sets up sign-in first (`auth.md`).

## Prefetch and detail from list

When a list endpoint already returns everything the detail screen shows, seed the detail query so it opens instantly:

```ts
const queryClient = useQueryClient();
// in the list screen's press handler, before navigating
queryClient.setQueryData(['coffee', coffee.id], coffee);
```

Only when the list item is the full object — otherwise the detail screen briefly shows partial data.

## Without TanStack Query

If the dev declined it, keep the project's hooks and add what the screens now need: `isLoading`, `error`, `refetch`.

```ts
export const useCoffee = (id: string) => {
  const [state, setState] = useState<{ data?: Coffee; error?: ApiError; isLoading: boolean }>({ isLoading: true });
  const load = useCallback(() => {
    setState((s) => ({ ...s, isLoading: true, error: undefined }));
    getCoffee(id).then(
      (data) => setState({ data, isLoading: false }),
      (error) => setState({ error, isLoading: false }),
    );
  }, [id]);
  useEffect(load, [load]);
  return { ...state, refetch: load };
};
```

No cache, no retry, no invalidation: after a mutation, call the affected hooks' `refetch`. Tell the dev this is the trade-off.
