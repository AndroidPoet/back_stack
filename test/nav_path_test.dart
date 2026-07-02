import 'package:back_stack/back_stack.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NavPath reading', () {
    test('safe path segment access, no throws', () {
      final p = NavPath(Uri.parse('/products/42'));
      expect(p.segments, ['products', '42']);
      expect(p.seg(0), 'products');
      expect(p.segInt(1), 42);
      expect(p.seg(5), isNull); // out of range
      expect(p.segInt(0), isNull); // 'products' isn't an int
    });

    test('typed query parameters', () {
      final p = NavPath(Uri.parse('/search?q=shoes&page=3&sale=1&ratio=1.5'));
      expect(p.str('q'), 'shoes');
      expect(p.integer('page'), 3);
      expect(p.number('ratio'), 1.5);
      expect(p.boolean('sale'), isTrue);
      expect(p.boolean('missing'), isFalse);
      expect(p.boolean('missing', orElse: true), isTrue);
      expect(p.integer('q'), isNull); // not a number
    });
  });

  group('NavPath.build', () {
    test('builds paths and drops nulls', () {
      expect(NavPath.build(['products', 42]).toString(), '/products/42');
      expect(NavPath.build(const []).toString(), '/');
      expect(NavPath.build([null, 'x']).toString(), '/x'); // null dropped
    });

    test('builds query strings, dropping null values', () {
      final uri = NavPath.build(const ['search'], query: {'q': 'x', 'page': 2});
      expect(uri.path, '/search');
      expect(uri.queryParameters, {'q': 'x', 'page': '2'});

      final noQuery = NavPath.build(const ['a'], query: {'x': null});
      expect(noQuery.hasQuery, isFalse); // all-null query → no '?'
    });

    test('round-trips through the reader', () {
      final uri = NavPath.build(['products', 7], query: {'ref': 'email'});
      final p = NavPath(uri);
      expect(p.segInt(1), 7);
      expect(p.str('ref'), 'email');
    });
  });
}
