# back_stack examples

Each file under `lib/` is a standalone runnable app demonstrating one facet of
the package. Run any of them with `-t`:

```bash
cd example

flutter run -t lib/multi_file/main.dart  # simplest: destinations split across files, no switch
flutter run                          # shop demo (lib/main.dart)
flutter run -t lib/pokedex.dart      # Pokédex — deep links, results, transitions
flutter run -t lib/showcase.dart     # NavListDetail — one stack, two adaptive layouts
flutter run -t lib/entries.dart      # NavEntries (modular builder) + NavEntryDecorator
flutter run -t lib/modular_demo.dart # fuller demo: feature-module entries + a cross-cutting decorator
```

- **multi_file/** — the simplest possible setup, split across files: `app_key.dart`
  (a non-sealed base), `home_feature.dart` and `product_feature.dart` (each owns its
  destination + screen + a `register*` function), and `main.dart` (collects them into
  one `NavEntries`). No `switch`, no central list — add a screen by adding a file.
- **main.dart** — the core model end to end: typed destinations, `push`/`pop`,
  a live inspector proving the stack is plain observable data.
- **pokedex.dart** — web URLs & deep links via a `NavStackCodec`, `pushForResult`,
  and custom transitions.
- **showcase.dart** — `NavListDetail`: one stack that renders as a two-pane
  list-detail on a wide window and a push/pop stack on a phone.
- **entries.dart** — register destinations as a map with `NavEntries` instead of
  one big `switch`, and scope setup/teardown to a destination with
  `NavEntryDecorator` (`decorate` + `onRemoved`).
- **modular_demo.dart** — the fuller version: three "feature modules" each register
  their own entries into one shared map, and a single `NavEntryDecorator` wraps
  every screen with an instrumentation overlay and logs a teardown line each time
  a destination leaves the stack (`onRemoved`). Covered by a smoke test in `test/`.
