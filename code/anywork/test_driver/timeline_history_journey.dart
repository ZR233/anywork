// Opt-in native journey for the persisted long timeline history.
//
// 两个阶段由协调器分别启动，共享同一隔离 home：
//   live    通过真实 composer 提交 2000 项历史，完成并持久化后真实离页/返回，
//           在独立的单项长正文调用期间分页；再次离页/返回后记录最新小页和深页。
//          同时记录真实持久化项目与会话身份，作为冷启动的唯一目标。
//   restart 冷启动同一 home：冷启动允许从无选择的启动页开始（design/26 §26.9），
//          因此这里通过正常侧栏选择与打开动作恢复首轮同一项目与会话，核对打开后
//          的实际身份后证明首屏按视口补齐、深页身份/顺序/游标与首轮一致。
//
// 这里不生产 seed、不写 SQL、不另建发流器：候选数据全部来自真实 account→core→writer
// 的持久化结果。判定只读当前展示事实与真实页请求回包。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'cold_start_navigation.dart';
import 'flutter_driver_session.dart';
import 'timeline_observation.dart';
import 'timeline_streaming_journey.dart';

/// 与 `pl_provider_fixture::GUI_TIMELINE_HISTORY_PROMPT` 完全一致的剧本提示词。
const _prompt = 'Generate the local timeline history fixture';
const _streamPrompt = 'Stream the local timeline reading fixture';
const _items = 2000;

/// 深页预算：每页最多 32 条，2000 条共约 63 页；这里逐页读取固定页数以证明真实
/// 页边界与顺序，不把“读到 EOF”当作时延预算内的必要条件。
const _deepPages = 40;

