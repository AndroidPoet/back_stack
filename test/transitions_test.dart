import 'package:back_stack/back_stack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

sealed class K extends NavKey {
  const K();
}

class A extends K {
  const A();
}

class B extends K {
  const B();
}

void main() {
  // Each Material motion should drive a push/pop to completion, animate the
  // outgoing screen (both on screen mid-transition), and leave the incoming one
  // showing — without throwing.
  for (final entry in <String, TransitionPage<dynamic> Function(Widget, LocalKey)>{
    'sharedAxisHorizontal': (c, k) => TransitionPage<void>.sharedAxisHorizontal(child: c, key: k),
    'sharedAxisVertical': (c, k) => TransitionPage<void>.sharedAxisVertical(child: c, key: k),
    'sharedAxisScaled': (c, k) => TransitionPage<void>.sharedAxisScaled(child: c, key: k),
    'fadeThrough': (c, k) => TransitionPage<void>.fadeThrough(child: c, key: k),
  }.entries) {
    testWidgets('${entry.key}: push animates both screens then settles', (
      tester,
    ) async {
      final stack = NavStack<K>.of(const A());
      addTearDown(stack.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: NavDisplay<K>(
            stack: stack,
            builder: (context, key) => switch (key) {
              A() => const Text('screen A'),
              B() => const Text('screen B'),
            },
            pageBuilder: (context, key, pageKey) => entry.value(
              switch (key) {
                A() => const Text('screen A'),
                B() => const Text('screen B'),
              },
              pageKey,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('screen A'), findsOneWidget);

      // Push B and step into the middle of the transition.
      stack.push(const B());
      await tester.pump(); // start the animation
      await tester.pump(const Duration(milliseconds: 150));
      // Both routes are mounted while the shared motion runs.
      expect(find.text('screen A'), findsOneWidget);
      expect(find.text('screen B'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.text('screen B'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // And back.
      stack.pop();
      await tester.pumpAndSettle();
      expect(find.text('screen A'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
