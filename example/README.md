# back_stack examples

Each file under `lib/` is a standalone runnable app demonstrating one facet of
the package. Run any of them with `-t`:

```bash
cd example

flutter run                          # shop demo (lib/main.dart)
flutter run -t lib/pokedex.dart      # Pokédex — deep links, results, transitions
flutter run -t lib/showcase.dart     # NavListDetail — one stack, two adaptive layouts
flutter run -t lib/entries.dart      # NavEntries (modular builder) + NavEntryDecorator
```

- **main.dart** — the core model end to end: typed destinations, `push`/`pop`,
  a live inspector proving the stack is plain observable data.
- **pokedex.dart** — web URLs & deep links via a `NavStackCodec`, `pushForResult`,
  and custom transitions.
- **showcase.dart** — `NavListDetail`: one stack that renders as a two-pane
  list-detail on a wide window and a push/pop stack on a phone.
- **entries.dart** — register destinations as a map with `NavEntries` instead of
  one big `switch`, and scope setup/teardown to a destination with
  `NavEntryDecorator` (`decorate` + `onRemoved`).
