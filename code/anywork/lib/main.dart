import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app/anywork_app.dart';
import 'src/app/app_graph.dart';
import 'src/platform/error_log.dart';

void main() {
  bootstrapStudio();
}

/// Driver 构建可注入外部 ProviderContainer，让 driver 请求访问应用级状态。
void bootstrapStudio({ProviderContainer? container, AppGraph? graph}) {
  final AppGraph application =
      graph ??
      (container != null
          ? container.read(appGraphProvider)
          : (const bool.fromEnvironment('ANYWORK_DEMO')
                ? AppGraph.demo(
                    driver: const bool.fromEnvironment('ANYWORK_DRIVER'),
                  )
                : AppGraph.production()));
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    recordDartError(details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    recordDartError(error, stack);
    return true;
  };
  runZonedGuarded(() {
    if (container case final external?) {
      runApp(
        UncontrolledProviderScope(
          container: external,
          child: const AnyworkApp(enableDesktopTray: true),
        ),
      );
      return;
    }
    runApp(
      ProviderScope(
        overrides: [appGraphProvider.overrideWithValue(application)],
        child: const AnyworkApp(enableDesktopTray: true),
      ),
    );
  }, recordDartError);
}
