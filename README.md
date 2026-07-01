# back_stack

<p align="center"><strong>You own the back stack.</strong> Navigation is a <code>List</code> you push and pop — type-safe, observable, no route graph.</p>

<p align="center">
  <a href="https://pub.dev/packages/back_stack"><img src="https://img.shields.io/pub/v/back_stack.svg" alt="pub package"></a>
  <a href="https://github.com/AndroidPoet/back_stack/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="license"></a>
  <a href="https://github.com/AndroidPoet/back_stack"><img src="https://img.shields.io/badge/tests-43%20passing-brightgreen.svg" alt="tests"></a>
</p>

<p align="center"><img src="https://raw.githubusercontent.com/AndroidPoet/back_stack/main/doc/demo.gif" width="260" alt="back_stack demo"></p>

**Push** adds, **pop** removes, the UI follows. No `go` vs `push`. No route graph. No `RouterDelegate` ceremony. Destinations are plain Dart types, checked by the compiler.

```dart
// 1. Destinations are typed objects. Arguments are real, checked fields.
sealed class AppKey extends NavKey {}
class Home extends AppKey { const Home(); }
class Product extends AppKey { const Product(this.id); final int id; }

// 2. The back stack is a list you own.
final stack = NavStack.of(const Home());

// 3. Render it. NavDisplay watches the list and follows.
NavDisplay(
  stack: stack,
  builder: (context, key) => switch (key as AppKey) {
    Home()             => const HomeScreen(),
    Product(:final id) => ProductScreen(id: id),
  },
);

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
  back_stack: ^0.2.0
```

## Reach the stack from anywhere

`NavDisplay` provides the stack to every screen below it — no passing it down by hand:

```dart
onTap: () => BackStack.of(context).push(const Product(42)),
```

It doesn't subscribe by default (right for event handlers); pass `listen: true` to rebuild on change.

## Why

| Common pain (go_router / Navigator 2.0) | back_stack |
| --- | --- |
| `go` vs `push` confusion; differs web vs mobile | **One operation: mutate the list.** |
| `extra` is `Object?` — not type-safe | **Typed destinations**, compiler-checked args. |
| Back stack is a black box | **`stack.keys` is plain, observable data.** |
| Redirect loops (`/login → /login → …`) | **`redirect` is a pure function**, applied once. Loop-proof. |
| 50-line route tables away from screens | One `switch` next to your screens. |

## Features

- **Own the stack** — `push` / `pop` / `replaceAll` / `popUntil` / `edit`. It's just a `List`.
- **Results** — `await stack.pushForResult<Color>(picker)`; complete it with `pop(value)`. Never hangs.
- **Web & deep links** — one `NavStackCodec` (`Uri ⇄ List`) gives URL sync, browser back/forward, and *you* decide what a link materializes.
- **Auth gating** — `redirect` (pure transform) and `guard` (veto), applied once per change. Loop-proof.
- **Adaptive layout** — `NavListDetail` turns one stack into list-detail / panes on wide screens, a stack on phones.
- **Per-tab history** — `MultiNavStack` gives each bottom-nav tab its own persistent back stack.
- **Shared elements** — `Hero` transitions just work, including inside nested displays.
- **Custom transitions** — `TransitionPage` (fade / slideUp / scale), `DialogPage`, `SheetPage`.
- **Restoration** — `RestorableBackStack` survives process death without a URL.
- **Leak-safe** — leaving the stack disposes the route; the whole suite runs under `leak_tracker`.

## Web URLs & deep links

A codec translates the stack ⇄ a `Uri`; the stack stays the source of truth. It's just two `switch`es, so write them inline with `NavStackCodec.of` — no class to declare:

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

There is no `errorBuilder` and no "route not found" — destinations are typed and the `builder` switch is exhaustive, so **in-app navigation can't reach an unknown screen; that error class is gone at compile time.**

The only untyped input is a **deep link** from outside. `decode` there can throw (a junk `int.parse`) or return nothing. back_stack never crashes on it: if `decode` throws or returns empty, it uses `fallbackFor` instead — the `fallback` list above, or override `fallbackFor` to route to a dedicated `NotFound()` screen. So `decode` can parse optimistically without defensive guards.

## Auth gating, without loops

```dart
stack.redirect = (proposed) {
  final guarded = proposed.any((k) => k is Account);
  return (guarded && !isLoggedIn) ? [const Login()] : proposed;
};
```

A pure function applied **once** per change — it can't ping-pong like a URL-redirect engine.

## Bottom nav with per-tab history — on the web too

`MultiNavStack` keeps one back stack per tab; `MultiNavDisplay` renders them (pass `lazy: true` to build a tab only when first opened). For URL sync, deep links and browser back on a tabbed app, drive it from the Router with `MultiNavStackRouterDelegate` + a `MultiNavStackCodec` (the multi-tab siblings of `NavStackRouterDelegate` / `NavStackCodec`). To survive process death, wrap it in `RestorableMultiNavStack` — every tab's stack and the active tab come back.

## Known limitations

Honest edges, so nothing surprises you:

- **Custom `NavSceneHost` scenes rebuild across the breakpoint.** `NavListDetail` preserves each pane's `State` across the breakpoint (it gives every entry a stable `GlobalKey`, so screens are reparented, not rebuilt). A *custom* scene you write with `NavSceneHost` + your own `NavSceneStrategy` doesn't get that for free — wrap pane content in your own per-entry `GlobalKey` if you need it, or hoist the transient state above the display.
- **`BackStack.of<K>` is nearest-by-type.** When a parent and a nested child stack share the *same* key type `K`, a screen gets the innermost one. Give nested stacks **distinct `NavKey` subtypes** (e.g. `AppKey` vs `WizardKey`) — then `BackStack.of<AppKey>` and `BackStack.of<WizardKey>` are unambiguous, and it's more type-safe anyway. (To reach a `MultiNavStack` host from a tab screen — e.g. to switch tabs — use `MultiBackStack.of(context)`.)
- **`Hero` doesn't fly across a nested-`NavDisplay` boundary.** Each `NavDisplay` owns its own `HeroController`, so a shared-element flight works *within* one display, not between a parent screen and a child display's screen. This is structural to how Flutter's `Hero` matches endpoints per-`Navigator` — every router (go_router included) has the same limit.
- **Custom `TransitionPage`s don't get the iOS edge-swipe-back** (they're plain `PageRoute`s). Use `CupertinoPage` where you want the native swipe.
- **`redirect` is synchronous** by design (that's what makes it loop-proof). For async auth, point `refreshListenable` at your auth notifier and route to a loading screen; the redirect re-runs when auth resolves.

## Example

```bash
cd example && flutter run               # the shop demo
cd example && flutter run -t lib/pokedex.dart   # the Pokédex above
```

See [`doc/PHILOSOPHY.md`](doc/PHILOSOPHY.md) for how each Flutter navigation leak and caveat is handled.

## License

[MIT](LICENSE)
