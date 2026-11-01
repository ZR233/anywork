import 'dart:convert';

import 'package:anywork/src/shared/studio_driver_key_values.dart';
import 'package:flutter_driver/flutter_driver.dart';

import 'current_tools_observation.dart';
import 'flutter_driver_session.dart';
import 'tool_probe.dart';

/// Explicit UI operations. The paired observation parser remains query-only.
final class CurrentToolsDriver {
  CurrentToolsDriver({
    required this.read,
    required this.tap,
    required this.observe,
    required this.readEntryText,
  });
  factory CurrentToolsDriver.session(FlutterDriverSession driver) =>
      CurrentToolsDriver(
        read: driver.readSnapshot,
        tap: (key) => driver.rawTap(find.byValueKey(key)),
        observe: (key) async {
          final result = await driver.sendCommand(
            ToolProbe(find.byValueKey(key), 'observe'),
          );
          final sample = ((result['samples'] as List).last as Map)
              .cast<String, dynamic>();
          if (sample['mounted'] == false) return sample;
          if (sample['width'] is! num || sample['height'] is! num) {
            throw StateError('ToolProbe returned no actual control geometry');
          }
          // ToolProbe's existing success record contains geometry; only its
          // missing-finder record carries mounted=false.
          if (key.startsWith('timeline-content-open:')) {
            final public = await driver.sendCommand(
              ToolProbe(find.byValueKey(key), 'readText'),
            );
            final texts =
                (((public['samples'] as List).last as Map)['texts'] as List)
                    .whereType<String>()
                    .where((text) => text == '收起当前段' || text == '展开当前段')
                    .toList();
            if (texts.length != 1) {
              throw StateError(
                'Deferred range control has no observable open/close label',
              );
            }
            return {
              ...sample,
              'mounted': true,
              'rangeExpanded': texts.single == '收起当前段',
            };
          }
          return {...sample, 'mounted': true};
        },
        readEntryText: (key) async {
          final tile = find.ancestor(
            of: find.byValueKey(key),
            matching: find.byType('ExpansionTile'),
            firstMatchOnly: true,
          );
          final result = await driver.sendCommand(ToolProbe(tile, 'readText'));
          return (((result['samples'] as List).last as Map)['texts'] as List)
              .cast<String>();
        },
      );

  final Future<Map<String, dynamic>> Function() read;
  final Future<void> Function(String key) tap;
  final Future<Map<String, dynamic>> Function(String key) observe;
  final Future<List<String>> Function(String key) readEntryText;

  Future<CurrentToolsObservation> _current() async {
    final value = CurrentToolsObservation.optional(await read());
    if (value == null) throw StaleCurrentTools('Current display retired');
    return value;
  }

  void _sameOwner(
    CurrentToolsObservation before,
    CurrentToolsObservation after,
  ) {
    if (before.owner != after.owner) {
      throw StaleCurrentTools('Main/Turn/activity changed during a UI action');
    }
  }

  CurrentToolEntry _sameEntry(
    CurrentToolsObservation original,
    CurrentToolEntry entry,
    CurrentToolsObservation current,
  ) {
    current.requireSame(original);
    final actual = current.collection!.entries.singleWhere(
      (value) => value.id == entry.id,
    );
    if (actual.position != entry.position ||
        actual.byteLength != entry.byteLength ||
        canonicalCurrentJson(actual.reference) !=
            canonicalCurrentJson(entry.reference) ||
        (entry.inline != null &&
            (actual.inline == null ||
                base64Encode(entry.inline!) != base64Encode(actual.inline!)))) {
      throw StaleCurrentTools('The original collection entry was replaced');
    }
    return actual;
  }

