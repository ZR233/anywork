import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../platform/error_log.dart';
import 'application_launch_boundary.dart';

/// Shared production/demo/Driver launch boundary. No module-level graph or
/// mutable container exists; entrypoints explicitly choose their real factories.
/// Binding and runApp precede assembly, so constructor failures can use the
/// same startup UI before the graph and its domain observers even exist.
void bootstrapStudio({
  required Future<void> Function() assemble,

  /// Runs inside the same guarded zone before the default binding is ensured.
  /// Driver installs its own binding here; production passes none.
  void Function()? beforeRun,
}) {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    recordDartError(details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    recordDartError(error, stack);
    return true;
  };
  runZonedGuarded(() {
    beforeRun?.call();
    WidgetsFlutterBinding.ensureInitialized();
    runApp(createApplicationLaunch(assemble: assemble));
  }, recordDartError);
}