Future<void> main(List<String> args) async {
  if (args.length != 5) {
    stderr.writeln(
      'usage: timeline_history_journey.dart PHASE VM_URL PROJECT_DIR OUTPUT_DIR COORD_DIR',
    );
    exitCode = 64;
    return;
  }
  final phase = args[0];
  if (phase != 'live' && phase != 'restart') {
    throw ArgumentError('phase must be live or restart');
  }
  final output = Directory(args[3]);
  final coord = Directory(args[4]);
  Future<void> stage(String value) =>
      File('${coord.path}/timeline-history-$phase-stage').writeAsString(value);
  final driver = await FlutterDriverSession.connect(vmServiceUrl: args[1]);
  final report = <String, Object?>{'phase': phase, 'verdict': 'pending'};
  try {
    report['pid'] = (jsonDecode(await driver.requestData('pid')) as Map)['pid'];
    await stage('connected');
    ColdStartIdentity? restartTarget;
    if (phase == 'restart') {
      // 同一数据根的冷启动允许从“无项目/会话选择”的启动页开始（design/26 §26.9）。
      // 必须通过正常侧栏选择与打开动作恢复首轮同一持久化身份，不能假定选择跨进程
      // 保留，也不在这里等待一个不会出现的自动打开。
      final target = ColdStartIdentity.fromBaseline(
        await _readBaselineFile(output),
      );
      restartTarget = target;
      try {
        report['restore'] = await _restoreColdStart(
          driver,
          target,
          phase,
          stage,
        );
      } on ColdStartNavigationFailure catch (error) {
        // 失败现场保留到报告：不把“没能恢复目标”改写成自动打开。
        report['restore'] = error.evidence;
        throw StateError('${error.message}: ${jsonEncode(error.evidence)}');
      }
    }
    if (phase == 'live') {
      await _openProject(driver, args[2]);
      await stage('project_opened');
      await _submit(driver, _prompt);
      await stage('prompt_submitted');
      // Turn 正常完成是独立事实：status 必须是 completed，且不再 busy。
      final completed = await _waitFor(
        driver,
        (snapshot) =>
            _generationSettled(snapshot) &&
            !_isBusy(snapshot) &&
            _lastTurnStatus(snapshot) == 'completed',
        'completion',
        timeout: const Duration(seconds: 300),
      );
      report['completion'] = _snapshotSummary(completed);
      report['turnCompleted'] = _lastTurnStatus(completed) == 'completed';
      // 真实持久化身份是冷启动必须复现的目标：三个权威来源必须一致且非空。
      final identity = readOpenedTimelineIdentity(completed);
      report['identity'] = identity.toJson();
      if (!identity.consistent ||
          identity.projectId == null ||
          identity.threadId == null ||
          identity.facts['projectPath'] == null) {
        throw StateError(
          'live snapshot has no single consistent persisted identity: '
          '${identity.toJson()}',
        );
      }
      await stage('turn_completed');
      final seedDurable = await _waitFor(
        driver,
        (snapshot) =>
            _generationSettled(snapshot) &&
            _durable(snapshot) &&
            !_isBusy(snapshot) &&
            _lastTurnStatus(snapshot) == 'completed',
        'seed_durable',
        timeout: const Duration(seconds: 300),
      );
      report['seed'] = <String, Object?>{
        'expectedIndependentItems': _items,
        'expectedReferenceTokensPerItem': 64,
        'expectedReferenceTokens': _items * 64,
        'settled': _snapshotSummary(seedDurable),
      };
      // 换代只能来自真实路由撤销展示需求，再加入同一会话。
      report['seedReattach'] = await _reattachThroughSettings(
        driver,
        seedDurable,
      );
      await _submit(driver, _streamPrompt);
      await stage('stream_prompt_submitted');
      report['streamingHistory'] = await observeStreamingHistory(
        driver,
        output,
      );
      final streamDurable = await _waitFor(
        driver,
        (snapshot) =>
            _generationSettled(snapshot) &&
            _durable(snapshot) &&
            !_isBusy(snapshot) &&
            _lastTurnStatus(snapshot) == 'completed',
        'stream_durable',
        timeout: const Duration(seconds: 300),
      );
      // returnLive 保留已加载窗口；跨重启对照的小页必须由另一次真实 reattach 建立。
      report['comparisonReattach'] = await _reattachThroughSettings(
        driver,
        streamDurable,
      );
    }
    // 持久化收束是另一个独立事实：ready 且 pendingCommits == 0 之后才允许正常退出。
    final settled = await _waitFor(
      driver,
      (snapshot) =>
          _generationSettled(snapshot) &&
          _durable(snapshot) &&
          !_isBusy(snapshot) &&
          (phase == 'restart' || _lastTurnStatus(snapshot) == 'completed'),
      'durable_settled',
      timeout: const Duration(seconds: 300),
    );
    report['settled'] = _snapshotSummary(settled);
    final initialStability = TimelineViewportStability();
    final filled = await _waitFor(
      driver,
      initialStability.accept,
      'viewport_filled',
    );
    final latest = TimelineObservation.parse(filled);
    latest.requireConsistentIds();
    if (restartTarget != null && latest.threadId != restartTarget.threadId) {
      throw StateError(
        'restart timeline belongs to ${latest.threadId}, '
        'expected ${restartTarget.threadId}',
      );
    }
    // 小页仍由 tail 提供，展示集合在其基础上按真实视口补齐。
    final latestScroll = TimelineScrollObservation.parse(filled);
    report['latestPage'] = <String, Object?>{
      ...latest.summary(),
      // 冷启动必须复现同一份有序身份，不只是首尾。
      'itemIds': latest.itemIds,
      'scroll': latestScroll.toJson(),
      'viewportFilled': timelineViewportSettled(filled),
      'atLiveEdge': latestScroll.atLiveEdge,
      'pixelsAtTop': (latestScroll.pixels ?? 1).abs() <= 0.5,
      'hasOlder': latest.hasOlder,
    };
    // 2000 条持久化历史意味着最新小页之后仍有更早内容；这也证明“最新小页”不是
    // 唯一一页全量加载。
    final latestOk =
        latest.isLive &&
        timelineViewportSettled(filled) &&
        latestScroll.atLiveEdge &&
        (latestScroll.pixels ?? 1).abs() <= 0.5 &&
        latest.hasOlder;
    report['coldStartLatest'] = <String, Object?>{
      'phase': phase,
      'live': latest.isLive,
      'loadedItems': latest.itemCount,
      'viewportFilled': timelineViewportSettled(filled),
      'pixelsAtTop': (latestScroll.pixels ?? 1).abs() <= 0.5,
      'hasOlder': latest.hasOlder,
    };
    await stage('latest_page_observed');

    // 真实页请求：向更早方向逐页读取，记录每页边界、顺序、游标与去重。
    final pages = <Map<String, Object?>>[];
    var previous = latest;
    final seen = <String>{...latest.itemIds};
    var duplicateIdentity = false;
    var orderViolation = false;
    var cursorStalled = false;
    var pageGrowthViolations = <Map<String, Object?>>[];
    for (var page = 1; page <= _deepPages; page++) {
      if (!previous.hasOlder) break;
      final before = previous;
      var validated = before;
      await driver.requestData('load-older');
      final next = await _waitFor(
        driver,
        (snapshot) {
          final timeline = TimelineObservation.optional(snapshot);
          if (timeline != null) {
            // Loading snapshots also retain completed atoms. Protect newly
            // observed atoms in every subsequent snapshot of this page.
            _requireFrozenCoverage(validated, timeline);
            validated = timeline;
          }
          return timeline != null &&
              !timeline.loadingOlder &&
              timeline.itemCount > before.itemCount &&
              timelineViewportSettled(snapshot);
        },
        'page_$page',
        timeout: const Duration(seconds: 60),
      );
      final after = TimelineObservation.parse(next);
      _requireFrozenCoverage(before, after);
      final delivered = after.itemCount - before.itemCount;
      final retained = before.itemIds.every(after.itemIds.contains);
      final prepended =
          after.itemIds.isNotEmpty &&
          after.itemIds.first != before.itemIds.first &&
          after.itemIds.last == before.itemIds.last;
      for (final id in after.itemIds) {
        if (!seen.add(id) && !before.itemIds.contains(id)) {
          duplicateIdentity = true;
        }
      }
      if (!after.appendSeqAscending) orderViolation = true;
      final cursorMoved =
          after.olderCursor != before.olderCursor || after.hasOlder == false;
      if (!cursorMoved) cursorStalled = true;
      if (!retained || !prepended || delivered <= 0 || delivered > 32) {
        pageGrowthViolations = <Map<String, Object?>>[
          ...pageGrowthViolations,
          <String, Object?>{
            'page': page,
            'before': before.itemCount,
            'after': after.itemCount,
            'retained': retained,
            'prepended': prepended,
          },
        ];
      }
      pages.add(<String, Object?>{
        'page': page,
        'beforeItems': before.itemCount,
        'afterItems': after.itemCount,
        'delivered': delivered,
        // 有序 ID：冷启动必须复现同一顺序，而不是只比首尾。
        'itemIds': after.itemIds,
        'firstId': after.itemIds.isEmpty ? null : after.itemIds.first,
        'lastId': after.itemIds.isEmpty ? null : after.itemIds.last,
        'olderCursorBefore': before.olderCursor,
        'olderCursorAfter': after.olderCursor,
        'hasOlder': after.hasOlder,
        'mode': after.mode,
        'generation': after.generation,
        'timelineEpoch': after.timelineEpoch,
        'frozenFieldsRetained': true,
        'retained': retained,
        'prepended': prepended,
        'orderAscending': after.appendSeqAscending,
        'cursorMoved': cursorMoved,
      });
      previous = after;
    }
    report['paging'] = <String, Object?>{
      'pages': pages,
      'pageCount': pages.length,
      'duplicateIdentity': duplicateIdentity,
      'orderViolation': orderViolation,
      'cursorStalled': cursorStalled,
      'growthViolations': pageGrowthViolations,
      'oldestLoadedId': previous.itemIds.isEmpty
          ? null
          : previous.itemIds.first,
      'loadedItems': previous.itemCount,
      // 真实分页深度；2000 项库存足够读取 40 个 partial pages，不要求 EOF。
      'partialDepthPages': pages.length,
      'reachedEnd': !previous.hasOlder,
      'hasOlder': previous.hasOlder,
      'olderCursor': previous.olderCursor,
      'mode': previous.mode,
      'generation': previous.generation,
    };
    report['latestPageOk'] = latestOk;
    report['pagingOk'] =
        pages.length == _deepPages &&
        !duplicateIdentity &&
        !orderViolation &&
        !cursorStalled &&
        pageGrowthViolations.isEmpty &&
        previous.mode == latest.mode &&
        previous.generation == latest.generation &&
        previous.timelineEpoch == latest.timelineEpoch &&
        previous.hasOlder;
    report['pass'] = latestOk && (report['pagingOk'] == true);
    await File(
      '${output.path}/timeline-history-$phase.json',
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(report)}\n');
    if (phase == 'live') {
      await _verifyCrossRestartBaseline(report, output);
    } else {
      await _compareWithFirstRun(report, output);
    }
    await File(
      '${output.path}/timeline-history-$phase.json',
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(report)}\n');
    await stage('journey_complete');
  } on Object catch (error) {
    report['failure'] = '$error';
    // Seed completion and route reattach also consume the real source. Preserve
    // its notice before shutdown, while keeping the original failure outermost.
    try {
      final failed = await driver.readSnapshot();
      if ((failed['timeline'] as Map?)?['connection'] == 'failed') {
        final evidence = <String, Object?>{
          'failure': '$error',
          'snapshot': _snapshotSummary(failed),
        };
        try {
          evidence['connectionNotice'] = await driver.getText(
            find.descendant(
              of: find.descendant(
                of: find.byValueKey('timeline-connection-notice'),
                matching: find.byType('Expanded'),
              ),
              matching: find.byType('Text'),
            ),
          );
          await File('${output.path}/timeline-history-$phase-source-failed.png')
              .writeAsBytes(await driver.screenshot());
        } catch (diagnosticError) {
          evidence['diagnosticError'] = '$diagnosticError';
        }
        report['sourceFailure'] = evidence;
        await File('${output.path}/timeline-history-$phase-source-failed.json')
            .writeAsString(jsonEncode(evidence));
      }
    } catch (diagnosticError) {
      report['failureDiagnosticError'] = '$diagnosticError';
    }
    rethrow;
  } finally {
    // 正常关闭必须走产品自己的退出协调器：OS 退出码由协调器核对。
    try {
      final shutdown = jsonDecode(
        await driver
            .requestData('shutdown', timeout: const Duration(seconds: 90))
            .timeout(const Duration(seconds: 95)),
      );
      if (shutdown is Map) {
        report['shutdownDetails'] = <String, Object?>{
          'outcome': shutdown['outcome'],
          'persistence': shutdown['persistence'],
          'clientCloseObserved': shutdown['clientCloseObserved'],
          'clientCloseResources': shutdown['clientCloseResources'],
          'issues': switch (shutdown['issues']) {
            final List issues => [
              for (final issue in issues)
                if (issue is Map)
                  <String, Object?>{
                    'stage': issue['stage'],
                    'code': issue['code'],
                    'retryable': issue['retryable'],
                    'correlationId': issue['correlationId'],
                  }
                else
                  <String, Object?>{'malformed': true},
            ],
            _ => null,
          },
        };
      }
      if (shutdown is! Map || shutdown['shutdown'] != 'completed') {
        report['shutdown'] = 'degraded';
      } else {
        report['shutdown'] = 'completed';
        await driver.requestData('request-app-exit');
      }
    } on Object catch (error) {
      report['shutdown'] = 'failed: $error';
    }
    await File(
      '${output.path}/timeline-history-$phase.json',
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(report)}\n');
    try {
      await driver.close().timeout(const Duration(seconds: 5));
    } catch (_) {
      // A completed shutdown must not keep the acceptance process open.
    }
  }
  if (report['pass'] != true || report['shutdown'] != 'completed') {
    throw StateError(
      'timeline-history $phase failed: pagingOk=${report['pagingOk']}, '
      'shutdown=${report['shutdown']}; details=${report['shutdownDetails']}',
    );
  }
}

