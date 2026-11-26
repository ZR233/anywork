import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/frb_startup_host.dart';
import 'package:anywork/src/app/routing/app_route.dart';
import 'package:anywork/src/app/routing/application_router.dart';
import 'package:anywork/src/app/studio_shutdown.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/composer/state/composer_view_state.dart'
    show StartComposerTarget, ThreadComposerTarget;
import 'package:anywork/src/features/conversation/composer/views/prompt_composer_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/settings/statistics/view_models/statistics_repository_provider.dart';
import 'package:anywork/src/infrastructure/frb/statistics/frb_statistics_feed.dart';
import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork/src/infrastructure/frb/studio_update_api.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/lifecycle.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/composer_target_diagnostic.dart';
import 'support/fixture_gate.dart';
import 'support/history_turns.dart';
import 'support/presentation_capture.dart';
import 'support/timeline_observation.dart';

const _first = '请保持第一轮运行，我将继续发送一条消息。';
const _second = '这是运行中的第二条消息，请确认收到。';
const _stage = 'submission-first-running';
const _lifecycle = '请保持这次执行，等待我停止后再显式继续。';
const _nextDraft = '这是下一条尚未发送的草稿，不应被上一条回执清除。';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  final project = Platform.environment['ANYWORK_SUBMISSION_PROJECT']!;
  final output = Platform.environment['ANYWORK_SUBMISSION_OUTPUT']!;
  final provider = Uri.parse(
    Platform.environment['ANYWORK_SUBMISSION_PROVIDER']!,
  );
  if (provider.scheme != 'http' ||
      !const {'127.0.0.1', 'localhost', '::1'}.contains(provider.host) ||
      !provider.hasPort ||
      provider.userInfo.isNotEmpty ||
      provider.hasQuery ||
      provider.hasFragment) {
    throw StateError('Submission fixture must be a strict loopback HTTP URI');
  }
  final captureEnabled =
      Platform.environment['ANYWORK_PRESENTATION_SCREENSHOTS'] == output;
  final clock = Stopwatch()..start();
  final timing = <Map<String, Object?>>[];
  void record(String event, [Map<String, Object?> facts = const {}]) {
    timing.add({
      'event': event,
      'elapsedUs': clock.elapsedMicroseconds,
      ...facts,
    });
  }

  final root = ClientScope(owner: 'message-submission');
  final runtime = FrbRuntimeOwner(startupScope: root.child('startup'));
  final transport = _SubmissionTransport(
    record,
    runtime: runtime,
    contentScope: root.child('transport-content'),
    progressScope: root.child('shutdown-progress'),
  );
  // Same real adapters as the production composition root; only the transport
  // subclass adds explicit test-owned barriers around real calls/delivery.
  final graph = AppGraph(
    scope: root.child('app'),
    closeLifecycleRoot: (budget) async {
      final report = await root.close(budget: budget);
      runtime.recordLifecycleCloseReport(report);
      return report;
    },
    transport: transport,
    acpBusinessPort: FrbAcpBusinessPort(ensureReady: runtime.ensureReady),
    statisticsFeed: const FrbStatisticsFeedPort(),
    updateApi: FrbStudioUpdateApi(ensureReady: runtime.ensureReady),
    startupHost: FrbStudioStartupHost(runtime),
  );
  final container = ProviderContainer(
    overrides: [
      appGraphProvider.overrideWithValue(graph),
      statisticsRepositoryProvider.overrideWithValue(
        graph.statisticsRepository,
      ),
    ],
  );
  var assertionsPassed = false;
  final report = <String, Object?>{
    'scenario': 'message-submission',
    'runner': 'flutter.integration_test',
    'guiPid': pid,
    'pass': false,
    'theme': 'pureStudioTheme/light',
    'timingScope':
        'Monotonic in-process observations with explicit test barriers; '
        'not network latency or a production performance benchmark.',
    'timing': timing,
  };

  setUpAll(() async {
    await graph.initialize();
    expect(graph.client.bootstrapState.value.failure, isNull);
  });
  tearDownAll(() async {
    transport.releaseAll();
    try {
      final shutdown = await runStudioShutdown(
        transport,
        (_) {},
        remainingMs: 30000,
        closeClient: (budget) => graph.close(budget: budget),
        closeRoot: graph.closeLifecycleRoot,
      );
      report['shutdownIssues'] = shutdown.shutdown.issues
          .map((issue) => issue.toString())
          .toList();
      expect(
        shutdown.shutdown.isClean,
        isTrue,
        reason: shutdown.shutdown.issues.toString(),
      );
      expect(shutdown.shutdown.issues, isEmpty);
      expect(
        shutdown.shutdown.persistence,
        isA<DrainedStudioPendingPersistence>(),
      );
      report['shutdown'] = 'completed';
      report['pass'] = assertionsPassed;
    } finally {
      container.dispose();
      final file = File('$output/message-submission.json');
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
        flush: true,
      );
    }
  });

  testWidgets('running conversation echoes before RPC and hands off once', (
    tester,
  ) async {
    final router = createApplicationRouter();
    var firstGateReleased = false;
    void syncRoute() {
      if (router.routerDelegate.currentConfiguration.isEmpty) return;
      final state = router.routerDelegate.state;
      graph.client.selection.beginNavigation();
      graph.setConversationPageVisible(
        state.name == StudioRoute.name ||
            state.name == BotConversationRoute.name,
        threadId: state.name == BotConversationRoute.name
            ? state.pathParameters['threadId']!
            : null,
      );
    }

    router.routerDelegate.addListener(syncRoute);
    tester.testTextInput.register();
    addTearDown(() async {
      transport.releaseAll();
      try {
        if (!firstGateReleased) {
          await fixtureGate(tester, provider, _stage, release: true);
        }
        graph.setConversationPageVisible(false);
        await tester.pumpWidget(const SizedBox());
        expect(
          (await graph.client.conversations.retryCleanup(
            budget: ClientCloseBudget(const Duration(seconds: 5)),
          )).complete,
          isTrue,
        );
      } finally {
        tester.testTextInput.unregister();
        router.routerDelegate.removeListener(syncRoute);
        router.dispose();
      }
    });
    await tester.pumpWidget(
      RepaintBoundary(
        key: presentationCaptureKey,
        child: UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: pureStudioTheme(),
            locale: const Locale('zh'),
            localizationsDelegates: [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      ),
    );
    if (captureEnabled) {
      report['viewport'] = await configurePresentationWindow(tester);
    }
    await graph.client.directoryCommands.openProject(project);
    graph.setConversationPageVisible(true);

    Future<void> until(bool Function() predicate, String reason) async {
      final elapsed = Stopwatch()..start();
      while (!predicate()) {
        if (elapsed.elapsed > const Duration(seconds: 35)) {
          final selection = graph.client.selection.state;
          final selectedThread = selection.selectedThreadId;
          final current = selectedThread == null
              ? null
              : graph.client.conversations.session(selectedThread).state;
          final currentDiagnostic = {
            'hasSnapshot': current?.hasSnapshot,
            'revision': current?.revision,
            'syncPhase': current?.sync.phase.name,
            'syncError': current?.sync.errorMessage,
            'activeTurnId': current?.activeTurn?.turnId,
            'activeInputId': current?.activeTurn?.inputId,
            'activeStatus': current?.activeTurn?.state.status.name,
            'lastTurnId': current?.lastTurn?.turnId,
            'lastStatus': current?.lastTurn?.state.status.name,
          };
          report['readinessFailure'] = {
            'reason': reason,
            'expectedProjectPath': project,
            'projectId': selection.selectedProjectId,
            'threadId': selection.selectedThreadId,
            'needsOpen': selection.needsOpen,
            'current': currentDiagnostic,
            'route': router.routeInformationProvider.value.uri.toString(),
            'projects': [
              for (final item
                  in graph.client.project.state.projects?.values ?? [])
                {'id': item.id, 'path': item.path},
            ],
            'inputs': find
                .byKey(const ValueKey('composer-input'))
                .evaluate()
                .length,
            'composers': [
              for (final composer in tester.widgetList<PromptComposerView>(
                find.byType(PromptComposerView),
              ))
                {
                  'target': composerTargetDiagnostic(composer.targetKey),
                  'enabled': composer.state.enabled,
                  'blocker': composer.state.blocker?.toString(),
                  'failure': composer.state.failure?.toString(),
                },
            ],
          };
          try {
            await capturePresentation(
              tester,
              'submission-readiness-failed.png',
            );
          } catch (error) {
            report['readinessCaptureError'] = error.toString();
          }
          fail('Timed out: $reason; Current: ${jsonEncode(currentDiagnostic)}');
        }
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);
      }
    }

    Future<void> submit(String text) async {
      final input = find.byKey(const ValueKey('composer-input'));
      await until(() {
        final selection = graph.client.selection.state;
        final selected = graph.client.project.state.projects?.values
            .where((item) => item.id == selection.selectedProjectId)
            .firstOrNull;
        final view = find.byType(PromptComposerView);
        // The harness may use a Windows device path for the same local directory.
        if (selected == null ||
            !FileSystemEntity.identicalSync(selected.path, project) ||
            selection.needsOpen ||
            view.evaluate().length != 1 ||
            input.evaluate().length != 1) {
          return false;
        }
        final composer = tester.widget<PromptComposerView>(view);
        return composer.state.enabled &&
            switch (composer.targetKey) {
              ThreadComposerTarget(:final threadId) =>
                threadId == selection.selectedThreadId,
              StartComposerTarget(:final workspaceId) =>
                selection.selectedThreadId == null &&
                    workspaceId == selection.selectedProjectId,
              _ => false,
            };
      }, 'production composer ready for the selected project');
      await tester.enterText(input, text);
      await tester.pump();
      expect(tester.widget<TextField>(input).controller!.text, text);
      if (text == _first) {
        await capturePresentation(tester, 'submission-editing.png');
      }
      record(text == _second ? 'second-ui-submit' : 'first-ui-submit');
      await tester.tap(find.byKey(const ValueKey('composer-submit')));
      await tester.pump();
    }

    await submit(_first);
    await fixtureGate(tester, provider, _stage);
    await until(
      () => graph.client.selection.state.selectedThreadId != null,
      'real conversation selected',
    );
    final threadId = graph.client.selection.state.selectedThreadId!;
    final owner = graph.client.drafts.composer(threadId);
    final observed = TimelineObservation(
      tester,
      () => graph.timeline.lease(threadId)!,
    );
    StudioTurnView? firstTurn;
    await until(() {
      if (graph.timeline.lease(threadId) == null) return false;
      final turn = graph.client.conversations
          .session(threadId)
          .state
          .activeTurn;
      if (turn?.state.status != StudioTurnStatus.running ||
          turn?.inputId == null) {
        return false;
      }
      firstTurn = turn;
      return true;
    }, 'first canonical running Turn with its accepted input');
    expect(firstTurn!.inputId, isNotNull);
    expect(firstTurn!.state.status, StudioTurnStatus.running);
    record('first-model-gate-reached', {'turnId': firstTurn!.turnId});

    StudioTurnView? activeTurn() {
      final state = graph.client.conversations.session(threadId).state;
      return state.activeTurn;
    }

    transport.arm();
    await submit(_second);
    await until(
      () =>
          transport.blockedInput != null &&
          owner.submissions.value.any((item) => item.text == _second),
      'second submission entered test RPC barrier',
    );
    final inputId = transport.blockedInput!.inputId;
    final card = find.byKey(ValueKey('composer-submission:$inputId'));
    await until(
      () => card.hitTestable().evaluate().length == 1,
      'pending card painted in the live timeline',
    );
    expect(
      owner.submissions.value.single.phase,
      ComposerSubmissionPhase.sending,
    );
    expect(find.text('正在发送'), findsNothing);
    expect(find.byTooltip('正在发送'), findsOneWidget);
    expect(transport.realSecondRpcStarted, isFalse);
    expect(transport.receipt, isNull);
    expect(
      observed.main.whereType<TimelineUserMessage>().where(
        (block) => block.inputId == inputId,
      ),
      isEmpty,
    );
    record('pending-painted-before-real-rpc', {'inputId': inputId});
    await capturePresentation(tester, 'submission-pending.png');
    final input = find.byKey(const ValueKey('composer-input'));
    await tester.enterText(input, _nextDraft);
    await tester.pump();
    expect(tester.widget<TextField>(input).controller!.text, _nextDraft);
    await capturePresentation(tester, 'submission-next-draft.png');

    transport.releaseRpc();
    await until(
      () =>
          transport.receipt != null &&
          find.byTooltip('已收到，等待同步').evaluate().length == 1 &&
          owner.submissions.value.any(
            (item) =>
                item.inputId == inputId &&
                item.phase == ComposerSubmissionPhase.accepted,
          ),
      'real submit receipt and accepted local echo',
    );
    expect(transport.receipt!.inputId, inputId);
    await until(() => transport.heldFrames > 0, 'real feed frame held');
    expect(find.text('已收到，等待同步'), findsNothing);
    expect(find.byTooltip('已收到，等待同步'), findsOneWidget);
    expect(tester.widget<TextField>(input).controller!.text, _nextDraft);
    expect(card.hitTestable(), findsOneWidget);
    expect(
      observed.main.whereType<TimelineUserMessage>().where(
        (block) => block.inputId == inputId,
      ),
      isEmpty,
    );
    record('received-painted-before-feed-release', {'inputId': inputId});
    await capturePresentation(tester, 'submission-received.png');

    transport.releaseFeed();
    final historyRows = await waitForHistoryRows(
      feeds: transport,
      threadId: threadId,
      matches: (rows) {
        final matches = rows.where((entry) {
          return entry is TimelineUserMessage && entry.inputId == inputId;
        }).toList();
        if (matches.length > 1) {
          throw StateError(
            'History admitted duplicate input rows for $inputId',
          );
        }
        return matches.length == 1;
      },
      description: 'one canonical History input row for $inputId',
    );
    expect(
      historyRows.where((entry) {
        return entry is TimelineUserMessage && entry.inputId == inputId;
      }),
      hasLength(1),
    );
    await until(
      () =>
          owner.submissions.value.isEmpty &&
          card.evaluate().isEmpty &&
          observed.main
                  .whereType<TimelineUserMessage>()
                  .where((block) => block.inputId == inputId)
                  .length ==
              1,
      'one canonical input replaces the local echo',
    );
    expect(card, findsNothing);
    final canonical = observed.main
        .whereType<TimelineUserMessage>()
        .singleWhere((block) => block.inputId == inputId);
    final historical = historyRows.whereType<TimelineUserMessage>().singleWhere(
      (item) => item.inputId == inputId,
    );
    expect(canonical.id, historical.id);
    expect(canonical.seq, historical.seq);
    expect(canonical.text, _second);
    await observed.revealSingle(canonical);
    final row = observed.itemRow(canonical.id);
    final canonicalText = find.descendant(
      of: row,
      matching: find.text(_second, findRichText: true),
    );
    await observed.reveal(canonicalText, canonical.id);
    expect(canonicalText.hitTestable(), findsOneWidget);
    expect(tester.widget<ChatItemView>(row).item.id, historical.id);
    expect(canonicalText, findsOneWidget);
    expect(tester.widget<TextField>(input).controller!.text, _nextDraft);
    record('canonical-painted-without-duplicate', {
      'inputId': inputId,
      'blockId': canonical.id,
      'recordId': historical.id,
      'heldFeedEvent': transport.lastHeldEvent,
    });
    await capturePresentation(tester, 'submission-canonical.png');
    await fixtureGate(tester, provider, _stage, release: true);
    firstGateReleased = true;
    final secondTurn = await waitForCompletedTurn(
      feeds: transport,
      threadId: threadId,
      matches: (head) => head.inputId == inputId,
      description: 'canonical completed Turn for the handed-off second input',
      timeout: const Duration(minutes: 2),
    );
    await until(() {
      return observed.main.whereType<TimelineAssistantText>().any(
        (item) => item.turnId == secondTurn.turnId,
      );
    }, 'second real model turn completed after interrupting the first');
    await until(() {
      final state = graph.client.conversations.session(threadId).state;
      final storage = state.storage;
      return state.runtime?.execution == null &&
          storage?.acceptedSequence != null &&
          storage?.durableSequence != null &&
          storage!.durableSequence! >= storage.acceptedSequence!;
    }, 'original journey has no execution and its accepted history is durable');
    expect(tester.widget<TextField>(input).controller!.text, _nextDraft);

    // Keep the same real bridge, Thread and persisted history. The coordinator
    // replaces only the now-complete strict provider script on the same address.
    await File('$output/submission-lifecycle-requested')
        .writeAsString('ready\n');
    await until(
      () => File('$output/submission-lifecycle-ready').existsSync(),
      'strict lifecycle provider listening on the original address',
    );
    await submit(_lifecycle);
    await until(() {
      final state = graph.client.conversations.session(threadId).state;
      final execution = state.runtime?.execution;
      final turn = state.activeTurn;
      return File('$output/submission-stop-reached').existsSync() &&
          execution?.phase == AgentExecutionPhase.running &&
          turn?.turnId == execution?.turnId &&
          turn?.inputId != null &&
          turn?.state.status == StudioTurnStatus.running;
    }, 'real execution is running inside the provider gate');
    final session = graph.client.conversations.session(threadId);
    final stoppedExecution = session.state.runtime!.execution!;
    final stoppedTurnId = stoppedExecution.turnId!;
    expect(activeTurn()!.turnId, stoppedTurnId);
    expect(activeTurn()!.state.isTerminal, isFalse);
    expect(tester.widget<TextField>(input).controller!.text, isEmpty);

    // Hold only the real stop RPC, not a fabricated stop result. This gives a
    // stable pending frame while the canonical execution is genuinely running.
    transport.armStop();
    final pendingStop = find.byKey(const ValueKey('composer-stop'));
    await tester.tap(pendingStop);
    await tester.pump();
    await until(() {
      final command = tester
          .widget<PromptComposerView>(find.byType(PromptComposerView))
          .state
          .stopCommand;
      return transport.blockedStopExecutionId == stoppedExecution.id &&
          pendingStop.hitTestable().evaluate().length == 1 &&
          tester.widget<IconButton>(pendingStop).onPressed == null &&
          find
                  .descendant(
                    of: pendingStop,
                    matching: find.byType(CircularProgressIndicator),
                  )
                  .evaluate()
                  .length ==
              1 &&
          command?.target.label == stoppedExecution.id &&
          command?.isPending == true &&
          command?.accepted == false &&
          session.state.runtime?.execution?.id == stoppedExecution.id &&
          session.state.runtime?.execution?.phase ==
              AgentExecutionPhase.running;
    }, 'production stop action pending for the frozen execution identity');
    expect(transport.stopReceipt, isNull);
    expect(session.state.runtime!.execution!.id, stoppedExecution.id);
    expect(activeTurn()!.state.isTerminal, isFalse);
    await capturePresentation(tester, 'submission-stopping.png');
    expect(session.state.runtime!.execution!.id, stoppedExecution.id);
    record('stop-pending-not-terminal', {'executionId': stoppedExecution.id});
    transport.releaseStop();
    await until(
      () => transport.stopReceipt != null,
      'real stop receipt returned',
    );
    expect(transport.stopReceipt!.executionId, stoppedExecution.id);
    expect(transport.stopReceipt!.threadId, threadId);
    expect(transport.stopReceipt!.stopped, isTrue);
    record('stop-accepted', {'executionId': stoppedExecution.id});
    final cancelledTurn = await waitForTurn(
      feeds: transport,
      threadId: threadId,
      matches: (head) => head.turnId == stoppedTurnId,
      isExpectedTerminal: (turn) =>
          turn.state.status == StudioTurnStatus.cancelled,
      description: 'canonical cancelled stopped Turn',
    );
    expect(
      cancelledTurn.state,
      isA<CancelledStudioTurnState>().having(
        (state) => state.cause,
        'cause',
        isA<InterruptedTurnCancellation>(),
      ),
    );
    await waitForHistoryRows(
      feeds: transport,
      threadId: threadId,
      matches: (rows) => rows.whereType<TimelineTurnOutcome>().any(
        (outcome) =>
            outcome.turnId == stoppedTurnId &&
            outcome.inputId == cancelledTurn.inputId &&
            outcome.outcome == 'interrupted',
      ),
      description: 'history interruption receipt for the exact stopped Turn',
    );
    // A successful RPC is NOT the end condition: wait for the canonical
    // execution to disappear, the exact Turn to terminate and its continuation.
    await until(
      () =>
          session.state.runtime?.execution == null &&
          session.state.runtime?.continuation?.sourceTurnId == stoppedTurnId &&
          session.state.runtime?.continuation != null &&
          find.byKey(const ValueKey('composer-continue')).evaluate().length ==
              1,
      'stopped execution ended and canonical continuation is available',
    );
    final continuation = session.state.runtime!.continuation!;
    expect(continuation.reason, ContinuationReason.userStop);
    expect(find.byKey(const ValueKey('composer-stop')), findsNothing);
    expect(find.byKey(const ValueKey('composer-stopping')), findsNothing);
    await capturePresentation(tester, 'submission-stopped.png');
    expect(session.state.runtime!.execution, isNull);
    expect(session.state.runtime!.continuation!.id, continuation.id);
    expect(File('$output/submission-resume-reached').existsSync(), isFalse);
    record('execution-ended-with-continuation', {
      'executionId': stoppedExecution.id,
      'turnId': stoppedTurnId,
      'continuationId': continuation.id,
    });

    // Continue consumes the exact canonical token and starts a new execution
    // without submitting a real or synthetic input.
    final submittedPromptCount = transport.submittedPromptCount;
    await tester.tap(find.byKey(const ValueKey('composer-continue')));
    await tester.pump();
    await until(() {
      final execution = session.state.runtime?.execution;
      final turn = session.state.activeTurn;
      return File('$output/submission-resume-reached').existsSync() &&
          execution?.phase == AgentExecutionPhase.running &&
          execution?.id != stoppedExecution.id &&
          turn?.turnId == execution?.turnId &&
          turn?.inputId == null &&
          turn?.state.status == StudioTurnStatus.running;
    }, 'explicit continuation starts a new real execution');
    final resumedExecution = session.state.runtime!.execution!;
    expect(resumedExecution.turnId, isNot(stoppedTurnId));
    expect(activeTurn()!.turnId, resumedExecution.turnId);
    expect(activeTurn()!.inputId, isNull);
    expect(transport.submittedPromptCount, submittedPromptCount);
    expect(activeTurn()!.state.isTerminal, isFalse);
    expect(find.byKey(const ValueKey('composer-stop')), findsOneWidget);
    expect(find.byKey(const ValueKey('composer-continue')), findsNothing);
    expect(tester.widget<TextField>(input).controller!.text, isEmpty);
    await capturePresentation(tester, 'submission-resumed.png');
    expect(session.state.runtime!.execution!.id, resumedExecution.id);
    record('new-execution-running', {
      'executionId': resumedExecution.id,
      'turnId': resumedExecution.turnId,
      'continuationId': continuation.id,
    });
    await File('$output/submission-stop-release').writeAsString('release\n');
    await File('$output/submission-resume-release').writeAsString('release\n');
    final resumedTurn = await waitForCompletedTurn(
      feeds: transport,
      threadId: threadId,
      matches: (head) => head.turnId == resumedExecution.turnId,
      description: 'canonical completed resumed Turn',
      timeout: const Duration(minutes: 2),
    );
    expect(resumedTurn.state.status, StudioTurnStatus.completed);
    await until(
      () =>
          session.state.runtime?.execution == null &&
          session.state.runtime?.continuation == null &&
          session.state.storage?.acceptedSequence != null &&
          session.state.storage?.durableSequence != null &&
          session.state.storage!.durableSequence! >=
              session.state.storage!.acceptedSequence!,
      'resumed execution completes, consumes the continuation and is durable',
    );
    report['lifecycle'] = {
      'stoppedExecutionId': stoppedExecution.id,
      'stoppedTurnId': stoppedTurnId,
      'continuationId': continuation.id,
      'resumedExecutionId': resumedExecution.id,
      'resumedTurnId': resumedExecution.turnId,
      'completed': true,
    };
    report['inputId'] = inputId;
    report['firstTurnId'] = firstTurn!.turnId;
    report['heldFrames'] = transport.heldFrames;
    if (captureEnabled) {
      for (final name in [
        'submission-pending.png',
        'submission-received.png',
        'submission-canonical.png',
        'submission-editing.png',
        'submission-next-draft.png',
        'submission-stopping.png',
        'submission-stopped.png',
        'submission-resumed.png',
      ]) {
        expect(await File('$output/$name').length(), greaterThan(0));
      }
    }
    assertionsPassed = true;
  });
}

