import 'package:back_stack/back_stack.dart';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AsyncRedirect — loop-proof ASYNC auth gating.
//
//   • Navigating to a gated destination (Admin) holds it while an async check
//     runs; gate.resolving drives a loading overlay.
//   • The check either allows it (stay) or denies it (bounce to Login) — once,
//     cached per destination, so it can't loop.
//   • Toggle "signed in" and hit Admin again: invalidate() forces a re-check.
// ─────────────────────────────────────────────────────────────────────────────

sealed class AppKey extends NavKey with EquatableNavKey {
  const AppKey();
}

class Home extends AppKey {
  const Home();
  @override
  List<Object?> get props => const [];
}

class Admin extends AppKey {
  const Admin();
  @override
  List<Object?> get props => const [];
}

class Login extends AppKey {
  const Login();
  @override
  List<Object?> get props => const [];
}

/// Stand-in for your session/auth service.
final _session = ValueNotifier<bool>(false); // signed in?

void main() => runApp(const GuardedDemo());

class GuardedDemo extends StatefulWidget {
  const GuardedDemo({super.key});
  @override
  State<GuardedDemo> createState() => _GuardedDemoState();
}

class _GuardedDemoState extends State<GuardedDemo> {
  final stack = NavStack<AppKey>.of(const Home());
  late final gate = AsyncRedirect<AppKey>(
    check: (proposed) async {
      // Pretend this is a network permission check.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (proposed.any((k) => k is Admin) && !_session.value) {
        return [const Login()]; // deny
      }
      return null; // allow
    },
  );

  @override
  void initState() {
    super.initState();
    stack
      ..redirect = gate.call
      ..refreshListenable = gate;
  }

  @override
  void dispose() {
    stack.dispose();
    gate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'back_stack — async gating',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF4F46E5),
        useMaterial3: true,
      ),
      home: Stack(
        children: [
          NavDisplay<AppKey>(
            stack: stack,
            builder: (context, key) => switch (key) {
              Home() => HomeScreen(gate: gate),
              Admin() => const AdminScreen(),
              Login() => const LoginScreen(),
            },
          ),
          // A loading scrim while any gate check is in flight.
          ValueListenableBuilder<bool>(
            valueListenable: gate.resolving,
            builder: (context, busy, _) => busy
                ? const ColoredBox(
                    color: Color(0x66000000),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.gate});
  final AsyncRedirect<AppKey> gate;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: _session,
              builder: (context, signedIn, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(signedIn ? 'Signed in ✅' : 'Signed out ❌'),
                  TextButton(
                    onPressed: () {
                      _session.value = !_session.value;
                      gate.invalidate(); // decision changed → re-check next time
                    },
                    child: Text(signedIn ? 'Sign out' : 'Sign in'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () =>
                  BackStack.of<AppKey>(context).push(const Admin()),
              child: const Text('Open Admin (gated)'),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Admin')),
    body: const Center(child: Text('Access granted 🎉')),
  );
}

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Login')),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('You were bounced here by the gate.'),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              _session.value = true;
              BackStack.of<AppKey>(context).replaceAll([const Home()]);
            },
            child: const Text('Sign in & go home'),
          ),
        ],
      ),
    ),
  );
}
