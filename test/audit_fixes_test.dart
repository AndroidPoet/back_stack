import 'package:back_stack/back_stack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';

// ── Destinations used across these tests ─────────────────────────────────────
sealed class AppKey extends NavKey {
  const AppKey();
}

class Feed extends AppKey {
  const Feed();
}

class Profile extends AppKey {
  const Profile();
}

class Product extends AppKey {
  const Product(this.id);
  final int id;
}

class Picker extends AppKey {
  const Picker();
}

Widget _screenFor(BuildContext context, AppKey key) => switch (key) {
  Feed() => const Text('feed'),
  Profile() => const Text('profile'),
  Product(:final id) => Text('product $id'),
  Picker() => const Text('picker'),
};

/// Per-key codec for restoration tests.
class _AppKeyCodec extends NavKeyCodec<AppKey> {
  const _AppKeyCodec();
  @override
  String encode(AppKey key) => switch (key) {
    Feed() => 'feed',
    Profile() => 'profile',
    Product(:final id) => 'product:$id',
    Picker() => 'picker',
  };
  @override
  AppKey decode(String data) {
    if (data.startsWith('product:')) {
      return Product(int.parse(data.substring(8)));
    }
    return switch (data) {
      'profile' => const Profile(),
      'picker' => const Picker(),
      _ => const Feed(),
    };
  }
}

/// Counts route pushes — proves `observers` are forwarded.
class _CountingObserver extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
  }
}

/// A screen with mutable State — tap to bump [n]. Used to prove a screen's
/// State survives a layout change (State is kept ⇒ [n] is retained).
class _Bump extends StatefulWidget {
  const _Bump(this.label);
  final String label;
  @override
  State<_Bump> createState() => _BumpState();
}

class _BumpState extends State<_Bump> {
  int n = 0;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => setState(() => n++),
    child: Text('${widget.label}:$n', textDirection: TextDirection.ltr),
  );
}

