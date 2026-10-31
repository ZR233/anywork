// Linux-only cumulative timeline-history acceptance journey.
//
// The coordinator starts five independent GUI lifecycles over one isolated
// ANYWORK_HOME: seed, cold-1, cold-2, cold-3 and growth. This host Driver never
// writes storage or calls load-older directly. Seed/growth use the normal
// composer/provider/Core/writer path; paging is triggered only by real
// PointerScroll input on the production timeline.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_driver/flutter_driver.dart';

import 'cold_start_navigation.dart';
import 'flutter_driver_session.dart';
import 'pointer_scroll.dart';
import 'timeline_history_20k_contract.dart';
import 'timeline_observation.dart';

const _seedBatches = 10;
const _seedItemsPerBatch = 2000;
const _growthBatches = 20;
const _growthItemsPerBatch = 100;
const _bodyBytes = 32;
const _coldScrollPages = 6;

String _seedPrompt(int batch) =>
    'Seed timeline history batch ${batch.toString().padLeft(2, '0')} of $_seedBatches';

String _growthPrompt(int batch) =>
    'Grow timeline history batch ${batch.toString().padLeft(2, '0')} of $_growthBatches';

Future<void> main(List<String> args) async {
  if (args.length != 5) {
    stderr.writeln(
      'usage: timeline_history_20k_journey.dart '
      'PHASE VM_URL PROJECT_DIR OUTPUT_DIR COORD_DIR',
    );
    exitCode = 64;
    return;
  }
  final phase = args[0];
  if (phase != 'seed' &&
      phase != 'cold-1' &&
      phase != 'cold-2' &&
      phase != 'cold-3' &&
      phase != 'growth') {
    stderr.writeln('PHASE must be seed, cold-1, cold-2, cold-3 or growth');
    exitCode = 64;
    return;
  }
  final output = Directory(args[3]);
  final coord = Directory(args[4]);
  final reportFile = File('${output.path}/timeline-history-20k-$phase.json');
  final report = <String, Object?>{
    'scenario': 'timeline-history-20k',
    'phase': phase,
    'platform': Platform.operatingSystem,
    'processCold': phase.startsWith('cold-'),
    'osPageCacheControlled': false,
    'tokenMeasurement': 'notMeasured',
    'verdict': 'pending',
  };
  final lifecycle = Stopwatch()..start();
  final driver = await FlutterDriverSession.connect(vmServiceUrl: args[1]);
  try {
    report['driverObservableMillis'] = lifecycle.elapsedMilliseconds;
    final pid =
        (jsonDecode(await driver.requestData('pid')) as Map)['pid'] as int;
    report['pid'] = pid;
    report['storageAtDriverObservable'] = await _storageSample(pid);
    // 协调器仅以最终路径的存在作为发布屏障，不能先暴露空文件。
    final pidPath = '${coord.path}/timeline-history-20k-$phase-pid';
    await File('$pidPath.pending').writeAsString('$pid\n');
    await File('$pidPath.pending').rename(pidPath);
    await _stage(coord, phase, 'connected');
    if (phase == 'seed') {
      await _runSeed(driver, args[2], output, report, coord, phase);
    } else {
      final identity = ColdStartIdentity.fromBaseline(
        await _readBaseline(output),
      );
      if (phase.startsWith('cold-')) {
        await _runCold(driver, identity, output, report, coord, phase);
      } else {
        await _runGrowth(driver, identity, output, report, coord, phase);
      }
    }
    report['pass'] = true;
    report['verdict'] = 'passed';
    await _stage(coord, phase, 'journey_complete');
  } on Object catch (error, stack) {
    report['pass'] = false;
    report['verdict'] = 'failed';
    report['failure'] = '$error';
    report['failureStack'] = '$stack';
    rethrow;
  } finally {
    report['lifecycleMillisBeforeShutdown'] = lifecycle.elapsedMilliseconds;
    final pid = report['pid'];
    if (pid is int) {
      final end = await _storageSample(pid);
      report['storageBeforeShutdown'] = end;
      final start = report['storageAtDriverObservable'];
      if (start is Map<String, Object?>) {
        report['storageLifecycleDelta'] = _storageDelta(start, end);
      } else if (start is Map) {
        report['storageLifecycleDelta'] = _storageDelta(
          start.cast<String, Object?>(),
          end,
        );
      }
    }
    await _coordinatedShutdown(driver, report);
    await reportFile.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    );
    try {
      await driver.close().timeout(const Duration(seconds: 5));
    } on Object {
      // The native process is already exiting after a completed coordinator ACK.
    }
  }
  if (report['pass'] != true || report['shutdown'] != 'completed') {
    throw StateError('$phase did not complete: ${jsonEncode(report)}');
  }
}

