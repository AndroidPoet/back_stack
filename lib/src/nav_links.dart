import 'package:back_stack/src/nav_key.dart';
import 'package:back_stack/src/nav_router.dart';

/// What a matched pattern hands your `decode` function: typed, null-safe access
/// to the path parameters and query parameters of the matched [uri].
///
/// Path parameters win over query parameters of the same name. Every read is
/// null-safe — a missing or malformed value is `null`, never a throw — and a
/// `decode` that can't live with `null` can just use `!`: a throwing decode
/// simply means "this pattern doesn't match after all" (see [NavLinks.on]).
class NavMatch {
  const NavMatch._(this.uri, this._params, this.rest);

  /// The full matched URL, for anything the helpers don't cover.
  final Uri uri;

  final Map<String, String> _params;

  /// The segments captured by a trailing `*` catch-all, e.g. for the pattern
  /// `/docs/*path`, `/docs/a/b` yields `['a', 'b']`. Empty otherwise.
  final List<String> rest;

  /// The path parameter or query parameter [name], or `null` if absent.
  String? str(String name) => _params[name] ?? uri.queryParameters[name];

  /// [str] parsed as an `int`, or `null` if absent/invalid.
  int? integer(String name) => int.tryParse(str(name) ?? '');

  /// [str] parsed as a `double`, or `null` if absent/invalid.
  double? number(String name) => double.tryParse(str(name) ?? '');

  /// [str] as a `bool`: `true`/`1` → true, `false`/`0` → false, anything else →
  /// [orElse] (default `false`).
  bool boolean(String name, {bool orElse = false}) =>
      switch (str(name)?.toLowerCase()) {
        'true' || '1' => true,
        'false' || '0' => false,
        _ => orElse,
      };
}

/// The URL table: one entry per linkable destination, each declaring **both
/// directions at once** — how a URL becomes the key, and how the key becomes a
/// URL. Everything URL-shaped is then derived from this single table: deep
/// links, web address-bar sync, browser back/forward, shareable links
/// ([linkFor]) and full-stack state restoration — they can never drift apart,
/// because there is nothing else to keep in sync.
///
/// ```dart
/// final links = NavLinks<AppKey>()
///   ..on<Home>('/', decode: (m) => const Home())
///   ..on<Product>(
///     '/products/:id',
///     decode: (m) => Product(m.integer('id')!),
///     encode: (key) => {'id': key.id},
///     parents: (key) => const [Home()], // Back from a deep link goes Home
///   )
///   ..on<Search>(
///     '/search',
///     decode: (m) => Search(m.str('q') ?? ''),
///     encode: (key) => {'q': key.q},    // not in the pattern → query param
///     parents: (key) => const [Home()],
///   )
///   ..notFound((uri) => const [Home(), NotFound()]);
///
/// BackStackApp<AppKey>(stack: stack, entries: entries, links: links);
/// ```
///
/// It is still **not** a route table that owns navigation: it never touches the
/// stack, it only translates. A [NavLinks] *is* a [NavStackCodec], so it plugs
/// in anywhere one goes — `BackStackApp(links: …)` is the usual place.
///
/// **Pattern syntax.** Segments are literal (`products`), a named parameter
/// (`:id` — matches exactly one segment), or a trailing catch-all (`*rest` —
/// matches zero or more; read them via [NavMatch.rest]). `/` is the empty
/// pattern. Patterns match in registration order; the first entry whose
/// pattern fits *and* whose `decode` doesn't throw wins.
///
/// **Encoding.** `encode` returns one flat map: values named in the pattern
/// fill its `:name` slots (a catch-all takes an `Iterable`), and every leftover
/// entry becomes a query parameter (`null` values are dropped). The URL for a
/// stack is the URL of its **top-most registered** destination — an
/// unregistered top (a dialog key, a transient step) simply keeps the URL of
/// the screen under it.
///
/// Like `NavEntries`, registration is just method calls, so feature modules
/// can each contribute their own entries into one shared instance. Matching for
/// `encode` is by exact runtime type — register each concrete type you push.
class NavLinks<K extends NavKey> extends NavStackCodec<K> {
  /// Creates an empty table; register entries with [on].
  NavLinks();

