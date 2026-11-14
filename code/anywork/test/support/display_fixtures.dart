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
        visibility: SingleVisibility.content,
        record: DisplayRecord(
          atom: entry.atom,
          contentSource: CompletedOriginal(completionId: entry.recordId),
        ),
      ),
    );

ViewUpdate displayBatch(
  List<DisplayBlock> blocks, {
  ChatPlacement placement = ChatPlacement.set,
  int? from,
  int? through,
  String? before,
  TailSnapshot? live,
}) => ViewUpdate(
  readerProtocolVersion: 1,
  after: const ViewCursor("fixture-C0"),
  next: const ViewCursor("fixture-C1"),
  history: HistoryDelta(
    placement: placement == ChatPlacement.set
        ? HistoryPlacement.set
        : HistoryPlacement.append,
    blocks: blocks,
    fromOrder: from,
    throughOrder:
        through ?? (blocks.isEmpty ? from ?? 0 : blocks.last.blockOrder),
    before: before,
  ),
  presentationVersion: presentationVersion,
  tail: live == null ? const KeepTail() : ReplaceTail(snapshot: live),
);

// Component fixtures supply already qualified blocks. Protocol admission is tested at TimelineSessionOwner.
extension FixtureUpdate on ViewUpdate {
  List<DisplayBlock> get blocks => history.blocks;
  int get throughOrder => history.throughOrder;
  int? get fromOrder => history.fromOrder;
  String? get before => history.before;
  TailSnapshot? get live => switch (tail) {
    ReplaceTail(:final snapshot) => snapshot,
    _ => null,
  };
  ChatPlacement get placement => history.placement == HistoryPlacement.set
      ? ChatPlacement.set
      : ChatPlacement.append;
}

extension ApplyComponentFixture on TimelineMessageController {
  Future<void> applyFixtureUpdate(
    ViewUpdate update, {
    ChatPlacement? placement,
  }) => applyBlocks(update.history.blocks, placement ?? update.placement);
}

TimelinePage historyFixturePage(
  ViewUpdate update, {
  String databaseId = 'db',
}) => TimelinePage(
  presentationVersion: update.presentationVersion,
  databaseId: databaseId,
  ceiling: update.history.throughOrder,
  blocks: update.history.blocks,
  before: update.history.before,
);
