// Scenario-local acceptance contracts shared by the host journey and its
// dependency-free negative checks.
import 'dart:convert';

const timelineHistory20kColdWindowBudget = <String, Object>{
  'defaultPageItems': 32,
  'maximumAutoFillPages': 4,
  'maximumLoadedItems': 128,
  'windowWidthPixels': 1280,
  'windowHeightPixels': 720,
  'fixtureBodyBytesPerItem': 32,
  'basis':
      'The production baseline/page default is 32. This fixture renders each '
      'canonical output as an independent non-empty single-line text row in '
      'the fixed 1280x720 Linux window; four pages allow conservative '
      'automatic viewport filling without accepting a near-full history.',
  'scope':
      'scenario guardrail for this fixed short-text shape, not a production '
      'pagination limit',
};

const timelineHistory20kColdWindowMaximumItems = 128;

void requireTimelineHistory20kColdWindow({
  required int? loadedCount,
  required int itemCount,
  required bool hasOlder,
}) {
  if (loadedCount == null) {
    throw StateError('cold window loadedCount is unavailable');
  }
  if (loadedCount < 1 || loadedCount != itemCount) {
    throw StateError(
      'cold window loadedCount=$loadedCount disagrees with itemCount=$itemCount',
    );
  }
  if (!hasOlder || itemCount > timelineHistory20kColdWindowMaximumItems) {
    throw StateError(
      'cold window is outside the partial-load budget: '
      'itemCount=$itemCount hasOlder=$hasOlder '
      'maximum=$timelineHistory20kColdWindowMaximumItems',
    );
  }
}

void requireTimelineHistory20kIdleWindowUnchanged({
  required int initialItemCount,
  required int? initialLoadedCount,
  required List<String> initialItemIds,
  required String? initialOlderCursor,
  required bool initialHasOlder,
  required int idleItemCount,
  required int? idleLoadedCount,
  required List<String> idleItemIds,
  required String? idleOlderCursor,
  required bool idleHasOlder,
}) {
  if (initialLoadedCount == null || idleLoadedCount == null) {
    throw StateError('cold idle comparison requires loadedCount');
  }
  if (idleItemCount != initialItemCount ||
      idleLoadedCount != initialLoadedCount ||
      idleLoadedCount != idleItemCount ||
      !_sameStrings(idleItemIds, initialItemIds) ||
      idleOlderCursor != initialOlderCursor ||
      idleHasOlder != initialHasOlder) {
    throw StateError('cold idle window changed without input');
  }
}

void requireTimelineHistory20kAppendOnlyWindow({
  required Map<String, Object?> before,
  required Map<String, Object?> after,
}) {
  final beforeScope = _timelineHistory20kScope(before, 'before');
  final afterScope = _timelineHistory20kScope(after, 'after');
  if (afterScope.threadId != beforeScope.threadId ||
      afterScope.generation != beforeScope.generation ||
      afterScope.timelineEpoch != beforeScope.timelineEpoch) {
    throw StateError(
      'History scope changed: '
      'before=(threadId=${beforeScope.threadId}, '
      'generation=${beforeScope.generation}, '
      'timelineEpoch=${beforeScope.timelineEpoch}) '
      'after=(threadId=${afterScope.threadId}, '
      'generation=${afterScope.generation}, '
      'timelineEpoch=${afterScope.timelineEpoch})',
    );
  }

  final beforeItems = _timelineHistory20kItems(before, 'before');
  final afterItems = _timelineHistory20kItems(after, 'after');
  if (afterItems.length < beforeItems.length) {
    throw StateError(
      'History append-only window lost old atoms: '
      'before=${beforeItems.length} after=${afterItems.length}',
    );
  }
  for (var index = 0; index < beforeItems.length; index++) {
    final oldItem = beforeItems[index];
    final currentItem = afterItems[index];
    if (jsonEncode(currentItem) != jsonEncode(oldItem)) {
      throw StateError(
        'History append-only prefix changed at index $index: '
        'beforeId=${oldItem['id']} afterId=${currentItem['id']} '
        'before=${jsonEncode(oldItem)} after=${jsonEncode(currentItem)}',
      );
    }
  }
  if (afterItems.length > beforeItems.length && beforeItems.isNotEmpty) {
    final oldLastSequence = beforeItems.last['appendSeq']! as int;
    final newFirstSequence =
        afterItems[beforeItems.length]['appendSeq']! as int;
    if (newFirstSequence <= oldLastSequence) {
      throw StateError(
        'History appended tail does not advance appendSeq: '
        'oldLast=$oldLastSequence newFirst=$newFirstSequence',
      );
    }
  }
}

