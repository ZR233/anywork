// Opt-in native displacement collector for the standard timeline list.
//
// 六组尺寸各 96 次固定 ±60 真指针输入；三组主要尺寸**各 600** 次连续输入/方向反转
// （360 向上 + 240 向下，合计 1800）。另有连续段（不逐 tick 等收束）与真实分页回包
// 交叠取证。
// 判定比较**真实可见行的位移**（请求时扫描挂载行的 rect），容差 ±2px 与边界 clamp
// 与纯库先行门禁相同；pixels 只用于计算期望位移，不用来替代可见行事实。
//
// 每次 resize 的完成条件是两个独立坐标域的真实证据：原生窗口的实际尺寸（设备像素）
// 与 Flutter 根布局（`studio-shell`）已采用尺寸（逻辑像素）。物理↔逻辑换算来自同
// 一时刻的两条测量，不假设 DPR=1；Timeline 子视口只作内容域诊断，不反推窗口尺寸。
//
// 这不是生产测量机制：没有每行 GlobalKey、没有每帧采样，也没有任何写回产品的值。
import 'dart:convert';
import 'dart:io';

import 'package:anywork/src/shared/studio_driver_key_values.dart';
import 'package:flutter_driver/flutter_driver.dart';

import 'cold_start_navigation.dart';
import 'pointer_scroll.dart';
import 'raw_tap.dart';
import 'timeline_observation.dart';
import 'window_control.dart';

// 冷启动后在真实侧栏选择首轮同一持久化项目与会话（协调器经 `--project-id` /
// `--thread-id` 传入 live 阶段记录的真实身份），再按产品入口打开并核对身份。

/// 六组尺寸：默认、屏幕大小、变宽/变窄、变高/变矮与恢复（复用 D1 门禁矩阵）。
const _sizes = <(int, int)>[
  (1280, 900),
  (1920, 1200),
  (1100, 760),
  (1600, 760),
  (1600, 1100),
  (1280, 900),
];

/// 每组 96 次固定 ±60 输入：48 次向上读取、48 次向下回到冻结本地底端。
const _fixedInputsPerSize = 96;

/// 三组主要尺寸**各 600** 次连续输入（合计 1800），含方向反转。
const _rapidSizes = <(int, int)>[(1920, 1200), (900, 760), (1280, 900)];
const _rapidInputs = 600;

/// 反转分布：前 360 次向上读取，之后 240 次向下回到底端。
const _rapidUpInputs = 360;

/// 连续段：不逐 tick 等收束，只按固定间隔采样真实几何，最后统一收束核对。
const _burstInputs = 40;

/// 真实分页请求与滚轮输入交叠的样本数。
const _overlapInputs = 8;

/// 产品分页小页上限（条）：一次 `load-older` 必须真实增长 1..32 条。
const _pageSizeLimit = 32;

/// 可比较的位移容差（与 D1 门禁一致）。
const _displacementTolerance = 2.0;

