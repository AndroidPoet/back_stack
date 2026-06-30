import 'package:flutter/widgets.dart';

/// Guards leaving a screen behind an **async** confirmation — the "are you sure
/// you want to discard?" gate (zenrouter's `popGuardWith`).
///
/// Unlike `NavStack.popGuard` (a synchronous veto for programmatic pops), this
/// covers the Android **system back gesture / button** too, because that event
/// is delivered to the widget tree, not the stack. Place it inside a screen that
/// has unsaved work:
///
/// ```dart
/// ConfirmPopScope(
///   // When there's nothing to lose, let back through untouched.
///   canPop: !hasUnsavedChanges,
///   confirm: () => showDialog<bool>(
///     context: context,
///     builder: (_) => AlertDialog(
///       content: const Text('Discard changes?'),
///       actions: [
///         TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Stay')),
///         TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard')),
///       ],
///     ),
///   ).then((v) => v ?? false),
///   child: form,
/// )
/// ```
///
/// On confirm it pops the **enclosing [NavStack]'s** [Navigator] — which flows
/// straight back into your stack via the usual sync path, so the list stays the
/// single source of truth. No result is returned to a `pushForResult` awaiter;
/// for that, pop the stack yourself inside [confirm].
class ConfirmPopScope extends StatelessWidget {
  /// Creates a confirm-before-leave gate around [child].
  const ConfirmPopScope({
    required this.confirm,
    required this.child,
    this.canPop = false,
    super.key,
  });

  /// When true, back is allowed immediately with no prompt (e.g. the form is
  /// pristine). When false, [confirm] decides.
  final bool canPop;

  /// Asks the user. Resolve `true` to actually leave, `false` to stay. Typically
  /// a `showDialog<bool>` — but any async check works (save-then-leave, etc.).
  final Future<bool> Function() confirm;

  /// The screen being guarded.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await confirm();
        if (!leave || !context.mounted) return;
        // Use pop(), not maybePop(): maybePop would re-consult this same
        // PopScope and ask again, looping forever. pop() removes the route
        // directly; the enclosing NavDisplay's onDidRemovePage syncs the stack.
        final navigator = Navigator.of(context);
        if (navigator.canPop()) navigator.pop();
      },
      child: child,
    );
  }
}
