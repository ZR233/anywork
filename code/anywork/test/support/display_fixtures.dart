import 'package:anywork_client/models.dart';

WorkSummary displaySummary(int total, {int? terminal, int running = 0}) =>
    WorkSummary(
      unavailable: 0,
      total: total,
      terminal: terminal ?? total,
      running: running,
      waiting: 0,
      failed: 0,
      cancelled: 0,
      transferred: 0,
      durationMs: 1250,
    );

DisplayBlock displayWork(String id, int pos, {int total = 3}) => DisplayBlock(
  id: id,
  historyPos: pos,
  body: WorkDisplayBlock(
    summary: displaySummary(total),
    members: DisplayBlockRef(databaseId: 'db', blockId: id),
  ),
);

DisplayBlock displaySingle(CompletedEntry entry, {int? historyPos}) =>
    DisplayBlock(
      id: entry.recordId,
      historyPos: historyPos ?? entry.completionSeq,
      body: SingleDisplayBlock(
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
