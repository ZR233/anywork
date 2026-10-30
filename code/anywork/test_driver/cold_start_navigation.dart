// 冷启动后的正常导航：通过真实侧栏选择首轮同一持久化项目与会话，再按产品入口打开。
//
// 同一数据根的冷启动允许从“无项目／会话选择”的启动页开始（design/26 §26.9）：
// 验收必须走正常的项目、会话选择与打开动作恢复同一真实持久化身份，不能假定选择
// 跨进程保留，也不为脚本新增选择持久化、自动恢复执行或旁路命令。
//
// 这里只做三件事：读取真实 snapshot 事实、在有界期限内对已挂载的稳定 Driver key
// 派发真实点击、核对打开后的实际身份。没有固定 sleep 兜底、没有猜值、没有“选第一
// 个项目或会话”，也不把 pixels 或任何恢复状态写回产品。
//
// 点击只有幂等入口：项目行、会话行在已选中时重复点击不改变选择；这里不使用会翻转
// 状态的展开开关。目标不存在时 RawTap 不会派发任何点击，因此“探测 + 点击”是同一次
// 有界真实动作，不需要额外的新命令。
import 'package:flutter_driver/flutter_driver.dart';

import 'timeline_observation.dart';

/// 冷启动必须复现的持久化身份：来自 live 阶段真实 snapshot，不是固定值。
final class ColdStartIdentity {
  const ColdStartIdentity({required this.workspaceId, required this.threadId});

  /// 从协调 baseline 读取 live 阶段记录的身份；缺失即验收失败，不回退猜测。
  factory ColdStartIdentity.fromBaseline(Map<String, Object?> baseline) {
    final workspaceId = baseline['workspaceId'];
    final threadId = baseline['threadId'];
    if (workspaceId is! String || workspaceId.isEmpty) {
      throw StateError('baseline has no persisted workspaceId: $baseline');
    }
    if (threadId is! String || threadId.isEmpty) {
      throw StateError('baseline has no persisted threadId: $baseline');
    }
    return ColdStartIdentity(workspaceId: workspaceId, threadId: threadId);
  }

  final String workspaceId;
  final String threadId;

  Map<String, Object?> toJson() => <String, Object?>{
    'workspaceId': workspaceId,
    'threadId': threadId,
  };
}

/// 打开后的实际身份事实：选择、展示、项目与 timeline 四个来源必须同一身份。
final class OpenedTimelineIdentity {
  const OpenedTimelineIdentity._({
    required this.workspaceId,
    required this.threadId,
    required this.consistent,
    required this.facts,
  });

  final String? workspaceId;
  final String? threadId;
  final bool consistent;
  final Map<String, Object?> facts;

  Map<String, Object?> toJson() => <String, Object?>{
    'workspaceId': workspaceId,
    'threadId': threadId,
    'evidenceConsistent': consistent,
    ...facts,
  };
}

/// 读取当前展示的真实身份：`navigation`（选择）、`workspace`（会话）、项目事实与
/// timeline 代次身份必须全部一致；不一致由调用方强失败，不取“第一个非空值”。
OpenedTimelineIdentity readOpenedTimelineIdentity(
  Map<String, dynamic> snapshot,
) {
  final navigation = _navigationOf(snapshot);
  final workspace = snapshot['workspace'];
  final workspaceMap = workspace is Map ? workspace : null;
  final project = snapshot['project'];
  final projectMap = project is Map ? project : null;
  final timeline = TimelineObservation.parse(snapshot);
  final navigationProject = _stringOf(navigation['selectedProjectId']);
  final navigationThread = _stringOf(navigation['selectedThreadId']);
  final workspaceProject = _stringOf(workspaceMap?['workspaceId']);
  final workspaceThread = _stringOf(workspaceMap?['threadId']);
  final projectFactId = _stringOf(projectMap?['id']);
  final timelineThread = timeline.threadId;
  final projectPath = _stringOf(projectMap?['path']);
  final consistent =
      navigationProject != null &&
      navigationThread != null &&
      workspaceProject == navigationProject &&
      workspaceThread == navigationThread &&
      projectFactId == navigationProject &&
      timelineThread == navigationThread;
  return OpenedTimelineIdentity._(
    workspaceId: navigationProject,
    threadId: timelineThread,
    consistent: consistent,
    facts: <String, Object?>{
      'navigation': <String, Object?>{
        'selectedProjectId': navigationProject,
        'selectedThreadId': navigationThread,
        'isStartPage': navigation['isStartPage'],
      },
      'workspace': <String, Object?>{
        'workspaceId': workspaceProject,
        'threadId': workspaceThread,
      },
      'projectFactId': projectFactId,
      // 目录身份：同一持久化项目的真实路径，和 id 一起排除“同名不同库”。
      'projectPath': projectPath,
      'timelineThreadId': timelineThread,
    },
  );
}

