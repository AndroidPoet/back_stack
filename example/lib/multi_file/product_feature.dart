import 'package:back_stack/back_stack.dart';
import 'package:flutter/material.dart';

import 'app_key.dart';

/// This feature's destination — with a real, typed argument.
class Product extends AppKey {
  const Product(this.id);
  final int id;
}

/// Register this feature's screens into the shared table.
void registerProduct(NavEntries<AppKey> entries) {
  entries.on<Product>((context, key) => ProductScreen(id: key.id));
}

class ProductScreen extends StatelessWidget {
  const ProductScreen({super.key, required this.id});
  final int id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Product $id')),
      body: Center(
        child: FilledButton.tonal(
          onPressed: () => BackStack.of<AppKey>(context).pop(),
          child: const Text('Back'),
        ),
      ),
    );
  }
}
