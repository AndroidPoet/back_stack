import 'package:back_stack/src/nav_display.dart';
import 'package:back_stack/src/nav_key.dart';
import 'package:back_stack/src/nav_router.dart';
import 'package:back_stack/src/nav_stack.dart';
import 'package:flutter/material.dart';

/// The one-widget way to get deep links + web URL sync with back_stack.
///
/// It bundles the `MaterialApp.router` + [NavStackRouterDelegate] +
/// [NavStackRouteInformationParser] wiring so you don't write any of it. You
/// supply **one** function — [onLink], mapping an incoming `Uri` to the stack it
/// should show — and back_stack owns the rest: the OS/browser hands a deep link
/// to [onLink], the result becomes the stack, and system/browser back flow back
/// into the list.
///
/// ```dart
/// void main() => runApp(
///   BackStackApp<AppKey>(
///     stack: NavStack.of(const Home()),
///     builder: entries.call,
///     onLink: (uri) => switch (uri.pathSegments) {
///       ['products', final id] => [const Home(), Product(int.parse(id))],
///       _                      => [const Home()],
///     },
///   ),
/// );
/// ```
///
/// [onLink] is also called with the launch URL (`/` on mobile) on startup, so
/// return your home stack for it — that keeps the passed-in [stack] and the
/// first link in sync. It may parse optimistically: if it throws or returns
/// empty, [onLinkFallback] (or `/`) is shown instead of crashing.
///
/// Pass [toLink] to project the stack back onto the URL (for web address-bar
/// sync and shareable links); omit it and the URL just stays `/`. For a bottom
/// nav with per-tab history, or full control over `MaterialApp`, drop down to
/// [NavStackRouterDelegate] directly.
class BackStackApp<K extends NavKey> extends StatefulWidget {
  /// Creates an app that renders [stack] and routes deep links through [onLink].
  const BackStackApp({
    required this.stack,
    required this.builder,
    required this.onLink,
    this.toLink,
    this.onLinkFallback,
    this.pageBuilder,
    this.observers = const [],
    this.decorators = const [],
    this.title = '',
    this.color,
    this.theme,
    this.darkTheme,
    this.themeMode = ThemeMode.system,
    this.locale,
    this.localizationsDelegates,
    this.supportedLocales = const [Locale('en', 'US')],
    this.scrollBehavior,
    this.debugShowCheckedModeBanner = true,
    this.restorationScopeId = 'back_stack',
    super.key,
  });

  /// The back stack to render — the single source of truth. You own it.
  final NavStack<K> stack;

  /// Maps a destination to its screen. Hand it [NavEntries.call] or a `switch`.
  final NavWidgetBuilder<K> builder;

  /// A `Uri` → the stack to show. This is the deep-link map, and the *only*
  /// required piece. Return every destination you want on the stack for the URL
  /// (this is where you choose layer-vs-replace). Parse optimistically.
  final List<K> Function(Uri uri) onLink;

  /// The stack → the URL to show, for web address-bar sync. Omit to keep the URL
  /// at `/` (fine on mobile).
  final Uri Function(List<K> stack)? toLink;

  /// The stack shown when a link can't be parsed (i.e. [onLink] threw or was
  /// empty). Defaults to `onLink(Uri(path: '/'))`.
  final List<K>? onLinkFallback;

  /// Optional custom page/transition. See [NavDisplay.pageBuilder].
  final NavPageBuilder<K>? pageBuilder;

  /// Forwarded to the display's [Navigator] — a `screen_view` analytics seam.
  final List<NavigatorObserver> observers;

  /// Cross-cutting wrappers/cleanup for every screen. See [NavEntryDecorator].
  final List<NavEntryDecorator<K>> decorators;

  /// Forwarded to `MaterialApp.title`.
  final String title;

  /// Forwarded to `MaterialApp.color`.
  final Color? color;

  /// Forwarded to `MaterialApp.theme`.
  final ThemeData? theme;

  /// Forwarded to `MaterialApp.darkTheme`.
  final ThemeData? darkTheme;

  /// Forwarded to `MaterialApp.themeMode`.
  final ThemeMode themeMode;

  /// Forwarded to `MaterialApp.locale`.
  final Locale? locale;

  /// Forwarded to `MaterialApp.localizationsDelegates`.
  final Iterable<LocalizationsDelegate<dynamic>>? localizationsDelegates;

  /// Forwarded to `MaterialApp.supportedLocales`.
  final Iterable<Locale> supportedLocales;

  /// Forwarded to `MaterialApp.scrollBehavior`.
  final ScrollBehavior? scrollBehavior;

  /// Forwarded to `MaterialApp.debugShowCheckedModeBanner`.
  final bool debugShowCheckedModeBanner;

  /// Forwarded to `MaterialApp.restorationScopeId` — set (default `back_stack`)
  /// so the stack survives process death without any extra work.
  final String? restorationScopeId;

  @override
  State<BackStackApp<K>> createState() => _BackStackAppState<K>();
}

class _BackStackAppState<K extends NavKey> extends State<BackStackApp<K>> {
  late final NavStackRouterDelegate<K> _delegate = NavStackRouterDelegate<K>(
    stack: widget.stack,
    codec: NavStackCodec<K>.of(
      encode: widget.toLink ?? (_) => Uri(path: '/'),
      decode: widget.onLink,
      fallback: widget.onLinkFallback,
    ),
    builder: widget.builder,
    pageBuilder: widget.pageBuilder,
    observers: widget.observers,
    decorators: widget.decorators,
  );

  @override
  void dispose() {
    // We created the delegate; the caller owns (and disposes) the stack.
    _delegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerDelegate: _delegate,
      routeInformationParser: const NavStackRouteInformationParser(),
      title: widget.title,
      color: widget.color,
      theme: widget.theme,
      darkTheme: widget.darkTheme,
      themeMode: widget.themeMode,
      locale: widget.locale,
      localizationsDelegates: widget.localizationsDelegates,
      supportedLocales: widget.supportedLocales,
      scrollBehavior: widget.scrollBehavior,
      debugShowCheckedModeBanner: widget.debugShowCheckedModeBanner,
      restorationScopeId: widget.restorationScopeId,
    );
  }
}
