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