/// The gate delays real work, not its outcome. No receipt or frame is synthesized.
class _SubmissionTransport extends FrbStudioTransport {
  _SubmissionTransport(
    this.record, {
    required super.runtime,
    required super.contentScope,
    required super.progressScope,
  });
  final void Function(String, [Map<String, Object?>]) record;
  Completer<void>? _rpc;
  Completer<void>? _feed;
  Completer<void>? _stopRpc;
  String? blockedStopExecutionId;
  StopThreadCommandReply? stopReceipt;
  StudioPromptInput? blockedInput;
  SubmitPromptReceipt? receipt;
  bool realSecondRpcStarted = false;
  int submittedPromptCount = 0;
  int heldFrames = 0;
  String? lastHeldEvent;

  void arm() {
    _rpc = Completer<void>();
  }

  void releaseRpc() {
    if (_rpc case final gate? when !gate.isCompleted) {
      record('real-rpc-released');
      gate.complete();
    }
  }

  void releaseFeed() {
    if (_feed case final gate? when !gate.isCompleted) {
      record('real-feed-released');
      gate.complete();
    }
  }

  void releaseAll() {
    releaseRpc();
    releaseFeed();
    releaseStop();
  }

  void armStop() => _stopRpc = Completer<void>();

  void releaseStop() {
    if (_stopRpc case final gate? when !gate.isCompleted) {
      gate.complete();
    }
  }

