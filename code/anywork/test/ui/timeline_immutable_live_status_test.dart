import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_connector.dart';
import 'package:anywork/src/features/conversation/timeline/live_status/live_status_bar.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/completion_run_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/conversation_activity_bar.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../../anywork_client/test/support/timeline_transport.dart'
    show TestHistoryReader;
import '../support/chat_fixtures.dart';
import '../support/pump_client_future.dart';
import '../support/recording_demo_transport.dart';
import '../support/test_app_lifecycle.dart';
import '../support/test_statistics_feed.dart';

const _threadId = 'thread-main';

CurrentContentRef _currentRef(String ownerId, String entityId) =>
    CurrentContentRef(
      ownerId: ownerId,
      domain: 'thread',
      entityId: entityId,
      contentKey: 'body',
      generation: '1',
    );

HistoryEventRecord _inputDivider({
  required int seq,
  required String id,
  required String text,
  required String runId,
  required String turnId,
}) => HistoryEventRecord(
  seq: seq,
  eventId: 'event:$id',
  kind: 'input_accepted',
  timelineRole: HistoryTimelineRole.divider,
  recordedAt: seq * 1000,
  occurredAt: seq * 1000,
  runId: runId,
  turnId: turnId,
  entityId: id,
  rowKey: 'row:$id',
  source: InputChatSource(inputId: id),
  payloadSchema: 'anywork.event/1',
  payloadJson: jsonEncode({
    'contract': 'anywork.event/1',
    'type': 'text',
    'meta': {
      'entityId': id,
      'entityKind': 'input',
      'delivery': 'foreground',
      'state': {'kind': 'knownTerminal', 'outcome': 'completed'},
      'contentPresent': true,
    },
    'data': {'channel': 'user'},
    'bodies': [
      {
        'key': 'body',
        'byteLength': utf8.encode(text).length,
        'inlineText': text,
      },
    ],
  }),
);

HistoryEventRecord _finalTextDivider({
  required int seq,
  required String id,
  required String text,
  required String runId,
  required String turnId,
}) => HistoryEventRecord(
  seq: seq,
  eventId: 'event:$id',
  kind: 'text_completed',
  timelineRole: HistoryTimelineRole.divider,
  recordedAt: seq * 1000,
  occurredAt: seq * 1000,
  runId: runId,
  turnId: turnId,
  entityId: id,
  rowKey: 'row:$id',
  source: ForegroundTurnChatSource(turnId: turnId),
  payloadSchema: 'anywork.event/1',
  payloadJson: jsonEncode({
    'contract': 'anywork.event/1',
    'type': 'text',
    'meta': {
      'entityId': id,
      'entityKind': 'text',
      'delivery': 'foreground',
      'state': {'kind': 'knownTerminal', 'outcome': 'completed'},
      'contentPresent': true,
      'startedAt': seq * 1000,
      'finishedAt': seq * 1000 + 200,
    },
    'data': {'channel': 'final'},
    'bodies': [
      {
        'key': 'body',
        'byteLength': utf8.encode(text).length,
        'inlineText': text,
      },
    ],
  }),
);

HistoryEventRecord _toolCalled({
  required int seq,
  required String callId,
  required String toolName,
  required String runId,
  required String turnId,
}) => HistoryEventRecord(
  seq: seq,
  eventId: 'event:tool-called:$callId',
  kind: 'tool_called',
  timelineRole: HistoryTimelineRole.work,
  recordedAt: seq * 1000,
  occurredAt: seq * 1000,
  runId: runId,
  turnId: turnId,
  entityId: 'tool:${callId.length}:$callId',
  callId: callId,
  toolName: toolName,
  rowKey: 'call:$callId',
  source: ForegroundTurnChatSource(turnId: turnId),
  payloadSchema: 'anywork.event/1',
  payloadJson: jsonEncode({
    'contract': 'anywork.event/1',
    'type': 'tool',
    'meta': {
      'entityId': 'tool:${callId.length}:$callId',
      'entityKind': 'toolCall',
      'delivery': 'foreground',
      'tool': {'callId': callId, 'name': toolName},
      'state': {'kind': 'knownActive', 'status': 'running'},
      'startedAt': seq * 1000,
      'contentPresent': true,
    },
    'data': {
      'callId': callId,
      'toolName': toolName,
      'state': {'kind': 'running'},
      'invocation': {
        'callId': callId,
        'toolName': toolName,
        'presentationContract': 'builtin.read_file@1',
      },
    },
    'bodies': [
      {
        'key': 'tool.arguments',
        'byteLength': 19,
        'inlineText': '{"path":"a.txt"}',
      },
    ],
  }),
);

