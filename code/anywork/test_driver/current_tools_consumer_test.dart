import 'dart:convert';

import 'package:anywork/src/shared/studio_driver_key_values.dart';
import 'package:flutter_test/flutter_test.dart';

import 'current_tools_driver.dart';
import 'current_tools_observation.dart';

// ThreadActivityToolEntry + ThreadWaitPresentation serde, not a Chat envelope.
const _producerWait =
    r'''{"callId":"original-call","name":"wait","summary":"等待工具","arguments":"opaque","state":"running","wait":{"intent":{"kind":"events","data":{"targets":[{"taskId":"task:sleep","status":"running"},{"taskId":"task:exec","toolName":"exec","summaryTruncated":true,"status":"running"}],"timeoutMs":300000}},"state":"waiting"}}''';
const _producerTimer =
    r'''{"callId":"timer-call","taskId":"task:timer","name":"sleep","summary":"sleep","arguments":"opaque","state":"running","wait":{"intent":{"kind":"timer","data":{"durationMs":1000}},"state":"waiting"}}''';

void main() {
  test(
    'reads exact producer Waiting, optional facts and distinct entry identity',
    () {
      final view = _parse(_snapshot());
      final tool = view.toolByCallId('original-call')!;
      expect(tool.entry.id, 'visible-entry');
      expect(tool.callId, 'original-call');
      expect(tool.evidence().containsKey('itemId'), isFalse);
      expect(tool.ordinal, isNull);
      expect(tool.startedAt, isNull);
      expect(tool.taskId, isNull);
      expect(tool.arguments, 'opaque');
      expect(tool.waiting, isTrue);
      expect(tool.wait!.kind, 'events');
      expect(tool.wait!.timeoutMs, 300000);
      expect(tool.wait!.messagesReady, isNull);
      expect(tool.wait!.target('task:sleep')!.toolName, isNull);
      expect(tool.wait!.target('task:sleep')!.summaryTruncated, isFalse);
      expect(tool.wait!.target('task:exec')!.summaryTruncated, isTrue);
      expect(tool.wait!.target('task:sleep')!.status, 'running');
      expect(tool.wait!.target('task:sleep-prefix'), isNull);
      expect(tool.wait!.targetsRunning(['task:sleep', 'task:exec']), isTrue);
      expect(tool.wait!.targetsRunning(['task:sleep']), isFalse);
      expect(
        tool.wait!.targetsRunning(['task:sleep-prefix', 'task:exec']),
        isFalse,
      );
      expect(tool.wait!.targetsRunning([null, 'task:exec']), isFalse);
    },
  );

  test('same named wait or sleep without typed wait remains unknown', () {
    for (final name in ['wait', 'sleep']) {
      final raw = jsonEncode({
        'callId': 'call',
        'name': name,
        'summary': name,
        'arguments': 'unavailable',
        'state': 'running',
      });
      final tool = _parse(_snapshot(entries: [_entry(raw: raw)]))
          .toolByCallId('call')!;
      expect(tool.wait, isNull);
      expect(tool.waiting, isFalse);
    }
    final timer = _parse(_snapshot(entries: [_entry(raw: _producerTimer)]))
        .toolByCallId('timer-call')!;
    expect(timer.waiting, isTrue);
    expect(timer.wait!.kind, 'timer');
    expect(timer.wait!.durationMs, 1000);
    expect(timer.wait!.timeoutMs, isNull);
  });

  test('Ready and timeout keep the actual target snapshot and unknowns', () {
    final source = jsonDecode(_producerWait) as Map<String, dynamic>;
    final wait = source['wait'] as Map;
    wait['state'] = 'ready';
    wait['messagesReady'] = true;
    final ready = _parse(_snapshot(entries: [_entry(raw: jsonEncode(source))]))
        .toolByCallId('original-call')!;
    expect(ready.waiting, isFalse);
    expect(ready.wait!.state, 'ready');
    expect(ready.wait!.messagesReady, isTrue);
    expect(ready.wait!.targetsRunning(['task:sleep', 'task:exec']), isFalse);
    // A message can wake wait while every named target still runs.
    expect(
      ready.wait!.targets.every((target) => target.status == 'running'),
      isTrue,
    );
    wait.remove('messagesReady');
    wait['state'] = 'timedOut';
    final timedOut = _parse(
      _snapshot(entries: [_entry(raw: jsonEncode(source))]),
    ).toolByCallId('original-call')!;
    expect(timedOut.wait!.state, 'timedOut');
    expect(timedOut.wait!.messagesReady, isNull);
    final targets = ((wait['intent'] as Map)['data'] as Map)['targets'] as List;
    (targets.first as Map).remove('status');
    wait['state'] = 'waiting';
    final unknown = _parse(
      _snapshot(entries: [_entry(raw: jsonEncode(source))]),
    ).toolByCallId('original-call')!;
    expect(unknown.wait!.target('task:sleep')!.status, isNull);
    expect(unknown.wait!.targetsRunning(['task:sleep', 'task:exec']), isFalse);
  });

  test('only an expanded admitted page can supply current tools', () {
    expect(CurrentToolsObservation.optional({'timeline': null}), isNull);
    final retired = _snapshot();
    (retired['timeline'] as Map)['current'] = null;
    expect(CurrentToolsObservation.optional(retired), isNull);
    final closed = _parse(_snapshot(expanded: false, collection: false));
    expect(() => closed.toolByCallId('original-call'), throwsStateError);
    expect(() => _parse(_snapshot(expanded: false)), throwsStateError);
    final errored = _parse(_snapshot(error: 'database unavailable'));
    expect(() => errored.toolByCallId('original-call'), throwsStateError);
    expect(() => _parse(_snapshot(ready: false)), throwsStateError);
  });

  test('signed positions use the producer position/id tuple order', () {
    final entries = [
      _entry(id: 'a', position: -2),
      _entry(id: '\uE000', position: -2),
      _entry(id: '\u{10000}', position: -2),
      _entry(id: 'later', position: -1),
    ];
    final page = _parse(_snapshot(entries: entries)).collection!;
    expect(page.entries.map((entry) => entry.position), [-2, -2, -2, -1]);
    expect(page.entries.map((entry) => entry.id), [
      'a',
      '\uE000',
      '\u{10000}',
      'later',
    ]);
    expect(
      () => _parse(
        _snapshot(entries: [entries[0], entries[2], entries[1], entries[3]]),
      ),
      throwsStateError,
    );
    expect(
      () => _parse(_snapshot(entries: [entries[0], entries[0]])),
      throwsStateError,
    );
  });

  test('malformed producer payload or byte lengths cannot become success', () {
    expect(
      () =>
          _parse(_snapshot(entries: [_entry(raw: '{"type":"tool","data":{}}')]))
              .toolByCallId('original-call'),
      throwsStateError,
    );
    expect(
      () =>
          _parse(_snapshot(entries: [_entry(raw: '{broken')]))
              .toolByCallId('original-call'),
      throwsFormatException,
    );
    final wrongLength = _entry()
      ..['payload'] = {
        'kind': 'inline',
        'byteLength': 1,
        'base64': base64Encode([1, 2]),
      };
    expect(() => _parse(_snapshot(entries: [wrongLength])), throwsStateError);
    final unknown = jsonDecode(_producerWait) as Map<String, dynamic>;
    unknown['arguments'] = 'guessedArgs';
    expect(
      () =>
          _parse(_snapshot(entries: [_entry(raw: jsonEncode(unknown))]))
              .toolByCallId('original-call'),
      throwsStateError,
    );
    final flat = jsonDecode(_producerWait) as Map<String, dynamic>;
    (flat['wait'] as Map)['intent'] = {
      'kind': 'events',
      'targets': <Object?>[],
      'timeoutMs': 1,
    };
    expect(
      () =>
          _parse(_snapshot(entries: [_entry(raw: jsonEncode(flat))]))
              .toolByCallId('original-call'),
      throwsStateError,
    );
    final nullBoolean = jsonDecode(_producerWait) as Map<String, dynamic>;
    final target =
        (((nullBoolean['wait'] as Map)['intent'] as Map)['data']
                as Map)['targets']
            as List;
    (target.first as Map)['summaryTruncated'] = null;
    expect(
      () =>
          _parse(_snapshot(entries: [_entry(raw: jsonEncode(nullBoolean))]))
              .toolByCallId('original-call'),
      throwsStateError,
    );
  });

  test(
    'Deferred is unresolved until a matching complete visible window exists',
    () {
      final view = _parse(_snapshot(entries: [_deferred()]));
      expect(view.decode(view.collection!.entries.single), isNull);
      for (final window in [
        _window(reference: {'different': 'reference'}),
        _window(offset: 1),
        _window(sealed: false),
      ]) {
        final partial = _parse(
          _snapshot(entries: [_deferred()], windows: [window]),
        );
        expect(partial.decode(partial.collection!.entries.single), isNull);
      }
      final shown = _parse(
        _snapshot(entries: [_deferred()], windows: [_window()]),
      );
      final decoded = shown.decode(shown.collection!.entries.single)!;
      expect(decoded.waiting, isTrue);
      expect(decoded.windowGeneration, 55);
      final failure = _parse(
        _snapshot(
          entries: [_deferred()],
          windows: [
            {..._window(), 'error': 'staleContent'},
          ],
        ),
      );
      expect(
        () => failure.decode(failure.collection!.entries.single),
        throwsStateError,
      );
    },
  );

  test('every owner/ref/display generation is part of the qualification', () {
    final original = _parse(_snapshot());
    for (final changed in [
      _snapshot(mainGeneration: 8),
      _snapshot(turnId: 'new-turn'),
      _snapshot(childrenParentId: 'other-parent'),
      _snapshot(activityId: 'new-activity'),
      _snapshot(databaseId: 'new-db'),
      _snapshot(revision: 8),
      _snapshot(generation: 2),
    ]) {
      expect(
        () => _parse(changed).requireSame(original),
        throwsA(isA<StaleCurrentTools>()),
      );
    }
  });

  test(
    'completed members require the observed parent without deriving one',
    () async {
      final missing = _snapshot(childrenParentId: null);
      final view = _parse(missing);
      expect(view.childrenParentId, isNull);
      expect(view.requireChildrenParentId, throwsStateError);
      final ui = _ScriptedUi(missing);
      await expectLater(
        ui.driver.openCompletedItems(turnId: 'turn'),
        throwsStateError,
      );
      expect(ui.actions, isEmpty);
      final absent = _snapshot();
      ((absent['timeline'] as Map)['current'] as Map).remove(
        'childrenParentId',
      );
      expect(_parse(absent).childrenParentId, isNull);
    },
  );

  test(
    'completed members open the actual parent once and never collapse it',
    () async {
      final ui = _ScriptedUi(_snapshot(expanded: false, collection: false));
      ui.completedExpanded = false;
      final key = StudioDriverKeyValues.currentCompletedItems('parent');
      ui.onTap = (target) {
        if (target == 'conversation-activity') {
          ui.snapshot = _snapshot(collection: false);
        } else {
          expect(target, key);
          ui.completedExpanded = true;
        }
      };
      final opened = await ui.driver.openCompletedItems(turnId: 'turn');
      expect(opened.requireChildrenParentId(), 'parent');
      await ui.driver.openCompletedItems(turnId: 'turn');
      expect(ui.actions, ['conversation-activity', key]);
    },
  );

  test(
    'a changed parent cannot admit the original completed disclosure',
    () async {
      final ui = _ScriptedUi(_snapshot(collection: false));
      ui.completedExpanded = false;
      ui.onTap = (_) {
        ui.snapshot = _snapshot(
          collection: false,
          childrenParentId: 'replacement-parent',
        );
      };
      await expectLater(
        ui.driver.openCompletedItems(turnId: 'turn'),
        throwsA(isA<StaleCurrentTools>()),
      );
      expect(ui.actions, [
        StudioDriverKeyValues.currentCompletedItems('parent'),
      ]);
    },
  );

  test(
    'an already open activity collection and entry are not tapped closed',
    () async {
      final ui = _ScriptedUi(_snapshot());
      final view = await ui.driver.openTools(turnId: 'turn');
      final tool = await ui.driver.inspect(
        view,
        view.collection!.entries.single,
      );
      expect(tool.waiting, isTrue);
      expect(ui.actions, isEmpty);
      expect(ui.textReads, 1);
    },
  );

  test(
    'explicitly opens only the real activity collection and entry controls',
    () async {
      final ui = _ScriptedUi(_snapshot(expanded: false, collection: false));
      ui.entryExpanded = false;
      ui.onTap = (key) {
        if (key == 'conversation-activity') {
          ui.snapshot = _snapshot(collection: false);
        } else if (key == StudioDriverKeyValues.currentCollection('tools')) {
          ui.snapshot = _snapshot();
        } else {
          expect(
            key,
            StudioDriverKeyValues.currentCollectionEntry(
              'tools',
              'visible-entry',
            ),
          );
          ui.entryExpanded = true;
        }
      };
      final view = await ui.driver.openTools(turnId: 'turn');
      await ui.driver.inspect(view, view.collection!.entries.single);
      expect(ui.actions, [
        'conversation-activity',
        StudioDriverKeyValues.currentCollection('tools'),
        StudioDriverKeyValues.currentCollectionEntry('tools', 'visible-entry'),
      ]);
    },
  );

  test(
    'a revision change during entry expansion rejects the old evidence',
    () async {
      for (final replacement in [
        _snapshot(revision: 8),
        _snapshot(
          entries: [_entry(raw: _producerWait.replaceFirst('等待工具', '不同工具'))],
        ),
      ]) {
        final ui = _ScriptedUi(_snapshot());
        ui.entryExpanded = false;
        ui.onTap = (_) => ui.snapshot = replacement;
        final original = _parse(ui.snapshot);
        await expectLater(
          ui.driver.inspect(original, original.collection!.entries.single),
          throwsA(isA<StaleCurrentTools>()),
        );
        expect(ui.textReads, 0);
      }
    },
  );

  test(
    'retirement and a changed display reject Next before any cursor action',
    () async {
      for (final replacement in [
        {'timeline': null},
        _snapshot(generation: 2),
        _snapshot(revision: 8),
      ]) {
        final ui = _ScriptedUi(_snapshot(continuation: 'old-cursor'));
        final original = _parse(ui.snapshot);
        ui.snapshot = replacement;
        await expectLater(
          ui.driver.next(original),
          throwsA(isA<StaleCurrentTools>()),
        );
        expect(ui.actions, isEmpty);
      }
    },
  );

  test(
    'a retired display cannot publish a replacement as the pending Next',
    () async {
      final ui = _ScriptedUi(_snapshot(continuation: 'cursor'));
      final original = _parse(ui.snapshot);
      ui.onTap = (_) {
        ui.snapshot = _snapshot(
          generation: 4,
          entries: [
            _entry(id: 'other-display-entry', position: 1, raw: _producerTimer),
          ],
        );
      };
      await expectLater(
        ui.driver.next(original),
        throwsA(isA<StaleCurrentTools>()),
      );
      expect(ui.actions, [
        StudioDriverKeyValues.currentCollectionNext('tools'),
      ]);
    },
  );

  test(
    'Next replaces the visible page using the same ref and a new generation',
    () async {
      final ui = _ScriptedUi(
        _snapshot(
          continuation: 'cursor',
          entries: [_entry(id: 'first-entry', position: -2)],
        ),
      );
      final original = _parse(ui.snapshot);
      ui.onTap = (key) {
        expect(key, StudioDriverKeyValues.currentCollectionNext('tools'));
        ui.snapshot = _snapshot(
          generation: 2,
          entries: [
            _entry(id: 'next-entry', position: -2, raw: _producerTimer),
          ],
        );
      };
      final next = await ui.driver.next(original);
      expect(next.collection!.entries.map((entry) => entry.id), ['next-entry']);
      expect(next.toolByCallId('original-call'), isNull);
      expect(next.toolByCallId('timer-call')!.wait!.kind, 'timer');
    },
  );

  test(
    'a collection not present yet remains unknown without phantom controls',
    () async {
      final actions = <String>[];
      final driver = CurrentToolsDriver(
        read: () async => _snapshot(collection: false),
        tap: (key) async {
          actions.add(key);
        },
        observe: (_) async => {'mounted': false},
        readEntryText: (_) async => throw StateError('No entry is displayed'),
      );
      await expectLater(
        driver.openTools(
          turnId: 'turn',
          timeout: const Duration(milliseconds: 1),
        ),
        throwsA(isA<CurrentToolsNotReady>()),
      );
      expect(actions, isEmpty);
    },
  );

  test('an original Deferred window generation cannot be rebound', () async {
    final original = _parse(
      _snapshot(entries: [_deferred()], windows: [_window()]),
    );
    final changed = _window();
    (changed['window'] as Map)['generation'] = 56;
    final ui = _ScriptedUi(
      _snapshot(entries: [_deferred()], windows: [changed]),
    );
    await expectLater(
      ui.driver.inspect(original, original.collection!.entries.single),
      throwsA(isA<StaleCurrentTools>()),
    );
    expect(ui.actions, isEmpty);
  });

  test(
    'only a public stale reload is used and read errors are not retried',
    () async {
      final stale = _ScriptedUi(_snapshot(ready: false, entries: []));
      stale.reloadVisible = true;
      stale.onTap = (key) {
        expect(key, StudioDriverKeyValues.currentCollectionReload('tools'));
        stale.snapshot = _snapshot(generation: 3);
      };
      await stale.driver.openTools(turnId: 'turn');
      expect(stale.actions, [
        StudioDriverKeyValues.currentCollectionReload('tools'),
      ]);
      final error = _ScriptedUi(_snapshot(error: 'real storage error'));
      error.reloadVisible = true;
      await expectLater(
        error.driver.openTools(turnId: 'turn'),
        throwsStateError,
      );
      expect(error.actions, isEmpty);
    },
  );

  test(
    'Deferred inspection uses the public range control and never fakes a page',
    () async {
      for (final alreadyExpanded in [false, true]) {
        final ui = _ScriptedUi(_snapshot(entries: [_deferred()]));
        ui.rangeExpanded = alreadyExpanded;
        final original = _parse(ui.snapshot);
        await expectLater(
          ui.driver.inspect(
            original,
            original.collection!.entries.single,
            timeout: const Duration(milliseconds: 1),
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('Deferred'),
            ),
          ),
        );
        expect(
          ui.actions,
          alreadyExpanded
              ? isEmpty
              : [
                  StudioDriverKeyValues.timelineContentOpen(
                    'visible-entry',
                    'payload',
                  ),
                ],
        );
        expect(ui.textReads, 0);
      }
    },
  );
}

