import 'dart:convert';
import 'dart:io';

import 'package:anywork/src/app/app_composition.dart';
import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/routing/app_route.dart';
import 'package:anywork/src/app/routing/application_router.dart';
import 'package:anywork/src/app/studio_shutdown.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/composer/views/prompt_composer_view.dart';
import 'package:anywork/src/features/conversation/timeline/previews/conversation_live_status_previews.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/content_reference_identity.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_content_connector.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_payload_reading.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_diagnostics.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
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
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/fixture_gate.dart';
import 'support/presentation_capture.dart';
import 'support/timeline_observation.dart';

const _firstTokenObserverStage = 'realtime-first-token';
const _readableTextObserverStage = 'realtime-text-readable';
const _parallelObserverStage = 'realtime-parallel-observer';
const _parallelObserverPrefix = 'realtime parallel observers ready';
const _hostCwdObserverStage = 'realtime-host-cwd-observer';
const _hostCwdObserverPrefix = 'realtime host cwd observers ready';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  final project = Platform.environment['ANYWORK_REALTIME_PROJECT'];
  final output = Platform.environment['ANYWORK_REALTIME_OUTPUT'];
  final providerValue = Platform.environment['ANYWORK_REALTIME_PROVIDER'];
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
    'pass': false,
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
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router,
            ),
          ),
        ),
      );
      await graph.client.directoryCommands.openProject(project);
      graph.setConversationPageVisible(true);
      final scene = _RealtimeScene(tester, graph, project);

      await capturePresentation(tester, 'realtime-start.png');
      await scene.submit('Realtime delayed first token');
      await fixtureGate(tester, provider, _firstTokenObserverStage);
      await scene.untilKey(const ValueKey('conversation-activity'));
      expect(scene.observed.activity, isEmpty);
      await capturePresentation(tester, 'realtime-thinking.png');
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
      await capturePresentation(tester, 'realtime-streaming.png');
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
            scene.observed.activity.any(
              (entry) => entry.atom.kind == ChatAtomKind.reasoning,
            ) ||
            scene.observed.entries.any(
              (entry) => entry.atom.kind == ChatAtomKind.reasoning,
            ),
        'production Activity or completed history admits real reasoning',
      );
      await scene.completed(answer: 'realtime reasoning answer');
      await scene.openLatestTurnThinking();
      await capturePresentation(tester, 'realtime-reasoning.png');
      await scene.closeLatestTurnGroups();

      await scene.submit('Realtime long command');
      await scene.untilLaidOutCurrentTools(
        minimum: 2,
        toolCallIds: const {'realtime-long-call', 'realtime-long-wait-call'},
      );
      await capturePresentation(tester, 'realtime-exec-wait.png');
      await scene.completed(answer: 'realtime long command complete');
      await scene.closeLatestTurnGroups();

      final priorParallelItems = scene.observed.entries
          .map((item) => item.recordId)
          .toSet();
      await scene.submit('Realtime parallel tools');
      await fixtureGate(tester, provider, _parallelObserverStage);
      final parallelObserver = await scene.prepareToolObserver(
        stage: _parallelObserverStage,
        prefix: _parallelObserverPrefix,
        doneText: 'realtime parallel tools complete',
      );
      report['parallelObserver'] = parallelObserver.evidence;
      await fixtureGate(
        tester,
        provider,
        _parallelObserverStage,
        release: true,
      );
      parallelObserver.evidence['gateReleased'] = true;
      await scene.untilLaidOutCurrentTools(
        minimum: 2,
        runningExecCallIds: const {
          'realtime-parallel-call-a',
          'realtime-parallel-call-b',
        },
        settleDisclosure: false,
        preparedObserver: parallelObserver,
      );
      expect(
        find.text('realtime parallel tools complete'),
        findsNothing,
        reason: 'Both exact exec calls must be running before the final answer',
      );
      await capturePresentation(tester, 'realtime-parallel-running.png');
      await scene.completed(answer: 'realtime parallel tools complete');
      await scene.verifyExecReceipts(priorParallelItems, const {
        'realtime-parallel-call-a': 'realtime-parallel-a-line-05',
        'realtime-parallel-call-b': 'realtime-parallel-b-line-07',
      }, turnId: parallelObserver.turnId);
      await scene.closeLatestTurnGroups();

      final priorHostCwdItems = scene.observed.entries
          .map((item) => item.recordId)
          .toSet();
      await scene.submit('Realtime host cwd command');
      await fixtureGate(tester, provider, _hostCwdObserverStage);
      final hostObserver = await scene.prepareToolObserver(
        stage: _hostCwdObserverStage,
        prefix: _hostCwdObserverPrefix,
        doneText: 'realtime host cwd complete',
      );
      report['hostCwdObserver'] = hostObserver.evidence;
      await fixtureGate(tester, provider, _hostCwdObserverStage, release: true);
      hostObserver.evidence['gateReleased'] = true;
      await scene.untilLaidOutCurrentTools(
        minimum: 1,
        runningExecCallIds: const {'realtime-host-cwd-call'},
        settleDisclosure: false,
        preparedObserver: hostObserver,
      );
      final hostCwdTurnId = hostObserver.turnId;
      await capturePresentation(tester, 'realtime-host-cwd-running.png');
      await scene.completed(answer: 'realtime host cwd complete');
      await scene.verifyExecReceipts(priorHostCwdItems, const {
        'realtime-host-cwd-call': 'realtime-host-cwd-line-03',
      }, turnId: hostCwdTurnId);
      await scene.closeLatestTurnGroups();

      await scene.submit('Realtime provider error');
      await scene.terminal(StudioTurnStatus.failed);
      await capturePresentation(
        tester,
        'realtime-provider-error-collapsed.png',
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
      await capturePresentation(tester, 'realtime-provider-error.png');
      await scene.closeTurnReceipt(failedTurn);
      await scene.returnAfterReadingHistory();

      await scene.submit('Realtime cancellable stream');
      final cancelledText = await scene.untilReadableCurrentText(
        timeout: const Duration(seconds: 30),
      );
      await capturePresentation(tester, 'realtime-before-cancel.png');
      await scene.tap(find.byKey(StudioDriverKeys.composerStop));
      await scene.terminal(StudioTurnStatus.cancelled);
      expect(
        scene.observed.entries.where(
          (item) => item.atom.id == cancelledText.id,
        ),
        hasLength(1),
        reason: 'accepted partial text survives cancellation',
      );
      expect(
        scene.lease.currentDisplay?.windows.where(
              (window) => window.id == cancelledText.id,
            ) ??
            const [],
        isEmpty,
      );
      await capturePresentation(tester, 'realtime-stopped.png');

      await scene.submit('Realtime continue after cancel');
      await scene.completed(answer: 'realtime continued after cancel');
      expect(find.byType(ChatItemView), findsWidgets);

      // Supplemental native production-component capture, not a fixture-driven
      // compaction lifecycle. Keep its evidence separate from the real journey.
      graph.setConversationPageVisible(false);
      await tester.pumpWidget(
        RepaintBoundary(
          key: presentationCaptureKey,
          child: conversationLiveStatusCompactingPreview(),
        ),
      );
      await tester.pump();
      await capturePresentation(tester, 'component-compacting.png');

      report.addAll({
        'syntheticComponentCaptures': ['component-compacting.png'],
        'delayedStreamVisible': true,
        'reasoningHistoryVisible': true,
        'execWaitCardsVisible': true,
        'parallelCardsVisible': true,
        'hostCwdCardsVisible': true,
        'providerErrorVisible': true,
        'cancelledViaProductionControl': true,
        'resumeVisible': true,
      });
      assertionsPassed = true;
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}

