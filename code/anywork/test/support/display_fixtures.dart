import 'package:anywork_client/models.dart';

WorkTiming displayTiming() => WorkTiming(startedAt: 0, finishedAt: null);

DisplayBlock displayWork(String id, int pos) => DisplayBlock(
  id: id,
  historyPos: pos,
  body: WorkDisplayBlock(
    timing: const WorkTiming(startedAt: 0, finishedAt: 1),
    members: DisplayBlockRef(databaseId: 'db', blockId: id),
  ),
);

DisplayBlock displaySingle(CompletedEntry entry, {int? historyPos}) =>
    DisplayBlock(
      id: entry.recordId,
      historyPos: historyPos ?? entry.completionSeq,
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
  fromPos: from,
  throughPos: through ?? (blocks.isEmpty ? from ?? 0 : blocks.last.historyPos),
  before: before,
  live: live,
);
