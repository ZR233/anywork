import 'dart:convert';

import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_models.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_history_projection.dart';
import 'package:anywork_client/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

HistoryEventRecord _event(int seq, Map<String, Object?> envelope) =>
    HistoryEventRecord(
      seq: seq,
      eventId: 'event-$seq',
      kind: 'text_completed',
      timelineRole: HistoryTimelineRole.boundary,
      recordedAt: 1000,
      payloadSchema: 'anywork.event/1',
      payloadJson: jsonEncode(envelope),
    );

Map<String, Object?> _textEnvelope(String text) => {
  'contract': 'anywork.event/1',
  'type': 'text',
  'meta': <String, Object?>{'entityId': 'entity-$text', 'contentPresent': true},
  'data': {'channel': 'final'},
  'bodies': [
    {'key': 'body', 'byteLength': utf8.encode(text).length, 'inlineText': text},
  ],
};

void main() {
  for (final sample in <({bool inMeta, String key, Object value})>[
    (inMeta: true, key: 'contentPresent', value: 'yes'),
    (inMeta: true, key: 'startedAt', value: 'yesterday'),
    (inMeta: true, key: 'finishedAt', value: <Object>[]),
    (inMeta: true, key: 'entityId', value: 17),
    (inMeta: true, key: 'sourceOrder', value: 'first'),
    (inMeta: false, key: 'capturedAt', value: false),
    (inMeta: false, key: 'sourceOrder', value: <String, Object?>{}),
    (inMeta: false, key: 'turnId', value: 42),
  ]) {
    final field = '${sample.inMeta ? 'meta.' : ''}${sample.key}';
    test(
      'invalid $field falls back in its own row and preserves the next row',
      () {
        final envelope = _textEnvelope('damaged');
        final target = sample.inMeta
            ? envelope['meta']! as Map<String, Object?>
            : envelope;
        target[sample.key] = sample.value;
        final damaged = _event(1, envelope);
        final normal = _event(2, _textEnvelope('正常后续行'));

        final blocks = TimelineHistoryProjection.blocksFromEntries([
          HistoryTimelineEntry(event: damaged, hasFoldedAfter: false),
          HistoryTimelineEntry(event: normal, hasFoldedAfter: false),
        ], cut: const HistoryCut('fixed-cut'));

        expect(blocks.map((block) => block.id), [
          'boundary:event-1',
          'boundary:event-2',
        ]);
        final damagedRecord = (blocks.first.body as SingleDisplayBlock).record;
        final fallback = ChatItemPresentation.forRecord(
          damagedRecord,
          id: blocks.first.id,
        );
        expect(fallback.compatibility, ChatItemCompatibility.malformed);
        expect(fallback.raw, damaged.payloadJson);
        expect(fallback.diagnostic, contains(field));
        expect(damagedRecord.historyDetailEventId, damaged.eventId);
        final normalRecord = (blocks.last.body as SingleDisplayBlock).record;
        final following = ChatItemPresentation.forRecord(
          normalRecord,
          id: blocks.last.id,
        );
        expect(following.compatibility, ChatItemCompatibility.current);
        expect(following.inlineText('body'), '正常后续行');
        expect(normalRecord.atom.id, 'entity-正常后续行');
      },
    );
  }

  test('valid metadata retains its identity, order, and timing', () {
    final envelope = _textEnvelope('valid')
      ..['sourceOrder'] = null
      ..['capturedAt'] = null
      ..['turnId'] = 'turn-1';
    envelope['meta'] = {
      'entityId': 'original-entity',
      'contentPresent': true,
      'sourceOrder': 4,
      'startedAt': 1000,
      'finishedAt': 2000,
    };
    final record = TimelineHistoryProjection.recordFromEvent(
      _event(1, envelope),
    );
    expect(
      record.predecodedPresentation!.compatibility,
      ChatItemCompatibility.current,
    );
    expect(record.atom.id, 'original-entity');
    expect(record.atom.sourceOrder, 4);
    expect(record.atom.turnId, 'turn-1');
    expect(record.atom.startedAt, 1);
    expect(record.atom.finishedAt, 2);
  });

  test('a missing event identity still fails continuity', () {
    expect(
      () => TimelineHistoryProjection.directBlock(
        const HistoryEventRecord(
          seq: 1,
          eventId: '',
          kind: 'text_completed',
          timelineRole: HistoryTimelineRole.boundary,
          recordedAt: 1000,
          payloadSchema: 'anywork.event/1',
          payloadJson: '{}',
        ),
      ),
      throwsA(isA<ConversationContinuityError>()),
    );
  });
}
