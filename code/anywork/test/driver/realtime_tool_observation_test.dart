import 'package:flutter_test/flutter_test.dart';

import '../../test_driver/realtime_journey.dart' as journey;

Map<String, Object?> _item(String id, int seq, String status) => {
  'id': id,
  'appendSeq': seq,
  'sourceEffectSeq': seq,
  'sealedAt': 1700000000,
  'omittedBytes': 0,
  'kind': 'toolCall',
  'status': status,
  'text': '',
  'channel': null,
  'details': <Object?>[],
  'attachments': <Object?>[],
  'tool': {
    'name': 'exec',
    'status': status,
    'callId': 'call',
    'arguments': '{"command":"pwd"}',
    'result': status == 'succeeded' ? 'final stdout' : 'Task is running',
    'progressBytes': 0,
    'appendSeq': seq,
    'denialReason': null,
    'workingDirectory': null,
    'exitCode': status == 'succeeded' ? 0 : null,
    'attachments': <Object?>[],
  },
};

Map<String, dynamic> _snapshot({
  required List<Map<String, Object?>> items,
  List<Map<String, Object?>>? activityTools,
}) => {
  'timeline': {
    'threadId': 'thread',
    'generation': 1,
    'ready': true,
    'mode': 'live',
    'connection': 'ready',
    'timelineEpoch': 'epoch',
    'completedThrough': items.length,
    'loadedCount': items.length,
    'itemCount': items.length,
    'itemIds': [for (final item in items) item['id']],
    'olderCursor': null,
    'hasOlder': false,
    'loadingOlder': false,
    'olderError': null,
    'hasNewOutput': false,
    'items': items,
    'presentationItems': <Object?>[],
    'hiddenPresentationItems': <Object?>[],
  },
  'conversationActivity': activityTools == null
      ? null
      : {
          'identity': 'activity',
          'turnId': 'turn',
          'executionId': 'execution',
          'toolDetails': activityTools,
        },
};

void main() {
  test('completed lookup skips a separate immutable background receipt', () {
    final receipt = _item('receipt', 1, 'running');
    final completion = _item('completion', 2, 'succeeded');
    final held = _snapshot(items: [receipt]);
    expect(journey.completedToolByCallId(held, 'call'), isNull);
    final finished = _snapshot(items: [receipt, completion]);
    final result = journey.completedToolByCallId(finished, 'call')!;
    expect(result.appendSeq, 2);
    expect(result.status, 'succeeded');
    expect(result.result, 'final stdout');
    expect(
      receipt['status'],
      'running',
      reason: 'completion did not mutate ACK',
    );
  });

  test('only current activity proves queued or executing tool state', () {
    final receipt = _item('receipt', 1, 'running');
    final history = [receipt, _item('completion', 2, 'succeeded')];
    expect(journey.activeExecCount(_snapshot(items: history)), 0);
    for (final state in ['queued', 'running']) {
      final current = _snapshot(
        items: history,
        activityTools: [
          {'callId': 'new-call', 'name': 'exec', 'state': state},
          {'callId': 'wait-call', 'name': 'wait', 'state': 'running'},
        ],
      );
      expect(journey.activeExecCount(current), 1);
      expect(
        journey.liveExecStatuses(current),
        state == 'queued' ? [] : ['running'],
      );
    }
    expect(journey.liveExecStatuses(_snapshot(items: history)), isEmpty);
  });
}
