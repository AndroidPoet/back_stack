import 'package:back_stack/back_stack.dart';
import 'package:flutter/material.dart';
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

void main() {
  group('moveToTop / pushOrMoveToTop', () {
    test('moveToTop brings an existing entry up and reports found', () {
      final s = NavStack<K>.of(const A())
        ..push(const B())
        ..push(const C()); // [A, B, C]
      addTearDown(s.dispose);

      expect(s.moveToTop((k) => k is A), isTrue);
      expect(s.keys.map((k) => k.runtimeType), [A]); // cleared above A
      expect(s.moveToTop((k) => k is B), isFalse); // no B left
    });

    test('pushOrMoveToTop de-dupes instead of stacking a copy', () {
      final s = NavStack<K>.of(const A())..push(const B()); // [A, B]
      addTearDown(s.dispose);

      s.pushOrMoveToTop(const A()); // A already present → move up
      expect(s.keys.map((k) => k.runtimeType), [A]);

      s.pushOrMoveToTop(const C()); // absent → push
      expect(s.current, isA<C>());
      expect(s.length, 2);
    });
  });

  group('combineRedirects', () {
    test('runs rules in order; stop short-circuits', () {
      final redirect = combineRedirects<K>([
        (s) => s.any((k) => k is C)
            ? RedirectTo<K>(const [A()], stop: true)
            : const ContinueRedirect(),
        (s) => RedirectTo<K>(const [B()]),
      ]);

      // First rule fires and stops → [A].
      expect(redirect([const C()]).map((k) => k.runtimeType), [A]);
      // First rule passes, second rewrites → [B].
      expect(redirect([const A()]).map((k) => k.runtimeType), [B]);
    });
  });

  testWidgets('BackStackInspector lists the stack and follows it', (
    tester,
  ) async {
    final s = NavStack<K>.of(const A());
    addTearDown(s.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: NavDisplay<K>(
          stack: s,
          builder: (context, key) => Stack(
            children: const [
              SizedBox.expand(),
              Positioned(left: 0, bottom: 0, child: BackStackInspector<K>()),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('▶ A'), findsOneWidget);

    s.push(const B());
    await tester.pumpAndSettle();
    expect(find.textContaining('▶ B'), findsOneWidget);
    expect(find.textContaining('A'), findsWidgets); // A still listed below
  });
}
