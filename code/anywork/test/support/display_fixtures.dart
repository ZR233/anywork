import 'package:anywork_client/models.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_message_controller.dart';

import 'chat_fixtures.dart';

WorkTiming displayTiming() => const WorkTiming(startedAt: 0, finishedAt: 1);

DisplayBlock displayWork(String id, int pos) => DisplayBlock(
  id: id,
  blockOrder: pos,
  body: WorkDisplayBlock(
    timing: displayTiming(),
    members: DisplayBlockRef(
      blockId: id,
      cut: HistoryCut('fixture:$id'),
      anchorSeq: pos,
      headSeq: pos,
    ),
    executionPresent: false,
    memberCount: 0,
    unfinishedCount: 0,
    groupClosed: true,
  ),
);

DisplayBlock displaySingle(FixtureCompletion entry, {int? blockOrder}) =>
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
    this.throughOrder = 0,
    this.from,
    this.before,
  });

  final List<DisplayBlock> blocks;
  final TimelineApplyPlacement placement;
  final int throughOrder;
  final int? from;
  final String? before;
}

TimelineFixtureBatch displayBatch(
  List<DisplayBlock> blocks, {
  TimelineApplyPlacement placement = TimelineApplyPlacement.set,
  int? through,
  int? from,
  String? before,
}) => TimelineFixtureBatch(
  blocks: blocks,
  placement: placement,
  throughOrder: through ?? (blocks.isEmpty ? 0 : blocks.last.blockOrder),
  from: from,
  before: before,
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
  HistoryCut? cut,
}) => HistoryTimelinePage(
  cut: cut ?? HistoryCut('$databaseId:${update.throughOrder}'),
  entries: [
    // History pages are newest-first; the display owner reverses them into
    // producer block order when it admits the page.
    for (final block in update.blocks.reversed)
      HistoryTimelineEntry(
        rowKey: block.id,
        anchorSeq: block.blockOrder,
        headSeq: block.blockOrder,
        head: switch (block.body) {
          WorkDisplayBlock(:final members) => WorkHistoryRow(
            HistoryWorkHead(
              groupId: members.blockId,
              startedAt: 0,
              boundaryAt: 1,
              closed: true,
              memberCount: 0,
              unfinishedCount: 0,
              executionPresent: false,
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
