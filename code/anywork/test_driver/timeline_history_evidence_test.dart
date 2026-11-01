import 'package:flutter_test/flutter_test.dart';

import 'timeline_history_evidence.dart';

void main() {
  test(
    'collects each scope to explicit EOF and records before closing it',
    () async {
      final surface = _HistorySurface();
      final scopes = <String, List<String>>{};
      final evidence = await surface.reader().collect(
        onScope: (main, child) async {
          expect(main.hasOlder, isFalse);
          expect(child.olderCursor, isNull);
          scopes[child.parentId] = child.itemIds;
          surface.actions.add('record:${child.parentId}');
        },
      );
      expect(surface.actions, [
        'main-page',
        'open:a',
        'child-page:a:a-before',
        'record:a',
        'close:a',
        'open:b',
        'record:b',
        'close:b',
      ]);
      expect(scopes, {
        'a': ['a-old', 'a-new'],
        'b': ['b-only'],
      });
      expect(evidence.main.itemIds, ['turn-a', 'turn-b']);
      expect(evidence.children.map((scope) => scope.generation), [11, 22]);
      expect((surface.snapshot['timeline'] as Map)['children'], isEmpty);
      // The earlier scope has retired, yet its immutable test evidence remains.
      expect(evidence.scopeContaining('a-old').itemIds, ['a-old', 'a-new']);
      expect(evidence.pages.map((page) => page['before']), [
        'main-before',
        'a-before',
      ]);
      expect(evidence.pages.map((page) => page['after']), [null, null]);
      expect(evidence.pages.last['scopeGeneration'], 11);
      expect(evidence.pages.last['prependedIds'], ['a-old']);
    },
  );

  test('missing cursor fields and typed errors cannot mean EOF', () async {
    for (final mutate in <void Function(_HistorySurface)>[
      (surface) => (surface.snapshot['timeline'] as Map).remove('olderCursor'),
      (surface) => surface.firstChild.remove('olderCursor'),
      (surface) => surface.firstChild['error'] = 'staleContent',
      (surface) =>
          (((surface.snapshot['timeline'] as Map)['items'] as List).single
                  as Map)['compatibility'] =
              'deferred',
      (surface) =>
          (surface.snapshot['timeline'] as Map)['olderErrorCode'] = 'storage',
    ]) {
      final surface = _HistorySurface();
      mutate(surface);
      await expectLater(surface.reader().collect(), throwsStateError);
      expect(surface.actions, isNot(contains('close:a')));
    }
  });

  test(
    'rejects generation replacement without rebinding an old before cursor',
    () async {
      final surface = _HistorySurface(
        pageChange: (child) => child['generation'] = 12,
      );
      await expectLater(surface.reader().collect(), throwsStateError);
      expect(
        surface.actions.where((action) => action == 'open:a'),
        hasLength(1),
      );
      expect(surface.actions, isNot(contains('open:b')));
    },
  );

  test(
    'a successful Prepend must retain order, data and advance its cursor',
    () async {
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (child) => child['olderCursor'] = 'a-before',
        (child) {
          child['itemIds'] = ['a-new', 'a-old'];
          child['items'] = [_item('a-new'), _item('a-old')];
        },
        (child) => ((child['items'] as List).last as Map)['text'] = 'changed',
        (child) {
          child['itemIds'] = ['a-new', 'a-new'];
          child['items'] = [_item('a-new'), _item('a-new')];
        },
      ]) {
        final surface = _HistorySurface(pageChange: mutate);
        await expectLater(surface.reader().collect(), throwsStateError);
        expect(surface.actions, isNot(contains('close:a')));
      }
    },
  );

  test(
    'Main and Children share the original finite page-request budget',
    () async {
      final surface = _HistorySurface();
      await expectLater(
        surface.reader(maxPages: 1).collect(),
        throwsStateError,
      );
      expect(surface.actions, ['main-page', 'open:a']);
    },
  );

  test(
    'reopening locates the Main parent then uses only the new scope cursor',
    () async {
      final surface = _HistorySurface();
      final reader = surface.reader();
      final recorded = await reader.collect();
      surface.actions.clear();
      surface.reopening = true;
      surface.snapshot = _snapshot(
        ['turn-b'],
        before: 'new-main-before',
        generation: 8,
      );
      final current = await reader.showItem(recorded, 'a-old');
      expect(surface.actions, [
        'main-page',
        'open:a',
        'child-page:a:new-child-before',
      ]);
      final child =
          ((current['timeline'] as Map)['children'] as List).single as Map;
      expect(child['generation'], 31);
      expect(child['itemIds'], ['a-old', 'a-new']);
    },
  );

  test('a close must revoke the actual Children registration', () async {
    final surface = _HistorySurface();
    await expectLater(
      surface.reader(retainClosed: true).collect(),
      throwsStateError,
    );
    expect(surface.actions, isNot(contains('open:b')));
  });
}

