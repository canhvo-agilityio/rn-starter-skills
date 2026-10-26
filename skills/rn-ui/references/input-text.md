# Input: a plain-language description

Example: *"App has 5 screens: Login, Home, Search, Detail, Profile"*.

## Infer before asking

Screen names usually imply both content and position in the navigation. Use these defaults and present them as the recommended answer, so the dev only corrects what's wrong:

| Name looks like | Default role | Default content |
|---|---|---|
| Splash, Onboarding, Welcome | before auth, shown once | logo / carousel + CTA |
| Login, Sign in, Register, Forgot password, OTP | auth stack | form + primary button + secondary links |
| Home, Feed, Dashboard | first tab | header + list/cards from mock data |
| Search, Explore, Discover | tab | search field + results list + empty state |
| Cart, Orders, Notifications, Messages, Inbox | tab (or stack from Home if 5+ tabs) | list + item rows + empty state |
| Profile, Account, Me | last tab | avatar + info rows + logout |
| Settings | stack (pushed from Profile) | grouped rows with toggles/chevrons |
| Detail, Product, Post, Item, `[X] detail` | stack, pushed from a list | hero image + title + body + action |
| Checkout, Payment, Edit X, Create X | stack or modal | form + submit |

Tabs: 2–5. With more candidates than that, keep the most frequently used as tabs and push the rest.

## Ask when

- Names carry no meaning ("A, B, C", "Screen1"): ask in plain text what each screen shows and how the user gets there. Don't guess.
- It's unclear whether there's authentication.
- There's no visual direction and the project has no theme yet (an app with screens already has one — reuse it, `follow-up.md`): ask primary color (offer 3 swatches + "you choose"), light/dark/both, and font (default **Inter**; for Vietnamese-heavy UIs suggest **Be Vietnam Pro**).

One `AskUserQuestion` call holds at most 4 questions: put navigation shape, primary color, light/dark and font in it; anything else becomes a line in the spec the dev can correct at approval.

## Result

A navigation tree and a one-line content description per screen in the spec. Layouts follow common platform patterns with generous spacing; the theme uses the chosen primary color plus neutral grays derived from `theme.md`'s default scale.