Future<void> _runSeed(
  FlutterDriverSession driver,
  String project,
  Directory output,
  Map<String, Object?> report,
  Directory coord,
  String phase,
) async {
  await _openProject(driver, project);
  await _stage(coord, phase, 'project_opened');
  final batches = <Map<String, Object?>>[];
  // 失败也保留之前已完成的批次，不把局部数据冒充整个 seed 通过。
  report['seedBatchObservations'] = batches;
  for (var batch = 1; batch <= _seedBatches; batch++) {
    // 新项目仍是起始页：首次提交才创建 Thread，不存在可等待的时间线。
    final before = batch == 1
        ? null
        : await _settled(driver, 'seed-$batch-before');
    final previousTurnId = before == null ? null : _lastTurnId(before);
    final accepted = Stopwatch()..start();
    await _submit(driver, _seedPrompt(batch));
    final completed = await _waitFor(
      driver,
      (snapshot) =>
          !_busy(snapshot) &&
          _lastTurnId(snapshot) != null &&
          _lastTurnId(snapshot) != previousTurnId &&
          _lastTurnStatus(snapshot) == 'completed' &&
          _viewportReady(snapshot),
      'seed-$batch-completed',
      timeout: const Duration(minutes: 5),
    );
    final completedMillis = accepted.elapsedMilliseconds;
    final completedTurnId = _lastTurnId(completed)!;
    final durable = await _waitFor(
      driver,
      (snapshot) =>
          !_busy(snapshot) &&
          _lastTurnId(snapshot) == completedTurnId &&
          _lastTurnStatus(snapshot) == 'completed' &&
          _durable(snapshot) &&
          _viewportReady(snapshot),
      'seed-$batch-durable',
      timeout: const Duration(minutes: 5),
    );
    final queue = await _persistenceQueue(driver);
    batches.add(<String, Object?>{
      'batch': batch,
      'expectedCompletedTextItems': _seedItemsPerBatch,
      'expectedBodyBytesPerItem': _bodyBytes,
      'previousTurnId': previousTurnId,
      'completedTurnId': completedTurnId,
      'latencyOrigin': 'before composer text entry and submit input',
      'submitStartToCompletedMillis': completedMillis,
      'submitStartToDurableMillis': accepted.elapsedMilliseconds,
      'completionItemsPerSecond':
          _seedItemsPerBatch * 1000 / math.max(1, completedMillis),
      'durableItemsPerSecond':
          _seedItemsPerBatch * 1000 / math.max(1, accepted.elapsedMilliseconds),
      'firstSubmissionCreatesThread': batch == 1,
      'before': before == null ? null : _timelineSummary(before),
      'completed': _timelineSummary(completed),
      'durable': _timelineSummary(durable),
      'persistence': queue,
    });
    await _stage(coord, phase, 'seed_batch_$batch');
  }
  final settled = await _settled(driver, 'seed-final');
  final identity = readOpenedTimelineIdentity(settled);
  if (!identity.consistent ||
      identity.workspaceId == null ||
      identity.threadId == null ||
      identity.facts['projectPath'] == null) {
    throw StateError('seed has no consistent persisted identity');
  }
  report['identity'] = identity.toJson();
  report['seed'] = <String, Object?>{
    'batches': _seedBatches,
    'itemsPerBatch': _seedItemsPerBatch,
    'expectedCompletedTextItems': _seedBatches * _seedItemsPerBatch,
    'bodyBytesPerItem': _bodyBytes,
    'expectedTextBodyBytes': _seedBatches * _seedItemsPerBatch * _bodyBytes,
    'batchesEvidence': batches,
    'settled': _timelineSummary(settled),
  };
  await File('${output.path}/timeline-history-20k-baseline.json').writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{'workspaceId': identity.workspaceId, 'threadId': identity.threadId, 'projectPath': identity.facts['projectPath']})}\n',
  );
}

