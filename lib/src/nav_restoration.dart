import 'dart:convert';
import 'package:back_stack/src/nav_key.dart';
import 'package:back_stack/src/nav_stack.dart';
import 'package:flutter/widgets.dart';

/// Serializes a single destination to/from a string, for state restoration.
///
/// Unlike a `NavStackCodec` (which maps the whole stack to one URL), this works
/// per key, so the **entire** stack is preserved across process death — not just
/// the deep-link projection of the top.
///
/// ```dart
/// class AppKeyCodec extends NavKeyCodec<AppKey> {
///   const AppKeyCodec();
///   @override
///   String encode(AppKey key) => switch (key) {
///         Home() => 'home',
///         Product(:final id) => 'product:$id',
///       };
///   @override
///   AppKey decode(String data) {
///     if (data == 'home') return const Home();
///     if (data.startsWith('product:')) return Product(int.parse(data.substring(8)));
///     return const Home();
///   }
/// }
/// ```
abstract class NavKeyCodec<K extends NavKey> {
  /// Const so a codec can be a cheap, shareable value.
  const NavKeyCodec();

  /// One destination → a stable string.
  String encode(K key);

  /// A string produced by [encode] → the destination.
  K decode(String data);
}

/// Owns a [NavStack] and persists it across **process death** (Android killing a
/// backgrounded app, then restoring it) — without needing a URL/Router.
///
/// Place it above a [NavDisplay] and give the surrounding app a
/// `restorationScopeId` (e.g. `MaterialApp(restorationScopeId: 'app')`). The
/// full typed stack is serialized via [codec]; on relaunch it's rebuilt exactly.
///
/// ```dart
/// MaterialApp(
///   restorationScopeId: 'app',
///   home: RestorableBackStack<AppKey>(
///     restorationId: 'nav',
///     create: () => NavStack.of(const Home()),
///     codec: const AppKeyCodec(),
///     builder: (context, stack) => NavDisplay<AppKey>(
///       stack: stack,
///       builder: (context, key) => screenFor(key),
///     ),
///   ),
/// )
/// ```
class RestorableBackStack<K extends NavKey> extends StatefulWidget {
  /// Creates a restorable host. [create] builds the initial stack when there's
  /// nothing to restore; [codec] serializes each destination; [builder] renders
  /// the (restored) stack.
  const RestorableBackStack({
    required this.restorationId,
    required this.create,
    required this.codec,
    required this.builder,
    super.key,
  });

  /// Restoration id for this stack within the enclosing restoration scope.
  final String restorationId;

  /// Builds the initial stack when there is nothing to restore. Called once;
  /// the returned stack is owned and disposed here.
  final NavStack<K> Function() create;

  /// Serializes each destination for storage.
  final NavKeyCodec<K> codec;

  /// Renders the (possibly restored) stack.
  final Widget Function(BuildContext context, NavStack<K> stack) builder;

  @override
  State<RestorableBackStack<K>> createState() => _RestorableBackStackState<K>();
}

class _RestorableBackStackState<K extends NavKey>
    extends State<RestorableBackStack<K>>
    with RestorationMixin {
  late final NavStack<K> _stack = widget.create()..addListener(_persist);
  final RestorableString _encoded = RestorableString('');

  @override
  String? get restorationId => widget.restorationId;

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_encoded, 'keys');
    final data = _encoded.value;
    if (data.isEmpty) {
      _persist(); // seed storage with the initial stack
      return;
    }
    final keys = _decode(data);
    if (keys.isNotEmpty) _stack.replaceAll(keys);
  }

  void _persist() => _encoded.value = _encode(_stack.keys);

  String _encode(List<K> keys) =>
      jsonEncode([for (final k in keys) widget.codec.encode(k)]);

  List<K> _decode(String data) => [
    for (final e in jsonDecode(data) as List) widget.codec.decode(e as String),
  ];

  @override
  void dispose() {
    _stack
      ..removeListener(_persist)
      ..dispose();
    _encoded.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _stack);
}
