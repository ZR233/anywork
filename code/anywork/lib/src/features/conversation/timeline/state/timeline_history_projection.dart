import 'package:anywork_client/conversation.dart';

import 'timeline_display_models.dart';

/// Projects only the typed main-history heads that own a visual row. Turn,
/// source, cost and accounting heads stay on their dedicated query surfaces.
abstract final class TimelineHistoryProjection {
  static List<DisplayBlock> blocks(
    Iterable<HistoryTimelineEntry> entries, {
    required HistoryCut cut,
  }) => [for (final entry in entries) ?_block(entry, cut: cut)];

  static DisplayBlock? block(
    HistoryTimelineEntry entry, {
    required HistoryCut cut,
  }) => _block(entry, cut: cut);

  static DisplayBlock? eventDetail(
    HistoryEventDetail detail, {
    required HistoryCut cut,
  }) {
    final head = detail.head;
    if (head == null) return null;
    if (detail.header.eventId.isEmpty) {
      throw const ConversationContinuityError(
        'History event has no stable event identity',
      );
    }
    final anchorSeq = detail.header.seq;
    return _blockFromHead(
      rowKey: detail.header.rowKey ?? 'event:${detail.header.eventId}',
      anchorSeq: anchorSeq,
      headSeq: anchorSeq,
      head: head,
      cut: cut,
    );
  }

  static DisplayBlock? _block(
    HistoryTimelineEntry entry, {
    required HistoryCut cut,
  }) => _blockFromHead(
    rowKey: entry.rowKey,
    anchorSeq: entry.anchorSeq,
    headSeq: entry.headSeq,
    head: entry.head,
    cut: cut,
  );

  static DisplayBlock? _blockFromHead({
    required String rowKey,
    required int anchorSeq,
    required int headSeq,
    required HistoryRowHead head,
    required HistoryCut cut,
  }) {
    if (rowKey.isEmpty) {
      throw const ConversationContinuityError(
        'History row has no stable row identity',
      );
    }
    final DisplayBlockBody? body;
    switch (head) {
      case WorkHistoryRow(:final head):
        if (head.groupId.isEmpty) {
          throw const ConversationContinuityError(
            'History Work has no stable group identity',
          );
        }
        body = WorkDisplayBlock(
          timing: WorkTiming(
            startedAtMillis: head.startedAt,
            finishedAtMillis: head.boundaryAt,
          ),
          members: DisplayBlockRef(
            blockId: head.groupId,
            cut: cut,
            anchorSeq: anchorSeq,
            headSeq: headSeq,
          ),
          executionPresent: head.executionPresent,
          memberCount: head.memberCount,
          unfinishedCount: head.unfinishedCount,
          groupClosed: head.closed,
          summary: head.summary,
        );
      case SingleHistoryRow(:final head):
        if (head.entityId.isEmpty) {
          throw const ConversationContinuityError(
            'History row has no stable entity identity',
          );
        }
        body = _single(
          head,
          visibility: switch (head.singleVisibility) {
            null ||
            HistorySingleVisibility.content => HistorySingleVisibility.content,
            HistorySingleVisibility.finalEmptyAfterContent =>
              HistorySingleVisibility.finalEmptyAfterContent,
          },
        );
      case MemberHistoryRow(:final head):
        if (head.entityId.isEmpty) {
          throw const ConversationContinuityError(
            'History member has no stable entity identity',
          );
        }
        body = _single(head, visibility: HistorySingleVisibility.content);
      case TurnHistoryRow() ||
          SourceHistoryRow() ||
          CostHistoryRow() ||
          AccountingHistoryRow():
        return null;
    }
    if (body == null) return null;
    return DisplayBlock(id: rowKey, blockOrder: anchorSeq, body: body);
  }

  static SingleDisplayBlock? _single(
    HistoryEntityHead head, {
    required HistorySingleVisibility visibility,
  }) {
    final record = _record(head);
    return record == null
        ? null
        : SingleDisplayBlock(record: record, visibility: visibility);
  }

  static DisplayRecord? _record(HistoryEntityHead head) {
    if (head.state.kind == HistoryEntityStateKind.unknown) return null;
    return DisplayRecord(
      atom: _atom(head),
      historyEventId: head.contentPresent == false
          ? null
          : head.bodyManifestEventId ?? head.detailEventId ?? head.entityId,
      historyDetailEventId: head.detailEventId,
      runId: head.runId,
      historyState: head.state.kind,
      historyObservation: head.observation.kind,
      contentSource: switch (head.observation.kind) {
        HistoryObservationKind.original => CompletedOriginal(
          completionId: head.detailEventId ?? head.entityId,
        ),
        HistoryObservationKind.boundary => FrozenObservation(
          capturedAt: head.observation.capturedAt,
          available: head.contentPresent ?? true,
        ),
        HistoryObservationKind.unavailableLegacy => FrozenObservation(
          capturedAt: head.observation.capturedAt,
          available: false,
        ),
      },
    );
  }

  static ChatAtom _atom(HistoryEntityHead head) => ChatAtom(
    id: head.entityId,
    source: head.source,
    sourceOrder: null,
    kind: head.kind,
    delivery: head.delivery,
    lifecycle: switch (head.state.kind) {
      HistoryEntityStateKind.unknown => throw StateError(
        'Unknown history state has no display lifecycle',
      ),
      HistoryEntityStateKind.knownActive => ActiveChatAtom(
        started: null,
        status: head.state.activeStatus!,
      ),
      HistoryEntityStateKind.knownTerminal => TerminalChatAtom(
        started: null,
        ended: null,
        outcome: head.state.outcome!,
      ),
    },
    attemptId: head.attemptId,
    tool: head.tool == null
        ? null
        : ChatToolIdentity(callId: head.tool!.callId, name: head.tool!.name),
    textChannel: head.textChannel,
    contentPresent: head.contentPresent,
    startedAt: _atomSeconds(head.startedAt),
    finishedAt: _atomSeconds(head.finishedAt),
    contents: const [],
  );

  // ChatAtom retains the native producer's Unix seconds.
  static int? _atomSeconds(int? millis) =>
      millis == null ? null : millis ~/ Duration.millisecondsPerSecond;
}
