# Migrating from go_router

back_stack and go_router solve the same problem from opposite ends. go_router
gives you a **route table** — a tree of paths the framework walks to figure out
which pages to show. back_stack gives you **the stack itself** — a `List` of
typed destinations you push and pop; the UI just renders the list.

So a migration is mostly *deleting* the route tree and its ceremony, and moving
navigation from "describe a path" to "change a list." This guide maps the pieces.

> The mental shift: in go_router the URL/path is the source of truth and the
> stack is derived. In back_stack the **stack is the source of truth** and the
> URL is a projection of it. That's what removes the `go` vs `push` question.

## At a glance

| go_router | back_stack |
| --- | --- |
| `GoRoute(path: '/product/:id', builder: ...)` | a typed destination `class Product extends AppKey { final int id; }` + one `..on<Product>(...)` |
| `GoRouter(routes: [...])` route tree | `NavStack<AppKey>` (a `List` you own) + a `NavEntries` map |
| `context.go('/product/42')` | `stack.replaceAll([Home(), Product(42)])` |
| `context.push('/product/42')` | `stack.push(Product(42))` |
| `context.pop()` | `stack.pop()` |
| `context.pushReplacement(...)` | `stack.replaceTop(...)` |
| `state.pathParameters['id']` / `state.extra` | `key.id` — a real, typed field (compiler-checked) |
| `redirect:` (can loop; runs repeatedly) | `redirect` (pure, runs once) + `guard` (veto) |
| async `redirect` | `AsyncRedirect` (loop-proof async gate) |
| `refreshListenable:` | `stack.refreshListenable` (same idea) |
| `ShellRoute` / `StatefulShellRoute` | `BackStackTabsApp` (one widget; `MultiNavStack` underneath) |
| `errorBuilder:` / "no route found" | `NavLinks.notFound` — in-app navigation is typed and can't reach an unknown screen; only the deep-link boundary is untyped |
| `GoRouter.of(context)` | `BackStack.of<AppKey>(context)` |
| `routerConfig` + `MaterialApp.router` | `BackStackApp(stack: ..., entries: ...)` (one widget) |
| deep links (via path matching) | `links:` — a `NavLinks` table (both directions at once); `onLink`/`toLink` closures for full control |
| `NavigatorObserver`s | `observers:` on `NavDisplay` |
| `redirectLimit`, `initialLocation` | not needed — no redirect loops to bound; the stack's initial value is the initial location |

## Routes table → NavLinks

The direct translation of a go_router routes list is a `NavLinks` table: one
entry per URL, declaring **both** directions at once (URL → key and key → URL).
It only translates — it never owns navigation; the stack stays the source of
truth.

**go_router:**

```dart
final router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (c, s) => const HomeScreen()),
    GoRoute(
      path: '/product/:id',
      builder: (c, s) => ProductScreen(id: int.parse(s.pathParameters['id']!)),
    ),
    GoRoute(
      path: '/search',
      builder: (c, s) => SearchScreen(q: s.uri.queryParameters['q'] ?? ''),
    ),
  ],
  errorBuilder: (c, s) => const NotFoundScreen(),
);
```

**back_stack** — the URL side becomes a `NavLinks` table (screens live in
`NavEntries`, see the next section):

```dart
final links = NavLinks<AppKey>()
  ..on<Home>('/', decode: (m) => const Home())
  ..on<Product>('/product/:id',
      decode: (m) => Product(m.integer('id')!),
      encode: (key) => {'id': key.id},
      parents: (key) => const [Home()])   // Back from a deep link goes Home
  ..on<Search>('/search',
      decode: (m) => Search(m.str('q') ?? ''),
      encode: (key) => {'q': key.q})      // not in the pattern → query param
  ..notFound((uri) => const [Home(), NotFoundScreen()]);

BackStackApp<AppKey>(stack: stack, entries: entries, links: links);
```

What you gain over the routes list: the key → URL direction (address bar,
shareable `links.linkFor(key)`) is declared in the same entry instead of being
derived implicitly, `parents:` makes the deep-link back stack explicit per
destination, and with `links:` set the **entire typed stack** is restored
across process death — not just the URL. `errorBuilder` becomes `notFound`.

## 1. Routes become typed destinations

**go_router** — paths and string parameters:

```dart
final router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (c, s) => const HomeScreen()),
    GoRoute(
      path: '/product/:id',
      builder: (c, s) => ProductScreen(id: int.parse(s.pathParameters['id']!)),
    ),
  ],
);
```

