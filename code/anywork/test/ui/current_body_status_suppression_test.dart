import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_connector.dart';
import 'package:anywork/src/features/conversation/timeline/live_status/live_status_bar.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/conversation_activity_bar.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/content_layout_witness.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/timeline_transport.dart'
    show TestHistoryReader;
import '../support/chat_fixtures.dart';
import '../support/pump_client_future.dart';
import '../support/recording_demo_transport.dart';
import '../support/test_app_lifecycle.dart';
import '../support/test_statistics_feed.dart';

const _threadId = 'thread-main';
const _turnId = 'turn';
const _atomId = 'current-body';
const _bodyText = 'mounted Current body';
const _cut = HistoryCut('body-status-cut');

CurrentContentRef _bodyRef(String ownerId) => CurrentContentRef(
  ownerId: ownerId,
  domain: 'thread',
  entityId: _atomId,
  contentKey: 'body',
  generation: '1',
);

final class _BodyStatusTransport extends RecordingDemoTransport {
  final changed = Completer<HistoryCut>();
  String? currentOwnerId;

  @override
  Future<CurrentReader> openCurrentReader(
    String threadId, {
    required int currentProtocolVersion,
    required ReadDemand demand,
  }) async {
    final reader = await super.openCurrentReader(
      threadId,
      currentProtocolVersion: currentProtocolVersion,
      demand: demand,
    );
    currentOwnerId ??= reader.metadata.currentOwnerId;
    return reader;
  }

  @override
  Future<HistoryReader> openHistoryReader(
    String threadId, {
    required int historyProtocolVersion,
  }) async {
    final reader = TestHistoryReader(threadId: threadId, cut: _cut);
    reader.onTimeline = (cut, cursor, demand) async {
      expectSync(cut, _cut);
      expectSync(cursor, isNull);
      return HistoryTimelinePage(
        cut: _cut,
        entries: [
          HistoryTimelineEntry(
            rowKey: 'row:$_atomId',
            anchorSeq: 4,
            headSeq: 4,
            head: SingleHistoryRow(
              HistoryEntityHead(
                entityId: _atomId,
                runId: currentOwnerId,
                source: const ForegroundTurnChatSource(turnId: _turnId),
                kind: ChatAtomKind.text,
                delivery: ChatDeliveryKind.foreground,
                state: const HistoryEntityState(
                  kind: HistoryEntityStateKind.knownActive,
                  activeStatus: ChatActiveStatus.running,
                ),
                // This row anchors the Current overlay. It intentionally has no
                // canonical body identity, so the test cannot depend on an
                // unscripted History readEvent fallback.
                contentPresent: false,
                observation: const HistoryObservation(
                  kind: HistoryObservationKind.original,
                ),
              ),
            ),
          ),
        ],
      );
    };
    reader.onWaitChanged = (_) => changed.future;
    return reader;
  }
}

CurrentAtom _currentAtom({required String turnId, required String ownerId}) =>
    CurrentAtom(
      id: _atomId,
      source: ForegroundTurnChatSource(turnId: turnId),
      sourceOrder: 1,
      kind: ChatAtomKind.text,
      delivery: ChatDeliveryKind.foreground,
      lifecycle: const ActiveChatAtom(
        started: null,
        status: ChatActiveStatus.running,
      ),
      turnId: turnId,
      contentPresent: true,
      contents: [
        CurrentAtomContent(
          role: ChatContentRole.body,
          reference: _bodyRef(ownerId),
        ),
      ],
    );

ProjectionCurrentFrame _projectionFrame({
  required String ownerId,
  required int revision,
  required String turnId,
}) => ProjectionCurrentFrame(
  revision: CurrentRevision(ownerId: ownerId, revision: revision),
  projection: CurrentProjection(
    logicalStatus: ThreadStatusView.running,
    executionPresent: true,
    activeTurn: CurrentTurnHead(id: turnId, phase: CurrentTurnPhase.responding),
    sources: const [],
    atoms: [_currentAtom(turnId: turnId, ownerId: ownerId)],
    previews: const [],
    collections: const [],
  ),
);

