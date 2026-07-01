import 'package:back_stack/back_stack.dart';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// A fuller demo of the 0.2.x additions:
//
//   • NavEntries — three "feature modules" each register their own destinations
//     into one shared map (registerDashboard / registerContent / registerSettings).
//     There is NO central switch; adding a screen is one `..on<T>()` line in the
//     feature that owns it.
//
//   • NavEntryDecorator — one decorator wraps EVERY screen with an instrumentation
//     overlay (without any screen knowing about it) and logs a teardown line when
//     a destination leaves the stack. That `onRemoved` hook is where a real app
//     disposes a Bloc / controller / DI scope tied to the destination.
//
// Run:  cd example && flutter run -t lib/modular_demo.dart
// ─────────────────────────────────────────────────────────────────────────────

// ── Destinations ─────────────────────────────────────────────────────────────
sealed class AppKey extends NavKey with EquatableNavKey {
  const AppKey();
}

class Dashboard extends AppKey {
  const Dashboard();
  @override
  List<Object?> get props => const [];
}

class Article extends AppKey {
  const Article(this.id);
  final int id;
  @override
  List<Object?> get props => [id];
}

class Profile extends AppKey {
  const Profile();
  @override
  List<Object?> get props => const [];
}

class Settings extends AppKey {
  const Settings();
  @override
  List<Object?> get props => const [];
}

// ── "Feature modules": each contributes its own entries to a shared registry.
//    In a real app these live in separate files/packages and never touch a
//    central switch.
void registerDashboard(NavEntries<AppKey> e) =>
    e.on<Dashboard>((context, key) => const DashboardScreen());

void registerContent(NavEntries<AppKey> e) => e
  ..on<Article>((context, key) => ArticleScreen(id: key.id))
  ..on<Profile>((context, key) => const ProfileScreen());

void registerSettings(NavEntries<AppKey> e) =>
    e.on<Settings>((context, key) => const SettingsScreen());

// ── A live teardown log so you can SEE onRemoved fire. Appended off-frame
//    because the decorator's onRemoved runs during the display's build.
final ValueNotifier<List<String>> teardownLog = ValueNotifier(const []);

void main() => runApp(const ModularDemo());

class ModularDemo extends StatefulWidget {
  const ModularDemo({super.key});
  @override
  State<ModularDemo> createState() => _ModularDemoState();
}

class _ModularDemoState extends State<ModularDemo> {
  final stack = NavStack<AppKey>.of(const Dashboard());

  // Compose the routing table from every feature module.
  final entries = _buildEntries();

  static NavEntries<AppKey> _buildEntries() {
    final e = NavEntries<AppKey>();
    registerDashboard(e);
    registerContent(e);
    registerSettings(e);
    return e;
  }

  // One decorator, applied to every screen.
  late final decorator = NavEntryDecorator<AppKey>(
    decorate: (context, key, child) => _Instrumented(label: _labelOf(key), child: child),
    onRemoved: (key) {
      // Defer the notifier write: onRemoved runs inside the display's build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        teardownLog.value = [
          '✗ disposed scope for ${_labelOf(key)}',
          ...teardownLog.value,
        ].take(4).toList();
      });
    },
  );

  @override
  void dispose() {
    stack.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'back_stack — modular demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF4F46E5), useMaterial3: true),
      home: NavDisplay<AppKey>(
        stack: stack,
        builder: entries.call, // the composed NavEntries map
        decorators: [decorator], // wraps every screen + logs teardown
      ),
    );
  }
}

String _labelOf(AppKey key) => switch (key) {
  Dashboard() => 'Dashboard',
  Article(:final id) => 'Article #$id',
  Profile() => 'Profile',
  Settings() => 'Settings',
};

// ── The cross-cutting wrapper the decorator injects onto every screen. No
//    screen below knows this is here — that's the point of a decorator.
class _Instrumented extends StatelessWidget {
  const _Instrumented({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: _OverlayCard(activeLabel: label),
        ),
      ],
    );
  }
}

class _OverlayCard extends StatelessWidget {
  const _OverlayCard({required this.activeLabel});
  final String activeLabel;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Card(
        color: const Color(0xF20E1330),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'decorator active on: $activeLabel',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
              ),
              const SizedBox(height: 6),
              ValueListenableBuilder<List<String>>(
                valueListenable: teardownLog,
                builder: (context, log, _) {
                  if (log.isEmpty) {
                    return const Text(
                      'onRemoved log: (pop a screen to see teardown)',
                      style: TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'monospace'),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in log)
                        Text(
                          line,
                          style: const TextStyle(color: Color(0xFF9DE7C0), fontSize: 11, fontFamily: 'monospace'),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Screens (none of them reference the decorator or the log) ────────────────
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final stack = BackStack.of<AppKey>(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          for (var i = 1; i <= 3; i++)
            ListTile(
              leading: CircleAvatar(child: Text('$i')),
              title: Text('Read article #$i'),
              subtitle: const Text('registered by the content module'),
              onTap: () => stack.push(Article(i)),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Profile'),
            onTap: () => stack.push(const Profile()),
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Settings'),
            onTap: () => stack.push(const Settings()),
          ),
        ],
      ),
    );
  }
}

class ArticleScreen extends StatelessWidget {
  const ArticleScreen({super.key, required this.id});
  final int id;
  @override
  Widget build(BuildContext context) {
    final stack = BackStack.of<AppKey>(context);
    return Scaffold(
      appBar: AppBar(title: Text('Article #$id')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Article #$id', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            const Text(
              'Pop this screen and watch the overlay: the decorator fires '
              'onRemoved for this exact destination — the hook where a real app '
              'disposes a Bloc or DI scope scoped to it.',
            ),
            const Spacer(),
            FilledButton.tonal(
              onPressed: () => stack.push(Article(id + 1)),
              child: const Text('Open the next article (push)'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: stack.pop,
              child: const Text('Pop (fires onRemoved)'),
            ),
          ],
        ),
      ),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Profile')),
    body: const Center(child: Text('👤', style: TextStyle(fontSize: 64))),
  );
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: const Center(child: Text('⚙️', style: TextStyle(fontSize: 64))),
  );
}
