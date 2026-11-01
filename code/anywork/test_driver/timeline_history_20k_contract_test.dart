import 'timeline_history_20k_contract.dart';

void main() {
  _testGrowthWriterStartup();
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
  _expectStateError('missing required queue field', () {
    final queue = _queue()..remove('pendingBytes');
    TimelineHistoryQueueSample.parse(
      queue,
      context: 'test',
      threadId: 'thread-1',
    );
  });
  _expectStateError('non-integer required queue field', () {
    final queue = _queue();
    queue['pendingOperations'] = 0.0;
    TimelineHistoryQueueSample.parse(
      queue,
      context: 'test',
      threadId: 'thread-1',
    );
  });
  final beforeAppend = _timeline(<Map<String, Object?>>[
    _item('a', text: 'old-a'),
    _item('b', text: 'old-b'),
  ]);
  requireTimelineHistory20kAppendOnlyWindow(
    before: beforeAppend,
    after: _timeline(<Map<String, Object?>>[
      _item('a', text: 'old-a'),
      _item('b', text: 'old-b'),
      _item('c', text: 'new-c'),
    ]),
  );
  _expectStateError(
    'equal-length old atom rewrite',
    () => requireTimelineHistory20kAppendOnlyWindow(
      before: beforeAppend,
      after: _timeline(<Map<String, Object?>>[
        _item('a', text: 'old-a'),
        _item('b', text: 'rewritten-b'),
      ]),
    ),
  );
  _expectStateError(
    'old atom missing',
    () => requireTimelineHistory20kAppendOnlyWindow(
      before: beforeAppend,
      after: _timeline(<Map<String, Object?>>[
        _item('a', text: 'old-a'),
        _item('c', text: 'new-c'),
        _item('d', text: 'new-d'),
      ]),
    ),
  );
  _expectStateError(
    'old atoms reordered',
    () => requireTimelineHistory20kAppendOnlyWindow(
      before: beforeAppend,
      after: _timeline(<Map<String, Object?>>[
        _item('b', text: 'old-b'),
        _item('a', text: 'old-a'),
        _item('c', text: 'new-c'),
      ]),
    ),
  );
  _expectStateError(
    'new item prepended instead of appended',
    () => requireTimelineHistory20kAppendOnlyWindow(
      before: beforeAppend,
      after: _timeline(<Map<String, Object?>>[
        _item('c', text: 'new-c'),
        _item('a', text: 'old-a'),
        _item('b', text: 'old-b'),
      ]),
    ),
  );
  _expectStateError(
    'duplicate item id',
    () => requireTimelineHistory20kAppendOnlyWindow(
      before: beforeAppend,
      after: _timeline(<Map<String, Object?>>[
        _item('a', text: 'old-a'),
        _item('b', text: 'old-b'),
        _item('a', text: 'new-a'),
      ]),
    ),
  );
  _expectStateError(
    'timeline scope changed',
    () => requireTimelineHistory20kAppendOnlyWindow(
      before: beforeAppend,
      after: _timeline(<Map<String, Object?>>[
        _item('a', text: 'old-a'),
        _item('b', text: 'old-b'),
        _item('c', text: 'new-c'),
      ], generation: 8),
    ),
  );

  requireTimelineHistory20kColdWindow(
    loadedCount: 128,
    itemCount: 128,
    hasOlder: true,
  );
  TimelineHistoryQueueSample.parse(
    _queue(),
    context: 'test',
    threadId: 'thread-1',
  );
  final passive = _queue(threads: []);
  requireTimelineHistoryPassiveQueue(passive, context: 'cold');
  for (final (field, invalid) in [
    ('loaded', false),
    ('syncPhase', 'reconnecting'),
    ('revision', 1.0),
    ('pendingOperations', 1),
    ('pendingBytes', 1),
    ('inFlightBytes', 1),
    ('lastError', 'save failed'),
    ('pressurePaused', true),
    (
      'threads',
      <Object?>[
        {'threadId': 'thread-1'},
      ],
    ),
  ]) {
    _expectStateError('invalid passive $field', () {
      final queue = Map<String, Object?>.from(passive);
      queue[field] = invalid;
      requireTimelineHistoryPassiveQueue(queue, context: 'cold');
    });
  }
  _expectStateError('missing passive queue metric', () {
    final queue = Map<String, Object?>.from(passive)..remove('pendingBytes');
    requireTimelineHistoryPassiveQueue(queue, context: 'cold');
  });

  final twoWriters = _queue(
    threads: [
      {'threadId': 'other', 'historyAdmitted': 7, 'historyDurable': 7},
      {'threadId': 'thread-1', 'historyAdmitted': 11, 'historyDurable': 10},
    ],
  );
  final target = TimelineHistoryQueueSample.parse(
    twoWriters,
    context: 'growth',
    threadId: 'thread-1',
  );
  if (target.threadId != 'thread-1' ||
      target.historyAdmitted != 11 ||
      target.historyDurable != 10 ||
      target.toJson()['threadId'] != 'thread-1') {
    throw StateError(
      'growth used another writer instead of its original target',
    );
  }
  _expectStateError(
    'target writer missing',
    () => TimelineHistoryQueueSample.parse(
      twoWriters,
      context: 'growth',
      threadId: 'missing',
    ),
  );
  _expectStateError(
    'duplicate target writer',
    () => TimelineHistoryQueueSample.parse(
      _queue(
        threads: [
          {'threadId': 'thread-1', 'historyAdmitted': 1, 'historyDurable': 1},
          {'threadId': 'thread-1', 'historyAdmitted': 1, 'historyDurable': 1},
        ],
      ),
      context: 'growth',
      threadId: 'thread-1',
    ),
  );
  _expectStateError(
    'unknown target watermark cannot become zero',
    () => TimelineHistoryQueueSample.parse(
      _queue(
        threads: [
          {
            'threadId': 'thread-1',
            'historyAdmitted': null,
            'historyDurable': null,
          },
        ],
      ),
      context: 'growth',
      threadId: 'thread-1',
    ),
  );
}