**back_stack** — a Dart type per destination, arguments as real fields:

```dart
// Not sealed, so each feature can live in its own file (see NavEntries).
abstract class AppKey extends NavKey { const AppKey(); }
class Home    extends AppKey { const Home(); }
class Product extends AppKey { const Product(this.id); final int id; }

final entries = NavEntries<AppKey>()
  ..on<Home>((context, key) => const HomeScreen())
  ..on<Product>((context, key) => ProductScreen(id: key.id)); // key.id is an int
```

`int.parse(...!)` is gone — `key.id` is already an `int`, checked by the compiler.
Prefer an exhaustive `switch (key)` over the `NavEntries` map when you want the
compiler to flag a destination you forgot to handle.

## 2. Navigation: describe a path → change a list

| Intent | go_router | back_stack |
| --- | --- | --- |
| Replace the stack (reset a flow) | `context.go('/home')` | `stack.replaceAll([const Home()])` |
| Push one screen | `context.push('/product/42')` | `stack.push(const Product(42))` |
| Pop | `context.pop()` | `stack.pop()` |
| Replace the top screen | `context.pushReplacement('/x')` | `stack.replaceTop(const X())` |
| Pop back to a screen | `context.go(...)` gymnastics | `stack.popUntil((k) => k is Home)` |
| Reuse an open screen (singleTop) | manual | `stack.pushOrMoveToTop(const Product(42))` |

The classic go_router headache — "does `go` replace or push? does it differ on
web vs mobile?" — doesn't exist here. There is one operation: **mutate the list.**

Reach the stack from any widget:

```dart
// go_router
onTap: () => context.push('/product/42'),
// back_stack
onTap: () => BackStack.of<AppKey>(context).push(const Product(42)),
```

## 3. Arguments: `extra` / path params → typed fields

go_router's `extra` is `Object?` (not type-safe) and path params are strings.
In back_stack the destination *is* the argument bundle:

```dart
// go_router
context.push('/checkout', extra: Cart(items));      // Object? — hope it's a Cart
final cart = state.extra as Cart;                    // cast, may throw

// back_stack
stack.push(Checkout(cart));                          // Checkout(this.cart) — typed
// in the builder: (context, key) => CheckoutScreen(cart: key.cart)
```

Deep-linkable arguments (ones that ride the URL) should have value equality so a
URL re-decode reuses the live screen — mix in `EquatableNavKey`:

```dart
class Product extends AppKey with EquatableNavKey {
  const Product(this.id);
  final int id;
  @override
  List<Object?> get props => [id];
}
```

## 4. Redirects and guards

go_router's `redirect` runs repeatedly and can loop (hence `redirectLimit`).
back_stack splits this into two loop-proof pieces:

```dart
// go_router
redirect: (context, state) {
  if (!loggedIn && state.matchedLocation.startsWith('/account')) return '/login';
  return null;
},

// back_stack — a pure transform, applied once per change
stack.redirect = (proposed) {
  final guarded = proposed.any((k) => k is Account);
  return (guarded && !loggedIn) ? [const Login()] : proposed;
};
```

