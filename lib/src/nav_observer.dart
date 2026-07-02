import 'package:back_stack/src/nav_key.dart';
import 'package:back_stack/src/nav_stack.dart';

/// Typed, stack-level navigation events — the analytics/logging seam that speaks
/// in *your* [NavKey]s instead of framework [Route]s.
///
/// A `NavigatorObserver` hands you `Route` objects whose `settings.name` you have
/// to reverse-engineer. This observes the [NavStack] itself: it diffs entry
/// identities on every change and calls back with the actual destination that was
/// pushed, popped, or is now on screen. Perfect for `screen_view` analytics:
///
/// ```dart
/// final analytics = NavStackObserver<AppKey>(
///   stack,
///   onScreen: (key) => analytics.logScreen(key.runtimeType.toString()),
///   onPush: (key) => debugPrint('→ $key'),
///   onPop: (key) => debugPrint('← $key'),
/// );
/// // ... later
/// analytics.dispose();
/// ```
///
/// [onScreen] fires whenever the visible top changes (and once on construction
/// for the initial screen, unless [emitInitial] is false) — that's your
/// screen-view signal. [onPush]/[onPop] fire per destination that enters/leaves,
/// so a single `replaceAll` reports each added and removed screen exactly once.
/// Reconciled survivors (same key kept across a change) don't re-fire.
class NavStackObserver<K extends NavKey> {
  /// Starts observing [stack]. Detach with [dispose] when you're done (it does
  /// not own the stack).
  NavStackObserver(
    this.stack, {
    this.onScreen,
    this.onPush,
    this.onPop,
    bool emitInitial = true,
  }) : _lastEntries = stack.entries {
    _lastTopId = stack.entries.last.id;
    if (emitInitial) onScreen?.call(stack.current);
    stack.addListener(_handle);
  }

  /// The stack being observed.
  final NavStack<K> stack;

  /// The visible top destination changed — your `screen_view` signal.
  final void Function(K current)? onScreen;

  /// A destination was added to the stack.
  final void Function(K key)? onPush;

  /// A destination left the stack (popped, replaced, or removed).
  final void Function(K key)? onPop;

  List<NavEntry<K>> _lastEntries;
  int _lastTopId = -1;

  void _handle() {
    final now = stack.entries;
    final oldIds = {for (final e in _lastEntries) e.id};
    final newIds = {for (final e in now) e.id};

    if (onPush != null) {
      for (final e in now) {
        if (!oldIds.contains(e.id)) onPush!(e.key);
      }
    }
    if (onPop != null) {
      for (final e in _lastEntries) {
        if (!newIds.contains(e.id)) onPop!(e.key);
      }
    }
    final topId = now.last.id;
    if (topId != _lastTopId) {
      _lastTopId = topId;
      onScreen?.call(now.last.key);
    }
    _lastEntries = now;
  }

  /// Stop observing. Safe to call once; the stack itself is not disposed.
  void dispose() => stack.removeListener(_handle);
}