  final List<_LinkEntry<K>> _entries = [];
  final Map<Type, _LinkEntry<K>> _byType = {};
  List<K> Function(Uri uri)? _notFound;

  /// Register destination type [T] at [pattern].
  ///
  /// [decode] builds the key from a matched URL. If it throws, the pattern is
  /// treated as not matching and the next entry is tried — so
  /// `Product(m.integer('id')!)` is the whole "only match numeric ids" story.
  ///
  /// [encode] supplies the pattern's parameter values (and any extra entries
  /// become query parameters). Omit it when the pattern has none.
  ///
  /// [parents] is the stack placed **under** the key when a deep link lands on
  /// it — the layer-vs-replace choice, per destination. Omit it for
  /// `[key]` alone (the link replaces the stack with just that screen).
  ///
  /// Registering the same type again keeps the earlier pattern matching
  /// inbound links (handy for legacy URL aliases), while the **latest**
  /// registration defines the outbound URL, `parents`, and restoration.
  void on<T extends K>(
    String pattern, {
    required T Function(NavMatch match) decode,
    Map<String, Object?> Function(T key)? encode,
    List<K> Function(T key)? parents,
  }) {
    final entry = _LinkEntry<K>(
      pattern: _parsePattern(pattern),
      patternSource: pattern,
      type: T,
      decode: decode,
      encode: encode == null ? null : (key) => encode(key as T),
      parents: parents == null ? null : (key) => parents(key as T),
    );
    _entries.add(entry);
    _byType[T] = entry;
  }

  /// The stack shown when no pattern matches an incoming link — your 404. It
  /// must be total (never throw). Without it, an unknown link falls back to
  /// decoding `/`.
  // ignore: use_setters_to_change_properties, cascades with ..notFound(…) like on().
  void notFound(List<K> Function(Uri uri) build) => _notFound = build;

  /// Whether an entry is registered for type [T].
  bool has<T extends K>() => _byType.containsKey(T);

  /// The shareable URL for [key], or `null` if its type isn't registered.
  Uri? linkFor(K key) {
    final entry = _byType[key.runtimeType];
    return entry == null ? null : _build(entry, key);
  }

  // ---- NavStackCodec: what the Router/delegate speaks -----------------------

  @override
  Uri encode(List<K> stack) {
    for (var i = stack.length - 1; i >= 0; i--) {
      final entry = _byType[stack[i].runtimeType];
      if (entry != null) return _build(entry, stack[i]);
    }
    return Uri(path: '/');
  }

  @override
  List<K> decode(Uri uri) {
    final key = _match(uri);
    if (key == null) {
      final fallback = _notFound;
      if (fallback != null) return fallback(uri);
      throw FormatException('No NavLinks pattern matches $uri');
    }
    final entry = _byType[key.runtimeType];
    final parents = entry?.parents?.call(key) ?? const [];
    return [...parents, key];
  }

  @override
  List<K> fallbackFor(Uri uri) =>
      _notFound?.call(uri) ?? super.fallbackFor(uri);

  // ---- restoration: the same table, per key ---------------------------------

  /// One destination → its URL string, or `null` when [key]'s type isn't in
  /// the table. Used for full-stack state restoration: unregistered keys (a
  /// dialog, a transient step) are simply skipped rather than crashing the
  /// snapshot.
  String? encodeKey(K key) => linkFor(key)?.toString();

  /// The inverse of [encodeKey]: a stored URL string → the key alone (no
  /// [on] `parents` are added — the whole stack was stored key by key).
  /// Returns `null` when nothing matches (e.g. the pattern changed across an
  /// app update) so restoration can skip it instead of crashing.
  K? decodeKey(String data) {
    final uri = Uri.tryParse(data);
    return uri == null ? null : _match(uri);
  }

  // ---- internals -------------------------------------------------------------

