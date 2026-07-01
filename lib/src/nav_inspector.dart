import 'package:back_stack/src/nav_key.dart';
import 'package:back_stack/src/nav_scope.dart';
import 'package:flutter/material.dart';

/// A tiny in-app inspector for the current [NavStack] of type [K] — back_stack's
/// take on a route debugger, with no DevTools plumbing.
///
/// Because the back stack is just observable data, showing it live is a plain
/// widget: it reads the nearest stack with `listen: true` and lists the
/// destinations bottom-to-top, the current one marked. Drop it in an overlay
/// during development to watch entries push and pop.
///
/// ```dart
/// Stack(
///   children: [
///     MyApp(),
///     const Positioned(
///       left: 8, bottom: 8,
///       child: SafeArea(child: BackStackInspector<AppKey>()),
///     ),
///   ],
/// )
/// ```
///
/// It must sit under the [NavDisplay] whose stack you want (that's what provides
/// the scope). Pass [onTapEntry] to make a row actionable — e.g. pop back to it.
class BackStackInspector<K extends NavKey> extends StatelessWidget {
  /// Creates an inspector for the nearest [NavStack] of type [K].
  const BackStackInspector({
    this.label = 'back stack',
    this.onTapEntry,
    super.key,
  });

  /// Small caption shown above the list.
  final String label;

  /// Called with the index of a tapped entry (bottom = 0). Null = display-only.
  final void Function(int index)? onTapEntry;

  @override
  Widget build(BuildContext context) {
    final stack = BackStack.of<K>(context, listen: true);
    final keys = stack.keys;
    return Material(
      color: const Color(0xF20E1330),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$label · ${keys.length}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 4),
            for (var i = 0; i < keys.length; i++)
              _Row(
                text: '${i == keys.length - 1 ? '▶ ' : '  '}${keys[i].runtimeType}',
                isTop: i == keys.length - 1,
                onTap: onTapEntry == null ? null : () => onTapEntry!(i),
              ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.text, required this.isTop, this.onTap});

  final String text;
  final bool isTop;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final line = Text(
      text,
      style: TextStyle(
        color: isTop ? const Color(0xFF9DE7C0) : Colors.white54,
        fontSize: 11,
        fontFamily: 'monospace',
      ),
    );
    if (onTap == null) return line;
    return InkWell(onTap: onTap, child: line);
  }
}
