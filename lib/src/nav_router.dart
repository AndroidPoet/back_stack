import 'package:back_stack/src/nav_display.dart';
import 'package:back_stack/src/nav_key.dart';
import 'package:back_stack/src/nav_multi.dart';
import 'package:back_stack/src/nav_stack.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Translates between your back stack and a [Uri].
///
/// This is the *only* thing you write to get web URL sync, deep links, browser
/// back/forward, and state restoration — and it keeps the back stack as the
/// single source of truth. The URL is just a projection of the list.
///
/// You decide what stack a link materializes, which fixes the classic "a deep
/// link nukes the whole stack" problem: for `/products/42` you can return
/// `[Home(), Product(42)]` so Back still goes Home, or just `[Product(42)]` to
/// replace — your call.
///
/// ```dart
/// class ShopCodec extends NavStackCodec<AppKey> {
///   const ShopCodec();
///   @override
///   Uri encode(List<AppKey> stack) => switch (stack.last) {
///         Home() => Uri(path: '/'),
///         Product(:final id) => Uri(path: '/products/$id'),
///         _ => Uri(path: '/'),
///       };
///
///   @override
///   List<AppKey> decode(Uri uri) {
///     final seg = uri.pathSegments;
///     if (seg.length == 2 && seg[0] == 'products') {
///       return [const Home(), Product(int.parse(seg[1]))]; // layer on Home
///     }
///     return [const Home()];
///   }
/// }
/// ```
abstract class NavStackCodec<K extends NavKey> {
  /// Const so a codec can be a cheap, shareable value.
  const NavStackCodec();

  /// Build a codec inline from two functions — no subclass needed.
  ///
  /// This is the easy way in: for most apps a codec is just two `switch`es, so
  /// write them where you wire the router instead of declaring a whole class.
  ///
  /// ```dart
  /// final codec = NavStackCodec<AppKey>.of(
  ///   encode: (stack) => switch (stack.last) {
  ///     Home()             => Uri(path: '/'),
  ///     Product(:final id) => Uri(path: '/products/$id'),
  ///     _                  => Uri(path: '/'),
  ///   },
  ///   decode: (uri) {
  ///     final s = uri.pathSegments;
  ///     if (s.length == 2 && s[0] == 'products') {
  ///       final id = int.tryParse(s[1]);
  ///       if (id != null) return [const Home(), Product(id)]; // layer on Home
  ///     }
  ///     return [const Home()];
  ///   },
  ///   fallback: [const Home()], // shown for a malformed / unknown link
  /// );
  /// ```
  factory NavStackCodec.of({
    required Uri Function(List<K> stack) encode,
    required List<K> Function(Uri uri) decode,
    List<K>? fallback,
  }) = _CallbackNavStackCodec<K>;

  /// The whole stack → the URL to show. Typically derived from `stack.last`.
  Uri encode(List<K> stack);

  /// A URL → the full stack to display. Return every destination you want on
  /// the stack for this URL (this is where you choose layer-vs-replace).
  ///
  /// Parse optimistically — you do **not** need to defend against bad input.
  /// If this throws (e.g. `int.parse` on a junk segment) or returns empty for
  /// an unknown link, [fallbackFor] is used instead of crashing.
  List<K> decode(Uri uri);

  /// The stack to show when a link can't be understood — i.e. when [decode]
  /// throws or returns empty. This is back_stack's answer to go_router's
  /// `errorBuilder`, scoped to the one place an untyped URL can go wrong: the
  /// deep-link boundary. In-app navigation never reaches it, because
  /// destinations are typed and the builder switch is exhaustive — that whole
  /// "route not found" error class is gone at compile time.
  ///
  /// Defaults to decoding the root path `/`. Override to show a dedicated
  /// NotFound screen. Keep it total — it must never throw.
  List<K> fallbackFor(Uri uri) => decode(Uri(path: '/'));
}

/// [NavStackCodec] built from plain functions — the target of
/// [NavStackCodec.of]. Not exported; construct it via the factory.
class _CallbackNavStackCodec<K extends NavKey> extends NavStackCodec<K> {
  _CallbackNavStackCodec({
    required Uri Function(List<K> stack) encode,
    required List<K> Function(Uri uri) decode,
    List<K>? fallback,
  })  : _encode = encode,
        _decode = decode,
        _fallback = fallback;