HistoryEventRecord _toolCompleted({
  required int seq,
  required String callId,
  required String toolName,
  required String runId,
  required String turnId,
  required String resultText,
}) => HistoryEventRecord(
  seq: seq,
  eventId: 'event:tool-done:$callId',
  kind: 'tool_completed',
  timelineRole: HistoryTimelineRole.work,
  recordedAt: seq * 1000,
  occurredAt: seq * 1000,
  runId: runId,
  turnId: turnId,
  entityId: 'tool:${callId.length}:$callId',
  callId: callId,
  toolName: toolName,
  rowKey: 'call:$callId',
  source: ForegroundTurnChatSource(turnId: turnId),
  payloadSchema: 'anywork.event/1',
  payloadJson: jsonEncode({
    'contract': 'anywork.event/1',
    'type': 'tool',
    'meta': {
      'entityId': 'tool:${callId.length}:$callId',
      'entityKind': 'toolCall',
      'delivery': 'foreground',
      'tool': {'callId': callId, 'name': toolName},
      'state': {'kind': 'knownTerminal', 'outcome': 'completed'},
      'startedAt': (seq - 1) * 1000,
      'finishedAt': seq * 1000,
      'contentPresent': true,
    },
    'data': {
      'callId': callId,
      'toolName': toolName,
      'state': {'kind': 'succeeded'},
      'invocation': {
        'callId': callId,
        'toolName': toolName,
        'presentationContract': 'builtin.read_file@1',
      },
    },
    'bodies': [
      {
        'key': 'tool.result',
        'byteLength': utf8.encode(resultText).length,
        'inlineText': resultText,
      },
    ],
  }),
);

final class _SnapshotOverrideCurrentReader implements CurrentReader {
  _SnapshotOverrideCurrentReader(this.inner);

  final RecordingCurrentReader inner;
  CurrentView? snapshotOverride;

  @override
  OpenCurrent get metadata => inner.metadata;

  @override
  String get threadId => inner.threadId;

  @override
  CurrentView get initialView => snapshotOverride ?? inner.initialView;

  @override
  Future<CurrentView> snapshot(ReadDemand demand) async =>
      snapshotOverride ?? await inner.snapshot(demand);

  @override
  Future<CurrentWatch> watch({
    CurrentRevision? after,
    required ReadDemand demand,
  }) => inner.watch(after: after, demand: demand);

  @override
  Future<CurrentCollectionPage> pageCollection({
    required CurrentCollectionRef reference,
    String? continuation,
    required ReadDemand demand,
  }) => inner.pageCollection(
    reference: reference,
    continuation: continuation,
    demand: demand,
  );

  @override
  Future<ContentWindow> readBody({
    required CurrentContentRef reference,
    required ContentRange range,
  }) => inner.readBody(reference: reference, range: range);

  @override
  Future<CurrentBodyWatch> watchBody({
    required CurrentContentRef reference,
    required ContentRange range,
  }) => inner.watchBody(reference: reference, range: range);

  @override
  void requestClose() => inner.requestClose();

  @override
  Future<void> close() => inner.close();
}

