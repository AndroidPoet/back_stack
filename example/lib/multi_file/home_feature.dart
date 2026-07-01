import 'package:back_stack/back_stack.dart';
import 'package:flutter/material.dart';

import 'app_key.dart';
import 'product_feature.dart';

/// This feature's destination.
class Home extends AppKey {
  const Home();
}

/// Register this feature's screens into the shared table.
void registerHome(NavEntries<AppKey> entries) {
  entries.on<Home>((context, key) => const HomeScreen());
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: Center(
        child: FilledButton(
          // Navigate by pushing a typed destination onto the list.
          onPressed: () => BackStack.of<AppKey>(context).push(const Product(42)),
          child: const Text('Open product 42'),
        ),
      ),
    );
  }
}
