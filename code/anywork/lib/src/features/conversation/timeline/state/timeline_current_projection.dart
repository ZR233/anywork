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
  }) {
    final current = {
      for (final atom in atoms)
        if (atom.contents.isNotEmpty) atom.id: atom,
    };
    return [
      for (final block in history) _overlayBlock(block, current, ownerId),
    ];
  }

  static DisplayBlock _overlayBlock(
    DisplayBlock block,
    Map<String, CurrentAtom> current,
    String ownerId,
  ) {
    final body = block.body;
    if (body is! SingleDisplayBlock) return block;
    final history = body.record.immutableRecord ?? body.record;
    if (body.record.immutableRecord == null &&
        current[history.atom.id] == null) {
      return block;
    }
    if (history.historyState == HistoryEntityStateKind.knownTerminal ||
        history.historyObservation == HistoryObservationKind.boundary ||
        history.historyObservation ==
            HistoryObservationKind.unavailableLegacy) {
      return _withRecord(block, body, history);
    }
    final atom = current[history.atom.id];
    if (atom == null || !_sameRun(history, atom, ownerId)) {
      return _withRecord(block, body, history);
    }
    return DisplayBlock(
      id: block.id,
      blockOrder: block.blockOrder,
      body: SingleDisplayBlock(
        visibility: body.visibility,
        record: DisplayRecord(
          atom: _atom(atom),
          contentSource: const CurrentAtomSource(),
          startFact: history.startFact,
          endFact: history.endFact,
          // Current owns the live detail while this row is eligible. Reverting
          // to the immutable History body requires a later History replace.
          historyEventId: null,
          historyDetailEventId: null,
          runId: history.runId,
          historyState: history.historyState,
          historyObservation: history.historyObservation,
          immutableRecord: history,
          currentContents: atom.contents,
        ),
      ),
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

  static bool _sameRun(
    DisplayRecord history,
    CurrentAtom atom,
    String ownerId,
  ) {
    return history.runId == ownerId;
  }

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
