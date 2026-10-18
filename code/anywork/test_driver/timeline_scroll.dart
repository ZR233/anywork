// Manual companion to the native stress-body-large journey. Attach before the
// stream starts: cargo dart run test_driver/timeline_scroll.dart <vm-url> <dir>.
// It drives actual drag/wheel events; snapshots only observe the standard
// timeline facts and the current ScrollController geometry.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'pointer_drag.dart';
import 'pointer_scroll.dart';
import 'raw_tap.dart';
import 'scrollbar_drag.dart';
import 'timeline_observation.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    throw ArgumentError('expected <vm-url> <evidence-directory>');
  }
  final driver = await FlutterDriver.connect(dartVmServiceUrl: args[0]);
  final output = Directory(args[1])..createSync(recursive: true);
  final observations = <String, Object?>{};
  final timelineFinder = find.byValueKey('timeline-scrollable');
  await driver.sendCommand(SetFrameSync(false));

  Future<Map<String, dynamic>> snapshot() async =>
      (jsonDecode(await driver.requestData('snapshot')) as Map)
          .cast<String, dynamic>();

  Map<String, Object?> geometry(Map<String, dynamic> state) =>
      <String, Object?>{
        'timeline': TimelineObservation.parse(state).summary(),
        'scroll': TimelineScrollObservation.parse(state).toJson(),
      };

  void record(String phase, Map<String, dynamic> state) {
    observations[phase] = <String, Object?>{
      'bodyCharacters': _bodyCharacters(state),
      'busy': _busy(state),
      ...geometry(state),
    };
  }

  Future<Map<String, dynamic>> waitFor(
    String label,
    bool Function(Map<String, dynamic>) condition,
  ) async {
    await File('${output.path}/stage.txt').writeAsString('$label\n');
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    Map<String, dynamic>? last;
    while (DateTime.now().isBefore(deadline)) {
      final state = await snapshot();
      last = state;
      if (condition(state)) return state;
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    if (last != null) record('timeoutState', last);
    throw StateError('timed out: $label');
  }

  /// 几何与展示都处于稳定态：无在途滚动、无准备中的新代次、几何属于当前代次。
  bool idle(Map<String, dynamic> state) {
    final timeline = TimelineObservation.optional(state);
    final scroll = TimelineScrollObservation.optional(state);
    return timeline != null &&
        !timeline.preparingLive &&
        scroll != null &&
        scroll.laidOut &&
        !scroll.isScrolling &&
        scroll.generation == timeline.generation;
  }

  bool liveAtEdge(Map<String, dynamic> state) {
    final timeline = TimelineObservation.optional(state);
    final scroll = TimelineScrollObservation.optional(state);
    return timeline != null &&
        timeline.isLive &&
        scroll != null &&
        scroll.atLiveEdge;
  }

  Future<void> drag(double dy) async {
    await waitFor('drag start geometry', idle);
    final drags = observations.putIfAbsent('drags', () => <Object?>[]) as List;
    drags.add(await driver.sendCommand(PointerDrag(timelineFinder, dy)));
    // Driver 已发出 pointer-up，但最后一次几何可能仍来自拖动中途；等它自己的
    // 空闲帧后再比较模式与像素。
    await waitFor('drag idle geometry', idle);
    final state = await snapshot();
    final scroll = TimelineScrollObservation.parse(state);
    record('drag-${drags.length}', state);
    _require(
      (dy > 0 && scroll.pixels! > 0.5) || (dy < 0),
      'drag $dy did not move the viewport',
    );
  }

  /// 阅读期间正文继续增长：已显示身份不变、冻结展示不被替换、模式保持 History。
  Future<void> checkGrowth(
    Map<String, dynamic> beforeState,
    String phase,
  ) async {
    final before = TimelineObservation.parse(beforeState);
    final beforeBody = _bodyCharacters(beforeState);
    final state = await waitFor(
      phase,
      (state) =>
          (!_busy(state) || _bodyCharacters(state) > beforeBody + 16000) &&
          idle(state),
    );
    record(phase, state);
    final after = TimelineObservation.parse(state);
    final grew = _bodyCharacters(state) > beforeBody + 16000;
    _require(grew || !_busy(state), '$phase did not settle');
    // History 冻结已展示结构（含保存/Remove）：先前身份必须全部保留。
    _require(
      before.itemIds.every(after.itemIds.contains),
      '$phase dropped already displayed identities',
    );
    if (before.isHistory) {
      _require(after.isHistory, '$phase left the frozen history display');
      _require(
        after.generation == before.generation,
        '$phase changed the display generation',
      );
    }
  }

  try {
    var state = await waitFor(
      'initial auto-follow',
      (state) => _busy(state) && _bodyCharacters(state) > 12000 && idle(state),
    );
    record('autoFollow', state);
    _require(liveAtEdge(state), 'streaming did not start at the live edge');
    // Less than the near-bottom threshold: new layout must not resume following.
    await drag(40);
    state = await snapshot();
    var timeline = TimelineObservation.parse(state);
    record('smallUpwardDrag', state);
    _require(timeline.isHistory, 'drag did not enter history');
    final historyGeneration = timeline.generation;
    await checkGrowth(state, 'outputWhileReading');

    // 桌面上滚轮按平台步长前进：重复同一步长直到冻结集合的本地底端。
    for (var step = 0; step < 24; step += 1) {
      await driver.sendCommand(PointerScroll(timelineFinder, 1000000));
      state = await snapshot();
      if (TimelineScrollObservation.parse(state).atLiveEdge) break;
    }
    state = await waitFor(
      'wheel back to frozen bottom',
      (state) =>
          TimelineScrollObservation.optional(state)?.atLiveEdge == true &&
          idle(state),
    );
    record('wheelToFrozenBottom', state);
    timeline = TimelineObservation.parse(state);
    // 到达本地底端仍是同一个 History 代次：不跨越后台输出、不跳最新。
    _require(
      timeline.isHistory && timeline.generation == historyGeneration,
      'reaching the frozen bottom created a new generation',
    );
    await checkGrowth(state, 'outputAfterReturning');

    await drag(300);
    state = await snapshot();
    record('secondUpwardDrag', state);
    _require(
      TimelineObservation.parse(state).isHistory,
      'output prevented the second drag',
    );
    await checkGrowth(state, 'outputAfterSecondDrag');
    observations['streamingThumbDrag'] = await driver.sendCommand(
      ScrollbarDrag(timelineFinder, -60),
    );
    state = await waitFor('thumb idle geometry', idle);
    record('thumbWhileStreaming', state);
    _require(
      TimelineObservation.parse(state).isHistory,
      'thumb drag did not enter history',
    );
    await checkGrowth(state, 'outputAfterThumbDrag');
    // 显式回到实时：新代次、最新小页、offset 0（不由滚轮自动完成）。
    final beforeReturn = TimelineObservation.parse(await snapshot());
    await driver.sendCommand(RawTap(find.byValueKey('timeline-return-live')));
    state = await waitFor('explicit return to live', (state) {
      final timeline = TimelineObservation.optional(state);
      final scroll = TimelineScrollObservation.optional(state);
      return timeline != null &&
          timeline.isLive &&
          !timeline.preparingLive &&
          timeline.generation > beforeReturn.generation &&
          scroll != null &&
          scroll.laidOut &&
          !scroll.isScrolling &&
          scroll.atLiveEdge;
    });
    record('returnToLive', state);
    _require(
      (TimelineScrollObservation.parse(state).pixels ?? 1).abs() <= 0.5,
      'explicit return to live did not start from offset 0',
    );
    observations['checksPassed'] = true;
    await File('${output.path}/screen.png')
        .writeAsBytes(await driver.screenshot());
  } catch (error) {
    observations['error'] = error.toString();
    rethrow;
  } finally {
    observations['humanVerdict'] = 'pending';
    await File('${output.path}/timeline-scroll.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(observations)}\n',
    );
    await driver.close();
  }
}

bool _busy(Map<String, dynamic> state) =>
    (state['workspace'] as Map?)?['isBusy'] == true;

/// 已加载消息的正文预览字符总数：随访问页增长，不是常量内存证明。
int _bodyCharacters(Map<String, dynamic> state) {
  final timeline = TimelineObservation.optional(state);
  if (timeline == null) return 0;
  return timeline.items.fold<int>(0, (total, item) => total + item.text.length);
}

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}