/// 首轮记录冷启动必须复现的**完整**事实：最新小页身份、每页有序身份、游标与边界。
///
/// 40 页 × 每页 ≤32 条的有序 ID 是透明证据，不把全部 2000 项缓存当成前提。
Future<void> _verifyCrossRestartBaseline(
  Map<String, Object?> report,
  Directory output,
) async {
  final paging = report['paging']! as Map<String, Object?>;
  final pages = (paging['pages']! as List).cast<Map<String, Object?>>();
  final latest = report['latestPage']! as Map<String, Object?>;
  final identity = report['identity']! as Map<String, Object?>;
  // 冷启动目标身份只能来自首轮真实 snapshot；缺失即验收失败，不写空值占位。
  final projectId = identity['projectId'];
  final threadId = identity['threadId'];
  final projectPath = identity['projectPath'];
  if (projectId is! String ||
      projectId.isEmpty ||
      threadId is! String ||
      threadId.isEmpty ||
      projectPath is! String ||
      projectPath.isEmpty) {
    throw StateError('live report has no persisted identity: $identity');
  }
  final baseline = <String, Object?>{
    // 冷启动必须恢复同一持久化项目与会话；这是正常侧栏选择的唯一目标身份。
    'projectId': projectId,
    'projectPath': projectPath,
    'threadId': threadId,
    'identity': identity,
    'latestItemIds': latest['itemIds'],
    'latestItemCount': latest['itemCount'],
    'oldestLoadedId': paging['oldestLoadedId'],
    'loadedItems': paging['loadedItems'],
    'partialDepthPages': paging['partialDepthPages'],
    'reachedEnd': paging['reachedEnd'],
    'pages': <Map<String, Object?>>[
      for (final page in pages)
        <String, Object?>{
          'page': page['page'],
          'itemIds': page['itemIds'],
          'delivered': page['delivered'],
          'timelineEpoch': page['timelineEpoch'],
          'olderCursorAfter': page['olderCursorAfter'],
          'hasOlder': page['hasOlder'],
        },
    ],
  };
  await File(
    '${output.path}/timeline-history-baseline.json',
  ).writeAsString('${const JsonEncoder.withIndent('  ').convert(baseline)}\n');
}