  Future<CurrentToolsObservation> openCompletedItems({
    required String turnId,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final clock = Stopwatch()..start();
    final original = await _current();
    if (original.turnId != turnId) {
      throw StaleCurrentTools('Completed members belong to another Turn');
    }
    final key = StudioDriverKeyValues.currentCompletedItems(
      original.requireChildrenParentId(),
    );
    var activityTapped = false, completedTapped = false;
    do {
      final current = await _current();
      _sameOwner(original, current);
      if (!current.expanded) {
        if (!activityTapped) {
          await tap('conversation-activity');
          activityTapped = true;
          _sameOwner(original, await _current());
        }
      } else {
        final state = await observe(key);
        final fresh = await _current();
        _sameOwner(original, fresh);
        if (state['mounted'] == true) {
          if (state['expanded'] is! bool) {
            throw StateError(
              'Completed members have no public expansion state',
            );
          }
          if (state['expanded'] == true) {
            if (clock.elapsed >= timeout) break;
            return fresh;
          }
          if (!completedTapped) {
            await tap(key);
            completedTapped = true;
            _sameOwner(original, await _current());
          }
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    } while (clock.elapsed < timeout);
    throw StateError('Original current completed members were not expanded');
  }

  Future<CurrentToolsObservation> openTools({
    required String? turnId,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final clock = Stopwatch()..start();
    final original = await _current();
    if (original.turnId != turnId || original.activityId == null) {
      throw StaleCurrentTools(
        'Current display is not the requested active Turn',
      );
    }
    var activityTapped = false;
    var collectionTapped = false;
    final reloaded = <Object>{};
    do {
      final current = await _current();
      _sameOwner(original, current);
      if (!current.expanded) {
        if (!activityTapped) {
          await tap('conversation-activity');
          activityTapped = true;
          _sameOwner(original, await _current());
        }
      } else {
        final page = current.collection;
        if (page == null) {
          final key = StudioDriverKeyValues.currentCollection('tools');
          final state = await observe(key);
          _sameOwner(original, await _current());
          if (state['mounted'] != false && state['expanded'] is! bool) {
            throw StateError(
              'Actual tools collection disclosure is unavailable',
            );
          }
          if (state['mounted'] == true &&
              state['expanded'] == false &&
              !collectionTapped) {
            await tap(key);
            collectionTapped = true;
            _sameOwner(original, await _current());
          }
        } else {
          if (page.error != null) {
            throw StateError('Current tools read failed: ${page.error}');
          }
          if (page.expanded && page.ready && !page.loading) {
            current.requirePage();
            return current;
          }
          // Only the actual public stale/replacement UI authorizes a reload.
          // Real read errors above are never converted into a retry.
          if (!page.ready && !page.loading) {
            final key = StudioDriverKeyValues.currentCollectionReload('tools');
            final state = await observe(key);
            final fresh = await _current();
            _sameOwner(original, fresh);
            if (fresh.qualification != current.qualification) {
              throw StaleCurrentTools(
                'Collection changed before its reload action',
              );
            }
            if (state['mounted'] == true &&
                reloaded.add(current.qualification)) {
              await tap(key);
              _sameOwner(original, await _current());
            }
          }
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    } while (clock.elapsed < timeout);
    throw CurrentToolsNotReady(
      'Current tools did not admit a visible page within $timeout',
    );
  }

  Future<CurrentToolsObservation> next(
    CurrentToolsObservation previous, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final before = await _current();
    before.requireSame(previous);
    final page = previous.collection!;
    if (page.continuation == null) {
      throw StateError('Current tools page has no continuation');
    }
    await tap(StudioDriverKeyValues.currentCollectionNext('tools'));
    final clock = Stopwatch()..start();
    do {
      final current = await _current();
      _sameOwner(previous, current);
      final next = current.collection;
      if (next == null || next.reference != page.reference) {
        throw StaleCurrentTools('Collection retired/revised while paging');
      }
      if (next.generation < page.generation ||
          next.generation > page.generation + 1) {
        throw StaleCurrentTools(
          'Collection display retired during the requested Next',
        );
      }
      if (next.error != null) {
        throw StateError('Current tools page failed: ${next.error}');
      }
      if (!next.loading &&
          next.ready &&
          next.generation == page.generation + 1) {
        current.requirePage();
        if (next.continuation == page.continuation ||
            (page.entries.isNotEmpty &&
                next.entries.isNotEmpty &&
                next.entries.first.compareOrderTo(page.entries.last) <= 0)) {
          throw StateError(
            'Current tools next page did not advance the original cursor',
          );
        }
        return current;
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    } while (clock.elapsed < timeout);
    throw StateError('Current tools next page was not admitted');
  }

  Future<CurrentToolObservation> inspect(
    CurrentToolsObservation original,
    CurrentToolEntry entry, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    var current = await _current();
    final actual = _sameEntry(original, entry, current);
    if (entry.inline == null) {
      var decoded = current.decode(actual);
      final recorded = original.decode(entry);
      if (recorded != null &&
          (decoded == null ||
              decoded.windowGeneration != recorded.windowGeneration ||
              decoded.raw != recorded.raw)) {
        throw StaleCurrentTools(
          'The original public payload window retired or changed',
        );
      }
      if (decoded != null) return decoded;
      // This is the production range viewer for the real collection entry.
      // No private read call or replacement lease is available to this helper.
      final openKey = StudioDriverKeyValues.timelineContentOpen(
        entry.id,
        'payload',
      );
      final shown = await observe(openKey);
      current = await _current();
      _sameEntry(original, entry, current);
      if (shown['mounted'] != true || shown['rangeExpanded'] is! bool) {
        throw StateError(
          'Deferred entry has no observable public range disclosure',
        );
      }
      if (shown['rangeExpanded'] == false) {
        await tap(openKey);
      }
      final clock = Stopwatch()..start();
      do {
        current = await _current();
        decoded = current.decode(_sameEntry(original, entry, current));
        if (decoded != null) return decoded;
        await Future<void>.delayed(const Duration(milliseconds: 150));
      } while (clock.elapsed < timeout);
      throw StateError(
        'Deferred current entry ${entry.id} has no complete admitted public window; '
        'the raw tools JSON remains unverified',
      );
    }
    final expected = current.decode(actual)!;
    final key = StudioDriverKeyValues.currentCollectionEntry('tools', entry.id);
    final state = await observe(key);
    _sameEntry(original, entry, await _current());
    if (state['expanded'] is! bool) {
      throw StateError('Current entry has no public expansion state');
    }
    if (state['expanded'] == false) await tap(key);
    _sameEntry(original, entry, await _current());
    final texts = await readEntryText(key);
    current = await _current();
    final fresh = current.decode(_sameEntry(original, entry, current));
    if (fresh == null ||
        fresh.callId != expected.callId ||
        fresh.raw != expected.raw) {
      throw StaleCurrentTools(
        'Current tool changed during public JSON inspection',
      );
    }
    var matched = false;
    for (final text in texts) {
      try {
        if (canonicalCurrentJson(jsonDecode(text)) ==
            canonicalCurrentJson(jsonDecode(fresh.raw))) {
          matched = true;
        }
      } on FormatException {
        // Public labels are not payload candidates; the original payload was
        // already strictly decoded outside this UI-label loop.
      }
    }
    if (!matched) {
      throw StateError(
        'Expanded current entry did not display its original JSON',
      );
    }
    return fresh;
  }
}

/// No page/control exists yet. This is distinct from a real read error and is
/// only awaited inside the caller's original observation deadline.
final class CurrentToolsNotReady implements Exception {
  CurrentToolsNotReady(this.message);
  final String message;
  @override
  String toString() => 'CurrentToolsNotReady: $message';
}
