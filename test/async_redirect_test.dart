import 'dart:async';

import 'package:back_stack/back_stack.dart';
import 'package:flutter_test/flutter_test.dart';

sealed class K extends NavKey with EquatableNavKey {
  const K();
}

class Home extends K {
  const Home();
  @override
  List<Object?> get props => const [];
}

class Admin extends K {
  const Admin();
  @override
  List<Object?> get props => const [];
}

class Login extends K {
  const Login();
  @override
  List<Object?> get props => const [];
}

Future<void> _flush() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  test('denies a gated destination once the async check resolves', () async {
    final check = Completer<List<K>?>();
    final gate = AsyncRedirect<K>(
      check: (proposed) => proposed.any((k) => k is Admin)
          ? check.future
          : Future<List<K>?>.value(),
    );
    addTearDown(gate.dispose);
    final stack = NavStack<K>.of(const Home())
      ..redirect = gate.call
      ..refreshListenable = gate;
    addTearDown(stack.dispose);

    // Navigating to a gated destination holds it on the stack while resolving.
    stack.push(const Admin());
    expect(stack.keys, [const Home(), const Admin()]);
    expect(gate.resolving.value, isTrue);

    // The check denies → the stack is corrected, and we're no longer busy.
    check.complete([const Login()]);
    await _flush();
    expect(stack.keys, [const Login()]);
    expect(gate.resolving.value, isFalse);
  });

  test(
    'allows a gated destination and clears busy when the check passes',
    () async {
      final gate = AsyncRedirect<K>(
        check: (proposed) async {
          return null; // always allow
        },
      );
      addTearDown(gate.dispose);
      final stack = NavStack<K>.of(const Home())
        ..redirect = gate.call
        ..refreshListenable = gate;
      addTearDown(stack.dispose);

      stack.push(const Admin());
      await _flush();
      expect(stack.keys, [const Home(), const Admin()]); // untouched
      expect(gate.resolving.value, isFalse);
    },
  );

  test(
    'caches the decision — a second visit does not re-run the check',
    () async {
      var checks = 0;
      final gate = AsyncRedirect<K>(
        check: (proposed) async {
          if (proposed.any((k) => k is Admin)) checks++;
          return null;
        },
      );
      addTearDown(gate.dispose);
      final stack = NavStack<K>.of(const Home())
        ..redirect = gate.call
        ..refreshListenable = gate;
      addTearDown(stack.dispose);

      stack.push(const Admin());
      await _flush();
      stack
        ..pop()
        ..push(const Admin());
      await _flush();
      expect(checks, 1, reason: 'same proposed stack → one check, then cached');

      // invalidate() forces a fresh check (e.g. after login state changed).
      gate.invalidate();
      stack
        ..pop()
        ..push(const Admin());
      await _flush();
      expect(checks, 2);
    },
  );
}
