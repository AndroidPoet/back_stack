import 'package:back_stack/back_stack.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';

sealed class AppKey extends NavKey {
  const AppKey();
}

class Home extends AppKey {
  const Home();
}

class Product extends AppKey {
  const Product(this.id);
  final int id;
}

// Keys for the nested parent/child test (same key type on both stacks).
class ParentRoot extends AppKey {
  const ParentRoot();
}

class ParentDetail extends AppKey {
  const ParentDetail();
}

class ChildRoot extends AppKey {
  const ChildRoot();
}

Future<void> _pushRoute(WidgetTester tester, String location) {
  return tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    const JSONMethodCodec().encodeMethodCall(
      MethodCall('pushRouteInformation', <String, dynamic>{
        'location': location,
        'state': null,
      }),
    ),
    (_) {},
  );
}

void main() {
  testWidgets(
    'BackStackApp: onLink maps a deep link straight onto the stack',
    (tester) async {
      final stack = NavStack<AppKey>.of(const Home());
      addTearDown(stack.dispose);

      await tester.pumpWidget(
        BackStackApp<AppKey>(
          stack: stack,
          restorationScopeId: null,
          builder: (context, key) => switch (key) {
            Home() => const Text('home'),
            Product(:final id) => Text('product $id'),
            _ => const Text('other'),
          },
          onLink: (uri) {
            final s = uri.pathSegments;
            if (s.length == 2 && s[0] == 'products') {
              return [const Home(), Product(int.parse(s[1]))];
            }
            return [const Home()];
          },
        ),
      );
      await tester.pumpAndSettle();

      // Launch URL '/' → home.
      expect(find.text('home'), findsOneWidget);

      // A deep link arrives → onLink maps it → the stack (and screen) follow.
      await _pushRoute(tester, '/products/7');
      await tester.pumpAndSettle();
      expect(find.text('product 7'), findsOneWidget);
      expect(stack.keys, hasLength(2));
      expect(stack.keys.first, isA<Home>());
      expect(stack.keys.last, isA<Product>().having((p) => p.id, 'id', 7));
    },
    experimentalLeakTesting: LeakTesting.settings.withIgnoredAll(),
  );

  testWidgets(
    'BackStack.parentOf reaches the parent stack from a nested child',
    (tester) async {
      final parent = NavStack<AppKey>.of(const ParentRoot());
      final child = NavStack<AppKey>.of(const ChildRoot());
      addTearDown(parent.dispose);
      addTearDown(child.dispose);

      NavStack<AppKey>? seenNearest;
      NavStack<AppKey>? seenParent;

      await tester.pumpWidget(
        MaterialApp(
          home: NavDisplay<AppKey>(
            stack: parent,
            builder: (context, key) => switch (key) {
              ParentRoot() => NavDisplay<AppKey>(
                stack: child,
                nested: true,
                builder: (context, _) => Builder(
                  builder: (context) {
                    seenNearest = BackStack.of<AppKey>(context);
                    seenParent = BackStack.parentOf<AppKey>(context);
                    return const Text('child');
                  },
                ),
              ),
              ParentDetail() => const Text('parent detail'),
              _ => const Text('other'),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('child'), findsOneWidget);
      // of() = the innermost (child) stack; parentOf() = the outer one.
      expect(seenNearest, same(child));
      expect(seenParent, same(parent));

      // Driving the parent from the child pushes on the outer stack only.
      seenParent!.push(const ParentDetail());
      await tester.pumpAndSettle();
      expect(find.text('parent detail'), findsOneWidget);
      expect(child.keys, [const ChildRoot()]); // child untouched
    },
  );
}
