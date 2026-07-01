import 'package:back_stack/src/nav_key.dart';
import 'package:flutter/widgets.dart';

/// A registrable destination-type → screen map — Compose Nav3's
/// `entryProvider { entry<T> { ... } }`, in Flutter.
///
/// Instead of one big `switch` in [NavDisplay.builder], register each
/// destination's screen by type. A [NavEntries] *is* a `NavWidgetBuilder` (it
/// defines [call]), so hand it straight to `NavDisplay(builder: entries)`.
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
/// NavDisplay<AppKey>(stack: stack, builder: entries.call);
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

  /// Register the screen for destination type [T]. Called for its side effect;
  /// returns `this` so registrations can be chained with `..`.
  void on<T extends K>(Widget Function(BuildContext context, T key) build) {
    _builders[T] = (context, key) => build(context, key as T);
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
}
