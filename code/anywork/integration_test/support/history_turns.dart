import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/models.dart';

const _pageLimit = 128;
const _maxHistoryPages = 1024;

/// Observes the exact Turn through the same metadata used by the product.
/// This does not infer completion from a command receipt or assistant text.
Future<StudioTurnView> waitForTurn({
  required ConversationFeedPort feeds,
  required String threadId,
  required bool Function(StudioTurnView turn) matches,
  required bool Function(StudioTurnView turn) isExpectedTerminal,
  required String description,
  Duration timeout = const Duration(seconds: 60),
}) => _withFeed(feeds, threadId, timeout, description, (
  feed,
  events,
  remaining,
) async {
  StudioTurnView? terminal(SessionMetaSnapshot meta) {
    if (meta.threadId != threadId) {
      throw StateError('Session metadata belongs to another Thread');
    }
    for (final turn in [meta.activeTurn, meta.lastTurn]) {
      if (turn == null || !matches(turn) || !turn.state.isTerminal) continue;
      if (isExpectedTerminal(turn)) return turn;
      throw StateError(
        '$description reached ${turn.state.status.name} instead of the expected '
        'terminal state for Turn ${turn.turnId}',
      );
    }
    return null;
  }

  // A fresh feed is independent of the page's single-subscription stream.
  // Metadata retains active/last Turn only; this cannot query superseded Turns.
  final initial = terminal(feed.sessionMetaSnapshot);
  if (initial != null) return initial;
  while (await events.moveNext().timeout(remaining())) {
    switch (events.current) {
      case ConversationSessionMeta(:final snapshot):
        final result = terminal(snapshot);
        if (result != null) return result;
      case ConversationResyncRequired(:final reason):
        throw StateError(
          'Feed resync required while waiting for $description: $reason',
        );
      default:
        break;
    }
  }
  throw StateError('Feed closed before $description');
});

Future<StudioTurnView> waitForCompletedTurn({
  required ConversationFeedPort feeds,
  required String threadId,
  required bool Function(StudioTurnView turn) matches,
  required String description,
  Duration timeout = const Duration(seconds: 60),
}) => waitForTurn(
  feeds: feeds,
  threadId: threadId,
  matches: matches,
  isExpectedTerminal: (turn) => turn.state.status == StudioTurnStatus.completed,
  description: description,
  timeout: timeout,
);

/// Reads Rust-owned history pages and subsequent typed timeline changes.
/// No grouping, event decoding or receipt synthesis is performed here.
Future<List<TimelineItem>> waitForHistoryRows({
  required ConversationFeedPort feeds,
  required String threadId,
  required bool Function(List<TimelineItem> rows) matches,
  required String description,
  Duration timeout = const Duration(seconds: 60),
}) => _withFeed(feeds, threadId, timeout, description, (
  feed,
  events,
  remaining,
) async {
  final rows = <TimelineItem>[];
  var hasReset = false;
  while (await events.moveNext().timeout(remaining())) {
    final event = events.current;
    if (event case ConversationResyncRequired(:final reason)) {
      throw StateError(
        'Feed resync required while reading $description: $reason',
      );
    }
    if (event is! ConversationTimeline) continue;
    switch (event.patch) {
      case TimelineReset(:final items, :final hasMoreOlder, :final olderCursor):
        hasReset = true;
        rows
          ..clear()
          ..addAll(items);
        var more = hasMoreOlder;
        var cursor = olderCursor;
        final seenCursors = <String>{};
        var pages = 0;
        while (more) {
          if (cursor == null || !seenCursors.add(cursor)) {
            throw StateError('History continuation missing or repeated');
          }
          if (++pages > _maxHistoryPages) {
            throw StateError('History scan exceeded $_maxHistoryPages pages');
          }
          final older = await feed
              .loadOlder(cursor: cursor, limit: _pageLimit)
              .timeout(remaining());
          if (older is! TimelinePrependOlder) {
            throw StateError('History loadOlder did not return a prepend');
          }
          rows.insertAll(0, older.items);
          more = older.hasMoreOlder;
          cursor = older.olderCursor;
        }
      case TimelineAppend(:final items):
        rows.addAll(items);
      case TimelineUpdate(:final item):
        final index = rows.indexWhere((row) => row.id == item.id);
        if (index < 0) {
          throw StateError('Timeline updated an unknown item ${item.id}');
        }
        rows[index] = item;
      case TimelineRemove(:final itemId):
        rows.removeWhere((row) => row.id == itemId);
      case TimelinePrependOlder():
        throw StateError('Unrequested history prepend on the feed stream');
    }
    if (!hasReset) {
      throw StateError('Timeline changed before its initial reset');
    }
    final ids = rows.map((row) => row.id).toSet();
    if (ids.length != rows.length) {
      throw StateError('History contains duplicate timeline identities');
    }
    final snapshot = List<TimelineItem>.unmodifiable(rows);
    if (matches(snapshot)) return snapshot;
  }
  throw StateError('Feed closed before $description');
});

Future<T> _withFeed<T>(
  ConversationFeedPort feeds,
  String threadId,
  Duration timeout,
  String description,
  Future<T> Function(
    ConversationFeedHandle,
    StreamIterator<ConversationFeedEvent>,
    Duration Function(),
  )
  read,
) async {
  if (timeout <= Duration.zero) {
    throw ArgumentError.value(timeout, 'timeout', 'must be positive');
  }
  final deadline = DateTime.now().add(timeout);
  Duration remaining() {
    final value = deadline.difference(DateTime.now());
    if (value <= Duration.zero) {
      throw TimeoutException('Timed out waiting for $description', timeout);
    }
    return value;
  }

  final feed = await feeds
      .openConversationFeed(threadId, initialLimit: _pageLimit)
      .timeout(remaining());
  final events = StreamIterator(feed.events);
  try {
    if (feed.threadId != threadId) {
      throw StateError('Feed Thread identity mismatch');
    }
    return await read(feed, events, remaining);
  } finally {
    feed.requestClose();
    try {
      await events.cancel();
    } finally {
      await feed.close();
    }
  }
}
