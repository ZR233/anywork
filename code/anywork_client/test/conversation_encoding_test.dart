import 'dart:convert';

import 'package:anywork_client/conversation_encoding.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

ChatAtom _activeWait(ThreadWaitPresentationView? wait) => ChatAtom(
  id: 'wait-atom',
  source: const ForegroundTurnChatSource(turnId: 'turn-a'),
  sourceOrder: 4,
  kind: ChatAtomKind.toolCall,
  delivery: ChatDeliveryKind.foreground,
  lifecycle: const ActiveChatAtom(
    started: null,
    status: ChatActiveStatus.running,
  ),
  turnId: 'turn-a',
  tool: const ChatToolIdentity(callId: 'wait-call', name: 'wait'),
  wait: wait,
  contents: const [],
);

Map<String, Object?> _expectedAtom(Object? wait) => {
  'id': 'wait-atom',
  'completionItemId': null,
  'completionSeq': null,
  'source': {'kind': 'foregroundTurn', 'turnId': 'turn-a'},
  'sourceOrder': 4,
  'kind': 'toolCall',
  'delivery': 'foreground',
  'lifecycle': {'kind': 'active', 'started': null, 'status': 'running'},
  'turnId': 'turn-a',
  'attemptId': null,
  'tool': {'callId': 'wait-call', 'name': 'wait'},
  if (wait != null) 'wait': wait,
  'textChannel': null,
  'startedAt': null,
  'finishedAt': null,
  'contents': <Object?>[],
  'payload': null,
};

void main() {
  test('Main item encoding preserves summary, typed ref, order and optional ownership', () {
    const reference = TimelineMembersRef(
      databaseId: 'database',
      projectionVersion: 3,
      itemId: 'work',
    );
    final item = TimelineItem(
      id: 'work',
      kind: TimelineItemKind.workGroup,
      source: const ForegroundTurnChatSource(turnId: 'turn'),
      delivery: ChatDeliveryKind.foreground,
      turnId: 'turn',
      summary: TimelineGroupSummary(
        memberCount: 12,
        activeCount: 2,
        failedCount: 1,
        cancelledCount: 3,
        categories: const [
          TimelineCategoryCount(category: TimelineCategory.read, count: 7),
          TimelineCategoryCount(category: TimelineCategory.wait, count: 5),
        ],
        startedAt: 100,
      ),
      members: reference,
      contents: const [],
      position: 9,
      admissionClosed: true,
    );
    final encoded = chatEntryToJson(ItemChatEntry(item));
    expect(encoded, {
      'kind': 'item',
      'value': {
        'id': 'work',
        'kind': 'workGroup',
        'source': {'kind': 'foregroundTurn', 'turnId': 'turn'},
        'delivery': 'foreground',
        'turnId': 'turn',
        'startedAt': null,
        'finishedAt': null,
        'summary': {
          'memberCount': 12,
          'activeCount': 2,
          'failedCount': 1,
          'cancelledCount': 3,
          'categories': [
            {'category': 'read', 'count': 7},
            {'category': 'wait', 'count': 5},
          ],
          'startedAt': 100,
          'finishedAt': null,
        },
        'members': {
          'databaseId': 'database',
          'projectionVersion': 3,
          'itemId': 'work',
        },
        'position': 9,
        'admissionClosed': true,
      },
    });
    final batch = ChatBatch(placement: ChatPlacement.append, entries: [ItemChatEntry(item)]);
    expect(batch.items.single, same(item));
    expect(batch.atoms, isEmpty);
    expect(reference, const TimelineMembersRef(
      databaseId: 'database', projectionVersion: 3, itemId: 'work',
    ));
    expect(reference, isNot(const TimelineMembersRef(
      databaseId: 'database', projectionVersion: 4, itemId: 'work',
    )));
  });

  test('content presence preserves explicit false separately from legacy unknown', () {
    final atom = ChatAtom(
      id: 'empty',
      source: const InputChatSource(inputId: 'input'),
      sourceOrder: null,
      kind: ChatAtomKind.input,
      delivery: ChatDeliveryKind.independent,
      lifecycle: const ActiveChatAtom(started: null, status: ChatActiveStatus.running),
      contentPresent: false,
      contents: const [],
    );
    expect(chatAtomToJson(atom)['contentPresent'], isFalse);
    expect(chatAtomToJson(_activeWait(null)), isNot(contains('contentPresent')));
  });

  test('text/status outcome is lightweight and does not require payload decoding', () {
    for (final kind in [TimelineItemKind.text, TimelineItemKind.status]) {
      final item = TimelineItem(
        id: 'interrupted',
        kind: kind,
        source: const ForegroundTurnChatSource(turnId: 'turn'),
        atomKind: ChatAtomKind.text,
        delivery: ChatDeliveryKind.foreground,
        outcome: ChatTerminalOutcome.cancelled,
        textChannel: ThreadTextChannel.finalAnswer,
        contents: const [],
        contentItemId: 'original-content',
        payload: DeferredPayload(
          reference: const ContentRef(
            databaseId: 'database',
            target: ItemPayloadTarget(itemId: 'original-content'),
          ),
          byteLength: 1000000,
        ),
        admissionClosed: true,
      );
      final encoded = timelineItemToJson(item);
      expect(encoded['outcome'], 'cancelled');
      expect(encoded['textChannel'], 'final');
      expect(encoded['contentItemId'], 'original-content');
      expect((encoded['payload'] as Map)['kind'], 'deferred');
      expect(encoded, isNot(contains('members')));
    }
  });

  test('event wait uses canonical Rust serde shape and counts target facts', () {
    final wait = ThreadWaitPresentationView(
      intent: ThreadWaitEventsIntentView(
        targets: const [
          ThreadWaitTargetView(
            taskId: 'task:timer',
            toolName: 'sleep',
            summary: 'timer still running',
            summaryTruncated: true,
            status: ThreadWaitTargetStatusView.running,
          ),
        ],
        timeoutMs: 30000,
      ),
      state: ThreadWaitStateView.waiting,
    );
    final expectedWait = {
      'intent': {
        'kind': 'events',
        'data': {
          'targets': [
            {
              'taskId': 'task:timer',
              'toolName': 'sleep',
              'summary': 'timer still running',
              'summaryTruncated': true,
              'status': 'running',
            },
          ],
          'timeoutMs': 30000,
        },
      },
      'state': 'waiting',
    };
    final atom = _activeWait(wait);
    final expectedAtom = _expectedAtom(expectedWait);

    expect(chatAtomToJson(atom), expectedAtom);
    expect(
      chatAtomEntryEncodedLength(atom),
      utf8.encode(jsonEncode({'kind': 'atom', 'value': expectedAtom})).length,
    );
    expect(
      chatAtomEntryEncodedLength(atom),
      greaterThan(chatAtomEntryEncodedLength(_activeWait(null))),
      reason:
          'typed wait and target status must consume the existing byte budget',
    );
  });

  test('timer wait uses kind/data and absent optional facts stay omitted', () {
    const wait = ThreadWaitPresentationView(
      intent: ThreadWaitTimerIntentView(durationMs: 5000),
      state: ThreadWaitStateView.waiting,
    );
    final expectedWait = {
      'intent': {
        'kind': 'timer',
        'data': {'durationMs': 5000},
      },
      'state': 'waiting',
    };

    final encoded = chatAtomToJson(_activeWait(wait));
    expect(encoded, _expectedAtom(expectedWait));
    expect(chatAtomToJson(_activeWait(null)), isNot(contains('wait')));
    expect(encoded['wait'], isNot(contains('messagesReady')));
  });
}
