import 'package:back_stack/src/nav_display.dart';
import 'package:back_stack/src/nav_key.dart';
import 'package:back_stack/src/nav_stack.dart';
import 'package:flutter/widgets.dart';

/// Owns one [NavStack] per tab — the "you own the back stack" answer to a bottom
/// navigation bar with **persistent per-tab history** (go_router's
/// `StatefulShellRoute`).
///
/// Each tab keeps its own stack alive while you're on another tab; switching
/// back lands you exactly where you left. Pair it with [MultiNavDisplay].
///
/// Takes ownership of the tab stacks: [dispose] disposes them all.
///
/// ```dart
/// final tabs = MultiNavStack<AppKey>([
///   NavStack.of(const Feed()),
///   NavStack.of(const Search()),
///   NavStack.of(const Profile()),
/// ]);
/// // switch tab: tabs.select(1);   pop within tab / fall back: tabs.handleBack();
/// ```
class MultiNavStack<K extends NavKey> extends ChangeNotifier {
  /// Creates a host over [tabs], starting on [initialIndex].
  MultiNavStack(List<NavStack<K>> tabs, {int initialIndex = 0})
    : assert(tabs.isNotEmpty, 'MultiNavStack needs at least one tab'),
      assert(
        initialIndex >= 0 && initialIndex < tabs.length,
        'initialIndex out of range',
      ),
      _tabs = List.of(tabs),
      _index = initialIndex {
    for (final tab in _tabs) {
      tab.addListener(notifyListeners);
    }
  }

  final List<NavStack<K>> _tabs;
  int _index;

  /// The per-tab stacks.
  List<NavStack<K>> get tabs => List.unmodifiable(_tabs);

  /// The active tab index.
  int get index => _index;

  /// The active tab's stack.
  NavStack<K> get active => _tabs[_index];

  /// Number of tabs.
  int get length => _tabs.length;

  /// Whether [handleBack] would do anything (active tab can pop, or we're not
  /// on the first tab). Drives a host `PopScope`.
  bool get canHandleBack => active.canPop || _index != 0;

  /// Switch to tab [i]. Re-selecting the active tab pops it to its root when
  /// [popToRootOnReselect] is true — the familiar bottom-nav gesture.
  void select(int i, {bool popToRootOnReselect = true}) {
    assert(i >= 0 && i < _tabs.length, 'tab index out of range');
    if (i == _index) {
      if (popToRootOnReselect) _popToRoot(active);
      return;
    }
    _index = i;
    notifyListeners();
  }

  /// Handle a back request: pop within the active tab; else fall back to the
  /// first tab; else return false (nothing to do — let the app close). This is
  /// what a host `PopScope` calls.
  bool handleBack() {
    if (active.canPop) return active.pop();
    if (_index != 0) {
      _index = 0;
      notifyListeners();
      return true;
    }
    return false;
  }

  void _popToRoot(NavStack<K> stack) {
    while (stack.pop()) {}
  }

  @override
  void dispose() {
    for (final tab in _tabs) {
      tab
        ..removeListener(notifyListeners)
        ..dispose();
    }
    super.dispose();
  }
}

/// Renders a [MultiNavStack]: every tab's [NavDisplay] stays mounted (so its
/// state survives tab switches) via an [IndexedStack], and the system back
/// gesture pops the active tab — or falls back to the first tab — through a
/// `PopScope`.
///
/// You supply the bottom bar yourself; drive it from `host.index` /
/// `host.select(i)`.
class MultiNavDisplay<K extends NavKey> extends StatefulWidget {
  /// Creates a display for [host], rendering each destination with [builder].
  const MultiNavDisplay({
    required this.host,
    required this.builder,
    this.pageBuilder,
    this.observers = const [],
    this.lazy = false,
    super.key,
  });

  /// The per-tab stacks to render.
  final MultiNavStack<K> host;

  /// Maps a destination to its screen. See [NavDisplay.builder].
  final NavWidgetBuilder<K> builder;

  /// Optional custom page/transition. See [NavDisplay.pageBuilder].
  final NavPageBuilder<K>? pageBuilder;

  /// Attached to every tab's [Navigator] — your `screen_view` analytics seam,
  /// route logging, etc. Each tab's navigator reports its own pushes/pops.
  final List<NavigatorObserver> observers;