/// 冷启动必须复现同一份 canonical 页；opaque 游标只在同 epoch 内逐字比较。
Future<void> _compareWithFirstRun(
  Map<String, Object?> report,
  Directory output,
) async {
  final baselineFile = File('${output.path}/timeline-history-baseline.json');
  if (!baselineFile.existsSync()) {
    report['restartComparison'] = 'missingBaseline';
    report['pass'] = false;
    return;
  }
  final baseline = (jsonDecode(await baselineFile.readAsString()) as Map)
      .cast<String, Object?>();
  final paging = report['paging']! as Map<String, Object?>;
  final pages = (paging['pages']! as List).cast<Map<String, Object?>>();
  final baselinePages = (baseline['pages']! as List)
      .cast<Map<String, Object?>>()
      .map((page) => page.cast<String, Object?>())
      .toList();
  final latestPage = (report['latestPage']! as Map).cast<String, Object?>();
  final restore =
      (report['restore'] as Map?)?.cast<String, Object?>() ??
      const <String, Object?>{};

  List<String> ids(Object? value) => <String>[
    for (final id in (value as List? ?? const [])) '$id',
  ];

  bool validCursorBoundary(Object? cursor, Object? hasOlder) =>
      switch (hasOlder) {
        true => cursor is String && cursor.isNotEmpty,
        false => cursor == null,
        _ => false,
      };

  // 打开后的真实身份必须就是首轮同一持久化项目与会话：值相等的 id，不是“某个
  // 项目/会话”。缺失与不符都直接失败。
  final identityMatches =
      restore['projectId'] != null &&
      restore['projectId'] == baseline['projectId'] &&
      restore['projectPath'] != null &&
      restore['projectPath'] == baseline['projectPath'] &&
      restore['threadId'] != null &&
      restore['threadId'] == baseline['threadId'] &&
      restore['evidenceConsistent'] == true &&
      restore['projectIdMatches'] == true &&
      restore['threadIdMatches'] == true;
  final latestMatches = _sameIds(
    ids(baseline['latestItemIds']),
    ids(latestPage['itemIds']),
  );
  final comparisons = <Map<String, Object?>>[];
  final comparable = pages.length < baselinePages.length
      ? pages.length
      : baselinePages.length;
  for (var index = 0; index < comparable; index++) {
    final first = baselinePages[index];
    final cold = pages[index];
    final firstIds = ids(first['itemIds']);
    final coldIds = ids(cold['itemIds']);
    final firstEpoch = first['timelineEpoch'];
    final coldEpoch = cold['timelineEpoch'];
    final epochsValid =
        firstEpoch is String &&
        firstEpoch.isNotEmpty &&
        coldEpoch is String &&
        coldEpoch.isNotEmpty;
    final cursorComparable = epochsValid && firstEpoch == coldEpoch;
    final firstCursor = first['olderCursorAfter'];
    final coldCursor = cold['olderCursorAfter'];
    final cursorBoundariesValid =
        validCursorBoundary(firstCursor, first['hasOlder']) &&
        validCursorBoundary(coldCursor, cold['hasOlder']);
    comparisons.add(<String, Object?>{
      'page': index + 1,
      'sameOrderedIds': _sameIds(firstIds, coldIds),
      'firstId': coldIds.isEmpty ? null : coldIds.first,
      'lastId': coldIds.isEmpty ? null : coldIds.last,
      'baselineFirstId': firstIds.isEmpty ? null : firstIds.first,
      'baselineLastId': firstIds.isEmpty ? null : firstIds.last,
      'sameDelivered': first['delivered'] == cold['delivered'],
      'baselineTimelineEpoch': firstEpoch,
      'coldStartTimelineEpoch': coldEpoch,
      'epochsValid': epochsValid,
      'olderCursorComparable': cursorComparable,
      'olderCursorComparison': !epochsValid
          ? 'invalidEpoch'
          : cursorComparable
          ? 'sameEpochExactToken'
          : 'differentEpochNotByteComparable',
      'sameOlderCursor': cursorComparable ? firstCursor == coldCursor : null,
      'cursorBoundariesValid': cursorBoundariesValid,
      'sameHasOlder': first['hasOlder'] == cold['hasOlder'],
    });
  }
  final pageCountMatches = baselinePages.length == pages.length;
  final oldestMatches = baseline['oldestLoadedId'] == paging['oldestLoadedId'];
  final loadedItemsMatch = baseline['loadedItems'] == paging['loadedItems'];
  final same =
      identityMatches &&
      latestMatches &&
      pageCountMatches &&
      oldestMatches &&
      loadedItemsMatch &&
      comparisons.every(
        (entry) =>
            entry['sameOrderedIds'] == true &&
            entry['sameDelivered'] == true &&
            entry['epochsValid'] == true &&
            entry['cursorBoundariesValid'] == true &&
            (entry['olderCursorComparable'] == false ||
                entry['sameOlderCursor'] == true) &&
            entry['sameHasOlder'] == true,
      );
  report['restartComparison'] = <String, Object?>{
    'identityMatches': identityMatches,
    'baselineProjectId': baseline['projectId'],
    'baselineProjectPath': baseline['projectPath'],
    'baselineThreadId': baseline['threadId'],
    'coldStartProjectId': restore['projectId'],
    'coldStartProjectPath': restore['projectPath'],
    'coldStartThreadId': restore['threadId'],
    'restoreMethod': restore['method'],
    'latestMatches': latestMatches,
    'baselineLatestItemIds': baseline['latestItemIds'],
    'coldStartLatestItemIds': latestPage['itemIds'],
    'pageCountMatches': pageCountMatches,
    'baselinePageCount': baselinePages.length,
    'coldStartPageCount': pages.length,
    'oldestMatches': oldestMatches,
    'baselineOldestLoadedId': baseline['oldestLoadedId'],
    'coldStartOldestLoadedId': paging['oldestLoadedId'],
    'loadedItemsMatch': loadedItemsMatch,
    'pages': comparisons.length > 8 ? comparisons.sublist(0, 8) : comparisons,
    'pagesCompared': comparisons.length,
    'sameOrder': same,
  };
  if (!same) report['pass'] = false;
}