  final Uri Function(List<K> stack) _encode;
  final List<K> Function(Uri uri) _decode;
  final List<K>? _fallback;

  @override
  Uri encode(List<K> stack) => _encode(stack);

  @override
  List<K> decode(Uri uri) => _decode(uri);

  @override
  List<K> fallbackFor(Uri uri) => _fallback ?? super.fallbackFor(uri);
}

/// Drives a [NavStack] from the platform's [Router]: URL sync on web, deep
/// links, OS back, and (with a `restorationScopeId`) state restoration.
///
/// ```dart
/// final delegate = NavStackRouterDelegate(
///   stack: NavStack.of(const Home()),
///   codec: ShopCodec(),
///   builder: (context, key) => /* your screen */,
/// );
///
/// MaterialApp.router(
///   routerDelegate: delegate,
///   routeInformationParser: const NavStackRouteInformationParser(),
///   restorationScopeId: 'app', // optional: survive process death
/// );
/// ```
///
/// The browser URL updates whenever the stack changes (it reads
/// [currentConfiguration]); a platform navigation (deep link, typed URL,
/// browser back/forward) flows in through [setNewRoutePath] and becomes the new
/// stack. The stack never stops being the source of truth.
class NavStackRouterDelegate<K extends NavKey> extends RouterDelegate<Uri>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<Uri> {
  /// Wires [stack] to the platform Router, translating via [codec] and
  /// rendering each destination with [builder].
  NavStackRouterDelegate({
    required this.stack,
    required this.codec,
    required this.builder,
    this.pageBuilder,
    this.observers = const [],
    this.decorators = const [],
  }) {
    // URL follows the stack: when the list changes, tell the Router to re-read
    // currentConfiguration.
    stack.addListener(notifyListeners);
  }

  /// The back stack this delegate renders and keeps the URL in sync with.
  final NavStack<K> stack;

  /// Your [Uri] ⇄ stack translation.
  final NavStackCodec<K> codec;

  /// Maps a destination to its screen. See [NavDisplay.builder].
  final NavWidgetBuilder<K> builder;

  /// Optional custom page/transition. See [NavDisplay.pageBuilder].
  final NavPageBuilder<K>? pageBuilder;

  /// Attached to the underlying [Navigator] — your `screen_view` analytics seam
  /// or route logging for the URL-driven display.
  final List<NavigatorObserver> observers;

  /// Applied to the display's screens. See [NavEntryDecorator].
  final List<NavEntryDecorator<K>> decorators;

  /// Stable key for the inner [Navigator] so OS back (`popRoute`, provided by
  /// [PopNavigatorRouterDelegateMixin]) reaches it — and any [PopScope] or
  /// dialog gets first chance before the stack pops.
  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  Uri get currentConfiguration => codec.encode(stack.keys);

  @override
  Widget build(BuildContext context) {
    return NavDisplay<K>(
      stack: stack,
      navigatorKey: navigatorKey,
      builder: builder,
      pageBuilder: pageBuilder,
      observers: observers,
      decorators: decorators,
    );
  }

  @override
  Future<void> setNewRoutePath(Uri configuration) async {
    final next = _decodeOrFallback(configuration);
    if (next != null && next.isNotEmpty) stack.replaceAll(next);
  }

  /// Turn a platform URI into a stack without ever throwing. A deep link is
  /// untyped input from outside, so it's the one place a bad value can reach
  /// navigation: try [NavStackCodec.decode], fall back to
  /// [NavStackCodec.fallbackFor] on an error or empty result, and if even that
  /// fails keep the current stack rather than crash the app.
  List<K>? _decodeOrFallback(Uri uri) {
    try {
      final decoded = codec.decode(uri);
      if (decoded.isNotEmpty) return decoded;
    } on Object catch (_) {
      // Malformed link — fall through to the fallback stack below.
    }
    try {
      return codec.fallbackFor(uri);
    } on Object catch (_) {
      return null; // Give up safely: keep whatever is already on screen.
    }
  }

