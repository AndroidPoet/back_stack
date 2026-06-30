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
  back_stack: ^0.1.0
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

One small class translates the stack ⇄ a `Uri`; the stack stays the source of truth.

```dart
class ShopCodec extends NavStackCodec {
  @override
  Uri encode(List<NavKey> stack) => switch (stack.last) {
    Home()             => Uri(path: '/'),
    Product(:final id) => Uri(path: '/products/$id'),
    _                  => Uri(path: '/'),
  };

  @override
  List<NavKey> decode(Uri uri) {
    final s = uri.pathSegments;
    if (s.length == 2 && s[0] == 'products') {
      return [const Home(), Product(int.parse(s[1]))]; // layer on Home, not replace
    }
    return [const Home()];
  }
}

MaterialApp.router(
  routerDelegate: NavStackRouterDelegate(
    stack: NavStack.of(const Home()),
    codec: ShopCodec(),
    builder: (context, key) => /* your screen */,
  ),
  routeInformationParser: const NavStackRouteInformationParser(),
  restorationScopeId: 'app', // survive process death
);
```

## Auth gating, without loops

```dart
stack.redirect = (proposed) {
  final guarded = proposed.any((k) => k is Account);
  return (guarded && !isLoggedIn) ? [const Login()] : proposed;
};
```

A pure function applied **once** per change — it can't ping-pong like a URL-redirect engine.

## Example

```bash
cd example && flutter run               # the shop demo
cd example && flutter run -t lib/pokedex.dart   # the Pokédex above
```

See [`doc/PHILOSOPHY.md`](doc/PHILOSOPHY.md) for how each Flutter navigation leak and caveat is handled.

## License

[MIT](LICENSE)
