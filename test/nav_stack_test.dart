import 'package:back_stack/back_stack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';

// Test destinations — plain, typed Dart objects. This is the "routes" table.
class Home extends NavKey {
  const Home();
}

class Detail extends NavKey {
  const Detail(this.id);
  final int id;
}

/// A destination with value equality — two `EqDetail(5)` built separately are
/// equal, so they reconcile (State preserved) across a URL re-decode.
class EqDetail extends NavKey with EquatableNavKey {
  const EqDetail(this.id);
  final int id;
  @override
  List<Object?> get props => [id];
}

/// A tiny codec for the Router tests: `/detail/<id>` ⇄ stack, deep links
/// layered on top of Home.
class TestCodec extends NavStackCodec<NavKey> {
  const TestCodec();

  @override
  Uri encode(List<NavKey> stack) => switch (stack.last) {
    Detail(:final id) => Uri(path: '/detail/$id'),
    _ => Uri(path: '/'),
  };

  @override
  List<NavKey> decode(Uri uri) {
    final seg = uri.pathSegments;
    if (seg.length == 2 && seg[0] == 'detail') {
      return [const Home(), Detail(int.parse(seg[1]))];
    }
    return [const Home()];
  }
}

/// A screen that records when its State is disposed — used to prove that
/// leaving the stack actually tears the route down (no leaked screens/controllers).
class DisposeSpy extends StatefulWidget {
  const DisposeSpy({required this.onDispose, super.key});
  final VoidCallback onDispose;
  @override
  State<DisposeSpy> createState() => _DisposeSpyState();
}

class _DisposeSpyState extends State<DisposeSpy> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// List-detail test destinations.
class Inbox extends NavKey {
  const Inbox();
}

class Message extends NavKey {
  const Message(this.id);
  final int id;
}

/// A supporting destination (e.g. a filters panel) for the scene engine test.
class Filters extends NavKey {
  const Filters();
}

/// A destination that declares its own page via the [NavPage] mixin — no
/// `switch` in `pageBuilder` needed.
class SelfPaged extends NavKey with NavPage {
  const SelfPaged();
  @override
  Page<dynamic> buildPage(
    BuildContext context,
    Widget child,
    LocalKey pageKey,
  ) => TransitionPage<dynamic>.none(key: pageKey, child: child);
}

