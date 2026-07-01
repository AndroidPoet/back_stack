import 'package:back_stack/back_stack.dart';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// pushForResult — await a value from a screen you pushed.
//
//   • `await stack.pushForResult<Color>(const Picker())` opens the picker and
//     suspends until it leaves the stack.
//   • The picker returns a value with `pop(color)`; that value completes the
//     future. Any other way off the stack (back gesture, replaceAll, dispose)
//     completes it with null — it never hangs.
//   • Make the picker pop the SAME type the caller awaits: pop takes Object?, so
//     a mismatched result throws when the future resolves, not at the pop site.
// ─────────────────────────────────────────────────────────────────────────────

sealed class Route extends NavKey {
  const Route();
}

class Home extends Route {
  const Home();
}

class Picker extends Route {
  const Picker();
}

void main() => runApp(const ResultsDemo());

class ResultsDemo extends StatefulWidget {
  const ResultsDemo({super.key});
  @override
  State<ResultsDemo> createState() => _ResultsDemoState();
}

class _ResultsDemoState extends State<ResultsDemo> {
  final stack = NavStack<Route>.of(const Home());

  @override
  void dispose() {
    stack.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'back_stack — results',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF4F46E5),
        useMaterial3: true,
      ),
      home: NavDisplay<Route>(
        stack: stack,
        builder: (context, key) => switch (key) {
          Home() => const HomeScreen(),
          Picker() => const PickerScreen(),
        },
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Color _picked = const Color(0xFF4F46E5);

  Future<void> _pick() async {
    // Open the picker and await what it pops. Null if it's dismissed instead.
    final result = await BackStack.of<Route>(
      context,
    ).pushForResult<Color>(const Picker());
    if (result != null) setState(() => _picked = result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Results')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 120, height: 120, color: _picked),
            const SizedBox(height: 24),
            FilledButton(onPressed: _pick, child: const Text('Pick a color')),
            const SizedBox(height: 8),
            const Text(
              'Dismiss the picker with back → result is null → no change.',
            ),
          ],
        ),
      ),
    );
  }
}

class PickerScreen extends StatelessWidget {
  const PickerScreen({super.key});

  static const _swatches = [
    Color(0xFF4F46E5),
    Color(0xFF0D9488),
    Color(0xFF2563EB),
    Color(0xFF7C3AED),
    Color(0xFFDB2777),
    Color(0xFFEA580C),
  ];

  @override
  Widget build(BuildContext context) {
    final stack = BackStack.of<Route>(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Pick a color')),
      body: GridView.count(
        crossAxisCount: 3,
        padding: const EdgeInsets.all(16),
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        children: [
          for (final c in _swatches)
            InkWell(
              // pop the chosen value — it completes the awaiting future above.
              onTap: () => stack.pop(c),
              child: Container(color: c),
            ),
        ],
      ),
    );
  }
}
