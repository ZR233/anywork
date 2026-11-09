import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/frb_startup_host.dart';
import 'package:anywork/src/app/routing/app_route.dart';
import 'package:anywork/src/app/routing/application_router.dart';
import 'package:anywork/src/app/studio_shutdown.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/composer/views/prompt_composer_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/settings/statistics/view_models/statistics_repository_provider.dart';
import 'package:anywork/src/infrastructure/frb/statistics/frb_statistics_feed.dart';
import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork/src/infrastructure/frb/studio_update_api.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/fixture_gate.dart';
import 'support/presentation_capture.dart';
import 'support/timeline_observation.dart';

const _first = '请保持第一轮运行，我将继续发送一条消息。';
const _second = '这是运行中的第二条消息，请确认收到。';
const _stage = 'submission-first-running';

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
        await fixtureGate(tester, provider, _stage, release: true);
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
            localizationsDelegates: AppLocalizations.localizationsDelegates,
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
        if (selected?.path != project ||
            selection.needsOpen ||
            view.evaluate().length != 1 ||
            input.evaluate().length != 1) {
          return false;
        }
        final composer = tester.widget<PromptComposerView>(view);
        return composer.enabled &&
            composer.pasteTargetId ==
                (selection.selectedThreadId ?? selection.selectedProjectId);
      }, 'production composer ready for the selected project');
      await tester.enterText(input, text);
      await tester.pump();
      expect(tester.widget<TextField>(input).controller!.text, text);
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
                (block.body as SingleDisplayBlock).atom.source
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
    expect(find.text('正在发送'), findsOneWidget);
    expect(transport.realSecondRpcStarted, isFalse);
    expect(transport.receipt, isNull);
    expect(
      observed.singleBlocks.where(
        (block) =>
            (block.body as SingleDisplayBlock).atom.source ==
            InputChatSource(inputId: inputId),
      ),
      isEmpty,
    );
    record('pending-painted-before-real-rpc', {'inputId': inputId});
    await capturePresentation(tester, 'submission-pending.png');

    transport.releaseRpc();
    await until(
      () =>
          transport.receipt != null &&
          find.text('已收到，等待同步').evaluate().length == 1 &&
          owner.submissions.value.any(
            (item) =>
                item.inputId == inputId &&
                item.phase == ComposerSubmissionPhase.accepted,
          ),
      'real submit receipt and accepted local echo',
    );
    expect(transport.receipt!.inputId, inputId);
    await until(() => transport.heldFrames > 0, 'real feed frame held');
    expect(find.text('已收到，等待同步'), findsOneWidget);
    expect(card.hitTestable(), findsOneWidget);
    expect(
      observed.singleBlocks.where(
        (block) =>
            (block.body as SingleDisplayBlock).atom.source ==
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
                        (block.body as SingleDisplayBlock).atom.source ==
                        InputChatSource(inputId: inputId),
                  )
                  .length ==
              1,
      'one canonical input replaces the local echo',
    );
    expect(card, findsNothing);
    final canonical = observed.singleBlocks.singleWhere(
      (block) =>
          (block.body as SingleDisplayBlock).atom.source ==
          InputChatSource(inputId: inputId),
    );
    final canonicalBody = canonical.body as SingleDisplayBlock;
    expect(canonicalBody.completionId, isNotNull);
    await observed.revealSingle(canonical);
    final row = observed.itemRow(canonical.id);
    expect(row.hitTestable(), findsOneWidget);
    expect(
      tester.widget<ChatItemView>(row).item.atom!.source,
      InputChatSource(inputId: inputId),
    );
    expect(find.text(_second), findsOneWidget);
    record('canonical-painted-without-duplicate', {
      'inputId': inputId,
      'blockId': canonical.id,
      'recordId': canonicalBody.completionId,
      'deliverySequence': transport.lastHeldSequence,
    });
    await capturePresentation(tester, 'submission-canonical.png');
    await fixtureGate(tester, provider, _stage, release: true);
    await until(() {
      final turn = latestTurn();
      return turn != null &&
          turn.turnId != firstTurn.turnId &&
          turn.state.status == StudioTurnStatus.completed &&
          observed.singleBlocks.any(
            (block) =>
                (block.body as SingleDisplayBlock).atom.source ==
                    ForegroundTurnChatSource(turnId: turn.turnId) &&
                (block.body as SingleDisplayBlock).atom.kind ==
                    ChatAtomKind.text,
          );
    }, 'second real model turn completed after interrupting the first');
    report['inputId'] = inputId;
    report['firstTurnId'] = firstTurn.turnId;
    report['heldFrames'] = transport.heldFrames;
    for (final name in [
      'submission-pending.png',
      'submission-received.png',
      'submission-canonical.png',
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
