import 'package:back_stack/src/nav_key.dart';
import 'package:flutter/widgets.dart';

/// A registrable destination-type → screen map — Compose Nav3's
/// `entryProvider { entry<T> { ... } }`, in Flutter.
///
/// Instead of one big `switch` in [NavDisplay.builder], register each
/// destination's screen by type. Hand the registry to the display directly
/// (`NavDisplay(entries: entries)`) — or, since a [NavEntries] *is* a
/// `NavWidgetBuilder` (it defines [call]), pass `builder: entries.call`.
/// Because registration is just method calls, feature modules can each
/// contribute their own entries into one shared instance — the builder no
/// longer has to live in a single file:
///
/// ```dart
/// // feature_home.dart
/// void registerHome(NavEntries<AppKey> e) =>
///     e.on<Home>((context, key) => const HomeScreen());
///
/// // feature_shop.dart
/// void registerShop(NavEntries<AppKey> e) =>
///     e.on<Product>((context, key) => ProductScreen(id: key.id));
///
/// // app.dart
/// final entries = NavEntries<AppKey>();
/// registerHome(entries);
/// registerShop(entries);
/// NavDisplay<AppKey>(stack: stack, entries: entries);
/// ```
///
/// A destination can also carry **its own presentation** — a dialog, a sheet,
/// a custom transition — without a `pageBuilder` switch and without mixing
/// `NavPage` into the domain key:
///
/// ```dart
/// entries.on<ConfirmDelete>(
///   (context, key) => const ConfirmDeleteContent(),
///   page: (context, key, child, pageKey) =>
///       DialogPage<void>(key: pageKey, builder: (_) => child),
/// );
/// ```
///
/// Trade-off vs a `switch`: a `switch` over a sealed type is checked for
/// exhaustiveness by the compiler; a registry is not, so a key whose type has no
/// registered entry throws at runtime (see [call]). Reach for this when
/// modularity matters more than that compile-time guarantee — e.g. a large app
/// split across feature packages. For a small app, the `switch` builder is
/// still the safest choice.
///
/// Matching is by **exact runtime type**, not subtype: registering `on<Product>`
/// handles a `Product`, but not a `DiscountedProduct extends Product` (a `switch`
/// `Product()` pattern would). Register each concrete destination type you push.
class NavEntries<K extends NavKey> {
  final Map<Type, Widget Function(BuildContext context, K key)> _builders = {};
  final Map<
    Type,
    Page<dynamic> Function(
      BuildContext context,
      K key,
      Widget child,
      LocalKey pageKey,
    )
  >
  _pages = {};

  /// Register the screen for destination type [T]. Called for its side effect
  /// (it returns `void`); chain registrations with the `..` cascade.
  ///
  /// Pass [page] to give this destination its own presentation: it receives the
  /// built (and decorator-wrapped) screen as `child` and returns the [Page]
  /// that shows it — `DialogPage`, `SheetPage`, a `TransitionPage`, anything.
  /// The returned page must use the supplied `pageKey` as its `key`. Omit
  /// [page] for the platform default.
  void on<T extends K>(
    Widget Function(BuildContext context, T key) build, {
    Page<dynamic> Function(
      BuildContext context,
      T key,
      Widget child,
      LocalKey pageKey,
    )?
    page,
  }) {
    _builders[T] = (context, key) => build(context, key as T);
    if (page != null) {
      _pages[T] = (context, key, child, pageKey) =>
          page(context, key as T, child, pageKey);
    } else {
      _pages.remove(T);
    }
  }

  /// Whether an entry is registered for type [T].
  bool has<T extends K>() => _builders.containsKey(T);

  /// Build the screen for [key]. Throws a [StateError] if its runtime type has
  /// no registered entry — register every destination you push.
  ///
  /// This method makes a [NavEntries] usable anywhere a `NavWidgetBuilder<K>` is
  /// expected (`NavDisplay(builder: entries)`), via Dart's callable-object
  /// tear-off.
  Widget call(BuildContext context, K key) {
    final build = _builders[key.runtimeType];
    if (build == null) {
      throw StateError(
        'NavEntries has no entry for ${key.runtimeType}. Register it with '
        '`entries.on<${key.runtimeType}>((context, key) => ...)`.',
      );
    }
    return build(context, key);
  }

  /// The page registered for [key]'s type via `on<T>(page: …)`, built around
  /// [child] — or null when the type has no custom presentation. `NavDisplay`
  /// consults this when given the registry via its `entries` parameter.
  Page<dynamic>? pageFor(
    BuildContext context,
    K key,
    Widget child,
    LocalKey pageKey,
  ) => _pages[key.runtimeType]?.call(context, key, child, pageKey);
}
