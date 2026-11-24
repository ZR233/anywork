import 'package:anywork/src/features/conversation/timeline/state/timeline_current_projection.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_history_projection.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_canonical_payload_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_models.dart';
import 'package:anywork_client/conversation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _currentRef = CurrentContentRef(
  ownerId: 'run-1',
  domain: 'content',
  entityId: 'entity-1',
  contentKey: 'body',
  generation: '3',
);

CurrentAtom _atom({
  String id = 'entity-1',
  ChatAtomKind kind = ChatAtomKind.toolCall,
  ChatToolIdentity? tool = const ChatToolIdentity(
    callId: 'call-1',
    name: 'read_file',
  ),
}) => CurrentAtom(
  id: id,
  source: const ForegroundTurnChatSource(turnId: 'turn-1'),
  sourceOrder: 1,
  kind: kind,
  delivery: ChatDeliveryKind.foreground,
  lifecycle: const ActiveChatAtom(
    started: null,
    status: ChatActiveStatus.running,
  ),
  turnId: 'turn-1',
  tool: tool,
  contentPresent: true,
  contents: const [
    CurrentAtomContent(role: ChatContentRole.body, reference: _currentRef),
  ],
);

DisplayRecord _record({
  bool isTerminalHistory = false,
  bool isFrozenHistory = false,
  String? callId,
  String? runId = 'run-1',
}) => DisplayRecord(
  atom: ChatAtom(
    id: 'entity-1',
    source: const ForegroundTurnChatSource(turnId: 'turn-1'),
    sourceOrder: 1,
    kind: ChatAtomKind.toolCall,
    delivery: ChatDeliveryKind.foreground,
    lifecycle: isTerminalHistory
        ? const TerminalChatAtom(
            started: null,
            ended: null,
            outcome: ChatTerminalOutcome.completed,
          )
        : const ActiveChatAtom(started: null, status: ChatActiveStatus.running),
    turnId: 'turn-1',
    contentPresent: true,
    contents: const [],
  ),
  contentSource: const CompletedOriginal(completionId: 'event-1'),
  historyEventId: 'event-1',
  historyDetailEventId: 'detail-1',
  runId: runId,
  callId: callId,
  isTerminalHistory: isTerminalHistory,
  isFrozenHistory: isFrozenHistory,
);