void main() {
  group('NavStack — navigation is a list', () {
    test('starts on its root and cannot pop past it', () {
      final stack = NavStack<NavKey>.of(const Home());
      expect(stack.current, isA<Home>());
      expect(stack.length, 1);
      expect(stack.canPop, isFalse);
      expect(stack.pop(), isFalse, reason: 'root is never popped');
      expect(stack.length, 1);
    });

    test('push adds, pop removes', () {
      final stack = NavStack<NavKey>.of(const Home());
      stack.push(const Detail(7));
      expect(stack.current, isA<Detail>());
      expect((stack.current as Detail).id, 7);
      expect(stack.canPop, isTrue);

      expect(stack.pop(), isTrue);
      expect(stack.current, isA<Home>());
    });

    test('duplicate destinations are independent slots', () {
      final stack = NavStack<NavKey>.of(const Home())
        ..push(const Detail(5))
        ..push(const Detail(5));
      expect(stack.length, 3);
      // Two identical Detail(5) keep distinct ids so their State survives.
      expect(stack.entries[1].id, isNot(stack.entries[2].id));
    });

    test('replaceAll resets the flow (e.g. after login)', () {
      final stack = NavStack<NavKey>([
        const Home(),
        const Detail(1),
        const Detail(2),
      ]);
      stack.replaceAll([const Home()]);
      expect(stack.keys, [isA<Home>()]);
    });

    test('popUntil unwinds to the first match', () {
      final stack = NavStack<NavKey>([
        const Home(),
        const Detail(1),
        const Detail(2),
        const Detail(3),
      ]);
      stack.popUntil((k) => k is Home);
      expect(stack.length, 1);
      expect(stack.current, isA<Home>());
    });

    test('edit() treats the stack as a plain list', () {
      final stack = NavStack<NavKey>([
        const Home(),
        const Detail(1),
        const Detail(2),
      ]);
      stack.edit((keys) => keys.removeWhere((k) => k is Detail && k.id == 1));
      expect(stack.keys.whereType<Detail>().map((d) => d.id), [2]);
    });

    test('edit() preserves entry identity (State) for retained screens', () {
      final stack = NavStack<NavKey>([
        const Home(),
        const Detail(1),
        const Detail(2),
      ]);
      final homeId = stack.entries[0].id;
      final detail2Id = stack.entries[2].id;

      // Remove the middle screen; Home and Detail(2) must keep their ids so
      // their State (controllers, scroll) survives instead of being rebuilt.
      stack.edit((keys) => keys.removeWhere((k) => k is Detail && k.id == 1));

      expect(stack.entries[0].id, homeId, reason: 'Home State preserved');
      expect(
        stack.entries[1].id,
        detail2Id,
        reason: 'Detail(2) State preserved',
      );
    });

    test('replaceAll reconciles — only changed screens are rebuilt', () {
      final stack = NavStack<NavKey>([const Home(), const Detail(1)]);
      final homeId = stack.entries[0].id;

      // Reset to [Home, Detail(2)]: Home survives (same const instance), only
      // Detail changes.
      stack.replaceAll([const Home(), const Detail(2)]);

      expect(stack.entries[0].id, homeId, reason: 'Home not rebuilt');
      expect((stack.entries[1].key as Detail).id, 2);
    });

    test('guard can veto a change (loop-proof auth gate)', () {
      final stack = NavStack<NavKey>.of(const Home())
        ..guard = (proposed) => proposed.length <= 2; // never go deeper than 2
      stack.push(const Detail(1)); // ok -> length 2
      stack.push(const Detail(2)); // vetoed -> stays at 2
      expect(stack.length, 2);
      expect(stack.current, isA<Detail>());
      expect((stack.current as Detail).id, 1);
    });

    test('notifies listeners on change, stays silent on no-op', () {
      final stack = NavStack<NavKey>.of(const Home());
      var notifications = 0;
      stack.addListener(() => notifications++);

      stack.push(const Detail(1)); // change -> notify
      stack.pop(); // change -> notify
      stack.pop(); // no-op (root) -> silent
      expect(notifications, 2);
    });

    test('redirect transforms the proposed stack (loop-proof auth gate)', () {
      var loggedIn = false;
      final stack = NavStack<NavKey>.of(const Home())
        ..redirect = (proposed) {
          final guarded = proposed.any((k) => k is Detail);
          if (guarded && !loggedIn) return [const Home()]; // bounce to Home
          return proposed;
        };

      stack.push(const Detail(1)); // redirected away
      expect(stack.keys, [isA<Home>()], reason: 'blocked while logged out');

      loggedIn = true;
      stack.push(const Detail(1)); // now allowed
      expect(stack.current, isA<Detail>());
    });

    test('EquatableNavKey: equal keys reconcile across instances', () {
      // Non-const so the two EqDetail(5) are genuinely different objects.
      final first = EqDetail(5);
      final stack = NavStack<NavKey>([const Home(), first]);
      final id = stack.entries[1].id;

      // Simulates a deep-link re-decode producing a fresh-but-equal key.
      stack.replaceAll([const Home(), EqDetail(5)]);
      expect(
        stack.entries[1].id,
        id,
        reason: 'equal key reused → live screen State preserved',
      );
    });

    test('without value equality, a fresh-but-equal key is NOT reused', () {
      final stack = NavStack<NavKey>([
        const Home(),
        Detail(5),
      ]); // non-const instance
      final id = stack.entries[1].id;

      stack.replaceAll([const Home(), Detail(5)]); // different instance, not ==
      expect(
        stack.entries[1].id,
        isNot(id),
        reason: 'motivates EquatableNavKey for keys that ride the URL',
      );
    });
  });

  group('NavDisplay — the list renders', () {
    testWidgets('shows the top destination and follows pushes/pops', (
      tester,
    ) async {
      final stack = NavStack<NavKey>.of(const Home());
      addTearDown(stack.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: NavDisplay<NavKey>(
            stack: stack,
            builder: (context, key) => switch (key) {
              Home() => const Text('home'),
              Detail(:final id) => Text('detail $id'),
              _ => const Text('?'),
            },
          ),
        ),
      );
      expect(find.text('home'), findsOneWidget);

      stack.push(const Detail(42));
      await tester.pumpAndSettle();
      expect(find.text('detail 42'), findsOneWidget);

      stack.pop();
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('system back pop keeps the stack in sync', (tester) async {
      final stack = NavStack<NavKey>.of(const Home())..push(const Detail(1));
      addTearDown(stack.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: NavDisplay<NavKey>(
            stack: stack,
            builder: (context, key) => switch (key) {
              Home() => const Text('home'),
              Detail(:final id) => Text('detail $id'),
              _ => const Text('?'),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('detail 1'), findsOneWidget);

      // A framework-driven pop (system back gesture / predictive back lands
      // here) goes through the Navigator, NOT through stack.pop(). Prove it
      // still syncs the owned list via onDidRemovePage.
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).last,
      );
      final didPop = await navigator.maybePop();
      await tester.pumpAndSettle();

      expect(didPop, isTrue);
      expect(stack.length, 1, reason: 'framework pop synced back to the list');
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('popping a screen disposes its State (no leak)', (
      tester,
    ) async {
      var disposed = false;
      final stack = NavStack<NavKey>.of(const Home());
      addTearDown(stack.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: NavDisplay<NavKey>(
            stack: stack,
            builder: (context, key) => switch (key) {
              Home() => const Text('home'),
              Detail() => DisposeSpy(onDispose: () => disposed = true),
              _ => const Text('?'),
            },
          ),
        ),
      );

      stack.push(const Detail(1));
      await tester.pumpAndSettle();
      expect(disposed, isFalse);

      stack.pop();
      await tester.pumpAndSettle();
      expect(
        disposed,
        isTrue,
        reason: 'leaving the stack tears down the route and frees the screen',
      );
    });

    testWidgets('screens reach the stack via BackStack.of<NavKey>(context)', (
      tester,
    ) async {
      final stack = NavStack<NavKey>.of(const Home());
      addTearDown(stack.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: NavDisplay<NavKey>(
            stack: stack,
            builder: (context, key) => switch (key) {
              Home() => TextButton(
                // No stack passed in — read it from context.
                onPressed: () =>
                    BackStack.of<NavKey>(context).push(const Detail(1)),
                child: const Text('go'),
              ),
              Detail() => const Text('detail'),
              _ => const Text('?'),
            },
          ),
        ),
      );

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('detail'), findsOneWidget);
      expect(stack.length, 2);
    });

    testWidgets('BackStack.maybeOf returns null with no scope', (tester) async {
      NavStack? found;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              found = BackStack.maybeOf<NavKey>(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(found, isNull);
    });

    testWidgets('removing a middle screen keeps the survivor alive', (
      tester,
    ) async {
      var topDisposed = false;
      final stack = NavStack<NavKey>([
        const Home(),
        const Detail(1),
        const Detail(2),
      ]);
      addTearDown(stack.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: NavDisplay<NavKey>(
            stack: stack,
            builder: (context, key) => switch (key) {
              Detail(:final id) when id == 2 => DisposeSpy(
                onDispose: () => topDisposed = true,
              ),
              _ => const SizedBox.shrink(),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Drop the MIDDLE screen. The top (Detail 2) must NOT be rebuilt/disposed.
      stack.edit((keys) => keys.removeWhere((k) => k is Detail && k.id == 1));
      await tester.pumpAndSettle();

      expect(
        topDisposed,
        isFalse,
        reason: 'reconciliation preserved the survivor State',
      );
      expect(stack.length, 2);
    });
  });

  group('pushForResult — awaiting a screen', () {
    test('completes with the value passed to pop', () async {
      final stack = NavStack<NavKey>.of(const Home());
      final result = stack.pushForResult<int>(const Detail(1));
      stack.pop(99);
      expect(await result, 99);
    });

    test('completes null when popped without a result', () async {
      final stack = NavStack<NavKey>.of(const Home());
      final result = stack.pushForResult<int>(const Detail(1));
      stack.pop();
      expect(await result, isNull);
    });

    test(
      'completes null when the screen leaves another way (no hang)',
      () async {
        final stack = NavStack<NavKey>.of(const Home());
        final result = stack.pushForResult<int>(const Detail(1));
        stack.replaceAll([const Home()]); // Detail(1) dropped
        expect(await result, isNull);
      },
    );

    test('completes null when the stack is disposed (no hang)', () async {
      final stack = NavStack<NavKey>.of(const Home());
      final result = stack.pushForResult<int>(const Detail(1));
      stack.dispose();
      expect(await result, isNull);
    });
  });

  group('NavStackRouterDelegate — URL is a projection of the stack', () {
    // MaterialApp.router creates framework-owned objects
    // (PlatformRouteInformationProvider, BackButtonDispatcher) that leak_tracker
    // flags but the framework, not us, owns. Our delegate + stack ARE disposed
    // (addTearDown). Scope leak tracking off for these two router tests.
    testWidgets(
      'URL follows the stack; deep links set the stack',
      (tester) async {
        final stack = NavStack<NavKey>.of(const Home());
        addTearDown(stack.dispose);
        final delegate = NavStackRouterDelegate<NavKey>(
          stack: stack,
          codec: const TestCodec(),
          builder: (context, key) => switch (key) {
            Home() => const Text('home'),
            Detail(:final id) => Text('detail $id'),
            _ => const Text('?'),
          },
        );
        addTearDown(delegate.dispose);

        await tester.pumpWidget(
          MaterialApp.router(
            routerDelegate: delegate,
            routeInformationParser: const NavStackRouteInformationParser(),
          ),
        );
        expect(find.text('home'), findsOneWidget);
        expect(delegate.currentConfiguration.path, '/');

        // Push → URL updates (URL is a projection of the stack).
        stack.push(const Detail(7));
        await tester.pumpAndSettle();
        expect(delegate.currentConfiguration.path, '/detail/7');

        // Deep link → the stack the codec constructs (layered on Home).
        await delegate.setNewRoutePath(Uri.parse('/detail/9'));
        await tester.pumpAndSettle();
        expect(find.text('detail 9'), findsOneWidget);
        expect(stack.keys, [isA<Home>(), isA<Detail>()]);
      },
      experimentalLeakTesting: LeakTesting.settings.withIgnoredAll(),
    );

    testWidgets(
      'OS back (popRoute) pops the stack',
      (tester) async {
        // Under Router the initial URL ('/') seeds the stack, so push after mount.
        final stack = NavStack<NavKey>.of(const Home());
        addTearDown(stack.dispose);
        final delegate = NavStackRouterDelegate<NavKey>(
          stack: stack,
          codec: const TestCodec(),
          builder: (context, key) => switch (key) {
            Home() => const Text('home'),
            Detail(:final id) => Text('detail $id'),
            _ => const Text('?'),
          },
        );
        addTearDown(delegate.dispose);

        await tester.pumpWidget(
          MaterialApp.router(
            routerDelegate: delegate,
            routeInformationParser: const NavStackRouteInformationParser(),
          ),
        );
        await tester.pumpAndSettle();
        stack.push(const Detail(1));
        await tester.pumpAndSettle();
        expect(find.text('detail 1'), findsOneWidget);

        final didPop = await delegate.popRoute();
        await tester.pumpAndSettle();
        expect(didPop, isTrue);
        expect(stack.length, 1);
        expect(find.text('home'), findsOneWidget);
      },
      experimentalLeakTesting: LeakTesting.settings.withIgnoredAll(),
    );
  });

  group('popGuard & refreshListenable', () {
    test('popGuard vetoes a programmatic pop', () {
      var allow = false;
      final stack = NavStack<NavKey>.of(const Home())
        ..push(const Detail(1))
        ..popGuard = (top) => allow;

      expect(stack.pop(), isFalse, reason: 'guard blocked it');
      expect(stack.length, 2);

      allow = true;
      expect(stack.pop(), isTrue);
      expect(stack.length, 1);
    });

    test('refreshListenable re-runs redirect when it fires', () {
      var loggedIn = false;
      final auth = ChangeNotifier();
      final stack = NavStack<NavKey>.of(const Home())
        ..redirect = (proposed) {
          if (proposed.any((k) => k is Detail) && !loggedIn) {
            return [const Home()];
          }
          return proposed;
        }
        ..refreshListenable = auth;

      stack.push(const Detail(1)); // bounced while logged out
      expect(stack.keys, [isA<Home>()]);

      loggedIn = true;
      auth.notifyListeners();
      stack.push(const Detail(1)); // now allowed
      expect(stack.current, isA<Detail>());

      auth.dispose();
      stack.dispose();
    });
  });

  group('MultiNavStack — per-tab back stacks', () {
    MultiNavStack<NavKey> makeHost() => MultiNavStack<NavKey>([
      NavStack<NavKey>.of(const Home()),
      NavStack<NavKey>.of(const Detail(0)),
    ]);

    test('select switches the active tab; tabs are independent', () {
      final host = makeHost();
      expect(host.index, 0);
      expect(host.active.current, isA<Home>());

      host.tabs[1].push(const Detail(99));
      host.select(1);
      expect(host.index, 1);
      expect(host.active.length, 2, reason: 'tab 1 kept its history');

      host.select(0);
      expect(host.active.current, isA<Home>(), reason: 'tab 0 untouched');
      host.dispose();
    });

    test('re-selecting the active tab pops it to root', () {
      final host = makeHost()..tabs[0].push(const Detail(1));
      expect(host.active.length, 2);
      host.select(0);
      expect(host.active.length, 1, reason: 'popped to root');
      host.dispose();
    });

    test(
      'handleBack pops the active tab, then falls back to the first tab',
      () {
        final host = makeHost()
          ..select(1)
          ..tabs[1].push(const Detail(5));
        expect(host.active.length, 2);

        expect(host.handleBack(), isTrue); // pop within tab 1
        expect(host.active.length, 1);

        expect(host.handleBack(), isTrue); // tab 1 at root -> jump to tab 0
        expect(host.index, 0);

        expect(host.handleBack(), isFalse, reason: 'nothing left to handle');
        host.dispose();
      },
    );
  });

  group('MultiNavDisplay — tabs stay alive', () {
    testWidgets('switching tabs preserves the inactive tab State', (
      tester,
    ) async {
      var tab0Disposed = false;
      final host = MultiNavStack<NavKey>([
        NavStack<NavKey>.of(const Home()),
        NavStack<NavKey>.of(const Detail(1)),
      ]);
      addTearDown(host.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: MultiNavDisplay<NavKey>(
            host: host,
            builder: (context, key) => switch (key) {
              Home() => DisposeSpy(onDispose: () => tab0Disposed = true),
              _ => const Text('other'),
            },
          ),
        ),
      );
      host.select(1);
      await tester.pumpAndSettle();

      expect(
        tab0Disposed,
        isFalse,
        reason: 'IndexedStack keeps the inactive tab mounted',
      );
    });
  });

  group('DialogPage — modal as a stack entry', () {
    testWidgets('renders as a dialog and pops off the stack', (tester) async {
      final stack = NavStack<NavKey>.of(const Home());
      addTearDown(stack.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: NavDisplay<NavKey>(
            stack: stack,
            builder: (context, key) => const Text('home'),
            pageBuilder: (context, key, pageKey) => switch (key) {
              Detail() => DialogPage<void>(
                key: pageKey,
                builder: (_) => const AlertDialog(content: Text('dialog!')),
              ),
              _ => MaterialPage<void>(key: pageKey, child: const Text('home')),
            },
          ),
        ),
      );

      stack.push(const Detail(1));
      await tester.pumpAndSettle();
      expect(find.text('dialog!'), findsOneWidget);

      stack.pop();
      await tester.pumpAndSettle();
      expect(find.text('dialog!'), findsNothing);
    });
  });

  group('RestorableBackStack — survives process death', () {
    testWidgets(
      'restores the full stack after restart',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            restorationScopeId: 'app',
            home: RestorableBackStack<NavKey>(
              restorationId: 'nav',
              create: () => NavStack<NavKey>.of(const Home()),
              codec: const _TestKeyCodec(),
              builder: (context, stack) => NavDisplay<NavKey>(
                stack: stack,
                builder: (context, key) => switch (key) {
                  Home() => const Text('home'),
                  Detail(:final id) => Text('detail $id'),
                  _ => const Text('?'),
                },
              ),
            ),
          ),
        );

        tester
            .widget<NavDisplay<NavKey>>(find.byType(NavDisplay<NavKey>))
            .stack
            .push(const Detail(7));
        await tester.pumpAndSettle();
        expect(find.text('detail 7'), findsOneWidget);

        await tester.restartAndRestore();
        await tester.pumpAndSettle();
        expect(
          find.text('detail 7'),
          findsOneWidget,
          reason: 'the deep stack came back after process death',
        );
      },
      experimentalLeakTesting: LeakTesting.settings.withIgnoredAll(),
    );
  });

  group('NavPage mixin — a destination owns its presentation', () {
    testWidgets('a NavPage key builds its own Page without a pageBuilder', (
      tester,
    ) async {
      final stack = NavStack<NavKey>.of(const Home());
      addTearDown(stack.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: NavDisplay<NavKey>(
            stack: stack,
            builder: (context, key) => switch (key) {
              SelfPaged() => const Text('self'),
              _ => const Text('home'),
            },
          ),
        ),
      );

      stack.push(const SelfPaged());
      // .none transition is instant — one pump is enough, no settle needed.
      await tester.pump();
      expect(find.text('self'), findsOneWidget);
    });
  });

  group('ConfirmPopScope — async confirm before leaving', () {
    testWidgets('stays put when confirm resolves false, leaves when true', (
      tester,
    ) async {
      final stack = NavStack<NavKey>.of(const Home())..push(const Detail(1));
      addTearDown(stack.dispose);
      var answer = false;

      await tester.pumpWidget(
        MaterialApp(
          home: NavDisplay<NavKey>(
            stack: stack,
            builder: (context, key) => switch (key) {
              Detail() => ConfirmPopScope(
                confirm: () async => answer,
                child: const Text('detail'),
              ),
              _ => const Text('home'),
            },
          ),
        ),
      );
      expect(find.text('detail'), findsOneWidget);

      // System back, confirm says "no" -> still here.
      await tester
          .state<NavigatorState>(find.byType(Navigator).last)
          .maybePop();
      await tester.pumpAndSettle();
      expect(stack.length, 2);
      expect(find.text('detail'), findsOneWidget);

      // Now confirm says "yes" -> popped off the stack.
      answer = true;
      await tester
          .state<NavigatorState>(find.byType(Navigator).last)
          .maybePop();
      await tester.pumpAndSettle();
      expect(stack.length, 1);
      expect(find.text('home'), findsOneWidget);
    });
  });

  group('nested NavDisplay — a child stack claims back first', () {
    testWidgets('system back pops the child stack before the parent', (
      tester,
    ) async {
      final parent = NavStack<NavKey>.of(const Home());
      final child = NavStack<NavKey>.of(const Detail(0))..push(const Detail(1));
      addTearDown(parent.dispose);
      addTearDown(child.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: NavDisplay<NavKey>(
            stack: parent,
            builder: (context, key) => NavDisplay<NavKey>(
              stack: child,
              nested: true,
              builder: (context, k) => switch (k) {
                Detail(:final id) => Text('child $id'),
                _ => const Text('child ?'),
              },
            ),
          ),
        ),
      );
      expect(find.text('child 1'), findsOneWidget);

      // Back reaches the parent navigator (index 1: root=0, parent=1, child=2);
      // the nested display's PopScope is registered there and claims it,
      // popping the child stack instead of the parent.
      await tester
          .state<NavigatorState>(find.byType(Navigator).at(1))
          .maybePop();
      await tester.pumpAndSettle();
      expect(child.length, 1, reason: 'child popped first');
      expect(
        parent.length,
        1,
        reason: 'parent untouched while child could pop',
      );
      expect(find.text('child 0'), findsOneWidget);
    });
  });

  group('NavListDetail — one stack, two adaptive layouts', () {
    Widget app(NavStack<NavKey> stack) => MaterialApp(
      home: NavListDetail<NavKey>(
        stack: stack,
        isDetail: (key) => key is Message,
        list: (context, key) => const Text('inbox'),
        detail: (context, key) => Text('message ${(key as Message).id}'),
        placeholder: (context) => const Text('pick one'),
      ),
    );

    testWidgets('wide: list + detail share the screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final stack = NavStack<NavKey>.of(const Inbox())..push(const Message(7));
      addTearDown(stack.dispose);

      await tester.pumpWidget(app(stack));
      await tester.pumpAndSettle();
      expect(find.text('inbox'), findsOneWidget, reason: 'left pane');
      expect(find.text('message 7'), findsOneWidget, reason: 'right pane');
    });

    testWidgets('wide: placeholder shows when no detail is selected', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final stack = NavStack<NavKey>.of(const Inbox());
      addTearDown(stack.dispose);

      await tester.pumpWidget(app(stack));
      await tester.pumpAndSettle();
      expect(find.text('inbox'), findsOneWidget);
      expect(find.text('pick one'), findsOneWidget);
      expect(find.textContaining('message'), findsNothing);
    });

    testWidgets('narrow: same stack collapses to a single pane', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final stack = NavStack<NavKey>.of(const Inbox())..push(const Message(7));
      addTearDown(stack.dispose);

      await tester.pumpWidget(app(stack));
      await tester.pumpAndSettle();
      // Single-pane stack shows the top destination; the list is offstage.
      expect(find.text('message 7'), findsOneWidget);
      expect(find.text('inbox'), findsNothing);
    });

    testWidgets('wide: back collapses the detail pane via the one stack', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final stack = NavStack<NavKey>.of(const Inbox())..push(const Message(7));
      addTearDown(stack.dispose);

      await tester.pumpWidget(app(stack));
      await tester.pumpAndSettle();
      expect(find.text('message 7'), findsOneWidget);

      stack.pop(); // same stack drives both layouts
      await tester.pumpAndSettle();
      expect(find.text('message 7'), findsNothing);
      expect(
        find.text('pick one'),
        findsOneWidget,
        reason: 'collapsed to placeholder',
      );
    });
  });

  group('NavSceneHost — the engine generalizes past list-detail', () {
    Widget app(NavStack<NavKey> stack) => MaterialApp(
      home: NavSceneHost<NavKey>(
        stack: stack,
        builder: (context, key) => switch (key) {
          Filters() => const Text('filters'),
          _ => const Text('inbox'),
        },
        scenes: [
          supportingPaneScene<NavKey>(
            isSupporting: (key) => key is Filters,
            primary: (context, key) => const Text('inbox'),
            supporting: (context, key) => const Text('filters'),
          ),
        ],
      ),
    );

    testWidgets('wide: supporting pane docks beside primary', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final stack = NavStack<NavKey>.of(const Inbox())..push(const Filters());
      addTearDown(stack.dispose);

      await tester.pumpWidget(app(stack));
      await tester.pumpAndSettle();
      expect(find.text('inbox'), findsOneWidget, reason: 'primary pane');
      expect(find.text('filters'), findsOneWidget, reason: 'docked supporting');
    });

    testWidgets('narrow: strategy declines, supporting becomes a pushed page', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(420, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final stack = NavStack<NavKey>.of(const Inbox())..push(const Filters());
      addTearDown(stack.dispose);

      await tester.pumpWidget(app(stack));
      await tester.pumpAndSettle();
      // Single-pane fallback shows only the top; primary is offstage.
      expect(find.text('filters'), findsOneWidget);
      expect(find.text('inbox'), findsNothing);
    });
  });
}

/// Per-key codec for the restoration test.
class _TestKeyCodec extends NavKeyCodec<NavKey> {
  const _TestKeyCodec();
  @override
  String encode(NavKey key) => key is Detail ? 'detail:${key.id}' : 'home';
  @override
  NavKey decode(String data) => data.startsWith('detail:')
      ? Detail(int.parse(data.substring(7)))
      : const Home();
}