/// 可注入的最小 Driver 动作面：读取当前 snapshot 事实，并对稳定 key 派发真实点击。
///
/// 两个旅程分别用 [FlutterDriverSession] 与裸 `FlutterDriver` 实现同一动作面，
/// 不因此新增生产命令或选择缓存。
final class ColdStartDriverSurface {
  ColdStartDriverSurface({required this.readSnapshot, required this.tap});

  final Future<Map<String, dynamic>> Function() readSnapshot;

  /// 在目标当前位置派发一次真实指针点击；目标在超时内没有稳定可点位置时不点击
  /// 并抛出（由调用方记为一次未命中的真实动作）。
  final Future<void> Function(SerializableFinder finder, Duration timeout) tap;
}

/// 冷启动导航失败：携带真实诊断，调用方可写入报告后强失败。
final class ColdStartNavigationFailure implements Exception {
  ColdStartNavigationFailure(this.message, this.evidence);

  final String message;
  final Map<String, Object?> evidence;

  @override
  String toString() => 'ColdStartNavigationFailure: $message';
}

/// 轮询间隔只决定“多久再看一次真实状态”，不是完成依据。
const _pollInterval = Duration(milliseconds: 150);

/// 一次真实点击等待目标稳定的上限；超时即记为未命中，不重放已派发的点击。
const _tapTimeout = Duration(seconds: 3);

/// 同一动作在状态尚未收敛时的最小重试间隔：不连续重放同一次业务意图。
const _retapInterval = Duration(seconds: 3);

/// 通过正常 UI 入口在冷启动后恢复同一持久化项目与会话，并核对打开后的实际身份。
///
/// 只点击幂等入口：项目行、会话行在已选中时重复点击不会翻转选择。找不到目标、
/// 身份不符或打开失败都在 [budget] 内有界强失败，并保留最后一次真实观测。
Future<Map<String, Object?>> restoreColdStartTarget(
  ColdStartDriverSurface driver, {
  required ColdStartIdentity identity,
  required String phase,
  required Future<void> Function(String stage) onStage,
  Duration budget = const Duration(seconds: 180),
}) async {
  final deadline = DateTime.now().add(budget);
  final started = DateTime.now();
  final log = _NavigationLog();
  Map<String, Object?>? initial;
  var lastFacts = <String, Object?>{};
  while (DateTime.now().isBefore(deadline)) {
    final snapshot = await driver.readSnapshot();
    final navigation = _navigationOf(snapshot);
    final project = snapshot['project'];
    final projectMap = project is Map ? project : null;
    initial ??= <String, Object?>{
      'selectedProjectId': _stringOf(navigation['selectedProjectId']),
      'selectedThreadId': _stringOf(navigation['selectedThreadId']),
      'isStartPage': navigation['isStartPage'],
      'projectFactId': _stringOf(projectMap?['id']),
    };
    final timeline = TimelineObservation.optional(snapshot);
    final scroll = TimelineScrollObservation.optional(snapshot);
    final opened =
        timeline != null &&
        timeline.threadId == identity.threadId &&
        timeline.ready &&
        scroll != null &&
        scroll.laidOut;
    if (opened) {
      final evidence = _openedEvidence(
        snapshot: snapshot,
        identity: identity,
        phase: phase,
        log: log,
        initial: initial,
        elapsed: DateTime.now().difference(started),
      );
      if (evidence['evidenceConsistent'] != true ||
          evidence['workspaceIdMatches'] != true ||
          evidence['threadIdMatches'] != true) {
        throw ColdStartNavigationFailure(
          'opened timeline identity does not match the persisted target',
          evidence,
        );
      }
      await onStage('restored_${evidence['method']}');
      return evidence;
    }
    final selectedProject = _stringOf(navigation['selectedProjectId']);
    final selectedThread = _stringOf(navigation['selectedThreadId']);
    lastFacts = <String, Object?>{
      'selectedProjectId': selectedProject,
      'selectedThreadId': selectedThread,
      'isStartPage': navigation['isStartPage'],
      'timelineThreadId': timeline?.threadId,
      'timelineReady': timeline?.ready,
      'scrollLaidOut': scroll?.laidOut,
    };
    if (selectedProject == identity.workspaceId &&
        selectedThread == identity.threadId) {
      // 恢复出的“已选中但未打开”会话：走产品自己的显式打开入口。
      if (await log.attempt(
        driver,
        action: 'openSelectedThread',
        key: 'studio-open-selected-thread',
      )) {
        await onStage('requested_open');
      }
    } else if (selectedProject != identity.workspaceId) {
      // 项目选择：已选中的项目重复点击是 no-op，不翻转任何状态。
      if (await log.attempt(
        driver,
        action: 'selectProject',
        key: 'project-row-${identity.workspaceId}',
      )) {
        await onStage('selected_project');
      }
    } else if (selectedThread != identity.threadId) {
      // 会话选择：项目已在选中时会自动展开，这里只点真实会话行。
      if (await log.attempt(
        driver,
        action: 'selectThread',
        key: 'thread-row-${identity.threadId}',
      )) {
        await onStage('selected_thread');
      }
    }
    // 已选中目标会话但展示尚未就绪：只继续观察真实状态，不重放打开动作。
    await Future<void>.delayed(_pollInterval);
  }
  throw ColdStartNavigationFailure(
    'cold start target was not restored within '
    '${budget.inSeconds}s (project row, thread row or open entry never became '
    'clickable)',
    <String, Object?>{
      'phase': phase,
      'expectedProjectId': identity.workspaceId,
      'expectedThreadId': identity.threadId,
      'initial': initial,
      'lastObserved': lastFacts,
      'autoOpened': false,
      'tapAttempts': log.attempts,
      'samples': log.samples,
      'tapCounts': log.counts,
      'tapMisses': log.misses,
      'elapsedMs': DateTime.now().difference(started).inMilliseconds,
      'evidenceConsistent': false,
      'workspaceIdMatches': false,
      'threadIdMatches': false,
    },
  );
}

