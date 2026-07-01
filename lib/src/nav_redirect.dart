import 'package:back_stack/src/nav_key.dart';
import 'package:back_stack/src/nav_stack.dart';

/// One step's verdict in a [combineRedirects] pipeline — either let the proposed
/// stack through unchanged ([ContinueRedirect]) or rewrite it ([RedirectTo]).
///
/// A rule is a pure `List<K> proposed → RedirectStep<K>` function. Composing
/// several keeps [NavStack.redirect]'s loop-proof guarantee: each rule runs once,
/// in order, over the (possibly already-rewritten) stack.
sealed class RedirectStep<K extends NavKey> {
  const RedirectStep();
}

/// This rule has no opinion — carry the current stack on to the next rule.
class ContinueRedirect<K extends NavKey> extends RedirectStep<K> {
  /// A no-op step.
  const ContinueRedirect();
}

/// Rewrite the stack to [stack]. Later rules keep evaluating against the new
/// value unless [stop] is set, which short-circuits the pipeline.
class RedirectTo<K extends NavKey> extends RedirectStep<K> {
  /// Redirect to [stack]; pass `stop: true` to end the pipeline immediately.
  const RedirectTo(this.stack, {this.stop = false});

  /// The stack to show instead of the proposed one.
  final List<K> stack;

  /// When true, no further rules run — [stack] is the final result.
  final bool stop;
}

/// A single redirect rule: a pure function from the proposed stack to a
/// [RedirectStep].
typedef NavRedirectRule<K extends NavKey> =
    RedirectStep<K> Function(List<K> proposed);

/// Compose [rules] into one function for [NavStack.redirect].
///
/// Rules run in order. A [ContinueRedirect] passes the stack through untouched;
/// a [RedirectTo] rewrites it (and, with `stop: true`, ends the pipeline). This
/// is the chainable version of a single `redirect` — split independent gates
/// (auth, onboarding, feature flags) into their own rules instead of one nested
/// function, while keeping the same once-per-change, loop-proof semantics.
///
/// ```dart
/// stack.redirect = combineRedirects<AppKey>([
///   // must be signed in for anything under Account
///   (s) => s.any((k) => k is Account) && !isLoggedIn
///       ? const RedirectTo([Login()], stop: true)
///       : const ContinueRedirect(),
///   // force onboarding first
///   (s) => !onboarded && s.last is! Onboarding
///       ? const RedirectTo([Onboarding()])
///       : const ContinueRedirect(),
/// ]);
/// ```
List<K> Function(List<K> proposed) combineRedirects<K extends NavKey>(
  List<NavRedirectRule<K>> rules,
) {
  return (proposed) {
    var current = proposed;
    for (final rule in rules) {
      final step = rule(current);
      if (step is RedirectTo<K>) {
        current = step.stack;
        if (step.stop) return current;
      }
    }
    return current;
  };
}
