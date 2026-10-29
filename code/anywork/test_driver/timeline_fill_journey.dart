import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'key_press.dart';
import 'pointer_scroll.dart';
import 'raw_tap.dart';
import 'timeline_observation.dart';

/// Observes the real viewport after the compact grouped tail and explicit Live transitions.
/// Tail baselines remain small; the display may then read several pages to fill its viewport.
Future<Map<String, Object?>> observeLatestPagePresentation(
  FlutterDriver driver,
  Directory output,
) async {
  final timeline = find.byValueKey('timeline-scrollable');
  Future<Map<String, dynamic>> snapshot() async =>
      (jsonDecode(await driver.requestData('snapshot')) as Map)
          .cast<String, dynamic>();

  bool filled(Map<String, dynamic> state) {
    return timelineViewportSettled(state);
  }

  Future<Map<String, dynamic>> until(
    String stage,
    bool Function(Map<String, dynamic>) ready,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (true) {
      final state = await snapshot();
      if (ready(state)) return state;
      if (DateTime.now().isAfter(deadline)) {
        await File('${output.path}/latest-fill-$stage.json')
            .writeAsString(jsonEncode(state));
        await File('${output.path}/latest-fill-$stage.png')
            .writeAsBytes(await driver.screenshot());
        throw StateError('Latest viewport did not settle: $stage');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  await driver.sendCommand(RawTap(find.byValueKey('timeline-return-live')));
  await driver.tap(find.byValueKey('composer-input'));
  await driver.enterText('Tool scroll compact');
  await driver.tap(find.byValueKey('composer-submit'));
  await until('compact-answer', (state) {
    final workspace = state['workspace'] as Map?;
    final content = TimelineObservation.optional(state);
    return workspace?['isBusy'] == false &&
        (content?.items.any(
              (item) => item.text.contains('compact tail complete'),
            ) ??
            false);
  });

  final observations = <String, Object?>{};
  // No pointer input or load command precedes this observation.
  final initialStability = TimelineViewportStability();
  final initial = await until('automatic-initial', initialStability.accept);
  final initialContent = TimelineObservation.parse(initial);
  initialContent.requireConsistentIds();
  observations['automaticInitial'] = <String, Object?>{
    'timeline': initialContent.summary(),
    'scroll': TimelineScrollObservation.parse(initial).toJson(),
    'pass': filled(initial) && initialContent.isLive,
  };
  await File('${output.path}/latest-fill-automatic.png')
      .writeAsBytes(await driver.screenshot());

  for (var attempt = 0; attempt < 2; attempt++) {
    final beforeState = await until('before-$attempt', filled);
    final before = TimelineObservation.parse(beforeState);
    await driver.sendCommand(PointerScroll(timeline, -250));
    await until(
      'detached-$attempt',
      (state) => TimelineObservation.optional(state)?.isHistory ?? false,
    );
    await driver.sendCommand(RawTap(find.byValueKey('timeline-return-live')));
    final returnStability = TimelineViewportStability();
    final state = await until('filled-$attempt', (state) {
      final content = TimelineObservation.optional(state);
      final scroll = TimelineScrollObservation.optional(state);
      return returnStability.accept(state) &&
          content != null &&
          scroll != null &&
          content.isLive &&
          content.generation > before.generation &&
          !content.hasNewOutput &&
          scroll.atLiveEdge &&
          (scroll.pixels ?? 1).abs() <= 0.5;
    });
    final content = TimelineObservation.parse(state);
    final scroll = TimelineScrollObservation.parse(state);
    content.requireConsistentIds();
    observations['return-$attempt'] = <String, Object?>{
      'timeline': content.summary(),
      'scroll': scroll.toJson(),
      'originalItemsCoveredExactlyOnce': true,
      'presentationItemCount': content.presentationItems.length,
      'groupsDefaultCollapsed': content.presentationItems.every(
        (item) => !item.expanded,
      ),
      'contentFillsViewportOrEof':
          (scroll.maxScrollExtent ?? 0) > 0 || !content.hasOlder,
      'autoFillExercised': content.itemCount > 32,
      'generationAdvanced': content.generation > before.generation,
    };
    await File('${output.path}/latest-fill-$attempt.png')
        .writeAsBytes(await driver.screenshot());
    await File('${output.path}/latest-fill-$attempt.json')
        .writeAsString(jsonEncode(state));
  }
  final keyboardStart = TimelineObservation.parse(await snapshot());
  await driver.sendCommand(
    RawTap(find.byValueKey('timeline-row-${keyboardStart.items.last.id}')),
  );
  Map<String, dynamic>? keyboardState;
  var keyCount = 0;
  for (; keyCount < 24; keyCount++) {
    // Flutter's public PageUp logical/physical values; the host cannot import dart:ui.
    await driver.sendCommand(KeyPress(0x00100000308, 0x0007004b));
    final stability = TimelineViewportStability();
    keyboardState = await until('keyboard-$keyCount', stability.accept);
    if (TimelineObservation.parse(keyboardState).itemCount >
        keyboardStart.itemCount) {
      keyCount++;
      break;
    }
  }
  final keyboardEnd = TimelineObservation.parse(keyboardState!);
  final keyboardPass =
      keyboardEnd.isHistory &&
      keyboardEnd.generation == keyboardStart.generation &&
      keyboardEnd.itemCount > keyboardStart.itemCount &&
      keyboardStart.itemIds.every(keyboardEnd.itemIds.contains) &&
      keyboardEnd.appendSeqAscending;
  observations['keyboardPagination'] = <String, Object?>{
    'input': 'focused message + native PageUp ScrollAction',
    'keyCount': keyCount,
    'before': keyboardStart.summary(),
    'after': keyboardEnd.summary(),
    'scroll': TimelineScrollObservation.parse(keyboardState).toJson(),
    'pass': keyboardPass,
  };
  await File('${output.path}/keyboard-pagination.png')
      .writeAsBytes(await driver.screenshot());
  await driver.sendCommand(RawTap(find.byValueKey('timeline-return-live')));
  final keyboardReturnStability = TimelineViewportStability();
  await until(
    'keyboard-return-live',
    (state) =>
        keyboardReturnStability.accept(state) &&
        TimelineObservation.parse(state).isLive &&
        TimelineObservation.parse(state).generation > keyboardEnd.generation,
  );
  observations['pass'] =
      keyboardPass &&
      (observations['automaticInitial']! as Map)['pass'] == true &&
      List.generate(2, (index) => observations['return-$index']! as Map).every(
        (record) =>
            record['originalItemsCoveredExactlyOnce'] == true &&
            record['groupsDefaultCollapsed'] == true &&
            record['contentFillsViewportOrEof'] == true &&
            record['autoFillExercised'] == true &&
            record['generationAdvanced'] == true,
      );
  return observations;
}
