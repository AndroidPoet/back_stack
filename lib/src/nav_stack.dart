import 'dart:async';
import 'package:back_stack/src/nav_key.dart';
import 'package:flutter/foundation.dart';

/// One entry on the stack: your [NavKey] plus a stable internal id.
///
/// The id is what keeps a screen's [State] alive across rebuilds and lets the
/// framework tell two identical destinations apart (e.g. two `ProductDetail(5)`
/// pushed on top of each other). You never see it — the public API is your keys.
@immutable
class NavEntry<K extends NavKey> {
  /// Creates an entry pairing a destination [key] with its stable [id].
  const NavEntry(this.key, this.id);

  /// The destination you pushed.
  final K key;

  /// Stable, unique identity for this slot on the stack — assigned when the
  /// entry is created and preserved as long as it survives. Two entries with the
  /// same [key] still have different ids, which is what lets duplicate
  /// destinations stay independent and keep their own `State`.
  final int id;
}

/// Your back stack — and the entire navigation API.
///
/// **The mental model: navigation is a list you own.**
/// - [push] adds to the list.
/// - [pop] removes from the list.
/// - the UI ([NavDisplay]) just renders the list.
///
/// Typed over your destination type [K], so the whole API — [push], [keys],
/// [redirect], the [NavDisplay] builder — speaks in *your* keys with no casts:
///
/// ```dart
/// final stack = NavStack<AppKey>.of(const Home());
/// stack.push(const Product(42)); // Product must be an AppKey
/// ```
///
/// There is no `go` vs `push` split, no route graph, no [Navigator] 2.0
/// `RouterDelegate` ceremony. URL sync, deep links, and guards (added in higher
/// layers) are simply things that read and write this same list. The list is
/// always the single source of truth.
class NavStack<K extends NavKey> extends ChangeNotifier {
  /// Create a stack with one or more initial destinations. The last one is the
  /// screen shown first.
  NavStack(List<K> initial)
    : assert(initial.isNotEmpty, 'A NavStack needs at least one destination'),
      _entries = [for (final k in initial) NavEntry<K>(k, _nextId++)];

  /// Convenience for the common "start on a single screen" case.
  NavStack.of(K root) : this([root]);

  static int _nextId = 0;

  final List<NavEntry<K>> _entries;

  /// Futures awaiting a result from a [pushForResult] destination, keyed by
  /// entry id. Completed (with the result, or null) the moment the entry leaves
  /// the stack — for any reason — so an `await` never hangs and no closure is
  /// retained.
  final Map<int, Completer<Object?>> _pending = {};

  /// Optional veto run before every change. Return `false` to block it.
  ///
  /// A pure function over the proposed stack, not a redirect engine that can
  /// spin. Leave it null for no guarding. For "send them somewhere else"
  /// (rather than just blocking), use [redirect].
  bool Function(List<K> proposed)? guard;

  /// Optional transform run before every change: map the proposed stack to the
  /// one to actually show.
  ///
  /// This is loop-proof auth gating done right — a pure function applied **once**
  /// per change, so it can't ping-pong the way a URL-redirect engine does:
  ///
  /// ```dart
  /// stack.redirect = (proposed) {
  ///   final guarded = proposed.any((k) => k is Account);
  ///   if (guarded && !isLoggedIn) return [const Login()];
  ///   return proposed;
  /// };
  /// ```
  ///
  /// Must return at least one destination. Runs before [guard]. Leave it null
  /// for no redirects.
  List<K> Function(List<K> proposed)? redirect;

  /// Optional veto for [pop]: return `false` to keep the top screen.
  ///
  /// Covers *programmatic* pops (your own back button, `stack.pop()`). For the
  /// Android system back gesture, also put a `PopScope` on the screen — that's
  /// where the framework asks before it removes the route. Use this for a
  /// synchronous "are you sure" gate (e.g. an unsaved-changes flag); for an
  /// async confirm dialog, use `PopScope` + `onPopInvokedWithResult`.
  bool Function(K top)? popGuard;

  Listenable? _refresh;

