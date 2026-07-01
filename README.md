# back_stack

<p align="center"><strong>You own the back stack.</strong> Navigation is a <code>List</code> you push and pop — type-safe, observable, no route graph.</p>

<p align="center">
  <a href="https://pub.dev/packages/back_stack"><img src="https://img.shields.io/pub/v/back_stack.svg" alt="pub package"></a>
  <a href="https://github.com/AndroidPoet/back_stack/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="license"></a>
  <a href="https://github.com/AndroidPoet/back_stack"><img src="https://img.shields.io/badge/tests-83%20passing-brightgreen.svg" alt="tests"></a>
</p>

<p align="center"><img src="https://raw.githubusercontent.com/AndroidPoet/back_stack/main/doc/demo.gif" width="260" alt="back_stack demo"></p>

**Push** adds, **pop** removes, the UI follows. No `go` vs `push`. No route graph. No `RouterDelegate` ceremony. Destinations are plain Dart types, checked by the compiler.

```dart
// 1. Destinations are typed objects. Arguments are real, checked fields.
//    Not sealed — each feature can live in its own file.
abstract class AppKey extends NavKey { const AppKey(); }
class Home    extends AppKey { const Home(); }
class Product extends AppKey { const Product(this.id); final int id; }

// 2. Map each destination to its screen. Add a screen = one line; split these
//    `..on<T>()` calls across feature files if you want (see example/multi_file).
final entries = NavEntries<AppKey>()
  ..on<Home>((context, key) => const HomeScreen())
  ..on<Product>((context, key) => ProductScreen(id: key.id));

// 3. The back stack is a list you own. NavDisplay watches it and follows.
final stack = NavStack<AppKey>.of(const Home());

NavDisplay<AppKey>(stack: stack, builder: entries.call);

// Navigate by changing the list:
stack.push(const Product(42));    // add
stack.pop();                      // remove
stack.replaceAll([const Home()]); // reset the flow (e.g. after login)
stack.popUntil((k) => k is Home); // unwind
```

System back, the Android predictive-back gesture, and the hardware back button all flow into the list automatically — you never wire that up.

## Install

```yaml
dependencies:
  back_stack: ^0.3.0
```

## Contents

