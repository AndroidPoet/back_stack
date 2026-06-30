import 'package:back_stack/src/nav_display.dart';
import 'package:back_stack/src/nav_key.dart';
import 'package:back_stack/src/nav_stack.dart';
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

  /// The whole stack → the URL to show. Typically derived from `stack.last`.
  Uri encode(List<K> stack);

  /// A URL → the full stack to display. Return every destination you want on
  /// the stack for this URL (this is where you choose layer-vs-replace). Must
  /// return at least one destination.
  List<K> decode(Uri uri);
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
    );
  }

  @override
  Future<void> setNewRoutePath(Uri configuration) async {
    final next = codec.decode(configuration);
    if (next.isNotEmpty) stack.replaceAll(next);
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
