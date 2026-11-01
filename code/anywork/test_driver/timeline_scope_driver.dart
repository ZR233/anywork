import 'dart:convert';

import 'package:flutter_driver/flutter_driver.dart';

import 'flutter_driver_session.dart';
import 'raw_tap.dart';
import 'timeline_observation.dart';
import 'timeline_history_evidence.dart';
import 'tool_probe.dart';

/// Explicit UI actions over the real Main Turn and its registered Children.
/// No Session, reader, body cache or hidden message collection is created here.
final class TimelineScopeDriver {
  TimelineScopeDriver({
    required this.read,
    required this.probe,
    required this.tap,
    required this.reveal,
    required this.revealWithin,
  });

  factory TimelineScopeDriver.session(FlutterDriverSession driver) =>
      TimelineScopeDriver(
        read: driver.readSnapshot,
        probe: (target) => driver.sendCommand(ToolProbe(target, 'observe')),
        tap: (target) => driver.rawTap(target),
        reveal: (target) => driver.scrollUntilVisible(
          find.byValueKey('timeline-scrollable'),
          target,
          dyScroll: -80,
          timeout: const Duration(seconds: 20),
        ),
        revealWithin: (scrollable, target) => driver.scrollUntilVisible(
          scrollable,
          target,
          dyScroll: -80,
          timeout: const Duration(seconds: 20),
        ),
      );

  factory TimelineScopeDriver.raw(FlutterDriver driver) => TimelineScopeDriver(
    read: () async => (jsonDecode(await driver.requestData('snapshot')) as Map)
        .cast<String, dynamic>(),
    probe: (target) => driver.sendCommand(ToolProbe(target, 'observe')),
    tap: (target) async {
      await driver.sendCommand(RawTap(target));
    },
    reveal: (target) => driver.scrollUntilVisible(
      find.byValueKey('timeline-scrollable'),
      target,
      dyScroll: -80,
      timeout: const Duration(seconds: 20),
    ),
    revealWithin: (scrollable, target) => driver.scrollUntilVisible(
      scrollable,
      target,
      dyScroll: -80,
      timeout: const Duration(seconds: 20),
    ),
  );

  final Future<Map<String, dynamic>> Function() read;
  final Future<Map<String, dynamic>> Function(SerializableFinder) probe;
  final Future<void> Function(SerializableFinder) tap;
  final Future<void> Function(SerializableFinder) reveal;
  final Future<void> Function(SerializableFinder, SerializableFinder)
  revealWithin;

  TimelineHistoryReader history({
    required Future<void> Function() loadMainOlder,
    required Future<void> Function(SerializableFinder) scrollOlder,
  }) => TimelineHistoryReader(
    read: read,
    loadMainOlder: loadMainOlder,
    openChildren: (parent) async {
      await setExpanded(parent, true);
    },
    closeChildren: (parent) async {
      await setExpanded(parent, false);
    },
    loadChildrenOlder: (turn, child) async {
      if (child.itemIds.isEmpty) {
        throw StateError('Children has a cursor but no UI item to reveal');
      }
      await revealItem(child.itemIds.first);
      await scrollOlder(
        find.descendant(
          of: find.byValueKey('chat-item:${turn.id}'),
          matching: find.byType('Scrollable'),
          firstMatchOnly: true,
        ),
      );
    },
  );

  Future<void> revealItem(String id) async {
    final timeline = TimelineObservation.parse(await read());
    if (timeline.item(id) != null) {
      await reveal(find.byValueKey('chat-item:$id'));
      return;
    }
    final child = timeline.childrenContaining(id);
    final turn = timeline.items.singleWhere(
      (item) => item.childrenParentId == child.parentId,
    );
    await reveal(find.byValueKey('timeline-row-${turn.id}'));
    await revealWithin(
      find.descendant(
        of: find.byValueKey('timeline-row-${turn.id}'),
        matching: find.byType('Scrollable'),
        firstMatchOnly: true,
      ),
      find.byValueKey('chat-item:$id'),
    );
  }

  Future<Map<String, dynamic>> openLatest() async {
    final timeline = TimelineObservation.parse(await read());
    final turns = timeline.items.where(
      (item) => item.kind == 'turn' && item.childrenParentId != null,
    );
    if (turns.isEmpty) {
      throw StateError('Main has no actual completed Turn to expand');
    }
    return setExpanded(turns.last.childrenParentId!, true);
  }

  Future<Map<String, dynamic>> openAllLoaded() async {
    final initial = TimelineObservation.parse(await read());
    for (final turn in initial.items) {
      final parent = turn.childrenParentId;
      if (parent != null) await setExpanded(parent, true);
    }
    return read();
  }

  Future<Map<String, dynamic>> setExpanded(
    String parentId,
    bool expanded,
  ) async {
    final before = TimelineObservation.parse(await read());
    final turn = before.items.singleWhere(
      (item) => item.childrenParentId == parentId,
    );
    final header = find.descendant(
      of: find.byValueKey('chat-item:${turn.id}'),
      matching: find.byType('TimelineActivityRow'),
      firstMatchOnly: true,
    );
    await reveal(header);
    final sample = ((await probe(header))['samples'] as List).last as Map;
    if (sample['expanded'] is! bool) {
      throw StateError('Actual Turn header has no observable expansion state');
    }
    if (sample['expanded'] != expanded) await tap(header);
    final deadline = Stopwatch()..start();
    while (deadline.elapsed < const Duration(seconds: 30)) {
      final snapshot = await read();
      final timeline = TimelineObservation.parse(snapshot);
      if (timeline.threadId != before.threadId ||
          timeline.generation != before.generation) {
        throw StateError('Turn display changed while expanding Children');
      }
      final child = timeline.childrenFor(parentId);
      if (!expanded && child == null) return snapshot;
      if (expanded && child != null) {
        if (child.error != null) {
          throw StateError('Children read failed: ${child.error}');
        }
        if (child.ready && child.appliedSets > 0) return snapshot;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    throw StateError(
      'Actual Children registration did not settle for $parentId',
    );
  }
}