/// 根布局逻辑尺寸容差（逻辑像素）：物理↔逻辑换算的舍入上限。
const _rootLayoutTolerance = 1.0;

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    _usage();
    return;
  }
  final output = Directory(args[1])..createSync(recursive: true);
  var functionalOnly = false;
  String? projectId;
  String? threadId;
  for (var index = 2; index < args.length; index++) {
    switch (args[index]) {
      case '--functional-only':
        functionalOnly = true;
      case '--project-id':
        if (index + 1 >= args.length) {
          _usage();
          return;
        }
        projectId = args[++index];
      case '--thread-id':
        if (index + 1 >= args.length) {
          _usage();
          return;
        }
        threadId = args[++index];
      default:
        stderr.writeln('unknown argument: ${args[index]}');
        _usage();
        return;
    }
  }
  // 冷启动目标身份必须来自首轮真实 snapshot（协调器经 baseline 传入）；
  // 缺失即失败，不猜值、不选择“第一个”项目或会话。
  if (projectId == null ||
      projectId.isEmpty ||
      threadId == null ||
      threadId.isEmpty) {
    _usage();
    return;
  }
  final target = ColdStartIdentity(projectId: projectId, threadId: threadId);
  final driver = await FlutterDriver.connect(dartVmServiceUrl: args[0]);
  final probe = TimelineRowsProbe(driver.requestData);
  final report = <String, Object?>{
    'platform': 'Linux',
    'driverInput': 'PointerScroll event at a real visible row',
    'tolerance': _displacementTolerance,
    // 与 D1 批准矩阵一致：六组尺寸各 96 次固定 ±60；三组主要尺寸**各 600** 次
    // 连续输入/方向反转（合计 1800），不把 600 摊成每组 200。
    'matrix': <String, Object?>{
      'singleSizes': [
        for (final (width, height) in _sizes) <int>[width, height],
      ],
      'inputsPerSingleSize': _fixedInputsPerSize,
      'rapidSizes': [
        for (final (width, height) in _rapidSizes) <int>[width, height],
      ],
      'inputsPerRapidSize': _rapidInputs,
      'rapidUpInputs': _rapidUpInputs,
      'rapidDownInputs': _rapidInputs - _rapidUpInputs,
      'rapidTotalInputs': _rapidInputs * _rapidSizes.length,
      'burstInputs': _burstInputs,
      'overlapInputs': _overlapInputs,
    },
    'checks': <String, bool>{},
    // 每次 resize 的双域证据：原生窗口（设备像素）与 Flutter 根布局（逻辑像素）。
    'resizes': <Object?>[],
    'single': <Object?>[],
    'rapid': <Object?>[],
  };
  final checks = report['checks']! as Map<String, bool>;
  final resizes = report['resizes']! as List<Object?>;
  var failures = 0;
  void check(String name, bool pass) {
    checks[name] = pass;
    if (!pass) failures++;
  }

  final pidRaw = jsonDecode(
    await driver.requestData('pid', timeout: const Duration(seconds: 15)),
  );
  final guiPid = (pidRaw as Map)['pid'] as int;
  report['pid'] = guiPid;
  WindowGeometry? original;

  /// 只读快照：与 `FlutterDriverSession.readSnapshot` 相同的请求，失败即抛出。
  Future<Map<String, dynamic>> snapshot() async {
    final raw = await driver.requestData(
      'snapshot',
      timeout: const Duration(seconds: 15),
    );
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('snapshot response must be a JSON object');
    }
    return decoded;
  }

  Future<void> save() =>
      File('${output.path}/observations.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(report));

  /// 收束条件：几何已发布、无在途滚动、没有准备中的新代次。
  Future<Map<String, dynamic>> settle() async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      final state = await snapshot();
      final timeline = TimelineObservation.optional(state);
      final scroll = TimelineScrollObservation.optional(state);
      if (timeline != null &&
          !timeline.preparingLive &&
          scroll != null &&
          scroll.laidOut &&
          !scroll.isScrolling &&
          scroll.generation == timeline.generation) {
        return state;
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    throw StateError('Timeline geometry did not settle');
  }

  // Flutter 根布局 key：`studio-shell`（`StudioDriverKeyValues.shell`）是
  // `lib/src/features/shell/studio_shell.dart` 中 Scaffold body 上的 Row：横向由
  // 「侧栏 + 5px 分隔 + Expanded(工作区)」（overlay 模式只有 Expanded）铺满，纵向由
  // 工作区 Column 的 Expanded 铺满，因此它的 bounds 就是 Flutter 已采用的布局尺寸。
  // Timeline 子视口有自己的坐标域（侧栏/标题/输入区不属于它），不能用它的边距或底边
  // 反推整个窗口。
  final rootLayout = find.byValueKey(StudioDriverKeyValues.shell);

  /// 只读根布局 bounds（逻辑像素）。`getTopLeft`/`getBottomRight` 是 FlutterDriver
  /// 公开几何命令，单位为逻辑像素，可直接换算到设备像素而不新增生产接口。
  Future<_RootLayoutBounds> readRootBounds() async {
    final topLeft = await driver.getTopLeft(
      rootLayout,
      timeout: const Duration(seconds: 10),
    );
    final bottomRight = await driver.getBottomRight(
      rootLayout,
      timeout: const Duration(seconds: 10),
    );
    return _RootLayoutBounds(
      left: topLeft.dx,
      top: topLeft.dy,
      width: bottomRight.dx - topLeft.dx,
      height: bottomRight.dy - topLeft.dy,
    );
  }

  /// Timeline 子视口（逻辑像素，视口自身坐标域）的独立诊断：只说明内容区在哪，
  /// 不参与窗口尺寸判断。
  Future<Map<String, Object?>?> readTimelineViewport() async {
    try {
      return (await probe.read()).viewportGlobal?.toJson();
    } on Object catch (error) {
      return <String, Object?>{'error': '$error'};
    }
  }

  /// 一次 resize 的完成条件由两条独立真实证据组成：
  ///   1. `window_control` 证明 GUI 所属原生窗口的**实际尺寸**（X11 设备像素）已经
  ///      等于请求值；
  ///   2. Flutter **根布局**被观察到采用了与该物理尺寸对应的**逻辑尺寸**。
  ///
  /// 物理↔逻辑比只来自同一时刻的两条真实测量（根布局宽度 + 原始窗口宽度），不假设
  /// DPR=1：根布局 `studio-shell` 横向必然铺满（侧栏 + 分隔 + Expanded），是唯一无
  /// 常量镶边的轴。纵向可能存在窗口装饰这类常量镶边，因此高度按**增量**核对，不把
  /// 常量镶边误当缩放差异。
  Future<void> resize(int width, int height) async {
    final rootBefore = await readRootBounds();
    final result = resizeOwnedWindow(
      guiPid: guiPid,
      width: width,
      height: height,
    );
    if (!result.resized) {
      throw StateError(
        'resize $width/$height: ${result.reason}: ${result.diagnostics}',
      );
    }
    original ??= result.original;
    final osOriginal = result.original!;
    final osApplied = result.applied!;
    final logicalPerPhysical = rootBefore.width / osOriginal.width;
    // 常量纵向镶边（逻辑像素）：0 表示根布局直接覆盖整个客户区；>0 说明窗口装饰在
    // Flutter 视图之外占固定高度，只作诊断，不参与判定。
    final chromeLogical =
        osOriginal.height * logicalPerPhysical - rootBefore.height;
    final evidence = <String, Object?>{
      'target': <int>[width, height],
      'osWindow': <String, Object?>{
        'original': osOriginal.toJson(),
        'applied': osApplied.toJson(),
      },
      'rootLayoutBefore': rootBefore.toJson(),
      // 逻辑像素 / 设备像素（由宽度轴求得，宽度轴无常量镶边）。
      'logicalPerPhysical': logicalPerPhysical,
      'rootChromeLogicalHeight': chromeLogical,
    };
    resizes.add(evidence);
    if (!(logicalPerPhysical > 0)) {
      evidence['failure'] = 'rootLayoutScaleInvalid';
      throw StateError(
        'resize $width/$height: the Flutter root layout '
        '${rootBefore.width}x${rootBefore.height} has no positive logical size for '
        'the native window ${osOriginal.width}x${osOriginal.height}',
      );
    }
    final expectedWidth = width * logicalPerPhysical;
    final expectedHeight =
        rootBefore.height + (height - osOriginal.height) * logicalPerPhysical;
    evidence['expectedRootLayout'] = <String, Object?>{
      'width': expectedWidth,
      'height': expectedHeight,
    };
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    var stable = 0;
    _RootLayoutBounds? last;
    while (DateTime.now().isBefore(deadline)) {
      last = await readRootBounds();
      final matches =
          (last.width - expectedWidth).abs() <= _rootLayoutTolerance &&
          (last.height - expectedHeight).abs() <= _rootLayoutTolerance;
      // 连续两次一致才算 Flutter 真的完成了这一帧布局，单次采样不作为完成依据。
      stable = matches ? stable + 1 : 0;
      if (stable >= 2) break;
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    if (stable < 2) {
      final viewport = await readTimelineViewport();
      evidence['failure'] = 'flutterRootLayoutNotApplied';
      evidence['lastRootLayout'] = last?.toJson();
      evidence['lastTimelineViewport'] = viewport;
      throw StateError(
        'resize $width/$height: the native window really is '
        '${osApplied.width}x${osApplied.height} (device px, applied), but the '
        'Flutter root layout did not adopt it: expected '
        '${expectedWidth}x$expectedHeight logical (logicalPerPhysical '
        '$logicalPerPhysical, constant vertical chrome $chromeLogical), last root '
        'layout ${last?.toJson()}, timeline viewport (separate content domain) '
        '$viewport',
      );
    }
    evidence['rootLayoutAfter'] = last!.toJson();
    evidence['timelineViewport'] = await readTimelineViewport();
    await settle();
  }

  /// 选一个完全落在视口内、离上下边缘足够远的非工具行作为真实输入目标与位移样本。
  ///
  /// 没有候选就是观测失败（记录下来并计为不通过），不静默丢样本。
  Future<(String, TimelineRect)?> chooseTarget(
    TimelineObservation timeline,
    TimelineRowsObservation rows,
  ) async {
    final height = rows.viewport.height;
    final candidates = <(String, TimelineRect)>[];
    for (final row in rows.visible) {
      final item = timeline.item(row.id);
      if (item == null || item.kind == 'toolCall') continue;
      final rect = row.rect;
      if (rect == null) continue;
      if (rect.top < 70) continue;
      if (rect.bottom > height - 70) continue;
      if (rect.height <= 0 || rect.height > height - 140) continue;
      candidates.add((row.id, rect));
    }
    if (candidates.isEmpty) return null;
    candidates.sort(
      (a, b) => (a.$2.centerY - height / 2).abs().compareTo(
        (b.$2.centerY - height / 2).abs(),
      ),
    );
    return candidates.first;
  }

  Future<Map<String, Object?>> wheel(
    double dy, {
    required String phase,
    required int index,
  }) async {
    final before = await snapshot();
    final beforeTimeline = TimelineObservation.parse(before);
    final beforeScroll = TimelineScrollObservation.parse(before);
    final beforeRows = await probe.read();
    final target = await chooseTarget(beforeTimeline, beforeRows);
    if (target == null) {
      failures++;
      return <String, Object?>{
        'phase': phase,
        'index': index,
        'dy': dy,
        'pass': false,
        'reason': 'noVisibleOuterTarget',
        'before': beforeTimeline.summary(),
        'scroll': beforeScroll.toJson(),
      };
    }
    final (rowId, rectBefore) = target;
    await driver.sendCommand(
      PointerScroll(find.byValueKey('timeline-row-$rowId'), dy),
    );
    final after = await settle();
    final afterTimeline = TimelineObservation.parse(after);
    final afterScroll = TimelineScrollObservation.parse(after);
    final afterRows = await probe.read(rowIds: [rowId]);
    final measured = afterRows.row(rowId);
    final rectAfter = measured?.rect;
    final oldPixels = beforeScroll.pixels;
    final oldMax = beforeScroll.maxScrollExtent;
    if (oldPixels == null || oldMax == null) {
      failures++;
      return <String, Object?>{
        'phase': phase,
        'index': index,
        'dy': dy,
        'pass': false,
        'reason': 'geometryNotLaidOut',
        'scroll': beforeScroll.toJson(),
      };
    }
    final expectedOffset = (oldPixels - dy).clamp(0.0, oldMax).toDouble();
    final expectedDisplacement = -(expectedOffset - oldPixels);
    final displacement = rectAfter == null || !measured!.intersects
        ? null
        : rectBefore.top - rectAfter.top;
    final retained = beforeTimeline.itemIds.every(
      afterTimeline.itemIds.contains,
    );
    final pageDelta = afterTimeline.itemCount - beforeTimeline.itemCount;
    final pass =
        displacement != null &&
        (displacement - expectedDisplacement).abs() <= _displacementTolerance &&
        retained &&
        pageDelta >= 0 &&
        pageDelta <= 32 &&
        afterTimeline.generation == beforeTimeline.generation;
    if (!pass) failures++;
    return <String, Object?>{
      'phase': phase,
      'index': index,
      'dy': dy,
      'rowId': rowId,
      'expected': expectedDisplacement,
      'visibleDisplacement': displacement,
      'retained': retained,
      'pageDelta': pageDelta,
      'modeBefore': beforeTimeline.mode,
      'modeAfter': afterTimeline.mode,
      'generation': beforeTimeline.generation,
      'beforeRect': rectBefore.toJson(),
      'afterRect': rectAfter?.toJson(),
      'scroll': afterScroll.toJson(),
      'pass': pass,
      'targetMissing': displacement == null,
    };
  }

  try {
    await driver.sendCommand(SetFrameSync(false));
    // 冷启动允许从无项目/会话选择的启动页开始（design/26 §26.9）：通过正常侧栏
    // 选择与打开动作恢复首轮同一持久化项目与会话，再核对打开后的实际身份。
    // 不建立选择缓存、不新增旁路命令、不重发 prompt。
    try {
      report['restore'] = await restoreColdStartTarget(
        ColdStartDriverSurface(
          readSnapshot: snapshot,
          tap: (finder, timeout) =>
              driver.sendCommand(RawTap(finder, timeout: timeout)),
        ),
        identity: target,
        phase: 'displacement',
        onStage: (value) async => stdout.writeln('displacement stage: $value'),
      );
    } on ColdStartNavigationFailure catch (error) {
      report['restore'] = error.evidence;
      rethrow;
    }
    final restore = (report['restore']! as Map).cast<String, Object?>();
    check(
      'restoredPersistedTarget',
      restore['projectId'] == target.projectId &&
          restore['threadId'] == target.threadId &&
          restore['projectIdMatches'] == true &&
          restore['threadIdMatches'] == true &&
          restore['evidenceConsistent'] == true,
    );
    await driver.waitFor(
      find.byValueKey('timeline-scrollable'),
      timeout: const Duration(seconds: 120),
    );
    final initial = await settle();
    report['initial'] = _summary(initial);
    check(
      'initialThreadIdentity',
      TimelineObservation.parse(initial).threadId == target.threadId,
    );
    check(
      'initialSmallPage',
      TimelineObservation.parse(initial).itemCount <= 32,
    );
    if (!functionalOnly) {
      for (var phase = 0; phase < _sizes.length; phase++) {
        final (width, height) = _sizes[phase];
        await resize(width, height);
        final steps = <Object?>[];
        (report['single']! as List<Object?>).add(<String, Object?>{
          'size': <int>[width, height],
          'inputs': _fixedInputsPerSize,
          'upInputs': _fixedInputsPerSize ~/ 2,
          'downInputs': _fixedInputsPerSize ~/ 2,
          'steps': steps,
        });
        for (var index = 0; index < _fixedInputsPerSize; index++) {
          // 前 48 次向上读取，后 48 次向下回到冻结集合的本地底端。
          final dy = index < _fixedInputsPerSize ~/ 2 ? -60.0 : 60.0;
          steps.add(await wheel(dy, phase: 'single-$phase', index: index));
          if (index % 24 == 23) await save();
        }
        await File('${output.path}/single-$phase.png')
            .writeAsBytes(await driver.screenshot());
        await save();
        stdout.writeln('single phase $phase complete, failures=$failures');
      }
      for (final (width, height) in _rapidSizes) {
        await resize(width, height);
        final steps = <Object?>[];
        (report['rapid']! as List<Object?>).add(<String, Object?>{
          'size': <int>[width, height],
          'inputs': _rapidInputs,
          'upInputs': _rapidUpInputs,
          'downInputs': _rapidInputs - _rapidUpInputs,
          'steps': steps,
        });
        for (var index = 0; index < _rapidInputs; index++) {
          // 方向反转：前 360 次向上，之后 240 次向下。
          final dy = index < _rapidUpInputs ? -60.0 : 60.0;
          steps.add(
            await wheel(dy, phase: 'rapid-${width}x$height', index: index),
          );
          if (index % 40 == 39) await save();
        }
        await File('${output.path}/rapid-$width.png')
            .writeAsBytes(await driver.screenshot());
        await save();
        stdout.writeln('rapid $width complete, failures=$failures');
      }
      // 连续段：不逐 tick 等待收束，只采样真实几何；最后统一 settle 后核对不换代、
      // 不丢身份、单 tick 不跨多页。这里不把“每 tick 都 settle”当成连续输入证明。
      await resize(1280, 900);
      report['continuousBurst'] = await _continuousBurst(
        driver,
        snapshot,
        settle,
        check: check,
      );
      // 真实分页回包与滚轮输入交叠：由应用内复合 Driver 场景在同一次操作里调用
      // 产品分页动作、读取应用真实发布的 loading、派发标准指针信号并 await 该页
      // 收束（不是宿主先发请求不 await 再发滚轮）。不使用生产 test hook。
      report['overlap'] = await _overlapWithPageLoad(
        driver,
        settle,
        check: check,
      );
    }
    await resize(1280, 900);
    final functional = await settle();
    report['functional'] = _summary(functional);
    await File('${output.path}/functional.png')
        .writeAsBytes(await driver.screenshot());
  } on Object catch (error, stack) {
    report['error'] = '$error';
    report['stack'] = '$stack';
    failures++;
  } finally {
    final restore = original;
    if (restore != null) {
      try {
        await resize(restore.width, restore.height);
        await File('${output.path}/restored.png')
            .writeAsBytes(await driver.screenshot());
        report['restored'] = true;
      } on Object catch (error) {
        report['restoreError'] = '$error';
        failures++;
      }
    }
    report['failureCount'] = failures;
    report['checksPassed'] = failures == 0;
    await save();
    try {
      final shutdown = jsonDecode(
        await driver
            .requestData('shutdown', timeout: const Duration(seconds: 90))
            .timeout(const Duration(seconds: 95)),
      );
      report['shutdown'] = shutdown is Map ? shutdown['shutdown'] : null;
    } on Object catch (error) {
      report['shutdownRequestError'] = '$error';
    }
    await driver.close();
    await save();
  }
  if (failures > 0) {
    stderr.writeln('timeline displacement finished with failures=$failures');
    exitCode = 1;
  } else {
    stdout.writeln('timeline displacement finished with no failures');
  }
}

Map<String, Object?> _summary(Map<String, dynamic> snapshot) =>
    <String, Object?>{
      'timeline': TimelineObservation.parse(snapshot).summary(),
      'scroll': TimelineScrollObservation.parse(snapshot).toJson(),
    };

/// 连续输入段：不逐 tick 等待收束，只采样真实几何，最后统一收束核对。
///
/// 逐 tick 采样的 `pixels/mode/generation/itemCount` 是真实快照；期望位移由每 tick
/// 采样到的真实 `maxScrollExtent` 与 clamp 累计得到，不依赖固定 sleep，也不把
/// “每 tick 都 idle”当作连续输入证据。
Future<Map<String, Object?>> _continuousBurst(
  FlutterDriver driver,
  Future<Map<String, dynamic>> Function() snapshot,
  Future<Map<String, dynamic>> Function() settle, {
  required void Function(String name, bool pass) check,
}) async {
  var state = await settle();
  var timeline = TimelineObservation.parse(state);
  var scroll = TimelineScrollObservation.parse(state);
  if (timeline.isLive && scroll.maxScrollExtent == 0) {
    return <String, Object?>{
      'skipped': true,
      'reason':
          'content does not fill the viewport, so no continuous reading '
          'range exists in this fixture state',
    };
  }
  final startIds = timeline.itemIds;
  final startGeneration = timeline.generation;
  final startPixels = scroll.pixels ?? 0;
  var expectedPixels = startPixels;
  var maxExtent = scroll.maxScrollExtent ?? 0;
  final ticks = <Map<String, Object?>>[];
  var violations = <Map<String, Object?>>[];
  var previousPixels = scroll.pixels ?? 0;
  for (var index = 0; index < _burstInputs; index++) {
    await driver.sendCommand(
      PointerScroll(find.byValueKey('timeline-scrollable'), -60),
    );
    // 只读采样：不等 idle、不 sleep，记录输入落地过程中的真实几何。
    final sampled = await snapshot();
    final sampledTimeline = TimelineObservation.parse(sampled);
    final sampledScroll = TimelineScrollObservation.parse(sampled);
    final pixels = sampledScroll.pixels;
    final currentMax = sampledScroll.maxScrollExtent;
    if (pixels == null || currentMax == null) {
      violations = <Map<String, Object?>>[
        ...violations,
        <String, Object?>{'tick': index, 'reason': 'geometryMissing'},
      ];
      continue;
    }
    final step = (pixels - previousPixels).abs();
    if (step > 60.5) {
      violations = <Map<String, Object?>>[
        ...violations,
        <String, Object?>{
          'tick': index,
          'reason': 'singleTickOverPage',
          'delta': step,
        },
      ];
    }
    if (sampledTimeline.generation != startGeneration) {
      violations = <Map<String, Object?>>[
        ...violations,
        <String, Object?>{
          'tick': index,
          'reason': 'generationChanged',
          'generation': sampledTimeline.generation,
        },
      ];
    }
    expectedPixels = (expectedPixels + 60).clamp(0.0, currentMax).toDouble();
    maxExtent = currentMax;
    previousPixels = pixels;
    ticks.add(<String, Object?>{
      'tick': index,
      'pixels': pixels,
      'maxScrollExtent': currentMax,
      'mode': sampledTimeline.mode,
      'generation': sampledTimeline.generation,
      'itemCount': sampledTimeline.itemCount,
      'isScrolling': sampledScroll.isScrolling,
    });
  }
  state = await settle();
  timeline = TimelineObservation.parse(state);
  scroll = TimelineScrollObservation.parse(state);
  final retained = startIds.every(timeline.itemIds.contains);
  final finalPixels = scroll.pixels ?? -1;
  final settledOk =
      timeline.isHistory &&
      timeline.generation == startGeneration &&
      retained &&
      (finalPixels - expectedPixels).abs() <= _displacementTolerance;
  check('continuousBurstSettles', settledOk && violations.isEmpty);
  return <String, Object?>{
    'inputs': _burstInputs,
    'startPixels': startPixels,
    'expectedPixels': expectedPixels,
    'finalPixels': finalPixels,
    'maxScrollExtent': maxExtent,
    'mode': timeline.mode,
    'generation': timeline.generation,
    'startGeneration': startGeneration,
    'identityRetained': retained,
    'itemCount': timeline.itemCount,
    'violations': violations,
    'ticks': ticks.length > 12 ? ticks.sublist(ticks.length - 12) : ticks,
    'ticksSampled': ticks.length,
    'note':
        'pixels-level supplementary evidence only: the per-tick samples are real '
        'snapshots and the final settle (not a fixed sleep) attributes the total '
        'displacement; the actual visible-row rect displacement is proven by the '
        '±60 single-input phases',
    'pass': settledOk && violations.isEmpty,
  };
}

/// 真实分页回包与滚轮输入交叠：由**同一个 Driver 复合场景命令**在应用内取证。
///
/// 旧实现把 `load-older` 的宿主 future 不 await 就发滚轮，但宿主命令往返与本地查询
/// 太快，样本全落在页完成之后——创建 future 的先后不能证明真实交叠。现在由
/// `load-older-overlap` 在应用内调用同一 owner 动作、读取应用真实发布的
/// `loadingOlder`，确认受理后才经标准指针信号路由派发输入，并 await 同一个真实分页
/// Future。这里仍只核对真实事实：至少一格输入在真实在途时派发、页在该输入之后发布、
/// 至少一格输入在有可用滚动余量时真的改变外层 pixels（首帧前读取）、页增长是
/// 1..32 条真实小页、身份/代次/模式与收束全部保持。
Future<Map<String, Object?>> _overlapWithPageLoad(
  FlutterDriver driver,
  Future<Map<String, dynamic>> Function() settle, {
  required void Function(String name, bool pass) check,
}) async {
  var state = await settle();
  var timeline = TimelineObservation.parse(state);
  if (timeline.isLive) {
    // 用一次真实上翻进入 History，保持“冻结历史 + 后台继续”的前提。
    await driver.sendCommand(
      PointerScroll(find.byValueKey('timeline-scrollable'), -60),
    );
    // 进入 History 是产品由真实滚动触发的发布事实：有界等待该真实 mode 到位，
    // 不用固定 sleep，也不在复合命令里猜。
    final historyDeadline = DateTime.now().add(const Duration(seconds: 20));
    while (timeline.mode != 'history') {
      if (!DateTime.now().isBefore(historyDeadline)) break;
      // 40ms 只是重新观察真实状态的节奏，完成条件始终是发布的 mode。
      await Future<void>.delayed(const Duration(milliseconds: 40));
      state = await settle();
      timeline = TimelineObservation.parse(state);
    }
  }
  if (timeline.mode != 'history') {
    check('overlapPageLoadWithWheel', false);
    return <String, Object?>{
      'inputs': _overlapInputs,
      'reason':
          'the real wheel did not put the timeline into history mode '
          '(mode=${timeline.mode})',
      'mode': timeline.mode,
      'pass': false,
    };
  }
  if (!timeline.hasOlder) {
    check('overlapPageLoadWithWheel', false);
    return <String, Object?>{
      'skipped': false,
      'reason': 'the frozen history reports no older page to load',
      'pass': false,
    };
  }
  final startIds = timeline.itemIds;
  final startThreadId = timeline.threadId;
  final startGeneration = timeline.generation;
  final startCount = timeline.itemCount;
  // 应用内复合场景：受理→派发→页发布→收束全部在同一次 Driver 操作里取证。
  Map<String, Object?> command;
  try {
    final raw = await driver.requestData(
      jsonEncode(<String, Object?>{
        'cmd': 'load-older-overlap',
        'threadId': startThreadId,
        'generation': startGeneration,
        'inputs': _overlapInputs,
        'dy': -60.0,
      }),
      timeout: const Duration(seconds: 180),
    );
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw StateError('load-older-overlap response is not an object: $raw');
    }
    command = decoded.cast<String, Object?>();
  } on Object catch (error) {
    check('overlapPageLoadWithWheel', false);
    return <String, Object?>{
      'inputs': _overlapInputs,
      'reason': 'the overlap scenario command did not complete: $error',
      'pass': false,
    };
  }
  state = await settle();
  final after = TimelineObservation.parse(state);
  final afterScroll = TimelineScrollObservation.parse(state);
  final commandChecks =
      (command['checks'] as Map?)?.cast<String, Object?>() ??
      const <String, Object?>{};
  final samples = <Map<String, Object?>>[
    for (final row in (command['inputsLog'] as List? ?? const <Object?>[]))
      if (row is Map) row.cast<String, Object?>(),
  ];
  final retained = startIds.every(after.itemIds.contains);
  final pageDelta = after.itemCount - startCount;
  // 20k 历史下首页之后 `hasOlder` 仍为真：必须真实增长 1..32 条才算一页成功；
  // 空页、假 EOF、多页合并都不接受（hasOlder 只作诊断保留）。
  final pageLoaded = pageDelta > 0 && pageDelta <= _pageSizeLimit;
  final noGenerationChange = after.generation == startGeneration;
  final sameThread = after.threadId == startThreadId;
  final noLostReader =
      retained &&
      samples.every(
        (sample) =>
            sample['generation'] == startGeneration &&
            sample['mode'] == 'history',
      );
  // 在途判据只用应用真实发布的事实：派发时 `loadingOlder == true`，且页在至少一格
  // 输入之后才发布（`pageCompletedAfterInputs >= 1`）。不再用宿主 future 先后冒充。
  final inFlightSamples = <Map<String, Object?>>[
    for (final sample in samples)
      if (sample['loadingOlder'] == true) sample,
  ];
  final inFlightObserved = inFlightSamples.isNotEmpty;
  final completedAfterInputs = command['pageCompletedAfterInputs'];
  final inputsInHistory =
      samples.length == _overlapInputs &&
      samples.every(
        (sample) =>
            sample['mode'] == 'history' &&
            sample['generation'] == startGeneration,
      );
  final pass =
      command['ok'] == true &&
      command['pass'] == true &&
      commandChecks['loadAccepted'] == true &&
      commandChecks['inputMovedOuterList'] == true &&
      (command['outerScrollMoves'] as int? ?? 0) >= 1 &&
      inFlightObserved &&
      completedAfterInputs is int &&
      completedAfterInputs >= 1 &&
      pageLoaded &&
      noGenerationChange &&
      sameThread &&
      after.mode == 'history' &&
      after.loadingOlder == false &&
      after.olderError == null &&
      inputsInHistory &&
      noLostReader;
  check('overlapPageLoadWithWheel', pass);
  return <String, Object?>{
    'inputs': _overlapInputs,
    'pageLoaded': pageLoaded,
    'beforeItems': startCount,
    'afterItems': after.itemCount,
    'pageDelta': pageDelta,
    'pageSizeLimit': _pageSizeLimit,
    'hasOlderAfter': after.hasOlder,
    'identityRetained': retained,
    'sameThread': sameThread,
    'outerScrollMoves': command['outerScrollMoves'],
    'generationBefore': startGeneration,
    'generationAfter': after.generation,
    'inFlightSamples': inFlightSamples.length,
    'inFlightObserved': inFlightObserved,
    'pageCompletedAfterInputs': completedAfterInputs,
    'commandChecks': commandChecks,
    'command': command,
    'finalScroll': afterScroll.toJson(),
    'reason': inFlightObserved
        ? 'the in-app scenario dispatched inputs only after the owner published '
              'loadingOlder, and the real page completed after at least one of '
              'them'
        : 'no input was dispatched while the owner published loadingOlder, so '
              'the page never really overlapped the wheel inputs',
    'samples': samples,
    'pass': pass,
  };
}

void _usage() {
  stderr.writeln(
    'usage: timeline_displacement_journey.dart VM_URL OUTPUT_DIR '
    '--project-id ID --thread-id ID [--functional-only]',
  );
  exitCode = 64;
}

/// Flutter 根布局在**逻辑像素**下的实际 bounds（相对 FlutterView 原点）。
///
/// 根布局覆盖整个 view，因此 width/height 就是 Flutter 已采用的布局尺寸；left/top
/// 只作诊断保留，不用它反推窗口。
final class _RootLayoutBounds {
  const _RootLayoutBounds({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  Map<String, Object?> toJson() => <String, Object?>{
    'left': left,
    'top': top,
    'width': width,
    'height': height,
  };
}