bool _sameIds(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

void _requireFrozenCoverage(
  TimelineObservation before,
  TimelineObservation after,
) {
  before.requireConsistentIds();
  after.requireConsistentIds();
  final oldIds = before.itemIds.toSet();
  if (before.timelineEpoch == null ||
      after.threadId != before.threadId ||
      after.generation != before.generation ||
      after.timelineEpoch != before.timelineEpoch ||
      oldIds.length != before.itemCount ||
      after.itemIds.toSet().length != after.itemCount ||
      !after.appendSeqAscending ||
      !_sameIds(
        before.itemIds,
        after.itemIds.where(oldIds.contains).toList(),
      )) {
    throw StateError('Page replaced, duplicated or reordered completed atoms');
  }
  for (final item in before.items) {
    final retained = after.item(item.id);
    if (retained == null ||
        jsonEncode(item.frozenFields()) !=
            jsonEncode(retained.frozenFields())) {
      throw StateError('Page changed frozen completed atom ${item.id}');
    }
  }
}

Future<Map<String, Object?>> _reattachThroughSettings(
  FlutterDriverSession driver,
  Map<String, dynamic> before,
) async {
  final previous = TimelineObservation.parse(before);
  final identity = readOpenedTimelineIdentity(before);
  await _tap(driver, 'settings-open');
  await driver.waitFor(
    find.byValueKey('settings-back'),
    timeout: const Duration(seconds: 30),
  );
  final detached = await _waitFor(
    driver,
    (snapshot) => TimelineObservation.optional(snapshot) == null,
    'settings_detached',
  );
  await _tap(driver, 'settings-back');
  final stability = TimelineViewportStability();
  final reopened = await _waitFor(driver, (snapshot) {
    final timeline = TimelineObservation.optional(snapshot);
    return timeline != null &&
        timeline.threadId == previous.threadId &&
        timeline.generation > previous.generation &&
        timeline.isLive &&
        stability.accept(snapshot) &&
        TimelineScrollObservation.parse(snapshot).atLiveEdge;
  }, 'settings_reattached');
  final currentIdentity = readOpenedTimelineIdentity(reopened);
  if (!identity.consistent ||
      !currentIdentity.consistent ||
      identity.projectId != currentIdentity.projectId ||
      identity.threadId != currentIdentity.threadId ||
      identity.facts['projectPath'] != currentIdentity.facts['projectPath']) {
    throw StateError('Settings return opened a different persisted identity');
  }
  final current = TimelineObservation.parse(reopened);
  current.requireConsistentIds();
  if (!current.hasOlder ||
      current.olderCursor == null ||
      current.timelineEpoch == null) {
    throw StateError('Reattached baseline lacks a real older page boundary');
  }
  return <String, Object?>{
    'method': 'settings-open/settings-back',
    'before': previous.summary(),
    'detached': _snapshotSummary(detached),
    'after': current.summary(),
    'hiddenOwners': [
      for (final owner in current.hiddenPresentationItems)
        <String, Object?>{'id': owner.id, 'memberIds': owner.memberIds},
    ],
    'identity': currentIdentity.toJson(),
    'freshGeneration': true,
  };
}

Future<void> _openProject(FlutterDriverSession driver, String project) async {
  await driver.waitFor(
    find.byValueKey('sidebar-open-project'),
    timeout: const Duration(seconds: 60),
  );
  await _tap(driver, 'sidebar-open-project');
  await _tap(driver, 'add-project-local');
  await driver.waitFor(
    find.byValueKey('add-project-continue-ready'),
    timeout: const Duration(seconds: 30),
  );
  await _tap(driver, 'add-project-continue-ready');
  await driver.waitFor(
    find.byValueKey('project-path-input'),
    timeout: const Duration(seconds: 30),
  );
  await _tap(driver, 'project-path-input');
  await driver.enterText(project);
  await driver.waitFor(
    find.byValueKey('project-path-submit'),
    timeout: const Duration(seconds: 30),
  );
  await _tap(driver, 'project-path-submit');
  await driver.waitFor(
    find.byValueKey('composer-input'),
    timeout: const Duration(seconds: 60),
  );
}

/// 首轮记录的冷启动目标身份；缺失即失败，不猜值也不选第一个项目/会话。
Future<Map<String, Object?>> _readBaselineFile(Directory output) async {
  final file = File('${output.path}/timeline-history-baseline.json');
  if (!file.existsSync()) {
    throw StateError(
      'restart has no baseline: ${file.path} '
      '(the live phase must record the persisted identity)',
    );
  }
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map) {
    throw StateError('restart baseline is not an object: $decoded');
  }
  return decoded.cast<String, Object?>();
}