void main() {
  test('LiveStatusBar overlayRecord overlays matching entity or callId and retains immutableRecord', () {
    final byId = TimelineCurrentProjection.overlayRecord(
      _record(),
      current: {'entity-1': _atom()},
      currentByCall: const {},
      ownerId: 'run-1',
    );
    expect(byId.contentSource, isA<CurrentAtomSource>());
    expect(byId.currentContents.single.reference, _currentRef);
    expect(byId.historyEventId, isNull);
    expect(byId.historyDetailEventId, isNull);
    expect(byId.immutableRecord?.historyEventId, 'event-1');

    final differentAtom = _atom(id: 'different-atom-id');
    final byCallId = TimelineCurrentProjection.overlayRecord(
      _record(callId: 'call-1'),
      current: {differentAtom.id: differentAtom},
      currentByCall: {'call-1': differentAtom},
      ownerId: 'run-1',
    );
    expect(byCallId.contentSource, isA<CurrentAtomSource>());
    expect(byCallId.currentContents.single.reference, _currentRef);

    final restored = TimelineCurrentProjection.overlayRecord(
      byId,
      current: const {},
      currentByCall: const {},
      ownerId: 'run-1',
    );
    expect(restored.historyEventId, 'event-1');
    expect(restored.currentContents, isEmpty);
    expect(restored.contentSource, isA<CompletedOriginal>());
  });

  test('terminal, frozen, and foreign-owner records never accept late Current overlay', () {
    final active = _record();
    for (final protected in [
      _record(isTerminalHistory: true),
      _record(isFrozenHistory: true),
    ]) {
      final result = TimelineCurrentProjection.overlayRecord(
        protected,
        current: {'entity-1': _atom()},
        currentByCall: const {},
        ownerId: 'run-1',
      );
      expect(result, same(protected));
    }

    final olderRun = TimelineCurrentProjection.overlayRecord(
      active,
      current: {'entity-1': _atom()},
      currentByCall: const {},
      ownerId: 'run-2',
    );
    expect(olderRun, same(active));
  });

  testWidgets(
    'Current raw body is rendered by its body owner, not JSON decode',
    (tester) async {
      final record = DisplayRecord(
        atom: _atomAsChatAtom(),
        contentSource: const CurrentAtomSource(),
        currentContents: const [
          CurrentAtomContent(
            role: ChatContentRole.body,
            reference: _currentRef,
          ),
        ],
      );
      final item = ChatItemPresentation.forRecord(record, id: 'entity-1');
      var rendered = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: TimelineCanonicalPayloadConnector(
            item: item,
            threadId: 'thread',
            isActive: () => true,
            render: (_) {
              rendered++;
              return const Text('raw-current-body-owner');
            },
          ),
        ),
      );
      expect(rendered, 1);
      expect(find.text('raw-current-body-owner'), findsOneWidget);
      expect(find.textContaining('正在读取'), findsNothing);
    },
  );
  test('TimelineHistoryProjection distinguishes migrated original, boundary empty, and unavailable legacy events', () {
    const cut = HistoryCut('cut-1');
    HistoryEventRecord record({
      required String id,
      required String kind,
      required HistoryTimelineRole timelineRole,
      required String payloadJson,
      String? callId,
      String? toolName,
    }) => HistoryEventRecord(
      seq: 1,
      eventId: id,
      kind: kind,
      timelineRole: timelineRole,
      recordedAt: 1000,
      callId: callId,
      toolName: toolName,
      payloadSchema: 'anywork.event/1',
      payloadJson: payloadJson,
    );

    final inputBlock = TimelineHistoryProjection.block(
      DividerTimelineItem(
        record(
          id: 'legacy:v24:input',
          kind: 'input_accepted',
          timelineRole: HistoryTimelineRole.divider,
          payloadJson: '{"contract":"anywork.event/1","type":"text","meta":{"entityId":"app-1","entityKind":"input","delivery":"independent","state":{"kind":"knownTerminal","outcome":"completed"},"textChannel":"user","singleVisibility":"content"},"data":{"channel":"user","attachments":[]},"bodies":[]}',
        ),
      ),
      cut: cut,
    );
    final inputSingle = inputBlock.body as SingleDisplayBlock;
    expect(inputSingle.record.contentSource, isA<CompletedOriginal>());
    expect(inputSingle.record.isFrozenHistory, isFalse);

    final emptyBoundary = TimelineHistoryProjection.recordFromEvent(
      record(
        id: 'legacy:v24:boundary',
        kind: 'boundary_observed',
        timelineRole: HistoryTimelineRole.work,
        payloadJson: '{"contract":"anywork.event/1","type":"thinking","capturedAt":5000,"meta":{"entityId":"think-1","entityKind":"reasoning","delivery":"foreground","state":{"kind":"knownTerminal","outcome":"completed"}},"data":{"channel":"final","attachments":[],"legacyUnavailable":false},"bodies":[]}',
      ),
    );
    expect(
      emptyBoundary.contentSource,
      isA<FrozenObservation>()
          .having((s) => s.capturedAt, 'capturedAt', 5000)
          .having((s) => s.available, 'available', isTrue),
    );

    final unavailable = TimelineHistoryProjection.recordFromEvent(
      record(
        id: 'legacy:v24:unavailable',
        kind: 'legacy_observed',
        timelineRole: HistoryTimelineRole.work,
        payloadJson: '{"contract":"anywork.event/1","type":"thinking","capturedAt":6000,"meta":{"entityId":"think-2","entityKind":"reasoning","delivery":"foreground","state":{"kind":"knownTerminal","outcome":"completed"},"contentPresent":false},"data":{"channel":"final","attachments":[],"legacyUnavailable":true},"bodies":[]}',
      ),
    );
    expect(
      unavailable.contentSource,
      isA<FrozenObservation>()
          .having((s) => s.capturedAt, 'capturedAt', 6000)
          .having((s) => s.available, 'available', isFalse),
    );
  });
}

ChatAtom _atomAsChatAtom() => ChatAtom(
  id: 'entity-1',
  source: const ForegroundTurnChatSource(turnId: 'turn-1'),
  sourceOrder: 1,
  kind: ChatAtomKind.text,
  delivery: ChatDeliveryKind.foreground,
  lifecycle: const ActiveChatAtom(
    started: null,
    status: ChatActiveStatus.running,
  ),
  turnId: 'turn-1',
  contentPresent: true,
  contents: const [],
);
