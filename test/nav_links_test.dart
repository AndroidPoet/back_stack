import 'package:back_stack/back_stack.dart';
import 'package:flutter_test/flutter_test.dart';

sealed class K extends NavKey with EquatableNavKey {
  const K();
}

class Home extends K {
  const Home();
  @override
  List<Object?> get props => const [];
}

class Product extends K {
  const Product(this.id);
  final int id;
  @override
  List<Object?> get props => [id];
}

class Search extends K {
  const Search(this.q, {this.page = 1});
  final String q;
  final int page;
  @override
  List<Object?> get props => [q, page];
}

class Docs extends K {
  const Docs(this.path);
  final List<String> path;
  @override
  List<Object?> get props => [path.join('/')];
}

class NotFound extends K {
  const NotFound();
  @override
  List<Object?> get props => const [];
}

class Transient extends K {
  // Deliberately not registered in any links table.
  const Transient();
  @override
  List<Object?> get props => const [];
}

NavLinks<K> buildLinks() => NavLinks<K>()
  ..on<Home>('/', decode: (m) => const Home())
  ..on<Product>(
    '/products/:id',
    decode: (m) => Product(m.integer('id')!),
    encode: (key) => {'id': key.id},
    parents: (key) => const [Home()],
  )
  ..on<Search>(
    '/search',
    decode: (m) => Search(m.str('q') ?? '', page: m.integer('page') ?? 1),
    encode: (key) => {'q': key.q, 'page': key.page},
    parents: (key) => const [Home()],
  )
  ..on<Docs>(
    '/docs/*path',
    decode: (m) => Docs(m.rest),
    encode: (key) => {'path': key.path},
  )
  ..notFound((uri) => const [Home(), NotFound()]);