/// Static UI responses at the Driver boundary; no SDK/production State machine
/// is simulated and these tests make no component lifecycle claim.
class _ScriptedUi {
  _ScriptedUi(this.snapshot);
  Map<String, dynamic> snapshot;
  final actions = <String>[];
  bool entryExpanded = true, reloadVisible = false, rangeExpanded = false;
  bool completedExpanded = true;
  int textReads = 0;
  void Function(String)? onTap;
  CurrentToolsDriver get driver => CurrentToolsDriver(
    read: () async => snapshot,
    tap: (key) async {
      actions.add(key);
      onTap?.call(key);
    },
    observe: (key) async => {
      'rangeExpanded': rangeExpanded,
      'mounted': key == StudioDriverKeyValues.currentCollectionReload('tools')
          ? reloadVisible
          : !key.startsWith('timeline-content-window:'),
      'expanded': key == StudioDriverKeyValues.currentCompletedItems('parent')
          ? completedExpanded
          : key ==
                StudioDriverKeyValues.currentCollectionEntry(
                  'tools',
                  'visible-entry',
                )
          ? entryExpanded
          : false,
    },
    readEntryText: (_) async {
      textReads++;
      return ['visible-entry', _producerWait];
    },
  );
}

CurrentToolsObservation _parse(Map<String, dynamic> snapshot) =>
    CurrentToolsObservation.optional(snapshot)!;