  /// Re-run [redirect]/[guard] over the current stack whenever [listenable]
  /// fires — the loop-proof equivalent of go_router's `refreshListenable`.
  ///
  /// Point it at your auth `ChangeNotifier`: when sign-in state changes, the
  /// current stack is re-evaluated and bounced if [redirect] now says so. This
  /// is how "navigation reacts to async auth" works without a blocking guard —
  /// send the user to a loading screen, and when auth resolves, the redirect
  /// re-runs and moves them on.
  set refreshListenable(Listenable? listenable) {
    if (identical(listenable, _refresh)) return;
    _refresh?.removeListener(_reevaluate);
    _refresh = listenable;
    _refresh?.addListener(_reevaluate);
  }

  /// The listenable currently driving re-evaluation, if any.
  Listenable? get refreshListenable => _refresh;

  void _reevaluate() => _commit(List.of(_entries));

  // ---- reading the stack ---------------------------------------------------

  /// The destinations, bottom-to-top. Read-only — mutate via the methods below.
  List<K> get keys => [for (final e in _entries) e.key];

  /// The entries (each a [key] paired with its stable [NavEntry.id]),
  /// bottom-to-top. [NavDisplay] uses these to build one page per entry; reach
  /// for them when you need an entry's identity, not just its [keys]. Read-only.
  List<NavEntry<K>> get entries => List.unmodifiable(_entries);

  /// The screen currently on top.
  K get current => _entries.last.key;

  /// Number of destinations on the stack.
  int get length => _entries.length;

  /// Whether [pop] would do anything (i.e. there's a screen to go back to).
  bool get canPop => _entries.length > 1;

  // ---- changing the stack --------------------------------------------------

  /// Add a destination on top.
  void push(K key) {
    _commit([..._entries, NavEntry<K>(key, _nextId++)]);
  }

  /// Add a destination on top and await the result it returns when popped.
  ///
  /// ```dart
  /// final picked = await stack.pushForResult<Color>(const ColorPicker());
  /// // ... on the picker screen: stack.pop(Colors.indigo);
  /// ```
  ///
  /// The future completes with the value passed to [pop], or `null` if the
  /// screen leaves the stack any other way (back gesture, `replaceAll`, the
  /// stack being disposed). It never hangs.
  ///
  /// [pop] takes an untyped `Object?`, so the value is cast to `T` when this
  /// future resolves: `pop(result)` with a result that isn't a `T` throws a
  /// `CastError` inside the `await` here, not at the `pop` call site. Make the
  /// popping screen return the same type this `pushForResult<T>` expects.
  Future<T?> pushForResult<T extends Object>(K key) {
    final entry = NavEntry<K>(key, _nextId++);
    final completer = Completer<Object?>();
    _pending[entry.id] = completer;
    _commit([..._entries, entry]);
    return completer.future.then((value) => value as T?);
  }

  /// Remove the top destination, optionally returning [result] to a matching
  /// [pushForResult] awaiter. Returns false (and does nothing) if this is the
  /// last screen — the stack always keeps at least one entry, or if the change
  /// is blocked by [guard]/collapsed by [redirect] so the top never actually
  /// leaves. The [result] reaches the awaiter only when the pop truly lands.
  bool pop([Object? result]) {
    if (!canPop) return false;
    if (popGuard != null && !popGuard!(current)) return false;
    return _commit(
      _entries.sublist(0, _entries.length - 1),
      poppedId: _entries.last.id,
      poppedResult: result,
    );
  }

  /// Replace the top destination in place (no back step recorded).
  void replaceTop(K key) {
    _commit([
      ..._entries.sublist(0, _entries.length - 1),
      NavEntry<K>(key, _nextId++),
    ]);
  }

  /// Replace the whole stack. Use this for "reset to a fresh flow" — e.g.
  /// after login, set the stack to `[Home()]`.
  ///
  /// Screens that survive the swap keep their [State] (controllers, scroll
  /// position, etc.): entries are reconciled against the current stack by key
  /// identity/equality, so only genuinely new destinations are rebuilt and only
  /// genuinely removed ones are disposed.
  void replaceAll(List<K> next) {
    assert(next.isNotEmpty, 'replaceAll needs at least one destination');
    _commit(_reconcile(next));
  }

