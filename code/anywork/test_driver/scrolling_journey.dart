import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'pointer_scroll.dart';
import 'raw_tap.dart';
import 'scrollbar_drag.dart';
import 'timeline_observation.dart';
import 'tool_probe.dart';

/// 判定真实 thumb 采样；仅将前一帧已越界、当前精确落回该边界的反向位移
/// 视为范围夹紧。夹紧不计入用户方向的连续位移次数。
Map<String, Object?> assessThumbDrag(List<dynamic> samples, bool increasing) {
  var changes = 0;
  final clamps = <Map<String, Object?>>[];
  Map<String, Object?> invalid(String reason, int index) => <String, Object?>{
    'continuous': false,
    'directionalChanges': 0,
    'clamps': clamps,
    'invalidReason': reason,
    'invalidIndex': index,
  };
  if (samples.isEmpty || samples.first is! Map) {
    return invalid('missingBaseline', 0);
  }
  final baseline = samples.first as Map;
  final threadId = baseline['threadId'];
  final generation = baseline['generation'];
  if (threadId is! String ||
      threadId.trim().isEmpty ||
      generation is! int ||
      generation < 0) {
    return invalid('invalidIdentity', 0);
  }
  for (var index = 0; index < samples.length; index++) {
    final sample = samples[index];
    if (sample is! Map) return invalid('invalidSample', index);
    if (sample['threadId'] != threadId ||
        sample['generation'] is! int ||
        sample['generation'] != generation) {
      return invalid('identityMismatch', index);
    }
    final pixels = sample['pixels'];
    final min = sample['minScrollExtent'];
    final max = sample['maxScrollExtent'];
    final viewport = sample['viewportDimension'];
    if (pixels is! num ||
        !pixels.isFinite ||
        min is! num ||
        !min.isFinite ||
        max is! num ||
        !max.isFinite ||
        min > max ||
        viewport is! num ||
        !viewport.isFinite ||
        viewport <= 0) {
      return invalid('invalidGeometry', index);
    }
  }
  for (var index = 1; index < samples.length; index++) {
    final previous = samples[index - 1] as Map;
    final current = samples[index] as Map;
    final before = previous['pixels'] as num;
    final after = current['pixels'] as num;
    final delta = after - before;
    if (increasing ? delta < -0.5 : delta > 0.5) {
      final min = previous['minScrollExtent'] as num;
      final max = previous['maxScrollExtent'] as num;
      final currentMin = current['minScrollExtent'] as num;
      final currentMax = current['maxScrollExtent'] as num;
      final clamped =
          currentMin <= after &&
          after <= currentMax &&
          (increasing
              ? before > max && after == max
              : before < min && after == min);
      if (!clamped) {
        return <String, Object?>{
          'continuous': false,
          'directionalChanges': changes,
          'clamps': clamps,
          'reverseIndex': index,
        };
      }
      clamps.add(<String, Object?>{
        'index': index,
        'previous': previous,
        'current': current,
      });
    } else if (increasing ? delta > 0.5 : delta < -0.5) {
      changes++;
    }
  }
  return <String, Object?>{
    'continuous': changes >= 12,
    'directionalChanges': changes,
    'clamps': clamps,
  };
}