Map<String, Object?> _openedEvidence({
  required Map<String, dynamic> snapshot,
  required ColdStartIdentity identity,
  required String phase,
  required _NavigationLog log,
  required Map<String, Object?>? initial,
  required Duration elapsed,
}) {
  final opened = readOpenedTimelineIdentity(snapshot);
  return <String, Object?>{
    ...opened.toJson(),
    'phase': phase,
    'method': log.method,
    'autoOpened': log.attempts == 0,
    'tapAttempts': log.attempts,
    'samples': log.samples,
    'tapCounts': log.counts,
    'tapMisses': log.misses,
    'initial': initial,
    'expectedProjectId': identity.workspaceId,
    'expectedThreadId': identity.threadId,
    'workspaceIdMatches': opened.workspaceId == identity.workspaceId,
    'threadIdMatches': opened.threadId == identity.threadId,
    'elapsedMs': elapsed.inMilliseconds,
  };
}

/// 有界的真实点击记录：动作计数与少量实际点击样本，不把每次轮询都写成证据。
final class _NavigationLog {
  int attempts = 0;
  int misses = 0;
  final Map<String, int> counts = <String, int>{};
  final List<Map<String, Object?>> _samples = <Map<String, Object?>>[];
  final Map<String, DateTime> _lastAttemptAt = <String, DateTime>{};

  /// 记录的前 12 次实际点击，足以说明走了哪个真实入口。
  List<Map<String, Object?>> get samples => _samples;

  String get method {
    if (attempts == 0) return 'autoOpened';
    if ((counts['selectThread'] ?? 0) > 0) return 'sidebarThreadSelection';
    if ((counts['selectProject'] ?? 0) > 0) return 'sidebarProjectSelection';
    if ((counts['openSelectedThread'] ?? 0) > 0) {
      return 'restoredSelectionOpened';
    }
    return 'unknown';
  }

  Future<bool> attempt(
    ColdStartDriverSurface driver, {
    required String action,
    required String key,
  }) async {
    final now = DateTime.now();
    final last = _lastAttemptAt[action];
    if (last != null && now.difference(last) < _retapInterval) {
      return false;
    }
    _lastAttemptAt[action] = now;
    try {
      await driver.tap(_key(key), _tapTimeout);
    } on Object {
      // 目标此刻没有稳定可点位置：没有派发点击，继续观察真实状态。
      misses++;
      return false;
    }
    attempts++;
    counts[action] = (counts[action] ?? 0) + 1;
    if (_samples.length < 12) {
      _samples.add(<String, Object?>{'action': action, 'key': key});
    }
    return true;
  }
}

SerializableFinder _key(String value) => find.byValueKey(value);

Map<String, dynamic> _navigationOf(Map<String, dynamic> snapshot) {
  final navigation = snapshot['navigation'];
  if (navigation is! Map) {
    throw StateError('snapshot navigation is missing: ${snapshot.keys}');
  }
  return navigation.cast<String, dynamic>();
}

String? _stringOf(Object? value) => value is String ? value : null;
