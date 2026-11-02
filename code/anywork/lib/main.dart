import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app/anywork_app.dart';
import 'src/app/app_composition.dart';
import 'src/app/app_graph.dart';
import 'src/capture/capture_extension.dart';
import 'src/features/settings/statistics/view_models/statistics_repository_provider.dart';
import 'src/platform/error_log.dart';

void main() {
  bootstrapStudio();
}

void bootstrapStudio({AppGraph? graph}) {
  final AppGraph application =
      graph ??
      (const bool.fromEnvironment('ANYWORK_DEMO')
          ? createDemoAppGraph()
          : createProductionAppGraph());
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    recordDartError(details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    recordDartError(error, stack);
    return true;
  };
  if (!const bool.fromEnvironment('dart.vm.product')) {
    maybeRegisterCaptureExtension();
  }
  runZonedGuarded(() {
    runApp(
      ProviderScope(
        overrides: [
          appGraphProvider.overrideWithValue(application),
          statisticsRepositoryProvider.overrideWithValue(
            application.statisticsRepository,
          ),
        ],
        child: AnyworkApp(
          enableDesktopHost: true,
          enableDesktopTray: true,
          enableContentCapture: const bool.fromEnvironment('ANYWORK_CAPTURE'),
        ),
      ),
    );
  }, recordDartError);
}
