import 'package:back_stack/back_stack.dart';

/// The shared destination type for the app.
///
/// It is **not** `sealed`: each feature lives in its own file and defines its
/// own [AppKey] subtype there, so there is no central list to edit and no
/// `switch` to keep exhaustive. Screens are wired up with [NavEntries] instead.
abstract class AppKey extends NavKey {
  const AppKey();
}
