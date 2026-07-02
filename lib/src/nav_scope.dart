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
    if (stack == null) {
      throw FlutterError.fromParts([
        ErrorSummary('BackStack.of<$K>() found no NavStackScope<$K>.'),
        if (K == NavKey)
          ErrorHint(
            'The type argument resolved to the NavKey base type — this '
            'usually means it was omitted. Call '
            "BackStack.of<YourKeyType>(context) with your app's destination "
            'type.',
          )
        else
          ErrorHint(
            'A NavStackScope<$K> is provided by NavDisplay<$K>; call this '
            'from a screen it builds with the same key type, or wrap your '
            'subtree in a NavStackScope<$K>.',
          ),
      ]);
    }
    return stack;
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

  /// The [NavStack] of type [K] **one level up** from the nearest one — a nested
  /// child screen's *parent* stack.
  ///
  /// Use this to drive the parent from inside a nested [NavDisplay] when parent
  /// and child share the same key type [K] — e.g. a detail screen deep in a
  /// child stack that wants to pop the *outer* flow:
  ///
  /// ```dart
  /// // From a screen inside a nested NavDisplay<AppKey>:
  /// BackStack.parentOf<AppKey>(context).pop(); // pops the parent, not the child
  /// ```
  ///
  /// When the nested stacks use *different* key subtypes (the usual, more
  /// type-safe setup), plain [of] with the parent's type already reaches it
  /// unambiguously — prefer that. This is the escape hatch for the same-type
  /// case. Throws (in debug) if there is no second [NavStackScope] of type [K]
  /// above; use [maybeParentOf] when a parent may not exist.
  static NavStack<K> parentOf<K extends NavKey>(
    BuildContext context, {
    bool listen = false,
  }) {
    final parent = maybeParentOf<K>(context, listen: listen);
    if (parent == null) {
      throw FlutterError.fromParts([
        ErrorSummary(
          'BackStack.parentOf<$K>() found no *parent* NavStackScope<$K> — '
          'there is no second stack of this type above.',
        ),
        ErrorHint(
          'Use BackStack.of<$K> for the nearest one, or give the parent stack '
          'a different key type and reach it with BackStack.of<ParentKey>.',
        ),
      ]);
    }
    return parent;
  }

  /// Like [parentOf] but returns null when there is no parent stack of type [K].
  static NavStack<K>? maybeParentOf<K extends NavKey>(
    BuildContext context, {
    bool listen = false,
  }) {
    // Collect the NavStackScope<K> ancestors, nearest first. [0] is the child
    // stack the caller sits in; [1] is its parent. Stop walking as soon as
    // both are found — no need to visit the rest of a deep tree.
    final scopes = <InheritedElement>[];
    context.visitAncestorElements((element) {
      if (element is InheritedElement && element.widget is NavStackScope<K>) {
        scopes.add(element);
        if (scopes.length == 2) return false;
      }
      return true;
    });
    if (scopes.length < 2) return null;
    final parentElement = scopes[1];
    if (listen) context.dependOnInheritedElement(parentElement);
    return (parentElement.widget as NavStackScope<K>).stack;
  }
}