void _testGrowthWriterStartup() {
  final growth = TimelineHistoryGrowthQueue(threadId: 'thread-1');
  final passive = _queue(threads: []);
  final unrelated = _queue(
    threads: [
      {'threadId': 'other', 'historyAdmitted': 99, 'historyDurable': 98},
    ],
  );
  for (final queue in [passive, unrelated]) {
    if (growth.observe(
          queue,
          context: 'submission still pending',
          turnCompleted: false,
        ) !=
        null) {
      throw StateError('startup fabricated a target watermark sample');
    }
  }
  final running = growth.observe(
    _queue(
      threads: [
        {'threadId': 'other', 'historyAdmitted': 99, 'historyDurable': 98},
        {'threadId': 'thread-1', 'historyAdmitted': 11, 'historyDurable': 9},
      ],
    ),
    context: 'writer appeared before Turn completion',
    turnCompleted: false,
  );
  if (running?.threadId != 'thread-1' ||
      running?.historyAdmitted != 11 ||
      running?.historyDurable != 9) {
    throw StateError('growth must sample the first actual target immediately');
  }
  // The same observer belongs to the whole lifecycle, not just one batch.
  final nextBatch = growth.observe(
    _queue(
      threads: [
        {'threadId': 'thread-1', 'historyAdmitted': 12, 'historyDurable': 11},
      ],
    ),
    context: 'next batch before completion',
    turnCompleted: false,
  );
  if (nextBatch?.historyAdmitted != 12 || nextBatch?.historyDurable != 11) {
    throw StateError('growth stopped sampling between batches');
  }
  _expectStateError(
    'observed writer disappeared in a later batch',
    () =>
        growth.observe(unrelated, context: 'later batch', turnCompleted: false),
  );
  _expectStateError(
    'completed Turn cannot bypass missing writer',
    () => TimelineHistoryGrowthQueue(threadId: 'thread-1').observe(
      passive,
      context: 'completion before writer observed',
      turnCompleted: true,
    ),
  );
  _expectStateError(
    'missing original identity',
    () => TimelineHistoryGrowthQueue(threadId: ''),
  );
  final malformedQueues = [
    {...passive, 'loaded': false},
    {...passive, 'syncPhase': 'reconnecting'},
    {...passive, 'pendingBytes': null},
    {...passive, 'threads': null},
    _queue(
      threads: [
        {'threadId': 'thread-1', 'historyAdmitted': 11, 'historyDurable': 9},
        {'threadId': 'thread-1', 'historyAdmitted': 11, 'historyDurable': 9},
      ],
    ),
    _queue(
      threads: [
        {
          'threadId': 'thread-1',
          'historyAdmitted': null,
          'historyDurable': null,
        },
      ],
    ),
    _queue(
      threads: [
        {'threadId': 'thread-1', 'historyAdmitted': 9, 'historyDurable': 11},
      ],
    ),
  ];
  for (var index = 0; index < malformedQueues.length; index++) {
    final queue = malformedQueues[index];
    for (final observer in [
      TimelineHistoryGrowthQueue(threadId: 'thread-1'),
      growth,
    ]) {
      _expectStateError(
        'invalid queue $index must not be mistaken for writer startup',
        () => observer.observe(
          queue,
          context: 'invalid queue',
          turnCompleted: false,
        ),
      );
    }
  }
}

Map<String, Object?> _queue({List<Map<String, Object?>>? threads}) => {
  'loaded': true,
  'revision': 1,
  'syncPhase': 'ready',
  'pendingOperations': 0,
  'pendingBytes': 0,
  'inFlightBytes': 0,
  'lastError': null,
  'pressurePaused': false,
  'threads':
      threads ??
      [
        {'threadId': 'thread-1', 'historyAdmitted': 1, 'historyDurable': 1},
      ],
};

Map<String, Object?> _timeline(
  List<Map<String, Object?>> items, {
  int generation = 7,
}) => <String, Object?>{
  'mode': 'history',
  'threadId': 'thread-20k',
  'generation': generation,
  'itemCount': items.length,
  'itemIds': [for (final item in items) item['id']! as String],
  'items': items,
};

Map<String, Object?> _item(String id, {required String text}) =>
    <String, Object?>{
      'id': id,
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
