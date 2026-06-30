import 'package:flutter/material.dart';
import 'package:back_stack/back_stack.dart';

// ── 1. Destinations: plain, typed Dart objects. This is your "routes" table.
//    Arguments are real fields — the compiler checks them. No `Object?`, no
//    string paths, no codegen. EquatableNavKey gives them value equality so a
//    deep-link re-decode reuses the live screen instead of rebuilding it.
sealed class AppKey extends NavKey with EquatableNavKey {
  const AppKey();
}

class Login extends AppKey {
  const Login();
  @override
  List<Object?> get props => const [];
}

class Catalog extends AppKey {
  const Catalog();
  @override
  List<Object?> get props => const [];
}

class Product extends AppKey {
  const Product(this.name, this.price);
  final String name;
  final int price;
  @override
  List<Object?> get props => [name, price];
}

class Cart extends AppKey {
  const Cart();
  @override
  List<Object?> get props => const [];
}

// ── The codec: stack ⇄ URL. The only thing you write to get web URL sync, deep
//    links, browser/OS back and restoration. The stack stays the source of truth.
class ShopCodec extends NavStackCodec<AppKey> {
  const ShopCodec();

  @override
  Uri encode(List<AppKey> stack) => switch (stack.last) {
    Login() => Uri(path: '/'),
    Catalog() => Uri(path: '/catalog'),
    Product(:final name, :final price) => Uri(path: '/product/$name/$price'),
    Cart() => Uri(path: '/cart'),
  };

  @override
  List<AppKey> decode(Uri uri) {
    final s = uri.pathSegments;
    if (s.isEmpty) return [const Login()];
    switch (s.first) {
      case 'catalog':
        return [const Catalog()];
      case 'cart':
        return [const Catalog(), const Cart()]; // layer Cart on Catalog
      case 'product':
        if (s.length == 3) {
          return [const Catalog(), Product(s[1], int.tryParse(s[2]) ?? 0)];
        }
    }
    return [const Login()];
  }
}

void main() => runApp(const ShopApp());

class ShopApp extends StatefulWidget {
  const ShopApp({super.key});
  @override
  State<ShopApp> createState() => ShopAppState();
}

class ShopAppState extends State<ShopApp> {
  // ── 2. The back stack: a list you own. Start at Login.
  final stack = NavStack<AppKey>.of(const Login());

  // ── 3. The delegate drives the platform Router from the stack: the browser
  //    URL updates as you navigate, and deep links / OS back flow back in.
  late final delegate = NavStackRouterDelegate<AppKey>(
    stack: stack,
    codec: const ShopCodec(),
    // Screens reach the stack via BackStack.of<AppKey>(context) — no passing it down.
    builder: (context, key) => switch (key) {
      Login() => const LoginScreen(),
      Catalog() => const CatalogScreen(),
      Product(:final name, :final price) => ProductScreen(
        name: name,
        price: price,
      ),
      Cart() => const CartScreen(),
    },
  );

  @override
  void dispose() {
    // You created them, so you dispose them.
    delegate.dispose();
    stack.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'back_stack demo',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF4F46E5), // indigo, calm premium tone
        useMaterial3: true,
      ),
      routerDelegate: delegate,
      routeInformationParser: const NavStackRouteInformationParser(),
      restorationScopeId: 'app', // survive process death
    );
  }
}

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Center(
        child: FilledButton(
          // After login, reset the flow. No "clear the stack" incantation —
          // just say what the stack should be now.
          onPressed: () =>
              BackStack.of<AppKey>(context).replaceAll([const Catalog()]),
          child: const Text('Log in'),
        ),
      ),
    );
  }
}

class CatalogScreen extends StatelessWidget {
  const CatalogScreen({super.key});

  static const _items = [('Coffee', 4), ('Notebook', 9), ('Headphones', 79)];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Catalog'),
        actions: [
          IconButton(
            icon: const Icon(Icons.shopping_cart_outlined),
            onPressed: () => BackStack.of<AppKey>(context).push(const Cart()),
          ),
        ],
      ),
      body: Column(
        children: [
          for (final (name, price) in _items)
            ListTile(
              title: Text(name),
              trailing: Text('\$$price'),
              // Push a typed destination. `name`/`price` are checked args.
              onTap: () =>
                  BackStack.of<AppKey>(context).push(Product(name, price)),
            ),
          const Spacer(),
          const StackInspector(),
        ],
      ),
    );
  }
}

class ProductScreen extends StatelessWidget {
  const ProductScreen({super.key, required this.name, required this.price});
  final String name;
  final int price;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('\$$price', style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => BackStack.of<AppKey>(context).push(const Cart()),
              child: const Text('Add to cart'),
            ),
            TextButton(
              // popUntil treats the stack as data: unwind to Catalog.
              onPressed: () =>
                  BackStack.of<AppKey>(context).popUntil((k) => k is Catalog),
              child: const Text('Back to catalog'),
            ),
          ],
        ),
      ),
    );
  }
}

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cart')),
      body: const Center(child: Text('🛒', style: TextStyle(fontSize: 64))),
    );
  }
}

/// Proof that the back stack is just observable data: with `listen: true` this
/// rebuilds live as you navigate, showing the exact list. Try that with go_router.
class StackInspector extends StatelessWidget {
  const StackInspector({super.key});

  @override
  Widget build(BuildContext context) {
    final stack = BackStack.of<AppKey>(context, listen: true);
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.all(12),
      child: Text(
        'back stack: ${stack.keys.map((k) => k.runtimeType).join(' › ')}',
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
    );
  }
}
