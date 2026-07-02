import 'dart:async';

import 'package:back_stack/back_stack.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

sealed class K extends NavKey with EquatableNavKey {
  const K();
}

class A extends K {
  const A();
  @override
  List<Object?> get props => const [];
}

class B extends K {
  const B();
  @override
  List<Object?> get props => const [];
}

class C extends K {
  const C();
  @override
  List<Object?> get props => const [];
}

class Login extends K {
  const Login();
  @override
  List<Object?> get props => const [];
}

class Item extends K {
  const Item(this.id);
  final int id;
  @override
  List<Object?> get props => [id];
}

void main() {
  group('tryPop + popGuardAsync', () {
    test('await-false keeps the screen; await-true pops', () async {
      final s = NavStack<K>.of(const A())..push(const B());
      addTearDown(s.dispose);
      var allow = false;
      s.popGuardAsync = (top) async => allow;

      expect(await s.tryPop(), isFalse);
      expect(s.current, isA<B>());

      allow = true;
      expect(await s.tryPop(), isTrue);
      expect(s.current, isA<A>());
    });

    test(
      'race: stack changed while the guard was deciding → nothing pops',
      () async {
        final s = NavStack<K>.of(const A())..push(const B());
        addTearDown(s.dispose);
        final gate = Completer<bool>();
        s.popGuardAsync = (top) => gate.future;

        final popping = s.tryPop();
        s.push(const C()); // the world moved on mid-await
        gate.complete(true);

        expect(await popping, isFalse, reason: 'guard answered about B, not C');
        expect(s.keys.map((k) => k.runtimeType), [A, B, C]);
      },
    );

    test('sync popGuard still runs after the async one', () async {
      final s = NavStack<K>.of(const A())..push(const B());
      addTearDown(s.dispose);
      s.popGuardAsync = (top) async => true;
      s.popGuard = (top) => false;
      expect(await s.tryPop(), isFalse);
      expect(s.current, isA<B>());
    });

    test('tryPop delivers a result like pop', () async {
      final s = NavStack<K>.of(const A());
      addTearDown(s.dispose);
      final picked = s.pushForResult<int>(const B());
      expect(await s.tryPop(7), isTrue);
      expect(await picked, 7);
    });
  });

  group('replaceTop result forwarding', () {
    test(
      'the replaced pushForResult screen still delivers its value',
      () async {
        final s = NavStack<K>.of(const A());
        addTearDown(s.dispose);
        final picked = s.pushForResult<int>(const B());
        s.replaceTop(const C(), result: 5);
        expect(await picked, 5);
        expect(s.keys.map((k) => k.runtimeType), [A, C]);
      },
    );

    test('without a result the awaiter resolves null (never hangs)', () async {
      final s = NavStack<K>.of(const A());
      addTearDown(s.dispose);
      final picked = s.pushForResult<int>(const B());
      s.replaceTop(const C());
      expect(await picked, isNull);
    });
  });

  group('typed pop results', () {
    test('a mistyped pop result fails at the pop call site in debug', () async {
      final s = NavStack<K>.of(const A());
      addTearDown(s.dispose);
      final picked = s.pushForResult<int>(const B());
      expect(() => s.pop('not an int'), throwsA(isA<FlutterError>()));
      // The pop was refused before committing — the screen is still up.
      expect(s.current, isA<B>());
      s.pop(3);
      expect(await picked, 3);
    });
  });

  group('pushOrMoveToTop return value', () {
    test('reports pushed/moved as true, already-on-top as false', () {
      final s = NavStack<K>.of(const A());
      addTearDown(s.dispose);
      expect(s.pushOrMoveToTop(const B()), isTrue); // pushed
      expect(s.pushOrMoveToTop(const B()), isFalse); // double-tap-proof no-op
      expect(s.pushOrMoveToTop(const A()), isTrue); // moved up
      expect(s.keys.map((k) => k.runtimeType), [A]);
    });
  });

  group('popToRoot guard semantics', () {
    test('popGuard on the current top vetoes a bulk pop-to-root', () {
      final s = NavStack<K>.of(const A())
        ..push(const B())
        ..push(const C());
      addTearDown(s.dispose);
      s.popGuard = (top) => top is! C;
      expect(s.popToRoot(), isFalse, reason: 'C is protected');
      expect(s.length, 3);
      s.popGuard = null;
      expect(s.popToRoot(), isTrue);
      expect(s.keys.map((k) => k.runtimeType), [A]);
    });

    test('tab re-select uses the same single-commit popToRoot', () {
      final tabs = MultiNavStack<K>([
        NavStack<K>.of(const A())
          ..push(const B())
          ..push(const C()),
        NavStack<K>.of(const A()),
      ]);
      addTearDown(tabs.dispose);
      var notifications = 0;
      tabs.addListener(() => notifications++);

      tabs.select(0); // re-select the active tab
      expect(tabs.active.keys.map((k) => k.runtimeType), [A]);
      expect(notifications, 1, reason: 'one commit, not one per popped entry');
    });
  });

  group('AsyncRedirect hardening', () {
    test('attach wires redirect + refreshListenable in one call', () async {
      final s = NavStack<K>.of(const A());
      addTearDown(s.dispose);
      final gate = AsyncRedirect<K>(
        check: (proposed) async =>
            proposed.any((k) => k is C) ? const [Login()] : null,
      )..attach(s);
      addTearDown(gate.dispose);

      s.push(const C());
      expect(gate.resolving.value, isTrue);
      await pumpEventQueue();
      expect(s.keys.map((k) => k.runtimeType), [Login]);
      expect(gate.resolving.value, isFalse);

      // detach restores the stack's own hooks.
      gate.detach();
      expect(s.redirect, isNull);
      expect(s.refreshListenable, isNull);
    });

    test(
      'dispose while a check is in flight neither crashes nor applies',
      () async {
        final s = NavStack<K>.of(const A());
        addTearDown(s.dispose);
        final started = Completer<void>();
        final finish = Completer<List<K>?>();
        final gate = AsyncRedirect<K>(
          check: (proposed) {
            started.complete();
            return finish.future;
          },
        )..attach(s);

        s.push(const C());
        await started.future;
        gate.dispose(); // in flight!
        finish.complete(const [Login()]);
        await pumpEventQueue();
        // The late decision was dropped; no disposed-notifier crash.
        expect(s.keys.map((k) => k.runtimeType), [A, C]);
      },
    );

    test('the decision cache is bounded and keyed by value equality', () async {
      var checks = 0;
      final s = NavStack<K>.of(const A());
      addTearDown(s.dispose);
      final gate = AsyncRedirect<K>(
        cacheSize: 2,
        check: (proposed) async {
          checks++;
          return null;
        },
      )..attach(s);
      addTearDown(gate.dispose);

      s.replaceAll(const [A(), Item(1)]);
      await pumpEventQueue();
      expect(checks, 1);

      // An equal proposed stack re-uses the cached decision (value equality —
      // these are fresh but equal key instances, not the same objects).
      s.replaceAll([A(), Item(1)]); // deliberately non-const
      await pumpEventQueue();
      expect(checks, 1);

      // Two more distinct stacks evict the oldest (cacheSize: 2)…
      s.replaceAll(const [A(), Item(2)]);
      await pumpEventQueue();
      s.replaceAll(const [A(), Item(3)]);
      await pumpEventQueue();
      expect(checks, 3);

      // …so the first one re-checks instead of growing forever.
      s.replaceAll(const [A(), Item(1)]);
      await pumpEventQueue();
      expect(checks, 4);
    });

    test(
      'invalidate drops decisions so gates re-run after login/logout',
      () async {
        var loggedIn = false;
        final s = NavStack<K>.of(const A());
        addTearDown(s.dispose);
        final gate = AsyncRedirect<K>(
          check: (proposed) async =>
              proposed.any((k) => k is C) && !loggedIn ? const [Login()] : null,
        )..attach(s);
        addTearDown(gate.dispose);

        s.push(const C());
        await pumpEventQueue();
        expect(s.current, isA<Login>());

        loggedIn = true;
        gate.invalidate();
        s.replaceAll(const [A(), C()]);
        await pumpEventQueue();
        expect(s.keys.map((k) => k.runtimeType), [A, C]);
      },
    );
  });
}
