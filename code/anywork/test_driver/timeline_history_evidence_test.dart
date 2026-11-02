import 'package:flutter_test/flutter_test.dart';

import 'timeline_history_evidence.dart';

void main() {
  test('ordinary G1/text/G2 evidence visits only bounded mounted windows, never synthetic Children', () async {
    final surface = _GroupSurface();
    final evidence = await surface.reader().collect();
    expect(evidence.children, isEmpty);
    expect(evidence.groups.map((group) => group.unitId), ['G1', 'G2']);
    expect(evidence.processItems.map((item) => item.id), [
      'text',
      'G1-last',
      'G1-mid',
      'G1-first',
      'G2-last',
      'G2-mid',
      'G2-first',
    ]);
    expect(surface.actions, [
      'expand:G1:true',
      'read:G1:0',
      'read:G1:1',
      'expand:G1:false',
      'expand:G2:true',
      'read:G2:0',
      'read:G2:1',
      'expand:G2:false',
    ]);
    expect(
      evidence.pages
          .where((page) => page['unitId'] == 'G1')
          .map((page) => page['after']),
      ['cursor:G1', null],
    );
    expect((surface.snapshot['timeline'] as Map)['groups'], isEmpty);
    // New presentation owner, different local key. Locate the original atom via
    // new ordinary UI windows; do not restore the old unit key or opaque cursor.
    surface.reopen();
    surface.actions.clear();
    final shown = await surface.reader().showItem(evidence, 'G1-first');
    expect(surface.actions, [
      'expand:reopened:true',
      'read:reopened:0',
      'read:reopened:1',
    ]);
    expect(
      ((shown['timeline'] as Map)['groups'] as List).single['unitId'],
      'reopened',
    );
  });

  test('ordinary history cannot claim complete evidence on errors, budget or no progress', () async {
    final noActions = _GroupSurface();
    await expectLater(
      noActions.reader(withActions: false).collect(),
      throwsStateError,
    );
    final limited = _GroupSurface();
    await expectLater(limited.reader(maxPages: 1).collect(), throwsStateError);
    final stuck = _GroupSurface()..stuck = true;
    await expectLater(stuck.reader().collect(), throwsStateError);
    expect(
      stuck.actions.where((action) => action.startsWith('read:')).length,
      1,
    );
    final failed = _GroupSurface()..error = '真实读取失败';
    await expectLater(failed.reader().collect(), throwsStateError);
  });

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
        'child-page:a:a-before',
        'record:a',
        'close:a',
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
        surface.actions.where((action) => action == 'child-page:a:a-before'),
        hasLength(1),
      );
      expect(surface.actions, isNot(contains('close:a')));
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
      expect(surface.actions, ['main-page']);
    },
  );

  test(
    'an explicitly remounted business scope uses only its new actual cursor',
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
      surface.mountBusinessScopes();
      final current = await reader.showItem(recorded, 'a-old');
      expect(surface.actions, ['child-page:a:new-child-before']);
      final child = ((current['timeline'] as Map)['children'] as List)
          .cast<Map>()
          .singleWhere((child) => child['parentId'] == 'a');
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
    expect(surface.actions, isNot(contains('close:b')));
  });
}

final class _GroupSurface {
  _GroupSurface() {
    _setMain(['G1', 'text', 'G2']);
  }
  late Map<String, dynamic> snapshot;
  final actions = <String>[];
  String? active;
  int page = 0;
  bool stuck = false;
  String? error;
  bool reopened = false;
  void _setMain(List<String> ids) {
    snapshot = _snapshot(ids);
    final timeline = snapshot['timeline'] as Map;
    timeline['items'] = [
      for (final id in ids)
        {
          ..._item(id),
          'kind': id == 'text' ? 'text' : 'workGroup',
          'atomic': {'loadedCount': 3},
        },
    ];
    timeline['groups'] = <Object?>[];
  }

  void reopen() {
    reopened = true;
    _setMain(['reopened']);
    (snapshot['timeline'] as Map)['generation'] = 8;
  }

  void _display() {
    (snapshot['timeline'] as Map)['groups'] = active == null
        ? <Object?>[]
        : [
            {
              'unitId': active,
              'expanded': true,
              'loading': false,
              'error': error,
              'completionAnchor': page == 0 ? null : 10,
              'before': page == 1 ? 'cursor:$active' : null,
              'items': [
                _item('${reopened ? 'G1' : active}-last'),
                if (page > 0)
                  _item(
                    '${reopened ? 'G1' : active}-${page == 1 ? 'mid' : 'first'}',
                  ),
              ],
            },
          ];
  }

  TimelineHistoryReader reader({int maxPages = 24, bool withActions = true}) =>
      TimelineHistoryReader(
        maxPages: maxPages,
        read: () async => snapshot,
        loadMainOlder: () async => fail('No unloaded Main prefix'),
        closeChildren: (_) async => fail('Work is not a Children parent'),
        loadChildrenOlder: (_) async => fail('Work is not a Children parent'),
        setGroupExpanded: !withActions
            ? null
            : (id, expanded) async {
                actions.add('expand:$id:$expanded');
                active = expanded ? id : null;
                page = 0;
                _display();
              },
        loadGroupEarlier: !withActions
            ? null
            : (id) async {
                expect(id, active);
                actions.add('read:$id:$page');
                if (!stuck) page++;
                _display();
              },
      );
}

class _HistorySurface {
  _HistorySurface({this.pageChange}) {
    mountBusinessScopes();
  }
  final void Function(Map<String, dynamic>)? pageChange;
  final actions = <String>[];
  Map<String, dynamic> snapshot = _snapshot(['turn-b'], before: 'main-before');
  final firstChild = _child('a', ['a-new'], generation: 11, before: 'a-before');
  bool reopening = false;
  void mountBusinessScopes() {
    (snapshot['timeline'] as Map)['children'] = [
      reopening
          ? _child('a', ['a-new'], generation: 31, before: 'new-child-before')
          : firstChild,
      _child('b', ['b-only'], generation: 22),
    ];
  }

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
      mountBusinessScopes();
    },
    loadChildrenOlder: (scope) async {
      actions.add('child-page:${scope.parentId}:${scope.olderCursor}');
      final child = _child(
        'a',
        ['a-old', 'a-new'],
        generation: reopening ? 31 : 11,
        prepends: 1,
      );
      pageChange?.call(child);
      final children = (snapshot['timeline'] as Map)['children'] as List;
      children[children.indexWhere(
            (value) => (value as Map)['parentId'] == scope.parentId,
          )] =
          child;
    },
    closeChildren: (parent) async {
      actions.add('close:$parent');
      if (!retainClosed) {
        ((snapshot['timeline'] as Map)['children'] as List).removeWhere(
          (value) => (value as Map)['parentId'] == parent,
        );
      }
    },
  );
}

Map<String, dynamic> _item(String id) => {
  'id': id,
  'kind': id.startsWith('turn-') ? 'turn' : 'tool',
  'channel': null,
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
    'groups': <Object?>[],
  },
};
