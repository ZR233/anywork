import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dart:convert';

import 'timeline_observation.dart';

export 'display_record_expectations.dart';

typedef ObservedDisplayRecord = ({
  TimelineDisplayUnit unit,
  DisplayMemberHead? member,
  DisplayRecord record,
});

// Finite acceptance inventory through the original bounded member reader.
// A call can have a frozen start and a later end with different member keys.
Future<List<ObservedDisplayRecord>> collectDisplayRecords(
  TimelineObservation observed, {
  ChatSourceId? source,
  String? turnId,
}) async {
  final result = <ObservedDisplayRecord>[];
  final units = {
    for (final unit in [...observed.main, ...observed.liveWork]) unit.id: unit,
  };
  bool wanted(DisplayRecord record) =>
      (source == null || record.atom.source == source) &&
      (turnId == null || record.atom.turnId == turnId);
  for (final unit in units.values) {
    if (unit.body case SingleDisplayBlock(:final record)) {
      if (wanted(record)) {
        result.add((unit: unit, member: null, record: record));
      }
      continue;
    }
    DisplayMemberWindow window = const LatestDisplayMembers();
    int? before;
    final keys = <String>{};
    while (true) {
      final page = await observed.readMemberPage(
        unit.memberReference!,
        window: window,
        demand: const ReadDemand(maxItems: 12, maxBytes: 64 * 1024),
      );
      for (final member in page.entries) {
        expect(keys.add(member.memberKey), isTrue);
        if (wanted(member.record)) {
          result.add((unit: unit, member: member, record: member.record));
        }
      }
      final next = page.before;
      if (next == null) break;
      expect(page.entries, isNotEmpty);
      if (before != null) expect(next, lessThan(before));
      before = next;
      window = BeforeDisplayMembers(memberOrder: next);
    }
  }
  return result;
}

String? completedOriginalId(DisplayRecord record) =>
    switch (record.contentSource) {
      CompletedOriginal(:final completionId) => completionId,
      CurrentAtom() || FrozenObservation() => null,
    };

// The display record grants the read domain. Never resolve a frozen observation
// through the executing atom's latest payload or its eventual completion ID.
Future<ChatItemPresentation> readDisplayRecord(
  TimelineDisplayLease lease,
  DisplayRecord record, {
  String? displayId,
}) async {
  final scope = lease.openScope(generation: lease.generation);
  try {
    final source = record.contentSource;
    if (source is CompletedOriginal) {
      final original = await scope.readCompleted(
        recordId: source.completionId,
        demand: const ReadDemand(maxItems: 1, maxBytes: 64 * 1024),
      );
      expect(original.recordId, source.completionId);
      expect(original.atom.id, record.atom.id);
      expect(original.atom.source, record.atom.source);
      expect(original.completionSeq, record.atom.completionSeq);
      return ChatItemPresentation.decode(
        original.atom,
        record: record,
        displayId: displayId,
      );
    }
    final value = ChatItemPresentation.decode(
      record.atom,
      record: record,
      displayId: displayId,
    );
    if (source is FrozenObservation) expect(source.available, isTrue);
    if (value.compatibility != ChatItemCompatibility.deferred) {
      if (source is FrozenObservation) {
        expectFrozenObservationPayload(value);
      } else {
        expect(value.compatibility, ChatItemCompatibility.current);
      }
      return value;
    }
    final reference = value.reference!;
    if (source is FrozenObservation) {
      expect(reference.target, isA<BodyContentTarget>());
      expect(
        (reference.target as BodyContentTarget).owner,
        isA<DisplayObservationContentOwner>(),
      );
    }
    final window = await scope.readContent(
      reference: reference,
      range: const ContentRange(offset: 0, maxBytes: 64 * 1024),
    );
    expect(window.offset, 0);
    expect(window.bytes.length, window.availableThrough);
    if (source is FrozenObservation) expect(window.sealed, isTrue);
    final resolved = value.resolvePayload(InlinePayload(bytes: window.bytes));
    if (source is FrozenObservation) expectFrozenObservationPayload(resolved);
    return resolved;
  } finally {
    scope.retire();
    expect((await scope.close()).complete, isTrue);
  }
}

void expectFrozenObservationPayload(ChatItemPresentation value) {
  expect(
    value.compatibility,
    ChatItemCompatibility.current,
    reason:
        'Available FrozenObservation ${value.id} (atom ${value.atom?.id}) '
        'must decode a supported public payload; '
        'compatibility=${value.compatibility.name}, type=${value.type}, '
        'diagnostic=${value.diagnostic}',
  );
}

Future<List<String>> displayBodyTexts(
  TimelineDisplayLease lease,
  ChatItemPresentation item,
) async {
  final scope = lease.openScope(generation: lease.generation);
  try {
    final texts = <String>[];
    for (final body in item.bodies) {
      if (body.inline != null) {
        texts.add(utf8.decode(body.inline!));
      } else {
        expect(body.reference, isNotNull);
        final window = await scope.readContent(
          reference: body.reference!,
          range: const ContentRange(offset: 0, maxBytes: 64 * 1024),
        );
        if (item.displayRecord?.contentSource is! CurrentAtom) {
          expect(window.sealed, isTrue);
        }
        expect(window.offset, 0);
        expect(window.bytes.length, window.availableThrough);
        texts.add(utf8.decode(window.bytes));
      }
    }
    return texts;
  } finally {
    scope.retire();
    expect((await scope.close()).complete, isTrue);
  }
}
