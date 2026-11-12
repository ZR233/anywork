import 'support/display_record_observation.dart';

import 'dart:convert';
import 'dart:io';

import 'package:anywork/src/app/app_composition.dart';
import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/routing/app_route.dart';
import 'package:anywork/src/app/routing/application_router.dart';
import 'package:anywork/src/app/studio_shutdown.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/features/conversation/composer/state/composer_view_state.dart'
    show StartComposerTarget, ThreadComposerTarget;
import 'package:anywork/src/features/conversation/composer/views/prompt_composer_view.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/conversation_current_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/completion_run_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_member_atom.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/content_reference_identity.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_content_connector.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_payload_reading.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_diagnostics.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/display_member_controller.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/conversation_current_views.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_content_range_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_wait_blocks.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_tool_blocks.dart';
import 'package:anywork/src/features/settings/statistics/view_models/statistics_repository_provider.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/fixture_gate.dart';
import 'support/composer_target_diagnostic.dart';
import 'support/presentation_capture.dart';
import 'support/realtime_background_observation.dart';
import 'support/timeline_observation.dart';

const _firstTokenObserverStage = 'realtime-first-token';
const _readableTextObserverStage = 'realtime-text-readable';
const _parallelObserverStage = 'realtime-parallel-observer';
const _parallelObserverPrefix = 'realtime parallel observers ready';
const _backgroundResultObserverStage = 'realtime-background-result';
const _backgroundResultReasoning =
    'realtime background A delivered; foreground reasoning remains active';
