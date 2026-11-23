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
const _inputText = 'immutable prompt';
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
  final currentOwner = Completer<String>();

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
    if (!currentOwner.isCompleted) {
      currentOwner.complete(reader.metadata.currentOwnerId);
    }
    return reader;
  }

  @override
  Future<HistoryReader> openHistoryReader(
    String threadId, {
    required int historyProtocolVersion,
  }) async {
    final reader = TestHistoryReader(threadId: threadId, cut: _cut);
    reader.onTimeline = (cut, cursor, demand) async {
      final runId = await currentOwner.future;
      expectSync(cut, _cut);
      expectSync(cursor, isNull);
      return HistoryTimelinePage(
        cut: _cut,
        items: [
          DividerTimelineItem(
            HistoryEventRecord(
              seq: 4,
              eventId: 'event:input-1',
              kind: 'input_accepted',
              timelineRole: HistoryTimelineRole.divider,
              recordedAt: 4,
              occurredAt: 4,
              runId: runId,
              turnId: _turnId,
              entityId: 'input-1',
              rowKey: 'row:input-1',
              source: const InputChatSource(inputId: 'input-1'),
              payloadSchema: 'anywork.event/1',
              payloadJson: jsonEncode({
                'contract': 'anywork.event/1',
                'type': 'text',
                'meta': {
                  'entityId': 'input-1',
                  'entityKind': 'input',
                  'delivery': 'foreground',
                  'state': {'kind': 'knownTerminal', 'outcome': 'completed'},
                  'contentPresent': true,
                },
                'data': {'channel': 'user'},
                'bodies': [
                  {
                    'key': 'body',
                    'byteLength': utf8.encode(_inputText).length,
                    'inlineText': _inputText,
                  },
                ],
              }),
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
  bool includeBodyAtom = true,
}) => ProjectionCurrentFrame(
  revision: CurrentRevision(ownerId: ownerId, revision: revision),
  projection: CurrentProjection(
    logicalStatus: ThreadStatusView.running,
    executionPresent: true,
    activeTurn: CurrentTurnHead(id: turnId, phase: CurrentTurnPhase.responding),
    sources: const [],
    atoms: includeBodyAtom
        ? [_currentAtom(turnId: turnId, ownerId: ownerId)]
        : const [],
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
  required bool Function() showLiveStatus,
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
              if (showLiveStatus()) LiveStatusBar(threadId: threadId),
            ],
          );
        },
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'LiveStatusBar owns Current body layout and responding suppression while Timeline stays immutable',
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
      var showLiveStatus = true;
      late StateSetter rebuildRoot;
      await tester.pumpWidget(
        _root(
          graph: graph,
          threadId: _threadId,
          showTimeline: () => showTimeline,
          showLiveStatus: () => showLiveStatus,
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
      reader.onReadBody = (_, range) async => ContentWindow(
        offset: range.offset,
        bytes: const [],
        generation: _bodyRef(ownerId).generation,
        availableThrough: 0,
        sealed: false,
      );
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
      expect(
        find.descendant(
          of: find.byType(TimelineConnector),
          matching: find.byType(ConversationResponseView),
        ),
        findsNothing,
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
        'laid-out Current body inside LiveStatusBar',
      );
      expect(
        find.descendant(
          of: find.byType(LiveStatusBar),
          matching: find.byType(ContentLayoutWitness),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(LiveStatusBar),
          matching: find.byType(ConversationResponseView),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(TimelineConnector),
          matching: find.text(_bodyText),
        ),
        findsNothing,
      );
      expect(
        graph.timeline.lease(_threadId)!.controller.messages.map((m) => m.id),
        ['row:input-1'],
      );
      expect(find.byType(ConversationActivityStatus), findsNothing);

      const appendedBody = '$_bodyText\nmore streamed text';
      final appendedBytes = utf8.encode(appendedBody);
      firstBody.add(
        ContentWindow(
          offset: 0,
          bytes: appendedBytes,
          generation: _bodyRef(ownerId).generation,
          availableThrough: appendedBytes.length,
          sealed: false,
        ),
      );
      await pumpClientUntil(
        tester,
        () => find.text(appendedBody).evaluate().isNotEmpty,
        'same Current window displays appended text',
      );
      expect(find.byType(ConversationActivityStatus), findsNothing);
      expect(
        graph.timeline.lease(_threadId)!.renderedCurrentAtomIds,
        contains(_atomId),
      );

      // Hiding Timeline does not interrupt LiveStatusBar streaming or suppression.
      showTimeline = false;
      rebuildRoot(() {});
      await tester.pump();
      expect(
        graph.timeline.lease(_threadId)!.renderedCurrentAtomIds,
        contains(_atomId),
      );
      expect(find.byType(ConversationActivityStatus), findsNothing);

      // Unmounting LiveStatusBar immediately clears rendered Current body evidence.
      showLiveStatus = false;
      rebuildRoot(() {});
      await tester.pump();
      await pumpClientUntil(
        tester,
        () => graph.timeline.lease(_threadId)!.renderedCurrentAtomIds.isEmpty,
        'unmounted LiveStatusBar clears renderedCurrentAtomIds',
      );

      // Removing active body atom restores ConversationActivityStatus when LiveStatusBar returns.
      showTimeline = true;
      showLiveStatus = true;
      reader.emitCurrentFrame(
        _projectionFrame(
          ownerId: ownerId,
          revision: 4,
          turnId: _turnId,
          includeBodyAtom: false,
        ),
      );
      rebuildRoot(() {});
      await tester.pump();
      await pumpClientUntil(
        tester,
        () => find.byType(ConversationActivityStatus).evaluate().isNotEmpty,
        'missing Current body restores status',
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
        _projectionFrame(ownerId: ownerId, revision: 5, turnId: 'other-turn'),
      );
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
