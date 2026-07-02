import 'dart:async';

import 'package:back_stack/back_stack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

sealed class K extends NavKey with EquatableNavKey {
  const K();
}

class Home extends K {
  const Home();
  @override
  List<Object?> get props => const [];
}

class Product extends K {
  const Product(this.id);
  final int id;
  @override
  List<Object?> get props => [id];
}

class Profile extends K {
  const Profile();
  @override
  List<Object?> get props => const [];
}

class Confirm extends K {
  const Confirm();
  @override
  List<Object?> get props => const [];
}

NavLinks<K> buildLinks() => NavLinks<K>()
  ..on<Home>('/', decode: (m) => const Home())
  ..on<Product>(
    '/products/:id',
    decode: (m) => Product(m.integer('id')!),
    encode: (key) => {'id': key.id},
    parents: (key) => const [Home()],
  )
  ..on<Profile>('/profile', decode: (m) => const Profile());

NavEntries<K> buildEntries() => NavEntries<K>()
  ..on<Home>((context, key) => const Text('home-screen'))
  ..on<Product>((context, key) => Text('product-${key.id}'))
  ..on<Profile>((context, key) => const Text('profile-screen'))
  ..on<Confirm>(
    (context, key) => const Text('confirm-content'),
    page: (context, key, child, pageKey) => DialogPage<void>(
      key: pageKey,
      builder: (_) => AlertDialog(content: child),
    ),
  );

