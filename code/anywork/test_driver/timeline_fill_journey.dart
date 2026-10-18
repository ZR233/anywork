import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'pointer_scroll.dart';
import 'raw_tap.dart';
import 'timeline_observation.dart';

/// Native observation of the small canonical latest page after returning to live.
///
/// 最新小页由 tail 基线给出（默认 32 条），不是“窗口自动补满”。回到实时必须建立新
/// 代次并从新基线开始；重复执行都由显式「回到实时」触发，不靠向上滚动手势
/// （design/26 §26.3/§26.4）。
Future<Map<String, Object?>> observeLatestViewportFill(
  FlutterDriver driver,
  Directory output,
) async {
  final timeline = find.byValueKey('timeline-scrollable');
  Future<Map<String, dynamic>> snapshot() async =>
      (jsonDecode(await driver.requestData('snapshot')) as Map)
          .cast<String, dynamic>();

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
    final timeline = TimelineObservation.optional(state);
    return workspace?['isBusy'] == false &&
        (timeline?.items.any(
              (item) => item.text.contains('compact tail complete'),
            ) ??
            false);
  });

  final observations = <String, Object?>{};
  // 每次都由显式回到实时建立新代次：重复执行不需要任何向上手势。
  for (var attempt = 0; attempt < 2; attempt++) {
    final before = TimelineObservation.parse(await snapshot());
    await driver.sendCommand(PointerScroll(timeline, -250));
    await until(
      'detached-$attempt',
      (state) => TimelineObservation.optional(state)?.isHistory ?? false,
    );
    await driver.sendCommand(RawTap(find.byValueKey('timeline-return-live')));
    final filled = await until('filled-$attempt', (state) {
      final scroll = TimelineScrollObservation.optional(state);
      final latest = TimelineObservation.optional(state);
      if (scroll == null || latest == null) return false;
      return latest.isLive &&
          latest.generation > before.generation &&
          !latest.preparingLive &&
          latest.hasNewOutput == false &&
          scroll.laidOut &&
          !scroll.isScrolling &&
          scroll.generation == latest.generation &&
          scroll.atLiveEdge &&
          (scroll.extentAfter ?? 1).abs() <= 0.5 &&
          (scroll.pixels ?? 1).abs() <= 0.5;
    });
    final filledTimeline = TimelineObservation.parse(filled);
    final filledScroll = TimelineScrollObservation.parse(filled);
    observations['return-$attempt'] = <String, Object?>{
      'timeline': filledTimeline.summary(),
      'scroll': filledScroll.toJson(),
      // 最新小页：条数不超过 tail 基线，且内容确实高于视口（不是空白页）。
      'latestPageAtMostBaseline': filledTimeline.itemCount <= 32,
      'contentFillsViewport': (filledScroll.maxScrollExtent ?? 0) > 0,
      'generationAdvanced': filledTimeline.generation > before.generation,
    };
    await File('${output.path}/latest-fill-$attempt.png')
        .writeAsBytes(await driver.screenshot());
  }
  // 短内容不足一屏时的显式入口与触底分页共用同一个动作：入口存在时才点击它，
  // 并只以真实页请求结果（loadingOlder 收束、olderCursor 前进、身份保留）判定。
  final explicit = await _explicitLoadOlderIfShown(driver, output);
  observations['explicitLoadOlder'] = explicit;
  final attempts = <String, Object?>{
    for (var attempt = 0; attempt < 2; attempt++)
      'return-$attempt': observations['return-$attempt'],
  };
  final attemptsOk = attempts.values.every((value) {
    final record = value! as Map<String, Object?>;
    return record['latestPageAtMostBaseline'] == true &&
        record['contentFillsViewport'] == true &&
        record['generationAdvanced'] == true;
  });
  observations['pass'] = attemptsOk && explicit['pass'] == true;
  return observations;
}

/// 短屏「加载更早」入口：取真实事实并只在入口确实可见时点击一次。
///
/// - `hasOlder == false`：没有更早内容，入口**不应**出现；出现即失败。
/// - `hasOlder == true` 且入口可见：必须真实前进（页数增长、身份保留、游标变化）。
/// - `hasOlder == true` 且入口不可见：只有“内容填满视口”才成立，不用 false 证明已加载。
Future<Map<String, Object?>> _explicitLoadOlderIfShown(
  FlutterDriver driver,
  Directory output,
) async {
  Future<Map<String, dynamic>> snapshot() async =>
      (jsonDecode(await driver.requestData('snapshot')) as Map)
          .cast<String, dynamic>();
  final entry = find.byValueKey('timeline-load-older');
  var shown = true;
  try {
    await driver.waitFor(entry, timeout: const Duration(seconds: 3));
  } on Object {
    shown = false;
  }
  final beforeState = await snapshot();
  final before = TimelineObservation.parse(beforeState);
  final scroll = TimelineScrollObservation.parse(beforeState);
  if (!shown) {
    if (!before.hasOlder) {
      return <String, Object?>{
        'shown': false,
        'hasOlder': false,
        'reason': 'no older content exists, so no explicit entry is expected',
        'pass': true,
      };
    }
    final fillsViewport = (scroll.maxScrollExtent ?? 0) > 0;
    return <String, Object?>{
      'shown': false,
      'hasOlder': true,
      'contentFillsViewport': fillsViewport,
      'reason':
          'the short-content entry is only shown below one viewport of content',
      // 入口不可见时不能用“没有增长”证明已加载：只认可内容确实填满视口这一事实。
      'pass': fillsViewport,
    };
  }
  if (!before.hasOlder) {
    return <String, Object?>{
      'shown': true,
      'hasOlder': false,
      'reason': 'an explicit older entry was rendered with no older content',
      'pass': false,
    };
  }
  await driver.sendCommand(RawTap(entry));
  // 点击后第一次快照可能还没进入 loading：等待真实状态机（loading → 收束，或页已落地，
  // 或显式错误，或到达 EOF），不用固定延迟也不用“看起来没 loading 就算完成”。
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  var sawLoading = false;
  while (DateTime.now().isBefore(deadline)) {
    final state = await snapshot();
    final after = TimelineObservation.parse(state);
    if (after.loadingOlder) {
      sawLoading = true;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      continue;
    }
    final delivered = after.itemCount - before.itemCount;
    final cursorMoved =
        after.olderCursor != before.olderCursor || !after.hasOlder;
    final settled =
        sawLoading ||
        delivered > 0 ||
        after.olderError != null ||
        !after.hasOlder;
    if (!settled) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      continue;
    }
    final retained = before.itemIds.every(after.itemIds.contains);
    await File('${output.path}/explicit-load-older.json')
        .writeAsString(jsonEncode(state));
    return <String, Object?>{
      'shown': true,
      'hasOlderBefore': true,
      'beforeItems': before.itemCount,
      'afterItems': after.itemCount,
      'delivered': delivered,
      'identityRetained': retained,
      'cursorMoved': cursorMoved,
      'sawLoading': sawLoading,
      'olderCursorAfter': after.olderCursor,
      'hasOlderAfter': after.hasOlder,
      'loadingOlder': after.loadingOlder,
      'olderError': after.olderError,
      // 错误/无交付/丢身份都失败；EOF 也是收束（交付可以是最后一页）。
      'pass':
          after.olderError == null && retained && delivered > 0 && cursorMoved,
    };
  }
  throw StateError('Explicit load-older never settled');
}
