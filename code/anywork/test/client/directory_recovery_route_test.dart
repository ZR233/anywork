import 'dart:async';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/shell/studio_shell.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pump_client_future.dart';
import 'support/recording_demo_transport.dart';

void main() {
  testWidgets(
    'directory failure retains the shell and explicitly retries its topic',
    (tester) async {
      final transport = _DirectoryFailureTransport();
      final graph = AppGraph(
        transport: transport,
        clientId: 'directory-recovery',
      );
      await graph.client.bootstrap();
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await pumpClientFuture(
          tester,
          graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
          'directory recovery close',
        );
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appGraphProvider.overrideWithValue(graph)],
          child: MaterialApp(
            theme: pureStudioTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const StudioShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final input = find.byKey(StudioDriverKeys.composerInput);
      await tester.enterText(input, 'draft survives directory outage');
      final project = graph.client.selection.state.selectedProjectId;
      transport.fail();
      // Release the production retry timers using Flutter's virtual clock.
      for (var attempt = 0; attempt < 8; attempt++) {
        if (graph.client.project.state.projectSync.phase ==
            DomainSyncPhase.failed) {
          break;
        }
        await tester.pump(const Duration(seconds: 5));
        await tester.runAsync(() async {});
      }
      expect(
        graph.client.project.state.projectSync.phase,
        DomainSyncPhase.failed,
      );
      expect(find.byKey(StudioDriverKeys.startPage), findsOneWidget);
      expect(find.byKey(const ValueKey('studio-startup')), findsNothing);
      expect(
        tester.widget<TextField>(input).controller!.text,
        'draft survives directory outage',
      );
      expect(graph.client.selection.state.selectedProjectId, project);
      final retry = find.byKey(const ValueKey('project-directory-retry'));
      expect(retry, findsOneWidget);
      transport.unavailable = false;
      await tester.tap(retry);
      await pumpClientUntil(
        tester,
        () => graph.client.project.state.projectSync.isReady,
        'project topic baseline after explicit retry',
      );
      await tester.pumpAndSettle();
      expect(retry, findsNothing);
      expect(
        tester.widget<TextField>(input).controller!.text,
        'draft survives directory outage',
      );
      expect(transport.bootstrapCalls, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpClientFuture(
        tester,
        graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
        'explicit directory recovery close',
      );
    },
  );
}

final class _DirectoryFailureTransport extends RecordingDemoTransport {
  bool unavailable = false;
  MultiStreamController<ProductTopicFrame>? _directory;

  void fail() {
    unavailable = true;
    _directory!.addErrorSync(StateError('directory offline'));
  }

  @override
  Stream<ProductTopicFrame> subscribeProductTopic(ProductTopic topic) {
    if (topic is! ProjectDirectoryTopic) {
      return super.subscribeProductTopic(topic);
    }
    if (unavailable) return Stream.error(StateError('directory offline'));
    return Stream<ProductTopicFrame>.multi((controller) {
      _directory = controller;
      final source = super
          .subscribeProductTopic(topic)
          .listen(
            controller.addSync,
            onError: controller.addErrorSync,
            onDone: controller.closeSync,
          );
      controller.onCancel = source.cancel;
    });
  }
}
