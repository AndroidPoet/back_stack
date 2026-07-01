import 'package:back_stack/back_stack.dart';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NavEntries + NavEntryDecorator — the modular builder and cross-cutting hooks.
//
//   • NavEntries registers each destination's screen with `..on<T>()`, so a big
//     app splits its `switch` across feature files instead of one giant block.
//   • NavEntryDecorator wraps every screen (a DI scope, a provider, tracing) and
//     calls `onRemoved` when an entry leaves the stack — the place to tear down
//     something scoped to a destination that `State.dispose` can't reach.
// ─────────────────────────────────────────────────────────────────────────────

sealed class Screen extends NavKey {
  const Screen();
}

class Home extends Screen {
  const Home();
}

class Detail extends Screen {
  const Detail(this.id);
  final int id;
}

/// Stand-in for a per-destination scope (a Bloc, a controller, a DI container).
/// We create one when a Detail screen is decorated and dispose it in onRemoved.
final _openScopes = <int>{};

void main() => runApp(const EntriesDemo());

class EntriesDemo extends StatefulWidget {
  const EntriesDemo({super.key});
  @override
  State<EntriesDemo> createState() => _EntriesDemoState();
}

class _EntriesDemoState extends State<EntriesDemo> {
  final stack = NavStack<Screen>.of(const Home());

  // Register destinations as a map. In a real app each feature file adds its
  // own `..on<T>()` to a shared NavEntries — no central switch to edit.
  final entries = NavEntries<Screen>()
    ..on<Home>((context, key) => const HomePane())
    ..on<Detail>((context, key) => DetailPane(id: key.id));

  @override
  void dispose() {
    stack.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'back_stack — entries & decorators',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF4F46E5), useMaterial3: true),
      home: NavDisplay<Screen>(
        stack: stack,
        // The whole app's routing table: a map, not a switch.
        builder: entries.call,
        decorators: [
          NavEntryDecorator<Screen>(
            // Runs on every build — wrap the screen in whatever scope it needs.
            decorate: (context, key, child) {
              if (key is Detail) _openScopes.add(key.id);
              return child;
            },
            // Fires once when the entry is popped, replaced, or disposed.
            onRemoved: (key) {
              if (key is Detail) {
                _openScopes.remove(key.id);
                debugPrint('disposed scope for Detail(${key.id}) — '
                    'open scopes: $_openScopes');
              }
            },
          ),
        ],
      ),
    );
  }
}

class HomePane extends StatelessWidget {
  const HomePane({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: ListView(
        children: [
          for (var i = 1; i <= 6; i++)
            ListTile(
              leading: CircleAvatar(child: Text('$i')),
              title: Text('Open Detail #$i'),
              subtitle: const Text('push(Detail(i)) — a scope opens'),
              onTap: () => BackStack.of<Screen>(context).push(Detail(i)),
            ),
        ],
      ),
    );
  }
}

class DetailPane extends StatelessWidget {
  const DetailPane({super.key, required this.id});
  final int id;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Detail #$id')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'A scope opened for this destination when it was decorated. '
                'Pop this screen and watch the console — onRemoved tears it '
                'down exactly once.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.tonal(
                onPressed: () => BackStack.of<Screen>(context).pop(),
                child: const Text('Pop (fires onRemoved)'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
