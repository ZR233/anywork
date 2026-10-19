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
    bool Function(Map<String, dynamic>) condition, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    await File('${output.path}/stage.txt').writeAsString('$label\n');
    final deadline = DateTime.now().add(timeout);
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

  /// 阅读期间后台继续生成，但已展示的 History 展示保持冻结。
  ///
  /// 冻结期间**不能**再用“行内预览字符增长”当生成证据：预览按产品 32 KiB 预算封顶，
  /// 而 History 不向已展示 Message 应用实时正文。真实证据是 owner 从内容增量发布的
  /// `hasNewOutput`（design/26 §26.8），它只在后台确实产出新内容时出现。
  ///
  /// [requireLiveBackground] 为真时，必须在**生成仍在进行**的同一时刻观察：`busy`
  /// 为真、`hasNewOutput` 为真、此前展示的正文逐字不变。等待流结束再靠 `!busy`
  /// 通过属于覆盖空洞，不能接受；这类阶段会持续到 deadline 并如实失败。
  Future<void> checkGrowth(
    Map<String, dynamic> beforeState,
    String phase, {
    bool requireLiveBackground = false,
  }) async {
    final before = TimelineObservation.parse(beforeState);
    final frozen = _frozenBodies(before);
    final state = await waitFor(
      phase,
      (state) {
        final timeline = TimelineObservation.optional(state);
        if (timeline == null || !timeline.isHistory || !idle(state)) {
          return false;
        }
        if (!_frozenBodiesUnchanged(timeline, frozen)) return false;
        if (!requireLiveBackground) return true;
        // 后台生成进行中的真实提示：这一帧同时具备 busy、新输出提示与未变的冻结正文。
        return _busy(state) && timeline.hasNewOutput;
      },
      // 生成窗口只有数秒：错过就必须尽早如实失败，不能靠长等掩盖覆盖空洞。
      timeout: requireLiveBackground
          ? const Duration(seconds: 25)
          : const Duration(seconds: 60),
    );
    record(phase, state);
    final after = TimelineObservation.parse(state);
    _require(after.isHistory, '$phase left the frozen history display');
    _require(
      after.generation == before.generation,
      '$phase changed the display generation',
    );
    // History 冻结已展示结构（含保存/Remove）：先前身份必须全部保留。
    _require(
      before.itemIds.every(after.itemIds.contains),
      '$phase dropped already displayed identities',
    );
    _require(
      _frozenBodiesUnchanged(after, frozen),
      '$phase replaced an already displayed body',
    );
    // 后台仍在生成时，冻结展示必须带真实新输出提示。
    if (_busy(state)) {
      _require(after.hasNewOutput, '$phase hid real background output');
    }
    if (requireLiveBackground) {
      observations['backgroundOutputWhileFrozen'] = true;
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
    observations['historyGeneration'] = historyGeneration;
    // 第一处冻结观察必须在后台仍在生成期间完成：这是本 companion 的核心证据。
    await checkGrowth(state, 'outputWhileReading', requireLiveBackground: true);

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
    _require(
      observations['backgroundOutputWhileFrozen'] == true,
      'no in-progress background output was observed while the history '
      'display stayed frozen',
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

/// 已展示条目的正文指纹：预览字符数 + 声明的真实总字节数 + 预览正文本身。
///
/// History 冻结的是“已展示内容”，因此比较这三项即可发现替换、重排成另一份正文或
/// 预览被重新裁剪；revision 等元数据只记录，不参与冻结判定。
Map<String, String> _frozenBodies(TimelineObservation timeline) =>
    <String, String>{
      for (final item in timeline.items)
        item.id:
            '${item.text.length}:${item.textTotalBytes}:'
            '${_fnv1a64(item.text)}',
    };

bool _frozenBodiesUnchanged(
  TimelineObservation timeline,
  Map<String, String> frozen,
) {
  for (final entry in frozen.entries) {
    final item = timeline.item(entry.key);
    if (item == null) return false;
    final current =
        '${item.text.length}:${item.textTotalBytes}:${_fnv1a64(item.text)}';
    if (current != entry.value) return false;
  }
  return true;
}

/// FNV-1a over the code units. Must stay identical to the Driver-side helper.
int _fnv1a64(String text) {
  var hash = 0xcbf29ce484222325;
  for (var index = 0; index < text.length; index += 1) {
    hash ^= text.codeUnitAt(index);
    hash = hash * 0x100000001b3;
  }
  return hash;
}

/// 已加载消息的正文预览字符总数：随访问页增长，不是常量内存证明。
int _bodyCharacters(Map<String, dynamic> state) {
  final timeline = TimelineObservation.optional(state);
  if (timeline == null) return 0;
  return timeline.items.fold<int>(0, (total, item) => total + item.text.length);
}

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}
