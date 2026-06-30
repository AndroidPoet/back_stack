// Benchmarks for back_stack.
//
// zenrouter publishes no numbers — its only performance claim is "Myers diff →
// minimal widget rebuilds". So we measure exactly that (reconciliation
// minimality + actual screen builds/State creations) plus push/pop latency at
// realistic stack depths.
//
// Run:  flutter test benchmark/nav_benchmark.dart
import 'package:back_stack/back_stack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class Home extends NavKey {
  const Home();
}

class Item extends NavKey {
  const Item(this.i);
  final int i;
}

/// Screen whose State creation we count — the real "did navigation rebuild it?".
class CountedScreen extends StatefulWidget {
  const CountedScreen(this.onInit, {super.key});
  final VoidCallback onInit;
  @override
  State<CountedScreen> createState() => _CountedScreenState();
}

class _CountedScreenState extends State<CountedScreen> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  test('push/pop latency at realistic stack depths', () {
    const cycles = 50000;
    for (final depth in [4, 16, 64]) {
      final stack = NavStack<NavKey>.of(const Home());
      for (var i = 0; i < depth; i++) {
        stack.push(Item(i));
      }
      // Steady-depth churn: push one, pop one, repeated.
      final sw = Stopwatch()..start();
      for (var i = 0; i < cycles; i++) {
        stack
          ..push(const Item(-1))
          ..pop();
      }
      final us = sw.elapsedMicroseconds;
      stack.dispose();
      final perOp = us / (cycles * 2); // a push + a pop per cycle
      debugPrint(
        '── depth $depth ──  '
        '${perOp.toStringAsFixed(3)} µs/op  '
        '(${(2e6 * cycles / us).toStringAsFixed(0)} ops/s)',
      );
    }
  });

  test('reconciliation minimality — the "Myers diff" claim, measured', () {
    for (final depth in [50, 500, 2000]) {
      final stack = NavStack<NavKey>.of(const Home());
      final base = <NavKey>[for (var i = 0; i < depth; i++) Item(i)];
      stack.replaceAll(base);
      final before = [for (final e in stack.entries) e.id];

      final next = List<NavKey>.of(base)..[depth ~/ 2] = const Item(-1);
      final sw = Stopwatch()..start();
      stack.replaceAll(next);
      final us = sw.elapsedMicroseconds;

      final after = [for (final e in stack.entries) e.id];
      var reused = 0;
      for (var i = 0; i < depth; i++) {
        if (i < before.length && before[i] == after[i]) reused++;
      }
      stack.dispose();
      debugPrint(
        '── reconcile depth=$depth, 1 changed ──  '
        'reused $reused/$depth ids in ${(us / 1000).toStringAsFixed(2)} ms',
      );
      expect(reused, depth - 1, reason: 'all-but-one State must survive');
    }
  });

  testWidgets('minimal rebuilds — 1 push onto a 31-deep stack', (tester) async {
    final stateInits = <int, int>{};
    final builderCalls = <int, int>{};
    final stack = NavStack<NavKey>.of(const Home());
    addTearDown(stack.dispose);

    Widget screen(BuildContext context, NavKey key) {
      final id = key is Item ? key.i : -100;
      builderCalls[id] = (builderCalls[id] ?? 0) + 1;
      return CountedScreen(() => stateInits[id] = (stateInits[id] ?? 0) + 1);
    }

    await tester.pumpWidget(
      MaterialApp(
        home: NavDisplay<NavKey>(stack: stack, builder: screen),
      ),
    );
    for (var i = 0; i < 30; i++) {
      stack.push(Item(i));
    }
    await tester.pumpAndSettle();
    builderCalls.clear();
    stateInits.clear(); // count only the next push

    stack.push(const Item(999));
    await tester.pumpAndSettle();

    final builds = builderCalls.values.fold<int>(0, (a, b) => a + b);
    final inits = stateInits.values.fold<int>(0, (a, b) => a + b);
    debugPrint('── 1 push onto a 31-deep stack ──');
    debugPrint(
      '  destination-builder calls : $builds  (memoized: only the new one)',
    );
    debugPrint(
      '  screen State creations    : $inits  (only the new screen mounts)',
    );
    expect(
      builds,
      1,
      reason: 'memoized pages: builder runs only for the new entry',
    );
    expect(inits, 1, reason: 'only the pushed screen is created');
  });
}
