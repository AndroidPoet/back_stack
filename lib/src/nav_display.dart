import 'package:back_stack/src/nav_key.dart';
import 'package:back_stack/src/nav_pages.dart';
import 'package:back_stack/src/nav_scope.dart';
import 'package:back_stack/src/nav_stack.dart';
import 'package:flutter/material.dart';

/// Builds the screen widget for a destination of type [K].
typedef NavWidgetBuilder<K extends NavKey> =
    Widget Function(
      BuildContext context,
      K key,
    );

/// Builds a full [Page] for a destination — use this to customize the
/// transition. The returned page's `key` is set for you, so just return e.g.
/// `MaterialPage(child: ...)` or a custom `Page` subclass.
typedef NavPageBuilder<K extends NavKey> =
    Page<dynamic> Function(
      BuildContext context,
      K key,
      LocalKey pageKey,
    );

/// Renders a [NavStack] and nothing more.
///
/// It watches the stack and rebuilds the underlying [Navigator] whenever the
/// list changes. System back gestures, the Android predictive-back animation,
/// and the hardware back button all flow back into the stack automatically via
/// [Navigator.onDidRemovePage] — you never wire that up.
///
/// Typed over your destination type [K], so [builder] receives your own key
/// directly — no `as` cast, and the `switch` is exhaustive:
///
/// ```dart
/// NavDisplay<AppKey>(
///   stack: stack,
///   builder: (context, key) => switch (key) {
///     Home() => const HomeScreen(),
///     ProductDetail(:final id) => ProductScreen(id: id),
///   },
/// )
/// ```
class NavDisplay<K extends NavKey> extends StatefulWidget {
  /// Creates a display for [stack], mapping each destination via [builder].
  const NavDisplay({
    required this.stack,
    required this.builder,
    this.pageBuilder,
    this.observers = const [],
    this.navigatorKey,
    this.nested = false,
    super.key,
  });

  /// The back stack to render. The single source of truth.
  final NavStack<K> stack;

  /// Optional key for the underlying [Navigator]. Supply a stable key (created
  /// once, e.g. in a `State` or a `RouterDelegate`) when something outside needs
  /// to drive this navigator — e.g. routing a system/predictive back gesture
  /// into it via `maybePop`. Never create a fresh key in `build`.
  final GlobalKey<NavigatorState>? navigatorKey;

  /// Maps a destination to its screen widget. Wrapped in a default platform
  /// page. Ignored when [pageBuilder] is provided.
  final NavWidgetBuilder<K> builder;

  /// Optional: build the whole [Page] yourself to control the transition.
  /// Takes precedence over [builder].
  final NavPageBuilder<K>? pageBuilder;

  /// Forwarded to the underlying [Navigator].
  final List<NavigatorObserver> observers;

  /// Set true when this display is **nested inside another** (a child stack
  /// living inside a screen — a tab, a wizard, a master/detail pane).
  ///
  /// A nested [Navigator] doesn't receive the system back gesture on its own —
  /// the event goes to the outermost route. With [nested] on, this display wraps
  /// itself in a `PopScope` that claims the gesture while its own stack
  /// [NavStack.canPop], popping the child first and only letting back bubble up
  /// to the parent once the child is at its root. That's innermost-first back
  /// for free. Leave it false for a top-level display.
  final bool nested;

  @override
  State<NavDisplay<K>> createState() => _NavDisplayState<K>();
}

class _NavDisplayState<K extends NavKey> extends State<NavDisplay<K>> {
  /// Pages memoized by entry id. A NavEntry's (id, key) pair never changes, so a
  /// surviving entry reuses its exact page — the destination builder runs only
  /// for *new* entries, not for every entry on every change. That's minimal
  /// rebuilds without a diff algorithm: the stable id already is the diff.
  final Map<int, Page<dynamic>> _pages = {};

  /// This [Navigator]'s own [HeroController], handed to it via a
  /// [HeroControllerScope] below. `MaterialApp` creates one material
  /// HeroController, but a single controller can only drive one Navigator — the
  /// root one claims it, so a *nested* `NavDisplay` (e.g. inside `NavListDetail`
  /// or under `MaterialApp(home:)`) is left without one, and a `Hero` flight
  /// (shared-element transition) between two of our pages silently doesn't
  /// animate. Giving this Navigator its own controller via a scope fixes that
  /// and, because the scope shadows any ancestor one, also keeps the root/Router
  /// case to exactly one controller (no double flights). Kept for the life of
  /// the State — a HeroController is stateful, so rebuilding it each frame would
  /// drop in-flight animations. Uses the same arc tween Material uses.
  late final HeroController _heroController = HeroController(
    createRectTween: (begin, end) =>
        MaterialRectArcTween(begin: begin, end: end),
  );

  @override
  void dispose() {
    _heroController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(NavDisplay<K> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different stack (or a different page-building strategy) invalidates the
    // memoized pages.
    if (!identical(widget.stack, oldWidget.stack) ||
        !identical(widget.builder, oldWidget.builder) ||
        !identical(widget.pageBuilder, oldWidget.pageBuilder)) {
      _pages.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Provide the stack to every screen below via BackStack.of<K>(context).
    return NavStackScope<K>(
      stack: widget.stack,
      child: ListenableBuilder(
        listenable: widget.stack,
        builder: (context, _) {
          final entries = widget.stack.entries;
          final live = {for (final e in entries) e.id};
          _pages.removeWhere((id, _) => !live.contains(id));

          final navigator = HeroControllerScope(
            controller: _heroController,
            child: Navigator(
              key: widget.navigatorKey,
              observers: widget.observers,
              pages: [
                for (final entry in entries)
                  _pages[entry.id] ??= _pageFor(
                    context,
                    entry.key,
                    ValueKey(entry.id),
                  ),
              ],
              onDidRemovePage: (page) {
                final key = page.key;
                if (key is ValueKey<int>) widget.stack.syncRemoved(key.value);
              },
            ),
          );
          if (!widget.nested) return navigator;
          return PopScope(
            // Claim back while the child can pop; release it (let the parent /
            // app handle it) once we're at this stack's root.
            canPop: !widget.stack.canPop,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) widget.stack.pop();
            },
            child: navigator,
          );
        },
      ),
    );
  }

  Page<dynamic> _pageFor(BuildContext context, K key, LocalKey pageKey) {
    final custom = widget.pageBuilder;
    if (custom != null) return custom(context, key, pageKey);
    if (key is NavPage) {
      return key.buildPage(context, widget.builder(context, key), pageKey);
    }
    return MaterialPage<dynamic>(
      key: pageKey,
      child: widget.builder(context, key),
    );
  }
}