  @override
  void dispose() {
    stack.removeListener(notifyListeners);
    super.dispose();
  }
}

/// Parses platform [RouteInformation] into a [Uri] and back, enabling browser
/// history and state restoration. Stateless — share one `const` instance.
class NavStackRouteInformationParser extends RouteInformationParser<Uri> {
  /// Creates a parser. Holds no state — keep one `const` instance.
  const NavStackRouteInformationParser();

  @override
  Future<Uri> parseRouteInformation(RouteInformation routeInformation) async {
    return routeInformation.uri;
  }

  @override
  RouteInformation restoreRouteInformation(Uri configuration) {
    return RouteInformation(uri: configuration);
  }
}

/// Where a URL lands in a [MultiNavStack]: which [tab], and the [stack] to show
/// inside it. Returned by [MultiNavStackCodec.decode].
@immutable
class MultiNavLocation<K extends NavKey> {
  /// A location targeting [tab], displaying [stack] within it.
  const MultiNavLocation(this.tab, this.stack);

  /// The tab index to select.
  final int tab;

  /// The stack to show inside that tab (at least one destination).
  final List<K> stack;
}

/// Translates between a [MultiNavStack] (per-tab back stacks) and a [Uri] — the
/// missing piece that lets a bottom-nav app also have web URLs, deep links and
/// browser back/forward. This is the multi-tab sibling of [NavStackCodec]:
/// [encode] projects "which tab + that tab's stack" to a URL, and [decode] maps
/// a URL to a [MultiNavLocation].
///
/// ```dart
/// final codec = MultiNavStackCodec<AppKey>.of(
///   encode: (tab, stack) => switch (stack.last) {
///     Feed()             => Uri(path: '/feed'),
///     Profile()          => Uri(path: '/profile'),
///     Product(:final id) => Uri(path: '/feed/product/$id'),
///     _                  => Uri(path: '/feed'),
///   },
///   decode: (uri) {
///     final s = uri.pathSegments;
///     if (s.isNotEmpty && s.first == 'profile') {
///       return const MultiNavLocation(1, [Profile()]);
///     }
///     if (s.length == 3 && s[1] == 'product') {
///       final id = int.tryParse(s[2]);
///       if (id != null) return MultiNavLocation(0, [const Feed(), Product(id)]);
///     }
///     return const MultiNavLocation(0, [Feed()]);
///   },
///   fallback: const MultiNavLocation(0, [Feed()]),
/// );
/// ```
abstract class MultiNavStackCodec<K extends NavKey> {
  /// Const so a codec can be a cheap, shareable value.
  const MultiNavStackCodec();

  /// Build a codec inline from two functions — no subclass needed.
  factory MultiNavStackCodec.of({
    required Uri Function(int tab, List<K> activeStack) encode,
    required MultiNavLocation<K> Function(Uri uri) decode,
    MultiNavLocation<K>? fallback,
  }) = _CallbackMultiNavStackCodec<K>;

  /// The active [tab] and its [activeStack] → the URL to show.
  Uri encode(int tab, List<K> activeStack);

  /// A URL → the tab to select and the stack to show inside it. Parse
  /// optimistically; a throw or an out-of-range tab falls back to [fallbackFor].
  MultiNavLocation<K> decode(Uri uri);

  /// The location shown when a link is malformed or unknown — the multi-tab
  /// equivalent of [NavStackCodec.fallbackFor]. Defaults to decoding `/`.
  MultiNavLocation<K> fallbackFor(Uri uri) => decode(Uri(path: '/'));
}

class _CallbackMultiNavStackCodec<K extends NavKey>
    extends MultiNavStackCodec<K> {
  _CallbackMultiNavStackCodec({
    required Uri Function(int tab, List<K> activeStack) encode,
    required MultiNavLocation<K> Function(Uri uri) decode,
    MultiNavLocation<K>? fallback,
  })  : _encode = encode,
        _decode = decode,
        _fallback = fallback;

  final Uri Function(int tab, List<K> activeStack) _encode;
  final MultiNavLocation<K> Function(Uri uri) _decode;
  final MultiNavLocation<K>? _fallback;

  @override
  Uri encode(int tab, List<K> activeStack) => _encode(tab, activeStack);

  @override
  MultiNavLocation<K> decode(Uri uri) => _decode(uri);

  @override
  MultiNavLocation<K> fallbackFor(Uri uri) => _fallback ?? super.fallbackFor(uri);
}

