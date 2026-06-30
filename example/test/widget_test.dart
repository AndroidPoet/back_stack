import 'package:flutter_test/flutter_test.dart';

import 'package:example/main.dart';

void main() {
  testWidgets('login resets the stack to the catalog', (tester) async {
    await tester.pumpWidget(const ShopApp());
    expect(find.text('Sign in'), findsOneWidget);

    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();

    expect(find.text('Catalog'), findsOneWidget);
    expect(find.textContaining('back stack: Catalog'), findsOneWidget);
  });
}
