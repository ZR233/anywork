import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:anywork/src/app/app_composition.dart';
import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/routing/application_router.dart';
import 'package:anywork/src/app/studio_shutdown.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/settings/statistics/view_models/statistics_repository_provider.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Narrow integration-test host for the production Studio shell.
///
/// It owns the real FRB client, SQLite-backed [AppGraph], production router and
/// shutdown contract. Tests may prepare ordinary directories and invoke public
/// Client commands, but must not seed SQLite or replace production renderers.
final class ProductionStudioHarness {
  ProductionStudioHarness._({
    required this.binding,
    required this.graph,
    required this.artifacts,
  });

  final IntegrationTestWidgetsFlutterBinding binding;
  final AppGraph graph;
  final Directory artifacts;
  final GlobalKey _captureBoundary = GlobalKey(
    debugLabel: 'production-studio-capture',
  );

  static Future<ProductionStudioHarness> start({
    required IntegrationTestWidgetsFlutterBinding binding,
    required String artifactsEnvironmentVariable,
  }) async {
    final artifactsPath = Platform.environment[artifactsEnvironmentVariable]
        ?.trim();
    if (artifactsPath == null || artifactsPath.isEmpty) {
      throw StateError('Supply $artifactsEnvironmentVariable');
    }
    final artifacts = Directory(artifactsPath);
    await artifacts.create(recursive: true);

    final graph = createProductionAppGraph();
    await graph.initialize();
    if (graph.client.bootstrapState.value.failure case final failure?) {
      throw StateError('Production Studio bootstrap failed: $failure');
    }
    await _verifyDirectoryObservation(graph);
    return ProductionStudioHarness._(
      binding: binding,
      graph: graph,
      artifacts: artifacts,
    );
  }

  static Future<void> _verifyDirectoryObservation(AppGraph graph) async {
    final observation = graph.client.threadDirectory.observeThreads(
      const DirectoryQuery(),
      DirectoryWindow(limit: 1),
    );
    try {
      final state = await observation.state
          .waitFor(
            (state) =>
                state.frame != null || state.error != null || state.closed,
          )
          .timeout(const Duration(seconds: 30));
      if (state.error case final error?) {
        throw StateError('Production thread directory failed: $error');
      }
      if (state.closed || state.frame == null) {
        throw StateError(
          'Production thread directory closed without an initial frame',
        );
      }
    } finally {
      await observation.release();
    }
  }

  Future<ProductionStudioScene> mount(
    WidgetTester tester, {
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    final router = createApplicationRouter();
    // Native integration tests must not race a desktop IME with enterText.
    // This is Flutter's standard test keyboard, registered before fields mount.
    tester.testTextInput.register();
    graph.setConversationPageVisible(true);
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appGraphProvider.overrideWithValue(graph),
            statisticsRepositoryProvider.overrideWithValue(
              graph.statisticsRepository,
            ),
          ],
          child: MaterialApp.router(
            theme: pureStudioTheme(),
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: textScaler),
              child: RepaintBoundary(key: _captureBoundary, child: child!),
            ),
          ),
        ),
      );
      final scene = ProductionStudioScene._(
        tester: tester,
        harness: this,
        disposeRouter: router.dispose,
      );
      await scene.until(
        () => find.byKey(StudioDriverKeys.shell).evaluate().length == 1,
        'production Studio shell mounted',
      );
      return scene;
    } catch (_) {
      graph.setConversationPageVisible(false);
      try {
        await tester.pumpWidget(const SizedBox());
      } finally {
        tester.testTextInput.unregister();
        router.dispose();
      }
      rethrow;
    }
  }

  Future<StudioProject> openProject(
    ProductionStudioScene scene,
    String path,
  ) async {
    if (!await Directory(path).exists()) {
      throw StateError('Synthetic project directory does not exist: $path');
    }
    await graph.client.directoryCommands.openProject(path);
    late StudioProject project;
    await scene.until(() {
      final matches =
          (graph.client.project.state.projects?.values ??
                  const <StudioProject>[])
              .where((candidate) => candidate.path == path)
              .toList(growable: false);
      if (matches.length != 1) return false;
      project = matches.single;
      return true;
    }, 'canonical project directory contains $path');
    return project;
  }

  Future<void> close() async {
    await File('${artifacts.path}/sidebar-mutations-before-shutdown.json')
        .writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'operations': graph.client.mutations.operations
                .map(_operationDiagnostic)
                .toList(growable: false),
          }),
          flush: true,
        );
    final report = await runStudioShutdown(
      graph.client.transport,
      (_) {},
      remainingMs: 30000,
      closeClient: (deadline) => graph.close(deadline: deadline),
    );
    await File('${artifacts.path}/sidebar-shutdown.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'clean': report.shutdown.isClean,
        'issues': report.shutdown.issues.map((issue) => '$issue').toList(),
        'persistence': report.shutdown.persistence.runtimeType.toString(),
      }),
      flush: true,
    );
    expect(
      report.shutdown.isClean,
      isTrue,
      reason: report.shutdown.issues.toString(),
    );
    expect(report.shutdown.issues, isEmpty);
    expect(report.shutdown.persistence, isA<DrainedStudioPendingPersistence>());
  }
}