Future<void> _runCold(
  FlutterDriverSession driver,
  ColdStartIdentity identity,
  Directory output,
  Map<String, Object?> report,
  Directory coord,
  String phase,
) async {
  await driver.requestData('frame-start');
  final pid = report['pid']! as int;
  final storageBeforeOpen = await _storageSample(pid);
  final openWatch = Stopwatch()..start();
  final restore = await _restore(driver, identity, phase, coord);
  final selectedMillis = openWatch.elapsedMilliseconds;
  final stability = TimelineViewportStability();
  final firstViewport = await _waitFor(
    driver,
    stability.accept,
    '$phase-first-viewport',
    timeout: const Duration(minutes: 3),
  );
  final viewportMillis = openWatch.elapsedMilliseconds;
  final initial = TimelineObservation.parse(firstViewport);
  initial.requireConsistentIds();
  if (!initial.isLive) {
    throw StateError(
      '$phase initial window is not partial: ${initial.summary()}',
    );
  }
  requireTimelineHistory20kColdWindow(
    loadedCount: initial.loadedCount,
    itemCount: initial.itemCount,
    hasOlder: initial.hasOlder,
  );
  final openFrames = await _stopFrames(driver, '$phase-coldOpen');
  final storageAfterOpen = await _storageSample(pid);
  final idleState = await _settled(driver, '$phase-idle');
  final idle = TimelineObservation.parse(idleState);
  idle.requireConsistentIds();
  requireTimelineHistory20kIdleWindowUnchanged(
    initialItemCount: initial.itemCount,
    initialLoadedCount: initial.loadedCount,
    initialItemIds: initial.itemIds,
    initialOlderCursor: initial.olderCursor,
    initialHasOlder: initial.hasOlder,
    idleItemCount: idle.itemCount,
    idleLoadedCount: idle.loadedCount,
    idleItemIds: idle.itemIds,
    idleOlderCursor: idle.olderCursor,
    idleHasOlder: idle.hasOlder,
  );
  await _stage(coord, phase, 'first_viewport_settled');

  final beforeScrollQueue = TimelineHistoryQueueSample.parse(
    await _persistenceQueue(driver),
    context: '$phase before real scroll',
  );
  await driver.requestData('frame-start');
  final pages = await _scrollOlderPages(
    driver,
    phase: phase,
    count: _coldScrollPages,
  );
  final scrollFrames = await _stopFrames(driver, '$phase-realScroll');
  final storageAfterScroll = await _storageSample(pid);
  final afterScrollQueue = TimelineHistoryQueueSample.parse(
    await _persistenceQueue(driver),
    context: '$phase after real scroll',
  );
  if (beforeScrollQueue.historyAdmitted != afterScrollQueue.historyAdmitted ||
      beforeScrollQueue.historyDurable > beforeScrollQueue.historyAdmitted ||
      afterScrollQueue.historyDurable < beforeScrollQueue.historyDurable ||
      afterScrollQueue.historyDurable > afterScrollQueue.historyAdmitted) {
    throw StateError('$phase real scrolling changed history admission');
  }
  // 打开 owner 的生命周期 effect 可以仍在保存；帧/分页计时已结束，
  // 再等待既有保存排空，不能把耐久追平当成分页写入。
  await _waitFor(driver, _durable, '$phase open lifecycle durable');
  final finalState = await _settled(driver, '$phase-final');
  final finalTimeline = TimelineObservation.parse(finalState);
  final queue = await _persistenceQueue(driver);
  report['identity'] = <String, Object?>{
    'target': identity.toJson(),
    'restore': restore,
  };
  report['coldLoad'] = <String, Object?>{
    'selectionToOpenedMillis': selectedMillis,
    'selectionToFirstViewportSettledMillis': viewportMillis,
    'partialLoadBudget': timelineHistory20kColdWindowBudget,
    'initialLoadedCount': initial.loadedCount,
    'initialCanonicalAtomsLoaded': initial.itemCount,
    'initialPresentationGroups': initial.presentationItems.length,
    'initialHiddenPresentationGroups': initial.hiddenPresentationItems.length,
    'hasOlder': initial.hasOlder,
    'olderCursor': initial.olderCursor,
    'queryCalls': null,
    'minimumInitialQueriesProven': 1,
    'queryCountAvailability': 'the existing read-only facts prove a partial initial page but do not expose an exact initial query counter',
    'withinPartialLoadBudget':
        initial.itemCount <= timelineHistory20kColdWindowMaximumItems,
    'viewport': _timelineSummary(firstViewport),
    'idleCanonicalAtomsLoaded': idle.itemCount,
    'idleLoadedCount': idle.loadedCount,
    'idlePresentationGroups': idle.presentationItems.length,
    'idleHasOlder': idle.hasOlder,
    'idleOlderCursor': idle.olderCursor,
    'idleWindowUnchanged': true,
    'idleLoadedWindowGrowthObserved': false,
    'frames': openFrames,
    'storage': <String, Object?>{
      'before': storageBeforeOpen,
      'after': storageAfterOpen,
      'delta': _storageDelta(storageBeforeOpen, storageAfterOpen),
    },
  };
  report['realScroll'] = <String, Object?>{
    'trigger': 'PointerScroll(timeline-scrollable, -1000000)',
    'explicitLoadOlderRequests': 0,
    'scrollTriggeredPageLoadsObserved': pages.length,
    'pages': pages,
    'finalCanonicalAtomsLoaded': finalTimeline.itemCount,
    'finalPresentationGroups': finalTimeline.presentationItems.length,
    'frames': scrollFrames,
    'storage': <String, Object?>{
      'before': storageAfterOpen,
      'after': storageAfterScroll,
      'delta': _storageDelta(storageAfterOpen, storageAfterScroll),
    },
  };
  report['coldWatermarks'] = <String, Object?>{
    'beforeScroll': beforeScrollQueue.toJson(),
    'afterScroll': afterScrollQueue.toJson(),
  };
  report['persistence'] = queue;
}

