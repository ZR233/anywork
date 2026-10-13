import 'dart:convert';
import 'dart:io';

import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:flutter_driver/flutter_driver.dart';

import 'flutter_driver_session.dart';

/// 会话选择器收敛验收：主界面的"任务模式 / 思考强度"选择器必须在**不发生任何页面
/// 跳转**的前提下显示新值。
///
/// 验收的是用户报告的两个症状：改动后选择器仍显示旧值、菜单仍停在旧选中行，需要往返
/// 设置页才生效。证据分三层：
///   * 渲染证据：触发器的实际文本在选择后变化，且等于被选中那一行的文本；
///   * canonical 证据：driver `snapshot` 的 `navigation.newThreadMode` 到位。
///     起始页思考强度是 route 草稿，提交前不写 `settings.modeModelRoutes`，
///     快照也不投影 effort intent；验收落在触发器文案等于被选中的候选。
///     `settings.mutations` 在这次选择后必须仍为空（没有停在 pending 命令上）。
///     `settings.mutations[].phase` 若出现，只可能是 pending/failed/succeeded；
///     `settings.lastMerge` 恒为 null，本 journey 不把它当写入证据。
///   * 反证据：全程未出现设置页（`settings-back` 不存在），shell 与起始页仍在。
///
/// 运行方式（本仓库 canonical 入口）：
///   1. `cargo xtask run-gui --demo --driver`（从输出中取 VM service URL）
///   2. `dart run test_driver/session_selector_journey.dart <vm_url> [output_dir]`
///
/// 说明：本 journey 依赖真实 Flutter 引擎与 Driver 扩展，只能在能构建并启动 GUI 的
/// 环境执行；它不进入 CI 的确定性门禁，但受 `cargo xtask verify-gui` 的格式化与静态
/// 分析约束。
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    throw ArgumentError('VM_URL [OUTPUT_DIR] required');
  }
  final output = Directory(
    args.length > 1 ? args[1] : Directory.systemTemp.path,
  );
  final session = await FlutterDriverSession.connect(vmServiceUrl: args[0]);
  final checks = <String, Object?>{};
  Object? failure;
  StackTrace? failureStack;
  try {
    await _run(session, checks);
  } catch (error, stack) {
    failure = error;
    failureStack = stack;
  } finally {
    try {
      await session.close().timeout(const Duration(seconds: 5));
    } catch (_) {
      // 原生关闭后连接终止不覆盖已收集的验收结果。
    }
  }
  final status = failure == null ? 'complete' : 'failed';
  await output.create(recursive: true);
  await File('${output.path}/session-selector-summary.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'scenario': 'session-selector',
      'status': status,
      'error': failure?.toString(),
      'humanVerdict': 'pending',
      'checks': checks,
    }),
  );
  if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
}

Future<void> _run(
  FlutterDriverSession session,
  Map<String, Object?> checks,
) async {
  final modeTrigger = find.byValueKey(StudioDriverKeys.sessionMode.value);
  final effortTrigger = find.byValueKey(StudioDriverKeys.reasoningEffort.value);
  final settingsBack = find.byValueKey(StudioDriverKeys.settingsBack.value);

  await session.waitFor(
    find.byValueKey(StudioDriverKeys.shell.value),
    timeout: const Duration(seconds: 60),
  );

  // 起始页是新会话草稿的唯一入口：模式选择器改的是 draft，投影在
  // `navigation.newThreadMode`（完整 id，如 `mode.simple`）。
  await session.waitFor(
    find.byValueKey(StudioDriverKeys.newSession.value),
    timeout: const Duration(seconds: 30),
  );
  await session.tap(find.byValueKey(StudioDriverKeys.newSession.value));
  await session.waitFor(
    find.byValueKey(StudioDriverKeys.startPage.value),
    timeout: const Duration(seconds: 30),
  );

  final before = await session.readSnapshot();
  final beforeMode = _string(_navigation(before)?['newThreadMode']);
  checks['startPageMode'] = beforeMode;
  final beforeLabel = await _labelOf(session, modeTrigger);
  checks['modeLabelBefore'] = beforeLabel;

  // --- 任务模式：简洁 -> 任务，随后菜单选中行与触发器都必须跟着新事实 ---
  final targetMode = beforeMode == 'mode.task' ? 'mode.simple' : 'mode.task';
  final targetModeRow = find.byValueKey(
    StudioDriverKeys.sessionModeOption(targetMode).value,
  );
  await session.tap(modeTrigger);
  await session.waitFor(targetModeRow, timeout: const Duration(seconds: 10));
  final targetRowLabel = await _labelOf(session, targetModeRow);
  await session.tap(targetModeRow);

  final afterMode = _string(
    _navigation(await session.readSnapshot())?['newThreadMode'],
  );
  checks['modeAfter'] = afterMode;
  checks['modeConverged'] = afterMode == targetMode;
  final afterLabel = await _labelOf(session, modeTrigger);
  checks['modeLabelAfter'] = afterLabel;
  checks['modeLabelUpdated'] = afterLabel != beforeLabel;
  checks['modeLabelMatchesSelectedRow'] = afterLabel == targetRowLabel;

  // 重新打开菜单：选中行必须是新的一行（渲染证据），而不是停在旧行。
  await session.tap(modeTrigger);
  await session.waitFor(targetModeRow, timeout: const Duration(seconds: 10));
  checks['menuStillReachable'] = true;
  await _dismiss(session, modeTrigger);

  // --- 思考强度：选择一个与当前不同的候选 ---
  final modeRouteBefore = _routeFor(
    _settings(await session.readSnapshot())?['modeModelRoutes'],
    targetMode,
  );
  final effortBefore = _string(modeRouteBefore?['effort']);
  checks['effortBefore'] = effortBefore;
  final effortLabelBefore = await _labelOf(session, effortTrigger);
  checks['effortLabelBefore'] = effortLabelBefore;
  final efforts = await _effortOptions(
    session,
    _string(modeRouteBefore?['providerId']),
    _string(modeRouteBefore?['model']),
  );
  checks['effortOptions'] = efforts;
  String? targetEffort;
  for (final candidate in efforts) {
    if (candidate != effortBefore) {
      targetEffort = candidate;
      break;
    }
  }
  if (targetEffort == null) {
    throw StateError('当前模型声明的思考强度候选不足两个：$efforts');
  }
  final targetEffortRow = find.byValueKey(
    StudioDriverKeys.reasoningEffortOption(targetEffort).value,
  );
  await session.tap(effortTrigger);
  await session.waitFor(targetEffortRow, timeout: const Duration(seconds: 10));
  await session.tap(targetEffortRow);

  final modeRouteAfter = _routeFor(
    _settings(await session.readSnapshot())?['modeModelRoutes'],
    targetMode,
  );
  final effortAfter = _string(modeRouteAfter?['effort']);
  checks['effortCanonicalRoute'] = effortAfter;
  final effortLabelAfter = await _labelOf(session, effortTrigger);
  checks['effortLabelAfter'] = effortLabelAfter;
  checks['effortLabelUpdated'] = effortLabelAfter != effortLabelBefore;
  checks['effortDisplayed'] = effortLabelAfter == targetEffort;

  // --- 反证据：没有发生任何页面跳转，也没有停在 pending 命令上 ---
  final finalSnapshot = await session.readSnapshot();
  final mutations = _settings(finalSnapshot)?['mutations'];
  checks['mutationsSettled'] = mutations is List && mutations.isEmpty;
  checks['settingsNeverVisited'] = !await _exists(session, settingsBack);
  checks['startPageStillShown'] = await _exists(
    session,
    find.byValueKey(StudioDriverKeys.startPage.value),
  );

  for (final entry in checks.entries) {
    if (entry.value == false) {
      throw StateError('check failed: ${entry.key}');
    }
  }
}