const _hostCwdObserverStage = 'realtime-host-cwd-observer';
const _hostCwdObserverPrefix = 'realtime host cwd observers ready';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  final project = Platform.environment['ANYWORK_REALTIME_PROJECT'];
  final output = Platform.environment['ANYWORK_REALTIME_OUTPUT'];
  final providerValue = Platform.environment['ANYWORK_REALTIME_PROVIDER'];
  final focus = Platform.environment['ANYWORK_REALTIME_FOCUS'];
  if (focus != null && focus != 'stop-background') {
    throw StateError('Unknown ANYWORK_REALTIME_FOCUS: $focus');
  }
  final full = focus == null;
  final provider = providerValue == null ? null : Uri.tryParse(providerValue);
  if (project == null || output == null) {
    throw StateError(
      'Supply ANYWORK_REALTIME_PROJECT and ANYWORK_REALTIME_OUTPUT',
    );
  }
  if (provider == null ||
      provider.scheme != 'http' ||
      !provider.hasAuthority ||
      !const {'127.0.0.1', 'localhost', '::1'}.contains(provider.host) ||
      !provider.hasPort ||
      provider.port <= 0 ||
      provider.port > 65535 ||
      provider.userInfo.isNotEmpty ||
      provider.hasQuery ||
      provider.hasFragment) {
    throw StateError(
      'Supply ANYWORK_REALTIME_PROVIDER as the strict loopback HTTP fixture URI',
    );
  }
  final reportFile = File('$output/realtime-presentation.json');
  late AppGraph graph;
  late ProviderContainer container;
  var assertionsPassed = false;
  final report = <String, Object?>{
    'scenario': 'realtime-presentation',
    'fixture': 'realtime-presentation',
    'runner': 'flutter.integration_test',
    'focus': focus ?? 'full',
    'expectedRequiredProviderSteps': full ? 15 : 6,
    'pass': false,
    'presentationCaptures': <Map<String, Object?>>[],
    'presentationCaptureScope':
        'Production journey witnesses below; initial empty surface, failure '
        'diagnostics are kept separate. Synthetic previews run in widget tests.',
    'captureCoverageGaps': {
      'mediaFailure': 'This strict realtime story does not read media.',
      'attachmentOnly': 'This strict realtime story submits text only.',
      'storageFailure': 'This story produces no visible storage failure.',
    },
  };

  setUpAll(() async {
    graph = createProductionAppGraph();
    container = ProviderContainer(
      overrides: [
        appGraphProvider.overrideWithValue(graph),
        statisticsRepositoryProvider.overrideWithValue(
          graph.statisticsRepository,
        ),
      ],
    );
    await graph.initialize();
    expect(graph.client.bootstrapState.value.failure, isNull);
  });

  tearDownAll(() async {
    try {
      final shutdown = await runStudioShutdown(
        graph.client.transport,
        (_) {},
        remainingMs: 30000,
        closeClient: (deadline) => graph.close(deadline: deadline),
      );
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
      await reportFile.parent.create(recursive: true);
      await reportFile.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
    }
  });

  testWidgets(
    'real realtime states render through production current and history',
    (tester) async {
      final router = createApplicationRouter();
      void syncConversationRoute() {
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

      router.routerDelegate.addListener(syncConversationRoute);
      tester.testTextInput.register();
      final testErrorHandler = FlutterError.onError!;
      FlutterError.onError = (details) {
        debugPrintSynchronously(details.toString());
        testErrorHandler(details);
      };
      addTearDown(() async {
        try {
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
          router.routerDelegate.removeListener(syncConversationRoute);
          router.dispose();
          FlutterError.onError = testErrorHandler;
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
      report['nativeWindow'] = await configurePresentationWindow(
        tester,
        requireNativeResize: full,
      );
      await graph.client.directoryCommands.openProject(project);
      graph.setConversationPageVisible(true);
      final scene = _RealtimeScene(tester, graph, project, report);

      await capturePresentation(tester, 'realtime-start.png');
      if (full) {
        await scene.submit('Realtime delayed first token');
        await fixtureGate(tester, provider, _firstTokenObserverStage);
        await scene.untilKey(const ValueKey('conversation-activity'));
        final firstLease = await scene.waitForTimelineSet();
        expect(scene.observed.liveBlocks, isEmpty);
        await scene.captureEvidence(
          'realtime-thinking.png',
          _firstTokenObserverStage,
          'Real activity before the fixture releases its first text token.',
        );
        expect(scene.lease, same(firstLease));
        expect(firstLease.isMounted && !firstLease.isRetired, isTrue);
        await fixtureGate(
          tester,
          provider,
          _firstTokenObserverStage,
          release: true,
        );
        await fixtureGate(tester, provider, _readableTextObserverStage);
        await scene.untilReadableCurrentText(
          timeout: const Duration(seconds: 20),
        );
        await scene.captureEvidence(
          'realtime-streaming.png',
          _readableTextObserverStage,
          'Existing real readable current text before the fixture terminal.',
        );
        await fixtureGate(
          tester,
          provider,
          _readableTextObserverStage,
          release: true,
        );
        await scene.completed(answer: 'realtime delayed first token');

        await scene.submit('Realtime reasoning then answer');
        await scene.until(
          () =>
              scene.observed.liveWork.isNotEmpty ||
              scene.observed.workBlocks.isNotEmpty,
          'producer-defined Work is available for explicit member inspection',
        );
        await scene.completed(answer: 'realtime reasoning answer');
        await scene.openLatestTurnThinking();
        await scene.captureEvidence(
          'realtime-reasoning.png',
          'Realtime reasoning then answer; completed Work expanded',
          'Existing real reasoning member/body disclosure; not a synthetic component.',
        );
        await scene.closeLatestTurnGroups();

        await scene.submit('Realtime long command');
        await scene.untilLaidOutCurrentTools(
          minimum: 2,
          toolCallIds: const {'realtime-long-call', 'realtime-long-wait-call'},
        );
        await scene.captureEvidence(
          'realtime-exec-wait.png',
          'Realtime long command; two exact current tool cards laid out',
          'Real expanded live exec/wait members from the original Work window.',
        );
        await scene.completed(answer: 'realtime long command complete');
        await scene.closeLatestTurnGroups();
      }
      await scene.submit('Realtime parallel tools');
      await fixtureGate(tester, provider, _parallelObserverStage);
      final parallelObserver = await scene.prepareToolObserver(
        stage: _parallelObserverStage,
        prefix: _parallelObserverPrefix,
        doneText: 'realtime parallel tools complete',
      );
      report['parallelObserver'] = parallelObserver.evidence;
      await scene.untilLaidOutCurrentTools(
        minimum: 2,
        handedOffExecCallIds: const {
          'realtime-parallel-call-a',
          'realtime-parallel-call-b',
        },
        settleDisclosure: false,
        preparedObserver: parallelObserver,
        beginRelease: (onProgress) => beginFixtureGateRelease(
          tester,
          provider,
          _parallelObserverStage,
          onProgress: onProgress,
        ),
      );
      expect(
        find.text('realtime parallel tools complete'),
        findsNothing,
        reason: 'Both exact exec calls must hand off before the final answer',
      );
      await scene.captureEvidence(
        'realtime-parallel-handoff.png',
        '$_parallelObserverStage released; both exec tasks accepted',
        'Real expanded members in the original parallel Work window.',
      );
      await fixtureGate(tester, provider, _backgroundResultObserverStage);
      await scene.observeBackgroundResultWithForeground(parallelObserver);
      await fixtureGate(
        tester,
        provider,
        _backgroundResultObserverStage,
        release: true,
      );
      (report['backgroundResultObserver']
              as Map<String, Object?>)['gateReleased'] =
          true;
      await scene.completed(answer: 'realtime parallel tools complete');
      await scene.verifyExecReceipts(
        const {
          'realtime-parallel-call-a': 'realtime-parallel-a-line-05',
          'realtime-parallel-call-b': 'realtime-parallel-b-line-07',
        },
        turnId: parallelObserver.turnId,
        foregroundBlockId: parallelObserver.display.unitId,
      );
      await scene.closeLatestTurnGroups();

      Future<List<Map<String, Object?>>> parallelFinalFacts() async {
        final records = await collectDisplayRecords(
          scene.observed,
          turnId: parallelObserver.turnId,
        );
        final finals =
            records
                .where(
                  (entry) =>
                      entry.record.contentSource is CompletedOriginal &&
                      entry.record.atom.source is BackgroundResultChatSource &&
                      const {
                        'realtime-parallel-call-a',
                        'realtime-parallel-call-b',
                      }.contains(entry.record.atom.tool?.callId),
                )
                .toList()
              ..sort(
                (a, b) => a.record.atom.tool!.callId.compareTo(
                  b.record.atom.tool!.callId,
                ),
              );
        expect(finals, hasLength(2));
        return [
          for (final entry in finals)
            {
              'blockId': entry.unit.id,
              'memberKey': entry.member?.memberKey,
              ...displayRecordEvidence(entry.record),
            },
        ];
      }

      final backgroundBeforeStop = await parallelFinalFacts();
      report['backgroundFinalsBeforeStop'] = backgroundBeforeStop;
      if (full) {
        await scene.submit('Realtime host cwd command');
        await fixtureGate(tester, provider, _hostCwdObserverStage);
        final hostObserver = await scene.prepareToolObserver(
          stage: _hostCwdObserverStage,
          prefix: _hostCwdObserverPrefix,
          doneText: 'realtime host cwd complete',
        );
        report['hostCwdObserver'] = hostObserver.evidence;
        await fixtureGate(
          tester,
          provider,
          _hostCwdObserverStage,
          release: true,
        );
        hostObserver.evidence['gateReleased'] = true;
        await scene.untilLaidOutCurrentTools(
          minimum: 1,
          handedOffExecCallIds: const {'realtime-host-cwd-call'},
          settleDisclosure: false,
          preparedObserver: hostObserver,
        );
        final hostCwdTurnId = hostObserver.turnId;
        await scene.captureEvidence(
          'realtime-host-cwd-handoff.png',
          '$_hostCwdObserverStage released; host exec task accepted',
          'Real host-cwd exec member in its original Work window.',
        );
        await scene.completed(answer: 'realtime host cwd complete');
        await scene.verifyExecReceipts(
          const {'realtime-host-cwd-call': 'realtime-host-cwd-line-03'},
          turnId: hostCwdTurnId,
          foregroundBlockId: hostObserver.display.unitId,
        );
        await scene.closeLatestTurnGroups();

        await scene.submit('Realtime provider error');
        await scene.terminal(StudioTurnStatus.failed);
        await scene.captureEvidence(
          'realtime-provider-error-collapsed.png',
          'Realtime provider error; failed terminal admitted',
          'Real provider failure before expanding its receipt.',
        );
        final failedTurn = scene._latestTurn()!;
        final failed = await scene.openTurnReceipt(
          failedTurn,
          expectedOutcome: 'failed',
        );
        final failureText = find
            .descendant(
              of: failed,
              matching: find.textContaining('realtime fixture provider error'),
            )
            .first;
        await scene.until(
          () => _laidOut(failureText),
          'provider failure laid out',
        );
        await _revealTextFragment(
          tester,
          failureText,
          'realtime fixture provider error',
        );
        await scene.captureEvidence(
          'realtime-provider-error.png',
          'Realtime provider error; failed receipt text laid out',
          'Real provider failure body in the expanded production receipt.',
        );
        await scene.closeTurnReceipt(failedTurn);
        await scene.returnAfterReadingHistory();
      }
      await scene.submit('Realtime cancellable stream');
      final cancelledText = await scene.untilReadableCurrentText(
        timeout: const Duration(seconds: 30),
      );
      final cancelledDisplay = scene.observed.liveBlocks
          .expand(scene.observed.liveDisplayRecords)
          .singleWhere(
            (head) =>
                head.record.atom.id == cancelledText.id &&
                head.record.atom.source == cancelledText.source,
          );
      await scene.captureEvidence(
        'realtime-before-cancel.png',
        'Realtime cancellable stream; before stop request',
        'Real readable partial stream; this is not evidence of stopping.',
        identities: {'partialAtomId': cancelledText.id},
      );
      await scene.tap(find.byKey(StudioDriverKeys.composerStop));
      await scene.captureStoppingIfVisible(cancelledText);
      await scene.terminal(StudioTurnStatus.cancelled);
      expect(
        scene.observed.singleBlocks.where(
          (item) => item.atom!.id == cancelledText.id,
        ),
        hasLength(1),
        reason: 'accepted partial text survives cancellation',
      );
      expect(
        scene.liveWindows.where(
          (window) => window.id == cancelledDisplay.displayId,
        ),
        isEmpty,
      );
      Map<String, Object?> stoppedCut() {
        final state = graph.client.conversations
            .session(scene.lease.threadId)
            .state;
        final turn = state.lastTurn!;
        expect(turn.turnId, cancelledText.turnId);
        expect(turn.state.status, StudioTurnStatus.cancelled);
        expect(turn.state.isBusy, isFalse);
        expect(state.activeTurn?.state.isBusy ?? false, isFalse);
        expect(state.runtime?.execution, isNull);
        expect(
          scene.observed.singleBlocks.where(
            (item) => item.atom!.id == cancelledText.id,
          ),
          hasLength(1),
        );
        expect(
          scene.liveWindows.where(
            (window) => window.id == cancelledDisplay.displayId,
          ),
          isEmpty,
        );
        return {
          'turnId': turn.turnId,
          'status': turn.state.status.name,
          'busy': turn.state.isBusy,
          'activeTurnId': state.activeTurn?.turnId,
          'executionId': state.runtime?.execution?.id,
          'partialAtomId': cancelledText.id,
          'partialSource': displayRecordEvidence(
            (scene.observed.singleBlocks
                        .singleWhere(
                          (item) => item.atom!.id == cancelledText.id,
                        )
                        .body
                    as SingleDisplayBlock)
                .record,
          ),
        };
      }

      final stoppedBefore = stoppedCut();
      report['stoppedBeforeCapture'] = stoppedBefore;
      expect(await parallelFinalFacts(), backgroundBeforeStop);
      await scene.captureEvidence(
        'realtime-stopped.png',
        'Realtime cancellable stream; canonical cancelled terminal admitted',
        'Real stopped Turn, preserved partial body and revoked live body window.',
        identities: {'partialAtomId': cancelledText.id},
      );
      final stoppedAfter = stoppedCut();
      expect(stoppedAfter, stoppedBefore);
      expect(await parallelFinalFacts(), backgroundBeforeStop);
      report['stoppedAfterCapture'] = stoppedAfter;

      await scene.submit('Realtime continue after cancel');
      await scene.completed(answer: 'realtime continued after cancel');
      expect(find.byType(ChatItemView), findsWidgets);

      if (full) {
        report.addAll({
          'delayedStreamVisible': true,
          'reasoningHistoryVisible': true,
          'execWaitCardsVisible': true,
          'parallelCardsVisible': true,
          'hostCwdCardsVisible': true,
          'providerErrorVisible': true,
          'cancelledViaProductionControl': true,
          'resumeVisible': true,
        });
      } else {
        report.addAll({
          'parallelCardsVisible': true,
          'cancelledViaProductionControl': true,
          'resumeVisible': true,
        });
      }
      assertionsPassed = true;
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}

typedef _PreparedToolObserver = ({
  String turnId,
  TimelineDisplayLease lease,
  Object liveAdmission,
  Object controller,
  int generation,
  int mainSets,
  TimelineGroupDisplay display,
  DisplayBlockRef reference,
  Object expansion,
  DisplayMemberController memberController,
  Object bodyGeneration,
  String prefixId,
  List<String> prefixReferences,
  Map<String, Object?> evidence,
});

typedef _ExecReceipt = ({
  ChatAtom member,
  TimelineDisplayUnit block,
  DisplayMemberHead? head,
  ChatItemPresentation value,
});

final class _RealtimeScene {
  _RealtimeScene(this.tester, this.graph, this.projectPath, this.report);

  final WidgetTester tester;
  final AppGraph graph;
  final String projectPath;
  final Map<String, Object?> report;
  String? _priorTurn;
  String? _submittedThreadId;
  String? _submittedTurnId;
  int _liveTextObservation = 0;
  int _execReceiptObservation = 0;
  int _sourceCloseObservation = 0;
  late final observed = TimelineObservation(tester, () => lease);

  TimelineDisplayLease get lease =>
      graph.timeline.lease(graph.client.selection.state.selectedThreadId!)!;

  Future<TimelineDisplayLease> waitForTimelineSet() async {
    TimelineDisplayLease? accepted;
    await until(() {
      final threadId = graph.client.selection.state.selectedThreadId;
      if (threadId == null) return false;
      _submittedThreadId ??= threadId;
      if (threadId != _submittedThreadId) return false;
      final display = graph.timeline.lease(threadId);
      if (display == null ||
          display.threadId != threadId ||
          !display.isMounted ||
          display.isRetired ||
          display.appliedSets != 1 ||
          display.live.value == null ||
          display.content.state.value is! ChatReady<bool>) {
        return false;
      }
      expect(
        display.content,
        same(graph.client.conversations.session(threadId).content),
      );
      accepted = display;
      return true;
    }, 'the selected Thread original Timeline Set and live cut admitted');
    report['firstTimelineAdmission'] = {
      'threadId': accepted!.threadId,
      'generation': accepted!.generation,
      'selectionId': accepted!.selectionId,
      'mainSets': accepted!.appliedSets,
      'liveRevision': accepted!.live.value!.revision,
      'retired': accepted!.isRetired,
    };
    return accepted!;
  }

  // Borrow only actual mounted live member scopes. Both Single and expanded
  // Work members expose these windows; no Activity query is involved.
  Iterable<TimelineCurrentWindowDisplay> get liveWindows sync* {
    final original = lease;
    for (final head in observed.liveBlocks.expand(
      observed.liveDisplayRecords,
    )) {
      final rows = observed.liveRenderer(head);
      for (final element in rows.evaluate()) {
        expect(lease, same(original));
        expect(original.isMounted && !original.isRetired, isTrue);
        yield* ((element as StatefulElement).state as TimelineMemberDisplay)
            .windows;
      }
    }
  }

  List<ChatItemPresentation> get items => observed.main
      .where((unit) => unit.atom?.payload != null)
      .map(ChatItemPresentation.forUnit)
      .toList();

  Future<Map<String, Object?>> captureEvidence(
    String fileName,
    String stage,
    String coverage, {
    Map<String, Object?> identities = const {},
  }) async {
    final state = graph.client.conversations.session(lease.threadId).state;
    final evidence = <String, Object?>{
      'fileName': fileName,
      'fixtureStage': stage,
      'coverage': coverage,
      'threadId': lease.threadId,
      'turnId': state.lastTurn?.turnId,
      'activeTurnId': state.activeTurn?.turnId,
      'executionId': state.runtime?.execution?.id,
      'liveBlockIds': observed.liveBlocks.map((block) => block.id).toList(),
      'mainBlockIds': lease.controller.messages
          .map((message) => message.id)
          .toList(),
      'mountedMemberIds': observed.mountedMembers
          .map((atom) => atom.id)
          .toList(),
      'memberWindows': [
        for (final display in lease.groupDisplays)
          {
            'blockId': display.unitId,
            'memberIds': display.atoms.map((atom) => atom.id).toList(),
          },
      ],
      'interactionIds': state.interactions.map((value) => value.id).toList(),
      ...identities,
      'captureRequested':
          Platform
              .environment['ANYWORK_PRESENTATION_SCREENSHOTS']
              ?.isNotEmpty ??
          false,
      'captureCompleted': false,
    };
    (report['presentationCaptures'] as List<Map<String, Object?>>).add(
      evidence,
    );
    await capturePresentation(tester, fileName);
    expect(tester.takeException(), isNull);
    evidence['captureCompleted'] = evidence['captureRequested'];
    return evidence;
  }

  Future<void> observeBackgroundResultWithForeground(
    _PreparedToolObserver prepared,
  ) async {
    final evidence = <String, Object?>{
      'gate': _backgroundResultObserverStage,
      'gateReached': true,
      'gateReleased': false,
      'holds': 'real foreground reasoning before its terminal and wait-b call',
      'bActivityRequired': false,
      'stage': 'awaiting original foreground member window',
    };
    report['backgroundResultObserver'] = evidence;
    final clock = Stopwatch()..start();
    Duration remaining() {
      final value = const Duration(seconds: 60) - clock.elapsed;
      if (value <= Duration.zero) {
        fail(
          'Timed out observing A final result with real foreground reasoning',
        );
      }
      return value;
    }

    final source = ForegroundTurnChatSource(turnId: prepared.turnId);
    try {
      await until(
        () =>
            _expectPreparedToolObserver(prepared) &&
            _preparedToolDisplay(prepared).atoms.any(
              (atom) =>
                  atom.source == source &&
                  atom.kind == ChatAtomKind.reasoning &&
                  atom.lifecycle is ActiveChatAtom,
            ),
        'new active foreground reasoning after A delivery',
        timeout: remaining(),
      );
    } catch (error) {
      final diagnostics = <String, Object?>{
        'error': error.toString(),
        'observer': _preparedToolObserverSnapshot(prepared),
        'members': [
          for (final atom in _preparedToolDisplay(prepared).atoms)
            {
              'id': atom.id,
              'kind': atom.kind.name,
              'source': atom.source.toString(),
              'sameSource': atom.source == source,
              'lifecycle': atom.lifecycle.runtimeType.toString(),
              'callId': atom.tool?.callId,
            },
        ],
        'memberWindow': prepared.memberController.window.runtimeType.toString(),
        'memberPageRevision': prepared.memberController.page?.revision,
        'memberPageSealed': prepared.memberController.page?.sealed,
      };
      debugPrintSynchronously(
        'Realtime background observer failure: ${jsonEncode(diagnostics)}',
      );
      await File.fromUri(
        Directory(Platform.environment['ANYWORK_REALTIME_OUTPUT']!).uri
            .resolve('realtime-background-observer-failure.json'),
      ).writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(diagnostics)}\n',
      );
      rethrow;
    }
    evidence['activeReasoningObserver'] = _preparedToolObserverSnapshot(
      prepared,
    );
    final reasoning = _preparedToolDisplay(prepared).atoms.singleWhere(
      (atom) =>
          atom.source == source &&
          atom.kind == ChatAtomKind.reasoning &&
          atom.lifecycle is ActiveChatAtom,
    );
    expect(reasoning.id, isNot(prepared.prefixId));
    final handoff = _preparedToolDisplay(prepared).atoms.singleWhere(
      (atom) =>
          atom.source == source &&
          atom.tool?.callId == 'realtime-parallel-call-a' &&
          atom.delivery == ChatDeliveryKind.backgroundHandoff,
    );
    expect(
      (handoff.lifecycle as TerminalChatAtom).outcome,
      ChatTerminalOutcome.transferred,
    );
    final handoffCard = (await _readCompletedPresentation(
      handoff,
      timeout: remaining(),
    )).toolCard;
    expect(handoffCard, isA<DecodedToolCard>());
    final taskId = (handoffCard as DecodedToolCard).value.taskId;
    expect(taskId, isNotNull);
    expect(taskId, isNotEmpty);

    evidence['stage'] = 'awaiting A independent Main block';
    ObservedDisplayRecord? resultRecord;
    while (resultRecord == null) {
      remaining();
      expect(_expectPreparedToolObserver(prepared), isTrue);
      resultRecord = await realtimeBackgroundRecord(
        observed,
        turnId: prepared.turnId,
        callId: 'realtime-parallel-call-a',
      );
      if (resultRecord == null) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull);
      }
    }
    final block = resultRecord.unit;
    final atom = resultRecord.record.atom;
    final resultHead = resultRecord.member;
    final backgroundSource = atom.source as BackgroundResultChatSource;
    evidence.addAll({
      'stage': 'revealing real background result and foreground reasoning',
      'backgroundBlockId': block.id,
      'backgroundMemberId': atom.id,
      'backgroundMessageId': backgroundSource.messageId,
      'foregroundBlockId': prepared.display.unitId,
      'reasoningMemberId': reasoning.id,
      'taskId': taskId,
    });
    if (resultHead == null) {
      await observed.revealSingle(block, timeout: remaining());
    } else {
      await observed.revealMember(
        atom,
        reference: block.memberReference!,
        timeout: remaining(),
      );
    }
    final backgroundRow = resultHead == null
        ? observed.itemRow(block.id)
        : find.descendant(
            of: observed.groupRow(block.id),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is ChatItemView &&
                  widget.item.id == resultHead.memberKey,
            ),
          );
    final rendered = await _awaitCanonicalRow(
      backgroundRow,
      atom,
      type: 'tool',
      timeout: remaining(),
    );
    expect(rendered.id, resultHead?.memberKey ?? block.id);
    expect(completedOriginalId(rendered.displayRecord!), atom.completionItemId);
    if (resultHead == null) expect(rendered.displayUnit, same(block));
    expect(rendered.atom?.source, backgroundSource);
    expect(rendered.atom?.id, atom.id);
    expect(rendered.toolCard, isA<DecodedToolCard>());
    final tool = (rendered.toolCard as DecodedToolCard).value;
    expect(tool.toolCallId, 'realtime-parallel-call-a');
    expect(tool.taskId, taskId);
    expect(tool.name, 'exec');
    expect(tool.statusString, 'succeeded');
    expect(tool.exitCode, 0);
    expect(tool.output, contains('realtime-parallel-a-line-05'));
    await observed.ensureMemberReadable(
      backgroundRow,
      atom,
      timeout: remaining(),
    );
    final declaredOutputs = atom.contents
        .where((content) => content.role == ChatContentRole.toolOutput)
        .toList();
    expect(declaredOutputs, hasLength(1));
    final outputReference = declaredOutputs.single.reference;
    final outputTarget = outputReference.target as BodyContentTarget;
    expect(
      (outputTarget.owner as ItemContentOwner).itemId,
      atom.completionItemId,
    );
    final outputIdentity = contentReferenceIdentity(outputReference);
    final backgroundOutput = find.descendant(
      of: backgroundRow,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is TimelineContentRangeConnector &&
            widget.itemId == rendered.id &&
            widget.contentKey == ChatContentRole.toolOutput.name &&
            contentReferenceIdentity(widget.reference) == outputIdentity,
      ),
    );
    await until(
      () => backgroundOutput.evaluate().length == 1,
      'the exact canonical declared tool output section',
      timeout: remaining(),
    );
    await until(
      () => find
          .descendant(
            of: backgroundOutput,
            matching: find.textContaining(
              'realtime-parallel-a-line-05',
              findRichText: true,
            ),
          )
          .evaluate()
          .isNotEmpty,
      'A canonical result output is actually rendered',
      timeout: remaining(),
    );
    // The native boundary proves that the same active foreground reference is readable
    // while the independent result has really arrived. Co-display geometry and disclosure
    // are covered by data-driven component tests, without another native scroll protocol.
    final summary = reasoning.contents.singleWhere(
      (content) => content.role == ChatContentRole.reasoningSummary,
    );
    final scope = prepared.lease.content.openScope(
      generation: prepared.generation,
    );
    try {
      final window = await scope.readContent(
        reference: summary.reference,
        range: const ContentRange(offset: 0, maxBytes: 4096),
      );
      expect(utf8.decode(window.bytes), contains(_backgroundResultReasoning));
    } finally {
      expect((await scope.close()).complete, isTrue);
    }
    expect(_expectPreparedToolObserver(prepared), isTrue);
    final state = graph.client.conversations.session(lease.threadId).state;
    expect(state.activeTurn?.turnId, prepared.turnId);
    expect(state.activeTurn?.state.isBusy, isTrue);
    expect(state.activeTurn?.state.isTerminal, isFalse);
    expect(state.runtime?.execution?.turnId, prepared.turnId);
    expect(state.runtime?.execution?.phase.isStopping, isFalse);
    final currentReasoning = _preparedToolDisplay(prepared).atoms
        .singleWhere((member) => member.id == reasoning.id);
    expect(currentReasoning.source, source);
    expect(currentReasoning.lifecycle, isA<ActiveChatAtom>());
    expect(observed.unitForBlock(prepared.reference).historyPos, isNull);
    expect(lease.live.value!.executionPresent, isTrue);
    evidence.addAll({
      'stage': 'native result and active foreground content verified',
      'executionId': state.runtime?.execution?.id,
      'foregroundSummaryRead': true,
      'backgroundCompletionId': atom.completionItemId,
      'backgroundAndForegroundShareWork': block.id == prepared.display.unitId,
    });
  }

  Future<void> captureStoppingIfVisible(ChatAtom partial) async {
    final state = graph.client.conversations.session(lease.threadId).state;
    final executionId = state.runtime?.execution?.id;
    final turnId = partial.turnId;
    final stopping = find.byKey(const ValueKey('composer-stopping-disabled'));
    PromptComposerView? composer() => tester
        .widgetList<PromptComposerView>(find.byType(PromptComposerView))
        .singleOrNull;
    bool sameStoppingCut() {
      final current = graph.client.conversations.session(lease.threadId).state;
      final command = composer()?.state.stopCommand;
      return executionId != null &&
          current.runtime?.execution?.id == executionId &&
          current.lastTurn?.turnId == turnId &&
          current.lastTurn?.state.isTerminal == false &&
          command != null &&
          command.target.label == executionId &&
          command.startedAtMs > 0 &&
          (command.isPending || command.accepted) &&
          _laidOut(stopping);
    }

    final evidence = <String, Object?>{
      'fixtureStage':
          'Realtime cancellable stream; production stop control tapped',
      'turnId': turnId,
      'executionId': executionId,
      'partialAtomId': partial.id,
      'stopCommandStartedAtMs': composer()?.state.stopCommand?.startedAtMs,
      'sameNonterminalExecutionBeforeCapture': sameStoppingCut(),
      'coverage':
          'Opportunistic observation only; this story has no stop-cleanup gate. '
          'A missed or changing transient is not evidence of the stopping state.',
    };
    report['stoppingCaptureObservation'] = evidence;
    if (!sameStoppingCut()) {
      evidence['status'] = 'not observed; no stable visible stopping cut';
      return;
    }
    final capture = await captureEvidence(
      'realtime-stopping.png',
      'Realtime cancellable stream; visible stop request before terminal',
      'Stopping candidate; require sameNonterminalExecutionBeforeAndAfter.',
      identities: {
        'partialAtomId': partial.id,
        'stopCommandStartedAtMs': composer()!.state.stopCommand!.startedAtMs,
      },
    );
    final preserved = sameStoppingCut();
    capture['sameNonterminalExecutionBeforeAndAfter'] = preserved;
    evidence['status'] = preserved
        ? 'same nonterminal execution observed before and after capture'
        : 'not proven; state changed during capture';
    evidence['sameNonterminalExecutionAfterCapture'] = preserved;
  }

  Future<ChatItemPresentation> openLatestTurnThinking() async {
    final turn = _latestTurn()!;
    final source = ForegroundTurnChatSource(turnId: turn.turnId);
    final groups = await observed.workForSource(source);
    expect(groups, isNotEmpty);
    await observed.openSourceWork(source);
    final reasoning = observed.mountedMembers
        .where(
          (atom) =>
              atom.source == source && atom.kind == ChatAtomKind.reasoning,
        )
        .toList();
    expect(reasoning, isNotEmpty);
    late ChatItemPresentation rendered;
    for (final atom in reasoning) {
      final reference = observed.unitForMember(atom.id).memberReference!;
      final display = await observed.revealMember(atom, reference: reference);
      expect(
        display.atoms.where((member) => member.id == atom.id),
        hasLength(1),
      );
      rendered = await _awaitCanonicalRow(
        observed.memberRow(atom.id),
        atom,
        type: 'thinking',
      );
      expect(display.error, isNull);
    }
    return rendered;
  }

  Future<void> closeLatestTurnGroups() async {
    final turnId = _latestTurn()!.turnId;
    final evidence = <String, Object?>{'turnId': turnId};
    try {
      await observed.closeSourceWork(
        ForegroundTurnChatSource(turnId: turnId),
        diagnostics: evidence,
      );
      final cleanup = await graph.client.conversations.retryCleanup(
        deadline: DateTime.now().add(const Duration(seconds: 5)),
      );
      evidence['scopeCleanupJoined'] = cleanup.complete;
      expect(cleanup.complete, isTrue);
    } finally {
      final output = Platform.environment['ANYWORK_REALTIME_OUTPUT']!;
      await File.fromUri(
        Directory(output).uri
            .resolve('realtime-source-close-${++_sourceCloseObservation}.json'),
      ).writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(evidence)}\n',
      );
    }
  }

  Future<_PreparedToolObserver> prepareToolObserver({
    required String stage,
    required String prefix,
    required String doneText,
  }) async {
    StudioTurnView? turn;
    await until(() {
      final current = _latestTurn();
      if (current == null || current.turnId == _priorTurn) return false;
      _submittedTurnId ??= current.turnId;
      expect(current.turnId, _submittedTurnId);
      turn = current;
      return current.state.status == StudioTurnStatus.running;
    }, 'typed $stage Turn at the observer gate');
    final source = ForegroundTurnChatSource(turnId: turn!.turnId);
    await until(
      () => observed.liveWork.length == 1,
      'the $stage Turn original live Work header',
    );
    final unit = (await observed.workForSource(source)).single;
    expect(
      unit.historyPos,
      isNull,
      reason: 'A terminal member without a boundary stays live',
    );
    final mainLease = lease;
    final liveAdmission = mainLease.live;
    expect(mainLease.isMounted && !mainLease.isRetired, isTrue);
    expect(liveAdmission.value, isNotNull);
    expect(liveAdmission.value!.executionPresent, isTrue);
    expect(
      liveAdmission.value!.blocks.where((block) => block.id == unit.id),
      hasLength(1),
    );
    final controller = mainLease.controller;
    final generation = mainLease.generation;
    final mainSets = mainLease.appliedSets;
    final reference = unit.memberReference!;
    final expansion = unit.expansion;
    final bodyActiveBeforeOpen = expansion.bodyActive;
    final bodyGenerationBeforeOpen = expansion.bodyGeneration;
    final display = await observed.openWork(unit.id);
    await until(() {
      final members = display.atoms.toList();
      expect(members.length, lessThanOrEqualTo(1));
      expect(
        members.where((atom) => atom.kind == ChatAtomKind.toolCall),
        isEmpty,
        reason: 'The provider gate has not admitted any exec',
      );
      return display.isCurrent &&
          display.expanded &&
          !display.loading &&
          members.length == 1 &&
          members.single.lifecycle is TerminalChatAtom &&
          members.single.completionItemId != null &&
          members.single.completionSeq != null;
    }, 'original $stage member window ready before exec admission');
    expect(display.error, isNull);
    expect(display.blockReference, reference);
    expect(display.atoms, hasLength(1));
    final reasoning = display.atoms.single;
    expect(reasoning.source, source);
    expect(reasoning.kind, ChatAtomKind.reasoning);
    expect(reasoning.tool, isNull);
    expect(reasoning.completionItemId, isNotNull);
    expect(reasoning.completionSeq, isNotNull);
    expect(reasoning.lifecycle, isA<TerminalChatAtom>());
    expect(
      (reasoning.lifecycle as TerminalChatAtom).outcome,
      ChatTerminalOutcome.completed,
    );
    expect(reasoning.contents, isNotEmpty);
    await observed.revealMember(reasoning, reference: reference);
    final rendered = await _awaitCanonicalRow(
      observed.memberRow(reasoning.id),
      reasoning,
      type: 'thinking',
    );
    expect(rendered.atom?.id, reasoning.id);
    expect(rendered.compatibility, ChatItemCompatibility.current);
    expect(rendered.type, 'thinking');
    expect(
      rendered.bodies
          .where((body) => body.inline != null)
          .map((body) => utf8.decode(body.inline!)),
      contains(prefix),
    );
    // Reveal and inspect the actual text boxes while the provider is gated.
    // This completes the original disclosure layout before the exec calls start.
    await _revealTextFragment(tester, observed.memberRow(reasoning.id), prefix);
    Rect? previousBounds;
    await until(() {
      final row = observed.memberRow(reasoning.id);
      if (!_laidOut(row)) return false;
      final bounds = tester.getRect(row);
      final stable = previousBounds == bounds;
      previousBounds = bounds;
      return stable && display.isCurrent && !display.loading;
    }, 'stable original reasoning member layout before gate release');
    expect(display.atoms, hasLength(1));
    expect(
      display.atoms.where((atom) => atom.kind == ChatAtomKind.toolCall),
      isEmpty,
      reason: 'No exec has been admitted before the observer gate is released',
    );
    expect(find.text(doneText), findsNothing);
    // The member body scope is acquired by the original UI disclosure, not
    // before it. Freeze it only after the real prefix is ready and laid out.
    expect(expansion.bodyActive, isTrue);
    final bodyGeneration = expansion.bodyGeneration;
    if (!bodyActiveBeforeOpen) {
      expect(bodyGeneration, isNot(same(bodyGenerationBeforeOpen)));
    }
    final prepared = (
      turnId: turn!.turnId,
      lease: mainLease,
      liveAdmission: liveAdmission,
      controller: controller,
      generation: generation,
      mainSets: mainSets,
      display: display,
      reference: reference,
      expansion: expansion,
      memberController: expansion.members!,
      bodyGeneration: bodyGeneration,
      prefixId: reasoning.id,
      prefixReferences: reasoning.contents
          .map(
            (content) => contentReferenceIdentity(content.reference).toString(),
          )
          .toList(),
      evidence: <String, Object?>{
        'gate': stage,
        'gateReached': true,
        'gateReleased': false,
        'bodyScopeAdmission': {
          'activeBeforeOpen': bodyActiveBeforeOpen,
          'activeAfterReady': expansion.bodyActive,
          'generationChangedOnOpen': !identical(
            bodyGenerationBeforeOpen,
            bodyGeneration,
          ),
        },
      },
    );
    expect(_expectPreparedToolObserver(prepared), isTrue);
    prepared.evidence['prearm'] = _preparedToolObserverSnapshot(prepared);
    return prepared;
  }

  // A virtualized Main row can remount its Widget State while the original
  // display lease, block reference and member controller remain unchanged.
  // Borrow the currently mounted renderer by that identity, never by an old
  // Widget State or by whichever foreground block happens to be visible.
  TimelineGroupDisplay _preparedToolDisplay(_PreparedToolObserver prepared) =>
      lease.groupDisplays.singleWhere(
        (display) =>
            display.unitId == prepared.display.unitId &&
            display.blockReference == prepared.reference,
      );

  bool _expectPreparedToolObserver(_PreparedToolObserver prepared) {
    expect(_latestTurn()?.turnId, prepared.turnId);
    expect(lease, same(prepared.lease));
    expect(lease.live, same(prepared.liveAdmission));
    expect(lease.isMounted && !lease.isRetired, isTrue);
    expect(lease.live.value, isNotNull);
    expect(lease.controller, same(prepared.controller));
    expect(lease.generation, prepared.generation);
    expect(lease.appliedSets, prepared.mainSets);
    final unit = observed.unitForBlock(prepared.reference);
    expect(unit.expansion, same(prepared.expansion));
    expect(
      unit.expansion.members,
      same(prepared.memberController),
      reason: 'The display lease, not a parent Widget, owns member demand',
    );
    if (unit.historyPos == null) {
      expect(unit.expansion.bodyGeneration, same(prepared.bodyGeneration));
    }
    expect(unit.memberReference, prepared.reference);
    final display = _preparedToolDisplay(prepared);
    expect(display.isCurrent && display.expanded, isTrue);
    expect(display.error, isNull);
    expect(display.blockReference, prepared.reference);
    if (display.loading) return false;
    final prefix = display.atoms
        .where((atom) => atom.id == prepared.prefixId)
        .single;
    expect(
      prefix.contents.map(
        (content) => contentReferenceIdentity(content.reference).toString(),
      ),
      orderedEquals(prepared.prefixReferences),
    );
    return true;
  }

  Map<String, Object?> _preparedToolObserverSnapshot(
    _PreparedToolObserver prepared, {
    Iterable<ChatAtom> handedOff = const [],
  }) {
    final display = _preparedToolDisplay(prepared);
    final loading = display.loading;
    return {
      'turnId': prepared.turnId,
      'groupId': prepared.display.unitId,
      'sameMainLease': identical(lease, prepared.lease),
      'sameLiveAdmission': identical(lease.live, prepared.liveAdmission),
      'liveRevision': lease.live.value?.revision,
      'executionPresent': lease.live.value?.executionPresent,
      'sameMainController': identical(lease.controller, prepared.controller),
      'mainGeneration': lease.generation,
      'mainSets': lease.appliedSets,
      'sameGroupDisplay': identical(
        lease.groupDisplays.singleWhere(
          (display) => display.unitId == prepared.display.unitId,
        ),
        prepared.display,
      ),
      'sameBodyGeneration': identical(
        observed.unitForBlock(prepared.reference).expansion.bodyGeneration,
        prepared.bodyGeneration,
      ),
      'blockReference': {
        'databaseId': prepared.reference.databaseId,
        'blockId': prepared.reference.blockId,
        'itemId': prepared.display.unitId,
      },
      'current': display.isCurrent,
      'expanded': display.expanded,
      'loading': loading,
      'membersAvailable': !loading,
      'error': display.error?.toString(),
      'prefixId': prepared.prefixId,
      'prefixReferences': loading ? null : prepared.prefixReferences,
      'memberIds': loading
          ? null
          : display.atoms.map((atom) => atom.id).toList(),
      'windows': loading
          ? null
          : [
              for (final window in display.windows)
                {
                  'id': window.id,
                  'reference': contentReferenceIdentity(window.reference)
                      .toString(),
                  'generation': window.window?.generation,
                  'ready': window.window != null,
                  'error': window.error?.toString(),
                },
            ],
      'handedOffTools': loading
          ? null
          : [
              for (final atom in handedOff)
                {
                  'id': atom.id,
                  'callId': atom.tool?.callId,
                  'active': atom.lifecycle is ActiveChatAtom,
                  'status': tester
                      .widget<TimelineToolDetails>(currentToolCard(atom))
                      .item
                      .statusString,
                  'taskId': tester
                      .widget<TimelineToolDetails>(currentToolCard(atom))
                      .item
                      .taskId,
                  'laidOut': _laidOut(currentToolCard(atom)),
                  'finder': _toolFinderObservation(atom),
                },
            ],
    };
  }

  TimelineDisplayUnit _turnReceipt(StudioTurnView turn) =>
      observed.singleBlocks.singleWhere(
        (item) =>
            item.atom!.kind == ChatAtomKind.turnReceipt &&
            item.atom!.source == ForegroundTurnChatSource(turnId: turn.turnId),
      );

  Future<ChatItemPresentation> _readCompletedPresentation(
    ChatAtom head, {
    required Duration timeout,
  }) async {
    expect(head.lifecycle, isA<TerminalChatAtom>());
    expect(head.completionItemId, isNotNull);
    expect(head.completionSeq, isNotNull);
    final original = lease;
    final scope = original.content.openScope(generation: original.generation);
    try {
      final entry = await scope
          .readCompleted(
            recordId: head.completionItemId!,
            demand: const ReadDemand(maxItems: 1, maxBytes: 64 * 1024),
          )
          .timeout(timeout);
      expect(lease, same(original));
      expect(original.isRetired, isFalse);
      expect(entry.recordId, head.completionItemId);
      expect(entry.completionSeq, head.completionSeq);
      expect(entry.atom.id, head.id);
      expect(entry.atom.source, head.source);
      expect(entry.atom.kind, head.kind);
      expect(entry.atom.delivery, head.delivery);
      expect(entry.atom.completionItemId, head.completionItemId);
      expect(entry.atom.completionSeq, head.completionSeq);
      expect(entry.atom.lifecycle, isA<TerminalChatAtom>());
      expect(
        (entry.atom.lifecycle as TerminalChatAtom).outcome,
        (head.lifecycle as TerminalChatAtom).outcome,
      );
      expect(entry.atom.payload, isA<InlinePayload>());
      expect(
        (entry.atom.payload as InlinePayload).bytes.length,
        lessThanOrEqualTo(64 * 1024),
      );
      final value = ChatItemPresentation.decode(entry.atom);
      expect(
        value.compatibility,
        ChatItemCompatibility.current,
        reason: 'The canonical fixture envelope must fit one 64KiB read',
      );
      return value;
    } finally {
      scope.retire();
      expect(
        (await scope.close(
          deadline: DateTime.now().add(const Duration(seconds: 5)),
        )).complete,
        isTrue,
      );
    }
  }

  Future<ChatItemPresentation> _awaitCanonicalRow(
    Finder row,
    ChatAtom head, {
    required String type,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    late ChatItemPresentation rendered;
    await until(
      () {
        if (row.evaluate().length != 1 || !_laidOut(row)) return false;
        final value = tester.widget<ChatItemView>(row).item;
        if (value.compatibility == ChatItemCompatibility.deferred) return false;
        expect(value.compatibility, ChatItemCompatibility.current);
        expect(value.type, type);
        expect(value.atom?.id, head.id);
        expect(value.atom?.source, head.source);
        expect(value.atom?.kind, head.kind);
        expect(value.atom?.delivery, head.delivery);
        expect(value.atom?.turnId, head.turnId);
        expect(value.atom?.tool?.callId, head.tool?.callId);
        Object? lifecycleFields(ChatAtomLifecycle? lifecycle) =>
            switch (lifecycle) {
              ActiveChatAtom(:final started, :final status) => (
                'active',
                started?.effectSeq,
                started?.suborder,
                status,
              ),
              TerminalChatAtom(:final started, :final ended, :final outcome) =>
                (
                  'terminal',
                  started?.effectSeq,
                  started?.suborder,
                  ended?.effectSeq,
                  ended?.suborder,
                  outcome,
                ),
              null => null,
            };
        expect(
          lifecycleFields(value.atom?.lifecycle),
          lifecycleFields(head.lifecycle),
        );
        expect(value.atom?.completionItemId, head.completionItemId);
        expect(value.atom?.completionSeq, head.completionSeq);
        rendered = value;
        return true;
      },
      'canonical $type renderer for ${head.id}',
      timeout: timeout,
    );
    return rendered;
  }

  void _expectTurnReceiptHead(TimelineDisplayUnit item) {
    expect(item.body, isA<SingleDisplayBlock>());
    expect(item.atom!.kind, ChatAtomKind.turnReceipt);
    expect(item.atom!.lifecycle, isA<TerminalChatAtom>());
    expect(observed.unit(item.id).atom!.id, item.atom!.id);
    expect(observed.unit(item.id).atom!.source, item.atom!.source);
  }

  Finder _turnReceiptTitle(TimelineDisplayUnit item) {
    final disclosure = find.descendant(
      of: observed.itemRow(item.id),
      matching: find.byKey(ValueKey(('item-disclosure', item.id))),
    );
    expect(disclosure, findsOneWidget);
    final disclosureElement = tester.element(disclosure);
    final tiles = find.descendant(
      of: disclosure,
      matching: find.byElementPredicate(
        (element) =>
            element.widget is ExpansionTile &&
            identical(
              element
                  .findAncestorWidgetOfExactType<TimelineActivityDisclosure>(),
              disclosureElement.widget,
            ),
      ),
    );
    expect(tiles, findsOneWidget);
    final outerTile = tester.element(tiles);
    final title = find.descendant(
      of: disclosure,
      matching: find.byWidgetPredicate((widget) {
        final tile = outerTile.widget;
        return widget is ListTile &&
            tile is ExpansionTile &&
            identical(widget.title, tile.title);
      }),
    );
    expect(title, findsOneWidget);
    return title;
  }

  Future<Finder> openTurnReceipt(
    StudioTurnView turn, {
    required String expectedOutcome,
  }) async {
    final item = _turnReceipt(turn);
    expect(item.body, isA<SingleDisplayBlock>());
    expect(item.atom!.kind, ChatAtomKind.turnReceipt);
    _expectTurnReceiptHead(item);
    await observed.revealSingle(item);
    final row = observed.itemRow(item.id);
    final receipt = await _awaitCanonicalRow(row, item.atom!, type: 'turn');
    expect(receipt.type, 'turn');
    expect((receipt.data['outcome'] as Map)['kind'], expectedOutcome);
    final title = _turnReceiptTitle(item);
    final header = find.descendant(
      of: title,
      matching: find.byType(TimelineActivityRow),
    );
    expect(header, findsOneWidget);
    if (!tester.widget<TimelineActivityRow>(header).expanded) {
      await tap(title);
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    return row;
  }

  Future<void> closeTurnReceipt(StudioTurnView turn) async {
    final item = _turnReceipt(turn);
    final title = _turnReceiptTitle(item);
    final header = find.descendant(
      of: title,
      matching: find.byType(TimelineActivityRow),
    );
    expect(header, findsOneWidget);
    expect(tester.widget<TimelineActivityRow>(header).expanded, isTrue);
    await tap(title);
    expect(tester.widget<TimelineActivityRow>(header).expanded, isFalse);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  }

  Future<ContentWindow> readDeclaredRange(
    String presentationId,
    String contentItemId,
    List<ChatAtomContent> contents,
    ChatContentRole role,
    String fragment, {
    required TimelineDisplayUnit single,
    DisplayMemberHead? head,
  }) async {
    final mainLease = lease;
    final initialLive = mainLease.live.value;
    final controller = mainLease.controller;
    final scroll = mainLease.scrollController;
    final generation = mainLease.generation;
    final mainSets = mainLease.appliedSets;
    final scrollable = find.byWidgetPredicate(
      (widget) => widget is Scrollable && identical(widget.controller, scroll),
    );
    TimelineDisplayUnit? originalMain;
    ScrollableState? originalScrollable;
    Element? originalCanonical;
    final canonical = find.byWidgetPredicate(
      (widget) => widget is ChatItemView && widget.item.id == presentationId,
      skipOffstage: false,
    );
    final connector = find.byWidgetPredicate(
      (widget) =>
          widget is TimelineContentRangeConnector &&
          widget.itemId == presentationId &&
          widget.contentKey == role.name,
    );
    final rangeView = find.descendant(
      of: connector,
      matching: find.byType(TimelineContentRangeView),
    );
    final read = find.descendant(
      of: connector,
      matching: find.byKey(
        StudioDriverKeys.timelineContentOpen(presentationId, role.name),
      ),
    );
    ContentRef? expectedReference;
    State? originalState;
    TimelineCurrentWindowDisplay? originalOwner;

    void expectLease() {
      expect(lease, same(mainLease));
      expect(mainLease.isRetired, isFalse);
      expect(mainLease.controller, same(controller));
      expect(mainLease.scrollController, same(scroll));
      expect(mainLease.generation, generation);
      expect(mainLease.appliedSets, mainSets);
    }

    TimelineDisplayUnit singleMetadata(ContentRef reference) {
      final messages = controller.messages
          .where((message) => message.id == single.id)
          .toList();
      expect(messages, hasLength(1), reason: 'one original Main Message');
      final metadata = messages.single.metadata?[timelineDisplayUnitKey];
      if (metadata is! TimelineDisplayUnit) {
        fail('The original Main Message must own TimelineDisplayUnit metadata');
      }
      expect(metadata.historyPos!, greaterThan(0));
      expect(metadata, same(single));
      final DisplayRecord record;
      if (head == null) {
        expect(metadata.id, presentationId);
        expect(metadata.body, isA<SingleDisplayBlock>());
        expect(metadata.memberReference, isNull);
        record = (metadata.body as SingleDisplayBlock).record;
      } else {
        expect(metadata.body, isA<WorkDisplayBlock>());
        expect(metadata.memberReference, single.memberReference);
        expect(presentationId, head.memberKey);
        final rendered = tester.widget<ChatItemView>(canonical).item;
        expect(rendered.displayRecord, isNotNull);
        record = rendered.displayRecord!;
        expect(record.atom.id, head.record.atom.id);
        expect(completedOriginalId(record), completedOriginalId(head.record));
      }
      expect(record.contentSource, isA<CompletedOriginal>());
      final member = record.atom;
      expect(member.source, isA<BackgroundResultChatSource>());
      expect(member.delivery, ChatDeliveryKind.independent);
      expect(member.lifecycle, isA<TerminalChatAtom>());
      expect(
        (member.lifecycle as TerminalChatAtom).outcome,
        ChatTerminalOutcome.completed,
      );
      expect(member.completionItemId, contentItemId);
      final declared = member.contents
          .where((content) => content.role == role)
          .toList();
      expect(
        declared,
        hasLength(1),
        reason: 'one declared member content role',
      );
      expect(
        contentReferenceIdentity(declared.single.reference),
        contentReferenceIdentity(reference),
      );
      return metadata;
    }

    bool belongsTo(Element element, Element ancestor) {
      var belongs = identical(element, ancestor);
      element.visitAncestorElements((candidate) {
        if (identical(candidate, ancestor)) {
          belongs = true;
          return false;
        }
        return true;
      });
      return belongs;
    }

    try {
      final reference = contents
          .singleWhere((content) => content.role == role)
          .reference;
      expectedReference = reference;
      final body = reference.target as BodyContentTarget;
      expect((body.owner as ItemContentOwner).itemId, contentItemId);
      expectLease();
      // The actual Single card owns this range, not a fabricated member window
      // or a nullable current-overlay borrow.
      final main = singleMetadata(reference);
      originalMain = main;
      expect(scrollable, findsOneWidget);
      expect(scroll.positions, hasLength(1));
      final mainScrollable = tester.state<ScrollableState>(scrollable);
      originalScrollable = mainScrollable;
      expect(mainScrollable.position, same(scroll.position));
      expect(canonical, findsOneWidget);
      final row = tester.element(canonical);
      final originalAtom = tester.widget<ChatItemView>(canonical).item.atom;
      originalCanonical = row;
      final memberScrollable = Scrollable.maybeOf(row);
      expect(memberScrollable, isNotNull);

      void expectMain() {
        expectLease();
        expect(singleMetadata(reference), same(main));
        expect(scrollable, findsOneWidget);
        expect(tester.state<ScrollableState>(scrollable), same(mainScrollable));
        expect(mainScrollable.mounted, isTrue);
        expect(scroll.positions, hasLength(1));
        expect(mainScrollable.position, same(scroll.position));
        expect(canonical, findsOneWidget);
        expect(tester.element(canonical), same(row));
        expect(row.mounted, isTrue);
        final widget = row.widget;
        if (widget is! ChatItemView) {
          fail('The original member canonical row must remain a ChatItemView');
        }
        expect(widget.item.id, presentationId);
        expect(widget.item.atom, same(originalAtom));
        expect(Scrollable.maybeOf(row), same(memberScrollable));
        expect(memberScrollable!.mounted, isTrue);
      }

      await until(() {
        expectMain();
        final count = connector.evaluate().length;
        expect(count, lessThanOrEqualTo(1));
        return count == 1;
      }, 'declared ${role.name} range of $contentItemId');
      final state = tester.state(connector);
      final owner = state as TimelineCurrentWindowDisplay;
      originalState = state;
      originalOwner = owner;
      final mountedReference = owner.reference;

      TimelineContentRangeView expectAutomaticRead() {
        expectMain();
        expect(connector, findsOneWidget);
        expect(tester.state(connector), same(state));
        expect(state.mounted, isTrue);
        expect(
          tester
              .widget<TimelineContentRangeConnector>(connector)
              .isDisplayActive
              ?.call(),
          isTrue,
        );
        final element = tester.element(connector);
        expect(Scrollable.maybeOf(element), same(memberScrollable));
        expect(belongsTo(element, row), isTrue);
        expect(owner.reference, same(mountedReference));
        expect(
          contentReferenceIdentity(owner.reference),
          contentReferenceIdentity(reference),
        );
        expect(
          tester.widget<TimelineContentRangeConnector>(connector).reference,
          same(mountedReference),
        );
        expect(
          tester
              .element(connector)
              .getInheritedWidgetOfExactType<TimelineBodyReadIntent>(),
          isNotNull,
        );
        expect(rangeView, findsOneWidget);
        final view = tester.widget<TimelineContentRangeView>(rangeView);
        expect(view.itemId, presentationId);
        expect(view.contentKey, role.name);
        expect(view.initiallyExpanded, isTrue);
        expect(view.disclosed, isTrue);
        expect(view.active, isTrue);
        expect(view.canRead, isTrue);
        if (owner.error case final error?) throw error;
        if (view.error case final error?) throw error;
        expect(read, findsNothing);
        return view;
      }

      // The enclosing tool disclosure supplies the read intent and renders the
      // bounded body directly, without a second disclosure or another click.
      await until(() {
        final view = expectAutomaticRead();
        return owner.window != null && !view.loading;
      }, 'accepted bounded ${role.name} window');
      final window = owner.window!;
      expect(expectAutomaticRead().window, same(window));
      expect(window.offset, 0);
      expect(window.sealed, isTrue);
      expect(window.bytes, isNotEmpty);
      expect(window.bytes.length, lessThanOrEqualTo(64 * 1024));
      final text = utf8.decode(window.bytes);
      expect(text, contains(fragment));
      final rendered = find.byKey(
        StudioDriverKeys.timelineContentWindow(presentationId, role.name),
      );
      await until(() {
        expectAutomaticRead();
        return _laidOut(rendered);
      }, 'actual bounded body text');
      await _revealTextFragment(tester, rendered, fragment);
      expectAutomaticRead();
      expect(owner.window, same(window));
      return window;
    } catch (_) {
      try {
        Map<String, Object?> positionFacts(ScrollPosition position) => {
          'sameMainPosition': scroll.positions.contains(position),
          'axis': position.axisDirection.name,
          'pixels': position.hasPixels ? position.pixels : null,
          'minExtent': position.hasContentDimensions
              ? position.minScrollExtent
              : null,
          'maxExtent': position.hasContentDimensions
              ? position.maxScrollExtent
              : null,
          'viewport': position.hasViewportDimension
              ? position.viewportDimension
              : null,
        };
        Map<String, Object?> boxFacts(RenderObject? render) => {
          'type': render?.runtimeType.toString(),
          'attached': render?.attached,
          if (render is RenderBox) ...{
            'hasSize': render.hasSize,
            if (render.attached && render.hasSize)
              'rect': [
                render.localToGlobal(Offset.zero).dx,
                render.localToGlobal(Offset.zero).dy,
                render.size.width,
                render.size.height,
              ],
          },
        };
        Map<String, Object?> geometry(Finder finder) {
          final elements = finder.evaluate().toList();
          final facts = <String, Object?>{
            'finder': finder.toString(),
            'matches': elements.length,
          };
          if (elements.length != 1) return facts;
          final element = elements.single;
          facts['widgetType'] = element.widget.runtimeType.toString();
          facts['key'] = element.widget.key?.toString();
          try {
            final render = element.findRenderObject();
            facts['render'] = boxFacts(render);
            final clips = <Map<String, Object?>>[];
            var ancestor = render?.parent;
            for (var depth = 0; ancestor != null && depth < 96; depth++) {
              if (ancestor is RenderClipRect ||
                  ancestor is RenderAbstractViewport) {
                clips.add(boxFacts(ancestor));
                if (clips.length == 8) break;
              }
              ancestor = ancestor.parent;
            }
            facts['clips'] = clips;
            final scrollables = <Map<String, Object?>>[];
            var depth = 0;
            element.visitAncestorElements((ancestor) {
              if (ancestor is StatefulElement &&
                  ancestor.state is ScrollableState) {
                final state = ancestor.state as ScrollableState;
                scrollables.add(positionFacts(state.position));
              }
              return ++depth < 96 && scrollables.length < 6;
            });
            facts['scrollables'] = scrollables;
            if (render is RenderBox && render.attached && render.hasSize) {
              facts['hitTestable'] = finder.hitTestable().evaluate().length;
              final center = render.localToGlobal(
                render.size.center(Offset.zero),
              );
              facts['centerHitTypes'] = tester
                  .hitTestOnBinding(center)
                  .path
                  .take(12)
                  .map((entry) => entry.target.runtimeType.toString())
                  .toList();
            }
          } catch (error) {
            facts['diagnosticErrorType'] = error.runtimeType.toString();
          }
          return facts;
        }

        Map<String, Object?> ownerFacts(TimelineCurrentWindowDisplay? owner) {
          final window = owner?.window;
          return {
            'type': owner?.runtimeType.toString(),
            'reference': owner == null
                ? null
                : contentReferenceIdentity(owner.reference).toString(),
            'errorType': owner?.error?.runtimeType.toString(),
            'window': window == null
                ? null
                : {
                    'offset': window.offset,
                    'bytes': window.bytes.length,
                    'generation': window.generation,
                    'availableThrough': window.availableThrough,
                    'sealed': window.sealed,
                  },
          };
        }

        Map<String, Object?> mainFacts(Object? metadata) {
          if (metadata is! TimelineDisplayUnit) {
            return {'type': metadata?.runtimeType.toString()};
          }
          final declared =
              (metadata.atom?.contents ?? const <ChatAtomContent>[])
                  .where((content) => content.role == role)
                  .toList();
          return {
            'type': metadata.runtimeType.toString(),
            'completed': true,
            'id': metadata.id,
            'itemId': metadata.id,
            'hasPosition': metadata.historyPos! > 0,
            'contentItemId': switch (metadata.body) {
              SingleDisplayBlock(:final record) => completedOriginalId(record),
              WorkDisplayBlock() => null,
            },
            'declaredRoleMatches': declared.length,
            'declaredReference': declared.length == 1
                ? contentReferenceIdentity(declared.single.reference).toString()
                : null,
          };
        }

        final mainMessages = controller.messages
            .where((message) => message.id == presentationId)
            .toList();
        Object? metadata;
        if (mainMessages.length == 1) {
          metadata = mainMessages.single.metadata?[timelineDisplayUnitKey];
        }
        final canonicalMatches = canonical.evaluate().toList();
        final canonicalWidget = canonicalMatches.length == 1
            ? canonicalMatches.single.widget
            : null;
        final scrollableMatches = scrollable.evaluate().toList();
        final actualScrollable = scrollableMatches.length == 1
            ? tester.state<ScrollableState>(scrollable)
            : null;
        final currentLive = mainLease.live.value;
        final matches = connector.evaluate().toList();
        final actualState = matches.length == 1
            ? tester.state(connector)
            : null;
        final views = rangeView.evaluate().toList();
        final view = views.length == 1
            ? views.single.widget as TimelineContentRangeView
            : null;
        final tiles = find
            .descendant(of: read, matching: find.byType(ExpansionTile))
            .evaluate()
            .toList();
        final ownTitle = find.descendant(
          of: read,
          matching: find.byWidgetPredicate(
            (widget) =>
                tiles.length == 1 &&
                widget is ListTile &&
                identical(
                  widget.title,
                  (tiles.single.widget as ExpansionTile).title,
                ),
          ),
        );
        final disclosures = read.evaluate().toList();
        final snapshot = jsonEncode({
          'presentationId': presentationId,
          'role': role.name,
          'contentItemId': contentItemId,
          'expectedReference': expectedReference == null
              ? null
              : contentReferenceIdentity(expectedReference).toString(),
          'sameLease': identical(
            graph.timeline.lease(mainLease.threadId),
            mainLease,
          ),
          'retired': mainLease.isRetired,
          'sameController':
              !mainLease.isRetired &&
              identical(mainLease.controller, controller),
          'generation': mainLease.generation,
          'expectedGeneration': generation,
          'mainSets': mainLease.appliedSets,
          'expectedMainSets': mainSets,
          'liveAdmissionObservation': {
            'initialRevision': initialLive?.revision,
            'revision': currentLive?.revision,
            'executionPresent': currentLive?.executionPresent,
            'mounted': mainLease.isMounted,
            'retired': mainLease.isRetired,
          },
          'mainMetadata': {
            'messageMatches': mainMessages.length,
            'original': mainFacts(originalMain),
            'actual': mainFacts(metadata),
            'sameOriginal': originalMain == null
                ? null
                : identical(metadata, originalMain),
          },
          'mainDomain': {
            'scrollableMatches': scrollableMatches.length,
            'originalScrollableMounted': originalScrollable?.mounted,
            'sameScrollable': originalScrollable == null
                ? null
                : identical(actualScrollable, originalScrollable),
            'sameScrollController':
                !mainLease.isRetired &&
                identical(mainLease.scrollController, scroll),
            'samePosition': actualScrollable == null
                ? null
                : scroll.positions.contains(actualScrollable.position),
            'canonicalMatches': canonicalMatches.length,
            'originalCanonicalMounted': originalCanonical?.mounted,
            'sameCanonical': originalCanonical == null
                ? null
                : canonicalMatches.length == 1 &&
                      identical(canonicalMatches.single, originalCanonical),
            'canonicalMetadataMatches':
                originalMain != null && canonicalWidget is ChatItemView
                ? identical(canonicalWidget.item.displayUnit, originalMain)
                : null,
            'connectorInOriginalCanonical':
                originalCanonical != null && matches.length == 1
                ? belongsTo(matches.single, originalCanonical)
                : null,
            'connectorInOriginalScrollable':
                originalScrollable != null && matches.length == 1
                ? identical(
                    Scrollable.maybeOf(matches.single),
                    originalScrollable,
                  )
                : null,
          },
          'sameState': identical(actualState, originalState),
          'originalStateMounted': originalState?.mounted,
          'actualStateMounted': actualState?.mounted,
          'originalOwner': ownerFacts(originalOwner),
          'actualOwner': ownerFacts(
            actualState is TimelineCurrentWindowDisplay
                ? actualState as TimelineCurrentWindowDisplay
                : null,
          ),
          'automaticIntent': matches.length == 1
              ? matches.single
                        .getInheritedWidgetOfExactType<
                          TimelineBodyReadIntent
                        >() !=
                    null
              : null,
          'initiallyExpanded': view?.initiallyExpanded,
          'disclosed': view?.disclosed,
          'loading': view?.loading,
          'active': view?.active,
          'canRead': view?.canRead,
          'viewErrorType': view?.error?.runtimeType.toString(),
          'enabled': disclosures.length == 1
              ? (disclosures.single.widget as TimelineActivityDisclosure)
                    .enabled
              : null,
          'connector': geometry(connector),
          'disclosure': geometry(read),
          'ownTitle': geometry(ownTitle),
          'mainPositions': scroll.positions.take(2).map(positionFacts).toList(),
        });
        debugPrintSynchronously('Declared automatic range failure: $snapshot');
        await File.fromUri(
          Directory(Platform.environment['ANYWORK_REALTIME_OUTPUT']!).uri
              .resolve('realtime-declared-range-failure.json'),
        ).writeAsString('$snapshot\n');
      } catch (error) {
        debugPrintSynchronously(
          'Declared range diagnostic failed: ${error.runtimeType}',
        );
      }
      rethrow;
    }
  }

  Future<void> verifyExecReceipts(
    Map<String, String> expected, {
    required String turnId,
    required String foregroundBlockId,
  }) async {
    final source = ForegroundTurnChatSource(turnId: turnId);
    final associatedTasks = <String, String>{};
    final observations = <Map<String, Object?>>[];
    final clock = Stopwatch()..start();
    Map<String, Object?>? lastObservation;
    String? previousObservation;
    final canonical = <String, ChatItemPresentation>{};
    Duration remaining() {
      final value = const Duration(seconds: 60) - clock.elapsed;
      if (value <= Duration.zero) {
        fail(
          'Timed out waiting for original exec terminals and each '
          'independently sourced final result: ${jsonEncode(lastObservation)}',
        );
      }
      return value;
    }

    Map<String, Object?> sourceFacts(ChatSourceId value) =>
        value is ForegroundTurnChatSource
        ? {'kind': 'foregroundTurn', 'turnId': value.turnId}
        : value is BackgroundResultChatSource
        ? {'kind': 'backgroundResult', 'messageId': value.messageId}
        : {'kind': value.runtimeType.toString()};

    Future<List<ObservedDisplayRecord>> backgroundRecords() async {
      final result = <ObservedDisplayRecord>[];
      for (final call in expected.keys) {
        final entry = await realtimeBackgroundRecord(
          observed,
          turnId: turnId,
          callId: call,
        );
        if (entry != null) result.add(entry);
      }
      return result;
    }

    Future<List<_ExecReceipt>> targets() async {
      final result = <_ExecReceipt>[];
      final candidates = <Map<String, Object?>>[];
      final counts = {for (final call in expected.keys) call: 0};
      final snapshot = <String, Object?>{
        'turnId': turnId,
        'candidates': candidates,
        'finalCounts': counts,
        'backgroundSingleAnchors': <Map<String, Object?>>[],
        'memberCallTaskMapping': <Map<String, Object?>>[],
        'complete': false,
      };
      lastObservation = {
        'elapsedMillis': clock.elapsedMilliseconds,
        ...snapshot,
      };

      Future<ChatItemPresentation> read(
        ChatAtom atom,
        Map<String, Object?> candidate,
      ) async {
        candidates.add(candidate);
        final payload = atom.payload;
        candidate['payloadKind'] = payload.runtimeType.toString();
        candidate['payloadBytes'] = payload is InlinePayload
            ? payload.bytes.length
            : payload is DeferredPayload
            ? payload.byteLength
            : null;
        if (payload is DeferredPayload) {
          candidate['payloadReference'] = contentReferenceIdentity(
            payload.reference,
          ).toString();
        }
        expect(atom.completionItemId, isNotNull);
        final recordId = atom.completionItemId!;
        final value = canonical[recordId] ??= await _readCompletedPresentation(
          atom,
          timeout: remaining(),
        );
        expect(value.atom?.id, atom.id);
        expect(value.atom?.source, atom.source);
        expect(value.atom?.completionSeq, atom.completionSeq);
        final reading = value.toolCard;
        candidate['compatibility'] = value.compatibility.name;
        candidate['decoder'] = reading.runtimeType.toString();
        if (reading is DecodedToolCard) {
          candidate.addAll({
            'callId': reading.value.toolCallId,
            'taskId': reading.value.taskId,
            'status': reading.value.statusString,
            'exitCode': reading.value.exitCode,
          });
        } else if (reading is UnavailableToolCard) {
          candidate['unavailableKind'] = reading.kind.name;
        }
        expect(
          reading,
          isA<DecodedToolCard>(),
          reason:
              'Canonical receipt envelope must decode within one bounded read: '
              '${jsonEncode(candidate)}',
        );
        return value;
      }

      // Only completed foreground receipts establish the original task link.
      final originals = await collectDisplayRecords(observed, source: source);
      for (final entry in originals.where(
        (entry) => entry.record.contentSource is CompletedOriginal,
      )) {
        final atom = entry.record.atom;
        if (atom.turnId != turnId ||
            !expected.containsKey(atom.tool?.callId) ||
            atom.lifecycle is! TerminalChatAtom) {
          continue;
        }
        final terminal = atom.lifecycle as TerminalChatAtom;
        final reference = entry.unit.memberReference!;
        final candidate = <String, Object?>{
          'domain': 'Run',
          'id': atom.id,
          'kind': atom.kind.name,
          'source': sourceFacts(atom.source),
          'turnId': atom.turnId,
          'delivery': atom.delivery.name,
          'outcome': terminal.outcome.name,
          'completionItemId': atom.completionItemId,
          'groupId': observed.unitForBlock(reference).id,
        };
        final value = await read(atom, candidate);
        final tool = (value.toolCard as DecodedToolCard).value;
        expect(tool.toolCallId, atom.tool!.callId);
        expect(tool.name, atom.tool!.name);
        final handedOff =
            atom.source == source &&
            atom.kind == ChatAtomKind.toolCall &&
            tool.name == 'exec' &&
            atom.delivery == ChatDeliveryKind.backgroundHandoff &&
            terminal.outcome == ChatTerminalOutcome.transferred &&
            tool.statusString == 'backgroundStarted';
        if (handedOff) {
          expect(tool.taskId, isNotNull);
          final previous = associatedTasks[tool.toolCallId];
          expect(previous, anyOf(isNull, tool.taskId));
          associatedTasks[tool.toolCallId] = tool.taskId!;
        }
        candidate['handedOff'] = handedOff;
        expect(handedOff, isTrue);
      }
      final finals = await backgroundRecords();
      for (final entry in finals) {
        final block = entry.unit;
        final atom = entry.record.atom;
        final candidate = <String, Object?>{
          'domain': entry.member == null ? 'Single' : 'WorkMember',
          'memberKey': entry.member?.memberKey,
          'id': atom.id,
          'source': sourceFacts(atom.source),
          'turnId': atom.turnId,
          'delivery': atom.delivery.name,
          'completionItemId': atom.completionItemId,
          'completionSeq': atom.completionSeq,
          'blockId': block.id,
          'historyPos': block.historyPos,
        };
        final value = await read(atom, candidate);
        final tool = (value.toolCard as DecodedToolCard).value;
        expect(tool.toolCallId, atom.tool!.callId);
        expect(tool.name, atom.tool!.name);
        expect(tool.name, 'exec');
        expect(tool.taskId, isNotNull);
        expect(associatedTasks.containsKey(tool.toolCallId), isTrue);
        expect(tool.taskId, associatedTasks[tool.toolCallId]);
        expect(tool.statusString, 'succeeded');
        expect(tool.exitCode, 0);
        candidate['taskAssociated'] = true;
        candidate['finalResult'] = true;
        result.add((
          member: atom,
          block: block,
          head: entry.member,
          value: value,
        ));
        counts[tool.toolCallId] = counts[tool.toolCallId]! + 1;
      }
      snapshot['backgroundResultAnchors'] = [
        for (final entry in finals)
          {
            'blockId': entry.unit.id,
            'memberKey': entry.member?.memberKey,
            'historyPos': entry.unit.historyPos,
            'atomId': entry.record.atom.id,
            'completionId': completedOriginalId(entry.record),
            'completionSeq': entry.record.atom.completionSeq,
          },
      ];
      snapshot['memberCallTaskMapping'] = [
        for (final candidate in candidates)
          if (candidate.containsKey('callId'))
            {
              for (final key in const [
                'callId',
                'taskId',
                'turnId',
                'source',
                'delivery',
                'groupId',
                'status',
                'exitCode',
                'finalResult',
              ])
                if (candidate.containsKey(key)) key: candidate[key],
            },
      ];
      snapshot['associatedTasks'] = Map<String, String>.of(associatedTasks);
      snapshot['complete'] = true;
      lastObservation = {
        'elapsedMillis': clock.elapsedMilliseconds,
        ...snapshot,
      };
      final signature = jsonEncode(snapshot);
      if (signature != previousObservation) {
        previousObservation = signature;
        if (observations.length < 32) observations.add(lastObservation!);
      }
      return result;
    }

    var receipts = <_ExecReceipt>[];
    try {
      Future<void> readRun(TimelineDisplayUnit unit) async {
        final display = await observed.openWork(unit.id, timeout: remaining());
        await observed.selectLatestMembers(display, timeout: remaining());
        while (true) {
          await observed.until(
            () {
              expect(display.isCurrent, isTrue);
              expect(display.expanded, isTrue);
              expect(display.blockReference, unit.memberReference!);
              if (display.error case final error?) throw StateError('$error');
              return !display.loading;
            },
            'original receipt Run page is ready',
            timeout: remaining(),
          );
          if (display.before == null) break;
          await observed.loadOlderMemberPage(display, timeout: remaining());
        }
        expect(
          unit.summary!.total,
          lessThanOrEqualTo(12),
          reason: 'This finite receipt fixture fits one member page',
        );
        expect(display.atoms, hasLength(unit.summary!.total));
        expect(
          display.atoms.map((atom) => atom.id).toSet(),
          hasLength(display.atoms.length),
        );
      }

      // The caller already owns this exact foreground Work. Never discover a
      // background result by opening unrelated Work member windows.
      final foreground = observed.unit(foregroundBlockId);
      expect(foreground.body, isA<WorkDisplayBlock>());
      await readRun(foreground);
      final foregroundDisplay = lease.groupDisplays.singleWhere(
        (display) => display.unitId == foregroundBlockId,
      );
      expect(
        foregroundDisplay.atoms.where((atom) => atom.source == source),
        isNotEmpty,
      );
      while (true) {
        remaining();
        receipts = await targets();
        final terminalCalls = observed.mountedMembers
            .where(
              (atom) =>
                  atom.source == source &&
                  atom.turnId == turnId &&
                  atom.lifecycle is TerminalChatAtom,
            )
            .map((atom) => atom.tool?.callId)
            .whereType<String>()
            .toSet();
        final finalCounts = {
          for (final call in expected.keys)
            call: receipts.where((receipt) {
              final tool = (receipt.value.toolCard as DecodedToolCard).value;
              return tool.toolCallId == call;
            }).length,
        };
        expect(
          finalCounts.values.where((count) => count > 1),
          isEmpty,
          reason: 'Each exact background task must produce one final receipt',
        );
        remaining();
        if (terminalCalls.containsAll(expected.keys) &&
            associatedTasks.keys.toSet().containsAll(expected.keys) &&
            finalCounts.values.every((count) => count == 1)) {
          break;
        }
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull);
      }
    } finally {
      final output = Directory(
        Platform.environment['ANYWORK_REALTIME_OUTPUT']!,
      );
      await File.fromUri(
        output.uri.resolve(
          'realtime-exec-receipts-${_execReceiptObservation++}.json',
        ),
      ).writeAsString(
        '${jsonEncode({'turnId': turnId, 'expectedCalls': expected.keys.toList(), 'associatedTasks': associatedTasks, 'observations': observations, 'lastObservation': lastObservation})}\n',
      );
    }
    expect(
      receipts
          .map(
            (target) =>
                (target.value.toolCard as DecodedToolCard).value.toolCallId,
          )
          .toSet(),
      expected.keys.toSet(),
    );
    expect(receipts, hasLength(expected.length));
    final controller = lease.controller;
    final mainSets = lease.appliedSets;
    final witnessed = <String>{};
    Map<String, Object?> Function()? disclosureFacts;
    try {
      for (final target in receipts) {
        disclosureFacts = null;
        final atom = target.member;
        final block = target.block;
        final head = target.head;
        if (head == null) {
          await observed.revealSingle(block);
        } else {
          await observed.revealMember(atom, reference: block.memberReference!);
        }
        final row = head == null
            ? observed.itemRow(block.id)
            : find.descendant(
                of: observed.groupRow(block.id),
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is ChatItemView &&
                      widget.item.id == head.memberKey,
                ),
              );
        final restored = await _awaitCanonicalRow(row, atom, type: 'tool');
        expect(restored.id, head?.memberKey ?? block.id);
        if (head == null) expect(restored.displayUnit, same(block));
        expect(restored.toolCard, isA<DecodedToolCard>());
        final item = restored;
        final rowId = restored.id;
        final contentItemId = atom.completionItemId!;
        final contents = atom.contents;
        final tool = (item.toolCard as DecodedToolCard).value;
        final originalTool = (target.value.toolCard as DecodedToolCard).value;
        expect(tool.toolCallId, originalTool.toolCallId);
        expect(tool.taskId, originalTool.taskId);
        final lastLine = expected[tool.toolCallId]!;
        expect(tool.name, 'exec');
        expect(tool.statusString, 'succeeded');
        expect(tool.exitCode, 0);
        expect(tool.output, contains(lastLine));
        final details = find.descendant(
          of: row,
          matching: find.byType(TimelineToolDetails),
        );
        expect(details, findsOneWidget);
        final detailsElement = tester.element(details);
        final renderedTool = tester.widget<TimelineToolDetails>(details).item;
        expect(renderedTool.id, tool.id);
        expect(renderedTool.toolCallId, tool.toolCallId);
        expect(renderedTool.statusString, 'succeeded');
        final disclosure = find.descendant(
          of: details,
          matching: find.byKey(
            ValueKey('timeline-tool-details:${renderedTool.id}'),
          ),
        );
        expect(disclosure, findsOneWidget);
        final disclosureElement = tester.element(disclosure);
        expect(disclosureElement.widget, isA<TimelineActivityDisclosure>());
        final tiles = find.descendant(
          of: disclosure,
          matching: find.byElementPredicate(
            (element) =>
                element.widget is ExpansionTile &&
                identical(
                  element
                      .findAncestorWidgetOfExactType<
                        TimelineActivityDisclosure
                      >(),
                  disclosureElement.widget,
                ),
          ),
        );
        expect(tiles, findsOneWidget);
        final outerTile = tester.element(tiles);
        final outerTitle = find.descendant(
          of: disclosure,
          matching: find.byWidgetPredicate((widget) {
            final tile = outerTile.widget;
            return widget is ListTile &&
                tile is ExpansionTile &&
                identical(widget.title, tile.title);
          }),
        );
        final title = find.descendant(
          of: outerTitle,
          matching: find.byType(TimelineActivityRow),
        );

        bool expectDisclosure() {
          expect(details, findsOneWidget);
          expect(tester.element(details), same(detailsElement));
          expect(detailsElement.mounted, isTrue);
          final currentTool = tester.widget<TimelineToolDetails>(details).item;
          expect(currentTool.id, renderedTool.id);
          expect(currentTool.toolCallId, tool.toolCallId);
          expect(currentTool.statusString, 'succeeded');
          expect(disclosure, findsOneWidget);
          expect(tester.element(disclosure), same(disclosureElement));
          expect(disclosureElement.mounted, isTrue);
          expect(tiles, findsOneWidget);
          expect(tester.element(tiles), same(outerTile));
          expect(outerTile.mounted, isTrue);
          expect(outerTitle, findsOneWidget);
          expect(title, findsOneWidget);
          return tester.widget<TimelineActivityRow>(title).expanded;
        }

        if (!expectDisclosure()) {
          await tap(outerTitle);
        }
        expect(expectDisclosure(), isTrue);
        final output = await readDeclaredRange(
          rowId,
          contentItemId,
          contents,
          ChatContentRole.toolOutput,
          lastLine,
          single: block,
          head: head,
        );
        final outputState = tester.state(
          find.byWidgetPredicate(
            (widget) =>
                widget is TimelineContentRangeConnector &&
                widget.itemId == rowId &&
                widget.contentKey == ChatContentRole.toolOutput.name,
          ),
        );
        final outputBorrow = outputState as TimelineCurrentWindowDisplay;
        Map<String, Object?> closeFacts() {
          final headers = outerTile.mounted
              ? title.evaluate().toList()
              : <Element>[];
          final window = outputBorrow.window;
          return {
            'rowId': rowId,
            'callId': tool.toolCallId,
            'closedTitleExpanded': headers.length == 1
                ? tester.widget<TimelineActivityRow>(title).expanded
                : null,
            'originalStateMounted': outputState.mounted,
            'windowPresent': window != null,
            'sameAcceptedWindow': window == null
                ? null
                : identical(window, output),
          };
        }

        disclosureFacts = closeFacts;
        if (tool.toolCallId == 'realtime-host-cwd-call') {
          final arguments = await readDeclaredRange(
            rowId,
            contentItemId,
            contents,
            ChatContentRole.toolArguments,
            'cwd',
            single: block,
            head: head,
          );
          final cwd =
              (jsonDecode(utf8.decode(arguments.bytes)) as Map)['cwd']
                  as String;
          expect(cwd, isNotEmpty);
          // The background result prefixes its JSON with the task completion
          // notice. Decode stdout before comparing physical directory identity;
          // Windows shells and the harness can use different path spellings.
          expect(
            tool.output,
            startsWith('Task ${tool.taskId} for tool exec finished:'),
          );
          final resultStart = tool.output.indexOf('{');
          expect(resultStart, greaterThanOrEqualTo(0));
          final result = jsonDecode(tool.output.substring(resultStart)) as Map;
          expect(result['taskId'], tool.taskId);
          final stdout = (result['stdout'] as Map)['content'] as String;
          const cwdPrefix = 'realtime-host-cwd-actual:';
          final cwdLine = const LineSplitter()
              .convert(stdout)
              .singleWhere((line) => line.startsWith(cwdPrefix));
          expect(
            FileSystemEntity.identicalSync(
              cwd,
              cwdLine.substring(cwdPrefix.length),
            ),
            isTrue,
          );
        }
        expect(observed.unit(block.id), same(block));
        if (head == null) {
          expect(block.memberReference, isNull);
          expect(block.atom, same(atom));
        } else {
          expect(restored.atom!.id, head.record.atom.id);
          expect(
            completedOriginalId(restored.displayRecord!),
            completedOriginalId(head.record),
          );
        }
        expect(lease.controller, same(controller));
        expect(lease.appliedSets, mainSets);
        expect(witnessed.add(tool.toolCallId), isTrue);
        debugPrintSynchronously(
          'Exec receipt laid out: ${jsonEncode({'callId': tool.toolCallId, 'rowId': rowId, 'contentItemId': contentItemId, 'state': tool.statusString, 'sourceOrder': atom.sourceOrder, 'lastLine': lastLine, 'blockId': block.id, 'outputBytes': output.bytes.length})}',
        );
        await captureEvidence(
          'realtime-${tool.toolCallId}-succeeded.png',
          'verified exec receipt after foreground completed',
          'Existing real completed display record and bounded output window; '
              'does not prove a concurrent active foreground.',
          identities: {
            'blockId': block.id,
            'memberId': atom.id,
            'toolCallId': tool.toolCallId,
            'sourceKind': atom.source.runtimeType.toString(),
          },
        );
        expect(expectDisclosure(), isTrue);
        await tap(outerTitle);
        expect(expectDisclosure(), isFalse);
        final closeClock = Stopwatch()..start();
        await until(
          () => outputBorrow.window == null,
          'collapsed result revokes its original bounded output borrow',
        );
        final closeRemaining = const Duration(seconds: 60) - closeClock.elapsed;
        expect(
          closeRemaining > Duration.zero,
          isTrue,
          reason: 'receipt closing must keep its original 60 second deadline',
        );
        await tester.pumpAndSettle(
          const Duration(milliseconds: 16),
          EnginePhase.sendSemanticsUpdate,
          closeRemaining,
        );
        expect(tester.takeException(), isNull);
        expect(outputBorrow.window, isNull);
        if (head != null) {
          await observed.closeWork(
            lease.groupDisplays.singleWhere(
              (display) => display.unitId == block.id,
            ),
          );
        }
      }
      expect(witnessed, expected.keys.toSet());
      await returnAfterReadingHistory();
    } catch (_) {
      final scroll = lease.scrollController;
      Map<String, Object?>? disclosure;
      try {
        disclosure = disclosureFacts?.call();
      } catch (error) {
        disclosure = {'diagnosticErrorType': error.runtimeType.toString()};
      }
      debugPrintSynchronously(
        'Exec receipt navigation failure: ${jsonEncode({'mode': lease.mode.name, 'pixels': scroll.hasClients ? scroll.position.pixels : null, 'maxExtent': scroll.hasClients ? scroll.position.maxScrollExtent : null, 'witnessed': witnessed.toList(), 'disclosure': disclosure})}',
      );
      await capturePresentation(tester, 'realtime-exec-receipts-failure.png');
      rethrow;
    }
  }

  Future<void> returnAfterReadingHistory() async {
    // Programmatic revelation is not a user's reading intent.
    final originalLease = lease;
    final generation = originalLease.generation;
    final scroll = originalLease.scrollController;
    expect(scroll.hasClients, isTrue);
    final position = scroll.position;
    if (position.maxScrollExtent <= 0.5) return;
    void expectOriginalPosition() {
      expect(lease, same(originalLease));
      expect(originalLease.generation, generation);
      expect(originalLease.isMounted && !originalLease.isRetired, isTrue);
      expect(originalLease.scrollController, same(scroll));
      expect(scroll.hasClients, isTrue);
      expect(scroll.position, same(position));
    }

    expectOriginalPosition();
    final main = find.byWidgetPredicate(
      (widget) => widget is Scrollable && identical(widget.controller, scroll),
    );
    expect(main, findsOneWidget);
    final beforePixels = position.pixels;
    // Establish latest geometry only. The subsequent real drag must separately
    // produce the user ScrollUpdate that admits production history mode.
    scroll.jumpTo(position.minScrollExtent);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expectOriginalPosition();
    final distance = position.viewportDimension / 4;
    expect(distance, greaterThan(kDragSlopDefault));
    final delta = switch (position.axisDirection) {
      AxisDirection.up => Offset(0, distance),
      AxisDirection.down => Offset(0, -distance),
      _ => throw StateError('Main timeline must scroll vertically'),
    };
    final latest = find.byKey(StudioDriverKeys.timelineReturnLive);
    Map<String, Object?> gestureCut() => {
      'beforePixels': beforePixels,
      'pixels': position.pixels,
      'maxExtent': position.maxScrollExtent,
      'axis': position.axisDirection.name,
      'viewportDimension': position.viewportDimension,
      'plannedDrag': {'dx': delta.dx, 'dy': delta.dy},
      'mode': originalLease.mode.name,
      'returnButtonOnstage': latest.evaluate().length,
      'returnButtonAll': find
          .byKey(StudioDriverKeys.timelineReturnLive, skipOffstage: false)
          .evaluate()
          .length,
      'returnButtonHitTestable': latest.hitTestable().evaluate().length,
    };
    debugPrintSynchronously(
      'Main history gesture prepared: ${jsonEncode(gestureCut())}',
    );
    await tester.drag(main, delta);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expectOriginalPosition();
    debugPrintSynchronously(
      'Main history gesture applied: ${jsonEncode(gestureCut())}',
    );
    await until(() {
      expectOriginalPosition();
      return originalLease.mode == TimelineDisplayMode.history &&
          latest.evaluate().length == 1 &&
          latest.hitTestable().evaluate().length == 1;
    }, 'production return-to-latest action after reading history');
    await tap(latest);
    await until(() {
      expectOriginalPosition();
      return position.pixels.abs() < 0.5 &&
          originalLease.mode == TimelineDisplayMode.live;
    }, 'latest timeline viewport after reading receipts');
  }

  Future<void> until(
    bool Function() ready,
    String description, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final clock = Stopwatch()..start();
    while (!ready()) {
      if (clock.elapsed >= timeout) {
        fail('Timed out waiting for $description');
      }
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    }
  }

  Future<void> untilKey(
    Key key, {
    Duration timeout = const Duration(seconds: 60),
  }) => until(
    () => find.byKey(key).evaluate().isNotEmpty,
    'laid out $key',
    timeout: timeout,
  );

  Future<void> tap(Finder finder) async {
    await until(() => finder.evaluate().isNotEmpty, finder.toString());
    await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
    await tester.pump();
    await until(
      () => finder.hitTestable().evaluate().length == 1,
      'hittable $finder',
    );
    await tester.tap(finder);
    await tester.pump();
  }

  Future<void> submit(String prompt) async {
    final input = find.byKey(const ValueKey('composer-input'));
    final composerView = find.byType(PromptComposerView);
    String? previousReadiness;
    await until(() {
      final selection = graph.client.selection.state;
      final project = graph.client.project.state.projects?.values
          .where((candidate) => candidate.id == selection.selectedProjectId)
          .firstOrNull;
      final readiness = jsonEncode({
        'projectId': selection.selectedProjectId,
        'threadId': selection.selectedThreadId,
        'projectPath': project?.path,
        'expectedProjectPath': projectPath,
        'needsOpen': selection.needsOpen,
        'inputCount': input.evaluate().length,
        'composerCount': composerView.evaluate().length,
        if (composerView.evaluate().length == 1)
          'composerEnabled': tester
              .widget<PromptComposerView>(composerView)
              .state
              .enabled,
      });
      if (readiness != previousReadiness) {
        debugPrintSynchronously('Realtime composer readiness: $readiness');
        previousReadiness = readiness;
      }
      if (project == null ||
          !FileSystemEntity.identicalSync(project.path, projectPath) ||
          selection.needsOpen ||
          input.evaluate().length != 1 ||
          composerView.evaluate().length != 1) {
        return false;
      }
      final composer = tester.widget<PromptComposerView>(composerView);
      final field = tester.widget<TextField>(input);
      return composer.state.enabled &&
          switch (composer.targetKey) {
            ThreadComposerTarget(:final threadId) =>
              threadId == selection.selectedThreadId,
            StartComposerTarget(:final workspaceId) =>
              selection.selectedThreadId == null &&
                  workspaceId == selection.selectedProjectId,
            _ => false,
          } &&
          (field.enabled ?? true);
    }, 'editable composer bound to the selected project and conversation');
    final selection = graph.client.selection.state;
    final controller = tester.widget<TextField>(input).controller!;
    final target = tester.widget<PromptComposerView>(composerView).targetKey;
    void recordInput(String phase) {
      final current = tester.widget<TextField>(input);
      final composer = tester.widget<PromptComposerView>(composerView);
      final selected = graph.client.selection.state;
      debugPrintSynchronously(
        'Realtime composer input: ${jsonEncode({'phase': phase, 'projectId': selected.selectedProjectId, 'threadId': selected.selectedThreadId, 'needsOpen': selected.needsOpen, 'navigation': graph.client.selection.navigationGeneration, 'target': composerTargetDiagnostic(composer.targetKey), 'element': identityHashCode(tester.element(input)), 'controller': identityHashCode(current.controller), 'enabled': current.enabled, 'draft': composer.state.composer.draft, 'text': current.controller?.text})}',
      );
    }

    try {
      recordInput('before');
      await tester.enterText(input, prompt);
      recordInput('entered');
      expect(controller.text, prompt);
      await tester.pump();
      recordInput('after-frame');
      expect(
        graph.client.selection.state.selectedProjectId,
        selection.selectedProjectId,
      );
      expect(
        graph.client.selection.state.selectedThreadId,
        selection.selectedThreadId,
      );
      expect(tester.widget<TextField>(input).controller, same(controller));
      expect(tester.widget<PromptComposerView>(composerView).targetKey, target);
      expect(controller.text, prompt);
      _submittedThreadId = selection.selectedThreadId;
      _priorTurn = _submittedThreadId == null
          ? null
          : graph.client.conversations
                .session(_submittedThreadId!)
                .state
                .lastTurn
                ?.turnId;
      _submittedTurnId = null;
      await tap(find.byKey(const ValueKey('composer-submit')));
    } catch (_) {
      final composer = tester.widget<PromptComposerView>(
        find.byType(PromptComposerView),
      );
      debugPrintSynchronously(
        'Realtime submission failure: draft=${composer.state.composer.draft}, '
        'pending=${composer.state.composer.isSubmissionPending}, '
        'execution=${composer.state.execution?.id}/${composer.state.execution?.phase}, '
        'blocker=${composer.state.blocker}, failure=${composer.state.failure}',
      );
      rethrow;
    }
  }

  Future<void> completed({required String answer}) async {
    await terminal(StudioTurnStatus.completed);
    await tester.pump();
    final returnToLatest = find
        .byKey(StudioDriverKeys.timelineReturnLive)
        .hitTestable();
    if (returnToLatest.evaluate().isNotEmpty) {
      await tap(returnToLatest);
    }
    final clock = Stopwatch()..start();
    Duration remaining() {
      final duration = const Duration(minutes: 2) - clock.elapsed;
      if (duration <= Duration.zero) {
        fail('Timed out waiting for completed answer "$answer"');
      }
      return duration;
    }

    try {
      expect(_submittedTurnId, isNotNull);
      final turnId = _submittedTurnId!;
      final source = ForegroundTurnChatSource(turnId: turnId);
      TimelineDisplayUnit? admittedAnswer() {
        final matches = observed.singleBlocks
            .where(
              (item) =>
                  item.atom!.source == source &&
                  item.atom!.turnId == turnId &&
                  item.atom!.kind == ChatAtomKind.text &&
                  item.atom!.textChannel == ThreadTextChannel.finalAnswer &&
                  (item.atom!.lifecycle as TerminalChatAtom).outcome ==
                      ChatTerminalOutcome.completed,
            )
            .toList();
        expect(matches.length, lessThanOrEqualTo(1));
        return matches.singleOrNull;
      }

      TimelineDisplayUnit? target;
      await until(
        () {
          remaining();
          target = admittedAnswer();
          return target != null;
        },
        'unique Main completed answer for $turnId',
        timeout: remaining(),
      );
      final item = target!;
      await observed.revealSingle(item, timeout: remaining());
      final unit = observed.unit(item.id);
      expect(unit, same(item));
      expect(unit.historyPos!, greaterThan(0));
      final row = observed.itemRow(item.id);
      final originalScrollable = Scrollable.maybeOf(tester.element(row));
      final text = find
          .descendant(of: row, matching: find.textContaining(answer))
          .hitTestable();
      await until(
        () {
          remaining();
          expect(admittedAnswer(), same(item));
          expect(observed.unit(item.id), same(unit));
          if (!_laidOut(row)) return false;
          final rendered = tester.widget<ChatItemView>(row).item;
          expect(rendered.compatibility, ChatItemCompatibility.current);
          expect(rendered.type, 'text');
          expect(rendered.displayUnit, same(unit));
          expect(
            Scrollable.maybeOf(tester.element(row)),
            same(originalScrollable),
          );
          return _laidOut(text);
        },
        'completed answer "$answer"',
        timeout: remaining(),
      );
    } catch (_) {
      final scroll = lease.scrollController;
      debugPrintSynchronously(
        'Missing completed answer: ${jsonEncode({'answer': answer, 'mainPixels': scroll.hasClients ? scroll.position.pixels : null, 'mainMaxExtent': scroll.hasClients ? scroll.position.maxScrollExtent : null, 'returnActionVisible': returnToLatest.evaluate().isNotEmpty, 'renderedRows': find.byType(ChatItemView).evaluate().length, 'latestItemIds': items.reversed.take(4).map((item) => item.id).toList()})}',
      );
      await capturePresentation(
        tester,
        'realtime-completed-answer-missing.png',
      );
      rethrow;
    }
  }

  Future<void> terminal(StudioTurnStatus kind) async {
    TimelineDisplayUnit? receipt;
    await until(
      () {
        final turn = _latestTurn();
        if (turn == null || turn.turnId == _priorTurn) return false;
        _submittedTurnId ??= turn.turnId;
        if (turn.turnId != _submittedTurnId) return false;
        if (!turn.state.isTerminal ||
            turn.state.status != kind ||
            graph.timeline.lease(turn.threadId) == null) {
          return false;
        }
        if (kind == StudioTurnStatus.cancelled) {
          final state = graph.client.conversations.session(turn.threadId).state;
          if (turn.state.isBusy ||
              (state.activeTurn?.state.isBusy ?? false) ||
              state.runtime?.execution != null) {
            return false;
          }
        }
        final source = ForegroundTurnChatSource(turnId: turn.turnId);
        // State proves the outcome; Main admission remains independent and
        // uses the original wait budget, without a normal completion item.
        if (!observed.singleBlocks.any((item) => item.atom!.source == source) ||
            graph.client.conversations
                    .session(turn.threadId)
                    .state
                    .runtime
                    ?.execution !=
                null) {
          return false;
        }
        if (kind == StudioTurnStatus.failed ||
            kind == StudioTurnStatus.cancelled) {
          final outcome = kind == StudioTurnStatus.failed
              ? ChatTerminalOutcome.failed
              : ChatTerminalOutcome.cancelled;
          final matches = observed.singleBlocks
              .where(
                (item) =>
                    item.atom!.source == source &&
                    item.atom!.kind == ChatAtomKind.turnReceipt,
              )
              .toList();
          expect(matches.length, lessThanOrEqualTo(1));
          receipt = matches.singleOrNull;
          return (receipt?.atom?.lifecycle as TerminalChatAtom?)?.outcome ==
              outcome;
        }
        return true;
      },
      '${kind.name} realtime Turn',
      timeout: const Duration(minutes: 3),
    );
    if (kind == StudioTurnStatus.failed || kind == StudioTurnStatus.cancelled) {
      _expectTurnReceiptHead(receipt!);
      await observed.revealSingle(receipt!);
      final rendered = await _awaitCanonicalRow(
        observed.itemRow(receipt!.id),
        receipt!.atom!,
        type: 'turn',
      );
      expect(rendered.compatibility, ChatItemCompatibility.current);
      expect(rendered.type, 'turn');
      expect((rendered.data['outcome'] as Map)['kind'], kind.name);
    }
  }

  Future<ChatAtom> untilReadableCurrentText({required Duration timeout}) async {
    final observationId = ++_liveTextObservation;
    final clock = Stopwatch()..start();
    final observations = <Map<String, Object?>>[];
    Map<String, Object?>? lastObservation;
    String? previousObservation;
    String? failure;
    ChatAtom? accepted;
    try {
      await until(
        () {
          final turn = _latestTurn();
          if (turn != null && turn.turnId != _priorTurn) {
            _submittedTurnId ??= turn.turnId;
          }
          final live = observed.liveAtoms.toList();
          final candidates = live
              .where(
                (atom) =>
                    turn != null &&
                    turn.turnId == _submittedTurnId &&
                    turn.turnId != _priorTurn &&
                    atom.turnId == turn.turnId &&
                    atom.source ==
                        ForegroundTurnChatSource(turnId: turn.turnId) &&
                    atom.kind == ChatAtomKind.text &&
                    atom.lifecycle is ActiveChatAtom,
              )
              .toList();
          // These are fresh synchronous borrows for this predicate invocation,
          // not a lease or window retained across its next pump.
          final liveCut = lease.live.value;
          final allWindows = liveWindows.toList();
          final views = tester
              .widgetList<ConversationCurrentWindowView>(
                find.byType(ConversationCurrentWindowView),
              )
              .toList();
          final state = {
            'selectedThreadId': graph.client.selection.state.selectedThreadId,
            'submittedThreadId': _submittedThreadId,
            'submittedTurnId': _submittedTurnId,
            'priorTurnId': _priorTurn,
            'turnId': turn?.turnId,
            'turnThreadId': turn?.threadId,
            'turnStatus': turn?.state.status.name,
            'leaseGeneration': lease.generation,
            'leaseMode': lease.mode.name,
            'contentPhase': lease.content.state.value.runtimeType.toString(),
            'livePresent': liveCut != null,
            'liveRevision': liveCut?.revision,
            'executionPresent': liveCut?.executionPresent,
            'displayMounted': lease.isMounted,
            'displayRetired': lease.isRetired,
            'live': [
              for (final unit in live)
                {
                  'id': unit.id,
                  'kind': unit.kind.name,
                  'atomKind': unit.kind.name,
                  'outcome': unit.lifecycle.runtimeType.toString(),
                  'sourceType': unit.source.runtimeType.toString(),
                  'sourceTurnId': unit.source is ForegroundTurnChatSource
                      ? (unit.source as ForegroundTurnChatSource).turnId
                      : null,
                  'matchesTurnSource':
                      turn != null &&
                      unit.source ==
                          ForegroundTurnChatSource(turnId: turn.turnId),
                  'references': [
                    for (final content in unit.contents)
                      contentReferenceIdentity(content.reference).toString(),
                  ],
                },
            ],
            'candidateIds': candidates.map((item) => item.id).toList(),
            'views': [
              for (final view in views)
                {
                  'id': view.id,
                  'laidOut': _laidOut(find.byWidget(view)),
                  'textCodeUnits': view.text.length,
                  'error': view.error?.toString(),
                  'offset': view.offset,
                  'end': view.end,
                  'availableThrough': view.availableThrough,
                },
            ],
            'windows': [
              for (final window in allWindows)
                {
                  'id': window.id,
                  'reference': contentReferenceIdentity(window.reference)
                      .toString(),
                  'error': window.error?.toString(),
                  'ready': window.window != null,
                  'generation': window.window?.generation,
                  'offset': window.window?.offset,
                  'bytes': window.window?.bytes.length,
                  'availableThrough': window.window?.availableThrough,
                  'sealed': window.window?.sealed,
                },
            ],
          };
          final signature = jsonEncode(state);
          if (signature != previousObservation) {
            final observation = {
              'elapsedMillis': clock.elapsedMilliseconds,
              ...state,
            };
            lastObservation = observation;
            if (observations.length < 32) {
              observations.add(observation);
            }
            previousObservation = signature;
          }
          for (final head in observed.liveBlocks.expand(
            observed.liveDisplayRecords,
          )) {
            final atom = head.record.atom;
            if (!candidates.any(
              (candidate) =>
                  candidate.id == atom.id && candidate.source == atom.source,
            )) {
              continue;
            }
            if (liveCut?.executionPresent != true) continue;
            final row = observed.liveRenderer(head);
            if (row.evaluate().length != 1) continue;
            final view = find.descendant(
              of: row,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is ConversationCurrentWindowView &&
                    widget.id == head.displayId &&
                    widget.error == null &&
                    widget.text.isNotEmpty,
              ),
            );
            if (!_laidOut(view)) continue;
            final body = atom.contents
                .where((content) => content.role == ChatContentRole.body)
                .singleOrNull;
            if (body == null) continue;
            final renderer = tester.state(row) as TimelineMemberDisplay;
            final windows = renderer.windows
                .where(
                  (window) =>
                      window.id == head.displayId &&
                      contentReferenceIdentity(window.reference) ==
                          contentReferenceIdentity(body.reference),
                )
                .toList();
            for (final window in windows) {
              if (window.error case final error?) throw StateError('$error');
            }
            if (windows.isEmpty ||
                windows.every(
                  (window) => window.window?.bytes.isNotEmpty != true,
                )) {
              continue;
            }
            for (final window in windows) {
              expect(
                window.window?.bytes.length ?? 0,
                lessThanOrEqualTo(64 * 1024),
              );
            }
            accepted = atom;
            return true;
          }
          return false;
        },
        'readable production live text with its original content-window borrow',
        timeout: timeout,
      );
      return accepted!;
    } catch (error) {
      failure = error.toString();
      rethrow;
    } finally {
      final output = Platform.environment['ANYWORK_REALTIME_OUTPUT']!;
      await File.fromUri(
        Directory(output).uri.resolve('realtime-live-text-$observationId.json'),
      ).writeAsString(
        '${const JsonEncoder.withIndent('  ').convert({'acceptedItemId': accepted?.id, 'failure': failure, 'timeoutMillis': timeout.inMilliseconds, 'observations': observations, 'lastObservation': lastObservation})}\n',
      );
    }
  }

  bool _sameToolAtom(ChatAtom candidate, ChatAtom atom) =>
      candidate.id == atom.id &&
      candidate.source == atom.source &&
      candidate.turnId == atom.turnId &&
      candidate.kind == atom.kind &&
      candidate.tool?.callId == atom.tool?.callId &&
      candidate.tool?.name == atom.tool?.name &&
      (candidate.lifecycle is ActiveChatAtom) ==
          (atom.lifecycle is ActiveChatAtom) &&
      candidate.completionItemId == atom.completionItemId &&
      candidate.completionSeq == atom.completionSeq;

  bool _isOriginalToolCompletion(DisplayRecord record, ChatAtom atom) {
    final source = record.contentSource;
    return atom.lifecycle is TerminalChatAtom &&
        record.atom.lifecycle is TerminalChatAtom &&
        source is CompletedOriginal &&
        atom.completionItemId != null &&
        atom.completionSeq != null &&
        source.completionId == atom.completionItemId &&
        _sameToolAtom(record.atom, atom);
  }

  Iterable<ObservedLiveDisplayRecord> _toolDisplayRecords(ChatAtom atom) sync* {
    for (final block in observed.liveBlocks) {
      for (final head in observed.liveDisplayRecords(block)) {
        if (!_sameToolAtom(head.record.atom, atom)) continue;
        if (atom.lifecycle is ActiveChatAtom) {
          if (block.state != DisplayBlockState.open ||
              head.record.contentSource is! CurrentAtom) {
            continue;
          }
        } else if (!_isOriginalToolCompletion(head.record, atom)) {
          continue;
        }
        yield head;
      }
    }
    // Completed tools can still be borrowed from their mounted original Work.
    // Read only that renderer's admitted page, never open another member query.
    if (atom.lifecycle is! TerminalChatAtom ||
        atom.completionItemId == null ||
        atom.completionSeq == null) {
      return;
    }
    for (final unit in observed.workBlocks) {
      final display = lease.groupDisplays
          .where(
            (display) =>
                display.unitId == unit.id &&
                display.blockReference == unit.memberReference &&
                display.expanded &&
                !display.loading,
          )
          .singleOrNull;
      if (display == null) continue;
      expect(display.error, isNull);
      final page = unit.expansion.members?.page;
      if (page == null) continue;
      expect(page.block, display.blockReference);
      for (final head in page.entries) {
        if (_isOriginalToolCompletion(head.record, atom)) {
          yield (
            blockId: unit.id,
            displayId: head.memberKey,
            record: head.record,
          );
        }
      }
    }
  }

  Finder _unscopedToolCard(
    ChatAtom atom, {
    List<ObservedLiveDisplayRecord>? records,
  }) {
    final heads = records ?? _toolDisplayRecords(atom).toList();
    final waitIds = <String>{};
    for (final head in heads) {
      final reading = tester
          .widgetList<ChatItemView>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is ChatItemView &&
                  widget.item.id == head.displayId &&
                  widget.item.atom != null &&
                  _sameToolAtom(widget.item.atom!, atom),
            ),
          )
          .singleOrNull
          ?.item
          .toolCard;
      // Use the actual renderer's typed facts for active and completed waits.
      if (head.record.atom.wait != null ||
          (reading is DecodedToolCard && reading.value.wait != null)) {
        waitIds.add(head.displayId);
      }
    }
    return find.byWidgetPredicate(
      (widget) => heads.any(
        (head) => waitIds.contains(head.displayId)
            ? widget is TimelineWaitPanel && widget.identity == head.displayId
            : widget is TimelineToolDetails &&
                  widget.item.id == head.displayId &&
                  widget.item.toolCallId == atom.tool?.callId &&
                  widget.item.name == atom.tool?.name,
      ),
    );
  }

  Finder currentToolCard(ChatAtom atom) {
    final originalLease = lease;
    final active = atom.lifecycle is ActiveChatAtom;
    final heads = _toolDisplayRecords(atom).toList();
    final runs = [
      for (final display in originalLease.groupDisplays)
        if (display.isCurrent &&
            heads.any((head) => head.blockId == display.unitId))
          display.blockReference,
    ];
    final singles = observed.liveBlocks.where(
      (block) =>
          block.body is SingleDisplayBlock &&
          heads.any((head) => head.blockId == block.id),
    );
    final scope = find.byWidgetPredicate(
      (widget) =>
          originalLease.isMounted &&
          !originalLease.isRetired &&
          ((widget is ConversationCurrentConnector &&
                  singles.isNotEmpty &&
                  identical(widget.content, originalLease.content) &&
                  widget.isDisplayActive()) ||
              (widget is CompletionRunConnector &&
                  widget.threadId == originalLease.threadId &&
                  identical(widget.content, originalLease.content) &&
                  heads.any((head) => head.blockId == widget.unit.id) &&
                  runs.contains(widget.unit.memberReference) &&
                  widget.unit.expansion.expanded == true)),
    );
    final member = find.descendant(
      of: scope,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is TimelineMemberAtom &&
            widget.isActive() &&
            heads.any(
              (head) =>
                  widget.displayId == head.displayId &&
                  widget.record == head.record,
            ) &&
            widget.atom.id == atom.id &&
            widget.atom.source == atom.source &&
            (widget.atom.lifecycle is ActiveChatAtom) == active &&
            widget.atom.completionItemId == atom.completionItemId &&
            widget.atom.completionSeq == atom.completionSeq &&
            (active
                ? identical(widget.content, originalLease.content)
                : atom.completionItemId != null &&
                      atom.lifecycle is TerminalChatAtom),
      ),
    );
    return find.descendant(
      of: member,
      matching: _unscopedToolCard(atom, records: heads),
    );
  }

  Map<String, Object?> _toolFinderObservation(ChatAtom atom) {
    final all = _unscopedToolCard(atom).evaluate().toList();
    return {
      'displayIds': _toolDisplayRecords(atom)
          .map((head) => head.displayId)
          .toList(),
      'unscopedCount': all.length,
      'qualifiedCount': currentToolCard(atom).evaluate().length,
      'matches': [
        for (final element in all.take(6))
          (() {
            final match = <String, Object?>{
              'widget': element.widget.runtimeType.toString(),
            };
            element.visitAncestorElements((ancestor) {
              final widget = ancestor.widget;
              if (widget is TimelineMemberAtom) {
                match['member'] = {
                  'id': widget.atom.id,
                  'displayId': widget.displayId,
                  'lifecycle': widget.atom.lifecycle.runtimeType.toString(),
                  'completionItemId': widget.atom.completionItemId,
                  'completionSeq': widget.atom.completionSeq,
                  'contentIdentity': identityHashCode(widget.content),
                  'sameMainContent': identical(widget.content, lease.content),
                  'activeScope': widget.isActive(),
                };
              } else if (widget is ConversationCurrentConnector) {
                match['scope'] = 'Timeline live';
                match['scopeActive'] = widget.isDisplayActive();
                match['sameMainContent'] = identical(
                  widget.content,
                  lease.content,
                );
              } else if (widget is CompletionRunConnector) {
                match['scope'] = 'Work';
                match['blockId'] = widget.unit.id;
                match['scopeActive'] = widget.unit.expansion.expanded;
              }
              return true;
            });
            return match;
          })(),
      ],
    };
  }

  int _toolObservationSequence = 0;

  Future<void> untilLaidOutCurrentTools({
    required int minimum,
    Set<String> toolCallIds = const {},
    Set<String> handedOffExecCallIds = const {},
    bool settleDisclosure = true,
    _PreparedToolObserver? preparedObserver,
    Future<({Future<void> completed})> Function(
      void Function(String phase) onProgress,
    )?
    beginRelease,
  }) async {
    final clock = Stopwatch()..start();
    var settled = !settleDisclosure;
    final observations = <Map<String, Object?>>[];
    if (preparedObserver != null) {
      preparedObserver.evidence['observations'] = observations;
    }
    String? previousObservation;
    final phases = <String, int>{};
    final admissions = <Map<String, Object?>>[];
    final frames = <Map<String, Object?>>[];
    var admissionsTruncated = 0;
    var framesTruncated = 0;
    var iteration = 0;
    Future<void>? releaseCompletion;
    ({Object error, StackTrace stack})? releaseFailure;
    String? observationFailure;
    final memberController = preparedObserver?.memberController;
    void recordAdmission() {
      if (admissions.length >= 128) {
        admissionsTruncated++;
        return;
      }
      final page = memberController!.page;
      admissions.add({
        'sampleMillis': clock.elapsedMilliseconds,
        'revision': page?.revision,
        'controllerIdentity': identityHashCode(memberController),
        'samePreparedController': identical(
          memberController,
          preparedObserver!.memberController,
        ),
        'loading': memberController.loading,
        'error': memberController.error?.toString(),
        'members': [
          for (final head in page?.entries ?? const <DisplayMemberHead>[])
            if (handedOffExecCallIds.contains(head.record.atom.tool?.callId))
              {
                'callId': head.record.atom.tool?.callId,
                'memberKey': head.memberKey,
                'lifecycle': head.record.atom.lifecycle.runtimeType.toString(),
                'completionItemId': head.record.atom.completionItemId,
              },
        ],
      });
    }

    void throwReleaseFailure() {
      final failure = releaseFailure;
      if (failure != null) {
        Error.throwWithStackTrace(failure.error, failure.stack);
      }
    }

    try {
      if (beginRelease != null) {
        expect(preparedObserver, isNotNull);
        memberController!.addListener(recordAdmission);
        recordAdmission();
        final release = await beginRelease((phase) {
          phases[phase] = clock.elapsedMilliseconds;
        });
        releaseCompletion = release.completed.then<void>(
          (_) {
            preparedObserver!.evidence['gateReleased'] = true;
          },
          onError: (Object error, StackTrace stack) {
            releaseFailure = (error: error, stack: stack);
          },
        );
        phases['observationStarted'] = clock.elapsedMilliseconds;
      }
      while (true) {
        throwReleaseFailure();
        final frame = beginRelease == null
            ? null
            : <String, Object?>{
                'iteration': iteration++,
                'sampleMillis': clock.elapsedMilliseconds,
                'revision': memberController!.page?.revision,
                'pumpStart': null,
                'pumpEnd': null,
              };
        if (frame != null) {
          if (frames.length < 512) {
            frames.add(frame);
          } else {
            framesTruncated++;
          }
        }
        Future<void> pumpObservedFrame(Duration duration) async {
          frame?['pumpStart'] = clock.elapsedMilliseconds;
          try {
            await tester.pump(duration);
          } finally {
            frame?['pumpEnd'] = clock.elapsedMilliseconds;
          }
          throwReleaseFailure();
        }

        final turn = _latestTurn();
        if (turn != null && turn.turnId != _priorTurn) {
          _submittedTurnId ??= turn.turnId;
          expect(turn.turnId, _submittedTurnId);
        }
        // The gated observer already proved the source and opened its Work.
        // Do not query every historical Work before sampling a one-second
        // foreground-call window; borrow the same admitted reference instead.
        final units = [
          if (preparedObserver != null)
            observed.unitForBlock(preparedObserver.reference)
          else if (turn != null && turn.turnId == _submittedTurnId)
            ...await observed.workForSource(
              ForegroundTurnChatSource(turnId: turn.turnId),
            ),
        ];
        final openingStartedMillis = clock.elapsedMilliseconds;
        if (preparedObserver == null) {
          for (final unit in units) {
            await observed.openWork(unit.id);
          }
        }
        // Keep every original identity/error assertion even while the same
        // reader temporarily cannot lend an admitted member window.
        final observerReady =
            preparedObserver == null ||
            _expectPreparedToolObserver(preparedObserver);
        final groupIds = units.map((unit) => unit.id).toSet();
        final expectedCallIds = {...toolCallIds, ...handedOffExecCallIds};
        if (preparedObserver != null) {
          expect(units.single.id, preparedObserver.display.unitId);
          expect(units.single.historyPos, isNull);
          expect(lease.live.value!.executionPresent, isTrue);
          expect(observed.liveWork.map((unit) => unit.id).toList(), [
            preparedObserver.display.unitId,
          ]);
          if (observerReady) {
            final display = lease.groupDisplays.singleWhere(
              (display) => display.unitId == preparedObserver.display.unitId,
            );
            for (final atom in display.atoms.where(
              (atom) =>
                  atom.delivery != ChatDeliveryKind.independent &&
                  expectedCallIds.contains(atom.tool?.callId),
            )) {
              expect(
                atom.source,
                ForegroundTurnChatSource(turnId: preparedObserver.turnId),
              );
              expect(atom.turnId, preparedObserver.turnId);
            }
          }
        }
        final tools = !observerReady
            ? null
            : observed.liveAtoms
                  .where(
                    (atom) =>
                        atom.turnId == _submittedTurnId &&
                        atom.kind == ChatAtomKind.toolCall,
                  )
                  .toList();
        final handedOff = tools
            ?.where(
              (atom) =>
                  atom.tool?.name == 'exec' &&
                  atom.delivery == ChatDeliveryKind.backgroundHandoff &&
                  atom.lifecycle is TerminalChatAtom &&
                  (atom.lifecycle as TerminalChatAtom).outcome ==
                      ChatTerminalOutcome.transferred,
            )
            .map((atom) => atom.tool!.callId)
            .toSet();
        final required = tools == null
            ? null
            : expectedCallIds.isEmpty
            ? tools
            : tools
                  .where((atom) => expectedCallIds.contains(atom.tool?.callId))
                  .toList();
        final laidOut = required
            ?.where((atom) => _laidOut(currentToolCard(atom)))
            .length;
        frame?.addAll({
          'sampleMillis': clock.elapsedMilliseconds,
          'revision': memberController?.page?.revision,
          'membersAvailable': observerReady,
          'members': [
            for (final callId in handedOffExecCallIds)
              {
                'callId': callId,
                'handedOff': handedOff?.contains(callId) ?? false,
                'laidOut':
                    required?.any(
                      (atom) =>
                          atom.tool?.callId == callId &&
                          _laidOut(currentToolCard(atom)),
                    ) ??
                    false,
              },
          ],
        });
        final observation = {
          'groupIds': groupIds.toList(),
          'liveIds': observed.liveAtoms.map((atom) => atom.id).toList(),
          if (preparedObserver != null)
            'observer': _preparedToolObserverSnapshot(preparedObserver),
          'membersAvailable': observerReady,
          'members': tools
              ?.map(
                (atom) => {
                  'id': atom.id,
                  'callId': atom.tool?.callId,
                  'active': atom.lifecycle is ActiveChatAtom,
                  'laidOut': _laidOut(currentToolCard(atom)),
                  'finder': _toolFinderObservation(atom),
                },
              )
              .toList(),
        };
        final signature = jsonEncode(observation);
        if (signature != previousObservation && observations.length < 32) {
          observations.add({
            'openingStartedMillis': openingStartedMillis,
            'observedMillis': clock.elapsedMilliseconds,
            ...observation,
          });
        }
        previousObservation = signature;
        if (observerReady &&
            tools != null &&
            required != null &&
            handedOff != null &&
            tools.length >= minimum &&
            required.isNotEmpty &&
            required
                .map((atom) => atom.tool?.callId)
                .toSet()
                .containsAll(expectedCallIds) &&
            laidOut == required.length &&
            handedOff.containsAll(handedOffExecCallIds)) {
          if (!settled) {
            await pumpObservedFrame(const Duration(milliseconds: 300));
            expect(tester.takeException(), isNull);
            settled = true;
            continue;
          }
          expect(
            required.map((atom) => atom.tool?.callId).toSet(),
            hasLength(required.length),
          );
          for (final atom in required) {
            final title = find.descendant(
              of: currentToolCard(atom),
              matching: find.byType(TimelineActivityRow),
            );
            expect(title, findsOneWidget);
            expect(_laidOut(title), isTrue);
            final row = tester.widget<TimelineActivityRow>(title);
            expect(row.label.trim(), isNotEmpty);
            // A full-width row's center can be empty space. The real title
            // inside this exact atom's tool card must remain readable/hittable.
            final label = find.descendant(
              of: title,
              matching: find.text(row.label),
            );
            expect(label, findsOneWidget);
            expect(_laidOut(label), isTrue);
            expect(label.hitTestable(), findsOneWidget);
          }
          // Dispatch waits for each exec's foreground window in order. Both
          // processes overlap after handoff; their foreground atoms cannot
          // both be Active. Independent final receipts are checked separately.
          final taskIds = <String>{};
          for (final call in handedOffExecCallIds) {
            final atom = required.singleWhere(
              (atom) => atom.tool?.callId == call,
            );
            final widget = tester.widget<TimelineToolDetails>(
              currentToolCard(atom),
            );
            expect(widget.item.statusString, 'backgroundStarted');
            expect(widget.item.taskId, isNotNull);
            expect(widget.item.taskId, isNotEmpty);
            expect(taskIds.add(widget.item.taskId!), isTrue);
            expect(widget.item.exitCode, isNull);
          }
          for (var index = 1; index < required.length; index++) {
            expect(
              tester.getTopLeft(currentToolCard(required[index])).dy,
              greaterThanOrEqualTo(
                tester.getTopLeft(currentToolCard(required[index - 1])).dy,
              ),
              reason: 'rendered tools retain the owner-provided member order',
            );
          }
          debugPrintSynchronously(
            'Realtime current tools: ${jsonEncode({'minimum': minimum, 'atomIds': tools.map((atom) => atom.id).toList(), 'callIds': tools.map((atom) => atom.tool?.callId).toList(), 'exactHandedOffExecIds': handedOff.toList(), 'laidOut': laidOut, 'contentWindows': liveWindows.length})}',
          );
          if (preparedObserver != null) {
            expect(_expectPreparedToolObserver(preparedObserver), isTrue);
            preparedObserver.evidence['handoff'] =
                _preparedToolObserverSnapshot(
                  preparedObserver,
                  handedOff: required.where(
                    (atom) => handedOffExecCallIds.contains(atom.tool?.callId),
                  ),
                );
          }
          // Freeze the successful frame before any asynchronous provenance
          // query. A later background result cannot invalidate this witness.
          final handoffFrameJson =
              '${const JsonEncoder.withIndent('  ').convert({
                'turnId': _submittedTurnId,
                'expectedCallIds': expectedCallIds.toList(),
                'observations': observations,
                'matched': required.map((atom) => {'id': atom.id, 'finder': _toolFinderObservation(atom)}).toList(),
              })}\n';
          if (preparedObserver != null) {
            preparedObserver.evidence['handoffFrame'] = jsonDecode(
              handoffFrameJson,
            );
            final sourceWork = await observed.workForSource(
              ForegroundTurnChatSource(turnId: preparedObserver.turnId),
            );
            expect(sourceWork, hasLength(1));
            expect(sourceWork.single.id, preparedObserver.display.unitId);
            expect(
              sourceWork.single.memberReference,
              preparedObserver.reference,
            );
            preparedObserver.evidence['sourceRecheckAfterHandoffCut'] = {
              'unitId': sourceWork.single.id,
              'databaseId': sourceWork.single.memberReference!.databaseId,
              'blockId': sourceWork.single.memberReference!.blockId,
            };
          }
          final output = Platform.environment['ANYWORK_REALTIME_OUTPUT']!;
          await File.fromUri(
            Directory(output).uri.resolve(
              'realtime-tool-observation-${++_toolObservationSequence}.json',
            ),
          ).writeAsString(handoffFrameJson);
          return;
        }
        if (clock.elapsed >= const Duration(minutes: 3)) {
          fail('Timed out waiting for $minimum real current tool cards');
        }
        await pumpObservedFrame(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull);
      }
    } catch (error) {
      observationFailure = error.toString();
      final output = Platform.environment['ANYWORK_REALTIME_OUTPUT']!;
      await File.fromUri(
        Directory(output).uri.resolve('realtime-tool-observation-failure.json'),
      ).writeAsString(
        '${const JsonEncoder.withIndent('  ').convert({
          'turnId': _submittedTurnId,
          'expectedCallIds': {...toolCallIds, ...handedOffExecCallIds}.toList(),
          'handedOffExecCallIds': handedOffExecCallIds.toList(),
          'observations': observations,
        })}\n',
      );
      debugPrintSynchronously(
        'Realtime tool observation failure: ${jsonEncode({
          'turnId': _submittedTurnId,
          'liveIds': observed.liveAtoms.map((atom) => atom.id).toList(),
          'groups': lease.groupDisplays.map((display) => {
            'id': display.unitId,
            'current': display.isCurrent,
            'expanded': display.expanded,
            'loading': display.loading,
            'membersAvailable': display.isCurrent && !display.loading,
            'error': display.error?.toString(),
            'members': display.isCurrent && !display.loading ? display.atoms.map((atom) => {'id': atom.id, 'callId': atom.tool?.callId, 'active': atom.lifecycle is ActiveChatAtom, 'laidOut': _laidOut(currentToolCard(atom))}).toList() : null,
          }).toList(),
        })}',
      );
      await capturePresentation(
        tester,
        'realtime-current-tools-$minimum-failure.png',
      );
      rethrow;
    } finally {
      if (beginRelease != null) {
        memberController?.removeListener(recordAdmission);
        try {
          // Pumping has ended. Join the I/O started outside the tester guard,
          // including its 204 check and client cleanup, before returning.
          await releaseCompletion;
          throwReleaseFailure();
        } finally {
          final output = Platform.environment['ANYWORK_REALTIME_OUTPUT']!;
          await File.fromUri(
            Directory(output).uri
                .resolve('realtime-parallel-release-frames.json'),
          ).writeAsString(
            '${const JsonEncoder.withIndent('  ').convert({'turnId': _submittedTurnId, 'expectedCallIds': handedOffExecCallIds.toList(), 'phasesMillis': phases, 'admissions': admissions, 'admissionsTruncated': admissionsTruncated, 'frames': frames, 'framesTruncated': framesTruncated, 'observationFailure': observationFailure, 'releaseFailure': releaseFailure?.error.toString(), 'releaseFailureStack': releaseFailure?.stack.toString()})}\n',
          );
        }
      }
    }
  }

  StudioTurnView? _latestTurn() {
    final threadId = graph.client.selection.state.selectedThreadId;
    if (threadId == null) return null;
    _submittedThreadId ??= threadId;
    if (threadId != _submittedThreadId) return null;
    final turn = graph.client.conversations.session(threadId).state.lastTurn;
    return turn?.threadId == threadId ? turn : null;
  }
}