Future<void> _runGrowth(
  FlutterDriverSession driver,
  ColdStartIdentity identity,
  Directory output,
  Map<String, Object?> report,
  Directory coord,
  String phase,
) async {
  final restore = await _restore(driver, identity, phase, coord);
  final baselineState = await _settled(driver, 'growth-baseline');
  final baseline = TimelineObservation.parse(baselineState);
  baseline.requireConsistentIds();
  final pid = report['pid']! as int;
  final liveBatches = <Map<String, Object?>>[];
  final historyBatches = <Map<String, Object?>>[];
  final pages = <Map<String, Object?>>[];
  final liveWindow = <String, Object?>{'batches': liveBatches};
  final historyWindow = <String, Object?>{
    'batches': historyBatches,
    'scrollPages': pages,
    'explicitLoadOlderRequests': 0,
  };
  final windows = <String, Object?>{
    'live': liveWindow,
    'history': historyWindow,
  };
  final growthReport = <String, Object?>{
    'baselineExpectedCompletedTextItems': 20_000,
    'growthBatches': _growthBatches,
    'itemsPerBatch': _growthItemsPerBatch,
    'expectedNewCompletedTextItems': _growthBatches * _growthItemsPerBatch,
    'bodyBytesPerItem': _bodyBytes,
    'expectedNewTextBodyBytes':
        _growthBatches * _growthItemsPerBatch * _bodyBytes,
    'fixtureEventStepMillis': 5,
    'baseline': baseline.summary(),
    'windows': windows,
  };
  report['identity'] = <String, Object?>{
    'target': identity.toJson(),
    'restore': restore,
  };
  report['growth'] = growthReport;

  await driver.requestData('frame-start');
  final liveStorageStart = await _storageSample(pid);
  for (var batch = 1; batch <= 10; batch++) {
    liveBatches.add(
      await _runGrowthBatch(driver, batch: batch, expectedMode: 'live'),
    );
    await _stage(coord, phase, 'growth_live_batch_$batch');
  }
  final liveStorageEnd = await _storageSample(pid);
  final liveWatermarks = _requireGrowthWindowWatermarks(
    liveBatches,
    'growth Live',
  );
  liveWindow.addAll(<String, Object?>{
    'watermarkGrowth': liveWatermarks,
    'frames': await _stopFrames(driver, 'growthLive'),
    'storage': <String, Object?>{
      'before': liveStorageStart,
      'after': liveStorageEnd,
      'delta': _storageDelta(liveStorageStart, liveStorageEnd),
    },
  });

  await driver.sendCommand(
    PointerScroll(find.byValueKey('timeline-scrollable'), -240),
  );
  final historyStartState = await _waitFor(
    driver,
    (snapshot) =>
        _viewportReady(snapshot) &&
        TimelineObservation.parse(snapshot).isHistory,
    'growth-enter-history',
  );
  var frozen = TimelineObservation.parse(historyStartState);
  frozen.requireConsistentIds();
  final historyAnchorIds = List<String>.of(frozen.itemIds);
  final historyAnchorScroll = TimelineScrollObservation.parse(
    historyStartState,
  );

  await driver.requestData('frame-start');
  final historyStorageStart = await _storageSample(pid);
  for (var batch = 11; batch <= _growthBatches; batch++) {
    final beforePageCount = frozen.itemCount;
    historyBatches.add(
      await _runGrowthBatch(driver, batch: batch, expectedMode: 'history'),
    );
    final pageEvidence = await _scrollOlderPages(
      driver,
      phase: 'growth-history-$batch',
      count: 1,
    );
    pages.addAll(pageEvidence);
    final state = await _settled(driver, 'growth-history-$batch-settled');
    frozen = TimelineObservation.parse(state);
    frozen.requireConsistentIds();
    if (frozen.itemCount <= beforePageCount ||
        !historyAnchorIds.every(frozen.itemIds.contains) ||
        !frozen.isHistory) {
      throw StateError('growth History lost its frozen reader window');
    }
    await _stage(coord, phase, 'growth_history_batch_$batch');
  }
  final historyEndState = await _settled(driver, 'growth-history-end');
  final historyEnd = TimelineObservation.parse(historyEndState);
  final historyEndScroll = TimelineScrollObservation.parse(historyEndState);
  final historyStorageEnd = await _storageSample(pid);
  final historyWatermarks = _requireGrowthWindowWatermarks(
    historyBatches,
    'growth History',
  );
  historyWindow.addAll(<String, Object?>{
    'anchorItemIds': historyAnchorIds,
    'anchorScroll': historyAnchorScroll.toJson(),
    'watermarkGrowth': historyWatermarks,
    'oldIdentitiesRetained': historyAnchorIds.every(
      historyEnd.itemIds.contains,
    ),
    'stayedHistory': historyEnd.isHistory,
    'hasNewOutput': historyEnd.hasNewOutput,
    'endScroll': historyEndScroll.toJson(),
    'frames': await _stopFrames(driver, 'growthHistory'),
    'storage': <String, Object?>{
      'before': historyStorageStart,
      'after': historyStorageEnd,
      'delta': _storageDelta(historyStorageStart, historyStorageEnd),
    },
  });
  growthReport['persistenceAtEnd'] = await _persistenceQueue(driver);
}

