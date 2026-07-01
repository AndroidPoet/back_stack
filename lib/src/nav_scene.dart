import 'package:back_stack/src/nav_display.dart';
import 'package:back_stack/src/nav_key.dart';
import 'package:back_stack/src/nav_scope.dart';
import 'package:back_stack/src/nav_stack.dart';
import 'package:flutter/material.dart';

/// What a [NavSceneStrategy] is handed: the live stack plus the room it has.
///
/// A strategy reads [keys]/[top] and [width] and decides whether — and how — to
/// present the top slice of the **one** stack as a combined adaptive layout.
class NavSceneContext<K extends NavKey> {
  /// Created by [NavSceneHost] on every layout pass.
  const NavSceneContext({
    required this.context,
    required this.constraints,
    required this.stack,
    required this.builder,
  });

  /// The enclosing build context.
  final BuildContext context;

  /// The space available to the display.
  final BoxConstraints constraints;

  /// The single source of truth.
  final NavStack<K> stack;

  /// The single-pane builder (what each destination is when shown alone). A
  /// custom strategy can call this to render any key into a pane.
  final NavWidgetBuilder<K> builder;

  /// The destinations, bottom-to-top.
  List<K> get keys => stack.keys;

  /// The destination on top.
  K get top => stack.current;

  /// Available width — the usual thing a strategy switches on.
  double get width => constraints.maxWidth;
}

/// Decides how to render a slice of the stack as one adaptive layout — the
/// general form of Compose Nav3's `SceneStrategy`, over a single [NavStack].
///
/// Return a widget to **claim** the layout (present several top entries
/// together — two panes, a supporting pane, three columns…). Return `null` to
/// **decline**, and [NavSceneHost] tries the next strategy, falling back to a
/// plain animated stack. This is how one ordered list becomes any adaptive
/// shell without a second navigation model or a coordinator.
typedef NavSceneStrategy<K extends NavKey> =
    Widget? Function(
      NavSceneContext<K> scene,
    );

/// Renders a [NavStack] through a list of [NavSceneStrategy]s: the first one to
/// claim the current (stack, width) wins; if none do, it falls back to a normal
/// single-pane [NavDisplay] (full transitions + system back).
///
/// Everything stays driven by the one stack — the system back button, deep
/// links, URL sync and [NavStack.pushForResult] all operate on it, in every
/// layout. This is the engine behind [NavListDetail]; reach for it directly when
/// you want a supporting pane, three columns, or your own custom scene.
///
/// ```dart
/// NavSceneHost<AppKey>(
///   stack: stack,
///   builder: (context, key) => screenFor(key),   // single-pane fallback
///   scenes: [
///     supportingPaneScene(isSupporting: (k) => k is Filters, primary: ..., supporting: ...),
///     listDetailScene(isDetail: (k) => k is Item, list: ..., detail: ...),
///   ],
/// )
/// ```
class NavSceneHost<K extends NavKey> extends StatelessWidget {
  /// Creates a scene host over [stack].
  const NavSceneHost({
    required this.stack,
    required this.builder,
    required this.scenes,
    this.pageBuilder,
    this.observers = const [],
    this.decorators = const [],
    super.key,
  });

  /// The single back stack driving every layout.
  final NavStack<K> stack;

  /// The single-pane builder: each destination shown alone, and the narrow
  /// fallback. Strategies also receive it via [NavSceneContext.builder].
  final NavWidgetBuilder<K> builder;

  /// Strategies tried in order; the first to return non-null claims the frame.
  final List<NavSceneStrategy<K>> scenes;

  /// Optional custom page/transition for the single-pane fallback.
  final NavPageBuilder<K>? pageBuilder;

  /// Forwarded to the single-pane fallback [NavDisplay]'s [Navigator]. Note that
  /// a *claimed* scene renders panes directly (no Navigator), so observers only
  /// fire while the layout is in its stacked/narrow form.
  final List<NavigatorObserver> observers;

