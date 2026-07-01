## 0.2.8

- **Async deep links from native.** The platform's `Router` only surfaces the
  launch URL and standard app links it resolves itself. Links that arrive *while
  the app runs* — a custom scheme (`myapp://…`), a Firebase Dynamic Link, a warm
  `app_links` link — come from a native plugin as a `Stream<Uri>`. `BackStackApp`
  now takes an optional **`linkStream`**: hand it that stream and every emission
  runs through the same `onLink`, with the same never-throws fallback as a
  platform link. back_stack owns the subscription lifecycle and cancels it on
  dispose; you bring the `Uri`s from whatever plugin you use — no new dependency.
- **`NavStackRouterDelegate.handleLink(uri)` / `MultiNavStackRouterDelegate.handleLink(uri)`** —
  the imperative sibling of `setNewRoutePath`, for driving your own router: apply
  a runtime link to the stack with the identical decode-or-fallback hardening.
  (`setNewRoutePath` now delegates to it, so platform and runtime links share one
  code path.)

## 0.2.7

A correctness + documentation pass. No API changes — every fix is behavior that
matches what the docs already promised.

- **Fix — `NavListDetail` no longer crashes when a lone detail is on top on a
  wide screen.** Previously, if the only (or first) entry was itself a *detail*
  type, it was mounted in both panes under the same per-entry `GlobalKey` and
  threw a duplicate-key error. It now shows as the list pane with an empty detail
  pane. Regression-tested.
- **Fix — `NavEntryDecorator.onRemoved` is now symmetric across the breakpoint in
  `NavListDetail`.** `onRemoved` fires only for entries that were actually rendered
  (as a wide pane or a narrow page), so a wide-only middle entry that was never
  shown no longer gets a spurious `onRemoved` with no matching `decorate`.
- **Fix — `MultiNavStack.handleBack` consumes back even when a `popGuard` vetoes
  the pop.** With history in the active tab, back is now treated as handled (so the
  app stays open) instead of surfacing the vetoed pop's `false` to the host
  `PopScope` — which would have closed the app.
- **Hardening — an empty stack is refused rather than crashing in release.** A
  `redirect`/`replaceAll` that resolves to no destinations is caught by an assert
  in debug and, in release, declined (the current stack stays) instead of leaving
  the `Navigator` with an empty pages list.
- **Examples:** adds `example/lib/tabs.dart` (`MultiNavStack` bottom nav with
  per-tab history) and `example/lib/results.dart` (`pushForResult` — await a value
  from a pushed screen), filling the two biggest example gaps.
- **Docs:** README gains a table of contents and runnable snippets for results,
  per-tab nav, reusing an open screen (`pushOrMoveToTop`/`moveToTop`) and the live
  `BackStackInspector`; corrects the `BackStack.of<AppKey>` type argument, the
  exhaustiveness claim (now that the hero leads with `NavEntries`), and the example
  README's Pokédex description. `pushForResult`'s `Object?`-cast caveat and the
  `NavEntry.id` / `entries` docs are clarified.

## 0.2.6

Convenience additions inspired by other routers — all built as plain list ops /
pure functions / one widget, so the core model is unchanged (no codegen, no
dependencies).

- **`NavStack.moveToTop(test)` / `pushOrMoveToTop(key)`** — reuse a screen that's
  already open instead of stacking a duplicate (`singleTop`/`clearTop`).
- **`combineRedirects([...])`** — compose several redirect rules (auth,
  onboarding, flags) into one `redirect`, each a pure `proposed → RedirectStep`
  (`ContinueRedirect` / `RedirectTo(stack, stop:)`). Same once-per-change,
  loop-proof semantics as a single `redirect`.
- **`BackStackInspector<K>`** — a zero-dep in-app widget that lists the live stack
  (current entry marked), for debugging without any DevTools plumbing.

Not added, on purpose: a string query-parameter bag (typed key fields already
carry a destination's arguments — a stringly-typed side channel would work
against that) and a route-file code generator (back_stack stays codegen-free).

## 0.2.5

- **`BackStackApp<K>` — deep links in one function.** A single widget bundles the
  `MaterialApp.router` + `NavStackRouterDelegate` + parser wiring; you supply only
  `onLink: (Uri) => [destinations]`. Optional `toLink` projects the stack back onto
  the web address bar, `onLinkFallback` handles bad links, and `restorationScopeId`
  is set by default. Zero new dependencies — it drives Flutter's own Router.
- **`BackStack.parentOf<K>(context)` (and `maybeParentOf`)** — reach the stack one
  level up from a nested child when parent and child share the same key type, so a
  child screen can `BackStack.parentOf<AppKey>(context).pop()` the outer flow.
  (Distinct key subtypes + `BackStack.of<ParentKey>` remain the more type-safe
  default.)
- `example/lib/multi_file/` now uses `BackStackApp` — the simplest example also
  demonstrates deep links (`/product/7`).

