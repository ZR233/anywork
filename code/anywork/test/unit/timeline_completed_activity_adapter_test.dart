import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_fixtures.dart';

// Completed activities are producer messages, no longer locally grouped typed
// atoms. Preserve the timestamp and standalone-receipt risks at the new decoder.
void main() {
  test(
    'unknown seal does not fabricate a message date from completion time',
    () {
      final item = ChatItemPresentation.decode(
        chatEnvelope(
          'completed',
          type: 'thinking',
          data: const {
            'outcome': {
              'kind': 'completed',
              'data': {'completedAt': 1700000000},
            },
          },
        ),
      );
      expect(item.compatibility, ChatItemCompatibility.current);
      expect(item.createdAt, isNull);
      expect(item.data['outcome'], {
        'kind': 'completed',
        'data': {'completedAt': 1700000000},
      });
    },
  );

  test(
    'only the explicit message seal creates a date, not an execution duration',
    () {
      final item = ChatItemPresentation.decode(
        chatEnvelope(
          'completed',
          type: 'thinking',
          sealedAt: 1700000001,
          data: const {
            'outcome': {
              'kind': 'completed',
              'data': {'completedAt': 1700000000},
            },
          },
        ),
      );
      expect(
        item.createdAt,
        DateTime.fromMillisecondsSinceEpoch(1700000001000, isUtc: true),
      );
      expect(item.data.containsKey('startedAt'), isFalse);
    },
  );

  test('background receipt remains its own producer item and exact frozen tool contract', () {
    final item = ChatItemPresentation.decode(
      chatEnvelope(
        'receipt',
        type: 'tool',
        data: const {
          'invocation': {
            'toolCallId': 'call',
            'name': 'exec',
            'taskId': 'task',
            'presentationContract': 'generic@1',
          },
          'state': {
            'kind': 'backgroundStarted',
            'data': {'startedAt': 1700000000},
          },
        },
      ),
    );
    expect(item.id, 'receipt');
    expect(item.type, 'tool');
    expect(item.presentationContract, 'generic@1');
    expect(item.data['state'], {
      'kind': 'backgroundStarted',
      'data': {'startedAt': 1700000000},
    });
    expect(item.createdAt, isNull);
    expect(item.childrenParentId, isNull);
  });
}
