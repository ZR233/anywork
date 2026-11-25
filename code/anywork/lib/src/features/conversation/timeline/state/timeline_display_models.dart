import 'dart:async';

import 'package:anywork_client/models.dart';

import 'chat_item_presentation.dart';

const presentationVersion = 6;

final class DisplayBlockRef {
  const DisplayBlockRef({
    required this.blockId,
    required this.cut,
    required this.anchorSeq,
    required this.headSeq,
    this.afterSeq,
    this.beforeSeq,
    this.runId,
  });
  final String blockId;

  /// Fixed immutable-history cut. The token is signed by and valid only for
  /// its original History reader/database scope.
  final HistoryCut cut;
  final int anchorSeq;
  final int headSeq;
  final int? afterSeq;
  final int? beforeSeq;
  final String? runId;

  @override
  bool operator ==(Object other) =>
      other is DisplayBlockRef &&
      blockId == other.blockId &&
      cut == other.cut &&
      anchorSeq == other.anchorSeq &&
      headSeq == other.headSeq &&
      afterSeq == other.afterSeq &&
      beforeSeq == other.beforeSeq &&
      runId == other.runId;
  @override
  int get hashCode =>
      Object.hash(blockId, cut, anchorSeq, headSeq, afterSeq, beforeSeq, runId);
}

/// Wall-clock interval owned by the Work block, in Unix milliseconds.
final class WorkTiming {
  const WorkTiming({required this.startedAtMillis, this.finishedAtMillis});
  final int? startedAtMillis;
  final int? finishedAtMillis;
}

sealed class DisplayBlockBody {
  const DisplayBlockBody();
}

final class WorkDisplayBlock extends DisplayBlockBody {
  const WorkDisplayBlock({
    required this.timing,
    required this.members,
    required this.executionPresent,
    required this.memberCount,
    required this.unfinishedCount,
    required this.groupClosed,
    this.summary,
  });
  final WorkTiming timing;
  final DisplayBlockRef members;
  final bool executionPresent;
  final int memberCount;
  final int unfinishedCount;
  final bool groupClosed;
  final String? summary;
}

final class SingleDisplayBlock extends DisplayBlockBody {
  const SingleDisplayBlock({required this.record, required this.visibility});
  final DisplayRecord record;
  final HistorySingleVisibility visibility;
}

final class DisplayRecord {
  const DisplayRecord({
    required this.atom,
    required this.contentSource,
    this.startFact,
    this.endFact,
    this.historyEventId,
    this.historyDetailEventId,
    this.runId,
    this.isTerminalHistory = false,
    this.isFrozenHistory = false,
    this.callId,
    this.predecodedPresentation,
    this.immutableRecord,
    this.currentContents = const [],
  });
  final ChatAtom atom;
  final ChatFactPosition? startFact;
  final ChatFactPosition? endFact;
  final DisplayContentSource contentSource;

  /// Canonical event whose immutable body/manifest owns this historical row.
  final String? historyEventId;
  final String? historyDetailEventId;
  final String? runId;
  final bool isTerminalHistory;
  final bool isFrozenHistory;
  final String? callId;
  final ChatItemPresentation? predecodedPresentation;

  /// The bounded row head retained while Current owns the same entity.
  final DisplayRecord? immutableRecord;

  /// Current-owner body references, never reinterpreted as historical identity.
  final List<CurrentAtomContent> currentContents;
}

sealed class DisplayContentSource {
  const DisplayContentSource();
}

final class CurrentAtomSource extends DisplayContentSource {
  const CurrentAtomSource();
}

final class FrozenObservation extends DisplayContentSource {
  const FrozenObservation({this.capturedAt, required this.available});

  /// The original History boundary timestamp in Unix milliseconds.
  final int? capturedAt;
  final bool available;
}

final class CompletedOriginal extends DisplayContentSource {
  const CompletedOriginal({required this.completionId});
  final String completionId;
}

enum DisplayBlockState { open, sealed }

final class DisplayBlock {
  const DisplayBlock({
    required this.id,
    required this.blockOrder,
    required this.body,
  });
  final String id;
  final int blockOrder;
  final DisplayBlockBody body;
}

bool sameDisplayBlock(DisplayBlock first, DisplayBlock second) =>
    first.id == second.id &&
    first.blockOrder == second.blockOrder &&
    sameDisplayBlockBody(first.body, second.body);

/// Checks whether [existing] in the immutable main Timeline already represents
/// the exact same historical entry or sealed Work interval as [incoming].
///
/// Sealed History Work blocks keep their original `cut` and identity once
/// admitted so advancing `HistoryCut` or adding trailing `divider`s never
/// triggers in-place message replacement or resets expanded Work groups.
bool sameImmutableTimelineBlock(DisplayBlock existing, DisplayBlock incoming) {
  if (sameDisplayBlock(existing, incoming)) return true;
  if (existing.id != incoming.id ||
      existing.blockOrder != incoming.blockOrder) {
    return false;
  }
  final a = existing.body;
  final b = incoming.body;
  if (a is! WorkDisplayBlock || b is! WorkDisplayBlock) return false;
  return a.groupClosed &&
      b.groupClosed &&
      !a.executionPresent &&
      !b.executionPresent &&
      a.unfinishedCount == b.unfinishedCount &&
      a.memberCount == b.memberCount &&
      a.summary == b.summary &&
      a.timing.startedAtMillis == b.timing.startedAtMillis &&
      a.timing.finishedAtMillis == b.timing.finishedAtMillis &&
      a.members.blockId == b.members.blockId &&
      a.members.anchorSeq == b.members.anchorSeq &&
      a.members.headSeq == b.members.headSeq &&
      a.members.afterSeq == b.members.afterSeq &&
      a.members.runId == b.members.runId &&
      (a.members.beforeSeq == b.members.beforeSeq ||
          a.members.beforeSeq == null);
}

