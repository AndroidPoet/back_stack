import 'dart:convert';
import 'package:back_stack/src/nav_key.dart';
import 'package:back_stack/src/nav_multi.dart';
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
    List<K> keys;
    try {
      keys = _decode(data);
    } on Object catch (_) {
      // The snapshot is corrupt or from an incompatible build (e.g. a key's
      // encoded format changed across an app update). Don't crash on cold
      // start: keep the freshly [create]d stack and overwrite the bad data.
      _persist();
      return;
    }
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

/// Owns a [MultiNavStack] and persists **every tab's stack plus the active tab**
/// across process death — the multi-tab sibling of [RestorableBackStack].
///
/// Restores each tab exactly where the user left it, and which tab was on top.
/// The tab count must match between runs (it's your app's fixed bottom bar);
/// mismatched or corrupt data is ignored and the freshly [create]d host is kept.
///
/// ```dart
/// MaterialApp(
///   restorationScopeId: 'app',
///   home: RestorableMultiNavStack<AppKey>(
///     restorationId: 'tabs',
///     create: () => MultiNavStack<AppKey>([
///       NavStack.of(const Feed()),
///       NavStack.of(const Profile()),
///     ]),
///     codec: const AppKeyCodec(),
///     builder: (context, host) => Scaffold(
///       body: MultiNavDisplay<AppKey>(host: host, builder: screenFor),
///       bottomNavigationBar: /* drive from host.index / host.select */,
///     ),
///   ),
/// )
/// ```
class RestorableMultiNavStack<K extends NavKey> extends StatefulWidget {
  /// Creates a restorable multi-tab host. [create] builds the initial tabs when
  /// there's nothing to restore; [codec] serializes each destination.
  const RestorableMultiNavStack({
    required this.restorationId,
    required this.create,
    required this.codec,
    required this.builder,
    super.key,
  });

  /// Restoration id within the enclosing restoration scope.
  final String restorationId;

  /// Builds the initial host when there is nothing to restore. Called once; the
  /// returned host is owned and disposed here.
  final MultiNavStack<K> Function() create;

  /// Serializes each destination for storage.
  final NavKeyCodec<K> codec;

  /// Renders the (possibly restored) host.
  final Widget Function(BuildContext context, MultiNavStack<K> host) builder;

  @override
  State<RestorableMultiNavStack<K>> createState() =>
      _RestorableMultiNavStackState<K>();
}

class _RestorableMultiNavStackState<K extends NavKey>
    extends State<RestorableMultiNavStack<K>>
    with RestorationMixin {
  late final MultiNavStack<K> _host = widget.create()..addListener(_persist);
  final RestorableString _encoded = RestorableString('');

  @override
  String? get restorationId => widget.restorationId;

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_encoded, 'multi');
    final data = _encoded.value;
    if (data.isEmpty) {
      _persist(); // seed storage with the initial host
      return;
    }
    try {
      final decoded = jsonDecode(data) as Map<String, dynamic>;
      final tabs = (decoded['tabs'] as List).cast<dynamic>();
      // Only restore when the saved shape matches this run's bottom bar.
      if (tabs.length == _host.length) {
        for (var t = 0; t < tabs.length; t++) {
          final keys = [
            for (final e in tabs[t] as List) widget.codec.decode(e as String),
          ];
          if (keys.isNotEmpty) _host.tabs[t].replaceAll(keys);
        }
        final i = decoded['i'] as int;
        if (i >= 0 && i < _host.length) {
          _host.select(i, popToRootOnReselect: false);
        }
      }
    } on Object catch (_) {
      // Corrupt or incompatible snapshot — keep the initial host, overwrite it.
      _persist();
    }
  }

  void _persist() {
    _encoded.value = jsonEncode({
      'i': _host.index,
      'tabs': [
        for (final tab in _host.tabs)
          [for (final k in tab.keys) widget.codec.encode(k)],
      ],
    });
  }

  @override
  void dispose() {
    _host
      ..removeListener(_persist)
      ..dispose();
    _encoded.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _host);
}
