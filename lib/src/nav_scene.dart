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
/// A thin convenience over [NavSceneHost] + [listDetailScene]; drop to those for
/// supporting panes, three columns, or a custom scene.
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
class NavListDetail<K extends NavKey> extends StatelessWidget {
  /// Creates an adaptive list-detail display over [stack].
  const NavListDetail({
    required this.stack,
    required this.isDetail,
    required this.list,
    required this.detail,
    this.placeholder,
    this.breakpoint = 600,
    this.listPaneWidth = 360,
    super.key,
  });

  /// The single back stack driving both layouts.
  final NavStack<K> stack;

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
  Widget build(BuildContext context) {
    return NavSceneHost<K>(
      stack: stack,
      // Single-pane / narrow fallback: detail or list by key.
      builder: (context, key) =>
          isDetail(key) ? detail(context, key) : list(context, key),
      scenes: [
        listDetailScene<K>(
          isDetail: isDetail,
          list: list,
          detail: detail,
          placeholder: placeholder,
          minWidth: breakpoint,
          listWidth: listPaneWidth,
        ),
      ],
    );
  }
}