bool _laidOut(Finder finder) {
  final elements = finder.evaluate();
  if (elements.length != 1) return false;
  final render = elements.single.findRenderObject();
  return render is RenderBox &&
      render.attached &&
      render.hasSize &&
      !render.size.isEmpty;
}

Future<void> _revealTextFragment(
  WidgetTester tester,
  Finder finder,
  String fragment, {
  double alignment = 0.5,
  ScrollPosition? expectedScrollPosition,
}) async {
  expect(_laidOut(finder), isTrue);
  // Consume the existing layout allowance before measuring the glyphs: an
  // admitted body can still be inside an expanding outer disclosure.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(tester.takeException(), isNull);
  expect(_laidOut(finder), isTrue);
  final text = find.descendant(
    of: finder,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is RichText && widget.text.toPlainText().contains(fragment),
    ),
  );
  expect(text, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(text);
  final start = paragraph.text.toPlainText().indexOf(fragment);
  expect(start, greaterThanOrEqualTo(0));
  final selection = TextSelection(
    baseOffset: start,
    extentOffset: start + fragment.length,
  );
  final boxes = paragraph.getBoxesForSelection(selection);
  expect(boxes, isNotEmpty);
  final bounds = boxes
      .map((box) => box.toRect())
      .reduce((left, right) => left.expandToInclude(right));
  final viewport = RenderAbstractViewport.of(paragraph);
  final position = Scrollable.of(tester.element(text)).position;
  if (expectedScrollPosition != null) {
    expect(position, same(expectedScrollPosition));
  }
  // Align the actual glyph range in its own viewport, centered by default.
  // Explicit edge alignment can reserve space for related content in Main.
  final reveal = viewport.getOffsetToReveal(paragraph, alignment, rect: bounds);
  await position.moveTo(reveal.offset, duration: Duration.zero);
  await tester.pump();
  expect(tester.takeException(), isNull);
  expect(tester.renderObject<RenderParagraph>(text), same(paragraph));
  // Preserve outward reveal for callers inside nested disclosures, using the
  // current glyph geometry rather than the pre-scroll measurement.
  final currentBounds = paragraph
      .getBoxesForSelection(selection)
      .map((box) => box.toRect())
      .reduce((left, right) => left.expandToInclude(right));
  paragraph.showOnScreen(rect: currentBounds);
  await tester.pump();
  expect(tester.takeException(), isNull);
  expect(tester.renderObject<RenderParagraph>(text), same(paragraph));
  _expectTextFragmentVisible(tester, finder, fragment);
}

