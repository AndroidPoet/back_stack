# back_stack

<p align="center"><strong>You own the back stack.</strong> Navigation is a <code>List</code> you push and pop — type-safe, observable, no route graph.</p>

<p align="center">
  <a href="https://pub.dev/packages/back_stack"><img src="https://img.shields.io/pub/v/back_stack.svg" alt="pub package"></a>
  <a href="https://github.com/AndroidPoet/back_stack/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="license"></a>
  <a href="https://github.com/AndroidPoet/back_stack"><img src="https://img.shields.io/badge/tests-136%20passing-brightgreen.svg" alt="tests"></a>
  <a href="https://androidpoet.github.io/back_stack"><img src="https://img.shields.io/badge/docs-site-blue.svg" alt="docs"></a>
</p>

<p align="center"><img src="https://raw.githubusercontent.com/AndroidPoet/back_stack/main/doc/demo.gif" width="260" alt="back_stack demo"></p>

## A whole app in 20 lines

```dart
// Destinations are plain Dart types — real, compiler-checked arguments.
abstract class AppKey extends NavKey { const AppKey(); }
class Home    extends AppKey { const Home(); }
class Product extends AppKey { const Product(this.id); final int id; }

// One line per screen.
final entries = NavEntries<AppKey>()
  ..on<Home>((context, key) => const HomeScreen())
  ..on<Product>((context, key) => ProductScreen(id: key.id));

// The back stack is a list you own.
final stack = NavStack<AppKey>.of(const Home());

void main() => runApp(BackStackApp<AppKey>(stack: stack, entries: entries));
```

Navigate by changing the list — from anywhere, no context gymnastics:

```dart
stack.push(const Product(42));    // forward
stack.pop();                      // back
stack.replaceAll([const Home()]); // reset a flow (e.g. after login)
// or from a widget: BackStack.of<AppKey>(context).push(const Product(42));
```

That's the entire model. System back, predictive back, and the hardware
button already flow into the list. Everything below is **one parameter** on
`BackStackApp` — the wiring is internal.

## Install

```yaml
dependencies:
  back_stack: ^0.4.0
```

## Deep links & web URLs — one table

Declare each URL **once**, both directions. Deep links, the address bar,
browser back/forward, shareable links, and state restoration all derive from
this single table — they can never drift apart:

```dart
final links = NavLinks<AppKey>()
  ..on<Home>('/', decode: (m) => const Home())
  ..on<Product>('/products/:id',
      decode: (m) => Product(m.integer('id')!),
      encode: (key) => {'id': key.id},
      parents: (key) => const [Home()])   // Back from a deep link goes Home
  ..notFound((uri) => const [Home(), NotFoundScreen()]);

BackStackApp<AppKey>(stack: stack, entries: entries, links: links);
```

`:id` is a path parameter, extra `encode` entries become query parameters,
`*rest` catches the tail. A malformed or unknown link lands on your
`notFound` stack — never a crash. `links.linkFor(Product(42))` gives you the
share URL.

Need to *fetch* before deciding what a link shows? Add `onLinkAsync` — newer
links supersede in-flight ones automatically:

```dart
BackStackApp<AppKey>(..., links: links,
  onLinkAsync: (uri) async =>
      await docExists(uri) ? null : const [Home(), NotFoundScreen()]);
```

## Survives process death — already on

With `links` set, the **entire typed stack** (not just the URL) is saved and
restored across Android process death. There is nothing to enable. Screens
without a URL are skipped; to restore those too, pass a `restoreWith` codec.

## Tabs — one widget

Bottom navigation with a live back stack per tab, back handled
innermost-first, re-tap pops to root:

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
  links: links, // optional: links land in the right tab automatically
);
```

Want your own bar or scaffold? Pass `shell:` instead of `destinations:`.

## Await a screen's result

```dart
final color = await stack.pushForResult<Color>(const ColorPicker());
// on the picker: stack.pop(Colors.indigo);
```

The future **never hangs** — if the screen leaves any other way (back
gesture, replace, redirect) it resolves `null`. A mistyped result fails at
the `pop` call site in debug, not as a cast error later.

## Auth gating — loop-proof, sync or async

```dart
// Sync rule: a pure function, applied once per change. No redirect loops.
stack.redirect = (proposed) =>
    proposed.any((k) => k is Account) && !isLoggedIn ? [const Login()] : proposed;

// Async rule (session check, permission call): one attach, nothing else.
final gate = AsyncRedirect<AppKey>(
  check: (proposed) async =>
      proposed.any((k) => k is Admin) && !await session.isAdmin()
          ? [const Login()] : null,
)..attach(stack);
// after login/logout: gate.invalidate();
```

Blocking *leaving* a screen: `stack.popGuard` (sync), `stack.popGuardAsync` +
`tryPop()` (async), or `ConfirmPopScope` around the screen for the system
back gesture.

## Dialogs, sheets & transitions — per destination

A destination can carry its own presentation. No `pageBuilder` switch:

```dart
entries.on<ConfirmDelete>(
  (context, key) => const ConfirmDeleteContent(),
  page: (context, key, child, pageKey) =>
      DialogPage<void>(key: pageKey, builder: (_) => AlertDialog(content: child)),
);
```

`DialogPage`, `SheetPage`, and `TransitionPage` (Material shared-axis, fade
through, slide, scale…) are included. Dialogs pushed this way are real stack
entries: back dismisses them, the URL can track them.

## Analytics — in your types

```dart
NavStackObserver<AppKey>(stack,
  onScreen: (key) => analytics.logScreen('${key.runtimeType}'));
```

## Why a list?

| Common pain (go_router / Navigator 2.0) | back_stack |
| --- | --- |
| `go` vs `push` confusion | **One operation: mutate the list.** |
| `extra` is `Object?`, breaks web refresh | **Typed destinations**, URL table restores the real stack. |
| The stack is a black box | **`stack.keys` is plain observable data** — inspect it, test it with a plain `expect`. |
| Redirect loops | Redirects are **pure functions applied once per change**. |
| Tab state loss, shell ceremony | **One widget**, per-tab stacks that never die. |
| Deep link + auth + cold start races | Ordered internally; async gates hold navigation until resolved. |
| Restoration restores only the URL | **Full typed stack** survives process death. |

Testing is the same story — no harness, no mocks:

```dart
stack.push(const Product(1));
expect(stack.keys, [const Home(), const Product(1)]);
```

## Going deeper

The [docs site](https://androidpoet.github.io/back_stack) covers the rest:
custom codecs and `RouterDelegate`-level control, native link plugins
(`app_links` cold-start ordering), adaptive layouts (`NavListDetail`, scenes),
modular multi-package setups, the live `BackStackInspector`, known
limitations, and the **[migration guide from go_router](doc/MIGRATING_FROM_GO_ROUTER.md)**.

## Example

Ten runnable demos in [`example/`](example/lib): `flutter run example/lib/main.dart`
(shop with a links table), `tabs_app.dart` (tabs in one widget), `tabs.dart`
(tabs by hand), `guarded.dart`, `results.dart`, `motion.dart`, `pokedex.dart`
(adaptive list-detail + Hero), `modular_demo.dart`, and more.
Live web demo: [androidpoet.github.io/back_stack/demo](https://androidpoet.github.io/back_stack/demo/).

## License

MIT © [AndroidPoet](https://github.com/AndroidPoet)