ContentWindow _window(int offset, int maxBytes, String ownerId) {
  final bytes = utf8.encode(_bodyText);
  final requestedEnd = offset + maxBytes;
  final end = requestedEnd < bytes.length ? requestedEnd : bytes.length;
  return ContentWindow(
    offset: offset,
    bytes: bytes.sublist(offset, end),
    generation: _bodyRef(ownerId).generation,
    availableThrough: bytes.length,
    sealed: false,
  );
}

RecordingCurrentReader _timelineReader(AppGraph graph) =>
    graph.timeline.lease(_threadId)!.current as RecordingCurrentReader;

Widget _root({
  required AppGraph graph,
  required String threadId,
  required bool Function() showTimeline,
  required void Function(StateSetter) exposeSetState,
}) => ProviderScope(
  overrides: [appGraphProvider.overrideWithValue(graph)],
  child: MaterialApp(
    theme: pureStudioTheme(),
    locale: const Locale('zh'),
    localizationsDelegates: [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: StatefulBuilder(
        builder: (context, setState) {
          exposeSetState(setState);
          return Column(
            children: [
              if (showTimeline())
                Expanded(child: TimelineConnector(threadId: threadId)),
              LiveStatusBar(threadId: threadId),
            ],
          );
        },
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'Current body layout gates responding suppression until real unmount',
    (tester) async {
      final transport = _BodyStatusTransport();
      final graph = testAppGraph(
        statisticsFeed: const TestStatisticsFeedPort(),
        transport: transport,
        clientId: 'current-body-status',
      );
      var graphClosed = false;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        if (!graphClosed) {
          final report = await pumpClientFuture(
            tester,
            graph.close(
              budget: testBudgetUntil(
                DateTime.now().add(const Duration(seconds: 5)),
              ),
            ),
            'current body teardown close',
          );
          expect(report.complete, isTrue);
          graphClosed = true;
        } else {
          await pumpClientFuture(
            tester,
            graph.client.conversations.retryCleanup(
              budget: testBudgetUntil(
                DateTime.now().add(const Duration(seconds: 5)),
              ),
            ),
            'current body teardown retry cleanup',
          );
        }
      });
      await pumpClientFuture(tester, graph.client.bootstrap(), 'bootstrap');
      graph.timeline.updateReadDemand(chatDemand);

      var showTimeline = true;
      late StateSetter rebuildRoot;
      await tester.pumpWidget(
        _root(
          graph: graph,
          threadId: _threadId,
          showTimeline: () => showTimeline,
          exposeSetState: (setState) => rebuildRoot = setState,
        ),
      );
      graph.setConversationPageVisible(true);
      await pumpClientFuture(
        tester,
        graph.client.directoryCommands.selectThread(_threadId),
        'select thread',
      );
      await pumpClientUntil(
        tester,
        () =>
            graph.client.conversations.visibleThreadId.value == _threadId &&
            graph.client.conversations
                    .existingSession(_threadId)
                    ?.state
                    .workspace !=
                null,
        'visible conversation',
      );
      try {
        await pumpClientFuture(
          tester,
          timelineReady(graph.timeline, _threadId),
          'timeline lease',
        );
      } catch (error) {
        fail(
          '$error; timeline=${graph.timeline.source.value}; '
          'current readers=${transport.currentReaders.length}; '
          'lease=${graph.timeline.lease(_threadId)}',
        );
      }

      final workspace = chatWorkspace(_threadId).copyWith(
        revision: 2,
        activeTurn: StudioTurnView(
          turnId: _turnId,
          threadId: _threadId,
          revision: 1,
          state: const RunningStudioTurnState(
            startedAt: 1,
            activity: StudioTurnActivity.responding,
          ),
          updatedAt: DateTime.utc(2026, 11, 17),
        ),
        activity: const ThreadActivityView(
          threadId: _threadId,
          identity: 'responding:turn',
          revision: 1,
          turnId: _turnId,
          kind: ThreadActivityKind.responding,
          summary: 'streaming',
        ),
      );
      await transport.publishWorkspace(workspace);
      await pumpClientUntil(
        tester,
        () => find.byType(ConversationActivityStatus).evaluate().isNotEmpty,
        'responding status before Current body',
      );

      final reader = _timelineReader(graph);
      final ownerId = reader.metadata.currentOwnerId;
      final firstListening = Completer<void>();
      final firstBody = StreamController<ContentWindow>.broadcast(
        sync: true,
        onListen: () => firstListening.complete(),
      );
      addTearDown(firstBody.close);
      reader.onReadBody = (_, range) async =>
          _window(range.offset, range.maxBytes, ownerId);
      reader.onWatchBody = (_, _) => firstBody.stream;
      reader.emitCurrentFrame(
        _projectionFrame(ownerId: ownerId, revision: 3, turnId: _turnId),
      );
      await pumpClientUntil(
        tester,
        () => firstListening.isCompleted,
        'Current body watch before layout',
      );
      expect(
        find.byType(ConversationActivityStatus),
        findsOneWidget,
        reason: 'A subscribed but unlaid-out body does not hide responding.',
      );

      firstBody.add(_window(0, 4096, ownerId));
      await pumpClientUntil(
        tester,
        () =>
            graph.timeline
                .lease(_threadId)!
                .renderedCurrentAtomIds
                .contains(_atomId) &&
            find.text(_bodyText).evaluate().isNotEmpty &&
            find.byType(ConversationActivityStatus).evaluate().isEmpty,
        'laid-out Current body',
      );
      expect(find.byType(ContentLayoutWitness), findsOneWidget);
      expect(find.byType(ConversationActivityStatus), findsNothing);

      showTimeline = false;
      rebuildRoot(() {});
      await tester.pump();
      await pumpClientUntil(
        tester,
        () =>
            graph.timeline.lease(_threadId)!.renderedCurrentAtomIds.isEmpty &&
            find.byType(ConversationActivityStatus).evaluate().isNotEmpty,
        'unmounted Current body restores status',
      );

      final secondListening = Completer<void>();
      final secondBody = StreamController<ContentWindow>.broadcast(
        sync: true,
        onListen: () => secondListening.complete(),
      );
      addTearDown(secondBody.close);
      reader.onReadBody = (_, range) async =>
          _window(range.offset, range.maxBytes, ownerId);
      reader.onWatchBody = (_, _) => secondBody.stream;
      reader.emitCurrentFrame(
        _projectionFrame(ownerId: ownerId, revision: 4, turnId: 'other-turn'),
      );
      showTimeline = true;
      rebuildRoot(() {});
      await tester.pump();
      await pumpClientUntil(
        tester,
        () => secondListening.isCompleted,
        'other Turn Current body watch',
      );
      secondBody.add(_window(0, 4096, ownerId));
      await pumpClientUntil(
        tester,
        () =>
            graph.timeline
                .lease(_threadId)!
                .renderedCurrentAtomIds
                .contains(_atomId) &&
            find.text(_bodyText).evaluate().isNotEmpty &&
            find.byType(ConversationActivityStatus).evaluate().isNotEmpty,
        'other Turn body layout',
      );
      expect(
        find.byType(ConversationActivityStatus),
        findsOneWidget,
        reason: 'A body from another Turn cannot suppress this Turn notice.',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      final report = await pumpClientFuture(
        tester,
        graph.close(
          budget: testBudgetUntil(
            DateTime.now().add(const Duration(seconds: 5)),
          ),
        ),
        'graph close',
      );
      expect(report.complete, isTrue);
      graphClosed = true;
    },
  );
}