/// 通过正常侧栏选择与打开动作恢复同一持久化目标，并核对打开后的实际身份。
Future<Map<String, Object?>> _restoreColdStart(
  FlutterDriverSession driver,
  ColdStartIdentity identity,
  String phase,
  Future<void> Function(String value) stage,
) {
  return restoreColdStartTarget(
    ColdStartDriverSurface(
      readSnapshot: driver.readSnapshot,
      tap: (finder, timeout) => driver.rawTap(finder, timeout: timeout),
    ),
    identity: identity,
    phase: phase,
    onStage: stage,
  );
}

Future<void> _submit(FlutterDriverSession driver, String prompt) async {
  await _tap(driver, 'composer-input');
  await driver.enterText(prompt);
  await driver.waitFor(
    find.byValueKey('composer-submit'),
    timeout: const Duration(seconds: 30),
  );
  await _tap(driver, 'composer-submit');
}

Future<void> _tap(FlutterDriverSession driver, String key) =>
    driver.rawTap(find.byValueKey(key), timeout: const Duration(seconds: 30));

Future<Map<String, dynamic>> _waitFor(
  FlutterDriverSession driver,
  bool Function(Map<String, dynamic>) predicate,
  String label, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final deadline = DateTime.now().add(timeout);
  Map<String, dynamic>? last;
  while (DateTime.now().isBefore(deadline)) {
    last = await driver.readSnapshot();
    if ((last['timeline'] as Map?)?['connection'] == 'failed') {
      throw StateError(
        'timeline-history source failed at $label: ${_snapshotSummary(last)}',
      );
    }
    if (predicate(last)) return last;
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
  throw StateError(
    'timed out waiting for timeline-history $label: ${_snapshotSummary(last)}',
  );
}

bool _generationSettled(Map<String, dynamic> snapshot) {
  return timelineViewportSettled(snapshot);
}

bool _durable(Map<String, dynamic> snapshot) {
  final persistence = snapshot['persistence'];
  return persistence is Map &&
      persistence['kind'] == 'ready' &&
      persistence['pendingCommits'] == 0;
}

bool _isBusy(Map<String, dynamic> snapshot) =>
    (snapshot['workspace'] as Map?)?['isBusy'] == true;

/// 最近一次 Turn 的权威状态（完成后 `turn` 为空，`lastTurn` 仍在）。
String? _lastTurnStatus(Map<String, dynamic> snapshot) {
  final workspace = snapshot['workspace'] as Map?;
  final lastTurn = workspace?['lastTurn'] as Map?;
  final status = lastTurn?['status'];
  return status is String ? status : null;
}

Map<String, Object?> _snapshotSummary(Map<String, dynamic>? snapshot) {
  if (snapshot == null) return const <String, Object?>{'observed': false};
  final workspace = snapshot['workspace'] as Map?;
  final persistence = snapshot['persistence'] as Map?;
  final timeline = TimelineObservation.optional(snapshot);
  return <String, Object?>{
    'selectedProjectId': (snapshot['navigation'] as Map?)?['selectedProjectId'],
    'selectedThreadId': (snapshot['navigation'] as Map?)?['selectedThreadId'],
    'isStartPage': (snapshot['navigation'] as Map?)?['isStartPage'],
    'isBusy': workspace?['isBusy'],
    'syncState': workspace?['syncState'],
    'outputTokens': (workspace?['usage'] as Map?)?['outputTokens'],
    'persistenceKind': persistence?['kind'],
    'pendingCommits': persistence?['pendingCommits'],
    'timeline': timeline?.summary(),
  };
}