  /// When true, a tab's screens are built only after it's first selected, then
  /// kept alive — go_router's `StatefulShellRoute` default, and lighter when
  /// some tabs are heavy or rarely visited. When false (the default) every tab
  /// is built eagerly on the first frame, matching earlier behavior.
  final bool lazy;

  @override
  State<MultiNavDisplay<K>> createState() => _MultiNavDisplayState<K>();
}

class _MultiNavDisplayState<K extends NavKey> extends State<MultiNavDisplay<K>> {
  /// Tabs that have been shown at least once. Under [MultiNavDisplay.lazy], only
  /// these are built; the rest are cheap placeholders until first selected.
  final Set<int> _visited = {};

  @override
  void initState() {
    super.initState();
    _visited.add(widget.host.index);
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    // Provide the host to every screen below so a deep screen can switch tabs
    // via MultiBackStack.of(context) — no passing the host down by hand.
    return MultiNavStackScope<K>(
      host: host,
      child: ListenableBuilder(
        listenable: host,
        builder: (context, _) {
          _visited.add(host.index);
          return PopScope(
            // We only let the route system pop (close the app / leave the host)
            // when there's nothing to handle internally.
            canPop: !host.canHandleBack,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) host.handleBack();
            },
            child: IndexedStack(
              index: host.index,
              children: [
                for (var i = 0; i < host.length; i++)
                  if (!widget.lazy || _visited.contains(i))
                    NavDisplay<K>(
                      stack: host.tabs[i],
                      builder: widget.builder,
                      pageBuilder: widget.pageBuilder,
                      observers: widget.observers,
                    )
                  else
                    // Not yet visited: keep the slot so IndexedStack indices stay
                    // aligned with tab indices, but build nothing.
                    const SizedBox.shrink(),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Exposes a [MultiNavStack] to the widgets below it via [MultiBackStack.of].
///
/// [MultiNavDisplay] inserts one, so any screen in any tab can reach the host —
/// e.g. to switch tabs from deep inside a screen — without it being passed down.
/// Being an [InheritedNotifier], widgets that read with `listen: true` rebuild
/// when the active tab changes.
class MultiNavStackScope<K extends NavKey>
    extends InheritedNotifier<MultiNavStack<K>> {
  /// Provides [host] to the subtree under [child].
  const MultiNavStackScope({
    required MultiNavStack<K> host,
    required super.child,
    super.key,
  }) : super(notifier: host);

  /// The host provided to this subtree.
  MultiNavStack<K> get host => notifier!;
}

/// Reach the [MultiNavStack] host from a `BuildContext` — switch tabs
/// (`select`), read `index`, drive a bottom bar — from anywhere under a
/// [MultiNavDisplay].
///
/// ```dart
/// onTap: () => MultiBackStack.of<AppKey>(context).select(2),
/// ```
///
/// Like [BackStack.of], this does **not** subscribe the caller by default (right
/// for tap handlers). Pass `listen: true` to rebuild when the active tab
/// changes (e.g. a custom bottom bar that highlights the current tab).
abstract final class MultiBackStack {
  /// The nearest [MultiNavStack] of type [K]. Throws (in debug) if there's no
  /// matching [MultiNavStackScope] — which [MultiNavDisplay] provides.
  static MultiNavStack<K> of<K extends NavKey>(
    BuildContext context, {
    bool listen = false,
  }) {
    final host = maybeOf<K>(context, listen: listen);
    assert(
      host != null,
      'MultiBackStack.of<$K>() found no MultiNavStackScope<$K>. It is provided '
      'by MultiNavDisplay<$K>; call this from a screen it builds with the same '
      'key type.',
    );
    return host!;
  }

  /// The nearest [MultiNavStack] of type [K], or null if there is none above.
  static MultiNavStack<K>? maybeOf<K extends NavKey>(
    BuildContext context, {
    bool listen = false,
  }) {
    if (listen) {
      return context
          .dependOnInheritedWidgetOfExactType<MultiNavStackScope<K>>()
          ?.host;
    }
    final element = context
        .getElementForInheritedWidgetOfExactType<MultiNavStackScope<K>>();
    return (element?.widget as MultiNavStackScope<K>?)?.host;
  }
}
