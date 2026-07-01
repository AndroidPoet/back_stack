import 'package:back_stack/back_stack.dart';
import 'package:flutter/material.dart';

import 'app_key.dart';
import 'home_feature.dart';
import 'product_feature.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The simplest multi-file setup: no switch, no sealed type — plus deep links.
//
// Each feature file (home_feature.dart, product_feature.dart) owns its own
// destination + screen + a register function. The app just collects them into
// one NavEntries table. Adding a screen = a new file + one register call.
//
// BackStackApp bundles all the Router wiring: you write ONE function, onLink,
// mapping an incoming URL to the stack. Try `/product/7` as a deep link.
//
// Run:  cd example && flutter run -t lib/multi_file/main.dart
// ─────────────────────────────────────────────────────────────────────────────

NavEntries<AppKey> buildEntries() {
  final entries = NavEntries<AppKey>();
  registerHome(entries);
  registerProduct(entries);
  return entries;
}

void main() => runApp(const MultiFileApp());

class MultiFileApp extends StatefulWidget {
  const MultiFileApp({super.key});
  @override
  State<MultiFileApp> createState() => _MultiFileAppState();
}

class _MultiFileAppState extends State<MultiFileApp> {
  final stack = NavStack<AppKey>.of(const Home());
  final entries = buildEntries();

  @override
  void dispose() {
    stack.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BackStackApp<AppKey>(
      stack: stack,
      builder: entries.call, // the map is the whole routing table
      title: 'back_stack — multi-file',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF4F46E5),
        useMaterial3: true,
      ),
      // Deep links: one function from URL → stack. `/product/7` lands you on the
      // product with Home underneath, so Back still works.
      onLink: (uri) {
        final seg = uri.pathSegments;
        if (seg.length == 2 && seg.first == 'product') {
          return [const Home(), Product(int.parse(seg[1]))];
        }
        return [const Home()];
      },
    );
  }
}
