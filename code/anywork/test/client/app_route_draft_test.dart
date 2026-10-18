import 'dart:async';

import 'package:anywork/src/app/anywork_app.dart';
import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/studio_host_lifecycle.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/platform/host_app_icons.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_demo_transport.dart';
import 'support/pump_client_future.dart';

void main() {
  testWidgets(
    'Settings retains drafts and observes a Turn completed while hidden',
    (tester) async {
      final transport = _RouteTurnTransport();
      final graph = AppGraph(
        transport: transport,
        clientId: 'route-draft-owner',
      );
      final exitFinished = Completer<void>();
      final exitCodes = <int>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(StudioHostLifecycle.channel, (
        call,
      ) async {
        switch (call.method) {
          case 'beginExit':
            return 30000;
          case 'finishExit':
            exitCodes.add(
              (call.arguments as Map<Object?, Object?>)['exitCode']! as int,
            );
            if (!exitFinished.isCompleted) exitFinished.complete();
            return null;
          case 'updateExitDiagnostics':
          case 'configureDiagnostics':
            return null;
          default:
            throw StateError('Unexpected host lifecycle call: ${call.method}');
        }
      });
      messenger.setMockMethodCallHandler(hostAppsChannel, (_) async => null);
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() async {
        // Keep host mocks installed while an early assertion failure unmounts
        // the real lifecycle coordinator and joins its shared exit operation.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        final exiting = StudioExitCoordinator.requestExit();
        await pumpClientFuture(tester, exiting, 'teardown exit');
        await pumpClientFuture(
          tester,
          graph.close(deadline: _deadline()),
          'teardown graph close',
        );
        messenger.setMockMethodCallHandler(StudioHostLifecycle.channel, null);
        messenger.setMockMethodCallHandler(hostAppsChannel, null);
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appGraphProvider.overrideWithValue(graph)],
          child: const AnyworkApp(),
        ),
      );
      // Await the production bootstrap owner, not a timer guessed from frame count.
      await pumpClientFuture(tester, graph.client.bootstrap(), 'bootstrap');
      await tester.pumpAndSettle();
      expect(find.byKey(StudioDriverKeys.startPage), findsOneWidget);
      expect(transport.bootstrapCalls, 1);
      final projectId = graph.client.selection.state.selectedProjectId!;
      final startOwner = graph.client.startDraft;
      await tester.enterText(
        find.byKey(StudioDriverKeys.composerInput),
        'start draft entered before Settings',
      );
      await tester.pump();
      final startRevision = startOwner.state.revision;

      await _settingsRoundTrip(tester);

      expect(graph.client.startDraft, same(startOwner));
      expect(startOwner.state.revision, startRevision);
      expect(
        startOwner.state.forProject(projectId).text,
        'start draft entered before Settings',
      );
      expect(_composerText(tester), 'start draft entered before Settings');
      expect(
        transport.timelines,
        isEmpty,
        reason: 'Settings navigation does not create a Thread',
      );

      await tester.tap(find.byKey(StudioDriverKeys.threadRow('thread-main')));
      await pumpClientUntil(
        tester,
        () =>
            graph.client
                .existingSession('thread-main')
                ?.timeline
                .lastDeliveredFrame !=
            null,
        'selected Thread timeline baseline',
      );
      await tester.pumpAndSettle();
      final session = graph.client.existingSession('thread-main')!;
      final attemptId = session.timeline.currentAttemptId?.value;
      final connection = transport.timelines.single;
      final composer = graph.client.composer('thread-main');
      final startedAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final running = transport.emitTurn(
        RunningStudioTurnState(
          startedAt: startedAt,
          activity: StudioTurnActivity.responding,
        ),
      );
      await pumpClientUntil(
        tester,
        () => session.state.activeTurn == running,
        'running Turn before Settings',
      );
      await tester.pump();
      expect(find.byKey(StudioDriverKeys.composerStop), findsOneWidget);
      await tester.enterText(
        find.byKey(StudioDriverKeys.composerInput),
        'Thread draft entered before Settings',
      );
      await tester.pump();
      final composerStamp = composer.stamp;

      await _settingsRoundTrip(
        tester,
        whileSettingsOpen: () async {
          // This notification must reach the application owner with both of its
          // business observers hidden by the real Settings route.
          expect(find.byKey(StudioDriverKeys.composerInput), findsNothing);
          expect(find.byKey(StudioDriverKeys.timeline), findsNothing);
          expect(session.state.activeTurn, running);
          expect(transport.runtimeSubscriptions, 1);
          expect(transport.runtimeCancellations, 0);
          final completed = transport.emitTurn(
            CompletedStudioTurnState(
              startedAt: startedAt,
              completedAt: startedAt + 1,
              completion: StudioTurnCompletion.normal,
            ),
          );
          await pumpClientUntil(
            tester,
            () =>
                session.state.workspace?.latestTurn == completed &&
                session.state.activeTurn == null,
            'completed Turn while Settings hides the workspace',
          );
          expect(find.byKey(StudioDriverKeys.settingsPage), findsOneWidget);
          expect(find.byKey(StudioDriverKeys.composerInput), findsNothing);
          expect(find.byKey(StudioDriverKeys.timeline), findsNothing);
          expect(graph.client.existingSession('thread-main'), same(session));
          expect(session.timeline.currentAttemptId?.value, attemptId);
          expect(connection.requestCloseCalls, 0);
          expect(connection.closeCalls, 0);
        },
      );

      expect(graph.client.composer('thread-main'), same(composer));
      expect(composer.stamp, composerStamp);
      expect(composer.state.draft, 'Thread draft entered before Settings');
      expect(_composerText(tester), 'Thread draft entered before Settings');
      expect(session.state.activeTurn, isNull);
      expect(
        session.state.workspace?.latestTurn?.state,
        isA<CompletedStudioTurnState>(),
      );
      expect(find.byKey(StudioDriverKeys.composerStop), findsNothing);
      final submit = find.byKey(StudioDriverKeys.composerSubmit);
      expect(submit, findsOneWidget);
      expect(
        tester.widget<IconButton>(submit).tooltip,
        AppLocalizations.of(tester.element(submit)).composerSend,
        reason: 'the visible composer must no longer display send-and-continue',
      );
      expect(
        startOwner.state.forProject(projectId).text,
        'start draft entered before Settings',
      );
      expect(session.timeline.currentAttemptId?.value, attemptId);
      expect(session.timeline.lastDeliveredFrame != null, isTrue);
      expect(transport.timelines, hasLength(1));
      expect(connection.requestCloseCalls, 0);
      expect(connection.closeCalls, 0);
      expect(transport.bootstrapCalls, 1);
      expect(transport.runtimeSubscriptions, 1);
      expect(transport.runtimeCancellations, 0);

      // Unmount through the real lifecycle coordinator. Only the host channel is
      // mocked, so the test cannot ask the native runner to exit this test process.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await pumpClientUntil(
        tester,
        () => exitFinished.isCompleted,
        'host finishExit',
      );
      await pumpClientFuture(
        tester,
        StudioExitCoordinator.requestExit(),
        'repeat exit',
      );
      expect(exitCodes, [0]);
      expect(
        (await pumpClientFuture(
          tester,
          graph.close(deadline: _deadline()),
          'repeat graph close',
        )).complete,
        isTrue,
      );
      expect(connection.joined.isCompleted, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _settingsRoundTrip(
  WidgetTester tester, {
  Future<void> Function()? whileSettingsOpen,
}) async {
  await tester.tap(find.byKey(StudioDriverKeys.settingsOpen));
  await tester.pumpAndSettle();
  expect(find.byKey(StudioDriverKeys.settingsPage), findsOneWidget);
  for (final tab in ['general', 'agents', 'providers']) {
    final target = find.byKey(StudioDriverKeys.settingsTab(tab));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(find.byKey(StudioDriverKeys.settingsPage), findsOneWidget);
  }
  await whileSettingsOpen?.call();
  await tester.tap(find.byKey(StudioDriverKeys.settingsBack));
  await tester.pumpAndSettle();
  expect(find.byKey(StudioDriverKeys.settingsPage), findsNothing);
}

String _composerText(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(StudioDriverKeys.composerInput))
    .controller!
    .text;

DateTime _deadline() => DateTime.now().add(const Duration(seconds: 5));

/// The fixture wraps the production Demo state subscription, adding only a
/// controllable producer of typed Turn notifications. It adds no UI observer,
/// does not call a Client setter, and never claims to exercise native FRB.
final class _RouteTurnTransport extends RecordingDemoTransport {
  MultiStreamController<ThreadStreamFrame>? _runtime;
  int? _revision;
  int _turnUpdates = 0;
  int runtimeSubscriptions = 0;
  int runtimeCancellations = 0;

  @override
  Stream<ThreadStreamFrame> subscribeThread(String threadId) {
    if (threadId != 'thread-main') return super.subscribeThread(threadId);
    return Stream<ThreadStreamFrame>.multi((controller) {
      runtimeSubscriptions++;
      _runtime = controller;
      final owner = super
          .subscribeThread(threadId)
          .listen(
            (frame) {
              _revision = switch (frame) {
                ThreadSnapshotFrame(:final workspace) => workspace.revision,
                ThreadNotificationFrame(:final revision) => revision,
                ThreadResyncRequiredFrame() => _revision,
              };
              controller.addSync(frame);
            },
            onError: controller.addErrorSync,
            onDone: controller.closeSync,
          );
      controller.onPause = owner.pause;
      controller.onResume = owner.resume;
      controller.onCancel = () async {
        runtimeCancellations++;
        if (identical(_runtime, controller)) _runtime = null;
        await owner.cancel();
      };
    });
  }

  StudioTurnView emitTurn(StudioTurnState state) {
    final runtime = _runtime;
    final base = _revision;
    if (runtime == null || base == null) {
      throw StateError('The selected Thread must own its state subscription');
    }
    final revision = base + 1;
    _revision = revision;
    final turn = StudioTurnView(
      turnId: 'settings-route-turn',
      threadId: 'thread-main',
      revision: revision,
      state: state,
      updatedAt: DateTime.now().add(Duration(seconds: ++_turnUpdates)),
    );
    runtime.addSync(
      ThreadNotificationFrame(
        threadId: 'thread-main',
        baseRevision: base,
        revision: revision,
        update: ThreadTurnUpdate(turn),
      ),
    );
    return turn;
  }
}
