import 'package:anywork_client/models.dart';

import 'timeline_display_models.dart';

/// Projects only the typed main-history heads that own a visual row. Turn,
/// source, cost and accounting heads stay on their dedicated query surfaces.
abstract final class TimelineHistoryProjection {
  static List<DisplayBlock> blocks(List<HistoryTimelineEntry> entries) => [
    for (final entry in entries)
      if (_block(entry) case final block?) block,
  ];

  static DisplayBlock? block(HistoryTimelineEntry entry) => _block(entry);

  static DisplayBlock? _block(HistoryTimelineEntry entry) {
    final DisplayBlockBody? body;
    switch (entry.head) {
      case WorkHistoryRow(:final head):
        body = WorkDisplayBlock(
          timing: WorkTiming(
            startedAt: head.startedAt,
            finishedAt: head.boundaryAt,
          ),
          members: DisplayBlockRef(databaseId: '', blockId: head.groupId),
        );
      case SingleHistoryRow(:final head):
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
        body = _single(head, visibility: HistorySingleVisibility.content);
      case TurnHistoryRow() ||
          SourceHistoryRow() ||
          CostHistoryRow() ||
          AccountingHistoryRow():
        return null;
    }
    if (body == null) return null;
    return DisplayBlock(
      id: entry.rowKey,
      blockOrder: entry.anchorSeq,
      body: body,
    );
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
    startedAt: head.startedAt,
    finishedAt: head.finishedAt,
    contents: const [],
  );
}
