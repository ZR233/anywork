import 'dart:convert';

import 'timeline_observation.dart';
import 'timeline_group_observation.dart';

/// Host-only evidence accumulated while bounded ordinary windows were mounted.
/// This is not a Children scope or a product-side member collection.
final class TimelineGroupHistoryEvidence {
  TimelineGroupHistoryEvidence(
    this.unitId,
    Iterable<TimelineItemObservation> items,
  ) : items = List.unmodifiable(items);
  final String unitId;
  final List<TimelineItemObservation> items;
}

/// Host test evidence captured while each real display was qualified. It is
/// never supplied to a product controller or treated as currently mounted UI.
final class TimelineHistoryEvidence {
  TimelineHistoryEvidence(
    this.main,
    List<TimelineChildrenObservation> children, {
    List<Map<String, Object?>> pages = const [],
    List<TimelineGroupHistoryEvidence> groups = const [],
  }) : children = List.unmodifiable(children),
       groups = List.unmodifiable(groups),
       pages = List.unmodifiable(pages);

  final TimelineObservation main;
  final List<TimelineChildrenObservation> children;
  final List<Map<String, Object?>> pages;
  final List<TimelineGroupHistoryEvidence> groups;
  Iterable<TimelineItemObservation> get processItems sync* {
    yield* main.items.where((item) => item.kind != 'workGroup');
    yield* childItems;
    for (final group in groups) {
      yield* group.items;
    }
  }

  TimelineChildrenObservation scopeContaining(String itemId) =>
      children.singleWhere((scope) => scope.itemIds.contains(itemId));

  Iterable<TimelineItemObservation> get childItems =>
      children.expand((scope) => scope.items);

  Map<String, Object?> inventory() => {
    'main': {'itemIds': main.itemIds, 'eof': !main.hasOlder},
    'pages': pages,
    'groups': [
      for (final group in groups)
        {
          'unitId': group.unitId,
          'itemIds': group.items.map((item) => item.id).toList(),
        },
    ],
    'children': [
      for (final child in children)
        {
          'parentId': child.parentId,
          'generation': child.generation,
          'itemIds': child.itemIds,
          'eof': child.olderCursor == null,
          'appliedSets': child.appliedSets,
          'appliedPrepends': child.appliedPrepends,
        },
    ],
  };
}

/// Explicit actions use the current UI's own paging capability. No cursor is
/// rebound to a new scope. The original 24-page and 90-second page budgets apply.
final class TimelineHistoryReader {
  TimelineHistoryReader({
    required this.read,
    required this.loadMainOlder,
    required this.loadChildrenOlder,
    this.closeChildren,
    this.setGroupExpanded,
    this.loadGroupEarlier,
    this.maxPages = 24,
    this.pageTimeout = const Duration(seconds: 90),
  });

  final Future<Map<String, dynamic>> Function() read;
  final Future<void> Function() loadMainOlder;
  final Future<void> Function(String parentId)? closeChildren;
  final Future<void> Function(String unitId, bool expanded)? setGroupExpanded;
  final Future<void> Function(String unitId)? loadGroupEarlier;
  final Future<void> Function(TimelineChildrenObservation scope)
  loadChildrenOlder;
  final int maxPages;
  final Duration pageTimeout;

  TimelineObservation _main(Map<String, dynamic> snapshot) {
    final raw = snapshot['timeline'];
    if (raw is! Map ||
        !raw.containsKey('olderCursor') ||
        !raw.containsKey('olderError') ||
        !raw.containsKey('olderErrorCode')) {
      throw StateError('Main EOF cursor is not observable');
    }
    for (final child in (raw['children'] as List)) {
      if (child is! Map ||
          !child.containsKey('olderCursor') ||
          !child.containsKey('error')) {
        throw StateError('Children EOF/error is not observable');
      }
    }
    final main = TimelineObservation.parse(snapshot);
    main.requireConsistentIds();
    for (final item in main.items) {
      if (item.compatibility != 'current') {
        throw StateError(
          'Cannot enumerate history from ${item.compatibility} Main item ${item.id}',
        );
      }
    }
    if (main.olderError != null || main.olderErrorCode != null) {
      throw StateError('Main paging failed: ${main.summary()}');
    }
    if (!main.ready ||
        main.appliedSets == null ||
        main.appliedSets! < 1 ||
        main.hasOlder != (main.olderCursor != null)) {
      throw StateError('Main has no qualified page/EOF: ${main.summary()}');
    }
    return main;
  }

