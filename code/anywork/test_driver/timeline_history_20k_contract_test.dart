import 'timeline_history_20k_contract.dart';

void main() {
  _expectStateError(
    'near-full cold window',
    () => requireTimelineHistory20kColdWindow(
      loadedCount: 19_999,
      itemCount: 19_999,
      hasOlder: true,
    ),
  );
  _expectStateError(
    'missing cold loadedCount',
    () => requireTimelineHistory20kColdWindow(
      loadedCount: null,
      itemCount: 32,
      hasOlder: true,
    ),
  );
  _expectStateError(
    'idle cursor change',
    () => requireTimelineHistory20kIdleWindowUnchanged(
      initialItemCount: 32,
      initialLoadedCount: 32,
      initialItemIds: const ['a'],
      initialOlderCursor: 'before-a',
      initialHasOlder: true,
      idleItemCount: 32,
      idleLoadedCount: 32,
      idleItemIds: const ['a'],
      idleOlderCursor: 'before-b',
      idleHasOlder: true,
    ),
  );
  _expectStateError(
    'missing required queue field',
    () => TimelineHistoryQueueSample.parse(<String, Object?>{
      'pendingOperations': 0,
      'inFlightBytes': 0,
      'threads': [
        <String, Object?>{'historyAdmitted': 1, 'historyDurable': 1},
      ],
    }, context: 'test'),
  );
  _expectStateError(
    'non-integer required queue field',
    () => TimelineHistoryQueueSample.parse(<String, Object?>{
      'pendingOperations': 0.0,
      'pendingBytes': 0,
      'inFlightBytes': 0,
      'threads': [
        <String, Object?>{'historyAdmitted': 1, 'historyDurable': 1},
      ],
    }, context: 'test'),
  );
  final beforeAppend = _timeline(<Map<String, Object?>>[
    _item('a', 1, text: 'old-a'),
    _item('b', 2, text: 'old-b'),
  ]);
  requireTimelineHistory20kAppendOnlyWindow(
    before: beforeAppend,
    after: _timeline(<Map<String, Object?>>[
      _item('a', 1, text: 'old-a'),
      _item('b', 2, text: 'old-b'),
      _item('c', 3, text: 'new-c'),
    ]),
  );
  _expectStateError(
    'equal-length old atom rewrite',
    () => requireTimelineHistory20kAppendOnlyWindow(
      before: beforeAppend,
      after: _timeline(<Map<String, Object?>>[
        _item('a', 1, text: 'old-a'),
        _item('b', 2, text: 'rewritten-b'),
      ]),
    ),
  );
  _expectStateError(
    'old atom missing',
    () => requireTimelineHistory20kAppendOnlyWindow(
      before: beforeAppend,
      after: _timeline(<Map<String, Object?>>[
        _item('a', 1, text: 'old-a'),
        _item('c', 3, text: 'new-c'),
        _item('d', 4, text: 'new-d'),
      ]),
    ),
  );
  _expectStateError(
    'old atoms reordered',
    () => requireTimelineHistory20kAppendOnlyWindow(
      before: beforeAppend,
      after: _timeline(<Map<String, Object?>>[
        _item('b', 1, text: 'old-b'),
        _item('a', 2, text: 'old-a'),
        _item('c', 3, text: 'new-c'),
      ]),
    ),
  );
  _expectStateError(
    'appended sequence does not advance',
    () => requireTimelineHistory20kAppendOnlyWindow(
      before: beforeAppend,
      after: _timeline(<Map<String, Object?>>[
        _item('a', 1, text: 'old-a'),
        _item('b', 2, text: 'old-b'),
        _item('c', 2, text: 'new-c'),
      ]),
    ),
  );
  _expectStateError(
    'duplicate item id',
    () => requireTimelineHistory20kAppendOnlyWindow(
      before: beforeAppend,
      after: _timeline(<Map<String, Object?>>[
        _item('a', 1, text: 'old-a'),
        _item('b', 2, text: 'old-b'),
        _item('a', 3, text: 'new-a'),
      ]),
    ),
  );
  _expectStateError(
    'timeline scope changed',
    () => requireTimelineHistory20kAppendOnlyWindow(
      before: beforeAppend,
      after: _timeline(<Map<String, Object?>>[
        _item('a', 1, text: 'old-a'),
        _item('b', 2, text: 'old-b'),
        _item('c', 3, text: 'new-c'),
      ], generation: 8),
    ),
  );

  requireTimelineHistory20kColdWindow(
    loadedCount: 128,
    itemCount: 128,
    hasOlder: true,
  );
  TimelineHistoryQueueSample.parse(<String, Object?>{
    'pendingOperations': 0,
    'pendingBytes': 0,
    'inFlightBytes': 0,
    'threads': [
      <String, Object?>{'historyAdmitted': 1, 'historyDurable': 1},
    ],
  }, context: 'test');
}

Map<String, Object?> _timeline(
  List<Map<String, Object?>> items, {
  int generation = 7,
}) => <String, Object?>{
  'mode': 'history',
  'threadId': 'thread-20k',
  'generation': generation,
  'timelineEpoch': 'epoch-20k',
  'itemCount': items.length,
  'itemIds': [for (final item in items) item['id']! as String],
  'items': items,
};

Map<String, Object?> _item(String id, int appendSeq, {required String text}) =>
    <String, Object?>{
      'id': id,
      'appendSeq': appendSeq,
      'kind': 'text',
      'status': 'completed',
      'text': text,
      'metadata': <String, Object?>{'batch': 11, 'source': 'fixture'},
    };

void _expectStateError(String label, void Function() action) {
  try {
    action();
  } on StateError {
    return;
  }
  throw StateError('$label did not fail');
}
