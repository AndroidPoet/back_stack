import 'package:example/modular_demo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('modular demo: entries build screens, decorator wraps + tears down', (tester) async {
    teardownLog.value = const [];
    await tester.pumpWidget(const ModularDemo());

    // NavEntries built the Dashboard, and the decorator wrapped it with the
    // instrumentation overlay (no screen references that overlay itself).
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.textContaining('decorator active on: Dashboard'), findsOneWidget);

    // Push a destination registered by a different "feature module".
    await tester.tap(find.text('Read article #1'));
    await tester.pumpAndSettle();
    expect(find.text('Article #1'), findsWidgets); // app-bar title + headline
    expect(find.textContaining('decorator active on: Article #1'), findsOneWidget);

    // Pop it — the decorator's onRemoved fires for exactly this destination.
    await tester.tap(find.text('Pop (fires onRemoved)'));
    await tester.pumpAndSettle();
    expect(find.text('Dashboard'), findsOneWidget);
    expect(teardownLog.value.first, contains('Article #1'));
  });
}
