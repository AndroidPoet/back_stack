import 'dart:async';
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';

/// Runs for every test in this package. Enabling leak tracking here makes the
/// whole `testWidgets` suite fail if a Listenable, controller, or other
/// disposable created during a test is not disposed — proving nav_stack doesn't
/// leak screens or notifiers as the stack changes.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  LeakTesting.enable();
  LeakTesting.settings = LeakTesting.settings.withTrackedAll().withIgnored(
    // The test binding lazily creates one TestRestorationManager (and its root
    // bucket) for the whole file when a test exercises state restoration, and
    // never disposes it — framework-owned, not something the package can free.
    notDisposed: {'TestRestorationManager': null, 'RestorationBucket': null},
  );
  await testMain();
}
