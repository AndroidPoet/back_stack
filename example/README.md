# back_stack examples

Each file under `lib/` is a standalone runnable app demonstrating one facet of
the package. Run any of them with `-t`:

```bash
cd example

flutter run -t lib/multi_file/main.dart  # simplest: destinations split across files, no switch
flutter run                          # shop demo (lib/main.dart)
flutter run -t lib/pokedex.dart      # Pokédex — NavListDetail + Hero on a real API
flutter run -t lib/showcase.dart     # NavListDetail — one stack, two adaptive layouts
flutter run -t lib/tabs.dart         # MultiNavStack — bottom nav with per-tab history
flutter run -t lib/results.dart      # pushForResult — await a value from a pushed screen
flutter run -t lib/guarded.dart      # AsyncRedirect — loop-proof async auth gating
flutter run -t lib/motion.dart       # Material motion (shared axis / fade-through)
flutter run -t lib/entries.dart      # NavEntries (modular builder) + NavEntryDecorator
flutter run -t lib/modular_demo.dart # fuller demo: feature-module entries + a cross-cutting decorator
```

- **multi_file/** — the simplest possible setup, split across files: `app_key.dart`
  (a non-sealed base), `home_feature.dart` and `product_feature.dart` (each owns its
  destination + screen + a `register*` function), and `main.dart` (collects them into
  one `NavEntries`). No `switch`, no central list — add a screen by adding a file.
- **main.dart** — the core model end to end: typed destinations, `push`/`pop`,
  a live inspector proving the stack is plain observable data.
- **pokedex.dart** — a real Pokédex on PokeAPI. Two typed destinations rendered by
  `NavListDetail`, so the *same* stack is a grid + detail on a wide window and a grid
  → pushed detail (with a `Hero` sprite flight) on a phone — no second navigation model.
- **showcase.dart** — `NavListDetail`: one stack that renders as a two-pane
  list-detail on a wide window and a push/pop stack on a phone.
- **tabs.dart** — `MultiNavStack` + `MultiNavDisplay`: a bottom nav bar where each
  tab keeps its own persistent back stack. Push deep in one tab, switch away and
  back — the history is intact. A deep screen jumps tabs via `MultiBackStack.of`.
- **results.dart** — `pushForResult`: open a color picker and `await` the value it
  pops back, or `null` if it's dismissed. The classic "return a result" flow with
  no result channel to wire up.
- **guarded.dart** — `AsyncRedirect`: a gated Admin screen runs an async permission
  check (with a loading overlay driven by `gate.resolving`) and either stays or
  bounces to Login — loop-proof, decision cached, `invalidate()` on auth change.
- **motion.dart** — Material motion on `TransitionPage`: shared-axis X for a peer
  step, shared-axis Z for drilling into a detail, chosen per destination in
  `pageBuilder`.
- **entries.dart** — register destinations as a map with `NavEntries` instead of
  one big `switch`, and scope setup/teardown to a destination with
  `NavEntryDecorator` (`decorate` + `onRemoved`).
- **modular_demo.dart** — the fuller version: three "feature modules" each register
  their own entries into one shared map, and a single `NavEntryDecorator` wraps
  every screen with an instrumentation overlay and logs a teardown line each time
  a destination leaves the stack (`onRemoved`). Covered by a smoke test in `test/`.
