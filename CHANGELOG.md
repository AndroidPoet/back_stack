## 0.1.1

- Docs: the demo GIF now uses an absolute URL so it renders on the pub.dev
  package page (a relative path inside a raw `<img>` tag wasn't rewritten).

## 0.1.0

- Fix: `Hero` (shared-element) transitions now animate inside a nested
  `NavDisplay` — e.g. under `NavListDetail` or `MaterialApp(home:)`. Each display
  drives its own `HeroController` via a `HeroControllerScope`, so a sprite
  *flies* between screens instead of snapping. Previously only the root/Router
  display inherited one. Regression-tested.

## 0.0.1

- Adaptive layout: `NavListDetail` (one stack → two-pane on wide, animated stack
  on narrow) and the general `NavSceneHost` + `NavSceneStrategy` engine
  (`listDetailScene`, `supportingPaneScene`) — Compose Nav3 "scenes" over one list.
- Multi-stack: `MultiNavStack` + `MultiNavDisplay` give a bottom-nav persistent
  per-tab back stack (`IndexedStack`), with innermost-first system back.
- Custom pages: `TransitionPage` (`.fade`/`.slideUp`/`.scale`/`.none`),
  `DialogPage`, `SheetPage`, and a per-key `NavPage` mixin so a destination
  declares its own transition.
- `ConfirmPopScope`: async confirm-before-leave covering the Android system back.
- `RestorableBackStack` + `NavKeyCodec`: full-stack restoration across process
  death without a URL.
- `NavDisplay.nested` flag routes the system back gesture into a nested stack.
- Minimal rebuilds: pages are memoized by entry id, so one push rebuilds exactly
  one screen regardless of stack depth (see `benchmark/`).
- `popGuard` (sync pop veto) and `refreshListenable` (re-run `redirect` on auth
  change) on `NavStack`.
- `NavStack`: the back stack you own. push / pop / replaceTop / replaceAll /
  popUntil / edit. `BackStack.of(context)` reaches it from a screen (auto-provided by NavDisplay).
- Auth gating: `redirect` (pure transform, applied once — loop-proof) and `guard`
  (veto). 
- `NavDisplay`: renders the stack via the Pages API; system / predictive /
  hardware back sync into the list automatically (`onDidRemovePage`).
- `NavKey`: type-safe destinations as plain Dart objects. `EquatableNavKey` mixin
  gives them value equality so a URL re-decode reuses the live screen.
- Identity & State preservation: stable unique id per entry (unique page key);
  duplicate destinations are independent; `replaceAll`/`edit` reconcile so
  survivors keep their State and only changed screens rebuild.
- Result passing: `pushForResult<T>()` -> `Future<T?>`, completed by
  `pop([result])` or null on any other removal / dispose (never hangs/leaks).
- Router integration: `NavStackRouterDelegate` + `NavStackRouteInformationParser`
  + a `NavStackCodec` (`Uri <-> List<NavKey>`): web URL sync, deep links (you
  choose layer-vs-replace), browser/OS/predictive back, and state restoration.
- Leak-safe: leaving the stack disposes the route (proven by test); suite runs
  under `leak_tracker_flutter_testing`. 42 tests + benchmarks, analyze clean
  under `very_good_analysis` (strict casts/inference/raw-types).
- Docs: `doc/PHILOSOPHY.md` maps Flutter's model + the nav leak/caveat catalog.