  void _sameMain(
    TimelineObservation original,
    TimelineObservation current, {
    bool allowPrepend = false,
  }) {
    if (current.threadId != original.threadId ||
        current.generation != original.generation ||
        current.appliedSets != original.appliedSets ||
        (!allowPrepend && current.itemCount != original.itemCount)) {
      throw StateError('Main lease changed during history evidence collection');
    }
    _retained(original.items, current.items, allowInsertion: true);
  }

  TimelineChildrenObservation _child(
    TimelineObservation main,
    String parentId, {
    TimelineChildrenObservation? original,
  }) {
    final child = main.childrenFor(parentId);
    if (child == null || !child.ready || child.appliedSets < 1) {
      throw StateError('Children $parentId retired or never admitted its Set');
    }
    if (child.error != null) {
      throw StateError('Children $parentId paging failed: ${child.error}');
    }
    if (original != null) {
      if (child.generation != original.generation ||
          child.appliedSets != original.appliedSets) {
        throw StateError('Children $parentId lease changed during paging');
      }
      _retained(original.items, child.items);
    }
    return child;
  }

  Future<TimelineObservation> _awaitMain(TimelineObservation before) async {
    final clock = Stopwatch()..start();
    do {
      final current = _main(await read());
      _sameMain(before, current, allowPrepend: true);
      if (!current.loadingOlder &&
          current.appliedPrepends != before.appliedPrepends) {
        current.requireAcceptedOperation(before, prepend: true);
        if (current.olderCursor == before.olderCursor) {
          throw StateError('Main Prepend did not advance its original cursor');
        }
        return current;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    } while (clock.elapsed < pageTimeout);
    throw StateError('Main UI did not admit the requested history page');
  }

  Future<TimelineChildrenObservation> _awaitChild(
    TimelineObservation main,
    TimelineChildrenObservation before,
  ) async {
    final clock = Stopwatch()..start();
    do {
      final current = _main(await read());
      _sameMain(main, current);
      final child = _child(current, before.parentId, original: before);
      if (!child.loadingOlder &&
          child.appliedPrepends > before.appliedPrepends) {
        if (child.olderCursor == before.olderCursor) {
          throw StateError(
            'Children Prepend did not advance its original cursor',
          );
        }
        return child;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    } while (clock.elapsed < pageTimeout);
    throw StateError(
      'Children ${before.parentId} UI did not admit its requested page',
    );
  }

  Future<TimelineHistoryEvidence> collect({
    Future<void> Function(
      TimelineObservation main,
      TimelineChildrenObservation scope,
    )?
    onScope,
    Future<void> Function(TimelineObservation, Map<String, dynamic>)?
    onGroupPage,
  }) async {
    var remaining = maxPages;
    final pages = <Map<String, Object?>>[];
    void usePage() {
      if (remaining-- <= 0) {
        throw StateError(
          'History did not reach EOF within $maxPages page requests',
        );
      }
    }

    var main = _main(await read());
    while (main.loadingOlder || main.olderCursor != null) {
      final before = main;
      if (!main.loadingOlder) {
        usePage();
        await loadMainOlder();
      }
      main = await _awaitMain(main);
      pages.add({
        'parentId': null,
        'mainGeneration': main.generation,
        'before': before.olderCursor,
        'after': main.olderCursor,
        'appliedPrependsBefore': before.appliedPrepends,
        'appliedPrependsAfter': main.appliedPrepends,
        'prependedIds': main.itemIds
            .where((id) => !before.itemIds.contains(id))
            .toList(),
      });
    }
    final children = <TimelineChildrenObservation>[];
    final groups = <TimelineGroupHistoryEvidence>[];
    for (final unit in main.items.where((item) => item.kind == 'workGroup')) {
      final expand = setGroupExpanded;
      final earlier = loadGroupEarlier;
      if (expand == null || earlier == null) {
        throw StateError(
          'History is incomplete: ordinary group UI actions are unavailable',
        );
      }
      await expand(unit.id, true);
      final items = <String, TimelineItemObservation>{};
      while (true) {
        final snapshot = await read();
        final current = _main(snapshot);
        _sameMain(main, current);
        final group = _group(snapshot, unit.id);
        for (final value in group['items'] as List) {
          final item = TimelineItemObservation.parse(
            (value as Map).cast<String, dynamic>(),
          );
          final previous = items[item.id];
          if (previous != null &&
              jsonEncode(previous.frozenFields()) !=
                  jsonEncode(item.frozenFields())) {
            throw StateError(
              'Ordinary window changed completed atom ${item.id}',
            );
          }
          items[item.id] = item;
        }
        await onGroupPage?.call(current, group);
        if (!_needsEarlier(snapshot, unit.id, group)) break;
        usePage();
        final before = group['before'];
        final anchor = group['completionAnchor'];
        await earlier(unit.id);
        final afterSnapshot = await read();
        _sameMain(main, _main(afterSnapshot));
        final after = _group(afterSnapshot, unit.id);
        if (after['completionAnchor'] == anchor && after['before'] == before) {
          throw StateError('Ordinary window did not advance its actual cursor');
        }
        pages.add({
          'unitId': unit.id,
          'mainGeneration': main.generation,
          'completionAnchor': after['completionAnchor'],
          'before': before,
          'after': after['before'],
        });
      }
      groups.add(TimelineGroupHistoryEvidence(unit.id, items.values));
      await expand(unit.id, false);
    }
    final parents = <String>{};
    final identities = main.itemIds.toSet();
    // Only explicitly mounted genuine business scopes are observable. Main
    // payloads do not advertise a Turn/work-group parent or authorize opening it.
    for (final mounted in main.children) {
      final parent = mounted.parentId;
      if (!parents.add(parent)) {
        throw StateError('Main contains a duplicated real business parent');
      }
      var current = _main(await read());
      _sameMain(main, current);
      var child = _child(current, parent);
      while (child.loadingOlder || child.olderCursor != null) {
        final before = child;
        if (!child.loadingOlder) {
          usePage();
          await loadChildrenOlder(child);
        }
        child = await _awaitChild(main, child);
        pages.add({
          'parentId': parent,
          'mainGeneration': main.generation,
          'scopeGeneration': child.generation,
          'before': before.olderCursor,
          'after': child.olderCursor,
          'appliedPrependsBefore': before.appliedPrepends,
          'appliedPrependsAfter': child.appliedPrepends,
          'prependedIds': child.itemIds
              .take(child.loadedCount - before.loadedCount)
              .toList(),
        });
      }
      for (final id in child.itemIds) {
        if (!identities.add(id)) {
          throw StateError('History repeated item $id across scope boundaries');
        }
      }
      await onScope?.call(main, child);
      current = _main(await read());
      _sameMain(main, current);
      final checked = _child(current, parent, original: child);
      if (checked.loadingOlder ||
          checked.olderCursor != null ||
          checked.itemIds.length != child.itemIds.length) {
        throw StateError('Children changed after EOF evidence capture');
      }
      children.add(child);
      final close = closeChildren;
      if (close == null) continue;
      await close(parent);
      current = _main(await read());
      _sameMain(main, current);
      if (current.childrenFor(parent) != null) {
        throw StateError('Closed Children $parent still registered');
      }
    }
    return TimelineHistoryEvidence(
      main,
      children,
      pages: pages,
      groups: groups,
    );
  }

  /// A later UI visit starts with its new actual Set, then pages only that scope.
  /// Previously captured before tokens and display generations are never reused.
  Future<Map<String, dynamic>> showItem(
    TimelineHistoryEvidence evidence,
    String itemId,
  ) async {
    if (evidence.main.itemIds.contains(itemId)) {
      var main = _main(await read());
      if (main.threadId != evidence.main.threadId) {
        throw StateError('Historical item belongs to another Thread');
      }
      var remaining = maxPages;
      while (!main.itemIds.contains(itemId)) {
        if (!main.hasOlder || remaining-- <= 0) {
          throw StateError('Reopened Main is incomplete');
        }
        await loadMainOlder();
        main = await _awaitMain(main);
      }
      final expected = evidence.main.items.singleWhere(
        (item) => item.id == itemId,
      );
      final actual = main.items.singleWhere((item) => item.id == itemId);
      if (jsonEncode(expected.frozenFields()) !=
          jsonEncode(actual.frozenFields())) {
        throw StateError('Reopened Main item $itemId changed completed data');
      }
      return read();
    }
    final recordedGroup = evidence.groups
        .where((group) => group.items.any((item) => item.id == itemId))
        .firstOrNull;
    if (recordedGroup != null) {
      final expected = recordedGroup.items.singleWhere(
        (item) => item.id == itemId,
      );
      var main = _main(await read());
      if (main.threadId != evidence.main.threadId) {
        throw StateError('Historical item belongs to another Thread');
      }
      var remaining = maxPages;
      while (main.hasOlder) {
        if (remaining-- <= 0) {
          throw StateError('Reopened Main evidence is incomplete');
        }
        await loadMainOlder();
        main = await _awaitMain(main);
      }
      final expand = setGroupExpanded;
      final earlier = loadGroupEarlier;
      if (expand == null || earlier == null) {
        throw StateError('Ordinary group actions unavailable');
      }
      // Owner-local keys are not stable across reopening. Search only actually
      // mounted bounded windows, never restore a captured cursor or fake parent.
      for (final unit in main.items.where((item) => item.kind == 'workGroup')) {
        await expand(unit.id, true);
        while (true) {
          final snapshot = await read();
          _sameMain(main, _main(snapshot));
          final group = _group(snapshot, unit.id);
          final matches = (group['items'] as List).cast<Map>().where(
            (item) => item['id'] == itemId,
          );
          if (matches.isNotEmpty) {
            final actual = TimelineItemObservation.parse(
              matches.single.cast<String, dynamic>(),
            );
            if (jsonEncode(expected.frozenFields()) !=
                jsonEncode(actual.frozenFields())) {
              throw StateError('Reopened atom $itemId changed completed data');
            }
            return snapshot;
          }
          if (!_needsEarlier(snapshot, unit.id, group)) break;
          if (remaining-- <= 0) {
            throw StateError('Reopened ordinary prefix is incomplete');
          }
          final before = group['before'];
          final anchor = group['completionAnchor'];
          await earlier(unit.id);
          final after = _group(await read(), unit.id);
          if (after['before'] == before &&
              after['completionAnchor'] == anchor) {
            throw StateError('Reopened ordinary window made no progress');
          }
        }
        await expand(unit.id, false);
      }
      throw StateError(
        'Original atom $itemId missing from reopened ordinary windows',
      );
    }
    final recorded = evidence.scopeContaining(itemId);
    var main = _main(await read());
    if (main.threadId != evidence.main.threadId) {
      throw StateError('Historical item belongs to another Thread');
    }
    var pages = 0;
    // The original business owner must mount this scope explicitly. Never
    // discover/reopen it through a removed Turn payload field.
    var child = _child(main, recorded.parentId);
    while (!child.itemIds.contains(itemId)) {
      if (child.olderCursor == null || pages++ >= maxPages) {
        throw StateError(
          'Original item $itemId missing from reopened Children',
        );
      }
      await loadChildrenOlder(child);
      child = await _awaitChild(main, child);
    }
    final expected = recorded.items.singleWhere((item) => item.id == itemId);
    final actual = child.items.singleWhere((item) => item.id == itemId);
    if (jsonEncode(expected.frozenFields()) !=
        jsonEncode(actual.frozenFields())) {
      throw StateError('Reopened item $itemId changed its original data');
    }
    final snapshot = await read();
    final last = _main(snapshot);
    _sameMain(main, last);
    _child(last, recorded.parentId, original: child);
    return snapshot;
  }
}

Map<String, dynamic> _group(Map<String, dynamic> snapshot, String id) {
  final group = timelineGroupDisplays(snapshot)
      .singleWhere((group) => group['unitId'] == id);
  if (group['error'] != null ||
      group['loading'] != false ||
      group['expanded'] != true) {
    throw StateError('Ordinary window $id is not qualified: ${group['error']}');
  }
  return group;
}

bool _needsEarlier(
  Map<String, dynamic> snapshot,
  String id,
  Map<String, dynamic> group,
) {
  if (group['completionAnchor'] != null) return group['before'] != null;
  final raw = ((snapshot['timeline'] as Map)['items'] as List)
      .cast<Map>()
      .singleWhere((item) => item['id'] == id);
  final atomic = raw['atomic'];
  if (atomic is! Map || atomic['loadedCount'] is! int) {
    throw StateError('Ordinary group lacks actual loaded metadata');
  }
  return (atomic['loadedCount'] as int) > (group['items'] as List).length;
}

void _retained(
  List<TimelineItemObservation> before,
  List<TimelineItemObservation> after, {
  bool allowInsertion = false,
}) {
  if (after.length < before.length) {
    throw StateError('Paging dropped previously loaded identities');
  }
  var next = allowInsertion ? 0 : after.length - before.length;
  for (final item in before) {
    while (next < after.length && after[next].id != item.id) {
      next++;
    }
    if (next == after.length ||
        jsonEncode(item.frozenFields()) !=
            jsonEncode(after[next].frozenFields())) {
      throw StateError('Paging reordered or changed an original item');
    }
    next++;
  }
}