void main() {
  group('pushForResult never hangs (fix #1)', () {
    test('completes null when guard vetoes the push', () async {
      final stack = NavStack<AppKey>.of(const Feed());
      addTearDown(stack.dispose);
      stack.guard = (proposed) => proposed.every((k) => k is! Picker);

      final result = await stack.pushForResult<Object>(const Picker());

      expect(result, isNull);
      expect(stack.keys, [isA<Feed>()], reason: 'push was blocked');
    });

    test(
      'completes null when redirect collapses the push to a no-op',
      () async {
        final stack = NavStack<AppKey>.of(const Feed());
        addTearDown(stack.dispose);
        stack.redirect = (proposed) => proposed.whereType<Feed>().toList();

        final result = await stack.pushForResult<Object>(const Picker());

        expect(result, isNull);
        expect(stack.keys, [isA<Feed>()]);
      },
    );

    test(
      'a normal pushForResult still resolves with the popped value',
      () async {
        final stack = NavStack<AppKey>.of(const Feed());
        addTearDown(stack.dispose);

        final future = stack.pushForResult<int>(const Picker());
        expect(stack.keys.last, isA<Picker>());
        stack.pop(42);

        expect(await future, 42);
      },
    );
  });

  group('MultiNavStack composes with the Router (fix #3a)', () {
    final codec = MultiNavStackCodec<AppKey>.of(
      encode: (tab, stack) => switch (stack.last) {
        Profile() => Uri(path: '/profile'),
        Product(:final id) => Uri(path: '/feed/product/$id'),
        _ => Uri(path: '/feed'),
      },
      decode: (uri) {
        final s = uri.pathSegments;
        if (s.isNotEmpty && s.first == 'profile') {
          return const MultiNavLocation(1, [Profile()]);
        }
        if (s.length == 3 && s[1] == 'product') {
          final id = int.tryParse(s[2]);
          if (id != null) {
            return MultiNavLocation(0, [const Feed(), Product(id)]);
          }
        }
        return const MultiNavLocation(0, [Feed()]);
      },
      fallback: const MultiNavLocation(0, [Feed()]),
    );

    testWidgets(
      'URL follows the active tab; deep links select tab + set its stack',
      (tester) async {
        final host = MultiNavStack<AppKey>([
          NavStack.of(const Feed()),
          NavStack.of(const Profile()),
        ]);
        addTearDown(host.dispose);
        final delegate = MultiNavStackRouterDelegate<AppKey>(
          host: host,
          codec: codec,
          builder: _screenFor,
        );
        addTearDown(delegate.dispose);

        await tester.pumpWidget(
          MaterialApp.router(
            routerDelegate: delegate,
            routeInformationParser: const NavStackRouteInformationParser(),
          ),
        );
        expect(find.text('feed'), findsOneWidget);
        expect(delegate.currentConfiguration.path, '/feed');

        // Deep link into the other tab.
        await delegate.setNewRoutePath(Uri.parse('/profile'));
        await tester.pumpAndSettle();
        expect(find.text('profile'), findsOneWidget);
        expect(host.index, 1);

        // Deep link that layers a product on the feed tab.
        await delegate.setNewRoutePath(Uri.parse('/feed/product/9'));
        await tester.pumpAndSettle();
        expect(find.text('product 9'), findsOneWidget);
        expect(host.index, 0);
        expect(host.active.keys, [isA<Feed>(), isA<Product>()]);
        expect(delegate.currentConfiguration.path, '/feed/product/9');

        // OS back pops the active tab's stack.
        await delegate.popRoute();
        await tester.pumpAndSettle();
        expect(find.text('feed'), findsOneWidget);
      },
      experimentalLeakTesting: LeakTesting.settings.withIgnoredAll(),
    );

    testWidgets(
      'a malformed multi-tab deep link falls back instead of crashing',
      (tester) async {
        final badCodec = MultiNavStackCodec<AppKey>.of(
          encode: (tab, stack) => Uri(path: '/feed'),
          // Throws on anything that isn't a bare int last segment.
          decode: (uri) =>
              MultiNavLocation(0, [Product(int.parse(uri.pathSegments.last))]),
          fallback: const MultiNavLocation(0, [Feed()]),
        );
        final host = MultiNavStack<AppKey>([
          NavStack.of(const Feed()),
          NavStack.of(const Profile()),
        ]);
        addTearDown(host.dispose);
        final delegate = MultiNavStackRouterDelegate<AppKey>(
          host: host,
          codec: badCodec,
          builder: _screenFor,
        );
        addTearDown(delegate.dispose);

        await tester.pumpWidget(
          MaterialApp.router(
            routerDelegate: delegate,
            routeInformationParser: const NavStackRouteInformationParser(),
          ),
        );

        await delegate.setNewRoutePath(Uri.parse('/totally/bogus'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('feed'), findsOneWidget);
      },
      experimentalLeakTesting: LeakTesting.settings.withIgnoredAll(),
    );
  });

  group('MultiNavDisplay lazy tab loading (fix #7)', () {
    testWidgets('an unvisited tab is not built until first selected', (
      tester,
    ) async {
      final host = MultiNavStack<AppKey>([
        NavStack.of(const Feed()),
        NavStack.of(const Profile()),
      ]);
      addTearDown(host.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: MultiNavDisplay<AppKey>(
            host: host,
            builder: _screenFor,
            lazy: true,
          ),
        ),
      );

      // Tab 1 hasn't been visited: its screen isn't built at all (not even
      // offstage).
      expect(find.text('profile', skipOffstage: false), findsNothing);

      host.select(1);
      await tester.pumpAndSettle();
      expect(find.text('profile'), findsOneWidget);
    });

    testWidgets('eager (default) builds every tab up front', (tester) async {
      final host = MultiNavStack<AppKey>([
        NavStack.of(const Feed()),
        NavStack.of(const Profile()),
      ]);
      addTearDown(host.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: MultiNavDisplay<AppKey>(host: host, builder: _screenFor),
        ),
      );

      // Offstage but present.
      expect(find.text('profile', skipOffstage: false), findsOneWidget);
    });
  });

  group('observers are forwarded (fix #5)', () {
    testWidgets('NavDisplay reports pushes to a supplied observer', (
      tester,
    ) async {
      final stack = NavStack<AppKey>.of(const Feed());
      addTearDown(stack.dispose);
      final observer = _CountingObserver();

      await tester.pumpWidget(
        MaterialApp(
          home: NavDisplay<AppKey>(
            stack: stack,
            observers: [observer],
            builder: _screenFor,
          ),
        ),
      );
      final initial = observer.pushes;

      stack.push(const Profile());
      await tester.pumpAndSettle();

      expect(observer.pushes, greaterThan(initial));
    });
  });

  group('NavListDetail preserves State across the breakpoint (fix #1)', () {
    testWidgets('detail State survives a wide → narrow layout flip', (
      tester,
    ) async {
      final width = ValueNotifier<double>(1000);
      addTearDown(width.dispose);
      final stack = NavStack<AppKey>.of(const Feed())..push(const Product(1));
      addTearDown(stack.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<double>(
              valueListenable: width,
              builder: (context, w, _) => Center(
                child: SizedBox(
                  width: w,
                  height: 700,
                  child: NavListDetail<AppKey>(
                    stack: stack,
                    isDetail: (k) => k is Product,
                    list: (context, key) => const _Bump('list'),
                    detail: (context, key) => const _Bump('detail'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // Wide: two panes. Bump the detail's State to 3.
      expect(find.text('detail:0'), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.textContaining('detail:'));
        await tester.pump();
      }
      expect(find.text('detail:3'), findsOneWidget);

      // Flip to narrow (phone width) — the detail becomes a Navigator page.
      width.value = 400;
      await tester.pumpAndSettle();

      // If the Element were rebuilt, this would be detail:0. Reparenting kept
      // the live State, so the count survived.
      expect(
        find.text('detail:3'),
        findsOneWidget,
        reason:
            'detail State was reparented across the breakpoint, not rebuilt',
      );
    });

    testWidgets('list State survives a narrow → wide layout flip', (
      tester,
    ) async {
      final width = ValueNotifier<double>(400);
      addTearDown(width.dispose);
      final stack = NavStack<AppKey>.of(const Feed());
      addTearDown(stack.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<double>(
              valueListenable: width,
              builder: (context, w, _) => Center(
                child: SizedBox(
                  width: w,
                  height: 700,
                  child: NavListDetail<AppKey>(
                    stack: stack,
                    isDetail: (k) => k is Product,
                    list: (context, key) => const _Bump('list'),
                    detail: (context, key) => const _Bump('detail'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('list:0'), findsOneWidget);
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.textContaining('list:'));
        await tester.pump();
      }
      expect(find.text('list:2'), findsOneWidget);

      width.value = 1000; // narrow → wide two-pane
      await tester.pumpAndSettle();

      expect(
        find.text('list:2'),
        findsOneWidget,
        reason: 'list State survived',
      );
    });
  });

  group('MultiBackStack.of reaches the host from a screen (fix #2b)', () {
    testWidgets('a deep screen can switch tabs via MultiBackStack.of', (
      tester,
    ) async {
      final host = MultiNavStack<AppKey>([
        NavStack.of(const Feed()),
        NavStack.of(const Profile()),
      ]);
      addTearDown(host.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: MultiNavDisplay<AppKey>(
            host: host,
            builder: (context, key) => switch (key) {
              Feed() => GestureDetector(
                onTap: () => MultiBackStack.of<AppKey>(context).select(1),
                child: const Text('feed'),
              ),
              _ => _screenFor(context, key),
            },
          ),
        ),
      );

      expect(host.index, 0);
      await tester.tap(find.text('feed'));
      await tester.pumpAndSettle();

      expect(
        host.index,
        1,
        reason: 'the Feed screen switched to the Profile tab',
      );
      expect(find.text('profile'), findsOneWidget);
    });
  });

  group('RestorableMultiNavStack survives process death (fix #3b)', () {
    testWidgets(
      'restores each tab and the active index',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            restorationScopeId: 'app',
            home: RestorableMultiNavStack<AppKey>(
              restorationId: 'tabs',
              create: () => MultiNavStack<AppKey>([
                NavStack.of(const Feed()),
                NavStack.of(const Profile()),
              ]),
              codec: const _AppKeyCodec(),
              builder: (context, host) =>
                  MultiNavDisplay<AppKey>(host: host, builder: _screenFor),
            ),
          ),
        );

        final host = tester
            .widget<MultiNavDisplay<AppKey>>(
              find.byType(MultiNavDisplay<AppKey>),
            )
            .host;
        host.active.push(const Product(3)); // deepen tab 0
        host.select(1); // move to tab 1
        await tester.pumpAndSettle();
        expect(find.text('profile'), findsOneWidget);

        await tester.restartAndRestore();
        await tester.pumpAndSettle();

        final restored = tester
            .widget<MultiNavDisplay<AppKey>>(
              find.byType(MultiNavDisplay<AppKey>),
            )
            .host;
        expect(restored.index, 1, reason: 'active tab came back');
        expect(find.text('profile'), findsOneWidget);
        expect(
          restored.tabs[0].keys,
          [isA<Feed>(), isA<Product>()],
          reason: 'the other tab kept its deep stack',
        );
      },
      experimentalLeakTesting: LeakTesting.settings.withIgnoredAll(),
    );
  });

  group('NavEntries — registrable builder (Nav3 entryProvider)', () {
    testWidgets('renders registered screens and drives navigation', (
      tester,
    ) async {
      final stack = NavStack<AppKey>.of(const Feed());
      addTearDown(stack.dispose);
      final entries = NavEntries<AppKey>()
        ..on<Feed>(
          (context, key) =>
              const Text('feed', textDirection: TextDirection.ltr),
        )
        ..on<Product>(
          (context, key) =>
              Text('product ${key.id}', textDirection: TextDirection.ltr),
        );

      await tester.pumpWidget(
        MaterialApp(
          home: NavDisplay<AppKey>(stack: stack, builder: entries.call),
        ),
      );
      expect(find.text('feed'), findsOneWidget);

      stack.push(const Product(7));
      await tester.pumpAndSettle();
      expect(find.text('product 7'), findsOneWidget);
    });

    testWidgets('throws for an unregistered destination', (tester) async {
      final stack = NavStack<AppKey>.of(const Feed());
      addTearDown(stack.dispose);
      final entries = NavEntries<AppKey>()
        ..on<Feed>(
          (context, key) =>
              const Text('feed', textDirection: TextDirection.ltr),
        );

      await tester.pumpWidget(
        MaterialApp(
          home: NavDisplay<AppKey>(stack: stack, builder: entries.call),
        ),
      );
      stack.push(const Profile()); // never registered
      await tester.pumpAndSettle();
      expect(tester.takeException(), isA<StateError>());
    });

    test('composes across modules', () {
      final entries = NavEntries<AppKey>();
      // Two "feature modules" register into one shared instance.
      void registerFeed(NavEntries<AppKey> e) => e.on<Feed>(
        (c, k) => const Text('feed', textDirection: TextDirection.ltr),
      );
      void registerShop(NavEntries<AppKey> e) => e.on<Product>(
        (c, k) => const Text('shop', textDirection: TextDirection.ltr),
      );
      registerFeed(entries);
      registerShop(entries);

      expect(entries.has<Feed>(), isTrue);
      expect(entries.has<Product>(), isTrue);
      expect(entries.has<Profile>(), isFalse);
    });
  });

  group('NavEntryDecorator (Nav3 decorators)', () {
    testWidgets('decorate wraps the visible screen', (tester) async {
      final stack = NavStack<AppKey>.of(const Feed());
      addTearDown(stack.dispose);
      final deco = NavEntryDecorator<AppKey>(
        decorate: (context, key, child) => Stack(
          children: [
            child,
            const Text('deco', textDirection: TextDirection.ltr),
          ],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: NavDisplay<AppKey>(
            stack: stack,
            builder: _screenFor,
            decorators: [deco],
          ),
        ),
      );

      expect(find.text('feed'), findsOneWidget);
      expect(find.text('deco'), findsOneWidget); // wrapper applied
    });

    testWidgets('onRemoved fires with the key when an entry is popped', (
      tester,
    ) async {
      final stack = NavStack<AppKey>.of(const Feed());
      addTearDown(stack.dispose);
      final removed = <AppKey>[];
      final deco = NavEntryDecorator<AppKey>(onRemoved: removed.add);

      await tester.pumpWidget(
        MaterialApp(
          home: NavDisplay<AppKey>(
            stack: stack,
            builder: _screenFor,
            decorators: [deco],
          ),
        ),
      );

      stack.push(const Product(1));
      await tester.pumpAndSettle();
      expect(removed, isEmpty);

      stack.pop();
      await tester.pumpAndSettle();
      expect(removed, [
        isA<Product>(),
      ], reason: 'the popped entry was cleaned up');
    });

    testWidgets('onRemoved fires for remaining entries when disposed', (
      tester,
    ) async {
      final stack = NavStack<AppKey>.of(const Feed());
      addTearDown(stack.dispose);
      final removed = <AppKey>[];
      final deco = NavEntryDecorator<AppKey>(onRemoved: removed.add);

      await tester.pumpWidget(
        MaterialApp(
          home: NavDisplay<AppKey>(
            stack: stack,
            builder: _screenFor,
            decorators: [deco],
          ),
        ),
      );
      expect(removed, isEmpty);

      // Tear the display down — its remaining entry's scope must be cleaned up.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(removed, [isA<Feed>()]);
    });
  });
}
