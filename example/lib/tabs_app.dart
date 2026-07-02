// The one-widget tabbed app: bottom navigation with a live back stack per
// tab, wired internally by BackStackTabsApp. Compare with tabs.dart, which
// builds the same shape by hand (MultiNavStack + MultiNavDisplay) for full
// control.
//
//   flutter run example/lib/tabs_app.dart
import 'package:back_stack/back_stack.dart';
import 'package:flutter/material.dart';

sealed class AppKey extends NavKey with EquatableNavKey {
  const AppKey();
}

class Feed extends AppKey {
  const Feed();
  @override
  List<Object?> get props => const [];
}

class Story extends AppKey {
  const Story(this.id);
  final int id;
  @override
  List<Object?> get props => [id];
}

class Profile extends AppKey {
  const Profile();
  @override
  List<Object?> get props => const [];
}

// One table: deep links land in the right tab (inferred from the decoded
// stack's root), the address bar follows on web, and every tab's stack —
// plus which tab was active — survives process death. Nothing else to wire.
final links = NavLinks<AppKey>()
  ..on<Feed>('/', decode: (m) => const Feed())
  ..on<Story>(
    '/story/:id',
    decode: (m) => Story(m.integer('id')!),
    encode: (key) => {'id': key.id},
    parents: (key) => const [Feed()],
  )
  ..on<Profile>('/profile', decode: (m) => const Profile());

final entries = NavEntries<AppKey>()
  ..on<Feed>((context, key) => const FeedScreen())
  ..on<Story>((context, key) => StoryScreen(id: key.id))
  ..on<Profile>((context, key) => const ProfileScreen());

void main() {
  runApp(
    BackStackTabsApp<AppKey>(
      tabs: [
        NavStack<AppKey>.of(const Feed()),
        NavStack<AppKey>.of(const Profile()),
      ],
      entries: entries,
      links: links,
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Feed'),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          label: 'Profile',
        ),
      ],
      title: 'tabs, one widget',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF4F46E5)),
    ),
  );
}

class FeedScreen extends StatelessWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Feed')),
      body: ListView(
        children: [
          for (var id = 1; id <= 20; id++)
            ListTile(
              leading: CircleAvatar(child: Text('$id')),
              title: Text('Story $id'),
              // Push into THIS tab's stack; switching tabs keeps it alive,
              // re-tapping the Feed destination pops back to this list.
              onTap: () => BackStack.of<AppKey>(context).push(Story(id)),
            ),
        ],
      ),
    );
  }
}

class StoryScreen extends StatelessWidget {
  const StoryScreen({super.key, required this.id});
  final int id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Story $id')),
      body: Center(
        child: Text('#$id', style: Theme.of(context).textTheme.displayLarge),
      ),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: Center(
        // Switch tabs from anywhere — the host is one lookup away.
        child: FilledButton(
          onPressed: () => MultiBackStack.of<AppKey>(context).select(0),
          child: const Text('Go to Feed'),
        ),
      ),
    );
  }
}
