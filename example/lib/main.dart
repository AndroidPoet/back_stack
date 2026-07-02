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

// ── 2. The URL table: each destination declared ONCE, both directions.
//    Deep links, the web address bar, browser back/forward, share links and
//    state restoration all derive from this one table — they can't drift apart.
//    `parents:` is the layer-vs-replace choice: Back from a deep-linked
//    product goes to the catalog, not out of the app.
final links = NavLinks<AppKey>()
  ..on<Login>('/', decode: (m) => const Login())
  ..on<Catalog>('/catalog', decode: (m) => const Catalog())
  ..on<Product>(
    '/product/:name/:price',
    decode: (m) => Product(m.str('name')!, m.integer('price')!),
    encode: (key) => {'name': key.name, 'price': key.price},
    parents: (key) => const [Catalog()],
  )
  ..on<Cart>(
    '/cart',
    decode: (m) => const Cart(),
    parents: (key) => const [Catalog()],
  );

void main() => runApp(const ShopApp());

class ShopApp extends StatefulWidget {
  const ShopApp({super.key});
  @override
  State<ShopApp> createState() => ShopAppState();
}

class ShopAppState extends State<ShopApp> {
  // ── 3. The back stack: a list you own. Start at Login.
  final stack = NavStack<AppKey>.of(const Login());

  // ── 4. One line per screen. A modular alternative to one big `switch`:
  //    each feature file can add its own `..on<T>()` to a shared instance.
  //    (For a small app a `switch` builder is just as good — see pokedex.dart.)
  final entries = NavEntries<AppKey>()
    ..on<Login>((context, key) => const LoginScreen())
    ..on<Catalog>((context, key) => const CatalogScreen())
    ..on<Product>(
      (context, key) => ProductScreen(name: key.name, price: key.price),
    )
    ..on<Cart>((context, key) => const CartScreen());

  //    NavEntryDecorator — wrap every screen and get a callback when an entry
  //    leaves the stack. Here we just log each visit and its teardown; in a
  //    real app `decorate` is where a DI scope / provider goes and `onRemoved`
  //    is where you dispose the thing you scoped to that screen.
  final analytics = NavEntryDecorator<AppKey>(
    decorate: (context, key, child) {
      debugPrint('screen_view: ${key.runtimeType}');
      return child;
    },
    onRemoved: (key) =>
        debugPrint('left: ${key.runtimeType} — tear down its scope'),
  );

  @override
  void dispose() {
    stack.dispose(); // you created it, you dispose it
    super.dispose();
  }

  // ── 5. One widget. Deep links, web URLs, OS/browser back, and full-stack
  //    state restoration are wired internally from `links`. Screens reach the
  //    stack via BackStack.of<AppKey>(context) — no passing it down.
  @override
  Widget build(BuildContext context) {
    return BackStackApp<AppKey>(
      stack: stack,
      entries: entries,
      links: links,
      decorators: [analytics],
      title: 'back_stack demo',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF4F46E5), // indigo, calm premium tone
        useMaterial3: true,
      ),
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

// A stable colour + glyph per product, so the shared element has something
// recognisable to fly. Just demo data — nothing back_stack-specific.
({Color color, IconData icon}) _badge(String name) => switch (name) {
  'Coffee' => (color: const Color(0xFF8D6E63), icon: Icons.coffee),
  'Notebook' => (color: const Color(0xFF26A69A), icon: Icons.menu_book),
  _ => (color: const Color(0xFF5C6BC0), icon: Icons.headphones),
};

/// The shared element. The *same* `Hero` tag in the catalog tile and on the
/// product screen is all Flutter needs to fly it between the two routes.
/// Because `NavDisplay` renders through the real Pages API on a `Navigator`,
/// `Hero` works with zero back_stack support — exactly like Navigator 1.0.
class ProductBadge extends StatelessWidget {
  const ProductBadge({super.key, required this.name, this.size = 40});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final badge = _badge(name);
    return Hero(
      tag: 'product-$name',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: badge.color,
          borderRadius: BorderRadius.circular(size / 4),
        ),
        child: Icon(badge.icon, color: Colors.white, size: size * 0.55),
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
              leading: ProductBadge(name: name),
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
            // Same Hero tag as the catalog tile → the badge flies in.
            ProductBadge(name: name, size: 120),
            const SizedBox(height: 24),
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
