import 'dart:async';

import 'package:back_stack/back_stack.dart';
import 'package:flutter_test/flutter_test.dart';

class K extends NavKey {
  const K(this.name);
  final String name;
}

void main() {
  test('guard-vetoed pop: result future + return value behaviour', () async {
    final stack = NavStack<K>.of(const K('home'));

    // Push a result-awaiting screen.
    Object? received = 'UNSET';
    var completed = false;
    unawaited(
      stack.pushForResult<String>(const K('picker')).then((v) {
        received = v;
        completed = true;
      }),
    );
    await Future<void>.value();

    expect(stack.length, 2);

    // A general guard that vetoes ANY pop back to a 1-length stack.
    stack.guard = (proposed) => proposed.length >= 2;

    final popReturned = stack.pop('CHOSEN');
    await Future<void>.value();

    // A guard-vetoed pop must be a true no-op: it didn't happen, so pop()
    // reports false, the screen stays, and its result future stays open.
    expect(popReturned, isFalse);
    expect(stack.length, 2);
    expect(stack.current.name, 'picker');
    expect(completed, isFalse);
    expect(received, 'UNSET');

    // And once the veto is lifted, a real pop delivers the result exactly once.
    stack.guard = null;
    expect(stack.pop('CHOSEN'), isTrue);
    await Future<void>.value();
    expect(completed, isTrue);
    expect(received, 'CHOSEN');

    stack.dispose();
  });
}