Future<Map<String, Object?>> _runGrowthBatch(
  FlutterDriverSession driver, {
  required int batch,
  required String expectedMode,
}) async {
  final beforeSnapshot = await _settled(driver, 'growth-$batch-before');
  final beforeTimeline = TimelineObservation.parse(beforeSnapshot);
  beforeTimeline.requireConsistentIds();
  final beforeTimelineWire = _timelineWire(
    beforeSnapshot,
    'growth batch $batch before',
  );
  final beforeScroll = TimelineScrollObservation.parse(beforeSnapshot);
  final previousTurnId = _lastTurnId(beforeSnapshot);
  if (beforeTimeline.mode != expectedMode) {
    throw StateError(
      'growth batch $batch started in ${beforeTimeline.mode}, expected $expectedMode',
    );
  }
  final accepted = Stopwatch()..start();
  await _submit(driver, _growthPrompt(batch));
  final samples = <Map<String, Object?>>[];
  var maxSampledPendingOperations = 0;
  var maxSampledPendingBytes = 0;
  var maxSampledInFlightBytes = 0;
  int? previousSampleMillis;
  int? firstCompletedThrough;
  int? lastCompletedThrough;
  Map<String, dynamic>? completed;
  while (accepted.elapsed < const Duration(minutes: 3)) {
    final snapshot = await driver.readSnapshot();
    final timeline = TimelineObservation.parse(snapshot);
    timeline.requireConsistentIds();
    final queue = await _persistenceQueue(driver);
    final queueSample = TimelineHistoryQueueSample.parse(
      queue,
      context: 'growth batch $batch sample ${samples.length + 1}',
    );
    maxSampledPendingOperations = math.max(
      maxSampledPendingOperations,
      queueSample.pendingOperations,
    );
    maxSampledPendingBytes = math.max(
      maxSampledPendingBytes,
      queueSample.pendingBytes,
    );
    maxSampledInFlightBytes = math.max(
      maxSampledInFlightBytes,
      queueSample.inFlightBytes,
    );
    firstCompletedThrough ??= timeline.completedThrough;
    lastCompletedThrough = timeline.completedThrough;
    final sampleMillis = accepted.elapsedMilliseconds;
    final sampleIntervalMillis = previousSampleMillis == null
        ? null
        : sampleMillis - previousSampleMillis;
    previousSampleMillis = sampleMillis;
    samples.add(<String, Object?>{
      'elapsedMillis': sampleMillis,
      'sampleIntervalMillis': sampleIntervalMillis,
      'mode': timeline.mode,
      'loadedAtoms': timeline.itemCount,
      'completedThrough': timeline.completedThrough,
      'hasNewOutput': timeline.hasNewOutput,
      ...queueSample.toJson(),
    });
    if (timeline.mode != expectedMode) {
      throw StateError(
        'growth batch $batch reader mode changed at ${sampleMillis}ms: '
        'before=${beforeTimeline.mode} after=${timeline.mode} '
        'expected=$expectedMode',
      );
    }
    if (expectedMode == 'history') {
      _requireSameHistoryScope(
        batch: batch,
        stage: 'sample at ${sampleMillis}ms',
        before: beforeTimeline,
        after: timeline,
      );
      _requireAppendOnlyHistory(
        batch: batch,
        stage: 'sample at ${sampleMillis}ms',
        before: beforeTimelineWire,
        after: _timelineWire(
          snapshot,
          'growth batch $batch sample at ${sampleMillis}ms',
        ),
      );
    }
    if (!_busy(snapshot) &&
        _lastTurnId(snapshot) != null &&
        _lastTurnId(snapshot) != previousTurnId &&
        _lastTurnStatus(snapshot) == 'completed' &&
        _viewportReady(snapshot)) {
      completed = snapshot;
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  if (completed == null) {
    throw StateError('growth batch $batch did not complete');
  }
  final completedMillis = accepted.elapsedMilliseconds;
  final completedTurnId = _lastTurnId(completed)!;
  final durable = await _waitFor(
    driver,
    (snapshot) =>
        !_busy(snapshot) &&
        _lastTurnId(snapshot) == completedTurnId &&
        _lastTurnStatus(snapshot) == 'completed' &&
        _durable(snapshot) &&
        _viewportReady(snapshot),
    'growth-$batch-durable',
    timeout: const Duration(minutes: 3),
  );
  final finalQueue = await _persistenceQueue(driver);
  final finalQueueSample = TimelineHistoryQueueSample.parse(
    finalQueue,
    context: 'growth batch $batch final queue',
  );
  final durableTimeline = TimelineObservation.parse(durable);
  durableTimeline.requireConsistentIds();
  final durableScroll = TimelineScrollObservation.parse(durable);
  final completedWatermarks = samples
      .map((sample) => sample['completedThrough'])
      .whereType<int>()
      .toSet();
  final admittedWatermarks = samples
      .map((sample) => sample['historyAdmitted'])
      .whereType<int>()
      .toSet();
  final durableWatermarks = samples
      .map((sample) => sample['historyDurable'])
      .whereType<int>()
      .toSet();
  final multipleWatermarksObserved =
      completedWatermarks.length > 1 ||
      admittedWatermarks.length > 1 ||
      durableWatermarks.length > 1;
  final sampleIntervals = samples
      .map((sample) => sample['sampleIntervalMillis'])
      .whereType<int>()
      .toList(growable: false);
  if (expectedMode == 'history') {
    _requireSameHistoryScope(
      batch: batch,
      stage: 'durable endpoint',
      before: beforeTimeline,
      after: durableTimeline,
    );
    _requireAppendOnlyHistory(
      batch: batch,
      stage: 'durable endpoint',
      before: beforeTimelineWire,
      after: _timelineWire(durable, 'growth batch $batch durable endpoint'),
    );
    final pixelsBefore = beforeScroll.pixels;
    final pixelsAfter = durableScroll.pixels;
    if (pixelsBefore == null || pixelsAfter == null) {
      throw StateError(
        'growth batch $batch History reader position is unavailable: '
        'before=${jsonEncode(beforeScroll.toJson())} '
        'after=${jsonEncode(durableScroll.toJson())}',
      );
    }
    final pixelDelta = pixelsAfter - pixelsBefore;
    if (pixelDelta.abs() > 0.5) {
      throw StateError(
        'growth batch $batch displaced the frozen History reader: '
        'beforePixels=$pixelsBefore afterPixels=$pixelsAfter '
        'delta=$pixelDelta allowedAbsoluteDelta=0.5 '
        'before=${jsonEncode(beforeScroll.toJson())} '
        'after=${jsonEncode(durableScroll.toJson())}',
      );
    }
  }
  return <String, Object?>{
    'batch': batch,
    'expectedCompletedTextItems': _growthItemsPerBatch,
    'previousTurnId': previousTurnId,
    'completedTurnId': completedTurnId,
    'latencyOrigin': 'before composer text entry and submit input',
    'submitStartToCompletedMillis': completedMillis,
    'submitStartToDurableMillis': accepted.elapsedMilliseconds,
    'completionItemsPerSecond':
        _growthItemsPerBatch * 1000 / math.max(1, completedMillis),
    'durableItemsPerSecond':
        _growthItemsPerBatch * 1000 / math.max(1, accepted.elapsedMilliseconds),
    'sampleCount': samples.length,
    'sampling': <String, Object?>{
      'targetIntervalMillis': 50,
      'observedIntervalsMillis': sampleIntervals,
      'maximumFieldsAreSampledPointsOnly': true,
      'continuousTruePeakClaimed': false,
    },
    'completedThroughStart': firstCompletedThrough,
    'completedThroughEnd': lastCompletedThrough,
    'multipleCompletionWatermarksObserved': multipleWatermarksObserved,
    'completedWatermarksObserved': completedWatermarks.length,
    'admittedWatermarksObserved': admittedWatermarks.length,
    'durableWatermarksObserved': durableWatermarks.length,
    'readerPixelsBefore': beforeScroll.pixels,
    'readerPixelsAfter': durableScroll.pixels,
    'readerPositionStable':
        expectedMode != 'history' ||
        (durableScroll.pixels! - beforeScroll.pixels!).abs() <= 0.5,
    'maxSampledPendingOperations': maxSampledPendingOperations,
    'maxSampledPendingBytes': maxSampledPendingBytes,
    'maxSampledInFlightBytes': maxSampledInFlightBytes,
    'finalHistoryAdmitted': finalQueueSample.historyAdmitted,
    'finalHistoryDurable': finalQueueSample.historyDurable,
    'completed': _timelineSummary(completed),
    'durable': _timelineSummary(durable),
    'samples': samples,
  };
}

Map<String, Object?> _timelineWire(
  Map<String, dynamic> snapshot,
  String context,
) {
  final timeline = snapshot['timeline'];
  if (timeline is! Map) {
    throw StateError('$context timeline wire is not an object');
  }
  return Map<String, Object?>.from(timeline);
}

void _requireSameHistoryScope({
  required int batch,
  required String stage,
  required TimelineObservation before,
  required TimelineObservation after,
}) {
  if (!before.isHistory ||
      !after.isHistory ||
      after.threadId != before.threadId ||
      after.generation != before.generation ||
      after.timelineEpoch != before.timelineEpoch) {
    throw StateError(
      'growth batch $batch changed History scope at $stage: '
      'before=(mode=${before.mode}, threadId=${before.threadId}, '
      'generation=${before.generation}, epoch=${before.timelineEpoch}) '
      'after=(mode=${after.mode}, threadId=${after.threadId}, '
      'generation=${after.generation}, epoch=${after.timelineEpoch})',
    );
  }
}

void _requireAppendOnlyHistory({
  required int batch,
  required String stage,
  required Map<String, Object?> before,
  required Map<String, Object?> after,
}) {
  try {
    requireTimelineHistory20kAppendOnlyWindow(before: before, after: after);
  } on StateError catch (error) {
    final beforeItems = before['items'];
    final afterItems = after['items'];
    throw StateError(
      'growth batch $batch violated append-only History at $stage: '
      '${error.message}; '
      'beforeItems=${beforeItems is List ? beforeItems.length : 'invalid'} '
      'afterItems=${afterItems is List ? afterItems.length : 'invalid'}',
    );
  }
}

Map<String, Object?> _requireGrowthWindowWatermarks(
  List<Map<String, Object?>> batches,
  String window,
) {
  final completed =
      batches
          .map((batch) => batch['completedThroughEnd'])
          .whereType<int>()
          .toSet()
          .toList()
        ..sort();
  final admitted =
      batches
          .map((batch) => batch['finalHistoryAdmitted'])
          .whereType<int>()
          .toSet()
          .toList()
        ..sort();
  final durable =
      batches
          .map((batch) => batch['finalHistoryDurable'])
          .whereType<int>()
          .toSet()
          .toList()
        ..sort();
  if (completed.length < 2 || admitted.length < 2 || durable.length < 2) {
    throw StateError(
      '$window did not expose multiple completed, admitted, and durable '
      'watermarks across its batches',
    );
  }
  return <String, Object?>{
    'completed': completed,
    'historyAdmitted': admitted,
    'historyDurable': durable,
    'multipleGrowthObserved': true,
  };
}

Future<List<Map<String, Object?>>> _scrollOlderPages(
  FlutterDriverSession driver, {
  required String phase,
  required int count,
}) async {
  final pages = <Map<String, Object?>>[];
  for (var page = 1; page <= count; page++) {
    final beforeState = await _settled(driver, '$phase-page-$page-before');
    final before = TimelineObservation.parse(beforeState);
    before.requireConsistentIds();
    if (!before.hasOlder) {
      throw StateError('$phase has no older page before page $page');
    }
    final watch = Stopwatch()..start();
    await driver.sendCommand(
      PointerScroll(find.byValueKey('timeline-scrollable'), -1000000),
    );
    var loadingObserved = false;
    final afterState = await _waitFor(
      driver,
      (snapshot) {
        final current = TimelineObservation.parse(snapshot);
        loadingObserved = loadingObserved || current.loadingOlder;
        return _viewportReady(snapshot) && current.itemCount > before.itemCount;
      },
      '$phase-page-$page',
      timeout: const Duration(seconds: 60),
    );
    final after = TimelineObservation.parse(afterState);
    after.requireConsistentIds();
    final delivered = after.itemCount - before.itemCount;
    final retained = before.itemIds.every(after.itemIds.contains);
    final cursorMoved =
        before.olderCursor != after.olderCursor || !after.hasOlder;
    if (delivered < 1 ||
        delivered > 32 ||
        !retained ||
        !after.appendSeqAscending ||
        after.itemIds.toSet().length != after.itemIds.length ||
        !cursorMoved) {
      throw StateError('$phase page $page violated identity/order/cursor');
    }
    pages.add(<String, Object?>{
      'page': page,
      'endToEndMillis': watch.elapsedMilliseconds,
      'loadingObserved': loadingObserved,
      'beforeAtoms': before.itemCount,
      'afterAtoms': after.itemCount,
      'delivered': delivered,
      'identityRetained': retained,
      'unique': after.itemIds.toSet().length == after.itemIds.length,
      'orderAscending': after.appendSeqAscending,
      'olderCursorBefore': before.olderCursor,
      'olderCursorAfter': after.olderCursor,
      'cursorMoved': cursorMoved,
      'hasOlderAfter': after.hasOlder,
      'generation': after.generation,
      'timelineEpoch': after.timelineEpoch,
    });
  }
  return pages;
}

Future<Map<String, Object?>> _restore(
  FlutterDriverSession driver,
  ColdStartIdentity identity,
  String phase,
  Directory coord,
) {
  return restoreColdStartTarget(
    ColdStartDriverSurface(
      readSnapshot: driver.readSnapshot,
      tap: (finder, timeout) => driver.rawTap(finder, timeout: timeout),
    ),
    identity: identity,
    phase: phase,
    onStage: (value) => _stage(coord, phase, value),
  );
}

Future<Map<String, Object?>> _readBaseline(Directory output) async {
  final file = File('${output.path}/timeline-history-20k-baseline.json');
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map) throw StateError('20k baseline is not an object');
  return decoded.cast<String, Object?>();
}

Future<Map<String, dynamic>> _settled(
  FlutterDriverSession driver,
  String label,
) {
  final stability = TimelineViewportStability();
  return _waitFor(driver, stability.accept, label);
}

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
        '$label source failed: '
        '${jsonEncode((last['timeline'] as Map?)?['connection'])}',
      );
    }
    if (_lastTurnStatus(last) == 'failed') {
      throw StateError(
        '$label turn failed: '
        '${jsonEncode((last['workspace'] as Map?)?['lastTurn'])}',
      );
    }
    if (predicate(last)) return last;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError(
    '$label timed out: ${jsonEncode({'navigation': last?['navigation'], 'project': last?['project'], 'workspace': last?['workspace'], 'persistence': last?['persistence'], 'timelineConnection': (last?['timeline'] as Map?)?['connection']})}',
  );
}