  /// Pop until [test] returns true for the new top, or until only the root
  /// remains. Useful for "back to the first matching screen".
  void popUntil(bool Function(K key) test) {
    var next = _entries;
    while (next.length > 1 && !test(next.last.key)) {
      next = next.sublist(0, next.length - 1);
    }
    _commit(next);
  }

  /// If a destination matching [test] is already on the stack, bring it to the
  /// top by removing everything above it, and return true. Otherwise do nothing
  /// and return false.
  ///
  /// The "don't stack another copy — go back to the one that's open" gesture
  /// (Android's `singleTop`/`clearTop`), expressed over your list.
  bool moveToTop(bool Function(K key) test) {
    final i = _entries.lastIndexWhere((e) => test(e.key));
    if (i == -1) return false;
    if (i != _entries.length - 1) _commit(_entries.sublist(0, i + 1));
    return true;
  }

  /// Push [key] — unless an equal destination is already on the stack, in which
  /// case bring that existing one to the top instead of adding a duplicate.
  ///
  /// Equality is [NavKey] `==` (mix in [EquatableNavKey] for value equality),
  /// unless you pass [isSame]. Handy for a deep link or a menu item that
  /// shouldn't pile up copies of the same screen.
  void pushOrMoveToTop(K key, {bool Function(K existing, K incoming)? isSame}) {
    final match = isSame ?? (existing, incoming) => existing == incoming;
    final i = _entries.lastIndexWhere((e) => match(e.key, key));
    if (i == -1) {
      push(key);
    } else if (i != _entries.length - 1) {
      _commit(_entries.sublist(0, i + 1));
    }
  }

  /// Push several destinations at once, in order, as a single change — one
  /// rebuild and one notification instead of N. Handy for materializing a whole
  /// flow (`stack.pushAll([Category(id), Product(pid)])`). A no-op if [keys] is
  /// empty.
  void pushAll(Iterable<K> keys) {
    final added = [for (final k in keys) NavEntry<K>(k, _nextId++)];
    if (added.isEmpty) return;
    _commit([..._entries, ...added]);
  }

  /// Pop everything above the root, landing back on the first entry. Returns
  /// whether anything was popped (false if already at the root). The root keeps
  /// its [State] — this is the "home button" / re-tap-the-tab gesture.
  bool popToRoot() {
    if (_entries.length <= 1) return false;
    return _commit(_entries.sublist(0, 1));
  }

  /// Remove every entry whose key matches [test], as one change. Returns whether
  /// anything was removed. Refuses to empty the stack: if *every* entry matches,
  /// nothing is removed and it returns false (the stack always keeps at least one
  /// destination). Matching entries that survive elsewhere keep their [State].
  bool removeWhere(bool Function(K key) test) {
    final kept = [
      for (final e in _entries)
        if (!test(e.key)) e,
    ];
    if (kept.length == _entries.length) return false; // nothing matched
    if (kept.isEmpty) return false; // would empty the stack — refuse
    return _commit(kept);
  }

  /// Escape hatch: mutate the stack as a plain list. Whatever the list looks
  /// like after [edit] runs is the new stack. The whole point of owning the
  /// back stack — anything you can do to a `List`, you can do to navigation.
  void edit(void Function(List<K> keys) edit) {
    final draft = keys;
    edit(draft);
    replaceAll(draft);
  }

  // ---- internal ------------------------------------------------------------

  /// Called by [NavDisplay] when the framework removes a page itself (system
  /// back gesture, predictive back, or an imperative pop animation finishing).
  /// Keeps the list in sync without the developer wiring anything.
  void syncRemoved(int id) {
    final i = _entries.indexWhere((e) => e.id == id);
    if (i == -1) return; // already gone (we popped it ourselves) — no-op.
    // Defensive: the stack always keeps at least one entry. The framework
    // shouldn't pop the root (it isn't poppable), but never desync into an
    // empty `pages` list, which would assert.
    if (_entries.length == 1) return;
    _completeResult(id, null);
    _entries.removeAt(i);
    notifyListeners();
  }