/// Opt-in native observation of the standard timeline scroll behaviour.
///
/// 全部依据只读事实：`timeline`（展示代次/模式/身份）与 `timelineScroll`（当前标准
/// `ScrollController` 几何）。滚轮是真实指针输入；到达已加载集合的本地底端不会改变
/// 阅读意图，显式「回到实时」保留同一 lease、完整窗口与消费身份（design/26 §26.8）。
Future<Map<String, Object?>> observeTimelineScrolling(
  String vmUrl,
  Directory output,
) async {
  final driver = await FlutterDriver.connect(dartVmServiceUrl: vmUrl);
  final timelineFinder = find.byValueKey('timeline-scrollable');
  final observations = <String, Object?>{};
  Future<Map<String, dynamic>> snapshot() async =>
      (jsonDecode(await driver.requestData('snapshot')) as Map)
          .cast<String, dynamic>();

  /// 一次真实输入的收束条件：几何已发布且没有在途滚动活动。
  Future<TimelineScrollObservation> settle({
    int? expectGeneration,
    String? stage,
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      final state = await snapshot();
      final scroll = TimelineScrollObservation.optional(state);
      if (scroll != null &&
          scroll.laidOut &&
          !scroll.isScrolling &&
          (expectGeneration == null || scroll.generation == expectGeneration)) {
        return scroll;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await File('${output.path}/scroll-timeout-${stage ?? 'settle'}.json')
        .writeAsString(jsonEncode(await snapshot()));
    throw StateError('Timeline geometry did not settle: ${stage ?? 'settle'}');
  }

  try {
    await driver.sendCommand(SetFrameSync(false));
    final initial = await settle(stage: 'initial');
    final initialTimeline = TimelineObservation.parse(await snapshot());
    observations['initial'] = initial.toJson();
    observations['initialTimeline'] = initialTimeline.summary();
    // 从最新小页开始：offset 0、几何贴底、Live 模式。
    final wheel = <Map<String, Object?>>[initial.toJson()];
    for (var step = 0; step < 8; step++) {
      await driver.sendCommand(PointerScroll(timelineFinder, -60));
      wheel.add((await settle(stage: 'wheel-$step')).toJson());
    }
    observations['wheel'] = wheel;
    observations['wheelViewportStable'] = wheel.every(
      (sample) =>
          sample['viewportDimension'] == wheel.first['viewportDimension'],
    );
    observations['forwardCoordinates'] = wheel.every(
      (sample) => sample['minScrollExtent'] == 0,
    );
    // 真实上翻位移：每一步 offset 都按输入前进 60（或已到冻结集合边界）。
    observations['wheelContinuous'] = List.generate(wheel.length - 1, (index) {
      final delta =
          (wheel[index + 1]['pixels'] as num) - (wheel[index]['pixels'] as num);
      return (delta - 60).abs() < 0.5 ||
          wheel[index + 1]['pixels'] == wheel[index + 1]['maxScrollExtent'];
    }).every((moved) => moved);
    final afterWheel = TimelineObservation.parse(await snapshot());
    // 离开真实底端后进入 History：这是阅读意图，不改变完成项接纳。
    observations['wheelDetached'] =
        afterWheel.isHistory && (wheel.last['pixels'] as num) > 0.5;
    await File('${output.path}/scroll-wheel.png')
        .writeAsBytes(await driver.screenshot());

    final returning = <Map<String, Object?>>[];
    for (var step = 0; step < 12; step++) {
      await driver.sendCommand(PointerScroll(timelineFinder, 60));
      final state = await settle(stage: 'return-$step');
      returning.add(state.toJson());
      if (state.atLiveEdge) break;
    }
    observations['wheelReturning'] = returning;
    final returned = returning.last;
    final returnedTimeline = TimelineObservation.parse(await snapshot());
    // 到达已加载集合的本地底端：几何贴底，但仍然是同一个 History 代次。
    //
    // 标准反向列表的底端是 offset 0（`extentBefore` 0、`extentAfter` 为全部可滚动
    // 内容）；`extentAfter ≈ 0` 是非反向 ListView 的贴底语义，不能拿来判反向列表。
    observations['wheelReachedFrozenBottom'] =
        returnedTimeline.isHistory &&
        returnedTimeline.generation == afterWheel.generation &&
        returned['atLiveEdge'] == true &&
        (returned['extentBefore'] as num? ?? 1).abs() <= 0.5 &&
        (returned['pixels'] as num? ?? 1).abs() <= 0.5;
    await File('${output.path}/scroll-wheel-latest.png')
        .writeAsBytes(await driver.screenshot());

    final state = await snapshot();
    final current = TimelineObservation.parse(state);
    current.requireConsistentIds();
    if (current.presentationItems.isEmpty) {
      throw StateError('Timeline exposes no presentation row to observe');
    }
    final lastPresentationId = current.presentationItems.last.id;
    final view = await driver.sendCommand(ToolProbe(timelineFinder, 'observe'));
    final last = await driver.sendCommand(
      ToolProbe(find.byValueKey('timeline-row-$lastPresentationId'), 'observe'),
    );
    final viewport = (view['samples'] as List).last as Map;
    final tail = (last['samples'] as List).last as Map;
    observations['latestRowId'] = lastPresentationId;
    observations['latestRowGeometry'] = tail;
    observations['wheelLastLineVisible'] =
        tail['mounted'] != false &&
        (tail['height'] as num) > 0 &&
        (tail['top'] as num) + (tail['height'] as num) >
            (viewport['top'] as num) &&
        (tail['top'] as num) + (tail['height'] as num) <=
            (viewport['top'] as num) + (viewport['height'] as num) + 0.5;

    final up = await driver.sendCommand(ScrollbarDrag(timelineFinder, -140));
    observations['thumbUp'] = up;
    await File('${output.path}/scroll-thumb-up.png')
        .writeAsBytes(await driver.screenshot());
    final down = await driver.sendCommand(ScrollbarDrag(timelineFinder, 80));
    observations['thumbDown'] = down;
    // 视觉上把 thumb 向上拖（负 dy）让 offset 增长（内容向更早方向移动）；向下拖
    // 让 offset 减少。方向写反会把正确滚动判成错误，因此按真实反向坐标断言。
    final upAssessment = assessThumbDrag(up['samples'] as List, true);
    final downAssessment = assessThumbDrag(down['samples'] as List, false);
    observations['thumbUpAssessment'] = upAssessment;
    observations['thumbDownAssessment'] = downAssessment;
    observations['thumbUpContinuous'] = upAssessment['continuous'];
    observations['thumbDownContinuous'] = downAssessment['continuous'];

    // 显式回到实时只改变阅读意图与滚动位置，不重开基线或裁掉已加载窗口。
    final beforeReturn = TimelineObservation.parse(await snapshot());
    beforeReturn.requireConsistentIds();
    if (!beforeReturn.isHistory ||
        !beforeReturn.ready ||
        beforeReturn.connection != 'ready' ||
        beforeReturn.generation < 1 ||
        beforeReturn.timelineEpoch == null ||
        beforeReturn.items.isEmpty ||
        !beforeReturn.appendSeqAscending ||
        beforeReturn.loadedCount != beforeReturn.itemCount ||
        beforeReturn.completedThrough != beforeReturn.items.last.appendSeq) {
      throw StateError('Return to live lacks a valid loaded History lease');
    }
    await driver.sendCommand(RawTap(find.byValueKey('timeline-return-live')));
    // generation 就是当前 lease 的身份；几何与内容必须仍属于同一 Thread/epoch/lease。
    final returnDeadline = DateTime.now().add(const Duration(seconds: 30));
    late TimelineScrollObservation returnedLive;
    late TimelineObservation liveTimeline;
    while (true) {
      final settledScroll = await settle(stage: 'return-live');
      final timeline = TimelineObservation.parse(await snapshot());
      if (timeline.isLive &&
          timeline.ready &&
          timeline.connection == 'ready' &&
          timeline.threadId == beforeReturn.threadId &&
          timeline.timelineEpoch == beforeReturn.timelineEpoch &&
          timeline.generation == beforeReturn.generation &&
          settledScroll.threadId == timeline.threadId &&
          settledScroll.generation == timeline.generation &&
          settledScroll.atLiveEdge &&
          (settledScroll.pixels ?? 1).abs() <= 0.5 &&
          !timeline.hasNewOutput) {
        returnedLive = settledScroll;
        liveTimeline = timeline;
        break;
      }
      if (DateTime.now().isAfter(returnDeadline)) {
        throw StateError(
          'Explicit return to live did not settle on the original lease',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    observations['returnedToLatest'] = <String, Object?>{
      'scroll': returnedLive.toJson(),
      'timeline': liveTimeline.summary(),
    };
    liveTimeline.requireConsistentIds();
    final firstKept = liveTimeline.itemIds.indexOf(beforeReturn.itemIds.first);
    final retainedEnd = firstKept + beforeReturn.items.length;
    // 只有返回前已在途的分页可前插；前缀必须为正序号且无缺口地接到旧首项。
    final prefixAuthorizedAndContinuous =
        firstKept == 0 ||
        (firstKept > 0 &&
            beforeReturn.loadingOlder &&
            List.generate(firstKept, (index) {
              final sequence = liveTimeline.items[index].appendSeq;
              return sequence > 0 &&
                  sequence ==
                      beforeReturn.items.first.appendSeq - firstKept + index;
            }).every((continuous) => continuous));
    final windowPreserved =
        firstKept >= 0 &&
        prefixAuthorizedAndContinuous &&
        retainedEnd <= liveTimeline.items.length &&
        jsonEncode([
              for (final item in beforeReturn.items) item.frozenFields(),
            ]) ==
            jsonEncode([
              for (final item in liveTimeline.items.sublist(
                firstKept,
                retainedEnd,
              ))
                item.frozenFields(),
            ]);
    final beforeH = beforeReturn.completedThrough!;
    final afterH = liveTimeline.completedThrough;
    final appended = liveTimeline.items
        .where((item) => item.appendSeq > beforeH)
        .toList();
    // 旧窗口可因已发起的分页前插而右移；尾部只能接纳 H 后的连续完成项。
    final completionContinuous =
        afterH != null &&
        afterH >= beforeH &&
        liveTimeline.appendSeqAscending &&
        liveTimeline.loadedCount == liveTimeline.itemCount &&
        liveTimeline.items.isNotEmpty &&
        liveTimeline.items.last.appendSeq == afterH &&
        appended.length == afterH - beforeH &&
        List.generate(
          appended.length,
          (index) => appended[index].appendSeq == beforeH + index + 1,
        ).every((continuous) => continuous);
    final keptIds = beforeReturn.itemIds.toSet();
    final presentationPositionsValid = [beforeReturn, liveTimeline].every(
      (timeline) =>
          [
            ...timeline.presentationItems,
            ...timeline.hiddenPresentationItems,
          ].every(
            (group) =>
                group.firstAppendSeq ==
                timeline.item(group.memberIds.first)?.appendSeq,
          ),
    );
    // 投影回原窗口后，展示 owner 的身份、顺序和完整成员关系必须原样保留；
    // 新分页或完成项可扩展边界组，但不能把旧成员移到另一组或另造 owner。
    // visibleMemberIds/skillPairs 随完整组扩展派生，不在此冻结或重验配对算法。
    List<Map<String, Object?>> membership(
      List<TimelinePresentationObservation> groups,
    ) => [
      for (final group in groups)
        if (group.memberIds.any(keptIds.contains))
          <String, Object?>{
            'id': group.id,
            'kind': group.kind,
            'memberIds': group.memberIds.where(keptIds.contains).toList(),
            'expanded': group.expanded,
          },
    ];
    final presentationPreserved =
        jsonEncode(membership(beforeReturn.presentationItems)) ==
            jsonEncode(membership(liveTimeline.presentationItems)) &&
        jsonEncode(membership(beforeReturn.hiddenPresentationItems)) ==
            jsonEncode(membership(liveTimeline.hiddenPresentationItems));
    observations['returnLivePreservesLoadedWindow'] =
        liveTimeline.isLive &&
        liveTimeline.threadId == beforeReturn.threadId &&
        liveTimeline.timelineEpoch == beforeReturn.timelineEpoch &&
        liveTimeline.generation == beforeReturn.generation &&
        returnedLive.threadId == liveTimeline.threadId &&
        returnedLive.generation == liveTimeline.generation &&
        returnedLive.atLiveEdge &&
        (returnedLive.pixels ?? 1).abs() <= 0.5 &&
        !liveTimeline.hasNewOutput &&
        windowPreserved &&
        presentationPositionsValid &&
        presentationPreserved &&
        completionContinuous;
    observations['returnLivePreservation'] = <String, Object?>{
      'before': beforeReturn.summary(),
      'after': liveTimeline.summary(),
      'scrollGeneration': returnedLive.generation,
      'beforeItemIds': beforeReturn.itemIds,
      'afterItemIds': liveTimeline.itemIds,
      'prefixAuthorizedAndContinuous': prefixAuthorizedAndContinuous,
      'windowPreserved': windowPreserved,
      'presentationPositionsValid': presentationPositionsValid,
      'presentationPreserved': presentationPreserved,
      'beforePresentationMembership': membership(
        beforeReturn.presentationItems,
      ),
      'afterPresentationMembership': membership(liveTimeline.presentationItems),
      'beforeHiddenMembership': membership(
        beforeReturn.hiddenPresentationItems,
      ),
      'afterHiddenMembership': membership(liveTimeline.hiddenPresentationItems),
      'completionContinuous': completionContinuous,
      'appendedSequences': [for (final item in appended) item.appendSeq],
    };
    observations['pass'] = [
      'wheelViewportStable',
      'forwardCoordinates',
      'wheelDetached',
      'wheelContinuous',
      'wheelReachedFrozenBottom',
      'wheelLastLineVisible',
      'thumbUpContinuous',
      'thumbDownContinuous',
      'returnLivePreservesLoadedWindow',
    ].every((key) => observations[key] == true);
    return observations;
  } finally {
    observations['humanVerdict'] = 'pending';
    await File('${output.path}/scrolling.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(observations)}\n',
    );
    await driver.close();
  }
}