Future<void> _openProject(FlutterDriverSession driver, String project) async {
  await driver.waitFor(
    find.byValueKey('sidebar-open-project'),
    timeout: const Duration(seconds: 60),
  );
  await driver.rawTap(find.byValueKey('sidebar-open-project'));
  await driver.rawTap(find.byValueKey('add-project-local'));
  await driver.waitFor(
    find.byValueKey('add-project-continue-ready'),
    timeout: const Duration(seconds: 30),
  );
  await driver.rawTap(find.byValueKey('add-project-continue-ready'));
  await driver.waitFor(
    find.byValueKey('project-path-input'),
    timeout: const Duration(seconds: 30),
  );
  await driver.rawTap(find.byValueKey('project-path-input'));
  await driver.enterText(project);
  await driver.rawTap(find.byValueKey('project-path-submit'));
  await driver.waitFor(
    find.byValueKey('composer-input'),
    timeout: const Duration(seconds: 60),
  );
  await _waitFor(driver, (snapshot) {
    final navigation = snapshot['navigation'];
    final selected = snapshot['project'];
    return navigation is Map &&
        selected is Map &&
        navigation['selectedProjectId'] is String &&
        (navigation['selectedProjectId'] as String).isNotEmpty &&
        navigation['selectedProjectId'] == selected['id'] &&
        selected['path'] == project &&
        navigation['isStartPage'] == true &&
        navigation['selectedThreadId'] == null;
  }, 'new project canonical selection');
}

