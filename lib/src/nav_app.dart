import 'dart:async';

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
/// **Async links from native.** The platform hands back_stack the launch URL and
/// the standard app links it handles itself. Links that arrive *while the app is
/// running* — a custom scheme (`myapp://…`), a Firebase Dynamic Link, a warm
/// `app_links` link — come from a native plugin as a `Stream<Uri>` instead. Pass
/// that stream as [linkStream] and every emission runs through the same [onLink]:
///
/// ```dart
/// // Create the plugin EARLY — a top-level singleton (or in main() before
/// // runApp), never lazily inside a widget. See the ordering note below.
/// final appLinks = AppLinks(); // from the app_links package (you own the plugin)
///
/// BackStackApp<AppKey>(
///   stack: NavStack.of(const Home()),
///   builder: entries.call,
///   onLink: (uri) => /* map Uri → stack */,
///   initialLink: appLinks.getInitialLink(), // cold-start link (any plugin version)
///   linkStream: appLinks.uriLinkStream,     // warm links while running
/// );
/// ```
///
/// **Cold start: order, not luck.** `app_links`' `uriLinkStream` replays the
/// launch URI (the one that cold-started the app) to its first listener — but
/// only if the `AppLinks()` singleton already exists when the OS delivers it.
/// Create it early (a top-level `final`, or in `main()` before `runApp`); create
/// it late, deep in a widget's build, and the first link is already gone.
///
/// Don't want to depend on that replay behaviour at all? Pass [initialLink] the
/// plugin's `getInitialLink()` future — back_stack awaits it and applies the
/// launch link through the same [onLink], which is the version-independent way to
/// survive a custom-scheme cold start. Use both together: [initialLink] for the
/// launch link, [linkStream] for warm ones; re-applying the same link is a no-op.
///
/// back_stack stays dependency-free: it owns the `Uri` → stack mapping and the
/// subscription lifecycle; you bring the `Uri`s from whatever plugin you prefer.
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
    this.linkStream,
    this.initialLink,
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

  /// A stream of deep links arriving **asynchronously from native** while the app
  /// runs (custom-scheme links, Firebase Dynamic Links, warm `app_links` links).
  /// Each `Uri` is routed through [onLink] with the same fallback safety as a
  /// platform link. Bring it from your deep-link plugin (e.g.
  /// `AppLinks().uriLinkStream`); back_stack owns the subscription and cancels it
  /// on dispose. Omit it if you only need the launch URL and web links.
  ///
  /// Construct the plugin (e.g. `AppLinks()`) **early** — a top-level singleton or
  /// in `main()` — so the cold-start URI isn't lost. See the class docs.
  final Stream<Uri>? linkStream;

  /// The one-shot link that **cold-started** the app, if any — hand it
  /// `AppLinks().getInitialLink()`. back_stack awaits it once on startup and, if
  /// non-null, runs it through [onLink] (same fallback safety), so the launch deep
  /// link lands even when [linkStream] doesn't replay it (the version-independent
  /// way to survive a custom-scheme cold start). Safe to use alongside
  /// [linkStream]: re-applying the same link is a no-op. Omit it if the platform
  /// already delivers your launch link (standard app links / web).
  final Future<Uri?>? initialLink;

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

  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    // Feed runtime links from the app's plugin through the same onLink mapping.
    _linkSub = widget.linkStream?.listen(_delegate.handleLink);
    // Apply the cold-start link (if any) once it resolves — through the same
    // mapping. Guarded on `mounted` in case we're disposed before it arrives.
    final initial = widget.initialLink;
    if (initial != null) {
      unawaited(
        initial.then((uri) {
          if (uri != null && mounted) _delegate.handleLink(uri);
        }),
      );
    }
  }

  @override
  void didUpdateWidget(BackStackApp<K> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-subscribe only if the stream instance actually changed.
    if (widget.linkStream != oldWidget.linkStream) {
      unawaited(_linkSub?.cancel());
      _linkSub = widget.linkStream?.listen(_delegate.handleLink);
    }
  }

  @override
  void dispose() {
    unawaited(_linkSub?.cancel());
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