final class _ImmutableLiveTransport extends RecordingDemoTransport {
  final currentOwner = Completer<String>();
  final Map<String, List<_SnapshotOverrideCurrentReader>> wrappedCurrent = {};

  HistoryCut currentCut = const HistoryCut('cut-1');
  List<HistoryTimelineItem> Function(HistoryCut cut, String ownerId)?
  timelineBuilder;
  List<HistoryEventRecord> Function(
    int? afterSeq,
    int? beforeSeq,
    HistoryCut cut,
    String ownerId,
  )?
  workRangeBuilder;

  Completer<HistoryCut>? _changeWaiter;

  void emitHistoryChange(HistoryCut nextCut) {
    currentCut = nextCut;
    final waiter = _changeWaiter;
    _changeWaiter = null;
    waiter?.complete(nextCut);
  }

  void setCurrentSnapshot(String threadId, CurrentView view) {
    for (final reader in wrappedCurrent[threadId] ?? const []) {
      reader.snapshotOverride = view;
    }
  }

  @override
  Future<CurrentReader> openCurrentReader(
    String threadId, {
    required int currentProtocolVersion,
    required ReadDemand demand,
  }) async {
    final base = await super.openCurrentReader(
      threadId,
      currentProtocolVersion: currentProtocolVersion,
      demand: demand,
    ) as RecordingCurrentReader;
    if (!currentOwner.isCompleted) {
      currentOwner.complete(base.metadata.currentOwnerId);
    }
    final wrapper = _SnapshotOverrideCurrentReader(base);
    wrappedCurrent.putIfAbsent(threadId, () => []).add(wrapper);
    return wrapper;
  }

  @override
  Future<HistoryReader> openHistoryReader(
    String threadId, {
    required int historyProtocolVersion,
  }) async {
    final ownerId = await currentOwner.future;
    final reader = TestHistoryReader(threadId: threadId, cut: currentCut);
    reader.onTimeline = (cut, cursor, demand) async {
      final activeCut = cut ?? currentCut;
      return HistoryTimelinePage(
        cut: activeCut,
        items: cursor == null
            ? (timelineBuilder?.call(activeCut, ownerId) ?? const [])
            : const [],
      );
    };
    reader.onWorkRange = (afterSeq, beforeSeq, cut, cursor, demand) async {
      final activeCut = cut ?? currentCut;
      return HistoryWorkRangePage(
        cut: activeCut,
        afterSeq: afterSeq,
        beforeSeq: beforeSeq,
        events: cursor == null
            ? (workRangeBuilder?.call(
                    afterSeq,
                    beforeSeq,
                    activeCut,
                    ownerId,
                  ) ??
                  const [])
            : const [],
      );
    };
    reader.onWaitChanged = (cut) {
      if (cut != currentCut) return Future.value(currentCut);
      return (_changeWaiter ??= Completer<HistoryCut>()).future;
    };
    return reader;
  }
}