Future<void> _submit(FlutterDriverSession driver, String prompt) async {
  await driver.rawTap(find.byValueKey('composer-input'));
  await driver.enterText(prompt);
  await driver.rawTap(find.byValueKey('composer-submit'));
}

bool _viewportReady(Map<String, dynamic> snapshot) =>
    timelineViewportSettled(snapshot);

bool _busy(Map<String, dynamic> snapshot) =>
    (snapshot['workspace'] as Map?)?['isBusy'] == true;

String? _lastTurnStatus(Map<String, dynamic> snapshot) =>
    ((snapshot['workspace'] as Map?)?['lastTurn'] as Map?)?['status']
        as String?;

String? _lastTurnId(Map<String, dynamic> snapshot) =>
    ((snapshot['workspace'] as Map?)?['lastTurn'] as Map?)?['id'] as String?;

bool _durable(Map<String, dynamic> snapshot) {
  final persistence = snapshot['persistence'];
  return persistence is Map &&
      persistence['kind'] == 'ready' &&
      persistence['pendingCommits'] == 0;
}

Map<String, Object?> _timelineSummary(Map<String, dynamic> snapshot) {
  final timeline = TimelineObservation.parse(snapshot);
  final scroll = TimelineScrollObservation.parse(snapshot);
  return <String, Object?>{
    ...timeline.summary(),
    'presentationGroups': timeline.presentationItems.length,
    'hiddenPresentationGroups': timeline.hiddenPresentationItems.length,
    'scroll': scroll.toJson(),
  };
}

