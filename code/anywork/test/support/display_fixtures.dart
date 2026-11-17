import 'package:anywork_client/models.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_message_controller.dart';

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
        visibility: HistorySingleVisibility.content,
        record: DisplayRecord(
          atom: entry.atom,
          contentSource: CompletedOriginal(completionId: entry.recordId),
        ),
      ),
    );

final class TimelineFixtureBatch {
  TimelineFixtureBatch({
    required this.blocks,
    required this.placement,
    this.fromOrder,
    required this.throughOrder,
    this.before,
    this.live,
  });
  final List<DisplayBlock> blocks;
  final TimelineApplyPlacement placement;
  final int? fromOrder;
  final int throughOrder;
  final String? before;
  final CurrentRunSnapshot? live;
}

TimelineFixtureBatch displayBatch(
  List<DisplayBlock> blocks, {
  TimelineApplyPlacement placement = TimelineApplyPlacement.set,
  int? from,
  int? through,
  String? before,
  CurrentRunSnapshot? live,
}) => TimelineFixtureBatch(
  blocks: blocks,
  placement: placement,
  fromOrder: from,
  throughOrder:
      through ?? (blocks.isEmpty ? from ?? 0 : blocks.last.blockOrder),
  before: before,
  live: live,
);

extension ApplyComponentFixture on TimelineMessageController {
  Future<void> applyFixtureUpdate(
    TimelineFixtureBatch update, {
    TimelineApplyPlacement? placement,
  }) => applyBlocks(update.blocks, placement ?? update.placement);
}

HistoryTimelinePage historyFixturePage(
  TimelineFixtureBatch update, {
  String databaseId = 'db',
}) => HistoryTimelinePage(
  cut: HistoryCut('$databaseId:${update.throughOrder}'),
  entries: [
    for (final block in update.blocks)
      HistoryTimelineEntry(
        rowKey: block.id,
        anchorSeq: block.blockOrder,
        headSeq: block.blockOrder,
        head: switch (block.body) {
          WorkDisplayBlock(:final members) => WorkHistoryRow(
            HistoryWorkHead(
              groupId: members.blockId,
              runId: null,
              startedAt: 0,
              boundaryAt: 1,
              closed: true,
              memberCount: 0,
              unfinishedCount: 0,
              executionPresent: false,
              summary: null,
            ),
          ),
          SingleDisplayBlock(:final record, :final visibility) =>
            SingleHistoryRow(
              HistoryEntityHead(
                entityId: record.atom.id,
                runId: record.runId,
                attemptId: record.atom.attemptId,
                source: record.atom.source,
                kind: record.atom.kind,
                delivery: record.atom.delivery,
                state: switch (record.atom.lifecycle) {
                  ActiveChatAtom(:final status) => HistoryEntityState(
                    kind: HistoryEntityStateKind.knownActive,
                    activeStatus: status,
                  ),
                  TerminalChatAtom(:final outcome) => HistoryEntityState(
                    kind: HistoryEntityStateKind.knownTerminal,
                    outcome: outcome,
                  ),
                },
                startedAt: record.atom.startedAt,
                finishedAt: record.atom.finishedAt,
                textChannel: record.atom.textChannel,
                tool: record.atom.tool,
                contentPresent: record.atom.contentPresent,
                singleVisibility: visibility,
                observation: const HistoryObservation(
                  kind: HistoryObservationKind.original,
                ),
                detailEventId: record.historyDetailEventId,
                bodyManifestEventId: record.historyEventId,
              ),
            ),
        },
      ),
  ],
  next: update.before,
);
