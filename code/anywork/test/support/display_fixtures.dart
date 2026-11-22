import 'dart:convert';

import 'package:anywork_client/models.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_message_controller.dart';

import 'chat_fixtures.dart';

WorkTiming displayTiming() =>
    const WorkTiming(startedAtMillis: 0, finishedAtMillis: 1_000);

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
  items: [
    // History pages are newest-first; the display owner reverses them into
    // producer block order when it admits the page.
    for (final block in update.blocks.reversed)
      switch (block.body) {
        WorkDisplayBlock(
          :final members,
          :final timing,
          :final memberCount,
          :final groupClosed,
        ) =>
          WorkRangeTimelineItem(
            HistoryWorkRange(
              rangeId: members.blockId,
              afterSeq: members.afterSeq,
              beforeSeq:
                  members.beforeSeq ??
                  (groupClosed ? block.blockOrder + 1 : null),
              firstSeq: block.blockOrder,
              lastSeq: members.headSeq,
              startedAt: timing.startedAtMillis,
              endedAt: timing.finishedAtMillis,
              runId: members.runId,
              eventCount: memberCount > 0 ? memberCount : 1,
            ),
          ),
        SingleDisplayBlock(:final record, :final visibility) =>
          DividerTimelineItem(
            _fixtureEventRecord(block, record, visibility: visibility),
          ),
      },
  ],
  next: update.before,
);

HistoryEventRecord _fixtureEventRecord(
  DisplayBlock block,
  DisplayRecord record, {
  required HistorySingleVisibility visibility,
}) {
  final atom = record.atom;
  final payloadObj = switch (atom.payload) {
    InlinePayload(:final bytes) => () {
      try {
        final decoded = jsonDecode(utf8.decode(bytes));
        return decoded is Map<String, Object?> ? decoded : null;
      } catch (_) {
        return null;
      }
    }(),
    _ => null,
  };
  final envelope = {
    'contract': 'anywork.event/1',
    'type':
        payloadObj?['type'] ??
        switch (atom.kind) {
          ChatAtomKind.input || ChatAtomKind.text => 'text',
          ChatAtomKind.reasoning => 'thinking',
          ChatAtomKind.toolCall => 'tool',
          ChatAtomKind.plan => 'plan',
          ChatAtomKind.turnReceipt => 'turn',
          ChatAtomKind.skill => 'skill',
          ChatAtomKind.fileChange => 'file',
          ChatAtomKind.agent => 'agent',
          ChatAtomKind.inference => 'inference',
          ChatAtomKind.compaction => 'contextCompaction',
          _ => 'raw',
        },
    'meta': {
      'entityId': atom.id,
      'entityKind': atom.kind.name,
      'delivery': atom.delivery.name,
      'state': switch (atom.lifecycle) {
        ActiveChatAtom(:final status) => {
          'kind': 'knownActive',
          'status': status.name,
        },
        TerminalChatAtom(:final outcome) => {
          'kind': 'knownTerminal',
          'outcome': outcome.name,
        },
      },
      if (atom.startedAt != null) 'startedAt': _historyMillis(atom.startedAt),
      if (atom.finishedAt != null)
        'finishedAt': _historyMillis(atom.finishedAt),
      if (atom.textChannel != null) 'textChannel': atom.textChannel!.name,
      'singleVisibility': visibility.name,
      if (atom.contentPresent != null) 'contentPresent': atom.contentPresent,
      if (atom.tool != null)
        'tool': {'callId': atom.tool!.callId, 'name': atom.tool!.name},
    },
    'data': payloadObj?['data'] ?? <String, Object?>{},
    'bodies': payloadObj?['bodies'] ?? <Object?>[],
  };
  return HistoryEventRecord(
    seq: block.blockOrder,
    eventId: record.historyDetailEventId ?? record.historyEventId ?? atom.id,
    kind: atom.kind == ChatAtomKind.input ? 'input_accepted' : 'text_completed',
    timelineRole: HistoryTimelineRole.divider,
    occurredAt: _historyMillis(atom.startedAt),
    recordedAt: block.blockOrder,
    runId: record.runId,
    turnId: atom.turnId,
    attemptId: atom.attemptId,
    callId: record.callId ?? atom.tool?.callId,
    entityId: atom.id,
    toolName: atom.tool?.name,
    source: atom.source,
    rowKey: block.id,
    payloadSchema: 'anywork.event/1',
    payloadJson: jsonEncode(envelope),
  );
}

int? _historyMillis(int? seconds) =>
    seconds == null ? null : seconds * Duration.millisecondsPerSecond;
