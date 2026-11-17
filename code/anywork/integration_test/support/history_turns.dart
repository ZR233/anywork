import 'dart:async';

import 'package:anywork_client/conversation.dart';

const _historyDemand = HistoryDemand(maxRows: 128, maxBytes: 1024 * 1024);
const _currentDemand = ReadDemand(maxItems: 128, maxBytes: 512 * 1024);
const _maxHistoryPages = 1024;

Future<CurrentView> readCurrentSnapshot({
  required ConversationRepository conversations,
  required String threadId,
  Duration timeout = const Duration(seconds: 60),
}) async {
  if (timeout <= Duration.zero) {
    throw ArgumentError.value(timeout, 'timeout', 'must be positive');
  }
  final deadline = DateTime.now().add(timeout);
  final reader = await conversations
      .openCurrentReader(threadId, demand: _currentDemand)
      .timeout(_remaining(deadline, timeout, 'Current snapshot reader'));
  try {
    return await reader
        .snapshot(_currentDemand)
        .timeout(_remaining(deadline, timeout, 'Current snapshot'));
  } finally {
    await reader.close();
  }
}

Future<HistoryTurnHead> waitForHistoryTurn({
  required ConversationRepository conversations,
  required String threadId,
  required bool Function(HistoryTurnHead head) matches,
  required bool Function(HistoryTurnHead head) isExpectedTerminal,
  required String description,
  Duration timeout = const Duration(seconds: 60),
}) async {
  if (timeout <= Duration.zero) {
    throw ArgumentError.value(timeout, 'timeout', 'must be positive');
  }
  final deadline = DateTime.now().add(timeout);
  final reader = await conversations
      .openHistoryReader(threadId)
      .timeout(_remaining(deadline, timeout, description));
  try {
    var cut = await reader.capture().timeout(
      _remaining(deadline, timeout, description),
    );
    while (true) {
      var remaining = _remaining(deadline, timeout, description);
      final heads = await _readTurnHeads(reader, cut).timeout(remaining);
      for (final head in heads.where(matches)) {
        if (head.state
            case HistoryTurnState.unknown ||
                HistoryTurnState.queued ||
                HistoryTurnState.running) {
          continue;
        }
        if (isExpectedTerminal(head)) return head;
        throw StateError(
          '$description reached ${head.state.name} instead of the expected '
          'terminal state for Turn ${head.turnId}',
        );
      }

      remaining = _remaining(deadline, timeout, description);
      final changed = await reader.waitChanged(cut).timeout(remaining);
      if (changed == cut) {
        throw StateError(
          'History change for $description did not advance its cut',
        );
      }
      cut = changed;
    }
  } finally {
    await reader.close();
  }
}

Future<HistoryTurnHead> waitForCompletedHistoryTurn({
  required ConversationRepository conversations,
  required String threadId,
  required bool Function(HistoryTurnHead head) matches,
  required String description,
  Duration timeout = const Duration(seconds: 60),
}) => waitForHistoryTurn(
  conversations: conversations,
  threadId: threadId,
  matches: matches,
  isExpectedTerminal: (head) => head.state == HistoryTurnState.completed,
  description: description,
  timeout: timeout,
);

Future<List<HistoryTimelineEntry>> waitForHistoryRows({
  required ConversationRepository conversations,
  required String threadId,
  required bool Function(List<HistoryTimelineEntry> rows) matches,
  required String description,
  Duration timeout = const Duration(seconds: 60),
}) async {
  if (timeout <= Duration.zero) {
    throw ArgumentError.value(timeout, 'timeout', 'must be positive');
  }
  final deadline = DateTime.now().add(timeout);
  final reader = await conversations
      .openHistoryReader(threadId)
      .timeout(_remaining(deadline, timeout, description));
  try {
    var cut = await reader.capture().timeout(
      _remaining(deadline, timeout, description),
    );
    while (true) {
      var remaining = _remaining(deadline, timeout, description);
      final rows = await _readMainRows(reader, cut).timeout(remaining);
      if (matches(rows)) return rows;

      remaining = _remaining(deadline, timeout, description);
      final changed = await reader.waitChanged(cut).timeout(remaining);
      if (changed == cut) {
        throw StateError(
          'History change for $description did not advance its cut',
        );
      }
      cut = changed;
    }
  } finally {
    await reader.close();
  }
}

Duration _remaining(DateTime deadline, Duration timeout, String description) {
  final remaining = deadline.difference(DateTime.now());
  if (remaining <= Duration.zero) {
    throw TimeoutException('Timed out waiting for $description', timeout);
  }
  return remaining;
}

Future<List<HistoryTurnHead>> _readTurnHeads(
  HistoryReader reader,
  HistoryCut cut,
) async {
  final heads = <HistoryTurnHead>[];
  String? cursor;
  final seenCursors = <String>{};
  for (var pageIndex = 0; pageIndex < _maxHistoryPages; pageIndex++) {
    final page = await reader.turnsPage(
      cut: cut,
      cursor: cursor,
      demand: _historyDemand,
    );
    if (page.cut != cut) {
      throw StateError('History Turn page did not preserve its requested cut');
    }
    for (final entry in page.entries) {
      if (entry.head case TurnHistoryRow(:final head)) {
        heads.add(head);
      }
    }
    final next = page.next;
    if (next == null) return heads;
    if (!seenCursors.add(next)) {
      throw StateError('History Turn continuation repeated');
    }
    cursor = next;
  }
  throw StateError('History Turn scan exceeded $_maxHistoryPages pages');
}

Future<List<HistoryTimelineEntry>> _readMainRows(
  HistoryReader reader,
  HistoryCut cut,
) async {
  final rows = <HistoryTimelineEntry>[];
  String? cursor;
  final seenCursors = <String>{};
  for (var pageIndex = 0; pageIndex < _maxHistoryPages; pageIndex++) {
    final page = await reader.timelinePage(
      cut: cut,
      cursor: cursor,
      demand: _historyDemand,
    );
    if (page.cut != cut) {
      throw StateError('History Main page did not preserve its requested cut');
    }
    rows.addAll(page.entries);
    final next = page.next;
    if (next == null) return rows;
    if (!seenCursors.add(next)) {
      throw StateError('History Main continuation repeated');
    }
    cursor = next;
  }
  throw StateError('History Main scan exceeded $_maxHistoryPages pages');
}
