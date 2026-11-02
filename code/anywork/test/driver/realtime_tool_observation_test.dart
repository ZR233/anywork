import 'package:flutter_test/flutter_test.dart';

import '../../test_driver/realtime_journey.dart' as journey;
import '../../test_driver/timeline_observation.dart';

Map<String, Object?> _item(String id, String status) => {
  'id': id,
  'sealedAt': 1700000000,
  'compatibility': 'current',
  'payloadByteLength': 100,
  'presentationContract': 'builtin.exec@2',
  'diagnostic': null,
  'omittedBytes': 0,
  'kind': 'tool',
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
    'presentationContract': 'builtin.exec@2',
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
    'loadedCount': 0,
    'itemCount': 0,
    'itemIds': <String>[],
    'olderCursor': null,
    'hasOlder': false,
    'loadingOlder': false,
    'olderError': null,
    'hasNewOutput': false,
    'items': <Object?>[],
    'groups': <Object?>[],
    'children': [
      {
        'parentId': 'provided-parent',
        'generation': 2,
        'ready': true,
        'loadedCount': items.length,
        'olderCursor': null,
        'loadingOlder': false,
        'error': null,
        'appliedSets': 1,
        'appliedPrepends': 0,
        'appliedAppends': 0,
        'itemIds': [for (final item in items) item['id']],
        'items': items,
      },
    ],
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
    final receipt = _item('receipt', 'running');
    final completion = _item('completion', 'succeeded');
    final held = _snapshot(items: [receipt]);
    expect(journey.completedToolByCallId(held, 'call'), isNull);
    final finished = _snapshot(items: [receipt, completion]);
    final result = journey.completedToolByCallId(finished, 'call')!;
    final children = TimelineObservation.parse(finished).children.single;
    expect(children.parentId, 'provided-parent');
    expect(children.itemIds, ['receipt', 'completion']);
    expect(result.callId, 'call');
    expect(result.presentationContract, 'builtin.exec@2');
    expect(result.status, 'succeeded');
    expect(result.result, 'final stdout');
    expect(
      receipt['status'],
      'running',
      reason: 'completion did not mutate ACK',
    );
    expect((receipt['tool']! as Map)['result'], 'Task is running');
  });

  test('only current activity proves queued or executing tool state', () {
    final receipt = _item('receipt', 'running');
    final history = [receipt, _item('completion', 'succeeded')];
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