## 0.2.4

- **Docs:** the README hero snippet is corrected and no longer uses a `switch` —
  it leads with `NavEntries` (`..on<Home>(...)`, `builder: entries.call`) over a
  non-sealed `AppKey`, so it compiles as shown and mirrors a multi-file app. (The
  previous snippet declared a `sealed` base with no `const` constructor and
  inferred `NavStack<Home>`, so it didn't compile.)
- Adds `example/lib/multi_file/` — the simplest multi-file layout: `app_key.dart`
  + one file per feature (`home_feature.dart`, `product_feature.dart`) each with
  its own destination, screen and `register*` call, collected in `main.dart`. No
  `switch`, no central list.

## 0.2.3

- **Fix:** a `pop(result)` that is vetoed by `guard` (or collapsed to a no-op by
  `redirect`) no longer completes the destination's `pushForResult` future or
  returns `true`. Previously the awaiter received the result while the screen was
  still on top — now the result is delivered, and `pop` returns `true`, only when
  the entry actually leaves the stack. (`popGuard` was already safe.)
- Docs: `NavEntryDecorator.onRemoved` notes that it runs during the display's
  build (defer any rebuild-triggering work with `addPostFrameCallback`);
  `NavEntries` documents that it matches by exact runtime type, not subtype.
- Adds `example/lib/modular_demo.dart` (also on GitHub): three feature modules
  register their own `NavEntries` into one map, and a single `NavEntryDecorator`
  wraps every screen and logs teardown on `onRemoved`.

## 0.2.2

- The main example (`example/lib/main.dart`, the one shown on the package page)
  now demonstrates `NavEntries` (as the builder) and `NavEntryDecorator` (a
  `screen_view` log + teardown hook) — so both APIs are visible on pub.dev's
  Example tab. No library code changed.

## 0.2.1

- Add `NavEntries<K>` — a registrable destination-type → screen map
  (`..on<Home>(...)`), Compose Nav3's `entryProvider`. Pass `builder: entries.call`
  to `NavDisplay`. Composes across feature files/modules instead of one big
  `switch`. The `switch` stays the default (compile-time exhaustive); this is the
  modular option.
- Add `NavEntryDecorator<K>` — Nav3's `NavEntryDecorator`. `decorate` wraps every
  screen (providers/DI scopes/tracing; first decorator is outermost) and
  `onRemoved` fires when an entry leaves the stack (or the display is disposed) so
  you can tear down a Bloc/controller/scope tied to a destination. Wire via the new
  `decorators:` on `NavDisplay` — also forwarded by `MultiNavDisplay`,
  `NavSceneHost`, `NavListDetail`, `NavStackRouterDelegate` and
  `MultiNavStackRouterDelegate`.

## 0.2.0

- Add `NavStackCodec.of(encode:, decode:, fallback:)` — build a deep-link codec
  inline from two functions instead of subclassing `NavStackCodec`.
- Add `NavStackCodec.fallbackFor(uri)` — the stack shown when a link is malformed
  or unknown (defaults to decoding `/`; supply `fallback:` or override to route
  to a NotFound screen).
- Harden the deep-link boundary: `NavStackRouterDelegate` now decodes without
  ever throwing — a `decode` that throws or returns empty falls back instead of
  crashing the app, so codecs can parse optimistically.
- **Fix:** `pushForResult` no longer hangs (and leaks its awaiter) when the push
  is blocked by `guard` or collapsed to a no-op by `redirect` — the future now
  resolves `null`, like every other way a screen can leave the stack.
- **Web + tabs:** `MultiNavStackRouterDelegate` + `MultiNavStackCodec` bring URL
  sync, deep links and OS back to a `MultiNavStack` (per-tab history) — the
  multi-tab equivalents of `NavStackRouterDelegate` / `NavStackCodec`.
- **Restoration + tabs:** `RestorableMultiNavStack` persists every tab's stack
  and the active tab across process death. Both restorable widgets now survive a
  corrupt/incompatible snapshot by keeping the freshly created stack instead of
  crashing on cold start.
- `MultiNavDisplay` gains `lazy` (build a tab only once first selected; default
  `false`, unchanged behavior) and `observers`. `observers` is also now forwarded
  by `NavSceneHost`, `NavListDetail` and `NavStackRouterDelegate` — a clean
  `NavigatorObserver` seam for `screen_view` analytics.
- **`NavListDetail` now preserves pane `State` across the breakpoint.** Rotating
  or resizing between the two-pane and stacked layouts keeps each screen's scroll
  position and controllers — every entry gets a stable `GlobalKey`, so Flutter
  reparents the live screen instead of rebuilding it.
- Add `MultiBackStack.of(context)` (and `MultiNavStackScope`) — reach the
  `MultiNavStack` host from any tab screen to switch tabs / read the active
  index, without passing the host down by hand.

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