  /// Applied to the single-pane fallback's screens. See [NavEntryDecorator].
  final List<NavEntryDecorator<K>> decorators;

  @override
  Widget build(BuildContext context) {
    return NavStackScope<K>(
      stack: stack,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ListenableBuilder(
            listenable: stack,
            builder: (context, _) {
              final ctx = NavSceneContext<K>(
                context: context,
                constraints: constraints,
                stack: stack,
                builder: builder,
              );
              for (final strategy in scenes) {
                final scene = strategy(ctx);
                if (scene != null) return _claimBack(scene);
              }
              // No scene claimed it → a plain animated stack.
              return NavDisplay<K>(
                stack: stack,
                builder: builder,
                pageBuilder: pageBuilder,
                observers: observers,
                decorators: decorators,
              );
            },
          );
        },
      ),
    );
  }

  // A scene shows several entries at once, so the Navigator isn't handling
  // back; route the system gesture to the one stack while it can pop.
  Widget _claimBack(Widget scene) {
    return PopScope(
      canPop: !stack.canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) stack.pop();
      },
      child: scene,
    );
  }
}

/// A ready-made [NavSceneStrategy]: **list-detail**. When `width >= minWidth`
/// it lays the latest list destination beside the top detail (or [placeholder]
/// when none is selected); below `minWidth` it declines, so the host shows a
/// normal stack. This is exactly what [NavListDetail] runs.
NavSceneStrategy<K> listDetailScene<K extends NavKey>({
  required bool Function(K key) isDetail,
  required NavWidgetBuilder<K> list,
  required NavWidgetBuilder<K> detail,
  WidgetBuilder? placeholder,
  double minWidth = 600,
  double listWidth = 360,
}) {
  return (scene) {
    if (scene.width < minWidth) return null; // narrow → fall back to a stack
    final keys = scene.keys;
    final listKey = keys.lastWhere(
      (k) => !isDetail(k),
      orElse: () => keys.first,
    );
    final top = keys.last;
    final detailKey = isDetail(top) ? top : null;

    return Row(
      children: [
        SizedBox(width: listWidth, child: list(scene.context, listKey)),
        const VerticalDivider(width: 1),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: detailKey == null
                ? (placeholder?.call(scene.context) ??
                      const ColoredBox(color: Color(0x00000000)))
                : KeyedSubtree(
                    key: ValueKey(scene.stack.entries.last.id),
                    child: detail(scene.context, detailKey),
                  ),
          ),
        ),
      ],
    );
  };
}

/// A ready-made [NavSceneStrategy]: **supporting pane**. When a supporting
/// destination is on top *and* `width >= minWidth`, it shows the primary
/// content with the supporting pane docked beside it (fixed [supportingWidth]).
/// Otherwise it declines — so on a phone the supporting destination is just a
/// normal pushed page. Proves the engine isn't list-detail-only.
NavSceneStrategy<K> supportingPaneScene<K extends NavKey>({
  required bool Function(K key) isSupporting,
  required NavWidgetBuilder<K> primary,
  required NavWidgetBuilder<K> supporting,
  double minWidth = 840,
  double supportingWidth = 320,
  bool supportingOnRight = true,
}) {
  return (scene) {
    final keys = scene.keys;
    final top = keys.last;
    if (!isSupporting(top)) return null; // nothing to dock → decline
    if (scene.width < minWidth) return null; // narrow → push it as a page
    final primaryKey = keys.lastWhere(
      (k) => !isSupporting(k),
      orElse: () => keys.first,
    );

    final primaryPane = Expanded(child: primary(scene.context, primaryKey));
    final supportPane = SizedBox(
      width: supportingWidth,
      child: supporting(scene.context, top),
    );
    return Row(
      children: supportingOnRight
          ? [primaryPane, const VerticalDivider(width: 1), supportPane]
          : [supportPane, const VerticalDivider(width: 1), primaryPane],
    );
  };
}