void main() {
  group('BackStackApp zero-config', () {
    testWidgets('stack + entries is a complete app', (tester) async {
      final stack = NavStack<K>.of(const Home());
      addTearDown(stack.dispose);

      await tester.pumpWidget(
        BackStackApp<K>(stack: stack, entries: buildEntries()),
      );
      await tester.pumpAndSettle();
      expect(find.text('home-screen'), findsOneWidget);

      stack.push(const Product(1));
      await tester.pumpAndSettle();
      expect(find.text('product-1'), findsOneWidget);

      stack.pop();
      await tester.pumpAndSettle();
      expect(find.text('home-screen'), findsOneWidget);
    });

    testWidgets('shell wraps the navigating area under MaterialApp', (
      tester,
    ) async {
      final stack = NavStack<K>.of(const Home());
      addTearDown(stack.dispose);

      await tester.pumpWidget(
        BackStackApp<K>(
          stack: stack,
          entries: buildEntries(),
          shell: (context, s, child) => Column(
            children: [
              const Text('side-rail'),
              Expanded(child: child),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('side-rail'), findsOneWidget);
      expect(find.text('home-screen'), findsOneWidget);
    });
  });

  group('BackStackApp links', () {
    testWidgets('a runtime link becomes the stack, with parents', (
      tester,
    ) async {
      final stack = NavStack<K>.of(const Home());
      addTearDown(stack.dispose);
      final linkController = StreamController<Uri>();
      addTearDown(linkController.close);

      await tester.pumpWidget(
        BackStackApp<K>(
          stack: stack,
          entries: buildEntries(),
          links: buildLinks(),
          linkStream: linkController.stream,
        ),
      );
      await tester.pumpAndSettle();

      linkController.add(Uri.parse('/products/42'));
      await tester.pumpAndSettle();
      expect(find.text('product-42'), findsOneWidget);
      expect(stack.keys, const [Home(), Product(42)]);
      // Back from the deep link goes Home, because the table said so.
      expect(stack.canPop, isTrue);
    });

    testWidgets('a malformed link falls back instead of crashing', (
      tester,
    ) async {
      final stack = NavStack<K>.of(const Home())..push(const Product(1));
      addTearDown(stack.dispose);
      final linkController = StreamController<Uri>();
      addTearDown(linkController.close);

      await tester.pumpWidget(
        BackStackApp<K>(
          stack: stack,
          entries: buildEntries(),
          links: buildLinks(),
          linkStream: linkController.stream,
        ),
      );
      await tester.pumpAndSettle();

      linkController.add(Uri.parse('/products/not-a-number'));
      await tester.pumpAndSettle();
      // No notFound registered → falls back to decoding '/'.
      expect(stack.keys, const [Home()]);
    });

    testWidgets('onLinkAsync resolves links; newer links win the race', (
      tester,
    ) async {
      final stack = NavStack<K>.of(const Home());
      addTearDown(stack.dispose);
      final linkController = StreamController<Uri>();
      addTearDown(linkController.close);
      final slow = Completer<List<K>?>();

      await tester.pumpWidget(
        BackStackApp<K>(
          stack: stack,
          entries: buildEntries(),
          links: buildLinks(),
          linkStream: linkController.stream,
          onLinkAsync: (uri) => uri.path == '/slow'
              ? slow.future
              // null → fall through to the links table
              : Future<List<K>?>.value(),
        ),
      );
      await tester.pumpAndSettle();

      linkController.add(Uri.parse('/slow'));
      await tester.pump();
      linkController.add(Uri.parse('/products/7'));
      await tester.pumpAndSettle();
      expect(find.text('product-7'), findsOneWidget);

      // The slow resolution finishes late — it must NOT clobber the newer link.
      slow.complete(const [Home(), Profile()]);
      await tester.pumpAndSettle();
      expect(find.text('product-7'), findsOneWidget);
      expect(stack.keys, const [Home(), Product(7)]);
    });
  });

  group('per-destination pages via NavEntries', () {
    testWidgets('a registered page presents as a dialog, decorated', (
      tester,
    ) async {
      final stack = NavStack<K>.of(const Home());
      addTearDown(stack.dispose);
      final decorated = <Type>[];

      await tester.pumpWidget(
        MaterialApp(
          home: NavDisplay<K>(
            stack: stack,
            entries: buildEntries(),
            decorators: [
              NavEntryDecorator<K>(
                decorate: (context, key, child) {
                  decorated.add(key.runtimeType);
                  return child;
                },
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      stack.push(const Confirm());
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('confirm-content'), findsOneWidget);
      expect(decorated, contains(Confirm), reason: 'decorators still apply');
      // The screen under the dialog is still mounted.
      expect(find.text('home-screen'), findsOneWidget);

      // Back dismisses the dialog like any route, and the list follows.
      stack.pop();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(stack.keys, const [Home()]);
    });
  });

  group('NavDisplay memoization', () {
    testWidgets('pages survive parent rebuilds (entries + tear-off)', (
      tester,
    ) async {
      final stack = NavStack<K>.of(const Home());
      addTearDown(stack.dispose);
      var builds = 0;
      final entries = NavEntries<K>()
        ..on<Home>((context, key) {
          builds++;
          return const Text('home-screen');
        });
      late StateSetter rebuildParent;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuildParent = setState;
              // A fresh `entries.call` tear-off every build — the README way.
              return NavDisplay<K>(stack: stack, builder: entries.call);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(builds, 1);

      rebuildParent(() {});
      await tester.pumpAndSettle();
      rebuildParent(() {});
      await tester.pumpAndSettle();
      expect(builds, 1, reason: 'equal tear-offs must keep the page memo');
    });

    testWidgets('onRemoved still fires after the builder function changes', (
      tester,
    ) async {
      final stack = NavStack<K>.of(const Home())..push(const Product(1));
      addTearDown(stack.dispose);
      final removed = <Type>[];
      final decorators = [
        NavEntryDecorator<K>(onRemoved: (key) => removed.add(key.runtimeType)),
      ];
      Widget screenA(BuildContext context, K key) => const Text('a');
      Widget screenB(BuildContext context, K key) => const Text('b');

      await tester.pumpWidget(
        MaterialApp(
          home: NavDisplay<K>(
            stack: stack,
            builder: screenA,
            decorators: decorators,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        MaterialApp(
          home: NavDisplay<K>(
            stack: stack,
            builder: screenB, // genuinely different function
            decorators: decorators,
          ),
        ),
      );
      await tester.pumpAndSettle();

      stack.pop();
      await tester.pumpAndSettle();
      expect(removed, [Product]);
    });
  });

  group('full-stack restoration', () {
    testWidgets('the whole typed stack survives restart via the links table', (
      tester,
    ) async {
      await tester.pumpWidget(const _RestorationHarness());
      await tester.pumpAndSettle();
      expect(find.text('home-screen'), findsOneWidget);

      final state = tester.state<_RestorationHarnessState>(
        find.byType(_RestorationHarness),
      );
      state.stack
        ..push(const Product(5))
        ..push(const Profile());
      await tester.pumpAndSettle();
      expect(find.text('profile-screen'), findsOneWidget);

      await tester.restartAndRestore();
      await tester.pumpAndSettle(); // restored keys apply after the frame
      final restored = tester.state<_RestorationHarnessState>(
        find.byType(_RestorationHarness),
      );
      expect(restored.stack.keys, const [Home(), Product(5), Profile()]);
      expect(find.text('profile-screen'), findsOneWidget);
      // The full history is back: popping lands on the product, not home.
      restored.stack.pop();
      await tester.pumpAndSettle();
      expect(find.text('product-5'), findsOneWidget);
    });
  });

  group('BackStackTabsApp', () {
    Future<(_TabsHarnessState, WidgetTester)> pumpTabs(
      WidgetTester tester, {
      StreamController<Uri>? links,
    }) async {
      await tester.pumpWidget(_TabsHarness(linkStream: links?.stream));
      await tester.pumpAndSettle();
      final state = tester.state<_TabsHarnessState>(find.byType(_TabsHarness));
      return (state, tester);
    }

    testWidgets('renders the bar, switches tabs, keeps per-tab history', (
      tester,
    ) async {
      final (state, _) = await pumpTabs(tester);
      expect(find.text('home-screen'), findsOneWidget);

      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(find.text('profile-screen'), findsOneWidget);

      // Push into the profile tab, switch away and back: history preserved.
      state.tabs[1].push(const Product(3));
      await tester.pumpAndSettle();
      expect(find.text('product-3'), findsOneWidget);

      await tester.tap(find.text('Feed'));
      await tester.pumpAndSettle();
      expect(find.text('home-screen'), findsOneWidget);

      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(find.text('product-3'), findsOneWidget);

      // Re-tapping the active tab pops it to its root.
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(find.text('profile-screen'), findsOneWidget);
      expect(state.tabs[1].length, 1);
    });

    testWidgets('links land in the right tab, inferred from the root', (
      tester,
    ) async {
      final linkController = StreamController<Uri>();
      addTearDown(linkController.close);
      final (state, _) = await pumpTabs(tester, links: linkController);

      // '/profile' decodes to [Profile()] whose root matches tab 1.
      linkController.add(Uri.parse('/profile'));
      await tester.pumpAndSettle();
      expect(find.text('profile-screen'), findsOneWidget);

      // '/products/8' decodes to [Home(), Product(8)] → tab 0, deep stack.
      linkController.add(Uri.parse('/products/8'));
      await tester.pumpAndSettle();
      expect(find.text('product-8'), findsOneWidget);
      expect(state.tabs[0].keys, const [Home(), Product(8)]);
    });
  });

  group('MultiNavStackRouterDelegate hardening', () {
    test('an out-of-range tab falls back instead of dropping the link', () {
      final host = MultiNavStack<K>([
        NavStack<K>.of(const Home()),
        NavStack<K>.of(const Profile()),
      ]);
      addTearDown(host.dispose);
      final delegate = MultiNavStackRouterDelegate<K>(
        host: host,
        codec: MultiNavStackCodec<K>.of(
          encode: (tab, stack) => Uri(path: '/'),
          decode: (uri) => MultiNavLocation(99, const [Home()]),
          fallback: const MultiNavLocation(1, [Profile(), Product(1)]),
        ),
        builder: (context, key) => const SizedBox(),
      );
      addTearDown(delegate.dispose);

      delegate.handleLink(Uri.parse('/whatever'));
      expect(host.index, 1);
      expect(host.active.keys, const [Profile(), Product(1)]);
    });
  });

  group('round-trip drift validator', () {
    test('a codec whose directions disagree is reported in debug', () {
      final stack = NavStack<K>.of(const Home());
      addTearDown(stack.dispose);
      final delegate = NavStackRouterDelegate<K>(
        stack: stack,
        codec: NavStackCodec<K>.of(
          // encode says '/a', but decoding '/a' re-encodes to '/a?drifted=1'.
          encode: (keys) =>
              keys.last is Product ? Uri.parse('/a?drifted=1') : Uri.parse('/a'),
          decode: (uri) => const [Home(), Product(1)],
        ),
        builder: (context, key) => const SizedBox(),
      );
      addTearDown(delegate.dispose);

      final reports = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reports.add;
      try {
        delegate.currentConfiguration;
      } finally {
        FlutterError.onError = previous;
      }
      expect(reports, hasLength(1));
      expect(reports.single.exception.toString(), contains('round-trip drift'));
    });

    test('a consistent codec reports nothing', () {
      final stack = NavStack<K>.of(const Home());
      addTearDown(stack.dispose);
      final delegate = NavStackRouterDelegate<K>(
        stack: stack,
        codec: buildLinks(),
        builder: (context, key) => const SizedBox(),
      );
      addTearDown(delegate.dispose);

      final reports = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reports.add;
      try {
        delegate.currentConfiguration;
        stack.push(const Product(2));
        delegate.currentConfiguration;
      } finally {
        FlutterError.onError = previous;
      }
      expect(reports, isEmpty);
    });
  });
}

/// Owns its stack in State so `restartAndRestore` genuinely recreates it —
/// proving the restored keys came from the restoration bucket, not memory.
class _RestorationHarness extends StatefulWidget {
  const _RestorationHarness();

  @override
  State<_RestorationHarness> createState() => _RestorationHarnessState();
}

class _RestorationHarnessState extends State<_RestorationHarness> {
  final NavStack<K> stack = NavStack<K>.of(const Home());

  @override
  void dispose() {
    stack.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BackStackApp<K>(
      stack: stack,
      entries: buildEntries(),
      links: buildLinks(),
    );
  }
}

class _TabsHarness extends StatefulWidget {
  const _TabsHarness({this.linkStream});

  final Stream<Uri>? linkStream;

  @override
  State<_TabsHarness> createState() => _TabsHarnessState();
}

class _TabsHarnessState extends State<_TabsHarness> {
  final List<NavStack<K>> tabs = [
    NavStack<K>.of(const Home()),
    NavStack<K>.of(const Profile()),
  ];

  @override
  Widget build(BuildContext context) {
    return BackStackTabsApp<K>(
      tabs: tabs,
      entries: buildEntries(),
      links: buildLinks(),
      linkStream: widget.linkStream,
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home), label: 'Feed'),
        NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
      ],
    );
  }
}