- Compose several independent gates with `combineRedirects([...])`.
- Veto a specific transition (rather than rewrite it) with `guard`.
- Re-run the redirect when auth changes: point `stack.refreshListenable` at your
  auth `Listenable` (the direct analog of go_router's `refreshListenable`).

### Async redirects

go_router lets `redirect` be async; back_stack keeps `redirect` synchronous (that
sync guarantee is what makes it loop-proof) and gives you `AsyncRedirect` for the
async case — a permission call, a session refresh, a "does this document exist"
check for a deep link:

```dart
final gate = AsyncRedirect<AppKey>(
  check: (proposed) async {
    if (proposed.any((k) => k is Admin) && !await session.hasAdminAccess()) {
      return [const Login()]; // deny → bounce
    }
    return null;              // allow as proposed
  },
)..attach(stack); // wires redirect + refreshListenable in one call

// gate.resolving is a ValueListenable<bool> — drive a loading overlay from it.
```

The decision is cached per destination and the check runs once, so it can't loop.
Call `gate.invalidate()` after login/logout to force a re-check.

## 5. Nested navigation / bottom tabs

`StatefulShellRoute` and its branch ceremony → `BackStackTabsApp`, one widget:

```dart
BackStackTabsApp<AppKey>(
  tabs: [
    NavStack<AppKey>.of(const Feed()),
    NavStack<AppKey>.of(const Search()),
    NavStack<AppKey>.of(const Profile()),
  ],
  entries: entries,
  destinations: const [
    NavigationDestination(icon: Icon(Icons.home), label: 'Feed'),
    NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
    NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
  ],
  links: links, // optional: a link lands in the right tab automatically
);
```

Each tab keeps its own history across switches, system back pops the active tab
first, re-tapping the active tab pops to root, and with `links:` every tab's
stack plus the active tab survive process death. Pass `shell:` instead of
`destinations:` for your own chrome (the `ShellRoute` case).

Underneath it's `MultiNavStack`, which you can wire yourself for full control —
one back stack per tab, persistent across switches:

```dart
final host = MultiNavStack<TabKey>([
  NavStack.of(const Feed()),
  NavStack.of(const Search()),
  NavStack.of(const Profile()),
]);

Scaffold(
  body: MultiNavDisplay<TabKey>(host: host, builder: screenFor),
  bottomNavigationBar: ListenableBuilder(
    listenable: host,
    builder: (context, _) => NavigationBar(
      selectedIndex: host.index,
      onDestinationSelected: host.select, // re-tap active tab → pop to root
      destinations: const [/* ... */],
    ),
  ),
);
```

System back pops the active tab, then falls back to the first tab. A deep screen
switches tabs with `MultiBackStack.of<TabKey>(context).select(i)`. Add web URL
sync/deep links with `MultiNavStackRouterDelegate` + a `MultiNavStackCodec`.

## 6. Deep links and web URLs

The declarative path is the `NavLinks` table from
[Routes table → NavLinks](#routes-table--navlinks) above — pass it as
`BackStackApp(links: …)` and deep links, the address bar, browser back/forward
and full-stack restoration are done. Its `parents:` fixes the "a deep link
nukes my whole stack" problem per destination.

For full control, write the mapping yourself with `onLink`/`toLink` closures —
you decide what a link materializes (return `[Home(), Product(42)]` so Back
still goes Home, or just `[Product(42)]` to replace):

```dart
void main() => runApp(
  BackStackApp<AppKey>(
    stack: NavStack.of(const Home()),
    builder: entries.call,
    onLink: (uri) => switch (uri.pathSegments) {
      ['product', final id] => [const Home(), Product(int.parse(id))],
      _                     => [const Home()],
    },
    toLink: (stack) => switch (stack.last) {        // optional: web address bar
      Product(:final id) => Uri(path: '/product/$id'),
      _                  => Uri(path: '/'),
    },
    linkStream: AppLinks().uriLinkStream,           // optional: async native links
  ),
);
```

`onLink` may parse optimistically — a bad link falls back to `onLinkFallback`
(or `/`) instead of crashing, so there's no `errorBuilder` to write. Async links
from native (custom scheme, Firebase Dynamic Links, warm `app_links`) flow through
the same `onLink` via `linkStream`.

> **Cold-start ordering (bites go_router users too).** Whatever router you use,
> `app_links`' `uriLinkStream` only replays the launch URI to its first listener
> if the `AppLinks()` singleton exists when the OS delivers it. Create `AppLinks()`
> early — a top-level `final` or in `main()` — not lazily inside a widget, or the
> cold-start link is gone before anything subscribes. With `BackStackApp` you then
> just pass `appLinks.uriLinkStream` to `linkStream`.

## 7. What you can delete

- The route-tree list and every `path:` string.
- `int.parse(state.pathParameters[...]!)` and `state.extra as T` casts.
- `errorBuilder` / "unknown route" screens for in-app navigation (typed
  destinations can't reach an unknown screen; only the deep-link boundary is
  untyped, and it falls back).
- `redirectLimit` / redirect-loop worries.
- `context.go` vs `context.push` decisions.

## Gradual migration

You don't have to convert everything at once. `NavDisplay` is a normal widget, so
you can host a back_stack-driven subtree *inside* an existing go_router route
(give it a distinct key type) and migrate feature by feature. Or flip the root to
`BackStackApp` and port screens into `NavEntries` one `..on<T>()` at a time.

---

See the [README](../README.md) for the full API and
[`doc/PHILOSOPHY.md`](PHILOSOPHY.md) for how each Flutter navigation caveat is
handled. Runnable examples are under [`example/`](../example).