/// Adaptive **list-detail** over a single [NavStack] — the marquee Nav3 idea:
/// one back stack, rendered two ways. On a wide screen the list and detail sit
/// side by side; on a phone the same stack collapses to a normal animated stack.
/// You write the stack once; the layout follows the window.
///
/// Unlike the generic [NavSceneHost] + [listDetailScene] path, this widget keeps
/// each pane's `State` alive **across the breakpoint**: a screen keeps its scroll
/// position and controllers when you rotate/resize between the two-pane and
/// stacked layouts. It does this by giving every entry a stable [GlobalKey], so
/// Flutter *reparents* the existing screen Element to its new home instead of
/// rebuilding it. Reach for [NavSceneHost] directly for supporting panes, three
/// columns, or a custom scene.
///
/// ```dart
/// NavListDetail<AppKey>(
///   stack: stack,
///   isDetail: (key) => key is Message,
///   list:   (context, key) => InboxScreen(),
///   detail: (context, key) => MessageScreen(key as Message),
///   placeholder: (context) => const Center(child: Text('Pick a message')),
/// )
/// ```
class NavListDetail<K extends NavKey> extends StatefulWidget {
  /// Creates an adaptive list-detail display over [stack].
  const NavListDetail({
    required this.stack,
    required this.isDetail,
    required this.list,
    required this.detail,
    this.placeholder,
    this.breakpoint = 600,
    this.listPaneWidth = 360,
    this.observers = const [],
    this.decorators = const [],
    super.key,
  });

  /// The single back stack driving both layouts.
  final NavStack<K> stack;

  /// Forwarded to the narrow/stacked layout's [NavDisplay]. See
  /// [NavDisplay.observers]. (The wide two-pane layout has no [Navigator].)
  final List<NavigatorObserver> observers;

  /// Applied to screens in both layouts. See [NavEntryDecorator]. (In the wide
  /// two-pane layout `onRemoved` still fires when an entry leaves the stack.)
  final List<NavEntryDecorator<K>> decorators;

  /// True for destinations that are a "detail" (the right pane / pushed page).
  final bool Function(K key) isDetail;

  /// Builds a list/root destination (left pane, or full page on narrow).
  final NavWidgetBuilder<K> list;

  /// Builds a detail destination (right pane, or pushed page on narrow).
  final NavWidgetBuilder<K> detail;

  /// Right-pane filler shown wide when no detail is selected.
  final WidgetBuilder? placeholder;

  /// Width (logical px) at or above which the two-pane layout is used.
  final double breakpoint;

  /// Fixed width of the list pane in two-pane mode.
  final double listPaneWidth;

  @override
  State<NavListDetail<K>> createState() => _NavListDetailState<K>();
}

class _NavListDetailState<K extends NavKey> extends State<NavListDetail<K>> {
  /// A stable [GlobalKey] per entry id. Because this State outlives the
  /// breakpoint flip (only its child subtree swaps), the same key wraps an
  /// entry's screen whether it's a two-pane child (wide) or a [Navigator] page
  /// (narrow) — so Flutter reparents the live Element rather than rebuilding it.
  final Map<int, GlobalKey> _paneKeys = {};

  GlobalKey _keyFor(int id) =>
      _paneKeys.putIfAbsent(id, () => GlobalKey(debugLabel: 'pane-$id'));

  /// id→key of entries that have actually been **rendered** (as a wide pane or a
  /// narrow page). [NavEntryDecorator.onRemoved] fires for an id in here once it
  /// leaves the stack — so a wide-only middle entry that was never shown doesn't
  /// get a spurious `onRemoved` with no matching `decorate`. Handled here (not
  /// delegated to the narrow [NavDisplay]) so it stays correct across the
  /// breakpoint. Only maintained when there are decorators.
  final Map<int, K> _seen = {};

  void _markRendered(int id, K key) {
    if (widget.decorators.isNotEmpty) _seen[id] = key;
  }

  @override
  void dispose() {
    if (widget.decorators.isNotEmpty) {
      _seen.values.forEach(_notifyRemoved);
      _seen.clear();
    }
    super.dispose();
  }

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

