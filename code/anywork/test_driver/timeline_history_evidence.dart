import 'dart:convert';

import 'timeline_observation.dart';

/// Host test evidence captured while each real display was qualified. It is
/// never supplied to a product controller or treated as currently mounted UI.
final class TimelineHistoryEvidence {
  TimelineHistoryEvidence(
    this.main,
    List<TimelineChildrenObservation> children, {
    List<Map<String, Object?>> pages = const [],
  }) : children = List.unmodifiable(children),
       pages = List.unmodifiable(pages);

  final TimelineObservation main;
  final List<TimelineChildrenObservation> children;
  final List<Map<String, Object?>> pages;

  TimelineChildrenObservation scopeContaining(String itemId) =>
      children.singleWhere((scope) => scope.itemIds.contains(itemId));

  Iterable<TimelineItemObservation> get childItems =>
      children.expand((scope) => scope.items);

  Map<String, Object?> inventory() => {
    'main': {'itemIds': main.itemIds, 'eof': !main.hasOlder},
    'pages': pages,
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
    required this.openChildren,
    required this.loadChildrenOlder,
    required this.closeChildren,
    this.maxPages = 24,
    this.pageTimeout = const Duration(seconds: 90),
  });

  final Future<Map<String, dynamic>> Function() read;
  final Future<void> Function() loadMainOlder;
  final Future<void> Function(String parentId) openChildren, closeChildren;
  final Future<void> Function(
    TimelineItemObservation turn,
    TimelineChildrenObservation scope,
  )
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
          'Cannot enumerate possible Turn parents from ${item.compatibility} Main item ${item.id}',
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
    _retained(original.items, current.items);
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
            .take(main.itemCount - before.itemCount)
            .toList(),
      });
    }
    final children = <TimelineChildrenObservation>[];
    final parents = <String>{};
    final identities = main.itemIds.toSet();
    for (final turn in main.items.where(
      (item) => item.childrenParentId != null,
    )) {
      final parent = turn.childrenParentId!;
      if (turn.kind != 'turn' || !parents.add(parent)) {
        throw StateError('Main contains an invalid/duplicated Turn parent');
      }
      await openChildren(parent);
      var current = _main(await read());
      _sameMain(main, current);
      var child = _child(current, parent);
      while (child.loadingOlder || child.olderCursor != null) {
        final before = child;
        if (!child.loadingOlder) {
          usePage();
          await loadChildrenOlder(turn, child);
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
      await closeChildren(parent);
      current = _main(await read());
      _sameMain(main, current);
      if (current.childrenFor(parent) != null) {
        throw StateError('Closed Children $parent still registered');
      }
    }
    return TimelineHistoryEvidence(main, children, pages: pages);
  }

  /// A later UI visit starts with its new actual Set, then pages only that scope.
  /// Previously captured before tokens and display generations are never reused.
  Future<Map<String, dynamic>> showItem(
    TimelineHistoryEvidence evidence,
    String itemId,
  ) async {
    final recorded = evidence.scopeContaining(itemId);
    var main = _main(await read());
    if (main.threadId != evidence.main.threadId) {
      throw StateError('Historical item belongs to another Thread');
    }
    var pages = 0;
    while (!main.items.any(
      (item) => item.childrenParentId == recorded.parentId,
    )) {
      if (main.olderCursor == null || pages++ >= maxPages) {
        throw StateError('Original Turn parent missing from reopened Main');
      }
      await loadMainOlder();
      main = await _awaitMain(main);
    }
    // Locate the current Main Message before asking the UI to reveal its header.
    await openChildren(recorded.parentId);
    final current = _main(await read());
    _sameMain(main, current);
    main = current;
    final turn = main.items.singleWhere(
      (item) => item.childrenParentId == recorded.parentId,
    );
    final originalTurn = evidence.main.items.singleWhere(
      (item) => item.childrenParentId == recorded.parentId,
    );
    if (jsonEncode(turn.frozenFields()) !=
        jsonEncode(originalTurn.frozenFields())) {
      throw StateError('Reopened Children belongs to a changed original Turn');
    }
    var child = _child(main, recorded.parentId);
    while (!child.itemIds.contains(itemId)) {
      if (child.olderCursor == null || pages++ >= maxPages) {
        throw StateError(
          'Original item $itemId missing from reopened Children',
        );
      }
      await loadChildrenOlder(turn, child);
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

void _retained(
  List<TimelineItemObservation> before,
  List<TimelineItemObservation> after,
) {
  if (after.length < before.length) {
    throw StateError('Paging dropped previously loaded identities');
  }
  final offset = after.length - before.length;
  for (var index = 0; index < before.length; index++) {
    if (jsonEncode(before[index].frozenFields()) !=
        jsonEncode(after[offset + index].frozenFields())) {
      throw StateError('Paging reordered or changed an original item');
    }
  }
}
