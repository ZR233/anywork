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
  test('typed neutral and inference kinds retain provenance on the wire', () {
    for (final kind in [
      ChatAtomKind.raw,
      ChatAtomKind.agent,
      ChatAtomKind.inference,
      ChatAtomKind.unknown,
    ]) {
      final atom = ChatAtom(
        id: 'typed-origin',
        source: const ForegroundTurnChatSource(turnId: 'turn'),
        sourceOrder: 2,
        kind: kind,
        delivery: ChatDeliveryKind.foreground,
        lifecycle: const ActiveChatAtom(
          status: ChatActiveStatus.running,
          started: ChatFactPosition(effectSeq: 3, suborder: 4),
        ),
        turnId: 'turn',
        contents: const [],
      );
      final encoded = chatAtomToJson(atom);
      expect(encoded['kind'], kind.name);
      expect(encoded['source'], {'kind': 'foregroundTurn', 'turnId': 'turn'});
      expect(encoded['lifecycle'], {
        'kind': 'active',
        'started': {'effectSeq': 3, 'suborder': 4},
        'status': 'running',
      });
      expect(
        chatAtomEntryEncodedLength(atom),
        utf8.encode(jsonEncode({'kind': 'atom', 'value': encoded})).length,
      );
    }
  });
  test(
    'content presence preserves explicit false separately from legacy unknown',
    () {
      final atom = ChatAtom(
        id: 'empty',
        source: const InputChatSource(inputId: 'input'),
        sourceOrder: null,
        kind: ChatAtomKind.input,
        delivery: ChatDeliveryKind.independent,
        lifecycle: const ActiveChatAtom(
          started: null,
          status: ChatActiveStatus.running,
        ),
        contentPresent: false,
        contents: const [],
      );
      expect(chatAtomToJson(atom)['contentPresent'], isFalse);
      expect(
        chatAtomToJson(_activeWait(null)),
        isNot(contains('contentPresent')),
      );
    },
  );

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
