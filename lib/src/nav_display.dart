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

/// Wraps every entry's screen with cross-cutting logic — back_stack's take on
/// Compose Nav3's `NavEntryDecorator`.
///
/// Two hooks, both optional:
/// - [decorate] runs when each screen is built — wrap it in a provider/scope,
///   inject a dependency, add tracing. In a list of decorators the **first is
///   the outermost** wrapper.
/// - [onRemoved] runs when an entry leaves the stack — popped, replaced, or the
///   whole display disposed. Tear down anything you scoped to that destination:
///   a Bloc, a controller, a DI scope. This is the piece Flutter's own
///   `State.dispose` can't give you for *non-widget* objects.
///
/// ```dart
/// NavDisplay<AppKey>(
///   stack: stack,
///   builder: screenFor,
///   decorators: [
///     NavEntryDecorator(
///       decorate: (context, key, child) =>
///           ProviderScope(overrides: [scopeFor(key)], child: child),
///       onRemoved: (key) => disposeScopeFor(key),
///     ),
///   ],
/// )
/// ```
///
/// Create decorators once (a `const`, a field, or a `State` member) — like
/// [NavDisplay.observers], not fresh in `build`. Decoration applies to
/// [NavDisplay.builder]-built screens; a fully custom [NavDisplay.pageBuilder]
/// owns its own content, so it isn't decorated.
@immutable
class NavEntryDecorator<K extends NavKey> {
  /// Creates a decorator from an optional [decorate] wrapper and optional
  /// [onRemoved] cleanup — supply either or both.
  const NavEntryDecorator({this.decorate, this.onRemoved});

  /// Wrap `child` (the screen built for `key`) — e.g. in a scope/provider.
  final Widget Function(BuildContext context, K key, Widget child)? decorate;

  /// Called when the entry for `key` leaves the stack. Clean up anything scoped
  /// to it here. Fires once per removal (and for any entries still present when
  /// the display is disposed).
  final void Function(K key)? onRemoved;
}

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
    this.decorators = const [],
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

  /// Cross-cutting wrappers/cleanup applied to every screen. See
  /// [NavEntryDecorator]. The first decorator is the outermost wrapper.
  final List<NavEntryDecorator<K>> decorators;

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

  /// Keys of entries currently on the stack, by id — so when an id disappears we
  /// can fire [NavEntryDecorator.onRemoved] with the right key. Only maintained
  /// when there are decorators.
  final Map<int, K> _seen = {};

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
    // The display is going away — let decorators clean up any entry still on
    // the stack (their screens' State.dispose won't touch non-widget scopes).
    if (widget.decorators.isNotEmpty) {
      _seen.values.forEach(_notifyRemoved);
      _seen.clear();
    }
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
      // A swapped stack/builder is a different display, not a pop — forget the
      // old entries without firing onRemoved (their identity no longer applies).
      _seen.clear();
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

          // Fire onRemoved for any entry that has left the stack, then refresh
          // the id→key record for next time.
          if (widget.decorators.isNotEmpty) {
            for (final seen in _seen.entries) {
              if (!live.contains(seen.key)) _notifyRemoved(seen.value);
            }
            _seen
              ..clear()
              ..addEntries([for (final e in entries) MapEntry(e.id, e.key)]);
          }

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
    final content = _decorate(context, key, widget.builder(context, key));
    if (key is NavPage) {
      return (key as NavPage).buildPage(context, content, pageKey);
    }
    return MaterialPage<dynamic>(key: pageKey, child: content);
  }

  /// Wrap [child] with each decorator's `decorate`, first-decorator-outermost.
  Widget _decorate(BuildContext context, K key, Widget child) {
    if (widget.decorators.isEmpty) return child;
    var result = child;
    for (final decorator in widget.decorators.reversed) {
      final wrap = decorator.decorate;
      if (wrap != null) result = wrap(context, key, result);
    }
    return result;
  }

  void _notifyRemoved(K key) {
    for (final decorator in widget.decorators) {
      decorator.onRemoved?.call(key);
    }
  }
}
