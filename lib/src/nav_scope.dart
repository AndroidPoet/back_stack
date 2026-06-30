import 'package:back_stack/src/nav_key.dart';
import 'package:back_stack/src/nav_stack.dart';
import 'package:flutter/widgets.dart';

/// Exposes a [NavStack] of destination type [K] to the widgets below it via
/// [BackStack.of].
///
/// [NavDisplay] inserts one of these for you, so any screen it builds can reach
/// the stack from its `BuildContext` — no passing `stack` down by hand. Being an
/// [InheritedNotifier], widgets that read with `listen: true` rebuild when the
/// stack changes.
class NavStackScope<K extends NavKey> extends InheritedNotifier<NavStack<K>> {
  /// Provides [stack] to the subtree under [child].
  const NavStackScope({
    required NavStack<K> stack,
    required super.child,
    super.key,
  }) : super(notifier: stack);

  /// The stack provided to this subtree.
  NavStack<K> get stack => notifier!;
}

/// Reach the back stack from a `BuildContext`, the way Flutter devs expect
/// (`Navigator.of`, `GoRouter.of`).
///
/// Pass your destination type so the result is fully typed (and sound — no
/// hidden downcast):
///
/// ```dart
/// onTap: () => BackStack.of<AppKey>(context).push(const Product(42)),
/// ```
///
/// By default this does **not** subscribe the caller to changes — right for
/// event handlers that just push/pop. Pass `listen: true` to rebuild when the
/// stack changes (e.g. a widget that renders the current destination).
abstract final class BackStack {
  /// The nearest [NavStack] of type [K]. Throws (in debug) if there's no
  /// matching [NavStackScope] — which [NavDisplay] provides automatically.
  static NavStack<K> of<K extends NavKey>(
    BuildContext context, {
    bool listen = false,
  }) {
    final stack = maybeOf<K>(context, listen: listen);
    assert(
      stack != null,
      'BackStack.of<$K>() found no NavStackScope<$K>. It is provided by '
      'NavDisplay<$K>; call this from a screen it builds with the same key '
      'type, or wrap your subtree in a NavStackScope<$K>.',
    );
    return stack!;
  }

  /// The nearest [NavStack] of type [K], or null if there is no matching
  /// [NavStackScope] above.
  static NavStack<K>? maybeOf<K extends NavKey>(
    BuildContext context, {
    bool listen = false,
  }) {
    if (listen) {
      return context
          .dependOnInheritedWidgetOfExactType<NavStackScope<K>>()
          ?.stack;
    }
    final element = context
        .getElementForInheritedWidgetOfExactType<NavStackScope<K>>();
    return (element?.widget as NavStackScope<K>?)?.stack;
  }
}
