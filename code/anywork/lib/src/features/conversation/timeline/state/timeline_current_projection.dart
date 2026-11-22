import 'package:anywork_client/models.dart';

import 'timeline_display_models.dart';

/// Overlay Current facts onto already loaded History rows.
///
/// Current never creates its own main-timeline rows. An entity with no loaded
/// History anchor remains visible through the Current activity/waiting surface
/// until History publishes the stable row key.
abstract final class TimelineCurrentProjection {
  static List<DisplayBlock> overlayHistory(
    Iterable<DisplayBlock> history, {
    required Iterable<CurrentAtom> atoms,
    required String ownerId,
    bool executionPresent = false,
  }) {
    final atomList = atoms.toList(growable: false);
    final current = {
      for (final atom in atomList)
        if (atom.contents.isNotEmpty) atom.id: atom,
    };
    return [
      for (final block in history)
        _overlayBlock(
          block,
          current,
          atomList: atomList,
          ownerId: ownerId,
          executionPresent: executionPresent,
        ),
    ];
  }

  static DisplayBlock _overlayBlock(
    DisplayBlock block,
    Map<String, CurrentAtom> current, {
    required List<CurrentAtom> atomList,
    required String ownerId,
    required bool executionPresent,
  }) {
    final body = block.body;
    if (body is WorkDisplayBlock) {
      if (body.members.beforeSeq == null &&
          executionPresent &&
          (body.members.runId == null || body.members.runId == ownerId)) {
        final unfinished = atomList
            .where((atom) => atom.lifecycle is ActiveChatAtom)
            .length;
        return DisplayBlock(
          id: block.id,
          blockOrder: block.blockOrder,
          body: WorkDisplayBlock(
            timing: WorkTiming(
              startedAtMillis: body.timing.startedAtMillis,
              finishedAtMillis: null,
            ),
            members: body.members,
            executionPresent: true,
            memberCount: body.memberCount,
            unfinishedCount: unfinished > 0 ? unfinished : body.unfinishedCount,
            groupClosed: false,
            summary: body.summary,
          ),
        );
      }
      return block;
    }
    if (body is! SingleDisplayBlock) return block;
    final history = body.record.immutableRecord ?? body.record;
    if (body.record.immutableRecord == null &&
        current[history.atom.id] == null) {
      return block;
    }
    final overlaid = overlayRecord(history, current: current, ownerId: ownerId);
    return _withRecord(block, body, overlaid);
  }

  static DisplayRecord overlayRecord(
    DisplayRecord record, {
    required Map<String, CurrentAtom> current,
    required String ownerId,
    String? fallbackRunId,
  }) {
    final history = record.immutableRecord ?? record;
    if (history.isTerminalHistory || history.isFrozenHistory) {
      return history;
    }
    final atom =
        current[history.atom.id] ??
        (history.callId == null
            ? null
            : current.values
                  .where(
                    (candidate) => candidate.tool?.callId == history.callId,
                  )
                  .firstOrNull);
    if (atom == null || (history.runId ?? fallbackRunId) != ownerId) {
      return history;
    }
    return DisplayRecord(
      atom: _atom(atom),
      contentSource: const CurrentAtomSource(),
      startFact: history.startFact,
      endFact: history.endFact,
      // Current owns the live detail while this row is eligible. Reverting
      // to the immutable History body requires a later History replace.
      historyEventId: null,
      historyDetailEventId: null,
      runId: history.runId ?? fallbackRunId,
      isTerminalHistory: history.isTerminalHistory,
      isFrozenHistory: history.isFrozenHistory,
      callId: history.callId,
      predecodedPresentation: null,
      immutableRecord: history,
      currentContents: atom.contents,
    );
  }

  static DisplayBlock _withRecord(
    DisplayBlock block,
    SingleDisplayBlock body,
    DisplayRecord record,
  ) => identical(record, body.record)
      ? block
      : DisplayBlock(
          id: block.id,
          blockOrder: block.blockOrder,
          body: SingleDisplayBlock(visibility: body.visibility, record: record),
        );

  static ChatAtom _atom(CurrentAtom atom) => ChatAtom(
    id: atom.id,
    source: atom.source,
    sourceState: atom.sourceState,
    sourceOrder: atom.sourceOrder,
    kind: atom.kind,
    delivery: atom.delivery,
    lifecycle: atom.lifecycle,
    turnId: atom.turnId,
    attemptId: atom.attemptId,
    tool: atom.tool,
    wait: atom.wait,
    textChannel: atom.textChannel,
    contentPresent: atom.contentPresent,
    startedAt: atom.startedAt,
    finishedAt: atom.finishedAt,
    contents: const [],
  );
}
