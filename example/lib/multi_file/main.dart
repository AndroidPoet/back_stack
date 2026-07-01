import 'package:back_stack/back_stack.dart';
import 'package:flutter/material.dart';

import 'app_key.dart';
import 'home_feature.dart';
import 'product_feature.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The simplest multi-file setup: no switch, no sealed type.
//
// Each feature file (home_feature.dart, product_feature.dart) owns its own
// destination + screen + a register function. The app just collects them into
// one NavEntries table. Adding a screen = a new file + one register call.
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
    return MaterialApp(
      title: 'back_stack — multi-file',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF4F46E5),
        useMaterial3: true,
      ),
      // The map is the whole routing table.
      home: NavDisplay<AppKey>(stack: stack, builder: entries.call),
    );
  }
}