/// Drives a [MultiNavStack] from the platform [Router]: URL sync, deep links and
/// OS back for a bottom-nav app with **persistent per-tab history**. The
/// [MultiNavStack] equivalent of [NavStackRouterDelegate].
///
/// The URL follows the active tab (it reads [currentConfiguration] whenever the
/// host changes); a platform navigation selects the tab and sets that tab's
/// stack via [setNewRoutePath]; and OS back is routed through
/// [MultiNavStack.handleBack] (pop the active tab, else fall back to the first).
///
/// ```dart
/// MaterialApp.router(
///   routerDelegate: MultiNavStackRouterDelegate(
///     host: tabs,
///     codec: codec,                 // a MultiNavStackCodec
///     builder: (context, key) => screenFor(key),
///   ),
///   routeInformationParser: const NavStackRouteInformationParser(),
/// );
/// ```
class MultiNavStackRouterDelegate<K extends NavKey> extends RouterDelegate<Uri>
    with ChangeNotifier {
  /// Wires [host] to the platform Router, translating via [codec] and rendering
  /// each destination with [builder].
  MultiNavStackRouterDelegate({
    required this.host,
    required this.codec,
    required this.builder,
    this.pageBuilder,
    this.observers = const [],
    this.decorators = const [],
    this.lazy = false,
  }) {
    host.addListener(notifyListeners);
  }

  /// The per-tab stacks this delegate renders and keeps the URL in sync with.
  final MultiNavStack<K> host;

  /// Your [Uri] ⇄ (tab, stack) translation.
  final MultiNavStackCodec<K> codec;

  /// Maps a destination to its screen. See [NavDisplay.builder].
  final NavWidgetBuilder<K> builder;

  /// Optional custom page/transition. See [NavDisplay.pageBuilder].
  final NavPageBuilder<K>? pageBuilder;

  /// Attached to every tab's [Navigator]. See [MultiNavDisplay.observers].
  final List<NavigatorObserver> observers;

  /// Applied to every tab's screens. See [NavEntryDecorator].
  final List<NavEntryDecorator<K>> decorators;

  /// Build tabs lazily. See [MultiNavDisplay.lazy].
  final bool lazy;

  @override
  Uri get currentConfiguration => codec.encode(host.index, host.active.keys);

  @override
  Widget build(BuildContext context) => MultiNavDisplay<K>(
    host: host,
    builder: builder,
    pageBuilder: pageBuilder,
    observers: observers,
    decorators: decorators,
    lazy: lazy,
  );

  // The root delegate is where OS back arrives under a Router (the inner
  // MultiNavDisplay PopScope is inert with no ModalRoute above it). Route it
  // through the host: pop the active tab, else fall back to the first tab.
  @override
  Future<bool> popRoute() => SynchronousFuture<bool>(host.handleBack());

  @override
  Future<void> setNewRoutePath(Uri configuration) async {
    final loc = _decodeOrFallback(configuration);
    if (loc == null || loc.tab < 0 || loc.tab >= host.length) return;
    // Select without popping-to-root: we're about to set the stack explicitly.
    host.select(loc.tab, popToRootOnReselect: false);
    if (loc.stack.isNotEmpty) host.active.replaceAll(loc.stack);
  }

  /// Decode a URL to a location without ever throwing — same deep-link hardening
  /// as [NavStackRouterDelegate], for the multi-tab case.
  MultiNavLocation<K>? _decodeOrFallback(Uri uri) {
    try {
      return codec.decode(uri);
    } on Object catch (_) {
      // Malformed link — fall through to the fallback below.
    }
    try {
      return codec.fallbackFor(uri);
    } on Object catch (_) {
      return null; // Give up safely: keep whatever is already on screen.
    }
  }

  @override
  void dispose() {
    host.removeListener(notifyListeners);
    super.dispose();
  }
}
