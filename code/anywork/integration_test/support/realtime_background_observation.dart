import 'display_record_observation.dart';
import 'timeline_observation.dart';

import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ObservedDisplayRecord?> realtimeBackgroundRecord(
  TimelineObservation observed, {
  required String turnId,
  required String callId,
}) async {
  final records = await collectDisplayRecords(observed, turnId: turnId);
  final matches = records
      .where(
        (entry) =>
            entry.record.atom.source is BackgroundResultChatSource &&
            entry.record.atom.tool?.callId == callId &&
            entry.record.contentSource is CompletedOriginal,
      )
      .toList();
  expect(
    matches.length,
    lessThanOrEqualTo(1),
    reason: 'Each exact call has one completed independent background result',
  );
  if (matches.isEmpty) return null;
  final entry = matches.single;
  final atom = entry.record.atom;
  expect((atom.source as BackgroundResultChatSource).messageId, isNotEmpty);
  expect(atom.kind, ChatAtomKind.toolCall);
  expect(atom.tool!.name, 'exec');
  expect(atom.delivery, ChatDeliveryKind.independent);
  expect(
    (atom.lifecycle as TerminalChatAtom).outcome,
    ChatTerminalOutcome.completed,
  );
  expect(atom.completionItemId, completedOriginalId(entry.record));
  expect(atom.completionSeq, greaterThan(0));
  return entry;
}

// Inspect loaded Main heads only. No member query, history paging or envelope
// decoding is needed to locate the producer's independent Single result.
TimelineDisplayUnit? realtimeBackgroundSingle(
  Iterable<TimelineDisplayUnit> main, {
  required String turnId,
  required String callId,
}) {
  final matches = main
      .where(
        (unit) =>
            unit.body is SingleDisplayBlock &&
            unit.atom!.source is BackgroundResultChatSource &&
            unit.atom!.turnId == turnId &&
            unit.atom!.tool?.callId == callId,
      )
      .toList();
  expect(
    matches.length,
    lessThanOrEqualTo(1),
    reason: 'Each exact call has one independent background Single',
  );
  if (matches.isEmpty) return null;
  final block = matches.single;
  final body = block.body as SingleDisplayBlock;
  final atom = body.record.atom;
  expect(block.blockOrder, greaterThan(0));
  expect(block.memberReference, isNull);
  expect((atom.source as BackgroundResultChatSource).messageId, isNotEmpty);
  expect(atom.id, isNotEmpty);
  expect(atom.kind, ChatAtomKind.toolCall);
  expect(atom.tool!.name, 'exec');
  expect(atom.delivery, ChatDeliveryKind.independent);
  expect(atom.lifecycle, isA<TerminalChatAtom>());
  expect(
    (atom.lifecycle as TerminalChatAtom).outcome,
    ChatTerminalOutcome.completed,
  );
  expect(completedOriginalId(body.record), isNotNull);
  expect(completedOriginalId(body.record), isNotEmpty);
  expect(atom.completionItemId, completedOriginalId(body.record));
  expect(atom.completionSeq, greaterThan(0));
  return block;
}
