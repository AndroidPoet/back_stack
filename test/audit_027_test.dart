import 'package:back_stack/back_stack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

sealed class K extends NavKey {
  const K();
}

class Root extends K {
  const Root();
}

class Item extends K {
  const Item(this.id);
  final int id;
}

void main() {
  group('NavListDetail — a lone detail on a wide screen (fix: dup GlobalKey)', () {
    Widget app(NavStack<K> stack) => MaterialApp(
      home: NavListDetail<K>(
        stack: stack,
        isDetail: (key) => key is Item,
        list: (context, key) => const Text('list'),
        detail: (context, key) => Text('item ${(key as Item).id}'),
        placeholder: (context) => const Text('none'),
      ),
    );

    testWidgets(
      'a single detail-type entry renders without a duplicate-key crash',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        // The only entry IS a detail — listEntry falls back to it. It must show
        // as the list pane (once), not be mounted in both panes.
        final stack = NavStack<K>.of(const Item(1));
        addTearDown(stack.dispose);

        await tester.pumpWidget(app(stack));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        // The lone detail entry is shown as the list pane (via the list builder),
        // and the detail pane is the empty placeholder — not the same entry
        // mounted twice.
        expect(find.text('list'), findsOneWidget);
        expect(find.text('none'), findsOneWidget); // empty detail pane
        expect(find.text('item 1'), findsNothing);
      },
    );
  });

  group('NavListDetail decorators (fix: onRemoved symmetry)', () {
    testWidgets(
      'onRemoved fires once for a rendered entry, not for never-shown ones',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final removed = <K>[];
        final stack = NavStack<K>.of(const Root())..push(const Item(1));
        addTearDown(stack.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: NavListDetail<K>(
              stack: stack,
              isDetail: (key) => key is Item,
              list: (context, key) => const Text('list'),
              detail: (context, key) => Text('item ${(key as Item).id}'),
              decorators: [
                NavEntryDecorator<K>(onRemoved: removed.add),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        stack.pop(); // Item(1) leaves
        await tester.pumpAndSettle();

        expect(removed, [const Item(1)]);
      },
    );
  });

  group('MultiNavStack.handleBack (fix: vetoed pop still consumes back)', () {
    test('a popGuard veto consumes back (returns true) instead of closing', () {
      final tab = NavStack<K>.of(const Root())
        ..push(const Item(1))
        ..popGuard = (_) => false; // veto every pop
      final host = MultiNavStack<K>([tab]);
      addTearDown(host.dispose);

      // Active tab has history, so back must be considered handled even though
      // the guard blocks the actual pop — otherwise the app would close.
      expect(host.handleBack(), isTrue);
      expect(tab.keys, [const Root(), const Item(1)]); // nothing popped
    });
  });
}
