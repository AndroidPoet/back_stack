/// Typed sugar over a [Uri] for writing `onLink`/`toLink` (or a `NavStackCodec`)
/// without hand-rolled index checks, `int.tryParse`, and `Uri(...)` plumbing.
///
/// It is **not** a route table or a path DSL — back_stack still has no route
/// graph. It just makes the two functions you already write terser: Dart 3 list
/// patterns handle path *matching*, and this handles the parts they don't —
/// building a URL and reading query parameters safely.
///
/// Decoding a link (`onLink`):
///
/// ```dart
/// onLink: (uri) {
///   final p = NavPath(uri);
///   return switch (uri.pathSegments) {
///     ['products', final id] when int.tryParse(id) != null =>
///         [const Home(), Product(int.parse(id))],
///     ['search'] => [const Home(), Search(p.str('q') ?? '')], // ?q=shoes
///     _ => [const Home()],
///   };
/// },
/// ```
///
/// Encoding the stack back to a URL (`toLink`):
///
/// ```dart
/// toLink: (stack) => switch (stack.last) {
///   Home()             => NavPath.build(const []),                    // '/'
///   Product(:final id) => NavPath.build(['products', id]),            // '/products/42'
///   Search(:final q)   => NavPath.build(const ['search'], query: {'q': q}),
///   _                  => NavPath.build(const []),
/// },
/// ```
class NavPath {
  /// Wraps [uri] for reading. Cheap — construct one per decode.
  const NavPath(this.uri);

  /// The wrapped URL.
  final Uri uri;

  /// The path segments, e.g. `['products', '42']` for `/products/42`.
  List<String> get segments => uri.pathSegments;

  /// The path segment at [index], or `null` if there aren't that many — the
  /// null-safe alternative to `uri.pathSegments[index]`.
  String? seg(int index) =>
      index >= 0 && index < segments.length ? segments[index] : null;

  /// The path segment at [index] parsed as an `int`, or `null` if it's missing
  /// or not a number — no `int.parse` throw to guard against.
  int? segInt(int index) => int.tryParse(seg(index) ?? '');

  /// The query parameter [key] (`?key=value`), or `null` if absent.
  String? str(String key) => uri.queryParameters[key];

  /// The query parameter [key] parsed as an `int`, or `null` if absent/invalid.
  int? integer(String key) => int.tryParse(uri.queryParameters[key] ?? '');

  /// The query parameter [key] parsed as a `double`, or `null` if absent/invalid.
  double? number(String key) => double.tryParse(uri.queryParameters[key] ?? '');

  /// The query parameter [key] as a `bool`: `true`/`1` → true, `false`/`0` →
  /// false, anything else → [orElse] (default `false`).
  bool boolean(String key, {bool orElse = false}) =>
      switch (uri.queryParameters[key]?.toLowerCase()) {
        'true' || '1' => true,
        'false' || '0' => false,
        _ => orElse,
      };

  /// Build a `Uri` from path [segments] and optional [query] — the terse way to
  /// write `toLink`/`encode`. Values are stringified via `toString()`; `null`
  /// path segments and `null` query values are dropped. An empty [segments]
  /// yields the root path `/`.
  ///
  /// ```dart
  /// NavPath.build(['products', 42]);                 // /products/42
  /// NavPath.build(const ['search'], query: {'q': 'x', 'page': 2}); // /search?q=x&page=2
  /// NavPath.build(const []);                         // /
  /// ```
  static Uri build(List<Object?> segments, {Map<String, Object?>? query}) {
    final path = [
      for (final s in segments)
        if (s != null) '$s',
    ];
    final params = query == null
        ? null
        : {
            for (final e in query.entries)
              if (e.value != null) e.key: '${e.value}',
          };
    final queryParameters = (params == null || params.isEmpty) ? null : params;
    // A leading empty segment makes the path absolute (`/a/b`) while keeping
    // per-segment percent-encoding; an empty path is just the root `/`.
    return path.isEmpty
        ? Uri(path: '/', queryParameters: queryParameters)
        : Uri(pathSegments: ['', ...path], queryParameters: queryParameters);
  }
}
