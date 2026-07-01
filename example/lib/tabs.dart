import 'package:back_stack/back_stack.dart';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MultiNavStack — a bottom nav bar with PERSISTENT per-tab history.
//
//   • Each tab owns its own NavStack, so pushing deep in one tab and switching
//     away leaves that history intact — switch back and you're where you left.
//   • MultiNavDisplay keeps every tab mounted (State survives switches) and
//     routes system back to the active tab, then to the first tab, then out.
//   • Re-tapping the active tab pops it to its root — the familiar gesture.
//   • Any screen reaches the host via MultiBackStack.of(context) to switch tabs.
// ─────────────────────────────────────────────────────────────────────────────

sealed class TabKey extends NavKey {
  const TabKey();
}

class Feed extends TabKey {
  const Feed();
}

class Post extends TabKey {
  const Post(this.id);
  final int id;
}

class Search extends TabKey {
  const Search();
}

class Profile extends TabKey {
  const Profile();
}

void main() => runApp(const TabsDemo());

class TabsDemo extends StatefulWidget {
  const TabsDemo({super.key});
  @override
  State<TabsDemo> createState() => _TabsDemoState();
}

class _TabsDemoState extends State<TabsDemo> {
  // One stack per tab. Each starts at that tab's root destination.
  final host = MultiNavStack<TabKey>([
    NavStack.of(const Feed()),
    NavStack.of(const Search()),
    NavStack.of(const Profile()),
  ]);

  @override
  void dispose() {
    host.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'back_stack — per-tab history',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF4F46E5),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: MultiNavDisplay<TabKey>(
          host: host,
          builder: (context, key) => switch (key) {
            Feed() => const FeedScreen(),
            Post(:final id) => PostScreen(id: id),
            Search() => const SearchScreen(),
            Profile() => const ProfileScreen(),
          },
        ),
        // Drive the bar from host.index / host.select — it rebuilds because
        // MultiNavDisplay listens to the host.
        bottomNavigationBar: ListenableBuilder(
          listenable: host,
          builder: (context, _) => NavigationBar(
            selectedIndex: host.index,
            onDestinationSelected: host.select,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dynamic_feed),
                label: 'Feed',
              ),
              NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
              NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
            ],
          ),
        ),
      ),
    );
  }
}

class FeedScreen extends StatelessWidget {
  const FeedScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Feed')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Open a post, then switch tabs and come back — this tab keeps its '
              'own history. System back pops within the tab first.',
            ),
          ),
          for (var i = 1; i <= 8; i++)
            ListTile(
              leading: CircleAvatar(child: Text('$i')),
              title: Text('Post #$i'),
              onTap: () => BackStack.of<TabKey>(context).push(Post(i)),
            ),
        ],
      ),
    );
  }
}

class PostScreen extends StatelessWidget {
  const PostScreen({super.key, required this.id});
  final int id;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Post #$id')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'This is post #$id.',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 24),
              // Reach the tab host from a deep screen to jump tabs — no wiring.
              FilledButton.tonal(
                onPressed: () => MultiBackStack.of<TabKey>(context).select(2),
                child: const Text('Jump to Profile tab'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Search')),
    body: const Center(child: Text('Search tab — its own independent stack.')),
  );
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Profile')),
    body: const Center(child: Text('Profile tab — its own independent stack.')),
  );
}