class _HistorySurface {
  _HistorySurface({this.pageChange});
  final void Function(Map<String, dynamic>)? pageChange;
  final actions = <String>[];
  Map<String, dynamic> snapshot = _snapshot(['turn-b'], before: 'main-before');
  final firstChild = _child('a', ['a-new'], generation: 11, before: 'a-before');
  bool reopening = false;

  TimelineHistoryReader reader({
    int maxPages = 24,
    bool retainClosed = false,
  }) => TimelineHistoryReader(
    maxPages: maxPages,
    read: () async => snapshot,
    loadMainOlder: () async {
      actions.add('main-page');
      snapshot = _snapshot(
        ['turn-a', 'turn-b'],
        prepends: 1,
        generation: reopening ? 8 : 7,
      );
    },
    openChildren: (parent) async {
      actions.add('open:$parent');
      final child = parent == 'a'
          ? reopening
                ? _child(
                    'a',
                    ['a-new'],
                    generation: 31,
                    before: 'new-child-before',
                  )
                : firstChild
          : _child('b', ['b-only'], generation: 22);
      // A single real display is present, as with a lazy parent viewport.
      (snapshot['timeline'] as Map)['children'] = [child];
    },
    loadChildrenOlder: (turn, scope) async {
      expect(turn.childrenParentId, scope.parentId);
      actions.add('child-page:${scope.parentId}:${scope.olderCursor}');
      final child = _child(
        'a',
        ['a-old', 'a-new'],
        generation: reopening ? 31 : 11,
        prepends: 1,
      );
      pageChange?.call(child);
      (snapshot['timeline'] as Map)['children'] = [child];
    },
    closeChildren: (parent) async {
      actions.add('close:$parent');
      if (!retainClosed) {
        (snapshot['timeline'] as Map)['children'] = <Object?>[];
      }
    },
  );
}

Map<String, dynamic> _item(String id) => {
  'id': id,
  'kind': id.startsWith('turn-') ? 'turn' : 'tool',
  'channel': null,
  'childrenParentId': id == 'turn-a'
      ? 'a'
      : id == 'turn-b'
      ? 'b'
      : null,
  'compatibility': 'current',
  'sealedAt': null,
  'omittedBytes': null,
  'payloadByteLength': 120,
  'status': 'completed',
  'text': id,
  'attachments': <Object?>[],
  'details': <Object?>[],
};

Map<String, dynamic> _child(
  String parent,
  List<String> ids, {
  required int generation,
  String? before,
  int prepends = 0,
}) => {
  'parentId': parent,
  'generation': generation,
  'ready': true,
  'loadedCount': ids.length,
  'olderCursor': before,
  'loadingOlder': false,
  'error': null,
  'appliedSets': 1,
  'appliedPrepends': prepends,
  'appliedAppends': 0,
  'itemIds': ids,
  'items': [for (final id in ids) _item(id)],
};

Map<String, dynamic> _snapshot(
  List<String> ids, {
  String? before,
  int generation = 7,
  int prepends = 0,
}) => {
  'timeline': {
    'threadId': 'thread',
    'generation': generation,
    'ready': true,
    'mode': 'history',
    'connection': 'ready',
    'loadedCount': ids.length,
    'itemCount': ids.length,
    'itemIds': ids,
    'items': [for (final id in ids) _item(id)],
    'olderCursor': before,
    'hasOlder': before != null,
    'loadingOlder': false,
    'olderError': null,
    'olderErrorCode': null,
    'olderErrorCorrelationId': null,
    'hasNewOutput': false,
    'appliedSets': 1,
    'appliedPrepends': prepends,
    'appliedAppends': 0,
    'firstContentLayout': null,
    'children': <Object?>[],
  },
};
