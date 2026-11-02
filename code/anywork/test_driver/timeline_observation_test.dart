import 'package:flutter_test/flutter_test.dart';

import 'cold_start_navigation.dart';
import 'timeline_observation.dart';

void main() {
  test('mounted work windows expose actual typed source and never a synthetic Children parent', () {
    final snapshot = _snapshot([
      {
        ..._item('local-unit', kind: 'workGroup'),
        'atomic': {
          'source': {'kind': 'foregroundTurn', 'turnId': 'real-turn'},
        },
      },
    ]);
    (snapshot['timeline'] as Map)['groups'] = [
      {
        'unitId': 'local-unit',
        'expanded': true,
        'loading': false,
        'completionAnchor': 7,
        'before': 'opaque-cursor',
        'error': null,
        'items': [
          {
            ..._item('opaque-member', kind: 'thinking'),
            'atomic': {
              'source': {'kind': 'foregroundTurn', 'turnId': 'real-turn'},
              'sourceOrder': 3,
              'completionSeq': 7,
            },
          },
        ],
      },
    ];
    final timeline = TimelineObservation.parse(snapshot);
    final member = timeline.expandedItem('opaque-member')!;
    expect(member.foregroundTurnId, 'real-turn');
    expect(member.atomic!['sourceOrder'], 3);
    expect(timeline.groupContainingItem(member.id).unitId, 'local-unit');
    expect(timeline.groupContainingItem(member.id).before, 'opaque-cursor');
    expect(timeline.children, isEmpty);
    (snapshot['timeline'] as Map).remove('groups');
    expect(() => TimelineObservation.parse(snapshot), throwsStateError);
  });

  test('current payload types and body keys are not legacy-mapped', () {
    final timeline = TimelineObservation.parse(
      _snapshot([
        _item('u', channel: 'user'),
        _item('c', channel: 'commentary'),
        _item('f', channel: 'final'),
      ]),
    );
    timeline.requireConsistentIds();
    expect(timeline.items.first.isUserMessage, isTrue);
    expect(timeline.items[1].isCommentary, isTrue);
    expect(timeline.items.last.isFinalAnswer, isTrue);
    expect(timeline.items.last.detail('body')?.totalBytes, 4097);
    expect(timeline.items.last.detail('text'), isNull);
    expect(timeline.items.last.textTruncated, isTrue);
  });

  test(
    'unknown malformed and deferred items stay local with unknown sizes',
    () {
      final timeline = TimelineObservation.parse(
        _snapshot([
          for (final compatibility in ['unknown', 'malformed', 'deferred'])
            {
              ..._item(compatibility, kind: compatibility),
              'compatibility': compatibility,
              'omittedBytes': null,
              'payloadByteLength': null,
              'channel': null,
              'details': <Object?>[],
              'diagnostic': 'fixture diagnostic',
            },
        ]),
      );
      timeline.requireConsistentIds();
      expect(timeline.itemIds, ['unknown', 'malformed', 'deferred']);
      for (final item in timeline.items) {
        expect(item.omittedBytes, isNull);
        expect(item.payloadByteLength, isNull);
        expect(item.isFinalAnswer, isFalse);
        expect(item.diagnostic, 'fixture diagnostic');
      }
    },
  );

  test(
    'window checks preserve real prefix or suffix and reject reordering',
    () {
      TimelineObservation read(List<String> ids, {int generation = 7}) =>
          TimelineObservation.parse(
            _snapshot([
              for (final id in ids) _item(id),
            ], generation: generation),
          );
      final previous = read(['b', 'c']);
      expect(
        read(['b', 'c', 'd']).retainsWindow(previous, prepend: false),
        isTrue,
      );
      expect(
        read(['a', 'b', 'c']).retainsWindow(previous, prepend: true),
        isTrue,
      );
      expect(
        read(['a', 'c', 'b']).retainsWindow(previous, prepend: true),
        isFalse,
      );
      expect(
        read(['b', 'a', 'c']).retainsWindow(previous, prepend: false),
        isFalse,
      );
      expect(
        read(['a', 'b', 'c', 'd']).retainsContiguousWindow(previous),
        isTrue,
      );
      expect(
        read(['a', 'b', 'd', 'c']).retainsContiguousWindow(previous),
        isFalse,
      );
      expect(
        read(['b', 'c'], generation: 8).retainsWindow(previous, prepend: false),
        isFalse,
      );
      expect(() => read(['b', 'b']).requireConsistentIds(), throwsStateError);
    },
  );

  test(
    'missing channel and non-integral generation are observation failures',
    () {
      final missing = _item('a')..remove('channel');
      expect(
        () => TimelineObservation.parse(_snapshot([missing])),
        throwsStateError,
      );
      final snapshot = _snapshot([_item('a')]);
      (snapshot['timeline'] as Map)['generation'] = 7.5;
      expect(() => TimelineObservation.parse(snapshot), throwsStateError);
    },
  );

  test('Children retain their own controller order and acceptance counts', () {
    final snapshot = _snapshot([
      _item('turn-a', kind: 'turn'),
      _item('turn-b', kind: 'turn'),
    ]);
    (snapshot['timeline'] as Map)['children'] = [
      _children('parent-a', ['a2', 'a1'], generation: 31),
      _children('parent-b', ['b1'], generation: 12),
    ];
    final timeline = TimelineObservation.parse(snapshot);
    expect(timeline.itemIds, ['turn-a', 'turn-b']);
    expect(timeline.childrenFor('parent-a')!.itemIds, ['a2', 'a1']);
    expect(timeline.childrenContaining('b1').generation, 12);
    expect(timeline.childrenFor('parent-a')!.appliedSets, 1);
    expect(timeline.childrenFor('parent-a')!.appliedPrepends, 2);
    expect(timeline.childrenFor('parent-a')!.appliedAppends, 3);
    expect(timeline.item('a2'), isNull);
    expect(timeline.expandedItem('a2')!.id, 'a2');
  });

  test(
    'identity growth requires real operation acceptance in the same lease',
    () {
      final before = TimelineObservation.parse(
        _snapshot([_item('b'), _item('c')]),
      );
      final append = _snapshot([_item('b'), _item('c'), _item('d')]);
      expect(
        () =>
            TimelineObservation.parse(append)
                .requireAcceptedOperation(before, prepend: false),
        throwsStateError,
      );
      (append['timeline'] as Map)['appliedAppends'] = 1;
      TimelineObservation.parse(append)
          .requireAcceptedOperation(before, prepend: false);
      final prepend = _snapshot([_item('a'), _item('b'), _item('c')]);
      (prepend['timeline'] as Map)['appliedPrepends'] = 1;
      TimelineObservation.parse(prepend)
          .requireAcceptedOperation(before, prepend: true);
      final middle = _snapshot([_item('b'), _item('middle'), _item('c')]);
      (middle['timeline'] as Map)['appliedPrepends'] = 1;
      TimelineObservation.parse(middle)
          .requireAcceptedOperation(before, prepend: true);
      final reordered = _snapshot([_item('c'), _item('middle'), _item('b')]);
      (reordered['timeline'] as Map)['appliedPrepends'] = 1;
      expect(
        () =>
            TimelineObservation.parse(reordered)
                .requireAcceptedOperation(before, prepend: true),
        throwsStateError,
      );
      (prepend['timeline'] as Map)['appliedSets'] = 2;
      expect(
        () =>
            TimelineObservation.parse(prepend)
                .requireAcceptedOperation(before, prepend: true),
        throwsStateError,
      );
    },
  );

  test('Children reject duplicated ids and inconsistent count or order', () {
    for (final child in [
      _children('p', ['a', 'a']),
      _children('p', ['a'])..['loadedCount'] = 2,
      _children('p', ['a', 'b'])..['itemIds'] = ['b', 'a'],
    ]) {
      final snapshot = _snapshot([_item('turn', kind: 'turn')]);
      (snapshot['timeline'] as Map)['children'] = [child];
      expect(() => TimelineObservation.parse(snapshot), throwsStateError);
    }
  });

  test('layout measures the same clock and current Main identity', () {
    final snapshot = _snapshot([_item('main')]);
    final layout = <String, dynamic>{
      'selectionId': 4,
      'generation': 7,
      'itemId': 'main',
      'selectionStartedMicros': 1000000,
      'layoutCompletedMicros': 1123456,
      'elapsedMicros': 123456,
    };
    (snapshot['timeline'] as Map)['firstContentLayout'] = layout;
    final value = TimelineObservation.parse(snapshot).firstContentLayout!;
    expect(value.elapsedMicros, 123456);
    expect(value.toJson(), layout);
    for (final invalid in [
      {...layout, 'generation': 8},
      {...layout, 'itemId': 'child-only'},
      {...layout, 'elapsedMicros': 123455},
      {...layout, 'selectionStartedMicros': -1},
    ]) {
      (snapshot['timeline'] as Map)['firstContentLayout'] = invalid;
      expect(() => TimelineObservation.parse(snapshot), throwsStateError);
    }
    (snapshot['timeline'] as Map)['firstContentLayout'] = null;
    expect(TimelineObservation.parse(snapshot).firstContentLayout, isNull);
  });

  for (final openingField in [
    'visibleThreadId',
    'presentationThreadId',
    'timeline',
  ]) {
    test(
      'cold restore does not replay an open indicated by $openingField',
      () async {
        final loading = _snapshot([_item('a')], ready: false);
        if (openingField != 'timeline') loading['timeline'] = null;
        loading['timelineScroll'] = null;
        (loading['navigation'] as Map)[openingField] = 'thread';
        var reads = 0;
        var taps = 0;
        final evidence = await restoreColdStartTarget(
          ColdStartDriverSurface(
            readSnapshot: () async =>
                reads++ == 0 ? loading : _snapshot([_item('a')]),
            tap: (_, _) async {
              taps++;
            },
          ),
          identity: const ColdStartIdentity(
            workspaceId: 'project',
            threadId: 'thread',
          ),
          phase: 'test',
          onStage: (_) async {},
          budget: const Duration(seconds: 2),
        );
        expect(taps, 0);
        expect(evidence['evidenceConsistent'], isTrue);
        expect(evidence['tapAttempts'], 0);
      },
    );
  }

  test(
    'selected but unopened cold target still uses the real open entry',
    () async {
      final unopened = _snapshot([_item('a')])..['timeline'] = null;
      unopened['timelineScroll'] = null;
      var taps = 0;
      await restoreColdStartTarget(
        ColdStartDriverSurface(
          readSnapshot: () async =>
              taps == 0 ? unopened : _snapshot([_item('a')]),
          tap: (_, _) async {
            taps++;
          },
        ),
        identity: const ColdStartIdentity(
          workspaceId: 'project',
          threadId: 'thread',
        ),
        phase: 'test',
        onStage: (_) async {},
        budget: const Duration(seconds: 2),
      );
      expect(taps, 1);
    },
  );
}