- [Reach the stack from anywhere](#reach-the-stack-from-anywhere)
- [Why](#why) · [Features](#features)
- [Deep links — one function](#deep-links--one-function)
- [Web URLs & the codec (full control)](#web-urls--the-codec-full-control)
- [Results — await a pushed screen](#results--await-a-pushed-screen)
- [Auth gating, without loops](#auth-gating-without-loops) · [Async gating](#async-gating)
- [Bottom nav with per-tab history](#bottom-nav-with-per-tab-history--on-the-web-too)
- [Modular destinations & scoped cleanup](#modular-destinations--scoped-cleanup)
- [Reuse an open screen](#reuse-an-open-screen)
- [Debug the stack live](#debug-the-stack-live) · [Transitions](#transitions)
- [Known limitations](#known-limitations) · [Examples](#example)
- **[Migrating from go_router](doc/MIGRATING_FROM_GO_ROUTER.md)**

## Reach the stack from anywhere

`NavDisplay` provides the stack to every screen below it — no passing it down by hand:

```dart
onTap: () => BackStack.of<AppKey>(context).push(const Product(42)),
```

Pass the key type — `BackStack.of<AppKey>` — so the lookup finds *your* stack. It doesn't subscribe by default (right for event handlers); pass `listen: true` to rebuild on change.

## Why

| Common pain (go_router / Navigator 2.0) | back_stack |
| --- | --- |
| `go` vs `push` confusion; differs web vs mobile | **One operation: mutate the list.** |
| `extra` is `Object?` — not type-safe | **Typed destinations**, compiler-checked args. |
| Back stack is a black box | **`stack.keys` is plain, observable data.** |
| Redirect loops (`/login → /login → …`) | **`redirect` is a pure function**, applied once. Loop-proof. |
| 50-line route tables away from screens | A `NavEntries` map (or one `switch`) next to your screens. |

## Features

- **Own the stack** — `push` / `pop` / `replaceTop` / `replaceAll` / `popUntil` / `edit`. It's just a `List`.
- **A modular map, or one `switch`** — `NavEntries` (`..on<Home>(...)`) registers destinations across feature files; prefer an exhaustive `switch` when you want the compiler to flag a destination you forgot.
- **Cross-cutting decorators** — `NavEntryDecorator` wraps every screen (DI scope, providers, tracing) and calls back when an entry leaves the stack, so you can tear down a Bloc/controller scoped to a destination.
- **Results** — `await stack.pushForResult<Color>(picker)`; complete it with `pop(value)`. Never hangs.
- **Deep links, one function** — `BackStackApp(onLink: (uri) => [...])` maps a URL straight onto the stack. No `MaterialApp.router` boilerplate; *you* decide what a link materializes. Async links from native (custom scheme, dynamic links, warm `app_links`) flow through the same `onLink` via `linkStream`.
- **Auth gating** — `redirect` (pure transform) and `guard` (veto), applied once per change. Loop-proof. Split independent gates with `combineRedirects([...])`, or gate on an **async** check (permission call, session refresh) with `AsyncRedirect` — still loop-proof.
- **No duplicate screens** — `stack.pushOrMoveToTop(key)` reuses an open copy instead of stacking another; `moveToTop(test)` is the `clearTop` gesture.
- **Debug the stack** — drop in `BackStackInspector<K>()` to watch entries push/pop live (no DevTools setup — the stack is just data).
- **Adaptive layout** — `NavListDetail` turns one stack into list-detail / panes on wide screens, a stack on phones.
- **Per-tab history** — `MultiNavStack` gives each bottom-nav tab its own persistent back stack.
- **Shared elements** — `Hero` transitions just work, including inside nested displays.
- **Custom transitions** — `TransitionPage`: fade / slideUp / scale plus the full Material motion set (shared axis X/Y/Z, fade-through), `DialogPage`, `SheetPage`. All zero-dep.
- **Restoration** — `RestorableBackStack` survives process death without a URL.
- **Leak-safe** — leaving the stack disposes the route; the whole suite runs under `leak_tracker`.

## Deep links — one function

The whole deep-link setup is one widget and one function. `BackStackApp` bundles the `MaterialApp.router` + delegate + parser wiring; you write `onLink`, mapping an incoming `Uri` to the stack it should show:

```dart
void main() => runApp(
  BackStackApp<AppKey>(
    stack: NavStack.of(const Home()),
    builder: entries.call,
    onLink: (uri) {
      final s = uri.pathSegments;
      if (s.length == 2 && s.first == 'products') {
        return [const Home(), Product(int.parse(s[1]))]; // layer on Home
      }
      return [const Home()]; // also the launch URL '/'
    },
  ),
);
```

`onLink` may parse optimistically — if it throws or returns empty, `onLinkFallback` (or `/`) is shown instead of crashing. Pass `toLink: (stack) => Uri(...)` to also project the stack back onto the web address bar. Back (system + browser) flows into the list automatically; `restorationScopeId` is set by default so the stack survives process death.

### Async links from native

The platform hands `BackStackApp` the launch URL and the standard app links it resolves itself. Links that arrive **while the app is already running** — a custom scheme (`myapp://…`), a Firebase Dynamic Link, a warm `app_links` link — come from a native plugin as a `Stream<Uri>`. Pass that stream as `linkStream` and every emission runs through the *same* `onLink`:

```dart
final appLinks = AppLinks(); // from the app_links package — you own the plugin

BackStackApp<AppKey>(
  stack: NavStack.of(const Home()),
  builder: entries.call,
  onLink: (uri) => /* map Uri → stack */,
  linkStream: appLinks.uriLinkStream, // runtime links → same onLink, same fallback
);
```

back_stack stays dependency-free: it owns the `Uri` → stack mapping and the subscription lifecycle; you bring the `Uri`s from whatever plugin you prefer. Driving your own router instead? Call `delegate.handleLink(uri)` (on `NavStackRouterDelegate` or `MultiNavStackRouterDelegate`) — the imperative sibling of the platform's `setNewRoutePath`, with the same never-throws hardening.

For a bottom-nav app with per-tab history, or when you need full `MaterialApp` control, drop to `NavStackRouterDelegate` directly (below).

## Web URLs & the codec (full control)

Under the hood a codec translates the stack ⇄ a `Uri`; the stack stays the source of truth. `BackStackApp` builds one for you from `onLink`/`toLink`; reach for the codec directly when you want a reusable value or full `MaterialApp.router` control. It's just two `switch`es, so write them inline with `NavStackCodec.of` — no class to declare:

```dart
final codec = NavStackCodec<AppKey>.of(
  encode: (stack) => switch (stack.last) {
    Home()             => Uri(path: '/'),
    Product(:final id) => Uri(path: '/products/$id'),
    _                  => Uri(path: '/'),
  },
  decode: (uri) {
    final s = uri.pathSegments;
    if (s.length == 2 && s[0] == 'products') {
      final id = int.tryParse(s[1]);
      if (id != null) return [const Home(), Product(id)]; // layer on Home, not replace
    }
    return [const Home()];
  },
  fallback: [const Home()], // shown for a malformed / unknown link
);

MaterialApp.router(
  routerDelegate: NavStackRouterDelegate(
    stack: NavStack.of(const Home()),
    codec: codec,
    builder: (context, key) => /* your screen */,
  ),
  routeInformationParser: const NavStackRouteInformationParser(),
  restorationScopeId: 'app', // survive process death
);
```

Prefer a class? Extend `NavStackCodec` and override `encode`/`decode` — same thing, reusable value.

### Error handling — the one place a link can go wrong

There is no `errorBuilder` and no "route not found" — destinations are typed, so **in-app navigation can't reach an unknown screen.** With an exhaustive `switch` builder the compiler even names the destination you forgot to handle; with a `NavEntries` map the match is by runtime type, so an unregistered destination throws a clear `StateError` naming the type rather than rendering a blank route. Either way there's no untyped "route string" to mistype.

The only untyped input is a **deep link** from outside. `decode` there can throw (a junk `int.parse`) or return nothing. back_stack never crashes on it: if `decode` throws or returns empty, it uses `fallbackFor` instead — the `fallback` list above, or override `fallbackFor` to route to a dedicated `NotFound()` screen. So `decode` can parse optimistically without defensive guards.

## Results — await a pushed screen

Open a screen and `await` the value it sends back — no result channel, no callback threading. `pushForResult<T>` completes when that screen leaves the stack:

```dart
// Caller: open the picker, await the color it returns.
final color = await BackStack.of<AppKey>(context).pushForResult<Color>(
  const ColorPicker(),
);
if (color != null) setState(() => _swatch = color);

// The picker screen: pop the chosen value back to the awaiter.
onTap: () => BackStack.of<AppKey>(context).pop(pickedColor),
```

It completes with the value passed to `pop`, or `null` if the screen leaves any other way (back gesture, `replaceAll`, disposal) — it never hangs. `pop` takes an untyped `Object?`, so make the picker return the same `T` the caller expects. Runnable in `example/lib/results.dart`.

## Auth gating, without loops

```dart
stack.redirect = (proposed) {
  final guarded = proposed.any((k) => k is Account);
  return (guarded && !isLoggedIn) ? [const Login()] : proposed;
};
```

A pure function applied **once** per change — it can't ping-pong like a URL-redirect engine.

### Async gating

`redirect` is synchronous by design — that's what makes it loop-proof. When a gate needs to *await* (a permission call, a session refresh, a "does this deep-linked doc exist" check), reach for `AsyncRedirect`. It's built on the same primitives, so the core stays sync and loop-proof:

```dart
final gate = AsyncRedirect<AppKey>(
  check: (proposed) async {
    if (proposed.any((k) => k is Admin) && !await session.hasAdminAccess()) {
      return [const Login()]; // deny → bounce
    }
    return null;              // allow as proposed
  },
);
stack
  ..redirect = gate.call
  ..refreshListenable = gate;
```

While a check runs the stack stays put and `gate.resolving` (a `ValueListenable<bool>`) flips true — drive a loading overlay from it. The decision is cached per destination so the check runs once, not on every rebuild; call `gate.invalidate()` after login/logout to force a re-check. Runnable in `example/lib/guarded.dart`.

## Bottom nav with per-tab history — on the web too

`MultiNavStack` keeps one back stack per tab; `MultiNavDisplay` renders them (pass `lazy: true` to build a tab only when first opened):

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
      onDestinationSelected: host.select, // re-tap the active tab → pop to root
      destinations: const [/* ... */],
    ),
  ),
);
```

Each tab keeps its own history across switches; system back pops the active tab, then falls back to the first tab. A deep screen switches tabs with `MultiBackStack.of<TabKey>(context).select(i)`. For URL sync, deep links and browser back on a tabbed app, drive it from the Router with `MultiNavStackRouterDelegate` + a `MultiNavStackCodec` (the multi-tab siblings of `NavStackRouterDelegate` / `NavStackCodec`). To survive process death, wrap it in `RestorableMultiNavStack` — every tab's stack and the active tab come back. Runnable in `example/lib/tabs.dart`.

## Modular destinations & scoped cleanup

The exhaustive `switch` stays the default — the compiler tells you when a destination is unhandled. When one `switch` grows past comfort, register destinations as a map instead, composed across feature files:

```dart
final entries = NavEntries<AppKey>()
  ..on<Home>((context, key) => const HomeScreen())
  ..on<Product>((context, key) => ProductScreen(id: key.id));

NavDisplay(stack: stack, builder: entries.call);
```

To wrap every screen — a DI scope, a provider, request tracing — and tear it down when the destination leaves the stack, pass a `NavEntryDecorator`:

```dart
NavDisplay(
  stack: stack,
  builder: entries.call,
  decorators: [
    NavEntryDecorator(
      decorate: (context, key, child) =>
          ProviderScope(overrides: [scopeFor(key)], child: child),
      onRemoved: (key) => disposeScopeFor(key), // popped, replaced, or disposed
    ),
  ],
);
```

`decorate` runs on every build (first decorator is the outermost wrapper); `onRemoved` fires once when the entry is popped, replaced, or the whole display is disposed — the hook `State.dispose` can't give you for a *non-widget* object.

## Reuse an open screen

Sometimes you want to jump *back* to a screen that's already open instead of stacking another copy of it — the `singleTop` / `clearTop` gesture. It's just list surgery:

```dart
// If a Product is already on the stack, bring it to the top; else push it.
stack.pushOrMoveToTop(const Product(42));

// Or unconditionally pop back to the first screen matching a test (clearTop).
stack.moveToTop((k) => k is Home);
```

`pushOrMoveToTop` matches by `==` by default; pass `isSame:` to define your own "same destination" (e.g. same route, ignoring a query field).

## Debug the stack live

Because the stack is plain observable data, you can watch it without any DevTools plumbing — drop `BackStackInspector` anywhere below the display:

```dart
Stack(children: [
  yourApp,
  const Positioned(left: 8, bottom: 8, child: BackStackInspector<AppKey>()),
]);
```

It lists every entry bottom-to-top, marks the current one, and updates on every push/pop. Handy while you're wiring flows; delete the one line to remove it.

## Transitions

A destination's transition is just the `Page` you return from `pageBuilder` — no separate transition registry. `TransitionPage` covers the common ones plus the full Material motion set (all dependency-free, and the shared-axis / fade-through motions animate the *outgoing* screen too):

```dart
pageBuilder: (context, key, pageKey) => switch (key) {
  Step2()  => TransitionPage.sharedAxisHorizontal(key: pageKey, child: screenFor(key)), // peer step
  Detail() => TransitionPage.sharedAxisScaled(key: pageKey, child: screenFor(key)),     // into a hierarchy
  Tab()    => TransitionPage.fadeThrough(key: pageKey, child: screenFor(key)),          // unrelated switch
  Toast()  => TransitionPage.fade(key: pageKey, child: screenFor(key)),
  _        => MaterialPage(key: pageKey, child: screenFor(key)),                        // platform default
};
```

Pick the motion by the *relationship* between screens: **shared axis** (X forward-among-peers, Y vertical, Z into-a-hierarchy) implies a spatial link; **fade-through** is for unrelated destinations (e.g. tabs). A destination can also carry its own transition by mixing in `NavPage` — then you don't even need a `pageBuilder`. Runnable in `example/lib/motion.dart`.

## Known limitations

Honest edges, so nothing surprises you:

- **Custom `NavSceneHost` scenes rebuild across the breakpoint.** `NavListDetail` preserves each pane's `State` across the breakpoint (it gives every entry a stable `GlobalKey`, so screens are reparented, not rebuilt). A *custom* scene you write with `NavSceneHost` + your own `NavSceneStrategy` doesn't get that for free — wrap pane content in your own per-entry `GlobalKey` if you need it, or hoist the transient state above the display.
- **`BackStack.of<K>` is nearest-by-type.** When a parent and a nested child stack share the *same* key type `K`, a screen gets the innermost one. Give nested stacks **distinct `NavKey` subtypes** (e.g. `AppKey` vs `WizardKey`) — then `BackStack.of<AppKey>` and `BackStack.of<WizardKey>` are unambiguous, and it's more type-safe anyway. If you must keep the same type, `BackStack.parentOf<K>(context)` reaches the stack one level up — e.g. a child screen calling `BackStack.parentOf<AppKey>(context).pop()` pops the *outer* flow. (To reach a `MultiNavStack` host from a tab screen — e.g. to switch tabs — use `MultiBackStack.of(context)`.)
- **`Hero` doesn't fly across a nested-`NavDisplay` boundary.** Each `NavDisplay` owns its own `HeroController`, so a shared-element flight works *within* one display, not between a parent screen and a child display's screen. This is structural to how Flutter's `Hero` matches endpoints per-`Navigator` — every router (go_router included) has the same limit.
- **Custom `TransitionPage`s don't get the iOS edge-swipe-back** (they're plain `PageRoute`s). Use `CupertinoPage` where you want the native swipe.
- **`redirect` is synchronous** by design (that's what makes it loop-proof). For async auth, point `refreshListenable` at your auth notifier and route to a loading screen; the redirect re-runs when auth resolves.

## Example

```bash
cd example && flutter run                             # the shop demo
cd example && flutter run -t lib/multi_file/main.dart # simplest: destinations split across files
cd example && flutter run -t lib/pokedex.dart         # NavListDetail + Hero on a real API
cd example && flutter run -t lib/tabs.dart            # MultiNavStack — per-tab history
cd example && flutter run -t lib/results.dart         # pushForResult — await a pushed screen
cd example && flutter run -t lib/guarded.dart         # AsyncRedirect — async auth gating
cd example && flutter run -t lib/motion.dart          # Material motion transitions
cd example && flutter run -t lib/showcase.dart        # NavListDetail, one adaptive stack
cd example && flutter run -t lib/entries.dart         # NavEntries + NavEntryDecorator
```

New to back_stack from go_router? See **[Migrating from go_router](doc/MIGRATING_FROM_GO_ROUTER.md)**.

See [`doc/PHILOSOPHY.md`](doc/PHILOSOPHY.md) for how each Flutter navigation leak and caveat is handled.

## License

[MIT](LICENSE)
