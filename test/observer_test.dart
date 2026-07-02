import 'package:back_stack/back_stack.dart';
import 'package:flutter_test/flutter_test.dart';

sealed class K extends NavKey {
  const K();
}

class Home extends K {
  const Home();
}

class Product extends K {
  const Product(this.id);
  final int id;
}

class Cart extends K {
  const Cart();
}

void main() {
  test('reports pushes, pops and screen views in your key type', () {
    final screens = <K>[];
    final pushed = <K>[];
    final popped = <K>[];
    final stack = NavStack<K>.of(const Home());
    addTearDown(stack.dispose);

    final obs = NavStackObserver<K>(
      stack,
      onScreen: screens.add,
      onPush: pushed.add,
      onPop: popped.add,
    );
    addTearDown(obs.dispose);

    // Initial screen view fired on construction.
    expect(screens, [const Home()]);

    stack.push(const Product(7));
    expect(pushed.last, const Product(7));
    expect((pushed.last as Product).id, 7); // events carry the typed key
    expect(screens.last, const Product(7));

    stack.pop();
    expect(popped.last, const Product(7));
    expect(screens.last, const Home());
  });

  test('replaceAll reports each added and removed screen once', () {
    final pushed = <K>[];
    final popped = <K>[];
    final stack = NavStack<K>.of(const Home())..push(const Product(1));
    addTearDown(stack.dispose);

    final obs = NavStackObserver<K>(
      stack,
      onPush: pushed.add,
      onPop: popped.add,
      emitInitial: false,
    );
    addTearDown(obs.dispose);

    // Home is reconciled (kept), Product(1) leaves, Cart is added.
    stack.replaceAll([const Home(), const Cart()]);
    expect(pushed, [const Cart()]);
    expect(popped, [const Product(1)]);
  });

  test('dispose stops the callbacks', () {
    final screens = <K>[];
    final stack = NavStack<K>.of(const Home());
    addTearDown(stack.dispose);

    NavStackObserver<K>(stack, onScreen: screens.add).dispose();
    stack.push(const Cart());
    expect(screens, [const Home()]); // only the initial one
  });
}
