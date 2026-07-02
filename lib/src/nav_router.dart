import 'package:back_stack/src/nav_display.dart';
import 'package:back_stack/src/nav_entries.dart';
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
  }) : _encode = encode,
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
  /// rendering each destination with [builder] (or [entries]).
  NavStackRouterDelegate({
    required this.stack,
    required this.codec,
    this.builder,
    this.entries,
    this.asyncDecode,
    this.shell,
    this.pageBuilder,
    this.observers = const [],
    this.decorators = const [],
  }) : assert(
         (builder != null) ^ (entries != null),
         'Provide exactly one of builder / entries.',
       ) {
    // URL follows the stack: when the list changes, tell the Router to re-read
    // currentConfiguration.
    stack.addListener(notifyListeners);
  }

  /// The back stack this delegate renders and keeps the URL in sync with.
  final NavStack<K> stack;

  /// Your [Uri] ⇄ stack translation.
  final NavStackCodec<K> codec;

  /// Maps a destination to its screen. See [NavDisplay.builder].
  final NavWidgetBuilder<K>? builder;

  /// The destination registry, as an alternative to [builder]. See
  /// [NavDisplay.entries].
  final NavEntries<K>? entries;

  /// Optional **async** link resolution, tried before [codec]'s sync decode for
  /// every incoming link: await a lookup ("does this document exist? who may
  /// see it?") and return the stack to show — or `null` to fall through to the
  /// sync mapping. Race-safe: a newer link supersedes an in-flight resolution
  /// (the stale result is dropped), and an error just falls through. The stack
  /// stays where it is while the future runs.
  final Future<List<K>?> Function(Uri uri)? asyncDecode;

  /// Optional chrome wrapped **around** the display — a persistent side rail,
  /// an app frame — that lives under `MaterialApp` (themes, localization, the
  /// restoration scope) but outside the navigating area. It receives the
  /// [stack] and the built display; return the display wrapped however you
  /// like.
  final Widget Function(BuildContext context, NavStack<K> stack, Widget child)?
  shell;

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

  /// Bumped by every link application so an in-flight [asyncDecode] result
  /// that has been superseded is dropped instead of clobbering a newer link.
  int _linkGeneration = 0;

  /// Debug-only: URI strings already round-trip-validated, so the check runs
  /// once per distinct URL instead of on every rebuild. Reset when it grows
  /// large so a long session with many distinct URLs stays bounded.
  final Set<String> _validatedLinks = {};

  /// Set by [dispose]: an in-flight [handleLinkAsync] must not apply its
  /// result through a delegate that has since been detached and disposed.
  bool _disposed = false;

  @override
  Uri get currentConfiguration {
    final uri = codec.encode(stack.keys);
    assert(() {
      _debugValidateRoundTrip(uri);
      return true;
    }(), '');
    return uri;
  }

  /// Encode → decode → encode must be idempotent, or the two directions of the
  /// codec have drifted apart (the classic hand-written onLink/toLink bug):
  /// the URL shown in the address bar would decode to a place that shows a
  /// *different* URL. Caught here, in debug, the moment it's introduced.
  void _debugValidateRoundTrip(Uri uri) {
    if (_validatedLinks.length >= 512) _validatedLinks.clear();
    if (!_validatedLinks.add(uri.toString())) return;
    try {
      final reencoded = codec.encode(codec.decode(uri));
      if (reencoded.toString() != uri.toString()) {
        FlutterError.reportError(
          FlutterErrorDetails(
            library: 'back_stack',
            exception: FlutterError(
              'Link round-trip drift: the stack encodes to "$uri", but '
              'decoding that URL yields a stack that encodes to "$reencoded". '
              'The encode/decode directions of your codec (onLink/toLink or '
              'NavLinks table) disagree — deep links into "$uri" will not '
              'land where the address bar says the user is.',
            ),
          ),
        );
      }
    } on Object catch (_) {
      // decode threw → the delegate's fallback hardening owns that case.
    }
  }

  @override
  Widget build(BuildContext context) {
    final display = NavDisplay<K>(
      stack: stack,
      navigatorKey: navigatorKey,
      builder: builder,
      entries: entries,
      pageBuilder: pageBuilder,
      observers: observers,
      decorators: decorators,
    );
    final wrap = shell;
    if (wrap == null) return display;
    // Shell chrome lives outside the Navigator, so nothing above it provides
    // an Overlay — but Material widgets in it (tooltips, menus, autocomplete)
    // need one. Give the shell its own, like WidgetsApp does.
    return Overlay.wrap(child: wrap(context, stack, display));
  }

  @override
  Future<void> setNewRoutePath(Uri configuration) async {
    // A platform route that already matches the current projection is a no-op.
    // This matters after full-stack restoration: the Router replays the
    // restored URL, and applying it would collapse the restored deep stack to
    // just the URL's projection. Same location → keep the richer stack.
    if (configuration == currentConfiguration) return;
    await handleLinkAsync(configuration);
  }

  /// Apply a deep link that arrived **asynchronously at runtime** to the stack —
  /// the imperative sibling of the platform-driven [setNewRoutePath].
  ///
  /// The platform's [Router] only surfaces the launch URL and standard app links
  /// it handles itself. A custom-scheme link (`myapp://…`), a Firebase Dynamic
  /// Link, or a warm link delivered while the app is already running arrives
  /// instead as a `Uri` from a native plugin — feed each one here.
  ///
  /// back_stack owns the `Uri` → stack step: this runs your [codec]'s
  /// [NavStackCodec.decode] with the same never-throws hardening as a platform
  /// link (a bad link falls back; if even the fallback fails the current stack is
  /// kept). *You* own link **acquisition** — hand it the `Uri`s from whatever
  /// plugin you use (`app_links`, `uni_links`, Firebase Dynamic Links…), usually
  /// by listening to that plugin's runtime `Stream<Uri>`. [BackStackApp.linkStream]
  /// wires exactly that for you.
  ///
  /// Changing the stack updates the URL (via [currentConfiguration]) just like a
  /// platform link, so this stays consistent with browser/web sync. When
  /// [asyncDecode] is set, prefer [handleLinkAsync]; this sync path skips it.
  void handleLink(Uri uri) {
    _linkGeneration++; // a sync link supersedes any in-flight async one
    final next = _decodeOrFallback(uri);
    if (next != null && next.isNotEmpty) stack.replaceAll(next);
  }

  /// [handleLink], but giving [asyncDecode] (when set) the first shot: await
  /// it, apply its stack if it returns one, fall through to the sync [codec]
  /// mapping if it returns `null` or throws. Every platform link
  /// ([setNewRoutePath]) comes through here, so async link resolution is the
  /// default behavior, not a separate code path. Without [asyncDecode] this is
  /// exactly [handleLink].
  Future<void> handleLinkAsync(Uri uri) async {
    final resolve = asyncDecode;
    if (resolve == null) return handleLink(uri);
    final generation = ++_linkGeneration;
    List<K>? next;
    try {
      next = await resolve(uri);
    } on Object catch (_) {
      next = null; // resolution failed — fall through to the sync mapping
    }
    // A newer link (sync or async) arrived while we awaited — or the delegate
    // was swapped out and disposed: drop this one.
    if (_disposed || generation != _linkGeneration) return;
    if (next != null && next.isNotEmpty) {
      stack.replaceAll(next);
      return;
    }
    final fallback = _decodeOrFallback(uri);
    if (fallback != null && fallback.isNotEmpty) stack.replaceAll(fallback);
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
    _disposed = true;
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
  }) : _encode = encode,
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
  MultiNavLocation<K> fallbackFor(Uri uri) =>
      _fallback ?? super.fallbackFor(uri);
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
  /// each destination with [builder] (or [entries]).
  MultiNavStackRouterDelegate({
    required this.host,
    required this.codec,
    this.builder,
    this.entries,
    this.asyncDecode,
    this.shell,
    this.pageBuilder,
    this.observers = const [],
    this.decorators = const [],
    this.lazy = false,
  }) : assert(
         (builder != null) ^ (entries != null),
         'Provide exactly one of builder / entries.',
       ) {
    host.addListener(notifyListeners);
  }

  /// The per-tab stacks this delegate renders and keeps the URL in sync with.
  final MultiNavStack<K> host;

  /// Your [Uri] ⇄ (tab, stack) translation.
  final MultiNavStackCodec<K> codec;

  /// Maps a destination to its screen. See [NavDisplay.builder].
  final NavWidgetBuilder<K>? builder;

  /// The destination registry, as an alternative to [builder]. See
  /// [NavDisplay.entries].
  final NavEntries<K>? entries;

  /// Optional **async** link resolution — the multi-tab sibling of
  /// [NavStackRouterDelegate.asyncDecode]: awaited first for every incoming
  /// link; return the location to show, or `null` to fall through to the sync
  /// [codec]. Race-safe the same way.
  final Future<MultiNavLocation<K>?> Function(Uri uri)? asyncDecode;

  /// Optional chrome wrapped around the tabbed display (a `Scaffold` with a
  /// `NavigationBar` is the classic one) — it lives under `MaterialApp`, so
  /// themes/localization/restoration are available, and receives the [host] to
  /// drive tab selection.
  final Widget Function(
    BuildContext context,
    MultiNavStack<K> host,
    Widget child,
  )?
  shell;

  /// Optional custom page/transition. See [NavDisplay.pageBuilder].
  final NavPageBuilder<K>? pageBuilder;

  /// Attached to every tab's [Navigator]. See [MultiNavDisplay.observers].
  final List<NavigatorObserver> observers;

  /// Applied to every tab's screens. See [NavEntryDecorator].
  final List<NavEntryDecorator<K>> decorators;

  /// Build tabs lazily. See [MultiNavDisplay.lazy].
  final bool lazy;

  /// See [NavStackRouterDelegate._linkGeneration] — same supersede rule.
  int _linkGeneration = 0;

  /// Debug-only: URIs already round-trip-validated. Bounded like
  /// [NavStackRouterDelegate._validatedLinks].
  final Set<String> _validatedLinks = {};

  /// Set by [dispose] — see [NavStackRouterDelegate._disposed].
  bool _disposed = false;

  @override
  Uri get currentConfiguration {
    final uri = codec.encode(host.index, host.active.keys);
    assert(() {
      _debugValidateRoundTrip(uri);
      return true;
    }(), '');
    return uri;
  }

  /// Same drift check as [NavStackRouterDelegate]: encode∘decode must be
  /// idempotent on URIs, or deep links land somewhere the address bar doesn't
  /// say the user is.
  void _debugValidateRoundTrip(Uri uri) {
    if (_validatedLinks.length >= 512) _validatedLinks.clear();
    if (!_validatedLinks.add(uri.toString())) return;
    try {
      final loc = codec.decode(uri);
      final reencoded = codec.encode(loc.tab, loc.stack);
      if (reencoded.toString() != uri.toString()) {
        FlutterError.reportError(
          FlutterErrorDetails(
            library: 'back_stack',
            exception: FlutterError(
              'Link round-trip drift: the active tab encodes to "$uri", but '
              'decoding that URL yields a location that encodes to '
              '"$reencoded". The encode/decode directions of your '
              'MultiNavStackCodec disagree.',
            ),
          ),
        );
      }
    } on Object catch (_) {
      // decode threw → the delegate's fallback hardening owns that case.
    }
  }

  @override
  Widget build(BuildContext context) {
    final display = MultiNavDisplay<K>(
      host: host,
      builder: builder,
      entries: entries,
      pageBuilder: pageBuilder,
      observers: observers,
      decorators: decorators,
      lazy: lazy,
    );
    final wrap = shell;
    if (wrap == null) return display;
    // Shell chrome (Scaffold + NavigationBar) lives outside every tab's
    // Navigator — give it its own Overlay so tooltips/menus in the bar work.
    return Overlay.wrap(child: wrap(context, host, display));
  }

  // The root delegate is where OS back arrives under a Router (the inner
  // MultiNavDisplay PopScope is inert with no ModalRoute above it). Route it
  // through the host: pop the active tab, else fall back to the first tab.
  @override
  Future<bool> popRoute() => SynchronousFuture<bool>(host.handleBack());

  @override
  Future<void> setNewRoutePath(Uri configuration) async {
    // Same-location no-op — see NavStackRouterDelegate.setNewRoutePath.
    if (configuration == currentConfiguration) return;
    await handleLinkAsync(configuration);
  }

  /// Apply a runtime deep link to the tabbed host — the imperative sibling of
  /// [setNewRoutePath], for links delivered asynchronously by a native plugin
  /// (custom scheme, Firebase Dynamic Link, warm `app_links`). Selects the target
  /// tab and sets its stack, with the same never-throws hardening as a platform
  /// link. See [NavStackRouterDelegate.handleLink] for who owns what.
  void handleLink(Uri uri) {
    _linkGeneration++; // a sync link supersedes any in-flight async one
    _apply(_decodeOrFallback(uri));
  }

  /// [handleLink] with [asyncDecode] (when set) given the first shot — the
  /// multi-tab sibling of [NavStackRouterDelegate.handleLinkAsync].
  Future<void> handleLinkAsync(Uri uri) async {
    final resolve = asyncDecode;
    if (resolve == null) return handleLink(uri);
    final generation = ++_linkGeneration;
    MultiNavLocation<K>? loc;
    try {
      loc = await resolve(uri);
    } on Object catch (_) {
      loc = null; // resolution failed — fall through to the sync mapping
    }
    // Superseded by a newer link, or the delegate was swapped out and disposed.
    if (_disposed || generation != _linkGeneration) return;
    if (loc != null && (loc.tab < 0 || loc.tab >= host.length)) loc = null;
    _apply(loc ?? _decodeOrFallback(uri));
  }

  void _apply(MultiNavLocation<K>? loc) {
    if (loc == null) return;
    // Select without popping-to-root: we're about to set the stack explicitly.
    host.select(loc.tab, popToRootOnReselect: false);
    if (loc.stack.isNotEmpty) host.active.replaceAll(loc.stack);
  }

  /// Decode a URL to a location without ever throwing — same deep-link hardening
  /// as [NavStackRouterDelegate], for the multi-tab case. A decode that throws
  /// **or targets an out-of-range tab** falls back to [MultiNavStackCodec
  /// .fallbackFor]; if even the fallback misbehaves, keep the current screen.
  MultiNavLocation<K>? _decodeOrFallback(Uri uri) {
    try {
      final loc = codec.decode(uri);
      if (loc.tab >= 0 && loc.tab < host.length) return loc;
      // Out-of-range tab — treat like a malformed link and fall back.
    } on Object catch (_) {
      // Malformed link — fall through to the fallback below.
    }
    try {
      final loc = codec.fallbackFor(uri);
      if (loc.tab >= 0 && loc.tab < host.length) return loc;
      return null;
    } on Object catch (_) {
      return null; // Give up safely: keep whatever is already on screen.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    host.removeListener(notifyListeners);
    super.dispose();
  }
}
