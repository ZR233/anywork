import 'support/display_record_observation.dart';

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
import 'package:anywork_client/studio_client.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/fixture_gate.dart';
import 'support/composer_target_diagnostic.dart';
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
  if (Platform.environment['ANYWORK_PRESENTATION_SCREENSHOTS'] != output) {
    throw StateError('Submission acceptance requires real presentation PNGs');
  }
  final clock = Stopwatch()..start();
  final timing = <Map<String, Object?>>[];
  void record(String event, [Map<String, Object?> facts = const {}]) {
    timing.add({
      'event': event,
      'elapsedUs': clock.elapsedMicroseconds,
      ...facts,
    });
  }

  final transport = _SubmissionTransport(record);
  // Same real adapters as the production composition root; only the transport
  // subclass adds explicit test-owned barriers around real calls/delivery.
  final graph = AppGraph(
    transport: transport,
    statisticsFeed: const FrbStatisticsFeedPort(),
    updateApi: const FrbStudioUpdateApi(),
    startupHost: FrbStudioStartupHost(),
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
        closeClient: (deadline) => graph.close(deadline: deadline),
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
            deadline: DateTime.now().add(const Duration(seconds: 5)),
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
    report['viewport'] = await configurePresentationWindow(tester);
    await graph.client.directoryCommands.openProject(project);
    graph.setConversationPageVisible(true);

    Future<void> until(bool Function() predicate, String reason) async {
      final elapsed = Stopwatch()..start();
      while (!predicate()) {
        if (elapsed.elapsed > const Duration(seconds: 35)) {
          final selection = graph.client.selection.state;
          report['readinessFailure'] = {
            'reason': reason,
            'expectedProjectPath': project,
            'projectId': selection.selectedProjectId,
            'threadId': selection.selectedThreadId,
            'needsOpen': selection.needsOpen,
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
          fail('Timed out: $reason');
        }
        await tester.pump(const Duration(milliseconds: 16));
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
    await until(
      () =>
          graph.timeline.lease(threadId) != null &&
          observed.singleBlocks.any(
            (block) =>
                (block.body as SingleDisplayBlock).record.atom.source
                    is InputChatSource,
          ),
      'first real InputChatSource applied',
    );
    StudioTurnView? latestTurn() {
      final state = graph.client.conversations.session(threadId).state;
      return state.activeTurn ?? state.lastTurn;
    }

    await until(
      () => latestTurn()?.state.status == StudioTurnStatus.running,
      'first canonical running Turn delivered',
    );
    final firstTurn = latestTurn()!;
    expect(firstTurn.state.status, StudioTurnStatus.running);
    record('first-model-gate-reached', {'turnId': firstTurn.turnId});

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
      observed.singleBlocks.where(
        (block) =>
            (block.body as SingleDisplayBlock).record.atom.source ==
            InputChatSource(inputId: inputId),
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
      observed.singleBlocks.where(
        (block) =>
            (block.body as SingleDisplayBlock).record.atom.source ==
            InputChatSource(inputId: inputId),
      ),
      isEmpty,
    );
    record('received-painted-before-feed-release', {'inputId': inputId});
    await capturePresentation(tester, 'submission-received.png');

    transport.releaseFeed();
    await until(
      () =>
          owner.submissions.value.isEmpty &&
          card.evaluate().isEmpty &&
          observed.singleBlocks
                  .where(
                    (block) =>
                        (block.body as SingleDisplayBlock).record.atom.source ==
                        InputChatSource(inputId: inputId),
                  )
                  .length ==
              1,
      'one canonical input replaces the local echo',
    );
    expect(card, findsNothing);
    final canonical = observed.singleBlocks.singleWhere(
      (block) =>
          (block.body as SingleDisplayBlock).record.atom.source ==
          InputChatSource(inputId: inputId),
    );
    final canonicalBody = canonical.body as SingleDisplayBlock;
    expect(completedOriginalId(canonicalBody.record), isNotNull);
    await observed.revealSingle(canonical);
    final row = observed.itemRow(canonical.id);
    expect(row.hitTestable(), findsOneWidget);
    expect(
      tester.widget<ChatItemView>(row).item.atom!.source,
      InputChatSource(inputId: inputId),
    );
    expect(find.text(_second), findsOneWidget);
    expect(tester.widget<TextField>(input).controller!.text, _nextDraft);
    record('canonical-painted-without-duplicate', {
      'inputId': inputId,
      'blockId': canonical.id,
      'recordId': completedOriginalId(canonicalBody.record),
      'deliverySequence': transport.lastHeldSequence,
    });
    await capturePresentation(tester, 'submission-canonical.png');
    await fixtureGate(tester, provider, _stage, release: true);
    firstGateReleased = true;
    await until(() {
      final turn = latestTurn();
      return turn != null &&
          turn.turnId != firstTurn.turnId &&
          turn.state.status == StudioTurnStatus.completed &&
          observed.singleBlocks.any(
            (block) =>
                (block.body as SingleDisplayBlock).record.atom.source ==
                    ForegroundTurnChatSource(turnId: turn.turnId) &&
                (block.body as SingleDisplayBlock).record.atom.kind ==
                    ChatAtomKind.text,
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
    await until(
      () =>
          File('$output/submission-stop-reached').existsSync() &&
          graph.client.conversations
                  .session(threadId)
                  .state
                  .runtime
                  ?.execution
                  ?.phase ==
              AgentExecutionPhase.running,
      'real execution is running inside the provider gate',
    );
    final session = graph.client.conversations.session(threadId);
    final stoppedExecution = session.state.runtime!.execution!;
    final stoppedTurnId = stoppedExecution.turnId!;
    expect(latestTurn()!.turnId, stoppedTurnId);
    expect(latestTurn()!.state.isTerminal, isFalse);
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
    expect(latestTurn()!.state.isTerminal, isFalse);
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
    // A successful RPC is NOT the end condition: wait for the canonical
    // execution to disappear, the exact Turn to terminate and its continuation.
    await until(
      () =>
          session.state.runtime?.execution == null &&
          session.state.runtime?.continuation?.sourceTurnId == stoppedTurnId &&
          session.state.runtime?.continuation?.claimed == false &&
          latestTurn()?.turnId == stoppedTurnId &&
          latestTurn()?.state.status == StudioTurnStatus.cancelled &&
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

    // No text is submitted to recover. Only the production Continue action may
    // claim this exact canonical continuation and admit a new execution.
    await tester.tap(find.byKey(const ValueKey('composer-continue')));
    await tester.pump();
    await until(
      () =>
          File('$output/submission-resume-reached').existsSync() &&
          session.state.runtime?.execution?.phase ==
              AgentExecutionPhase.running &&
          session.state.runtime?.execution?.id != stoppedExecution.id,
      'explicit continuation starts a new real execution',
    );
    final resumedExecution = session.state.runtime!.execution!;
    expect(resumedExecution.turnId, isNot(stoppedTurnId));
    expect(latestTurn()!.state.isTerminal, isFalse);
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
    await until(
      () =>
          session.state.runtime?.execution == null &&
          session.state.runtime?.continuation == null &&
          latestTurn()?.turnId == resumedExecution.turnId &&
          latestTurn()?.state.status == StudioTurnStatus.completed &&
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
    report['firstTurnId'] = firstTurn.turnId;
    report['heldFrames'] = transport.heldFrames;
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
    assertionsPassed = true;
  });
}

/// The gate delays real work, not its outcome. No receipt or frame is synthesized.
class _SubmissionTransport extends FrbStudioTransport {
  _SubmissionTransport(this.record);
  final void Function(String, [Map<String, Object?>]) record;
  Completer<void>? _rpc;
  Completer<void>? _feed;
  Completer<void>? _stopRpc;
  String? blockedStopExecutionId;
  StopThreadCommandReply? stopReceipt;
  StudioPromptInput? blockedInput;
  SubmitPromptReceipt? receipt;
  bool realSecondRpcStarted = false;
  int heldFrames = 0;
  int? lastHeldSequence;

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

  Future<ConversationFrame> deliver(ConversationFrame frame) async {
    final gate = _feed;
    if (gate != null && !gate.isCompleted) {
      heldFrames++;
      lastHeldSequence = frame.deliverySequence;
      record('real-frame-held', {
        'subscriptionId': frame.subscriptionId,
        'deliverySequence': frame.deliverySequence,
      });
      await gate.future;
    }
    return frame;
  }

  @override
  Future<TimelineFeed> openTimelineFeed(
    String threadId, {
    required ReadDemand demand,
  }) async => _SubmissionFeed(
    await super.openTimelineFeed(threadId, demand: demand),
    this,
  );
}

/// asyncMap preserves order/identity/backpressure. ACK and reader stay on the
/// original feed. Closing releases an in-flight barrier before joining native.
class _SubmissionFeed implements TimelineFeed {
  _SubmissionFeed(this.original, this.owner);
  final TimelineFeed original;
  final _SubmissionTransport owner;
  late final Stream<ConversationFrame> _events = original.events.asyncMap(
    owner.deliver,
  );
  @override
  String get threadId => original.threadId;
  @override
  String get subscriptionId => original.subscriptionId;
  @override
  ConversationReader get reader => original.reader;
  @override
  Future<TimelineBatch> loadTimelineOlder({
    required String before,
    required ReadDemand demand,
  }) => original.loadTimelineOlder(before: before, demand: demand);
  @override
  Future<LiveDisplayWindow> loadLiveOlder({
    required String before,
    required ReadDemand demand,
  }) => original.loadLiveOlder(before: before, demand: demand);
  @override
  Future<DisplayMembers> openDisplayMembers({
    required DisplayBlockRef reference,
    required DisplayMemberWindow window,
    required ReadDemand demand,
  }) => original.openDisplayMembers(
    reference: reference,
    window: window,
    demand: demand,
  );
  @override
  Stream<ConversationFrame> get events => _events;
  @override
  Future<void> acknowledge(int deliverySequence) =>
      original.acknowledge(deliverySequence);
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