  @override
  Future<StopThreadCommandReply> stopThread(
    String threadId,
    String executionId, {
    required OperationId operationId,
  }) async {
    blockedStopExecutionId = executionId;
    await _stopRpc!.future;
    final reply = await super.stopThread(
      threadId,
      executionId,
      operationId: operationId,
    );
    stopReceipt = reply;
    return reply;
  }

  @override
  Future<SubmitPromptReceipt> submitPrompt(
    String threadId,
    StudioPromptInput input, {
    required int expectedModelRouteRevision,
  }) async {
    submittedPromptCount++;
    if (input.text != _second) {
      return super.submitPrompt(
        threadId,
        input,
        expectedModelRouteRevision: expectedModelRouteRevision,
      );
    }
    blockedInput = input;
    // Arm only after beforeSubmit has finished any real live-feed replacement.
    _feed = Completer<void>();
    record('test-rpc-barrier-entered', {'inputId': input.inputId});
    await _rpc!.future;
    realSecondRpcStarted = true;
    record('real-rpc-started');
    final result = await super.submitPrompt(
      threadId,
      input,
      expectedModelRouteRevision: expectedModelRouteRevision,
    );
    receipt = result;
    record('real-receipt-returned', {'inputId': result.inputId});
    return result;
  }

  Future<ConversationFeedEvent> deliver(ConversationFeedEvent event) async {
    final gate = _feed;
    if (gate != null && !gate.isCompleted) {
      heldFrames++;
      lastHeldEvent = event.runtimeType.toString();
      record('real-response-held', {'event': lastHeldEvent});
      await gate.future;
    }
    return event;
  }

