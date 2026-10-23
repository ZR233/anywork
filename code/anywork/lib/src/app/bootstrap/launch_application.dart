import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/error_log.dart';
import '../anywork_app.dart';
import '../app_graph.dart';
import '../composition/application_container.dart';

/// Shared production/demo/Driver launch boundary. No module-level graph or
/// mutable container exists; entrypoints explicitly choose their real factories.
/// The returned container is owned by the caller and cannot be disposed until
/// the graph's real asynchronous exit joins have finished.
ProviderContainer bootstrapStudio({
  required AppGraph graph,
  required Widget Function(BuildContext context, Widget child) desktopHostBuilder,
  ProviderContainer? container,
}) {
  final applicationContainer = container ?? createApplicationContainer(graph);
  if (container != null) requireApplicationContainer(container, graph);
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    recordDartError(details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    recordDartError(error, stack);
    return true;
  };
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    runApp(UncontrolledProviderScope(container: applicationContainer,
      child: AnyworkApp(graph: graph, desktopHostBuilder: desktopHostBuilder)));
  }, recordDartError);
  return applicationContainer;
}