  /// First registered entry whose pattern matches [uri] and whose decode
  /// doesn't throw.
  K? _match(Uri uri) {
    List<String> segments;
    try {
      segments = uri.pathSegments;
    } on FormatException {
      // Even *reading* the path can throw (invalid UTF-8 in a percent
      // escape). An adversarial link is still just an unknown link.
      return null;
    }
    // Normalize: a trailing slash ('/products/7/') yields a trailing empty
    // segment — treat it as the same location, like every web router does.
    while (segments.isNotEmpty && segments.last.isEmpty) {
      segments = segments.sublist(0, segments.length - 1);
    }
    for (final entry in _entries) {
      final params = entry.matchSegments(segments);
      if (params == null) continue;
      final match = NavMatch._(uri, params.named, params.rest);
      try {
        return entry.decode(match);
      } on Object catch (_) {
        // A throwing decode means "not mine after all" — try the next pattern.
        continue;
      }
    }
    return null;
  }

  Uri _build(_LinkEntry<K> entry, K key) {
    final params = Map<String, Object?>.of(entry.encode?.call(key) ?? const {});
    final segments = <String>[];
    for (final seg in entry.pattern) {
      switch (seg) {
        case _Literal(:final value):
          segments.add(value);
        case _Param(:final name):
          final value = params.remove(name);
          assert(
            value != null,
            'NavLinks: encoding a ${key.runtimeType} for pattern '
            '"${entry.patternSource}" — encode() must supply "$name".',
          );
          segments.add('$value');
        case _CatchAll(:final name):
          final value = params.remove(name);
          if (value is Iterable) {
            segments.addAll([for (final v in value) '$v']);
          } else if (value != null) {
            segments.add('$value');
          }
      }
    }
    final query = <String, String>{
      for (final e in params.entries)
        if (e.value != null) e.key: '${e.value}',
    };
    final queryParameters = query.isEmpty ? null : query;
    return segments.isEmpty
        ? Uri(path: '/', queryParameters: queryParameters)
        : Uri(
            pathSegments: ['', ...segments],
            queryParameters: queryParameters,
          );
  }

  static List<_PatternSegment> _parsePattern(String pattern) {
    final parts = [
      for (final p in pattern.split('/'))
        if (p.isNotEmpty) p,
    ];
    final segments = <_PatternSegment>[];
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (part.startsWith(':')) {
        segments.add(_Param(part.substring(1)));
      } else if (part.startsWith('*')) {
        assert(
          i == parts.length - 1,
          'NavLinks: a catch-all (*) must be the last segment of a pattern '
          '(got "$pattern").',
        );
        final name = part.substring(1);
        segments.add(_CatchAll(name.isEmpty ? 'rest' : name));
      } else {
        segments.add(_Literal(part));
      }
    }
    return segments;
  }
}

class _LinkEntry<K extends NavKey> {
  _LinkEntry({
    required this.pattern,
    required this.patternSource,
    required this.type,
    required this.decode,
    required this.encode,
    required this.parents,
  });

  final List<_PatternSegment> pattern;
  final String patternSource;
  final Type type;
  final K Function(NavMatch match) decode;
  final Map<String, Object?> Function(K key)? encode;
  final List<K> Function(K key)? parents;

  /// Match [segments] against the pattern: the captured `:name` params and
  /// catch-all rest, or null when it doesn't fit.
  ({Map<String, String> named, List<String> rest})? matchSegments(
    List<String> segments,
  ) {
    final hasCatchAll = pattern.isNotEmpty && pattern.last is _CatchAll;
    final fixed = hasCatchAll ? pattern.length - 1 : pattern.length;
    if (hasCatchAll ? segments.length < fixed : segments.length != fixed) {
      return null;
    }
    final named = <String, String>{};
    for (var i = 0; i < fixed; i++) {
      switch (pattern[i]) {
        case _Literal(:final value):
          if (segments[i] != value) return null;
        case _Param(:final name):
          named[name] = segments[i];
        case _CatchAll():
          return null; // unreachable: catch-all is always last
      }
    }
    return (
      named: named,
      rest: hasCatchAll ? segments.sublist(fixed) : const [],
    );
  }
}

sealed class _PatternSegment {
  const _PatternSegment();
}

class _Literal extends _PatternSegment {
  const _Literal(this.value);
  final String value;
}

class _Param extends _PatternSegment {
  const _Param(this.name);
  final String name;
}

class _CatchAll extends _PatternSegment {
  const _CatchAll(this.name);
  final String name;
}
