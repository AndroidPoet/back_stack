import 'package:back_stack/back_stack.dart';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Material motion — the shared-axis and fade-through transitions on TransitionPage.
//
// A destination's transition is just the Page you return from pageBuilder. Pick
// the motion that matches the relationship between screens:
//   • sharedAxisHorizontal — a step forward among peers (a wizard/pager)
//   • sharedAxisScaled (Z)  — a step into a hierarchy (list → detail)
//   • fadeThrough           — switching between unrelated destinations
// All are dependency-free and animate the outgoing screen too.
// ─────────────────────────────────────────────────────────────────────────────

sealed class AppKey extends NavKey {
  const AppKey();
}

class Step1 extends AppKey {
  const Step1();
}

class Step2 extends AppKey {
  const Step2();
}

class Detail extends AppKey {
  const Detail(this.motion);
  final String motion;
}

void main() => runApp(const MotionDemo());

class MotionDemo extends StatefulWidget {
  const MotionDemo({super.key});
  @override
  State<MotionDemo> createState() => _MotionDemoState();
}

class _MotionDemoState extends State<MotionDemo> {
  final stack = NavStack<AppKey>.of(const Step1());

  @override
  void dispose() {
    stack.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'back_stack — Material motion',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF4F46E5),
        useMaterial3: true,
      ),
      home: NavDisplay<AppKey>(
        stack: stack,
        builder: (context, key) => switch (key) {
          Step1() => const _Page(title: 'Step 1', color: Color(0xFFEEF2FF)),
          Step2() => const _Page(title: 'Step 2', color: Color(0xFFE0E7FF)),
          Detail(:final motion) => _Page(
            title: 'Detail ($motion)',
            color: const Color(0xFFDDD6FE),
          ),
        },
        // The motion is chosen per destination here.
        pageBuilder: (context, key, pageKey) {
          final child = switch (key) {
            Step1() => const _Page(title: 'Step 1', color: Color(0xFFEEF2FF)),
            Step2() => const _Page(title: 'Step 2', color: Color(0xFFE0E7FF)),
            Detail(:final motion) => _Page(
              title: 'Detail ($motion)',
              color: const Color(0xFFDDD6FE),
            ),
          };
          return switch (key) {
            // Peer step forward → shared axis X.
            Step2() => TransitionPage<void>.sharedAxisHorizontal(
              key: pageKey,
              child: child,
            ),
            // Into a hierarchy → shared axis Z (scaled).
            Detail() => TransitionPage<void>.sharedAxisScaled(
              key: pageKey,
              child: child,
            ),
            _ => MaterialPage<void>(key: pageKey, child: child),
          };
        },
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.title, required this.color});
  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final stack = BackStack.of<AppKey>(context);
    return Scaffold(
      backgroundColor: color,
      appBar: AppBar(title: Text(title), backgroundColor: color),
      body: Center(
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            FilledButton(
              onPressed: () => stack.push(const Step2()),
              child: const Text('Next step → (shared axis X)'),
            ),
            FilledButton.tonal(
              onPressed: () => stack.push(const Detail('shared axis Z')),
              child: const Text('Into detail (shared axis Z)'),
            ),
            if (stack.canPop)
              TextButton(onPressed: stack.pop, child: const Text('Back')),
          ],
        ),
      ),
    );
  }
}
