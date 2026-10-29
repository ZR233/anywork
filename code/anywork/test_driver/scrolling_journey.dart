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
/// `ScrollController` 几何）。滚轮是真实指针输入；到达冻结集合的本地底端**不会**回到
/// 实时，只有显式「回到实时」才建立新代次（design/26 §26.3）。
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
    // 离开真实底端后进入 History：这是内容发布策略，不是像素贴底事实。
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
    // 到达冻结集合的本地底端：几何贴底，但仍然是同一个 History 代次。
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
    if (current.items.isEmpty) {
      throw StateError('Timeline exposes no canonical item to observe');
    }
    final view = await driver.sendCommand(ToolProbe(timelineFinder, 'observe'));
    final last = await driver.sendCommand(
      ToolProbe(
        find.byValueKey('timeline-row-${current.items.last.id}'),
        'observe',
      ),
    );
    final viewport = (view['samples'] as List).last as Map;
    final tail = (last['samples'] as List).last as Map;
    observations['latestRowGeometry'] = tail;
    observations['wheelLastLineVisible'] =
        tail['mounted'] != false &&
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

    // 显式回到实时：新代次、最新小页、offset 0。滚动条/滚轮到本地底端不会自行换代。
    final beforeReturn = TimelineObservation.parse(await snapshot());
    await driver.sendCommand(RawTap(find.byValueKey('timeline-return-live')));
    // 只要求“建立了更新的代次”：代次由 owner 单调递增，跨越多个内部重同步时
    // 增量可能大于 1；真正要证明的是新代次属于本 Thread 且几何归它所有。
    // 成功前旧 History 一直保留，所以等到旧代次被新 Live 代次替换再看。
    final returnDeadline = DateTime.now().add(const Duration(seconds: 30));
    late TimelineScrollObservation returnedLive;
    late TimelineObservation liveTimeline;
    while (true) {
      final settledScroll = await settle(stage: 'return-live');
      final timeline = TimelineObservation.parse(await snapshot());
      if (timeline.isLive &&
          timeline.generation > beforeReturn.generation &&
          settledScroll.generation == timeline.generation) {
        returnedLive = settledScroll;
        liveTimeline = timeline;
        break;
      }
      if (DateTime.now().isAfter(returnDeadline)) {
        throw StateError(
          'Explicit return to live did not establish a new generation',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    observations['returnedToLatest'] = <String, Object?>{
      'scroll': returnedLive.toJson(),
      'timeline': liveTimeline.summary(),
    };
    observations['returnLiveNewGeneration'] =
        liveTimeline.isLive &&
        liveTimeline.generation > beforeReturn.generation &&
        returnedLive.generation == liveTimeline.generation &&
        returnedLive.atLiveEdge &&
        (returnedLive.pixels ?? 1).abs() <= 0.5 &&
        liveTimeline.hasNewOutput == false;
    observations['returnLiveGeneration'] = <String, Object?>{
      'before': beforeReturn.generation,
      'after': liveTimeline.generation,
      'scrollGeneration': returnedLive.generation,
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
      'returnLiveNewGeneration',
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