Map<String, dynamic> _entry({
  String id = 'visible-entry',
  int position = 0,
  String raw = _producerWait,
}) {
  final bytes = utf8.encode(raw);
  return {
    'id': id,
    'position': position,
    'payload': {
      'kind': 'inline',
      'byteLength': bytes.length,
      'base64': base64Encode(bytes),
    },
  };
}

final _reference = <String, dynamic>{
  'databaseId': 'db',
  'target': {
    'kind': 'body',
    'key': 'payload',
    'owner': {
      'kind': 'current',
      'domain': 'activity',
      'id': 'visible-entry',
      'revision': 7,
    },
  },
};
Map<String, dynamic> _deferred() => {
  'id': 'visible-entry',
  'position': 0,
  'payload': {
    'kind': 'deferred',
    'byteLength': utf8.encode(_producerWait).length,
    'reference': _reference,
  },
};
Map<String, dynamic> _window({
  Object? reference,
  int offset = 0,
  bool sealed = true,
}) {
  final bytes = utf8.encode(_producerWait);
  return {
    'id': 'visible-entry',
    'reference': reference ?? _reference,
    'offset': offset,
    'error': null,
    'window': {
      'offset': offset,
      'byteLength': bytes.length,
      'base64': base64Encode(bytes),
      'generation': 55,
      'availableThrough': bytes.length,
      'sealed': sealed,
    },
  };
}

Map<String, dynamic> _snapshot({
  int mainGeneration = 7,
  String turnId = 'turn',
  String? childrenParentId = 'parent',
  String activityId = 'activity',
  String databaseId = 'db',
  int revision = 7,
  int generation = 1,
  bool expanded = true,
  bool collection = true,
  bool ready = true,
  String? error,
  String? continuation,
  List<Map<String, dynamic>>? entries,
  List<Map<String, dynamic>> windows = const [],
}) => {
  'timeline': <String, dynamic>{
    'threadId': 'thread',
    'generation': mainGeneration,
    'current': <String, dynamic>{
      'turnId': turnId,
      'childrenParentId': childrenParentId,
      'activityId': activityId,
      'expanded': expanded,
      'collections': [
        if (collection)
          {
            'databaseId': databaseId,
            'collection': 'tools',
            'revision': revision,
            'generation': generation,
            'expanded': true,
            'loading': false,
            'error': error,
            'ready': ready,
            'continuation': continuation,
            'entries': entries ?? [_entry()],
          },
      ],
      'windows': windows,
    },
  },
};
