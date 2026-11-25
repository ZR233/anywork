import 'package:anywork_client/models.dart';

import 'timeline_display_models.dart';

/// Overlay Current facts onto in-flight members inside `LiveStatusBar`.
///
/// Main Timeline rows are strictly immutable once admitted and never accept
/// Current overlay mutations.
abstract final class TimelineCurrentProjection {
  static DisplayRecord overlayRecord(
    DisplayRecord record, {
    required Map<String, CurrentAtom> current,
    required Map<String, CurrentAtom> currentByCall,
    required String ownerId,
    String? fallbackRunId,
  }) {
    final history = record.immutableRecord ?? record;
    if (history.isTerminalHistory ||
        history.isFrozenHistory ||
        (history.runId ?? fallbackRunId) != ownerId) {
      return history;
    }
    final atom = current[history.atom.id] ?? currentByCall[history.callId];
    if (atom == null) return history;
    return DisplayRecord(
      atom: toChatAtom(atom),
      contentSource: const CurrentAtomSource(),
      startFact: history.startFact,
      endFact: history.endFact,
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

  static ChatAtom toChatAtom(CurrentAtom atom) => ChatAtom(
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
    modelRecovery: atom.modelRecovery,
    contentPresent: atom.contentPresent,
    startedAt: atom.startedAt,
    finishedAt: atom.finishedAt,
    contents: const [],
  );
}
