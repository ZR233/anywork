import 'package:anywork_client/conversation_encoding.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter_test/flutter_test.dart';

void expectImageOriginalOutcome(ChatAtom atom, {required bool failed}) {
  expect(atom.lifecycle, isA<TerminalChatAtom>());
  expect(
    (atom.lifecycle as TerminalChatAtom).outcome,
    failed ? ChatTerminalOutcome.failed : ChatTerminalOutcome.completed,
    reason: 'The actual final original must agree with the image result',
  );
}

Map<String, Object?> displayRecordEvidence(DisplayRecord record) {
  // sourceState describes the current query cut, not frozen atom metadata.
  // All other public fields, including concrete lifecycle, times and payload,
  // use the SDK's canonical encoding rather than a second metadata schema.
  final atom = chatAtomToJson(record.atom)..remove('sourceState');
  return {
    'atom': atom,
    'start': chatFactPositionToJson(record.startFact),
    'end': chatFactPositionToJson(record.endFact),
    'contentSource': switch (record.contentSource) {
      CurrentAtom() => {'kind': 'currentAtom'},
      FrozenObservation(:final capturedAt, :final available) => {
        'kind': 'frozenObservation',
        'capturedAt': capturedAt,
        'available': available,
      },
      CompletedOriginal(:final completionId) => {
        'kind': 'completedOriginal',
        'completionId': completionId,
      },
    },
  };
}

Map<String, Object?> workTimingEvidence(WorkTiming timing) => {
  'startedAt': timing.startedAt,
  'finishedAt': timing.finishedAt,
};
