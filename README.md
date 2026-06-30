# back_stack

**You own the back stack.**

Navigation is a `List` you own. **Push** adds, **pop** removes, the UI follows.
No `go` vs `push`. No route graph. No `RouterDelegate` ceremony. Your
destinations are plain Dart types — checked by the compiler.

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
stack.edit((keys) => keys.removeWhere(...)); // it's just a List
```

## Reach it from `context`

`NavDisplay` provides the stack to everything below it, so screens navigate the
way Flutter devs expect (`Navigator.of`, `GoRouter.of`) — no passing `stack`
down by hand:

```dart
onTap: () => BackStack.of(context).push(const Product(42)),
```

`BackStack.of(context)` doesn't subscribe by default (right for event handlers);
pass `listen: true` for a widget that should rebuild when the stack changes.

## Why

Flutter's navigation pain is well documented. `back_stack` answers each pain
with the same idea — the list is the single source of truth:

| Common pain (go_router / Navigator 2.0) | back_stack |
| --- | --- |
| `go` vs `push` confusion; behaves differently on web vs mobile | **One operation: mutate the list.** No split. |
| `extra` is `Object?` — not type-safe; objects break deep links | **Destinations are typed objects.** Arguments are compiler-checked fields. |
| `extra` JSON serialization causing multi-second nav delays | Plain typed stack; you control serialization. |
| Back stack is a black box you can't observe | **`stack.keys` is plain, observable data** — inspect, test, time-travel. |
| Redirect loops (`/login → /login → …`) | **`redirect` is a pure function** applied once over the proposed stack. Loop-proof. |
| 50-line route tables disconnected from screens | One `switch` next to your screens. |

System back, the Android predictive-back gesture, and the hardware back button
all flow back into the list automatically — you never wire that up.

## Web URLs, deep links & restoration — one codec

Everything URL-shaped is one small class: translate the stack ⇄ a `Uri`. The
stack stays the source of truth; the URL is just a projection of it. This gives
web URL sync, deep links, browser back/forward, OS back, and state restoration
together — and *you* decide what stack a deep link materializes (so a link can
layer on top of Home instead of nuking the stack).

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

final delegate = NavStackRouterDelegate(
  stack: NavStack.of(const Home()),
  codec: ShopCodec(),
  builder: (context, key) => /* your screen */,
);

MaterialApp.router(
  routerDelegate: delegate,
  routeInformationParser: const NavStackRouteInformationParser(),
  restorationScopeId: 'app', // survive process death
);
```

Under the Router the initial URL seeds the stack (that's what URL-driven means),
so make `decode(Uri(path: '/'))` return your `NavStack`'s initial destinations.

> **Tip:** give destinations that ride the URL value equality so a re-decode
> reuses the live screen instead of rebuilding it — mix in `EquatableNavKey` and
> list the identifying fields (`List<Object?> get props => [id];`), or use
> `freezed`/`equatable`.

## Auth gating without redirect loops

```dart
stack.redirect = (proposed) {
  final guarded = proposed.any((k) => k is Account);
  return (guarded && !isLoggedIn) ? [const Login()] : proposed;
};
```

A pure function applied **once** per change — it can't ping-pong the way a
URL-redirect engine does. (Use `stack.guard` instead when you only want to
*block* a change, not reroute it.)

## Awaiting a result

```dart
final picked = await stack.pushForResult<Color>(const ColorPicker());
// on the picker: stack.pop(Colors.indigo);
```

The future completes with the popped value — or `null` if the screen leaves any
other way (back, `replaceAll`, the stack being disposed). It never hangs.

## Status — all shipped, leak-tracked

Owned stack, rendering, **type-safe result passing**, and the **Router
integration** (URL sync, deep links, browser/OS back, restoration) — done, 25
tests green under `leak_tracker` plus `BackStack.of(context)`. See [doc/PHILOSOPHY.md](doc/PHILOSOPHY.md) for
how each Flutter leak/caveat is handled.

Still ahead: a `Map<Tab, NavStack>` multi-stack helper for bottom-nav with
per-tab history.

## Run the example

```bash
cd example && flutter run
```

A tiny shop: login resets the flow, typed product args, `popUntil`, and a live
inspector that shows the back stack as data as you navigate:

```
back stack: Catalog › Product › Cart
```
