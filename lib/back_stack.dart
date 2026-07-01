/// back_stack — you own the back stack.
///
/// Navigation is a `List` you own. Push adds, pop removes, the UI follows.
/// No `go` vs `push`, no route graph, no `RouterDelegate`. Type-safe by
/// construction: your destinations are plain Dart types, checked by the
/// compiler.
library;

export 'src/nav_app.dart';
export 'src/nav_confirm.dart';
export 'src/nav_display.dart';
export 'src/nav_entries.dart';
export 'src/nav_key.dart';
export 'src/nav_multi.dart';
export 'src/nav_pages.dart';
export 'src/nav_restoration.dart';
export 'src/nav_router.dart';
export 'src/nav_scene.dart';
export 'src/nav_scope.dart';
export 'src/nav_stack.dart';