void main() {
  group('NavLinks decode', () {
    test('root, params, query and catch-all all decode', () {
      final links = buildLinks();

      expect(links.decode(Uri.parse('/')), const [Home()]);
      expect(
        links.decode(Uri.parse('/products/42')),
        const [Home(), Product(42)],
      );
      expect(
        links.decode(Uri.parse('/search?q=shoes&page=3')),
        const [Home(), Search('shoes', page: 3)],
      );
      expect(
        links.decode(Uri.parse('/docs/guides/deep-links')),
        const [Docs(['guides', 'deep-links'])],
      );
      // Catch-all matches zero segments too.
      expect(links.decode(Uri.parse('/docs')), const [Docs([])]);
    });

    test('a throwing decode means "not mine" — falls through to notFound', () {
      final links = buildLinks();
      // 'abc' fails integer('id')! → Product pattern rejects → 404 stack.
      expect(
        links.decode(Uri.parse('/products/abc')),
        const [Home(), NotFound()],
      );
    });

    test('unknown paths hit notFound; without notFound decode throws', () {
      final links = buildLinks();
      expect(links.decode(Uri.parse('/nope/nope')), const [Home(), NotFound()]);

      final bare = NavLinks<K>()..on<Home>('/', decode: (m) => const Home());
      expect(() => bare.decode(Uri.parse('/nope')), throwsFormatException);
      // fallbackFor still lands on '/' via the base implementation.
      expect(bare.fallbackFor(Uri.parse('/nope')), const [Home()]);
    });

    test('weird URIs never crash: encoded chars, trailing slash, empties', () {
      final links = buildLinks();
      // Percent-encoded query decodes.
      expect(
        links.decode(Uri.parse('/search?q=red%20shoes')),
        const [Home(), Search('red shoes')],
      );
      // Trailing slash produces the same segments.
      expect(
        links.decode(Uri.parse('/products/7/')),
        const [Home(), Product(7)],
      );
      // Nonsense never throws: URI dot-segment normalization collapses this
      // to the root, so it lands on Home rather than crashing.
      expect(links.decode(Uri.parse('/%2F%2F/..//')).first, const Home());
      // Truly unknown junk lands on the 404 stack.
      expect(
        links.decode(Uri.parse('/%00/%FF')),
        const [Home(), NotFound()],
      );
    });

    test('registration order wins ties', () {
      final links = NavLinks<K>()
        ..on<Product>('/x/:id', decode: (m) => Product(m.integer('id')!))
        ..on<Search>('/x/:q', decode: (m) => Search(m.str('q')!));
      // Numeric → first pattern.
      expect(links.decode(Uri.parse('/x/5')), const [Product(5)]);
      // Non-numeric → first pattern's decode throws → second matches.
      expect(links.decode(Uri.parse('/x/hi')), const [Search('hi')]);
    });
  });

  group('NavLinks encode', () {
    test('fills path params and turns leftovers into query params', () {
      final links = buildLinks();
      expect(
        links.encode(const [Home(), Product(42)]).toString(),
        '/products/42',
      );
      expect(
        links.encode(const [Home(), Search('shoes', page: 2)]).toString(),
        '/search?q=shoes&page=2',
      );
      expect(
        links.encode(const [Docs(['a', 'b'])]).toString(),
        '/docs/a/b',
      );
      expect(links.encode(const [Home()]).toString(), '/');
    });

    test('an unregistered top keeps the URL of the screen under it', () {
      final links = buildLinks();
      expect(
        links.encode(const [Home(), Product(9), Transient()]).toString(),
        '/products/9',
      );
      // Nothing registered at all → root.
      expect(links.encode(const [Transient()]).toString(), '/');
    });

    test('linkFor produces shareable URLs and null for unregistered', () {
      final links = buildLinks();
      expect(links.linkFor(const Product(3)).toString(), '/products/3');
      expect(links.linkFor(const Transient()), isNull);
    });

    test('encodes what needs it, both directions', () {
      final links = buildLinks();
      final uri = links.encode(const [Home(), Search('red shoes')]);
      expect(uri.toString(), isNot(contains('red shoes')), reason: 'encoded');
      expect(links.decode(uri), const [Home(), Search('red shoes')]);

      // Path segments percent-encode too.
      final docs = links.encode(const [Docs(['a b'])]);
      expect(docs.toString(), '/docs/a%20b');
      expect(links.decode(docs), const [Docs(['a b'])]);
    });
  });

  group('NavLinks round-trip', () {
    test('encode∘decode is idempotent for every registered pattern', () {
      final links = buildLinks();
      const stacks = [
        [Home()],
        [Home(), Product(1)],
        [Home(), Search('q w', page: 9)],
        [Docs(['x'])],
        [Docs([])],
      ];
      for (final stack in stacks) {
        final uri = links.encode(stack);
        expect(
          links.encode(links.decode(uri)).toString(),
          uri.toString(),
          reason: 'drift for $stack',
        );
      }
    });
  });

  group('NavLinks restoration codec', () {
    test('encodeKey/decodeKey round-trip a key without its parents', () {
      final links = buildLinks();
      final data = links.encodeKey(const Product(11));
      expect(data, '/products/11');
      expect(links.decodeKey(data!), const Product(11));
    });

    test('unregistered keys are skipped (null), never a crash', () {
      final links = buildLinks();
      expect(links.encodeKey(const Transient()), isNull);
      expect(links.decodeKey('/definitely/not/registered'), isNull);
      expect(links.decodeKey('::::not a uri::::'), isNull);
    });
  });

  group('NavMatch', () {
    test('typed reads are null-safe; path params beat query params', () {
      final links = NavLinks<K>()
        ..on<Product>(
          '/p/:id',
          decode: (m) {
            expect(m.integer('id'), 5);
            expect(m.str('missing'), isNull);
            expect(m.integer('junk'), isNull);
            expect(m.number('ratio'), 1.5);
            expect(m.boolean('on'), isTrue);
            expect(m.boolean('absent', orElse: true), isTrue);
            // Path param shadows the query param of the same name.
            expect(m.str('id'), '5');
            return Product(m.integer('id')!);
          },
        );
      links.decode(Uri.parse('/p/5?id=99&junk=x&ratio=1.5&on=1'));
    });
  });
}
