# Flutter philosophy & how back_stack honors it (and where the leaks hide)

This is the design rationale for `back_stack`. It records the parts of Flutter's
model that *constrain* a navigation library, the concrete memory-leak traps in
Flutter navigation, and — for each — whether `back_stack` solves it for you, hands
it to you, or has it on the roadmap.

## Flutter's model, in five principles

1. **Widgets are immutable, throwaway config. State lives in the Element tree.**
   A `Widget` (and a `Page`) is a cheap declaration rebuilt as often as every
   frame. Mutable state lives in the persistent Element/`State` behind it.
   → *back_stack:* a `NavKey` is exactly this — a cheap, immutable, `const`
   description of a destination. It holds *arguments*, never live state. The live
   state is the screen's `State`, owned by Flutter behind the route.

2. **UI = f(state); `build()` must be pure.** No side effects in build.
   → *back_stack:* `NavDisplay` maps the stack to a `pages` list as a pure
   function. Navigation happens by mutating `NavStack` from event handlers, never
   from inside `build`.

3. **Identity is `runtimeType + key` (`Page.canUpdate`).** Get the key wrong and
   Flutter reuses the wrong `State` (stale form/scroll) or throws State away.
   → *back_stack:* every stack entry carries a **stable, unique** id; the page key
   is `ValueKey(entry.id)`. Identical destinations (two `Detail(5)`) get distinct
   ids, so their State never collides. This is the single most important
   correctness invariant in a declarative router, and it's handled for you.

4. **State has a lifecycle; `dispose()` frees what `initState` created.** When a
   route leaves the stack, Flutter disposes its `State`, which must release its
   controllers/subscriptions.
   → *back_stack:* removing an entry removes the page, so Flutter tears the route
   down and your screen's `dispose()` runs. Proven by a test that asserts a
   screen's `State.dispose()` fires on pop.

5. **Dispose what you create; never dispose what you're handed.**
   → *back_stack:* `NavStack` is a `ChangeNotifier` — **you create it, so you
   dispose it.** Do it in the `State` that owns it. (The example app and every
   widget test do exactly this; leak tracking enforces it.)

## The navigation leak/caveat catalog

| # | Trap | Status in back_stack |
|---|------|---------------------|
| 1 | **Page key collisions** → wrong/lost State | **Solved by design.** Unique id per entry; duplicate keys are independent slots. |
| 2 | **Regenerating keys rebuilds everything** (UniqueKey-per-build, naive `replaceAll`) | **Solved.** `replaceAll`/`edit` *reconcile* against the current stack and reuse ids, so survivors keep their State; only changed screens rebuild, only removed ones dispose. |
| 3 | **Screen controllers/subscriptions not freed on leave** | **Solved at the route level** — leaving the stack disposes the route. *Your part:* dispose your own controllers in *your* `State.dispose()`. |
| 4 | **`onPopPage` deprecated** | **Solved.** Uses `onDidRemovePage`. |
| 5 | **System / hardware back desync** | **Solved for the common case** (NavDisplay as the app's navigator): framework pops sync back into the list automatically. |
| 6 | **ChangeNotifier listener leaks** | **Solved internally** — `NavDisplay` uses `ListenableBuilder`, which removes its own listener. *Your part:* if you `addListener` to the stack manually, `removeListener` in dispose. |
| 7 | **Disposing the notifier you don't own / forgetting the one you do** | *Your part, enforced:* dispose the `NavStack` you create. `leak_tracker` in the test suite fails the build if you forget. |
| 8 | **`setState`/`notifyListeners` during build** | **Avoided.** The stack is only mutated from event handlers and from the post-removal `onDidRemovePage` callback, not during build. |
| 9 | **`BuildContext` across async gaps** | *Your part:* guard with `context.mounted`. back_stack never *requires* `context` to navigate — you hold the `NavStack` directly (or read it once via `BackStack.of`), which removes the most common reason people touch a stale context. |
| 10 | **GlobalKey misuse / unstable navigatorKey** | **Avoided.** back_stack uses no GlobalKeys and no app-level navigatorKey. |

## URL sync, deep links, OS back, restoration — shipped

`NavStackRouterDelegate` + `NavStackRouteInformationParser` + a user
`NavStackCodec` (`Uri ⇄ List<NavKey>`) under `MaterialApp.router` give:

- **Web URL sync** — `currentConfiguration` projects the stack to a `Uri`; the
  URL updates on every push/pop. The stack, not a delegate, is the source of
  truth — so the "router rebuilt during build loses the URL" class of bugs
  (e.g. under a Riverpod `ProviderScope`) doesn't apply.
- **Deep links** — `decode(uri)` returns the *full stack you want*, so you choose
  layer-vs-replace instead of a link always nuking the stack.
- **OS / predictive back** — `popRoute` (via `PopNavigatorRouterDelegateMixin` +
  a stable `navigatorKey`) routes through the inner `Navigator`'s `maybePop`, so
  a `PopScope` or open dialog gets first chance before the stack pops.
- **State restoration** — `restoreRouteInformation` + `restorationScopeId`
  restores the URL (hence the stack) across process death.

Design note: under the Router the **initial URL seeds the stack**, so make
`decode(Uri(path: '/'))` reproduce your `NavStack`'s initial destinations.

## Result passing — shipped

`pushForResult<T>` returns a `Future<T?>`; `pop([result])` completes it. Every
dropped entry's future is completed (with `null`) the moment it leaves the stack
— including on `dispose` — so an `await` never hangs and no completer is
retained.

## Known caveats / your responsibility

- **Nested navigators without the Router.** If you put a `NavDisplay` *inside*
  another navigator (e.g. per-tab stacks) and you're **not** using
  `NavStackRouterDelegate`, wrap it so root back gestures reach the inner stack:

  ```dart
  NavigatorPopHandler(
    onPop: (_) => innerStack.pop(),
    child: NavDisplay(stack: innerStack, builder: ...),
  )
  ```

  For "confirm before leaving", use `PopScope(canPop: false,
  onPopInvokedWithResult: ...)` on the screen — predictive back needs the
  decision *before* the gesture, so don't decide asynchronously at pop time.

- **App-scoped lifetime.** Create the `NavStack` once (app/root State or the
  delegate), not inside a widget that rebuilds. Recreating it resets navigation —
  the same footgun as recreating a `GoRouter`.

- **Your screens still own their resources.** back_stack guarantees the *route* is
  disposed; it can't dispose controllers you forgot to release in your screen.

## Roadmap

- **Multi-stack helper** — `Map<Tab, NavStack>` for bottom-nav with per-tab
  history and predictive-back wired.

## Verifying no leaks yourself

- The suite runs under `leak_tracker_flutter_testing` (see
  `test/flutter_test_config.dart`) — any undisposed notifier/controller fails the
  test.
- In an app: DevTools → Memory; push then pop a screen repeatedly and confirm
  instance counts return to baseline.
- Lints worth enabling: `use_build_context_synchronously` (core) and DCM's
  `dispose-fields`.
