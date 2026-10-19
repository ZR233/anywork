// Opt-in companion to manual-gui --scenario stress / timeline-history, after its
// initial history observation settles. Exercises real wheel input across layout
// changes on the standard timeline list.
//
// 判定全部来自只读事实：`timeline`（代次/模式/身份/分页状态）与 `timelineScroll`
// （当前标准 ScrollController 的几何）。resize 不得制造阅读意图，滚轮到达冻结集合的
// 本地底端不得跨越后台输出或跳最新，只有显式「回到实时」建立新代次。
// On X11, run this client with the GUI's DISPLAY and XAUTHORITY as well.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'pointer_scroll.dart';
import 'raw_tap.dart';
import 'timeline_observation.dart';
import 'window_control.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    throw ArgumentError('expected <vm-url> <evidence-directory>');
  }
  final driver = await FlutterDriver.connect(dartVmServiceUrl: args[0]);
  final output = Directory(args[1])..createSync(recursive: true);
  final timelineFinder = find.byValueKey('timeline-scrollable');
  final observations = <String, Object?>{};
  final pid =
      (jsonDecode(await driver.requestData('pid')) as Map)['pid'] as int;

  Future<Map<String, dynamic>> snapshot() async =>
      (jsonDecode(await driver.requestData('snapshot')) as Map)
          .cast<String, dynamic>();

  /// 收束条件：几何已发布、没有在途滚动、没有准备中的新代次。
  Future<Map<String, dynamic>> settle({String? stage}) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      final state = await snapshot();
      if (timelineViewportSettled(state)) {
        return state;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final state = await snapshot();
    await File('${output.path}/edge-timeout-${stage ?? 'settle'}.json')
        .writeAsString(jsonEncode(state));
    throw StateError('Timeline did not settle: ${stage ?? 'settle'}');
  }

  Map<String, Object?> summary(Map<String, dynamic> state) => <String, Object?>{
    'timeline': TimelineObservation.parse(state).summary(),
    'scroll': TimelineScrollObservation.parse(state).toJson(),
  };

  Future<Map<String, Object?>> returnLive(String stage) async {
    final before = TimelineObservation.parse(await snapshot());
    await driver.sendCommand(RawTap(find.byValueKey('timeline-return-live')));
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      final state = await settle(stage: stage);
      final timeline = TimelineObservation.parse(state);
      if (timeline.isLive && timeline.generation > before.generation) {
        return summary(state);
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('Explicit return to live did not create a new generation');
  }

  try {
    await driver.sendCommand(SetFrameSync(false));
    for (final height in [2400, 5000]) {
      final evidence = <String, Object?>{};
      observations['height-$height'] = evidence;
      evidence['returnedToLive'] = await returnLive('height-$height-live');
      final initial = await settle(stage: 'height-$height-initial');
      final initialTimeline = TimelineObservation.parse(initial);
      final initialScroll = TimelineScrollObservation.parse(initial);
      final latestItem = initialTimeline.itemIds.isEmpty
          ? null
          : initialTimeline.itemIds.last;
      evidence['initial'] = summary(initial);
      // resize 不得制造阅读意图：Live 保持 Live，几何贴底。
      final resized = resizeOwnedWindow(
        guiPid: pid,
        width: 1280,
        height: height,
      );
      if (!resized.resized) {
        throw StateError('${resized.reason}: ${resized.diagnostics}');
      }
      final original = resized.original!;
      try {
        final afterResize = await settle(stage: 'height-$height-resized');
        final resizedTimeline = TimelineObservation.parse(afterResize);
        final resizedScroll = TimelineScrollObservation.parse(afterResize);
        evidence['resizeInLive'] = <String, Object?>{
          'summary': summary(afterResize),
          'stayedLive': resizedTimeline.isLive,
          'sameGeneration':
              resizedTimeline.generation == initialTimeline.generation,
          'stillAtLiveEdge': resizedScroll.atLiveEdge,
          'pixelsAtTop': (resizedScroll.pixels ?? 1).abs() <= 0.5,
          'viewportChanged':
              resizedScroll.viewportDimension !=
              initialScroll.viewportDimension,
        };
        final older = <Object?>[];
        for (var step = 0; step < 6; step++) {
          await driver.sendCommand(PointerScroll(timelineFinder, -1000000));
          final state = await settle(stage: 'height-$height-older-$step');
          older.add(summary(state));
        }
        evidence['older'] = older;
        final paged = TimelineObservation.parse(await snapshot());
        // 冻结已展示结构：初始身份一个都不能丢，最新端身份不变，代次不换代。
        final retained = initialTimeline.itemIds.every(paged.itemIds.contains);
        evidence['paging'] = <String, Object?>{
          'mode': paged.mode,
          'generation': paged.generation,
          'initialItems': initialTimeline.itemCount,
          'pagedItems': paged.itemCount,
          'pagingHappened': paged.itemCount > initialTimeline.itemCount,
          'identityRetained': retained,
          'canonicalOrder': paged.ordinalAscending,
          'latestUnchanged':
              latestItem == null || paged.itemIds.last == latestItem,
          'olderCursor': paged.olderCursor,
          'hasOlder': paged.hasOlder,
        };
        final newer = <Object?>[];
        var reachedBottom = false;
        for (var step = 0; step < 24; step++) {
          await driver.sendCommand(PointerScroll(timelineFinder, 1000000));
          final state = await settle(stage: 'height-$height-newer-$step');
          newer.add(summary(state));
          final scroll = TimelineScrollObservation.parse(state);
          if (scroll.atLiveEdge) {
            reachedBottom = true;
            break;
          }
        }
        evidence['newer'] = newer;
        final endpointState = await snapshot();
        final endpointTimeline = TimelineObservation.parse(endpointState);
        final endpointScroll = TimelineScrollObservation.parse(endpointState);
        evidence['endpoint'] = summary(endpointState);
        // 到达冻结集合的本地底端仍是同一个 History 代次：不跨越后台输出、不跳最新。
        evidence['endpointStayedFrozen'] = <String, Object?>{
          'reachedBottom': reachedBottom,
          'mode': endpointTimeline.mode,
          'generation': endpointTimeline.generation,
          'sameGeneration': endpointTimeline.generation == paged.generation,
          'extentAfter': endpointScroll.extentAfter,
          'latestUnchanged':
              latestItem == null || endpointTimeline.itemIds.last == latestItem,
          'hasNewOutput': endpointTimeline.hasNewOutput,
        };
        await driver.waitUntilNoTransientCallbacks();
        await driver.screenshot();
        await driver.sendCommand(PointerScroll(timelineFinder, 60));
        final afterOneStep = TimelineObservation.parse(
          await settle(stage: 'height-$height-endpoint-wheel'),
        );
        await File('${output.path}/edge-$height.png')
            .writeAsBytes(await driver.screenshot());
        final returned = await returnLive('height-$height-return');
        final liveTimeline = TimelineObservation.parse(await snapshot());
        evidence['returned'] = returned;
        evidence['pass'] =
            (evidence['resizeInLive'] as Map)['stayedLive'] == true &&
            (evidence['resizeInLive'] as Map)['stillAtLiveEdge'] == true &&
            (evidence['paging'] as Map)['pagingHappened'] == true &&
            (evidence['paging'] as Map)['identityRetained'] == true &&
            (evidence['paging'] as Map)['canonicalOrder'] == true &&
            (evidence['paging'] as Map)['latestUnchanged'] == true &&
            reachedBottom &&
            endpointTimeline.isHistory &&
            endpointTimeline.generation == paged.generation &&
            afterOneStep.generation == paged.generation &&
            liveTimeline.isLive;
      } finally {
        final restored = resizeOwnedWindow(
          guiPid: pid,
          width: original.width,
          height: original.height,
        );
        if (!restored.resized) throw StateError('Window restoration failed');
        await settle(stage: 'height-$height-restored');
      }
    }
    // Repeated small wheel steps must traverse paged history without idle
    // streaming flushes restoring a stale, pre-layout reading position, and a
    // single tick must never jump a whole page or to latest.
    await returnLive('rapid-live');
    final initial = await settle(stage: 'rapid-initial');
    final initialTimeline = TimelineObservation.parse(initial);
    final latestItem = initialTimeline.itemIds.isEmpty
        ? null
        : initialTimeline.itemIds.last;
    final rapid = <String, Object?>{
      'initial': summary(initial),
      'older': <Object?>[],
      'newer': <Object?>[],
      'singleTickPageJumps': <Object?>[],
    };
    observations['rapid-history'] = rapid;
    final olderSteps = rapid['older']! as List<Object?>;
    var previousCount = initialTimeline.itemCount;
    var previousGeneration = initialTimeline.generation;
    for (var step = 0; step < 100; step++) {
      await driver.sendCommand(PointerScroll(timelineFinder, -60));
      final state = await snapshot();
      final paged = TimelineObservation.parse(state);
      olderSteps.add(summary(state));
      if (paged.itemCount - previousCount > 32) {
        (rapid['singleTickPageJumps']! as List<Object?>).add(<String, Object?>{
          'step': step,
          'before': previousCount,
          'after': paged.itemCount,
        });
      }
      if (paged.generation != previousGeneration) {
        (rapid['singleTickPageJumps']! as List<Object?>).add(<String, Object?>{
          'step': step,
          'generationBefore': previousGeneration,
          'generationAfter': paged.generation,
        });
      }
      previousCount = paged.itemCount;
      previousGeneration = paged.generation;
    }
    final afterOlder = TimelineObservation.parse(await snapshot());
    final newerSteps = rapid['newer']! as List<Object?>;
    var reachedBottom = false;
    for (var step = 0; step < 200; step++) {
      await driver.sendCommand(PointerScroll(timelineFinder, 60));
      final state = await snapshot();
      newerSteps.add(summary(state));
      final scroll = TimelineScrollObservation.parse(state);
      final paged = TimelineObservation.parse(state);
      if (paged.generation != initialTimeline.generation) {
        (rapid['singleTickPageJumps']! as List<Object?>).add(<String, Object?>{
          'step': step,
          'generationBefore': initialTimeline.generation,
          'generationAfter': paged.generation,
          'phase': 'newer',
        });
      }
      if (scroll.atLiveEdge) {
        reachedBottom = true;
        break;
      }
    }
    final returned = await settle(stage: 'rapid-returned');
    final returnedTimeline = TimelineObservation.parse(returned);
    rapid['returned'] = summary(returned);
    rapid['pass'] =
        afterOlder.isHistory &&
        reachedBottom &&
        returnedTimeline.isHistory &&
        returnedTimeline.generation == initialTimeline.generation &&
        (rapid['singleTickPageJumps']! as List<Object?>).isEmpty &&
        (latestItem == null || returnedTimeline.itemIds.last == latestItem);
    await File('${output.path}/rapid-history.png')
        .writeAsBytes(await driver.screenshot());
    if (rapid['pass'] != true) {
      throw StateError(
        'Repeated wheel input broke the frozen history contract',
      );
    }
    // Regression: returning to live must clear the previous history generation.
    // The first subsequent wheel step enters History again from the new tail,
    // rather than reusing the old generation or opening the oldest page.
    final liveSummary = await returnLive('jump-then-browse-live');
    final liveTimeline = TimelineObservation.parse(await snapshot());
    await driver.sendCommand(PointerScroll(timelineFinder, -60));
    final browsed = await settle(stage: 'jump-then-browse');
    final browsedTimeline = TimelineObservation.parse(browsed);
    final browsedScroll = TimelineScrollObservation.parse(browsed);
    final jumpThenBrowse = <String, Object?>{
      'afterReturnLive': liveSummary,
      'afterOneOlderWheel': summary(browsed),
      'pass':
          liveTimeline.isLive &&
          browsedTimeline.isHistory &&
          browsedTimeline.generation == liveTimeline.generation &&
          browsedScroll.pixels != null &&
          browsedScroll.pixels! > 0.5 &&
          (latestItem == null || browsedTimeline.itemIds.last == latestItem),
    };
    observations['jump-then-browse'] = jumpThenBrowse;
    if (jumpThenBrowse['pass'] != true) {
      throw StateError(
        'A wheel step after returning to live reused a stale history generation',
      );
    }
    if (observations.values.any((value) => (value as Map)['pass'] != true)) {
      throw StateError(
        'History edge conditions failed: '
        '${observations.entries.where((entry) => (entry.value as Map)['pass'] != true).map((entry) => entry.key).toList()}',
      );
    }
    observations['pass'] = true;
  } catch (error) {
    observations['error'] = error.toString();
    rethrow;
  } finally {
    observations['humanVerdict'] = 'pending';
    await File('${output.path}/timeline-edge.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(observations)}\n',
    );
    await driver.close();
  }
}