bool sameDisplayBlockBody(DisplayBlockBody first, DisplayBlockBody second) {
  if (first is WorkDisplayBlock && second is WorkDisplayBlock) {
    return first.members == second.members &&
        first.timing.startedAtMillis == second.timing.startedAtMillis &&
        first.timing.finishedAtMillis == second.timing.finishedAtMillis &&
        first.executionPresent == second.executionPresent &&
        first.memberCount == second.memberCount &&
        first.unfinishedCount == second.unfinishedCount &&
        first.groupClosed == second.groupClosed &&
        first.summary == second.summary;
  }
  if (first is! SingleDisplayBlock || second is! SingleDisplayBlock) {
    return false;
  }
  return first.visibility == second.visibility &&
      sameDisplayRecord(first.record, second.record);
}

bool sameDisplayRecord(DisplayRecord first, DisplayRecord second) {
  final a = first.atom;
  final b = second.atom;
  return a.id == b.id &&
      a.source == b.source &&
      a.sourceState == b.sourceState &&
      a.sourceOrder == b.sourceOrder &&
      a.kind == b.kind &&
      a.delivery == b.delivery &&
      _sameLifecycle(a.lifecycle, b.lifecycle) &&
      a.turnId == b.turnId &&
      a.attemptId == b.attemptId &&
      _sameTool(a.tool, b.tool) &&
      a.wait == b.wait &&
      a.textChannel == b.textChannel &&
      a.contentPresent == b.contentPresent &&
      a.startedAt == b.startedAt &&
      a.finishedAt == b.finishedAt &&
      first.startFact == second.startFact &&
      first.endFact == second.endFact &&
      first.historyEventId == second.historyEventId &&
      first.historyDetailEventId == second.historyDetailEventId &&
      first.runId == second.runId &&
      first.isTerminalHistory == second.isTerminalHistory &&
      first.isFrozenHistory == second.isFrozenHistory &&
      first.callId == second.callId &&
      first.predecodedPresentation?.raw == second.predecodedPresentation?.raw &&
      first.predecodedPresentation?.compatibility ==
          second.predecodedPresentation?.compatibility &&
      _sameOptionalRecord(first.immutableRecord, second.immutableRecord) &&
      _sameContentSource(first.contentSource, second.contentSource) &&
      _sameCurrentContents(first.currentContents, second.currentContents);
}

bool _sameOptionalRecord(DisplayRecord? first, DisplayRecord? second) =>
    first == null && second == null ||
    first != null && second != null && sameDisplayRecord(first, second);

bool _sameLifecycle(ChatAtomLifecycle first, ChatAtomLifecycle second) =>
    switch ((first, second)) {
      (
        ActiveChatAtom(:final started, :final status),
        ActiveChatAtom(started: final otherStarted, status: final otherStatus),
      ) =>
        started == otherStarted && status == otherStatus,
      (
        TerminalChatAtom(:final started, :final ended, :final outcome),
        TerminalChatAtom(
          started: final otherStarted,
          ended: final otherEnded,
          outcome: final otherOutcome,
        ),
      ) =>
        started == otherStarted &&
            ended == otherEnded &&
            outcome == otherOutcome,
      _ => false,
    };

bool _sameTool(ChatToolIdentity? first, ChatToolIdentity? second) =>
    first == null && second == null ||
    first != null &&
        second != null &&
        first.callId == second.callId &&
        first.name == second.name;

bool _sameContentSource(
  DisplayContentSource first,
  DisplayContentSource second,
) => switch ((first, second)) {
  (CurrentAtomSource(), CurrentAtomSource()) => true,
  (
    FrozenObservation(:final capturedAt, :final available),
    FrozenObservation(capturedAt: final otherAt, available: final other),
  ) =>
    capturedAt == otherAt && available == other,
  (
    CompletedOriginal(:final completionId),
    CompletedOriginal(completionId: final other),
  ) =>
    completionId == other,
  _ => false,
};

bool _sameCurrentContents(
  List<CurrentAtomContent> first,
  List<CurrentAtomContent> second,
) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (first[index].role != second[index].role ||
        first[index].reference != second[index].reference) {
      return false;
    }
  }
  return true;
}

final class DisplayMemberHead {
  const DisplayMemberHead({
    required this.memberKey,
    required this.memberOrder,
    required this.record,
  });
  final String memberKey;
  final int memberOrder;
  final DisplayRecord record;
}

/// One bounded transport batch of a complete group at its original History cut.
final class DisplayMemberBatch {
  DisplayMemberBatch({
    required this.block,
    required this.offset,
    required this.complete,
    required List<DisplayMemberHead> entries,
  }) : entries = List.unmodifiable(entries);
  final DisplayBlockRef block;
  final int offset;
  final bool complete;
  final List<DisplayMemberHead> entries;
}

abstract interface class DisplayMembers {
  Future<DisplayMemberBatch?> next();
  void requestClose();
  Future<void> close();
}

final class CurrentAtomSnapshot {
  CurrentAtomSnapshot({
    required this.revision,
    List<CurrentAtom> currentAtoms = const [],
    this.ownerId,
    this.executionPresent = false,
    this.executionActive = false,
    this.modelRecovery,
  }) : currentAtoms = List.unmodifiable(currentAtoms);
  final int revision;
  final String? ownerId;
  final bool executionPresent;
  final bool executionActive;
  final CurrentModelRecovery? modelRecovery;

  /// The bounded Current run facts rendered inside LiveStatusBar and open live Work.
  /// They are never overlaid onto immutable main-Timeline rows.
  final List<CurrentAtom> currentAtoms;
}
