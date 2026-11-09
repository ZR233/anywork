import 'chat_models.dart';

const presentationVersion = 1;

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

final class WorkSummary {
  const WorkSummary({
    required this.total,
    required this.terminal,
    required this.running,
    required this.waiting,
    required this.failed,
    required this.cancelled,
    required this.transferred,
    this.startedAt,
    this.finishedAt,
    this.durationMs,
    this.thinkingSummary,
    this.thinkingContent,
  });
  final int total;
  final int terminal;
  final int running;
  final int waiting;
  final int failed;
  final int cancelled;
  final int transferred;
  final int? startedAt;
  final int? finishedAt;
  final int? durationMs;
  final String? thinkingSummary;
  final ContentRef? thinkingContent;
}

sealed class DisplayBlockBody {
  const DisplayBlockBody();
}

final class WorkDisplayBlock extends DisplayBlockBody {
  const WorkDisplayBlock({required this.summary, required this.members});
  final WorkSummary summary;
  final DisplayBlockRef members;
}

final class SingleDisplayBlock extends DisplayBlockBody {
  const SingleDisplayBlock({required this.atom, this.completionId});
  final ChatAtom atom;
  final String? completionId;
}

final class DisplayBlock {
  const DisplayBlock({
    required this.id,
    required this.historyPos,
    required this.body,
  });
  final String id;
  final int historyPos;
  final DisplayBlockBody body;
}

final class LiveDisplayBlock {
  const LiveDisplayBlock({
    required this.id,
    required this.blockOrder,
    required this.body,
    required this.closing,
  });
  final String id;
  final int blockOrder;
  final DisplayBlockBody body;
  final bool closing;
}

final class LiveDisplayWindow {
  LiveDisplayWindow({
    required this.revision,
    required this.historyThrough,
    required this.executionPresent,
    required List<LiveDisplayBlock> blocks,
    this.older,
  }) : blocks = List.unmodifiable(blocks);
  final int revision;
  final int historyThrough;
  final bool executionPresent;
  final List<LiveDisplayBlock> blocks;
  final String? older;
}

final class TimelineBatch {
  TimelineBatch({
    required this.presentationVersion,
    required this.placement,
    required List<DisplayBlock> blocks,
    this.before,
    this.fromPos,
    required this.throughPos,
    this.live,
  }) : blocks = List.unmodifiable(blocks);
  final int presentationVersion;
  final ChatPlacement placement;
  final List<DisplayBlock> blocks;
  final String? before;
  final int? fromPos;
  final int throughPos;
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
    required this.atom,
    this.completionId,
  });
  final String memberKey;
  final int memberOrder;
  final ChatAtom atom;
  final String? completionId;
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