void _expectTextFragmentVisible(
  WidgetTester tester,
  Finder finder,
  String fragment, {
  bool hitTestable = false,
}) {
  expect(_laidOut(finder), isTrue);
  final text = find.descendant(
    of: finder,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is RichText && widget.text.toPlainText().contains(fragment),
    ),
  );
  expect(text, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(text);
  final start = paragraph.text.toPlainText().indexOf(fragment);
  expect(start, greaterThanOrEqualTo(0));
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: start + fragment.length),
  );
  expect(boxes, isNotEmpty);
  for (final box in boxes) {
    final local = box.toRect();
    final rect = Rect.fromPoints(
      paragraph.localToGlobal(local.topLeft),
      paragraph.localToGlobal(local.bottomRight),
    );
    RenderObject? ancestor = paragraph.parent;
    while (ancestor != null) {
      if ((ancestor is RenderClipRect || ancestor is RenderAbstractViewport) &&
          ancestor is RenderBox) {
        final viewport = (ancestor.localToGlobal(Offset.zero) & ancestor.size)
            .inflate(1);
        final diagnostic =
            '$fragment $rect in ${ancestor.runtimeType} $viewport; '
            '${Scrollable.maybeOf(tester.element(text))?.position}';
        expect(viewport.contains(rect.topLeft), isTrue, reason: diagnostic);
        expect(viewport.contains(rect.bottomRight), isTrue, reason: diagnostic);
      }
      ancestor = ancestor.parent;
    }
    if (hitTestable) {
      expect(
        tester
            .hitTestOnBinding(rect.center)
            .path
            .any((entry) => identical(entry.target, paragraph)),
        isTrue,
        reason:
            'The actual $fragment glyphs must be hit-testable, not the '
            'center of a larger multi-line text widget',
      );
    }
  }
}
