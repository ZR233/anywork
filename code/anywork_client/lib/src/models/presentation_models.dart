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

final class LiveDisplayWindow {
  LiveDisplayWindow({
    required this.revision,
    required this.readyFrontier,
    required this.executionPresent,
    required this.currentWorkId,
    required List<LiveDisplayBlock> blocks,
    this.older,
  }) : blocks = List.unmodifiable(blocks);
  final int revision;
  final int readyFrontier;
  final bool executionPresent;
  final String? currentWorkId;
  final List<LiveDisplayBlock> blocks;
  final String? older;
}

final class TimelineBatch {
  TimelineBatch({
    required this.presentationVersion,
    required this.placement,
    required List<DisplayBlock> blocks,
    this.before,
    this.fromOrder,
    required this.throughOrder,
    this.live,
  }) : blocks = List.unmodifiable(blocks);
  final int presentationVersion;
  final ChatPlacement placement;
  final List<DisplayBlock> blocks;
  final String? before;
  final int? fromOrder;
  final int throughOrder;
  final LiveDisplayWindow? live;
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
