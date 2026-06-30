import 'package:flutter/material.dart';
import 'package:back_stack/back_stack.dart';

// ─────────────────────────────────────────────────────────────────────────────
// THE ENTIRE NAVIGATION MODEL. This is it.
//
//   • Destinations are plain typed classes (compiler-checked args, no codegen).
//   • The back stack is a List you own.
//   • push() adds, pop() removes, the UI follows.
//   • One stack renders as a two-pane list-detail on a wide window and collapses
//     to a normal push/pop stack on a narrow one — you write it once.
// ─────────────────────────────────────────────────────────────────────────────

sealed class Screen extends NavKey {
  const Screen();
}

class Inbox extends Screen {
  const Inbox();
}

class Mail extends Screen {
  const Mail(this.id);
  final int id;
}

void main() => runApp(const Demo());

class Demo extends StatefulWidget {
  const Demo({super.key});
  @override
  State<Demo> createState() => _DemoState();
}

class _DemoState extends State<Demo> {
  // 1. The stack. Start on the inbox.
  final stack = NavStack<Screen>.of(const Inbox());

  @override
  void dispose() {
    stack.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'back_stack showcase',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF4F46E5), // indigo
        useMaterial3: true,
      ),
      // 2. One adaptive display over the one stack. That's the whole app shell.
      home: NavListDetail<Screen>(
        stack: stack,
        isDetail: (key) => key is Mail,
        list: (context, key) => const InboxPane(),
        detail: (context, key) => MailPane(id: (key as Mail).id),
        placeholder: (context) => const _Placeholder(),
      ),
    );
  }
}

// ── The list pane / phone home screen ───────────────────────────────────────
class InboxPane extends StatelessWidget {
  const InboxPane({super.key});

  @override
  Widget build(BuildContext context) {
    final stack = BackStack.of<Screen>(context, listen: true);
    final openId = stack.current is Mail ? (stack.current as Mail).id : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Inbox')),
      body: ListView(
        children: [
          for (var i = 1; i <= 8; i++)
            ListTile(
              selected: i == openId,
              selectedTileColor: const Color(0x114F46E5),
              leading: CircleAvatar(child: Text('$i')),
              title: Text('Message #$i'),
              subtitle: const Text('Tap to open — push(Mail(i))'),
              // 3. Navigate = push a typed value onto the list.
              onTap: () => BackStack.of<Screen>(context).push(Mail(i)),
            ),
          const SizedBox(height: 12),
          const _StackInspector(),
        ],
      ),
    );
  }
}

// ── The detail pane / phone pushed screen ────────────────────────────────────
class MailPane extends StatelessWidget {
  const MailPane({super.key, required this.id});
  final int id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Message #$id'),
        // On a phone this is the pushed page, so a back arrow appears and the
        // system back works — same stack, both layouts.
        leading: BackStack.of<Screen>(context).canPop
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => BackStack.of<Screen>(context).pop(),
              )
            : null,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Subject line for message $id',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            const Text(
              'This pane is the same stack entry whether it sits beside the '
              'inbox on a wide window or as a pushed page on a phone. Resize '
              'the window and watch it move — the navigation code did not change.',
            ),
            const Spacer(),
            FilledButton.tonal(
              onPressed: () =>
                  BackStack.of<Screen>(context).push(Mail(id + 100)),
              child: const Text('Open a related message (push another)'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();
  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: Color(0xFFF6F6FB),
    child: Center(
      child: Text('Pick a message  ›', style: TextStyle(color: Colors.grey)),
    ),
  );
}

// Live proof the back stack is just observable data.
class _StackInspector extends StatelessWidget {
  const _StackInspector();
  @override
  Widget build(BuildContext context) {
    final stack = BackStack.of<Screen>(context, listen: true);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEEEEF6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'stack = [ ${stack.keys.map((k) => k is Mail ? 'Mail(${k.id})' : 'Inbox').join(', ')} ]',
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
    );
  }
}
