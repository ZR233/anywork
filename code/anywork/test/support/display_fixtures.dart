import 'package:anywork_client/models.dart';

WorkTiming displayTiming() => WorkTiming(startedAt: 0, finishedAt: null);

DisplayBlock displayWork(String id, int pos) => DisplayBlock(
  id: id,
  blockOrder: pos,
  body: WorkDisplayBlock(
    timing: const WorkTiming(startedAt: 0, finishedAt: 1),
    members: DisplayBlockRef(databaseId: 'db', blockId: id),
  ),
);

DisplayBlock displaySingle(CompletedEntry entry, {int? blockOrder}) =>
    DisplayBlock(
      id: entry.recordId,
      blockOrder: blockOrder ?? entry.completionSeq,
      body: SingleDisplayBlock(
        visibility: SingleVisibility.content,
        record: DisplayRecord(
          atom: entry.atom,
          contentSource: CompletedOriginal(completionId: entry.recordId),
        ),
      ),
    );

TimelineBatch displayBatch(
  List<DisplayBlock> blocks, {
  ChatPlacement placement = ChatPlacement.set,
  int? from,
  int? through,
  String? before,
  LiveDisplayWindow? live,
}) => TimelineBatch(
  presentationVersion: presentationVersion,
  placement: placement,
  blocks: blocks,
  fromOrder: from,
  throughOrder: through ?? (blocks.isEmpty ? from ?? 0 : blocks.last.blockOrder),
  before: before,
  live: live,
);