Map<String, dynamic> _item(
  String id, {
  String kind = 'text',
  String? channel,
}) => {
  'id': id,
  'kind': kind,
  'channel': channel,
  'compatibility': 'current',
  'sealedAt': null,
  'omittedBytes': 4096,
  'payloadByteLength': 100,
  'status': 'completed',
  'text': 'a',
  'attachments': <Object?>[],
  'details': [
    {
      'field': 'body',
      'totalBytes': 4097,
      'previewBytes': 1,
      'hasReference': true,
    },
  ],
};

Map<String, dynamic> _children(
  String parentId,
  List<String> ids, {
  int generation = 3,
}) => {
  'parentId': parentId,
  'generation': generation,
  'ready': true,
  'loadedCount': ids.length,
  'olderCursor': null,
  'loadingOlder': false,
  'error': null,
  'appliedSets': 1,
  'appliedPrepends': 2,
  'appliedAppends': 3,
  'itemIds': ids,
  'items': [for (final id in ids) _item(id, kind: 'tool')],
};

Map<String, dynamic> _snapshot(
  List<Map<String, dynamic>> items, {
  int generation = 7,
  bool ready = true,
}) => {
  'navigation': {'selectedProjectId': 'project', 'selectedThreadId': 'thread'},
  'workspace': {'workspaceId': 'project', 'threadId': 'thread'},
  'project': {'id': 'project', 'path': '/fixture'},
  'timeline': {
    'children': <Object?>[],
    'groups': <Object?>[],
    'appliedSets': ready ? 1 : 0,
    'appliedPrepends': 0,
    'appliedAppends': 0,
    'firstContentLayout': null,
    'threadId': 'thread',
    'generation': generation,
    'ready': ready,
    'mode': 'live',
    'connection': 'ready',
    'loadedCount': items.length,
    'itemCount': items.length,
    'itemIds': [for (final item in items) item['id']],
    'items': items,
    'olderCursor': null,
    'hasOlder': false,
    'loadingOlder': false,
    'olderError': null,
    'olderErrorCode': null,
    'olderErrorCorrelationId': null,
    'hasNewOutput': false,
  },
  'timelineScroll': {
    'threadId': 'thread',
    'generation': generation,
    'pixels': 0,
    'minScrollExtent': 0,
    'maxScrollExtent': 0,
    'viewportDimension': 600,
    'extentBefore': 0,
    'extentAfter': 0,
    'atLiveEdge': true,
    'isScrolling': false,
  },
};