typedef _PreparedToolObserver = ({
  String turnId,
  TimelineDisplayLease lease,
  TimelineCurrentDisplay currentDisplay,
  Object controller,
  int generation,
  int mainSets,
  TimelineGroupDisplay display,
  CompletionRunRef reference,
  Object expansion,
  Object bodyGeneration,
  String prefixId,
  List<String> prefixReferences,
  Map<String, Object?> evidence,
});

typedef _ExecReceipt = ({
  ChatAtom member,
  CompletionRunRef reference,
  ChatItemPresentation value,
});

final class _RealtimeScene {
  _RealtimeScene(this.tester, this.graph, this.projectPath);

  final WidgetTester tester;
  final AppGraph graph;
  final String projectPath;
  String? _priorTurn;
  String? _submittedThreadId;
  String? _submittedTurnId;
  int _liveTextObservation = 0;
  int _execReceiptObservation = 0;
  late final observed = TimelineObservation(tester, () => lease);

  TimelineDisplayLease get lease =>
      graph.timeline.lease(graph.client.selection.state.selectedThreadId!)!;

  List<ChatItemPresentation> get items => observed.main
      .where((unit) => unit.entry.atom.payload != null)
      .map(ChatItemPresentation.forUnit)
      .toList();

  Future<ChatItemPresentation> openLatestTurnThinking() async {
    final turn = _latestTurn()!;
    final source = ForegroundTurnChatSource(turnId: turn.turnId);
    final groups = observed.workFor(source).toList();
    expect(groups, isNotEmpty);
    await observed.openSourceRuns(source);
    final reasoning = observed.mountedMembers
        .where(
          (atom) =>
              atom.source == source && atom.kind == ChatAtomKind.reasoning,
        )
        .toList();
    expect(reasoning, isNotEmpty);
    for (final atom in reasoning) {
      final reference = observed.unitForMember(atom.id).run!.reference;
      final display = await observed.revealMember(atom, reference: reference);
      expect(
        display.atoms.where((member) => member.id == atom.id),
        hasLength(1),
      );
      await until(
        () => _laidOut(observed.memberRow(atom.id)),
        'reasoning member in its original Main work segment',
      );
      final row = observed.memberRow(atom.id);
      expect(tester.widget<ChatItemView>(row).item.type, 'thinking');
      expect(display.error, isNull);
    }
    return ChatItemPresentation.decode(reasoning.last);
  }