Map<String, Object?> _operationDiagnostic(OperationState operation) {
  final receipt = operation.receipt;
  return {
    'operationId': operation.id.value,
    'target': operation.target,
    'phase': operation.phase.name,
    'observed': operation.observed,
    'effective': operation.effective,
    'durable': operation.durable,
    'failurePhase': operation.failurePhase?.name,
    'errorType': operation.error?.runtimeType.toString(),
    'draft': switch (operation.draft) {
      final draft? => {'draftId': draft.draftId, 'revision': draft.revision},
      null => null,
    },
    'receipt': receipt == null
        ? null
        : {
            'operationId': receipt.operationId.value,
            'disposition': receipt.disposition.name,
            'targets': receipt.targets.map(_stampDiagnostic).toList(),
            'effect': receipt.effect.name,
            'effective': receipt.effective,
            'durable': receipt.durable,
            'requiresIdentityObservation': receipt.requiresIdentityObservation,
          },
  };
}

Map<String, Object?> _stampDiagnostic(ObservationStamp stamp) =>
    switch (stamp) {
      ResourceStamp() => {
        'type': 'resource',
        'resourceKey': stamp.resourceKey,
        'ownerEpoch': stamp.ownerEpoch,
        'revision': stamp.revision,
      },
      ViewStamp() => {
        'type': 'view',
        'resourceKey': stamp.resourceKey,
        'threadId': stamp.threadId,
        'viewId': stamp.viewId,
        'viewEpoch': stamp.viewEpoch,
        'version': stamp.version,
      },
    };

final class ProductionStudioScene {
  ProductionStudioScene._({
    required this.tester,
    required this.harness,
    required this._disposeRouter,
  });

  final WidgetTester tester;
  final ProductionStudioHarness harness;
  final void Function() _disposeRouter;
  bool _disposed = false;

  AppGraph get graph => harness.graph;

  Future<void> until(
    bool Function() condition,
    String stage, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 50));
      if (tester.takeException() case final error?) throw error;
      if (condition()) return;
    }
    throw StateError('Did not settle: $stage');
  }

  Future<File> capture(String name) async {
    final safeName = name.replaceAll(RegExp('[^a-z0-9-]'), '-');
    await tester.pump();
    final boundary =
        harness._captureBoundary.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null || boundary.debugNeedsPaint) {
      throw StateError('Production Studio capture boundary is not painted');
    }
    final view = ui.PlatformDispatcher.instance.views.single;
    final rendered = await boundary.toImage(pixelRatio: view.devicePixelRatio);
    final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
    rendered.dispose();
    if (data == null) {
      throw StateError('Production Studio capture did not encode PNG bytes');
    }
    final image = File('${harness.artifacts.path}/$safeName.png');
    await image.writeAsBytes(data.buffer.asUint8List(), flush: true);

    final metadata = File('${harness.artifacts.path}/$safeName.json');
    final sidebar = find.byKey(StudioDriverKeys.sidebar);
    final sidebarContext = tester.element(sidebar);
    final textScaler = MediaQuery.textScalerOf(sidebarContext);
    final sidebarFontSizes =
        find
            .descendant(of: sidebar, matching: find.byType(Text))
            .evaluate()
            .map((element) => (element.widget as Text).style?.fontSize)
            .whereType<double>()
            .toSet()
            .toList()
          ..sort();
    await metadata.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'capture': 'RenderRepaintBoundary.toImage',
        'scope': 'painted production Flutter surface without window chrome',
        'platform': Platform.operatingSystem,
        'physicalWidth': view.physicalSize.width,
        'physicalHeight': view.physicalSize.height,
        'devicePixelRatio': view.devicePixelRatio,
        'logicalWidth': view.physicalSize.width / view.devicePixelRatio,
        'logicalHeight': view.physicalSize.height / view.devicePixelRatio,
        'renderedLogicalWidth': boundary.size.width,
        'renderedLogicalHeight': boundary.size.height,
        'sidebarLogicalWidth': tester.getSize(sidebar).width,
        'scaledFont14': textScaler.scale(14),
        'sidebarExplicitFontSizes': sidebarFontSizes,
        'sidebarScaledFontSizes': sidebarFontSizes
            .map(textScaler.scale)
            .toList(growable: false),
      }),
      flush: true,
    );
    return image;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      graph.setConversationPageVisible(false);
      await tester.pumpWidget(const SizedBox());
      await until(
        () => graph.client.budget.used(ResourceKind.chatHandle) == 0,
        'retired production scene read handles joined',
      );
    } finally {
      tester.testTextInput.unregister();
      _disposeRouter();
    }
  }
}