void main() {
  testWidgets(
    'LiveStatusBar hosts open work and streaming text while Timeline keeps immutable finalized rows',
    (tester) async {
      final transport = _ImmutableLiveTransport();
      late String runId;
      const turn1 = 'turn-1';
      const turn2 = 'turn-2';
      const reply1Text = 'Final answer from turn 1';

      var stage = 1;
      transport.timelineBuilder = (cut, ownerId) {
        runId = ownerId;
        return switch (stage) {
          1 => [
            DividerTimelineItem(
              _inputDivider(
                seq: 1,
                id: 'input-1',
                text: 'First prompt',
                runId: ownerId,
                turnId: turn1,
              ),
            ),
          ],
          2 => [
            WorkRangeTimelineItem(
              HistoryWorkRange(
                rangeId: 'work:2',
                afterSeq: 1,
                beforeSeq: null,
                firstSeq: 2,
                lastSeq: 3,
                startedAt: 2000,
                endedAt: 3000,
                runId: ownerId,
                eventCount: 2,
              ),
            ),
            DividerTimelineItem(
              _inputDivider(
                seq: 1,
                id: 'input-1',
                text: 'First prompt',
                runId: ownerId,
                turnId: turn1,
              ),
            ),
          ],
          3 => [
            DividerTimelineItem(
              _finalTextDivider(
                seq: 4,
                id: 'text-1',
                text: reply1Text,
                runId: ownerId,
                turnId: turn1,
              ),
            ),
            WorkRangeTimelineItem(
              HistoryWorkRange(
                rangeId: 'work:2',
                afterSeq: 1,
                beforeSeq: 4,
                firstSeq: 2,
                lastSeq: 3,
                startedAt: 2000,
                endedAt: 3000,
                runId: ownerId,
                eventCount: 2,
              ),
            ),
            DividerTimelineItem(
              _inputDivider(
                seq: 1,
                id: 'input-1',
                text: 'First prompt',
                runId: ownerId,
                turnId: turn1,
              ),
            ),
          ],
          _ => [
            DividerTimelineItem(
              _inputDivider(
                seq: 5,
                id: 'input-2',
                text: 'Second prompt',
                runId: ownerId,
                turnId: turn2,
              ),
            ),
            DividerTimelineItem(
              _finalTextDivider(
                seq: 4,
                id: 'text-1',
                text: reply1Text,
                runId: ownerId,
                turnId: turn1,
              ),
            ),
            WorkRangeTimelineItem(
              HistoryWorkRange(
                rangeId: 'work:2',
                afterSeq: 1,
                beforeSeq: 4,
                firstSeq: 2,
                lastSeq: 3,
                startedAt: 2000,
                endedAt: 3000,
                runId: ownerId,
                eventCount: 2,
              ),
            ),
            DividerTimelineItem(
              _inputDivider(
                seq: 1,
                id: 'input-1',
                text: 'First prompt',
                runId: ownerId,
                turnId: turn1,
              ),
            ),
          ],
        };
      };

      transport.workRangeBuilder = (afterSeq, beforeSeq, cut, ownerId) {
        if (afterSeq == 1) {
          return [
            _toolCalled(
              seq: 2,
              callId: 'call-read',
              toolName: 'read_file',
              runId: ownerId,
              turnId: turn1,
            ),
            if (stage >= 3)
              _toolCompleted(
                seq: 3,
                callId: 'call-read',
                toolName: 'read_file',
                runId: ownerId,
                turnId: turn1,
                resultText: 'file-contents',
              ),
          ];
        }
        return const [];
      };

      final graph = testAppGraph(
        statisticsFeed: const TestStatisticsFeedPort(),
        transport: transport,
        clientId: 'timeline-immutable-live',
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
            'teardown close',
          );
          expect(report.complete, isTrue);
          graphClosed = true;
        }
      });

      await pumpClientFuture(tester, graph.client.bootstrap(), 'bootstrap');
      graph.timeline.updateReadDemand(chatDemand);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appGraphProvider.overrideWithValue(graph)],
          child: MaterialApp(
            theme: pureStudioTheme(),
            locale: const Locale('zh'),
            localizationsDelegates: [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: Column(
                children: [
                  Expanded(child: TimelineConnector(threadId: _threadId)),
                  LiveStatusBar(threadId: _threadId),
                ],
              ),
            ),
          ),
        ),
      );

      graph.setConversationPageVisible(true);
      await pumpClientFuture(
        tester,
        graph.client.directoryCommands.selectThread(_threadId),
        'select thread',
      );
      await pumpClientFuture(
        tester,
        timelineReady(graph.timeline, _threadId),
        'timeline ready',
      );
      await pumpClientUntil(
        tester,
        () => find.text('First prompt').evaluate().isNotEmpty,
        'initial input divider rendered',
      );

      final lease = graph.timeline.lease(_threadId)!;
      final input1Message = lease.controller.messages.single;
      expect(input1Message.id, 'row:input-1');

      // Turn 1 begins running with a live open WorkRange and active tool atom.
      final activeToolAtom = CurrentAtom(
        id: 'tool:9:call-read',
        source: const ForegroundTurnChatSource(turnId: turn1),
        sourceOrder: 1,
        kind: ChatAtomKind.toolCall,
        delivery: ChatDeliveryKind.foreground,
        lifecycle: const ActiveChatAtom(
          started: null,
          status: ChatActiveStatus.running,
        ),
        turnId: turn1,
        tool: const ChatToolIdentity(callId: 'call-read', name: 'read_file'),
        contentPresent: false,
        contents: const [],
      );
      final runningWorkspace = chatWorkspace(_threadId).copyWith(
        revision: 2,
        thread: chatWorkspace(_threadId).thread
            .copyWith(status: ThreadStatusView.running),
        runtime: chatWorkspace(_threadId).runtime.copyWith(
          execution: const AgentExecutionView(
            id: 'exec-1',
            phase: AgentExecutionPhase.running,
            turnId: turn1,
          ),
        ),
        activeTurn: StudioTurnView(
          turnId: turn1,
          threadId: _threadId,
          revision: 1,
          state: const RunningStudioTurnState(
            startedAt: 2,
            activity: StudioTurnActivity.runningTool,
          ),
          updatedAt: DateTime.utc(2026, 11, 22),
        ),
        activity: const ThreadActivityView(
          threadId: _threadId,
          identity: 'running:tool',
          revision: 1,
          turnId: turn1,
          kind: ThreadActivityKind.runningTool,
          summary: 'Reading a.txt',
        ),
      );
      final runningProjection = CurrentProjection(
        logicalStatus: ThreadStatusView.running,
        executionPresent: true,
        activeTurn: const CurrentTurnHead(
          id: turn1,
          phase: CurrentTurnPhase.runningTool,
        ),
        sources: const [],
        atoms: [activeToolAtom],
        previews: const [],
        collections: const [],
      );

      final timelineWrapper = lease.current! as _SnapshotOverrideCurrentReader;
      transport.setCurrentSnapshot(
        _threadId,
        CurrentView(
          revision: CurrentRevision(ownerId: runId, revision: 2),
          state: ThreadSnapshotFrame(
            workspace: runningWorkspace,
            schemaVersion: threadSchemaVersion,
          ),
          projection: runningProjection,
        ),
      );
      await transport.publishWorkspace(runningWorkspace);
      timelineWrapper.inner.emitCurrentFrame(
        ProjectionCurrentFrame(
          revision: CurrentRevision(ownerId: runId, revision: 2),
          projection: runningProjection,
        ),
      );

      stage = 2;
      transport.emitHistoryChange(const HistoryCut('cut-2'));
      await pumpClientUntil(
        tester,
        () => find
            .descendant(
              of: find.byType(LiveStatusBar),
              matching: find.byType(CompletionRunView),
            )
            .evaluate()
            .isNotEmpty,
        'live open Work mounted in LiveStatusBar',
      );

      // Expand open Work inside LiveStatusBar and confirm active tool renders there.
      await tester.tap(
        find.descendant(
          of: find.byType(LiveStatusBar),
          matching: find.byType(CompletionRunView),
        ),
      );
      await tester.pump();
      await pumpClientUntil(
        tester,
        () => find
            .descendant(
              of: find.byType(LiveStatusBar),
              matching: find.textContaining('a.txt'),
            )
            .evaluate()
            .isNotEmpty,
        'open live tool folded inside LiveStatusBar',
      );

      // Main Timeline must remain completely untouched (only immutable input-1).
      expect(lease.controller.messages, hasLength(1));
      expect(
        identical(lease.controller.messages.single, input1Message),
        isTrue,
      );
      expect(
        find.descendant(
          of: find.byType(TimelineConnector),
          matching: find.byType(CompletionRunView),
        ),
        findsNothing,
      );
      // Ordinary runningTool status is suppressed while live open Work header takes over.
      expect(
        find.descendant(
          of: find.byType(LiveStatusBar),
          matching: find.byType(ConversationActivityStatus),
        ),
        findsNothing,
      );

      // Live streaming response text renders inside LiveStatusBar without touching Timeline.
      final textListening = Completer<void>();
      final textStream = StreamController<ContentWindow>.broadcast(
        sync: true,
        onListen: () {
          if (!textListening.isCompleted) textListening.complete();
        },
      );
      addTearDown(textStream.close);
      const streamBody = 'Streaming partial answer';
      final streamBytes = utf8.encode(streamBody);
      timelineWrapper.inner.onReadBody = (_, range) async => ContentWindow(
        offset: range.offset,
        bytes: streamBytes,
        generation: '1',
        availableThrough: streamBytes.length,
        sealed: false,
      );
      timelineWrapper.inner.onWatchBody = (_, _) => textStream.stream;

      final streamingAtom = CurrentAtom(
        id: 'text:turn-1',
        source: const ForegroundTurnChatSource(turnId: turn1),
        sourceOrder: 2,
        kind: ChatAtomKind.text,
        delivery: ChatDeliveryKind.foreground,
        lifecycle: const ActiveChatAtom(
          started: null,
          status: ChatActiveStatus.running,
        ),
        turnId: turn1,
        startedAt: 3,
        contentPresent: true,
        contents: [
          CurrentAtomContent(
            role: ChatContentRole.body,
            reference: _currentRef(runId, 'text:turn-1'),
          ),
        ],
      );
      final respondingWorkspace = runningWorkspace.copyWith(
        revision: 3,
        runtime: runningWorkspace.runtime.copyWith(
          execution: const AgentExecutionView(
            id: 'exec-1',
            phase: AgentExecutionPhase.running,
            turnId: turn1,
          ),
        ),
        activity: const ThreadActivityView(
          threadId: _threadId,
          identity: 'responding:turn1',
          revision: 2,
          turnId: turn1,
          kind: ThreadActivityKind.responding,
          summary: 'Streaming',
        ),
      );
      final respondingProjection = CurrentProjection(
        logicalStatus: ThreadStatusView.running,
        executionPresent: true,
        activeTurn: const CurrentTurnHead(
          id: turn1,
          phase: CurrentTurnPhase.responding,
        ),
        sources: const [],
        atoms: [streamingAtom],
        previews: const [],
        collections: const [],
      );
      transport.setCurrentSnapshot(
        _threadId,
        CurrentView(
          revision: CurrentRevision(ownerId: runId, revision: 3),
          state: ThreadSnapshotFrame(
            workspace: respondingWorkspace,
            schemaVersion: threadSchemaVersion,
          ),
          projection: respondingProjection,
        ),
      );
      await transport.publishWorkspace(respondingWorkspace);
      timelineWrapper.inner.emitCurrentFrame(
        ProjectionCurrentFrame(
          revision: CurrentRevision(ownerId: runId, revision: 3),
          projection: respondingProjection,
        ),
      );
      await pumpClientUntil(
        tester,
        () => textListening.isCompleted,
        'streaming body watchBody subscribed',
      );
      textStream.add(
        ContentWindow(
          offset: 0,
          bytes: streamBytes,
          generation: '1',
          availableThrough: streamBytes.length,
          sealed: false,
        ),
      );
      await pumpClientUntil(
        tester,
        () => find
            .descendant(
              of: find.byType(LiveStatusBar),
              matching: find.text(streamBody),
            )
            .evaluate()
            .isNotEmpty,
        'streaming body in LiveStatusBar',
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
          matching: find.text(streamBody),
        ),
        findsNothing,
      );
      expect(
        identical(lease.controller.messages.single, input1Message),
        isTrue,
      );

      // Final divider + idle state settles WorkRange + reply once into Timeline and hides LiveStatusBar.
      final idleWorkspace = chatWorkspace(_threadId).copyWith(revision: 4);
      final idleProjection = CurrentProjection(
        logicalStatus: ThreadStatusView.idle,
        executionPresent: true,
        sources: const [],
        atoms: const [],
        previews: const [],
        collections: const [],
      );
      transport.setCurrentSnapshot(
        _threadId,
        CurrentView(
          revision: CurrentRevision(ownerId: runId, revision: 4),
          state: ThreadSnapshotFrame(
            workspace: idleWorkspace,
            schemaVersion: threadSchemaVersion,
          ),
          projection: idleProjection,
        ),
      );
      stage = 3;
      transport.emitHistoryChange(const HistoryCut('cut-3'));
      await transport.publishWorkspace(idleWorkspace);
      timelineWrapper.inner.emitCurrentFrame(
        ProjectionCurrentFrame(
          revision: CurrentRevision(ownerId: runId, revision: 4),
          projection: idleProjection,
        ),
      );
      await pumpClientUntil(
        tester,
        () =>
            lease.controller.messages.length == 3 &&
            find.byType(ConversationActivityBar).evaluate().isEmpty &&
            find.text(reply1Text).evaluate().isNotEmpty,
        'turn 1 settled into immutable Timeline and LiveStatusBar cleared',
      );

      final settledWorkMessage = lease.controller.messages[1];
      final settledReplyMessage = lease.controller.messages[2];
      expect(lease.controller.messages.map((m) => m.id), [
        'row:input-1',
        'work:2',
        'row:text-1',
      ]);
      expect(identical(lease.controller.messages[0], input1Message), isTrue);
      expect(
        identical(lease.controller.messages[2], settledReplyMessage),
        isTrue,
      );

      // Expand Turn 1's settled WorkRange inside TimelineConnector and verify persistence.
      await tester.tap(
        find.descendant(
          of: find.byType(TimelineConnector),
          matching: find.byType(CompletionRunView),
        ),
      );
      await tester.pump();
      await pumpClientUntil(
        tester,
        () =>
            find
                .descendant(
                  of: find.byType(TimelineConnector),
                  matching: find.textContaining('a.txt'),
                )
                .evaluate()
                .isNotEmpty ||
            lease.isBlockExpanded('work:2'),
        'turn 1 WorkRange expanded in Timeline',
      );
      expect(lease.isBlockExpanded('work:2'), isTrue);

      // Turn 2 arrives and advances HistoryCut: Turn 1 Timeline messages remain object-identical.
      stage = 4;
      transport.emitHistoryChange(const HistoryCut('cut-4'));
      await pumpClientUntil(
        tester,
        () =>
            lease.controller.messages.length == 4 &&
            find.text('Second prompt').evaluate().isNotEmpty,
        'turn 2 input appended',
      );
      expect(lease.controller.messages.map((m) => m.id), [
        'row:input-1',
        'work:2',
        'row:text-1',
        'row:input-2',
      ]);
      expect(identical(lease.controller.messages[0], input1Message), isTrue);
      expect(
        identical(lease.controller.messages[1], settledWorkMessage),
        isTrue,
      );
      expect(
        identical(lease.controller.messages[2], settledReplyMessage),
        isTrue,
      );
      expect(lease.isBlockExpanded('work:2'), isTrue);

      final work1Unit =
          lease.controller.messages[1].metadata![timelineDisplayUnitKey]
              as TimelineDisplayUnit;
      expect(work1Unit.state, DisplayBlockState.sealed);
      expect(
        ChatItemPresentation.forUnit(
          lease.controller.messages[2].metadata![timelineDisplayUnitKey]
              as TimelineDisplayUnit,
        ).inlineText('body'),
        reply1Text,
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