  Future<void> closeLatestTurnGroups() async {
    await observed.closeSource(
      ForegroundTurnChatSource(turnId: _latestTurn()!.turnId),
    );
    expect(
      (await graph.client.conversations.retryCleanup(
        deadline: DateTime.now().add(const Duration(seconds: 5)),
      )).complete,
      isTrue,
    );
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
    await until(() {
      final groups = observed.workFor(source).toList();
      expect(groups.length, lessThanOrEqualTo(1));
      return groups.length == 1;
    }, 'the $stage Turn original observer work group');
    final unit = observed.workFor(source).single;
    final mainLease = lease;
    final mountedDisplay = mainLease.currentDisplay;
    expect(mountedDisplay, isNotNull);
    final currentDisplay = mountedDisplay!;
    expect(currentDisplay.isCurrent, isTrue);
    expect(currentDisplay.turnId, turn!.turnId);
    final controller = mainLease.controller;
    final generation = mainLease.generation;
    final mainSets = mainLease.appliedSets;
    final reference = unit.run!.reference;
    final expansion = unit.expansion;
    final bodyActiveBeforeOpen = expansion.bodyActive;
    final bodyGenerationBeforeOpen = expansion.bodyGeneration;
    final display = await observed.openRun(unit.id);
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
    expect(display.runReference, reference);
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
    expect(reasoning.payload, isA<InlinePayload>());
    expect(reasoning.contents, isNotEmpty);
    await until(
      () => _laidOut(observed.memberRow(reasoning.id)),
      'laid out completed observer reasoning member',
    );
    final rendered = tester
        .widget<ChatItemView>(observed.memberRow(reasoning.id))
        .item;
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
      currentDisplay: currentDisplay,
      controller: controller,
      generation: generation,
      mainSets: mainSets,
      display: display,
      reference: reference,
      expansion: expansion,
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

  bool _expectPreparedToolObserver(_PreparedToolObserver prepared) {
    expect(_latestTurn()?.turnId, prepared.turnId);
    expect(lease, same(prepared.lease));
    expect(lease.currentDisplay, same(prepared.currentDisplay));
    expect(prepared.currentDisplay.isCurrent, isTrue);
    expect(lease.controller, same(prepared.controller));
    expect(lease.generation, prepared.generation);
    expect(lease.appliedSets, prepared.mainSets);
    final unit = observed.unitForRun(prepared.reference);
    expect(unit.expansion, same(prepared.expansion));
    expect(unit.expansion.bodyGeneration, same(prepared.bodyGeneration));
    expect(unit.run?.reference, prepared.reference);
    final displays = lease.groupDisplays
        .where((display) => display.unitId == prepared.display.unitId)
        .toList();
    expect(displays, hasLength(1));
    expect(displays.single, same(prepared.display));
    expect(prepared.display.isCurrent && prepared.display.expanded, isTrue);
    expect(prepared.display.error, isNull);
    expect(prepared.display.runReference, prepared.reference);
    if (prepared.display.loading) return false;
    final prefix = prepared.display.atoms
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
    Iterable<ChatAtom> running = const [],
  }) {
    final loading = prepared.display.loading;
    return {
      'turnId': prepared.turnId,
      'groupId': prepared.display.unitId,
      'sameMainLease': identical(lease, prepared.lease),
      'sameMainCurrentDisplay': identical(
        lease.currentDisplay,
        prepared.currentDisplay,
      ),
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
        observed.unitForRun(prepared.reference).expansion.bodyGeneration,
        prepared.bodyGeneration,
      ),
      'runReference': {
        'databaseId': prepared.reference.databaseId,
        'indexVersion': prepared.reference.indexVersion,
        'startSeq': prepared.reference.startSeq,
        'itemId': prepared.display.unitId,
      },
      'current': prepared.display.isCurrent,
      'expanded': prepared.display.expanded,
      'loading': loading,
      'membersAvailable': !loading,
      'error': prepared.display.error?.toString(),
      'prefixId': prepared.prefixId,
      'prefixReferences': loading ? null : prepared.prefixReferences,
      'memberIds': loading
          ? null
          : prepared.display.atoms.map((atom) => atom.id).toList(),
      'windows': loading
          ? null
          : [
              for (final window in prepared.display.windows)
                {
                  'id': window.id,
                  'reference': contentReferenceIdentity(window.reference)
                      .toString(),
                  'generation': window.window?.generation,
                  'ready': window.window != null,
                  'error': window.error?.toString(),
                },
            ],
      'runningTools': loading
          ? null
          : [
              for (final atom in running)
                {
                  'id': atom.id,
                  'callId': atom.tool?.callId,
                  'active': atom.lifecycle is ActiveChatAtom,
                  'status': tester
                      .widget<TimelineToolDetails>(currentToolCard(atom))
                      .item
                      .statusString,
                  'laidOut': _laidOut(currentToolCard(atom)),
                },
            ],
    };
  }

  CompletedEntry _turnReceipt(StudioTurnView turn) =>
      observed.entries.singleWhere(
        (item) =>
            item.mainPresentation == MainPresentation.single &&
            item.atom.kind == ChatAtomKind.turnReceipt &&
            item.atom.source == ForegroundTurnChatSource(turnId: turn.turnId),
      );

  void _expectSmallTurnReceipt(CompletedEntry item) {
    final payload = item.atom.payload;
    final byteLength = payload is InlinePayload
        ? payload.bytes.length
        : payload is DeferredPayload
        ? payload.byteLength
        : null;
    final reason =
        'Known small realtime fixture requires Inline/current business '
        'presentation within the original frame =${item.recordId}, '
        'payloadType=${payload?.runtimeType}, byteLength=$byteLength. '
        'Over-budget payloads may remain Deferred in the product.';
    expect(payload is InlinePayload, isTrue, reason: reason);
    expect(
      ChatItemPresentation.forUnit(observed.unit(item.recordId)).compatibility,
      ChatItemCompatibility.current,
      reason: reason,
    );
  }

  Finder _turnReceiptTitle(CompletedEntry item) {
    final disclosure = find.descendant(
      of: observed.itemRow(item.recordId),
      matching: find.byKey(ValueKey(('item-disclosure', item.recordId))),
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
    expect(item.mainPresentation, MainPresentation.single);
    expect(item.atom.kind, ChatAtomKind.turnReceipt);
    _expectSmallTurnReceipt(item);
    await observed.revealItem(item);
    final row = observed.itemRow(item.recordId);
    final receipt = tester.widget<ChatItemView>(row).item;
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
    required TimelineGroupDisplay group,
  }) async {
    final mainLease = lease;
    final initialCurrentOverlay = mainLease.currentDisplay;
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
    final canonical = find.descendant(
      of: observed.groupRow(group.unitId, skipOffstage: false),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is ChatItemView && widget.item.atom?.id == presentationId,
        skipOffstage: false,
      ),
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

    TimelineDisplayUnit groupMetadata(ContentRef reference) {
      expect(group.isCurrent && group.expanded, isTrue);
      expect(
        mainLease.groupDisplays.where((display) => identical(display, group)),
        hasLength(1),
      );
      final messages = controller.messages
          .where((message) => message.id == group.unitId)
          .toList();
      expect(messages, hasLength(1), reason: 'one original Main Message');
      final metadata = messages.single.metadata?[timelineDisplayUnitKey];
      if (metadata is! TimelineDisplayUnit) {
        fail('The original Main Message must own TimelineDisplayUnit metadata');
      }
      expect(metadata.entry.completionSeq, greaterThan(0));
      expect(metadata.id, group.unitId);
      expect(metadata.entry.mainPresentation, isNot(MainPresentation.single));
      expect(metadata.run?.reference, group.runReference);
      expect(metadata.entry.completionSeq, isNotNull);
      final member = group.atoms.singleWhere(
        (atom) => atom.id == presentationId,
      );
      if (metadata.entry.mainPresentation ==
          MainPresentation.backgroundResults) {
        expect(member.source, isA<BackgroundResultChatSource>());
      } else {
        expect(member.source, metadata.entry.atom.source);
      }
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
      // The original Main group and its mounted member own this range,
      // independently of a nullable current-overlay resource borrow.
      final main = groupMetadata(reference);
      originalMain = main;
      expect(scrollable, findsOneWidget);
      expect(scroll.positions, hasLength(1));
      final mainScrollable = tester.state<ScrollableState>(scrollable);
      originalScrollable = mainScrollable;
      expect(mainScrollable.position, same(scroll.position));
      expect(canonical, findsOneWidget);
      final row = tester.element(canonical);
      originalCanonical = row;
      final memberScrollable = Scrollable.maybeOf(row);
      expect(memberScrollable, isNotNull);

      void expectMain() {
        expectLease();
        expect(groupMetadata(reference), same(main));
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
        expect(
          widget.item.atom,
          same(group.atoms.singleWhere((atom) => atom.id == presentationId)),
        );
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
          group.windows.where((window) => identical(window, owner)),
          hasLength(1),
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
          final declared = metadata.entry.atom.contents
              .where((content) => content.role == role)
              .toList();
          return {
            'type': metadata.runtimeType.toString(),
            'completed': true,
            'id': metadata.id,
            'itemId': metadata.id,
            'hasPosition': metadata.entry.completionSeq > 0,
            'contentItemId': metadata.entry.recordId,
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
        final currentOverlay = mainLease.currentDisplay;
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
          'currentOverlayObservation': {
            'initialPresent': initialCurrentOverlay != null,
            'initialIsCurrent': initialCurrentOverlay?.isCurrent,
            'present': currentOverlay != null,
            'isCurrent': currentOverlay?.isCurrent,
            'sameResourceWhenBothPresent':
                initialCurrentOverlay == null || currentOverlay == null
                ? null
                : identical(initialCurrentOverlay, currentOverlay),
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
    Set<String> priorItemIds,
    Map<String, String> expected, {
    required String turnId,
  }) async {
    final source = ForegroundTurnChatSource(turnId: turnId);
    final associatedTasks = <String, String>{};
    final observations = <Map<String, Object?>>[];
    final clock = Stopwatch()..start();
    Map<String, Object?>? lastObservation;
    String? previousObservation;

    Map<String, Object?> sourceFacts(ChatSourceId value) =>
        value is ForegroundTurnChatSource
        ? {'kind': 'foregroundTurn', 'turnId': value.turnId}
        : value is BackgroundResultChatSource
        ? {'kind': 'backgroundResult', 'messageId': value.messageId}
        : {'kind': value.runtimeType.toString()};

    Iterable<TimelineDisplayUnit> backgroundGroups() => observed.main.where(
      (unit) =>
          !priorItemIds.contains(unit.entry.recordId) &&
          unit.entry.mainPresentation == MainPresentation.backgroundResults,
    );

    List<_ExecReceipt> targets() {
      final result = <_ExecReceipt>[];
      final candidates = <Map<String, Object?>>[];
      final counts = {for (final call in expected.keys) call: 0};
      final snapshot = <String, Object?>{
        'turnId': turnId,
        'candidates': candidates,
        'finalCounts': counts,
        'complete': false,
      };
      lastObservation = {
        'elapsedMillis': clock.elapsedMilliseconds,
        ...snapshot,
      };

      ChatItemPresentation read(
        PayloadData? payload,
        Map<String, Object?> candidate,
        ChatItemPresentation Function() decode,
      ) {
        candidates.add(candidate);
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
        expect(
          payload,
          isA<InlinePayload>(),
          reason:
              'Small fixture receipt needs its original Inline envelope: '
              '${jsonEncode(candidate)}',
        );
        final value = decode();
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
              'Receipt envelope must decode without a Deferred loader: '
              '${jsonEncode(candidate)}',
        );
        return value;
      }

      // Original foreground members establish the task association. Final
      // background results belong to their own independently sourced groups.
      final members = observed.mountedMembers;
      for (final atom
          in members
              .where((atom) => atom.source == source)
              .followedBy(
                members.where(
                  (atom) => atom.source is BackgroundResultChatSource,
                ),
              )) {
        if (atom.turnId != turnId ||
            !expected.containsKey(atom.tool?.callId) ||
            atom.lifecycle is! TerminalChatAtom) {
          continue;
        }
        final terminal = atom.lifecycle as TerminalChatAtom;
        final reference = observed.unitForMember(atom.id).run!.reference;
        final candidate = <String, Object?>{
          'domain': 'Run',
          'id': atom.id,
          'kind': atom.kind.name,
          'source': sourceFacts(atom.source),
          'turnId': atom.turnId,
          'delivery': atom.delivery.name,
          'outcome': terminal.outcome.name,
          'completionItemId': atom.completionItemId,
          'groupId': observed.unitForRun(reference).id,
        };
        final value = read(
          atom.payload,
          candidate,
          () => ChatItemPresentation.decode(atom),
        );
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
        final backgroundResult =
            atom.source is BackgroundResultChatSource &&
            atom.delivery == ChatDeliveryKind.independent;
        final taskAssociated =
            tool.taskId != null &&
            associatedTasks[tool.toolCallId] == tool.taskId;
        final finalResult =
            atom.kind == ChatAtomKind.toolCall &&
            ((atom.source == source &&
                    atom.delivery == ChatDeliveryKind.foreground) ||
                (backgroundResult && taskAssociated)) &&
            terminal.outcome == ChatTerminalOutcome.completed &&
            tool.name == 'exec' &&
            tool.statusString == 'succeeded' &&
            tool.exitCode == 0;
        candidate['handedOff'] = handedOff;
        candidate['backgroundResult'] = backgroundResult;
        candidate['taskAssociated'] = taskAssociated;
        candidate['finalResult'] = finalResult;
        if (finalResult) {
          result.add((member: atom, reference: reference, value: value));
          counts[tool.toolCallId] = counts[tool.toolCallId]! + 1;
        }
      }
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
      await observed.openSourceRuns(source);
      await until(
        () {
          targets();
          final terminalCalls = observed.mountedMembers
              .where(
                (atom) =>
                    atom.source == source &&
                    atom.turnId == turnId &&
                    atom.lifecycle is TerminalChatAtom,
              )
              .map((atom) => atom.tool?.callId)
              .toSet();
          return terminalCalls.containsAll(expected.keys) &&
              backgroundGroups().fold<int>(
                    0,
                    (count, unit) => count + unit.entry.run!.ordinal,
                  ) >=
                  associatedTasks.length;
        },
        'original exec terminals and independently admitted background groups',
      );
      for (final group in backgroundGroups().toList()) {
        await observed.openRun(group.id);
      }
      receipts = targets();
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
        final group = await observed.revealMember(
          atom,
          reference: target.reference,
        );
        final item = target.value;
        final rowId = atom.id;
        final contentItemId = atom.completionItemId!;
        final contents = atom.contents;
        final tool = (item.toolCard as DecodedToolCard).value;
        final lastLine = expected[tool.toolCallId]!;
        expect(tool.name, 'exec');
        expect(tool.statusString, 'succeeded');
        expect(tool.exitCode, 0);
        expect(tool.output, contains(lastLine));
        final details = find.descendant(
          of: observed.memberRow(rowId),
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
          group: group,
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
            group: group,
          );
          final cwd =
              (jsonDecode(utf8.decode(arguments.bytes)) as Map)['cwd']
                  as String;
          expect(cwd, isNotEmpty);
          expect(tool.output, contains('realtime-host-cwd-actual:$cwd'));
        }
        expect(group.error, isNull);
        expect(group.expanded && group.isCurrent, isTrue);
        expect(
          group.atoms.where((member) => member.id == atom.id),
          hasLength(1),
        );
        expect(lease.controller, same(controller));
        expect(lease.appliedSets, mainSets);
        expect(witnessed.add(tool.toolCallId), isTrue);
        debugPrintSynchronously(
          'Exec receipt laid out: ${jsonEncode({'callId': tool.toolCallId, 'rowId': rowId, 'contentItemId': contentItemId, 'state': tool.statusString, 'sourceOrder': atom.sourceOrder, 'lastLine': lastLine, 'groupId': group.unitId, 'outputBytes': output.bytes.length})}',
        );
        await capturePresentation(
          tester,
          'realtime-${tool.toolCallId}-succeeded.png',
        );
        expect(expectDisclosure(), isTrue);
        await observed.closeRun(group);
        final closeClock = Stopwatch()..start();
        await until(
          () => outputBorrow.window == null,
          'collapsed member revokes its original bounded output borrow',
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
    final scroll = lease.scrollController;
    expect(scroll.hasClients, isTrue);
    if (scroll.position.maxScrollExtent <= 0.5) return;
    final main = find.byWidgetPredicate(
      (widget) => widget is Scrollable && identical(widget.controller, scroll),
    );
    final towardLatest = scroll.position.pixels > 0.5;
    final distance =
        (towardLatest
                ? scroll.position.pixels / 2
                : scroll.position.maxScrollExtent / 2)
            .clamp(1.0, 60.0)
            .toDouble();
    final delta = towardLatest ? -distance : distance;
    debugPrintSynchronously(
      'Main history gesture: ${jsonEncode({'mode': lease.mode.name, 'pixels': scroll.position.pixels, 'maxExtent': scroll.position.maxScrollExtent, 'axis': scroll.position.axisDirection.name, 'logicalDelta': delta})}',
    );
    await tester.drag(main, switch (scroll.position.axisDirection) {
      AxisDirection.up => Offset(0, delta),
      AxisDirection.down => Offset(0, -delta),
      _ => throw StateError('Main timeline must scroll vertically'),
    });
    await tester.pump();
    final latest = find.byKey(StudioDriverKeys.timelineReturnLive);
    await until(
      () => latest.hitTestable().evaluate().isNotEmpty,
      'production return-to-latest action after reading history',
    );
    await tap(latest);
    await until(
      () => scroll.position.pixels.abs() < 0.5,
      'latest timeline viewport after reading receipts',
    );
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
    await until(() {
      final selection = graph.client.selection.state;
      final project = graph.client.project.state.projects?.values
          .where((candidate) => candidate.id == selection.selectedProjectId)
          .firstOrNull;
      if (project?.path != projectPath ||
          selection.needsOpen ||
          input.evaluate().length != 1 ||
          composerView.evaluate().length != 1) {
        return false;
      }
      final composer = tester.widget<PromptComposerView>(composerView);
      final field = tester.widget<TextField>(input);
      return composer.pasteTargetId ==
              (selection.selectedThreadId ?? selection.selectedProjectId) &&
          composer.enabled &&
          (field.enabled ?? true);
    }, 'editable composer bound to the selected project and conversation');
    final selection = graph.client.selection.state;
    final controller = tester.widget<TextField>(input).controller!;
    final target = tester
        .widget<PromptComposerView>(composerView)
        .pasteTargetId;
    void recordInput(String phase) {
      final current = tester.widget<TextField>(input);
      final composer = tester.widget<PromptComposerView>(composerView);
      final selected = graph.client.selection.state;
      debugPrintSynchronously(
        'Realtime composer input: ${jsonEncode({'phase': phase, 'projectId': selected.selectedProjectId, 'threadId': selected.selectedThreadId, 'needsOpen': selected.needsOpen, 'navigation': graph.client.selection.navigationGeneration, 'target': composer.pasteTargetId, 'element': identityHashCode(tester.element(input)), 'controller': identityHashCode(current.controller), 'enabled': current.enabled, 'draft': composer.composer.draft, 'text': current.controller?.text})}',
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
      expect(
        tester.widget<PromptComposerView>(composerView).pasteTargetId,
        target,
      );
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
        'Realtime submission failure: draft=${composer.composer.draft}, '
        'pending=${composer.composer.isSubmissionPending}, '
        'execution=${composer.execution?.id}/${composer.execution?.phase}, '
        'blocker=${composer.blocker}, failure=${composer.failure}',
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
      CompletedEntry? admittedAnswer() {
        final matches = observed.entries
            .where(
              (item) =>
                  item.atom.source == source &&
                  item.atom.turnId == turnId &&
                  item.mainPresentation == MainPresentation.single &&
                  item.atom.kind == ChatAtomKind.text &&
                  item.atom.textChannel == ThreadTextChannel.finalAnswer &&
                  (item.atom.lifecycle as TerminalChatAtom).outcome ==
                      ChatTerminalOutcome.completed,
            )
            .toList();
        expect(matches.length, lessThanOrEqualTo(1));
        return matches.singleOrNull;
      }

      CompletedEntry? target;
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
      await observed.revealItem(item, timeout: remaining());
      final unit = observed.unit(item.recordId);
      expect(unit.entry, same(item));
      expect(unit.entry.completionSeq, greaterThan(0));
      final row = observed.itemRow(item.recordId);
      final originalScrollable = Scrollable.maybeOf(tester.element(row));
      final text = find
          .descendant(of: row, matching: find.textContaining(answer))
          .hitTestable();
      await until(
        () {
          remaining();
          expect(admittedAnswer(), same(item));
          expect(observed.unit(item.recordId), same(unit));
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
    CompletedEntry? receipt;
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
        final source = ForegroundTurnChatSource(turnId: turn.turnId);
        // State proves the outcome; Main admission remains independent and
        // uses the original wait budget, without a normal completion item.
        if (!observed.entries.any((item) => item.atom.source == source) ||
            observed.activity.any((entry) => entry.atom.source == source)) {
          return false;
        }
        if (kind == StudioTurnStatus.failed ||
            kind == StudioTurnStatus.cancelled) {
          final outcome = kind == StudioTurnStatus.failed
              ? ChatTerminalOutcome.failed
              : ChatTerminalOutcome.cancelled;
          final matches = observed.entries
              .where(
                (item) =>
                    item.atom.source == source &&
                    item.mainPresentation == MainPresentation.single &&
                    item.atom.kind == ChatAtomKind.turnReceipt,
              )
              .toList();
          expect(matches.length, lessThanOrEqualTo(1));
          receipt = matches.singleOrNull;
          return (receipt?.atom.lifecycle as TerminalChatAtom?)?.outcome ==
              outcome;
        }
        return true;
      },
      '${kind.name} realtime Turn',
      timeout: const Duration(minutes: 3),
    );
    if (kind == StudioTurnStatus.failed || kind == StudioTurnStatus.cancelled) {
      _expectSmallTurnReceipt(receipt!);
      await observed.revealItem(receipt!);
      final rendered = tester
          .widget<ChatItemView>(observed.itemRow(receipt!.recordId))
          .item;
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
          final live = observed.activity.map((entry) => entry.atom).toList();
          final candidates = live
              .where(
                (atom) =>
                    atom.kind == ChatAtomKind.text &&
                    atom.lifecycle is ActiveChatAtom,
              )
              .toList();
          // These are fresh synchronous borrows for this predicate invocation,
          // not a lease or window retained across its next pump.
          final display = lease.currentDisplay;
          final allWindows = display?.windows.toList() ?? const [];
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
            'displayPresent': display != null,
            'displayCurrent': display?.isCurrent,
            'displayTurnId': display?.turnId,
            'displayActivityId': display?.activityId,
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
          for (final atom in candidates) {
            final view = find.byWidgetPredicate(
              (widget) =>
                  widget is ConversationCurrentWindowView &&
                  widget.id == atom.id &&
                  widget.error == null &&
                  widget.text.isNotEmpty,
            );
            if (!_laidOut(view)) continue;
            final windows = allWindows
                .where((window) => window.id == atom.id)
                .toList();
            for (final window in windows) {
              if (window.error case final error?) throw StateError('$error');
            }
            if (windows.isEmpty ||
                windows.every((window) => window.window == null)) {
              continue;
            }
            expect(
              atom.contents.any(
                (content) => windows.any(
                  (window) =>
                      contentReferenceIdentity(content.reference) ==
                      contentReferenceIdentity(window.reference),
                ),
              ),
              isTrue,
            );
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

  Finder currentToolCard(ChatAtom atom) {
    final reading = atom.payload == null
        ? null
        : ChatItemPresentation.decode(atom).toolCard;
    // Use the renderer's same typed facts for active and completed waits.
    final wait =
        atom.wait ?? (reading is DecodedToolCard ? reading.value.wait : null);
    return wait != null
        ? find.byWidgetPredicate(
            (widget) =>
                widget is TimelineWaitPanel && widget.identity == atom.id,
          )
        : find.byWidgetPredicate(
            (widget) =>
                widget is TimelineToolDetails &&
                widget.item.id == atom.id &&
                widget.item.toolCallId == atom.tool?.callId &&
                widget.item.name == atom.tool?.name,
          );
  }

  Future<void> untilLaidOutCurrentTools({
    required int minimum,
    Set<String> toolCallIds = const {},
    Set<String> runningExecCallIds = const {},
    bool settleDisclosure = true,
    _PreparedToolObserver? preparedObserver,
  }) async {
    final clock = Stopwatch()..start();
    var settled = !settleDisclosure;
    final observations = <Map<String, Object?>>[];
    if (preparedObserver != null) {
      preparedObserver.evidence['observations'] = observations;
    }
    String? previousObservation;
    try {
      while (true) {
        final turn = _latestTurn();
        if (turn != null && turn.turnId != _priorTurn) {
          _submittedTurnId ??= turn.turnId;
          expect(turn.turnId, _submittedTurnId);
        }
        // Running tools belong to Activity. The completed prefix keeps its
        // independently opened Run and body qualification while tools execute.
        final units = [
          if (turn != null && turn.turnId == _submittedTurnId)
            ...observed.workFor(ForegroundTurnChatSource(turnId: turn.turnId)),
        ];
        final openingStartedMillis = clock.elapsedMilliseconds;
        if (preparedObserver == null) {
          for (final unit in units) {
            await observed.openRun(unit.id);
          }
        }
        // Keep every original identity/error assertion even while the same
        // reader temporarily cannot lend an admitted member window.
        final observerReady =
            preparedObserver == null ||
            _expectPreparedToolObserver(preparedObserver);
        final groupIds = units.map((unit) => unit.id).toSet();
        if (preparedObserver != null) {
          expect(groupIds, {preparedObserver.display.unitId});
        }
        final tools = !observerReady
            ? null
            : observed.activity
                  .map((entry) => entry.atom)
                  .where(
                    (atom) =>
                        atom.turnId == _submittedTurnId &&
                        atom.kind == ChatAtomKind.toolCall,
                  )
                  .toList();
        final running = tools
            ?.where(
              (atom) =>
                  atom.tool?.name == 'exec' && atom.lifecycle is ActiveChatAtom,
            )
            .map((atom) => atom.tool!.callId)
            .toSet();
        final expectedCallIds = {...toolCallIds, ...runningExecCallIds};
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
        final observation = {
          'groupIds': groupIds.toList(),
          'liveIds': observed.activity.map((entry) => entry.atom.id).toList(),
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
            running != null &&
            tools.length >= minimum &&
            required.isNotEmpty &&
            required
                .map((atom) => atom.tool?.callId)
                .toSet()
                .containsAll(expectedCallIds) &&
            laidOut == required.length &&
            running.containsAll(runningExecCallIds)) {
          if (!settled) {
            await tester.pump(const Duration(milliseconds: 300));
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
          for (final call in runningExecCallIds) {
            final atom = required.singleWhere(
              (atom) => atom.tool?.callId == call,
            );
            final widget = tester.widget<TimelineToolDetails>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is TimelineToolDetails && widget.item.id == atom.id,
              ),
            );
            expect(widget.item.statusString, 'running');
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
            'Realtime current tools: ${jsonEncode({'minimum': minimum, 'atomIds': tools.map((atom) => atom.id).toList(), 'callIds': tools.map((atom) => atom.tool?.callId).toList(), 'exactRunningExecIds': running.toList(), 'laidOut': laidOut, 'contentWindows': lease.currentDisplay?.windows.length})}',
          );
          if (preparedObserver != null) {
            expect(_expectPreparedToolObserver(preparedObserver), isTrue);
            preparedObserver.evidence['running'] =
                _preparedToolObserverSnapshot(
                  preparedObserver,
                  running: required.where(
                    (atom) => runningExecCallIds.contains(atom.tool?.callId),
                  ),
                );
          }
          return;
        }
        if (clock.elapsed >= const Duration(minutes: 3)) {
          fail('Timed out waiting for $minimum real current tool cards');
        }
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull);
      }
    } catch (_) {
      final output = Platform.environment['ANYWORK_REALTIME_OUTPUT']!;
      await File.fromUri(
        Directory(output).uri.resolve('realtime-tool-observation-failure.json'),
      ).writeAsString(
        '${const JsonEncoder.withIndent('  ').convert({
          'turnId': _submittedTurnId,
          'expectedCallIds': {...toolCallIds, ...runningExecCallIds}.toList(),
          'runningExecCallIds': runningExecCallIds.toList(),
          'observations': observations,
        })}\n',
      );
      debugPrintSynchronously(
        'Realtime tool observation failure: ${jsonEncode({
          'turnId': _submittedTurnId,
          'liveIds': observed.activity.map((entry) => entry.atom.id).toList(),
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
  String fragment,
) async {
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
  paragraph.showOnScreen(rect: bounds);
  await tester.pump();
  expect(tester.takeException(), isNull);
  expect(tester.renderObject<RenderParagraph>(text), same(paragraph));
  for (final box in paragraph.getBoxesForSelection(selection)) {
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
  }
}