  @override
  Future<ConversationFeedHandle> openConversationFeed(
    String threadId, {
    int initialLimit = 50,
  }) async => _SubmissionConversationFeed(
    await super.openConversationFeed(threadId, initialLimit: initialLimit),
    this,
  );
}

/// Delays real feed delivery, including InputPresented, until explicitly released.
/// Closing releases the local barrier before joining the original feed.
class _SubmissionConversationFeed implements ConversationFeedHandle {
  _SubmissionConversationFeed(this.original, this.owner);
  final ConversationFeedHandle original;
  final _SubmissionTransport owner;
  @override
  String get threadId => original.threadId;
  @override
  LiveStatusSnapshot get liveStatusSnapshot => original.liveStatusSnapshot;
  @override
  SessionMetaSnapshot get sessionMetaSnapshot => original.sessionMetaSnapshot;
  @override
  late final Stream<ConversationFeedEvent> events = original.events.asyncMap(
    owner.deliver,
  );
  @override
  Future<TimelinePatch> loadOlder({required String cursor, int limit = 50}) =>
      original.loadOlder(cursor: cursor, limit: limit);
  @override
  Future<List<WorkGroupMember>> loadWorkGroupMembers({
    int? afterSeq,
    int? beforeSeq,
  }) => original.loadWorkGroupMembers(afterSeq: afterSeq, beforeSeq: beforeSeq);
  @override
  Future<BodyWindow> readBodyWindow({
    required BodyRef reference,
    required int offset,
    required int maxBytes,
  }) => original.readBodyWindow(
    reference: reference,
    offset: offset,
    maxBytes: maxBytes,
  );
  @override
  Future<SessionDetailWindow> readSessionDetail({
    required SessionDetailKind kind,
    required int offset,
    required int maxBytes,
  }) => original.readSessionDetail(
    kind: kind,
    offset: offset,
    maxBytes: maxBytes,
  );

  @override
  Future<TimelinePatch> resetToLatest({int limit = 50}) =>
      original.resetToLatest(limit: limit);
  @override
  void requestClose() {
    owner.releaseFeed();
    original.requestClose();
  }

  @override
  Future<void> close() {
    requestClose();
    return original.close();
  }
}
