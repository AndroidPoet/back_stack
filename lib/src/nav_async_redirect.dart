import 'dart:async';

import 'package:back_stack/src/nav_key.dart';
import 'package:back_stack/src/nav_stack.dart';
import 'package:flutter/foundation.dart';

/// An async gate's decision function: given the [proposed] stack, return `null`
/// to allow it unchanged, or a replacement stack (e.g. `[Login()]`) to redirect.
/// May `await` — a permission call, a session refresh, a "does this document
/// exist" lookup for a deep link.
typedef AsyncNavCheck<K extends NavKey> =
    Future<List<K>?> Function(List<K> proposed);

/// Loop-proof **async** navigation gating — the piece `redirect` (which must be
/// synchronous to stay loop-proof) can't do on its own.
///
/// It's built entirely on the sync primitives, so back_stack's core doesn't
/// change: call [attach] and the gate wires itself to the stack. When you
/// navigate to a gated destination the stack stays put and [resolving] flips
/// true while [check] runs; the moment it resolves, the redirect re-runs and
/// either leaves the stack alone (allowed) or replaces it (denied). Decisions
/// are cached per proposed stack, so a check runs once, not on every rebuild —
/// that's what keeps it loop-proof.
///
/// ```dart
/// final gate = AsyncRedirect<AppKey>(
///   check: (proposed) async {
///     if (proposed.any((k) => k is Admin) && !await session.hasAdminAccess()) {
///       return [const Login()]; // deny → bounce to login
///     }
///     return null;              // allow as proposed
///   },
/// )..attach(stack);
///
/// // Show a loading overlay while any gate check is in flight:
/// Stack(children: [
///   NavDisplay(stack: stack, builder: screenFor),
///   ValueListenableBuilder(
///     valueListenable: gate.resolving,
///     builder: (_, busy, __) => busy ? const LoadingScrim() : const SizedBox(),
///   ),
/// ]);
/// ```
///
/// After something that changes the answer (login, logout, a plan upgrade) call
/// [invalidate] to drop the cache so the next navigation re-checks.
class AsyncRedirect<K extends NavKey> extends ChangeNotifier {
  /// Gates navigation with [check]. [signature] identifies "the same proposed
  /// stack" for caching (default: element-wise key equality, so give gated
  /// destinations value equality via [EquatableNavKey] for stable caching). If
  /// [check] throws, the navigation is allowed unchanged. At most [cacheSize]
  /// decisions are kept; older ones are evicted and simply re-checked next time.
  AsyncRedirect({
    required AsyncNavCheck<K> check,
    Object Function(List<K> proposed)? signature,
    this.cacheSize = 128,
  }) : assert(cacheSize > 0, 'cacheSize must be positive'),
       _check = check,
       _signatureOf =
           signature ?? ((proposed) => _StackSignature(List.of(proposed)));

  final AsyncNavCheck<K> _check;
  final Object Function(List<K> proposed) _signatureOf;

  /// Upper bound on cached decisions. Browsing many distinct gated stacks (e.g.
  /// one per product id) can't grow memory without limit: the oldest decision is
  /// evicted and re-checked if that stack is proposed again.
  final int cacheSize;

  // signature → decision. Present means resolved; a null value means "allowed".
  final Map<Object, List<K>?> _decided = {};
  // signatures with a check currently in flight (so we start each check once).
  final Set<Object> _inFlight = {};

  final ValueNotifier<bool> _resolving = ValueNotifier<bool>(false);

  bool _disposed = false;
  NavStack<K>? _attached;

  /// True while at least one [check] is running — drive a loading overlay from it.
  ValueListenable<bool> get resolving => _resolving;

  /// Wire this gate to [stack] in one call — sets [NavStack.redirect] to [call]
  /// **and** [NavStack.refreshListenable] to this gate, the two halves that must
  /// always go together (with only the redirect set, a resolved check would
  /// never re-run it, and gating would silently hang). Detaches from any
  /// previously attached stack first. [dispose] detaches automatically.
  void attach(NavStack<K> stack) {
    detach();
    _attached = stack;
    stack
      ..redirect = call
      ..refreshListenable = this;
  }

  /// Undo [attach]: clear the stack's `redirect`/`refreshListenable` if they
  /// still point at this gate. Safe to call when never attached.
  void detach() {
    final stack = _attached;
    _attached = null;
    if (stack == null) return;
    if (stack.redirect == call) stack.redirect = null;
    if (identical(stack.refreshListenable, this)) {
      stack.refreshListenable = null;
    }
  }

  /// The sync redirect to hand to [NavStack.redirect] (done for you by
  /// [attach]). Pure given the decision cache: returns [proposed] unchanged
  /// while a check runs or once allowed, and the replacement stack once denied.
  /// Kicks off the check the first time it sees an undecided proposed stack.
  List<K> call(List<K> proposed) {
    if (_disposed) return proposed;
    final sig = _signatureOf(proposed);
    if (_decided.containsKey(sig)) {
      return _decided[sig] ?? proposed; // null decision = allow as-is
    }
    if (_inFlight.add(sig)) {
      _resolving.value = true;
      // Keep a copy of the awaited keys so the decision applies even if the
      // check completes synchronously. Fire-and-forget: it notifies when done.
      unawaited(_run(sig, List<K>.of(proposed)));
    }
    // Hold on the proposed stack; "busy" is surfaced via [resolving], not by
    // swapping the stack to a splash (which would break re-evaluation).
    return proposed;
  }

  Future<void> _run(Object sig, List<K> proposed) async {
    List<K>? decision;
    try {
      decision = await _check(proposed);
    } on Object {
      decision = null; // errors fail open — allow, don't strand the user
    }
    // The gate may have been disposed while the check was in flight — its
    // notifier is gone and nobody is listening; just drop the result.
    if (_disposed) return;
    _decided[sig] = decision;
    if (_decided.length > cacheSize) _decided.remove(_decided.keys.first);
    _inFlight.remove(sig);
    if (_inFlight.isEmpty) _resolving.value = false;
    // Re-run the redirect against the current stack now that we've decided.
    notifyListeners();
  }

  /// Forget cached decisions so the next navigation re-checks — call after login,
  /// logout, or anything else that changes what a gate would decide.
  void invalidate() {
    _decided.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    detach();
    _disposed = true;
    _inFlight.clear();
    _resolving.dispose();
    super.dispose();
  }
}

/// Default cache identity for a proposed stack: element-wise key equality (not
/// a bare hash, which could collide two different stacks into one decision).
@immutable
class _StackSignature {
  const _StackSignature(this.keys);

  final List<NavKey> keys;

  @override
  bool operator ==(Object other) =>
      other is _StackSignature && listEquals(other.keys, keys);

  @override
  int get hashCode => Object.hashAll(keys);
}
