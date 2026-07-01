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
/// change: assign [call] to [NavStack.redirect] and the instance itself to
/// [NavStack.refreshListenable]. When you navigate to a gated destination the
/// stack stays put and [resolving] flips true while [check] runs; the moment it
/// resolves, the redirect re-runs and either leaves the stack alone (allowed) or
/// replaces it (denied). Decisions are cached per proposed stack, so a check
/// runs once, not on every rebuild — that's what keeps it loop-proof.
///
/// ```dart
/// final gate = AsyncRedirect<AppKey>(
///   check: (proposed) async {
///     if (proposed.any((k) => k is Admin) && !await session.hasAdminAccess()) {
///       return [const Login()]; // deny → bounce to login
///     }
///     return null;              // allow as proposed
///   },
/// );
/// stack
///   ..redirect = gate.call
///   ..refreshListenable = gate;
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
  /// stack" for caching (default: the keys' own `==`/`hashCode`, so give gated
  /// destinations value equality via [EquatableNavKey] for stable caching). If
  /// [check] throws, the navigation is allowed unchanged.
  AsyncRedirect({
    required AsyncNavCheck<K> check,
    Object Function(List<K> proposed)? signature,
  }) : _check = check,
       _signatureOf = signature ?? _defaultSignature;

  final AsyncNavCheck<K> _check;
  final Object Function(List<K> proposed) _signatureOf;

  // signature → decision. Present means resolved; a null value means "allowed".
  final Map<Object, List<K>?> _decided = {};
  // signatures with a check currently in flight (so we start each check once).
  final Set<Object> _inFlight = {};

  final ValueNotifier<bool> _resolving = ValueNotifier<bool>(false);

  /// True while at least one [check] is running — drive a loading overlay from it.
  ValueListenable<bool> get resolving => _resolving;

  /// The sync redirect to hand to [NavStack.redirect]. Pure given the decision
  /// cache: returns [proposed] unchanged while a check runs or once allowed, and
  /// the replacement stack once denied. Kicks off the check the first time it
  /// sees an undecided proposed stack.
  List<K> call(List<K> proposed) {
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
    _decided[sig] = decision;
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
    _resolving.dispose();
    super.dispose();
  }

  static Object _defaultSignature(List<NavKey> proposed) =>
      Object.hashAll(proposed);
}
