import 'chat_models.dart';

const presentationVersion = 6;

final class DisplayBlockRef {
  const DisplayBlockRef({required this.databaseId, required this.blockId});
  final String databaseId;
  final String blockId;

  @override
  bool operator ==(Object other) =>
      other is DisplayBlockRef &&
      databaseId == other.databaseId &&
      blockId == other.blockId;
  @override
  int get hashCode => Object.hash(databaseId, blockId);
}

/// Wall-clock interval owned by the Work block, in Unix seconds.
final class WorkTiming {
  const WorkTiming({required this.startedAt, this.finishedAt});
  final int? startedAt;
  final int? finishedAt;
}

sealed class DisplayBlockBody {
  const DisplayBlockBody();
}

final class WorkDisplayBlock extends DisplayBlockBody {
  const WorkDisplayBlock({required this.timing, required this.members});
  final WorkTiming timing;
  final DisplayBlockRef members;
}

final class SingleDisplayBlock extends DisplayBlockBody {
  const SingleDisplayBlock({required this.record, required this.visibility});
  final DisplayRecord record;
  final SingleVisibility visibility;
}

enum SingleVisibility { content, finalEmptyAfterContent }

final class DisplayRecord {
  const DisplayRecord({
    required this.atom,
    required this.contentSource,
    this.startFact,
    this.endFact,
  });
  final ChatAtom atom;
  final ChatFactPosition? startFact;
  final ChatFactPosition? endFact;
  final DisplayContentSource contentSource;
}

sealed class DisplayContentSource {
  const DisplayContentSource();
}

final class CurrentAtom extends DisplayContentSource {
  const CurrentAtom();
}

final class FrozenObservation extends DisplayContentSource {
  const FrozenObservation({this.capturedAt, required this.available});
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

final class LiveDisplayBlock {
  const LiveDisplayBlock({
    required this.id,
    required this.blockOrder,
    required this.body,
    required this.state,
    this.source,
    this.hasUnfinishedMembers = false,
    this.thinkingSummary,
  });
  final String id;
  final int blockOrder;
  final DisplayBlockBody body;
  final DisplayBlockState state;
  final ChatSourceId? source;
  final bool hasUnfinishedMembers;
  final String? thinkingSummary;
}

sealed class DisplayMemberWindow {
  const DisplayMemberWindow();
}

final class LatestDisplayMembers extends DisplayMemberWindow {
  const LatestDisplayMembers();
}

final class BeforeDisplayMembers extends DisplayMemberWindow {
  const BeforeDisplayMembers({required this.memberOrder});
  final int memberOrder;
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

final class DisplayMemberPage {
  DisplayMemberPage({
    required this.block,
    required this.revision,
    required this.sealed,
    required List<DisplayMemberHead> entries,
    this.before,
  }) : entries = List.unmodifiable(entries);
  final DisplayBlockRef block;
  final int revision;
  final bool sealed;
  final List<DisplayMemberHead> entries;
  final int? before;
}

const timelineReaderProtocolVersion = 1;

final class ViewCursor {
  const ViewCursor(this.value);
  final String value;
  @override
  bool operator ==(Object other) => other is ViewCursor && value == other.value;
  @override
  int get hashCode => value.hashCode;
}

final class OpenTimeline {
  const OpenTimeline({
    required this.readerId,
    required this.presentationVersion,
    required this.readerProtocolVersion,
    required this.initialCursor,
  });
  final String readerId;
  final int presentationVersion;
  final int readerProtocolVersion;
  final ViewCursor initialCursor;
}

enum HistoryPlacement { set, append }

final class HistoryDelta {
  HistoryDelta({
    required this.placement,
    this.fromOrder,
    required this.throughOrder,
    required List<DisplayBlock> blocks,
    this.before,
  }) : blocks = List.unmodifiable(blocks);
  final HistoryPlacement placement;
  final int? fromOrder;
  final int throughOrder;
  final List<DisplayBlock> blocks;
  final String? before;
}

final class TailSnapshot {
  TailSnapshot({
    required this.revision,
    required this.layoutRevision,
    required this.readyFrontier,
    required this.executionPresent,
    required this.currentWorkId,
    required List<LiveDisplayBlock> blocks,
    this.older,
  }) : blocks = List.unmodifiable(blocks);
  final int revision;
  final int layoutRevision;
  final int readyFrontier;
  final bool executionPresent;
  final String? currentWorkId;
  final List<LiveDisplayBlock> blocks;
  final String? older;
}

sealed class TailUpdate {
  const TailUpdate();
}

final class KeepTail extends TailUpdate {
  const KeepTail();
}

final class ReplaceTail extends TailUpdate {
  const ReplaceTail({required this.snapshot});
  final TailSnapshot snapshot;
}

final class TailStatus extends TailUpdate {
  const TailStatus({
    required this.baseLayoutRevision,
    required this.revision,
    required this.currentWorkId,
    required this.thinkingSummary,
  });
  final int baseLayoutRevision;
  final int revision;
  final String? currentWorkId;
  final String? thinkingSummary;
}

final class ViewUpdate {
  const ViewUpdate({
    required this.presentationVersion,
    required this.readerProtocolVersion,
    required this.after,
    required this.next,
    required this.history,
    required this.tail,
  });
  final int presentationVersion;
  final int readerProtocolVersion;
  final ViewCursor after;
  final ViewCursor next;
  final HistoryDelta history;
  final TailUpdate tail;
}

final class TimelinePage {
  TimelinePage({
    required this.presentationVersion,
    required this.databaseId,
    required this.ceiling,
    required List<DisplayBlock> blocks,
    this.before,
  }) : blocks = List.unmodifiable(blocks);
  final int presentationVersion;
  final String databaseId;
  final int ceiling;
  final List<DisplayBlock> blocks;
  final String? before;
}