/// 触发器/菜单行内唯一文本：菜单行与触发器都由 `StudioMenuLabel` 或行内容提供一个
/// `Text`，因此按后代取文本即该控件的展示文案（不写死任何 locale 文案）。
Future<String> _labelOf(
  FlutterDriverSession session,
  SerializableFinder finder,
) {
  return session.getText(
    find.descendant(of: finder, matching: find.byType('Text')),
  );
}

/// 关掉已打开的菜单：Escape 由菜单自身的触发器快捷键处理。
Future<void> _dismiss(
  FlutterDriverSession session,
  SerializableFinder trigger,
) async {
  await session.tap(trigger);
  await session.waitForAbsent(
    find.byType('MenuItemButton'),
    timeout: const Duration(seconds: 10),
  );
}

Future<bool> _exists(
  FlutterDriverSession session,
  SerializableFinder finder,
) async {
  try {
    await session.waitFor(finder, timeout: const Duration(seconds: 2));
    return true;
  } catch (_) {
    return false;
  }
}

/// 当前路由模型声明的思考强度候选。
///
/// 候选来自 Driver 的诊断投影（`driver-diagnostics` 的 providers.details），而不是从
/// 渲染文本猜测：模型声明是 canonical 事实，菜单行只是它的展示。
Future<List<String>> _effortOptions(
  FlutterDriverSession session,
  String providerId,
  String model,
) async {
  final raw = await session.requestData(
    'driver-diagnostics',
    timeout: const Duration(seconds: 20),
  );
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw StateError('driver-diagnostics 不是 JSON 对象');
  }
  final providers = decoded['providers'];
  final details = providers is Map ? providers['details'] : null;
  if (details is! List) {
    throw StateError('driver-diagnostics 未提供 provider 详情');
  }
  for (final provider in details) {
    if (provider is! Map || provider['id'] != providerId) continue;
    final models = provider['models'];
    if (models is! List) continue;
    for (final candidate in models) {
      if (candidate is! Map || candidate['slug'] != model) continue;
      final efforts = candidate['reasoningEfforts'];
      if (efforts is! List) continue;
      return efforts.map((value) => '$value').toList();
    }
  }
  throw StateError('driver-diagnostics 未提供 $providerId/$model 的强度候选');
}

Map<String, Object?>? _routeFor(Object? routes, String modeId) {
  if (routes is! List) return null;
  for (final route in routes) {
    if (route is Map && route['modeId'] == modeId) {
      return route.cast<String, Object?>();
    }
  }
  return null;
}

String _string(Object? value) => value is String ? value : '';

Map<String, Object?>? _navigation(Map<String, dynamic> snapshot) =>
    _childMap(snapshot, 'navigation');

Map<String, Object?>? _settings(Map<String, dynamic> snapshot) =>
    _childMap(snapshot, 'settings');

Map<String, Object?>? _childMap(Map<String, dynamic> snapshot, String key) {
  final child = snapshot[key];
  if (child is Map) return child.cast<String, Object?>();
  return null;
}
