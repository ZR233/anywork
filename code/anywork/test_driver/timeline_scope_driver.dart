import 'dart:convert';

import 'package:flutter_driver/flutter_driver.dart';

import 'flutter_driver_session.dart';
import 'raw_tap.dart';
import 'timeline_observation.dart';
import 'timeline_history_evidence.dart';
import 'timeline_group_observation.dart';
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
    setGroupExpanded: (id, expanded) async {
      await setGroupExpanded(id, expanded);
    },
    loadGroupEarlier: (id) async {
      await loadGroupEarlier(id);
    },
    loadChildrenOlder: (child) async {
      if (child.itemIds.isEmpty) {
        throw StateError('Children has a cursor but no UI item to reveal');
      }
      await revealItem(child.itemIds.first);
      await scrollOlder(
        find.ancestor(
          of: find.byValueKey('chat-item:${child.itemIds.first}'),
          matching: find.byType('Scrollable'),
          firstMatchOnly: true,
        ),
      );
    },
  );

  Future<void> revealItem(String id) async {
    final snapshot = await read();
    final timeline = TimelineObservation.parse(snapshot);
    if (timeline.item(id) != null) {
      await reveal(find.byValueKey('chat-item:$id'));
      return;
    }
    for (final group in timelineGroupDisplays(snapshot)) {
      if (!(group['items'] as List).cast<Map>().any(
        (item) => item['id'] == id,
      )) {
        continue;
      }
      await reveal(find.byValueKey('timeline-row-${group['unitId']}'));
      await reveal(find.byValueKey('chat-item:$id'));
      return;
    }
    timeline.childrenContaining(id); // Only a genuinely mounted business scope.
    await revealWithin(
      find.ancestor(
        of: find.byValueKey('chat-item:$id'),
        matching: find.byType('Scrollable'),
        firstMatchOnly: true,
      ),
      find.byValueKey('chat-item:$id'),
    );
  }

  Future<Map<String, dynamic>> openLatest() async {
    final timeline = TimelineObservation.parse(await read());
    final turns = timeline.items.where((item) => item.kind == 'workGroup');
    if (turns.isEmpty) {
      throw StateError('Main has no actual completed work record to expand');
    }
    return setGroupExpanded(turns.last.id, true);
  }

  Future<Map<String, dynamic>> openAllLoaded() async {
    final initial = TimelineObservation.parse(await read());
    for (final unit in initial.items) {
      if (unit.kind == 'workGroup') await setGroupExpanded(unit.id, true);
    }
    return read();
  }

  Future<Map<String, dynamic>> setGroupExpanded(
    String unitId,
    bool expanded,
  ) async {
    final initial = TimelineObservation.parse(await read());
    final header = find.ancestor(
      of: find.byValueKey('source-unit-header:$unitId'),
      matching: find.byType('ListTile'),
      firstMatchOnly: true,
    );
    await reveal(header);
    final sample = ((await probe(header))['samples'] as List).last as Map;
    if (sample['expanded'] is! bool) {
      throw StateError('Group expansion is not observable');
    }
    if (sample['expanded'] != expanded) await tap(header);
    return _waitGroup(initial, unitId, expanded: expanded);
  }

  Future<Map<String, dynamic>> loadGroupEarlier(String unitId) async {
    final initial = TimelineObservation.parse(await read());
    final button = find.byValueKey('source-unit-older:$unitId');
    await reveal(button);
    await tap(button);
    return _waitGroup(initial, unitId, expanded: true);
  }

  Future<Map<String, dynamic>> _waitGroup(
    TimelineObservation initial,
    String id, {
    required bool expanded,
  }) async {
    final clock = Stopwatch()..start();
    while (clock.elapsed < const Duration(seconds: 30)) {
      final snapshot = await read();
      final timeline = TimelineObservation.parse(snapshot);
      if (timeline.threadId != initial.threadId ||
          timeline.generation != initial.generation) {
        throw StateError('Display lease changed during ordinary window action');
      }
      final matches = timelineGroupDisplays(snapshot)
          .where((group) => group['unitId'] == id);
      if (matches.length == 1) {
        final group = matches.single;
        if (group['error'] != null) {
          throw StateError('Ordinary window failed: ${group['error']}');
        }
        if (group['expanded'] == expanded && group['loading'] == false) {
          return snapshot;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    throw StateError('Group $id did not settle');
  }
}