  @override
  Widget build(BuildContext context) {
    final stack = widget.stack;
    return NavStackScope<K>(
      stack: stack,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ListenableBuilder(
            listenable: stack,
            builder: (context, _) {
              final entries = stack.entries;
              final liveIds = {for (final e in entries) e.id};
              // Drop keys for entries that have left the stack.
              _paneKeys.removeWhere((id, _) => !liveIds.contains(id));
              // Fire onRemoved for rendered entries (recorded in _seen when a
              // pane/page built them) that have now left the stack, and drop
              // them. Entries never rendered were never decorated, so they
              // correctly get no onRemoved.
              if (widget.decorators.isNotEmpty) {
                _seen.removeWhere((id, key) {
                  if (!liveIds.contains(id)) {
                    _notifyRemoved(key);
                    return true;
                  }
                  return false;
                });
              }

              return constraints.maxWidth >= widget.breakpoint
                  ? _buildWide(context, stack)
                  : _buildNarrow(context, stack);
            },
          );
        },
      ),
    );
  }

  Widget _buildWide(BuildContext context, NavStack<K> stack) {
    final entries = stack.entries;
    final listEntry = entries.lastWhere(
      (e) => !widget.isDetail(e.key),
      orElse: () => entries.first,
    );
    final topEntry = entries.last;
    // If the only/first entry is itself a detail there's no distinct list entry
    // to pair it with (listEntry falls back to the same entry). Show it as the
    // list and leave the detail pane empty, rather than mounting the same
    // per-entry GlobalKey in both panes — which would throw a duplicate-key error.
    final detailEntry =
        widget.isDetail(topEntry.key) && topEntry.id != listEntry.id
        ? topEntry
        : null;

    // Record what's actually on screen so onRemoved fires (once) for these — and
    // only these — when they later leave the stack.
    _markRendered(listEntry.id, listEntry.key);
    if (detailEntry != null) _markRendered(detailEntry.id, detailEntry.key);

    final detailChild = detailEntry == null
        ? (widget.placeholder?.call(context) ??
              const ColoredBox(color: Color(0x00000000)))
        : KeyedSubtree(
            key: _keyFor(detailEntry.id),
            child: _decorate(
              context,
              detailEntry.key,
              widget.detail(context, detailEntry.key),
            ),
          );

    // The two panes aren't inside a Navigator, so route the system back gesture
    // to the one stack while it can pop.
    return PopScope(
      canPop: !stack.canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) stack.pop();
      },
      child: Row(
        children: [
          SizedBox(
            width: widget.listPaneWidth,
            child: KeyedSubtree(
              key: _keyFor(listEntry.id),
              child: _decorate(
                context,
                listEntry.key,
                widget.list(context, listEntry.key),
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: detailChild,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNarrow(BuildContext context, NavStack<K> stack) {
    return NavDisplay<K>(
      stack: stack,
      observers: widget.observers,
      builder: (context, key) => widget.isDetail(key)
          ? widget.detail(context, key)
          : widget.list(context, key),
      // decorators are applied here (not passed to NavDisplay) so onRemoved
      // fires exactly once, tracked by this State across the breakpoint.
      // Wrap each page's screen in the same per-entry GlobalKey the wide layout
      // uses, so crossing the breakpoint reparents rather than rebuilds.
      pageBuilder: (context, key, pageKey) {
        final id = (pageKey as ValueKey<int>).value;
        // Same rendered-entry bookkeeping as the wide layout, so onRemoved is
        // symmetric across the breakpoint.
        _markRendered(id, key);
        return MaterialPage<dynamic>(
          key: pageKey,
          child: KeyedSubtree(
            key: _keyFor(id),
            child: _decorate(
              context,
              key,
              widget.isDetail(key)
                  ? widget.detail(context, key)
                  : widget.list(context, key),
            ),
          ),
        );
      },
    );
  }
}