  /// Reconcile [next] (keys only) against the current entries, reusing the id —
  /// and therefore the live [State] — of any destination that survives. Greedy
  /// match by key identity first, then value equality. Anything unmatched is a
  /// new entry; any current entry left over is dropped (its route disposed).
  List<NavEntry<K>> _reconcile(List<K> next) {
    final pool = List<NavEntry<K>?>.of(_entries);
    return [
      for (final key in next) _matchOrCreate(key, pool),
    ];
  }

  NavEntry<K> _matchOrCreate(K key, List<NavEntry<K>?> pool) {
    for (var i = 0; i < pool.length; i++) {
      final e = pool[i];
      if (e != null && (identical(e.key, key) || e.key == key)) {
        pool[i] = null; // consume — don't match the same slot twice.
        return e;
      }
    }
    return NavEntry<K>(key, _nextId++);
  }

  /// Apply [next] as the new stack, running [redirect] then [guard]. Returns
  /// whether the change actually landed (false if [guard] vetoed it or it was a
  /// no-op). When a [pop] drives this, [poppedId]/[poppedResult] carry the
  /// awaiter result to deliver — but only if that entry genuinely leaves, so a
  /// vetoed pop never resolves its future while the screen is still up.
  bool _commit(List<NavEntry<K>> next, {int? poppedId, Object? poppedResult}) {
    var resolved = next;
    // redirect runs once and transforms the proposed stack — loop-proof.
    final redirectFn = redirect;
    if (redirectFn != null) {
      final adjusted = redirectFn([for (final e in next) e.key]);
      assert(
        adjusted.isNotEmpty,
        'redirect must return at least one destination',
      );
      if (adjusted.isNotEmpty) resolved = _reconcile(adjusted);
    }
    // An empty stack has no screen to show and would leave [NavDisplay] with an
    // empty Pages list (a Navigator assertion). The asserts above catch a bad
    // `redirect`/`replaceAll` in debug; in release, refuse the change instead of
    // crashing — the current stack stays as-is. (A no-op `pop()` on the last
    // entry is handled by its own `canPop` check, so this only trips on misuse.)
    if (resolved.isEmpty) {
      _prunePending();
      return false;
    }
    // A change that never lands — blocked by [guard], or a no-op once [redirect]
    // is applied — can still have stranded a just-pushed [pushForResult] awaiter
    // (its entry was added to [_pending] before we got here). Resolve any
    // awaiter whose entry isn't on the stack so the future can never hang.
    if (guard != null && !guard!([for (final e in resolved) e.key])) {
      _prunePending();
      return false;
    }
    if (_sameAs(resolved)) {
      _prunePending();
      return false;
    }
    _entries
      ..clear()
      ..addAll(resolved);
    // Hand the popped screen its explicit result — but only if it truly left
    // (a redirect could have re-added it). Must run before _prunePending so the
    // pruner doesn't first resolve it with null.
    if (poppedId != null && _entries.every((e) => e.id != poppedId)) {
      _completeResult(poppedId, poppedResult);
    }
    // Anything else that left the stack (a replaceAll, or a key a redirect
    // dropped) resolves its awaiter with null.
    _prunePending();
    notifyListeners();
    return true;
  }

  /// Complete (with null) and drop any [pushForResult] awaiter whose entry is no
  /// longer on the stack, so an `await` never outlives its screen — whether the
  /// screen left by popping, a redirect, a blocked push, or a replace.
  void _prunePending() {
    if (_pending.isEmpty) return;
    final liveIds = {for (final e in _entries) e.id};
    final orphans = [
      for (final id in _pending.keys)
        if (!liveIds.contains(id)) id,
    ];
    for (final id in orphans) {
      _completeResult(id, null);
    }
  }

  void _completeResult(int id, Object? result) {
    final completer = _pending.remove(id);
    if (completer != null && !completer.isCompleted) completer.complete(result);
  }

  @override
  void dispose() {
    _refresh?.removeListener(_reevaluate);
    // Don't leave anyone awaiting a result on a dead stack.
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.complete(null);
    }
    _pending.clear();
    super.dispose();
  }

  bool _sameAs(List<NavEntry<K>> next) {
    if (next.length != _entries.length) return false;
    for (var i = 0; i < next.length; i++) {
      if (next[i].id != _entries[i].id) return false;
    }
    return true;
  }
}
