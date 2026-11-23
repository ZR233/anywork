import 'dart:convert';

import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_models.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_history_projection.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_fixtures.dart';

// Completed activities are producer messages, no longer locally grouped typed
// atoms. Preserve the timestamp and standalone-receipt risks at the new decoder.
void main() {
  test('a frozen History member retains its millisecond boundary', () {
    const capturedAt = 1_785_000_006_250;
    final block = TimelineHistoryProjection.eventRecord(
      HistoryEventRecord(
        seq: 2,
        eventId: 'event:reasoning',
        kind: 'legacy_observed',
        timelineRole: HistoryTimelineRole.work,
        recordedAt: 2,
        entityId: 'reasoning',
        rowKey: 'member:reasoning',
        source: const ForegroundTurnChatSource(turnId: 'turn'),
        payloadSchema: 'anywork.event/1',
        payloadJson: jsonEncode({
          'contract': 'anywork.event/1',
          'type': 'thinking',
          'meta': {
            'entityId': 'reasoning',
            'entityKind': 'reasoning',
            'delivery': 'foreground',
            'state': {'kind': 'knownActive', 'status': 'running'},
            'startedAt': 1_785_000_000_000,
          },
          'data': <String, Object?>{},
          'bodies': <Object?>[],
          'capturedAt': capturedAt,
        }),
      ),
      cut: const HistoryCut('history-cut'),
    );
    final record = (block.body as SingleDisplayBlock).record;
    expect((record.contentSource as FrozenObservation).capturedAt, capturedAt);
    expect(record.displayStartedAt, 1_785_000_000);
    expect(record.displayObservedThrough, 1_785_000_006);
    expect(record.atom.finishedAt, isNull);
  });

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
  });
}