int requireNonNegativeInteger(Object? value, String field) {
  if (value is! int || value < 0) {
    throw StateError('$field must be a non-negative integer, got $value');
  }
  return value;
}

final class TimelineHistoryQueueSample {
  const TimelineHistoryQueueSample({
    required this.pendingOperations,
    required this.pendingBytes,
    required this.inFlightBytes,
    required this.historyAdmitted,
    required this.historyDurable,
  });

  factory TimelineHistoryQueueSample.parse(
    Map<String, Object?> queue, {
    required String context,
  }) {
    final threads = queue['threads'];
    if (threads is! List || threads.length != 1 || threads.single is! Map) {
      throw StateError('$context.threads must contain exactly one thread');
    }
    final thread = Map<String, Object?>.from(threads.single as Map);
    return TimelineHistoryQueueSample(
      pendingOperations: requireNonNegativeInteger(
        queue['pendingOperations'],
        '$context.pendingOperations',
      ),
      pendingBytes: requireNonNegativeInteger(
        queue['pendingBytes'],
        '$context.pendingBytes',
      ),
      inFlightBytes: requireNonNegativeInteger(
        queue['inFlightBytes'],
        '$context.inFlightBytes',
      ),
      historyAdmitted: requireNonNegativeInteger(
        thread['historyAdmitted'],
        '$context.threads[0].historyAdmitted',
      ),
      historyDurable: requireNonNegativeInteger(
        thread['historyDurable'],
        '$context.threads[0].historyDurable',
      ),
    );
  }

  final int pendingOperations;
  final int pendingBytes;
  final int inFlightBytes;
  final int historyAdmitted;
  final int historyDurable;

  Map<String, Object?> toJson() => <String, Object?>{
    'pendingOperations': pendingOperations,
    'pendingBytes': pendingBytes,
    'inFlightBytes': inFlightBytes,
    'historyAdmitted': historyAdmitted,
    'historyDurable': historyDurable,
  };
}

({String threadId, int generation, String timelineEpoch})
_timelineHistory20kScope(Map<String, Object?> timeline, String context) {
  final mode = timeline['mode'];
  if (mode != 'history') {
    throw StateError('$context.mode must be history, got $mode');
  }
  final threadId = timeline['threadId'];
  if (threadId is! String || threadId.isEmpty) {
    throw StateError('$context.threadId must be a non-empty string');
  }
  final generation = timeline['generation'];
  if (generation is! int || generation < 1) {
    throw StateError('$context.generation must be a positive integer');
  }
  final timelineEpoch = timeline['timelineEpoch'];
  if (timelineEpoch is! String || timelineEpoch.isEmpty) {
    throw StateError('$context.timelineEpoch must be a non-empty string');
  }
  return (
    threadId: threadId,
    generation: generation,
    timelineEpoch: timelineEpoch,
  );
}

List<Map<String, Object?>> _timelineHistory20kItems(
  Map<String, Object?> timeline,
  String context,
) {
  final rawItems = timeline['items'];
  final rawItemIds = timeline['itemIds'];
  final itemCount = timeline['itemCount'];
  if (rawItems is! List || rawItemIds is! List) {
    throw StateError('$context.items and $context.itemIds must be lists');
  }
  if (itemCount is! int ||
      itemCount != rawItems.length ||
      rawItemIds.length != rawItems.length) {
    throw StateError(
      '$context item cardinality disagrees: '
      'itemCount=$itemCount items=${rawItems.length} '
      'itemIds=${rawItemIds.length}',
    );
  }

  final items = <Map<String, Object?>>[];
  final ids = <String>{};
  int? previousSequence;
  for (var index = 0; index < rawItems.length; index++) {
    final rawItem = rawItems[index];
    final rawId = rawItemIds[index];
    if (rawItem is! Map || rawId is! String || rawId.isEmpty) {
      throw StateError('$context item $index has an invalid wire shape');
    }
    final item = Map<String, Object?>.from(rawItem);
    final itemId = item['id'];
    if (itemId != rawId) {
      throw StateError(
        '$context item $index disagrees with itemIds: '
        'item.id=$itemId itemIds[$index]=$rawId',
      );
    }
    if (!ids.add(rawId)) {
      throw StateError('$context contains duplicate item id $rawId');
    }
    final appendSeq = item['appendSeq'];
    if (appendSeq is! int || appendSeq < 0) {
      throw StateError('$context item $rawId has invalid appendSeq=$appendSeq');
    }
    if (previousSequence != null && appendSeq <= previousSequence) {
      throw StateError(
        '$context appendSeq is not strictly increasing at item $rawId: '
        'previous=$previousSequence current=$appendSeq',
      );
    }
    previousSequence = appendSeq;
    items.add(item);
  }
  return items;
}

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