Future<Map<String, Object?>> _persistenceQueue(
  FlutterDriverSession driver,
) async {
  final decoded = jsonDecode(
    await driver.requestData(
      'persistence-queue',
      timeout: const Duration(seconds: 15),
    ),
  );
  if (decoded is! Map) {
    throw StateError('persistence-queue is not an object');
  }
  final queue = decoded.cast<String, Object?>();
  TimelineHistoryQueueSample.parse(queue, context: 'persistence-queue');
  return queue;
}

Future<Map<String, Object?>> _stopFrames(
  FlutterDriverSession driver,
  String window,
) async {
  final decoded = jsonDecode(await driver.requestData('frame-stop'));
  if (decoded is! Map) {
    throw StateError('$window frame result is not an object');
  }
  final raw = decoded.cast<String, Object?>();
  final samples = <Map<String, Object?>>[
    for (final sample in raw['samples'] as List? ?? const [])
      if (sample is Map) sample.cast<String, Object?>(),
  ];
  if (samples.isEmpty) {
    throw StateError('$window captured no FrameTiming samples');
  }

  Map<String, Object?> distribution(String field) {
    final values = <double>[
      for (final sample in samples)
        if (sample[field] is num) (sample[field] as num).toDouble(),
    ]..sort();
    if (values.isEmpty) throw StateError('$window has no $field samples');
    double percentile(double fraction) =>
        values[((values.length - 1) * fraction).round()];
    return <String, Object?>{
      'p50Millis': percentile(0.50),
      'p95Millis': percentile(0.95),
      'p99Millis': percentile(0.99),
      'maxMillis': values.last,
    };
  }

  return <String, Object?>{
    'window': window,
    'frames': raw['frames'],
    'over16Millis': raw['over16Millis'],
    'over33Millis': raw['over33Millis'],
    'build': distribution('buildMillis'),
    'raster': distribution('rasterMillis'),
    'total': distribution('totalMillis'),
    'vsyncOverhead': distribution('vsyncOverheadMillis'),
    'samples': samples,
  };
}

Future<void> _coordinatedShutdown(
  FlutterDriverSession driver,
  Map<String, Object?> report,
) async {
  try {
    final decoded = jsonDecode(
      await driver
          .requestData('shutdown', timeout: const Duration(seconds: 90))
          .timeout(const Duration(seconds: 95)),
    );
    if (decoded is Map && decoded['shutdown'] == 'completed') {
      report['shutdown'] = 'completed';
      report['shutdownDetails'] = <String, Object?>{
        'outcome': decoded['outcome'],
        'persistence': decoded['persistence'],
        'issues': decoded['issues'],
      };
      await driver.requestData('request-app-exit');
    } else {
      report['shutdown'] = 'degraded';
      report['shutdownDetails'] = decoded;
    }
  } on Object catch (error) {
    report['shutdown'] = 'failed';
    report['shutdownError'] = '$error';
  }
}

Future<void> _stage(Directory coord, String phase, String value) =>
    File('${coord.path}/timeline-history-20k-$phase-stage')
        .writeAsString(value);

Future<Map<String, Object?>> _storageSample(int pid) async {
  final io = <String, int>{};
  final ioFile = File('/proc/$pid/io');
  if (!await ioFile.exists()) {
    throw StateError('actual GUI /proc/$pid/io is unavailable');
  }
  for (final line in await ioFile.readAsLines()) {
    final parts = line.split(':');
    if (parts.length != 2) continue;
    final value = int.tryParse(parts[1].trim());
    if (value != null) io[parts[0]] = value;
  }
  for (final required in const [
    'read_bytes',
    'write_bytes',
    'cancelled_write_bytes',
  ]) {
    if (!io.containsKey(required)) {
      throw StateError('/proc/$pid/io has no $required');
    }
  }
  final database = Platform.environment['ANYWORK_TIMELINE_HISTORY_DB'];
  Future<int?> size(String path) async {
    final file = File(path);
    return await file.exists() ? (await file.stat()).size : null;
  }

  return <String, Object?>{
    'pid': pid,
    'scope': 'whole GUI process including embedded Runtime',
    'procIo': <String, Object?>{
      'readBytes': io['read_bytes'],
      'writeBytes': io['write_bytes'],
      'cancelledWriteBytes': io['cancelled_write_bytes'],
    },
    'database': database == null
        ? null
        : <String, Object?>{
            'path': database,
            'databaseBytes': await size(database),
            'walBytes': await size('$database-wal'),
          },
  };
}

Map<String, Object?> _storageDelta(
  Map<String, Object?> before,
  Map<String, Object?> after,
) {
  int? difference(Map? left, Map? right, String field) {
    final start = left?[field];
    final end = right?[field];
    return start is num && end is num ? end.toInt() - start.toInt() : null;
  }

  final beforeIo = before['procIo'] as Map?;
  final afterIo = after['procIo'] as Map?;
  final beforeDb = before['database'] as Map?;
  final afterDb = after['database'] as Map?;
  return <String, Object?>{
    'pid': after['pid'],
    'readBytes': difference(beforeIo, afterIo, 'readBytes'),
    'writeBytes': difference(beforeIo, afterIo, 'writeBytes'),
    'cancelledWriteBytes': difference(beforeIo, afterIo, 'cancelledWriteBytes'),
    'databaseBytes': difference(beforeDb, afterDb, 'databaseBytes'),
    'walBytes': difference(beforeDb, afterDb, 'walBytes'),
    'interpretation': <String>[
      'proc io is whole-process storage IO, not SQLite transaction count',
      'database and WAL sizes are logical file occupancy, not physical IO',
    ],
  };
}
