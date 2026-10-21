import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'flutter_driver_session.dart';
import 'sidebar_navigation.dart';

Future<void> main(List<String> args) async {
  if (args.length != 6 || !const ['first', 'restart'].contains(args[0])) {
    stderr.writeln(
      'usage: statistics_journey.dart first|restart VM_URL PROJECT_DIR OUTPUT_DIR COORD_DIR EXPECTED_SAMPLES',
    );
    exitCode = 64;
    return;
  }
  final phase = args[0];
  final output = Directory(args[3]);
  final coord = Directory(args[4]);
  final expected = int.parse(args[5]);
  final driver = await FlutterDriverSession.connect(vmServiceUrl: args[1]);
  final progress = _DriverProgress(output);
  Future<void> stage(String name) =>
      File('${coord.path}/statistics-stage').writeAsString(name);
  try {
    await progress.mark('connect', 'session');
    await stage('${phase}_connected');
    await _openStatistics(driver, progress);
    final initial = await _readStatistics(driver);
    if (phase == 'restart') {
      _verifyPopulated(initial, expected);
      _verifyHealthy(initial);
      await _capture(driver, output, 'statistics-restarted', initial);
      await progress.run(
        'restart',
        'settings-back',
        () => _rawTap(driver, 'settings-back'),
      );
      await progress.run(
        'restart',
        'sidebar-search',
        () => _waitForKey(driver, 'sidebar-search'),
      );
      final identityPath = File(
        '${output.path}/statistics-paced-thread-id.txt',
      );
      if (!identityPath.existsSync()) {
        throw StateError('paced thread identity missing for restart');
      }
      final pacedThreadId = identityPath.readAsStringSync().trim();
      final firstEvidence = jsonDecode(
        File('${output.path}/statistics-paced-status.json').readAsStringSync(),
      );
      if (firstEvidence is! Map) {
        throw StateError('first paced throughput evidence missing');
      }
      await progress.mark('restart', 'reveal-thread', key: pacedThreadId);
      await revealSidebarThread(driver, pacedThreadId);
      await progress.run(
        'restart',
        'thread-row-$pacedThreadId',
        () => _waitForKey(driver, 'thread-row-$pacedThreadId'),
      );
      await progress.run(
        'restart',
        'thread-row-$pacedThreadId',
        () => _rawTap(driver, 'thread-row-$pacedThreadId'),
      );
      await progress.run(
        'restart',
        'thread-throughput',
        () => _waitForKey(driver, 'thread-throughput'),
      );
      await _captureThroughput(
        driver,
        output,
        'statistics-restarted-status',
        pacedThreadId,
        expected: firstEvidence.cast<String, dynamic>(),
      );
      await stage('restart_verified');
    } else {
      if (_sampleCount(initial) != 0 ||
          (initial['history'] as List).isNotEmpty ||
          initial['statisticsPending'] != false ||
          initial['statisticsGap'] != false ||
          initial['readFailed'] != false) {
        throw StateError('isolated statistics page was not empty');
      }
      await _capture(driver, output, 'statistics-empty', initial);
      await stage('empty_verified');
      await progress.run(
        'empty',
        'settings-back',
        () => _rawTap(driver, 'settings-back'),
      );
      await _openProject(driver, args[2], progress);
      await stage('ready_lock');
      await _waitForFile(File('${coord.path}/lock-acquired'));
      await _submit(
        driver,
        progress,
        'fast',
        'Local statistics fast response',
        newThread: true,
      );
      await File('${coord.path}/fast-submitted').writeAsString('submitted');
      await stage('fast_submitted');
      await _openStatistics(driver, progress);
      final locked = await _waitForPending(driver);
      await _captureState(output, 'statistics-locked', locked);
      await File('${coord.path}/lock-observed').writeAsString('observed');
      await stage('lock_observed');
      await _waitForTurn(driver, 5, output, 'fast');
      final fast = await _waitForStatistics(driver, 1);
      _verifyHealthy(fast);
      await _capture(driver, output, 'statistics-fast', fast);
      await stage('fast_verified');

      await progress.run(
        'paced',
        'settings-back',
        () => _rawTap(driver, 'settings-back'),
      );
      await progress.run(
        'paced',
        'sidebar-new-session',
        () => _waitForKey(driver, 'sidebar-new-session'),
      );
      await progress.run(
        'paced',
        'sidebar-new-session',
        () => _rawTap(driver, 'sidebar-new-session'),
      );
      await progress.run(
        'paced',
        'composer-input',
        () => _waitForKey(driver, 'composer-input'),
      );
      await _submit(
        driver,
        progress,
        'paced',
        'Local statistics paced response',
        newThread: true,
      );
      await stage('paced_submitted');
      await _waitForTurn(driver, 25, output, 'paced');
      final workspace = (await driver.readSnapshot())['workspace'];
      final turn = workspace is Map ? workspace['lastTurn'] : null;
      final turnFields = turn is Map ? turn : const {};
      final diagnostic = {
        'status': turnFields['status'],
        'reason': turnFields['reason'],
        'usage': workspace is Map ? workspace['usage'] : null,
      };
      await File('${output.path}/statistics-paced-turn.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(diagnostic)}\n',
      );
      final pacedThreadId = workspace is Map ? workspace['threadId'] : null;
      if (pacedThreadId is! String || pacedThreadId.isEmpty) {
        throw StateError('paced thread identity missing after turn');
      }
      await _captureThroughput(
        driver,
        output,
        'statistics-paced-status',
        pacedThreadId,
      );
      await _openStatistics(driver, progress);
      final paced = await _waitForStatistics(
        driver,
        (fast['history'] as List).length + 1,
      );
      await _captureState(output, 'statistics-paced-diagnostics', paced);
      _verifyPopulated(paced, (fast['history'] as List).length + 1);
      _verifyHealthy(paced);
      await _capture(driver, output, 'statistics-final', paced);
      await stage('paced_verified');
    }
    final result = jsonDecode(
      await driver
          .requestData('shutdown', timeout: const Duration(seconds: 60))
          .timeout(const Duration(seconds: 65)),
    );
    if (result is! Map || result['shutdown'] != 'completed') {
      throw StateError('native GUI shutdown failed');
    }
    await stage('${phase}_shutdown');
  } catch (error, stack) {
    try {
      await progress.fail(error, driver: driver).timeout(_actionTimeout);
    } catch (_) {
      // Diagnostics must not hide the original interaction failure.
    }
    Error.throwWithStackTrace(error, stack);
  } finally {
    try {
      await driver.close().timeout(const Duration(seconds: 5));
    } catch (_) {
      // The native shutdown can close the observation connection first.
    }
  }
}

const _actionTimeout = Duration(seconds: 30);

Future<void> _openStatistics(
  FlutterDriverSession driver,
  _DriverProgress progress,
) async {
  await progress.run(
    'settings',
    'settings-open',
    () => _waitForKey(
      driver,
      'settings-open',
      timeout: const Duration(seconds: 60),
    ),
  );
  await progress.run(
    'settings',
    'settings-open',
    () => _rawTap(driver, 'settings-open'),
  );
  await progress.run(
    'settings',
    'settings-page',
    () => _waitForKey(driver, 'settings-page'),
  );
  await progress.run(
    'settings',
    'settings-tab-statistics',
    () => _rawTap(driver, 'settings-tab-statistics'),
  );
  await progress.run(
    'settings',
    'statistics-summary',
    () => _waitForKey(driver, 'statistics-summary'),
  );
  await progress.run(
    'settings',
    'statistics-history',
    () => _waitForKey(driver, 'statistics-history'),
  );
}

Future<void> _openProject(
  FlutterDriverSession driver,
  String path,
  _DriverProgress progress,
) async {
  await progress.run(
    'project',
    'sidebar-open-project',
    () => _waitForKey(driver, 'sidebar-open-project'),
  );
  await progress.run(
    'project',
    'sidebar-open-project',
    () => _rawTap(driver, 'sidebar-open-project'),
  );
  await progress.run(
    'project',
    'add-project-local',
    () => _rawTap(driver, 'add-project-local'),
  );
  await progress.run(
    'project',
    'add-project-continue-ready',
    () => _waitForKey(driver, 'add-project-continue-ready'),
  );
  await progress.run(
    'project',
    'add-project-continue-ready',
    () => _rawTap(driver, 'add-project-continue-ready'),
  );
  await progress.run(
    'project',
    'project-path-input',
    () => _waitForKey(driver, 'project-path-input'),
  );
  await progress.run(
    'project',
    'project-path-input',
    () => _rawTap(driver, 'project-path-input'),
  );
  await progress.run(
    'project',
    'project-path-enter',
    () => driver.enterText(path).timeout(_actionTimeout),
  );
  await progress.run(
    'project',
    'project-path-submit',
    () => _waitForKey(driver, 'project-path-submit'),
  );
  await progress.run(
    'project',
    'project-path-submit',
    () => _rawTap(driver, 'project-path-submit'),
  );
  await progress.run(
    'project',
    'composer-input',
    () => _waitForKey(
      driver,
      'composer-input',
      timeout: const Duration(seconds: 60),
    ),
  );
}

Future<void> _submit(
  FlutterDriverSession driver,
  _DriverProgress progress,
  String phase,
  String prompt, {
  required bool newThread,
}) async {
  await progress.run(
    phase,
    'composer-input',
    () => _waitForKey(driver, 'composer-input'),
  );
  await progress.run(
    phase,
    'composer-input',
    () => _rawTap(driver, 'composer-input'),
  );
  await progress.run(
    phase,
    'composer-enter',
    () => driver.enterText(prompt).timeout(_actionTimeout),
  );
  final fieldText = await progress.run(
    phase,
    'composer-read',
    () => driver
        .getText(find.byValueKey('composer-input'))
        .timeout(_actionTimeout),
  );
  if (fieldText != prompt) {
    throw StateError(
      'composer-input text is "$fieldText" after entering "$prompt"',
    );
  }
  await _waitForComposerDraft(driver, prompt, newThread: newThread);
  await progress.run(
    phase,
    'composer-submit',
    () => _waitForKey(driver, 'composer-submit'),
  );
  await progress.run(
    phase,
    'composer-submit',
    () => _rawTap(driver, 'composer-submit'),
  );
}

Future<void> _waitForKey(
  FlutterDriverSession driver,
  String key, {
  Duration timeout = _actionTimeout,
}) {
  return driver.waitFor(find.byValueKey(key), timeout: timeout);
}

Future<void> _rawTap(FlutterDriverSession driver, String key) {
  return driver.rawTap(find.byValueKey(key), timeout: _actionTimeout);
}

Future<void> _waitForComposerDraft(
  FlutterDriverSession driver,
  String prompt, {
  required bool newThread,
}) async {
  final deadline = DateTime.now().add(_actionTimeout);
  Map<String, dynamic>? last;
  while (DateTime.now().isBefore(deadline)) {
    last = await driver.readSnapshot();
    final draft = _composerDraft(last, newThread: newThread);
    if (draft == prompt) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError(
    'composer draft did not become "$prompt": ${_composerDraft(last, newThread: newThread)}',
  );
}

String? _composerDraft(
  Map<String, dynamic>? snapshot, {
  required bool newThread,
}) {
  if (snapshot == null) return null;
  if (newThread) {
    final navigation = snapshot['navigation'];
    final composer = navigation is Map ? navigation['newThreadComposer'] : null;
    return composer is Map ? composer['draft'] as String? : null;
  }
  final workspace = snapshot['workspace'];
  final composer = workspace is Map ? workspace['composer'] : null;
  return composer is Map ? composer['draft'] as String? : null;
}

final class _DriverProgress {
  _DriverProgress(this.output);

  final Directory output;
  String phase = 'start';
  String action = 'idle';
  String? key;

  Future<void> mark(String nextPhase, String nextAction, {String? key}) {
    phase = nextPhase;
    action = nextAction;
    this.key = key;
    return _write();
  }

  Future<T> run<T>(
    String nextPhase,
    String nextAction,
    Future<T> Function() body,
  ) async {
    await mark(nextPhase, nextAction, key: nextAction);
    return body();
  }

  Future<void> fail(Object error, {FlutterDriverSession? driver}) async {
    final payload = {
      'phase': phase,
      'action': action,
      'key': key,
      'error': '$error',
      'capturedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await File(
      '${output.path}/statistics-driver-progress.json',
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(payload)}\n');
    if (driver == null) return;
    final snapshot = await driver.readSnapshot().timeout(_actionTimeout);
    await File('${output.path}/statistics-driver-failure.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(_failureSummary(snapshot))}\n',
    );
    await File('${output.path}/statistics-driver-failure-tree.txt')
        .writeAsString(await driver.renderTree().timeout(_actionTimeout));
    await File('${output.path}/statistics-driver-failure.png')
        .writeAsBytes(await driver.screenshot().timeout(_actionTimeout));
  }

  Future<void> _write() {
    return File('${output.path}/statistics-driver-progress.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({'phase': phase, 'action': action, 'key': key, 'capturedAt': DateTime.now().toUtc().toIso8601String()})}\n',
    );
  }
}

Future<void> _waitForTurn(
  FlutterDriverSession driver,
  int minimumTokens,
  Directory output,
  String label,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  Map<String, dynamic>? lastSnapshot;
  while (DateTime.now().isBefore(deadline)) {
    final snapshot = await driver.readSnapshot();
    lastSnapshot = snapshot;
    final workspace = snapshot['workspace'];
    final persistence = snapshot['persistence'];
    final turn = workspace is Map ? workspace['lastTurn'] : null;
    final usage = workspace is Map ? workspace['usage'] : null;
    final outputTokens = usage is Map ? usage['outputTokens'] : null;
    if (turn is Map &&
        const [
          'failed',
          'cancelled',
          'budgetLimited',
        ].contains(turn['status'])) {
      throw StateError(
        'model turn ended as ${turn['status']}: ${turn['reason']}',
      );
    }
    if (workspace is Map &&
        turn is Map &&
        workspace['threadStatus'] == 'idle' &&
        workspace['isBusy'] == false &&
        workspace['syncState'] == 'ready' &&
        outputTokens is num &&
        outputTokens >= minimumTokens &&
        persistence is Map &&
        persistence['kind'] == 'ready' &&
        persistence['pendingCommits'] == 0) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  final workspace = lastSnapshot?['workspace'];
  final persistence = lastSnapshot?['persistence'];
  final fields = workspace is Map ? workspace : const {};
  final lastTurn = fields['lastTurn'];
  final turnFields = lastTurn is Map ? lastTurn : const {};
  final diagnostic = {
    'threadStatus': fields['threadStatus'],
    'isBusy': fields['isBusy'],
    'syncState': fields['syncState'],
    'lastTurnStatus': turnFields['status'],
    'lastTurnReason': turnFields['reason'],
    'usage': fields['usage'],
    'persistence': persistence,
  };
  await File('${output.path}/statistics-$label-turn-timeout.json')
      .writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(diagnostic)}\n',
      );
  throw StateError('model turn did not complete and persist');
}

Future<Map<String, dynamic>> _readStatistics(
  FlutterDriverSession driver,
) async {
  final data = jsonDecode(await driver.requestData('statistics'));
  if (data is! Map<String, dynamic> ||
      data['revision'] is! int ||
      data['statisticsPending'] is! bool ||
      data['statisticsGap'] is! bool ||
      data['readFailed'] is! bool ||
      data['summaries'] is! List ||
      data['history'] is! List) {
    throw StateError('statistics bridge snapshot unavailable');
  }
  return data;
}

Future<Map<String, dynamic>> _waitForPending(
  FlutterDriverSession driver,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 18));
  while (DateTime.now().isBefore(deadline)) {
    final data = await _readStatistics(driver);
    if (data['statisticsPending'] == true) {
      if (data['statisticsGap'] != false || data['readFailed'] != false) {
        throw StateError(
          'statistics projection unhealthy while SQLite is locked: pending=${data['statisticsPending']} gap=${data['statisticsGap']} readFailed=${data['readFailed']}',
        );
      }
      return data;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('statisticsPending not observed under BEGIN IMMEDIATE');
}

void _verifyHealthy(Map<String, dynamic> data) {
  if (data['statisticsPending'] != false ||
      data['statisticsGap'] != false ||
      data['readFailed'] != false) {
    throw StateError('statistics projection did not settle after lock release');
  }
}

int _sampleCount(Map<String, dynamic> data) => (data['summaries'] as List)
    .fold<int>(0, (count, summary) => count + (summary['samples'] as int));

Future<Map<String, dynamic>> _waitForStatistics(
  FlutterDriverSession driver,
  int minimum,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(deadline)) {
    final data = await _readStatistics(driver);
    if ((data['history'] as List).length >= minimum &&
        (minimum == 1 ||
            (_sampleCount(data) > 0 &&
                (data['history'] as List).any(
                  (row) =>
                      row['tokens'] >= 25 && (row['responseMillis'] ?? 0) > 0,
                )))) {
      return data;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  throw StateError(
    'statistics did not automatically refresh to $minimum samples',
  );
}

void _verifyPopulated(Map<String, dynamic> data, int minimum) {
  if (_sampleCount(data) < 1 ||
      (data['history'] as List).length < minimum ||
      !(data['summaries'] as List).any(
        (item) => item['modelId'] == 'fixture-model' && item['tokens'] > 0,
      ) ||
      !(data['history'] as List).any(
        (item) =>
            item['modelId'] == 'fixture-model' &&
            item['tokens'] >= 25 &&
            item['responseMillis'] > 0,
      )) {
    throw StateError('statistics summary, history, or paced sample missing');
  }
  // 实时状态栏与历史汇总必须使用同一个“含首字等待”的分母：历史行的速度由
  // 输出词元 ÷ 总响应耗时复算得到，而不是参考另一套 decode 口径。
  var consistentThroughput = false;
  for (final row in (data['history'] as List).whereType<Map>()) {
    final tokens = row['tokens'];
    final responseMillis = row['responseMillis'];
    final tokensPerSecond = row['tokensPerSecond'];
    if (row['modelId'] != 'fixture-model' ||
        tokens is! num ||
        tokens < 25 ||
        responseMillis is! num ||
        responseMillis <= 0 ||
        tokensPerSecond is! num) {
      continue;
    }
    final expected = tokens * 1000 / responseMillis;
    if ((tokensPerSecond - expected).abs() <= expected * 0.01) {
      consistentThroughput = true;
    }
  }
  if (!consistentThroughput) {
    throw StateError(
      'paced history throughput does not use the total response denominator',
    );
  }
}

Future<void> _capture(
  FlutterDriverSession driver,
  Directory output,
  String name,
  Map<String, dynamic> data,
) async {
  // The Driver data endpoint omits prompts, paths, credentials and call bodies.
  await _captureState(output, name, data);
  await File('${output.path}/$name.png')
      .writeAsBytes(await driver.screenshot());
  if ((data['history'] as List).isNotEmpty) {
    final item = (data['history'] as List).first as Map;
    final key =
        'statistics-history-row:${jsonEncode([item['accountId'], item['modelId'], item['effort'], 0])}';
    await driver.scrollUntilVisible(
      find.byValueKey('statistics-history'),
      find.byValueKey(key),
      dyScroll: -200,
      timeout: const Duration(seconds: 30),
    );
    await _waitForKey(driver, key);
    await File('${output.path}/$name-history.png')
        .writeAsBytes(await driver.screenshot());
  }
}

Future<void> _captureState(
  Directory output,
  String name,
  Map<String, dynamic> data,
) async {
  await File('${output.path}/$name.json').writeAsString(
    '${const JsonEncoder.withIndent('  ').convert({
      'revision': data['revision'],
      'statisticsPending': data['statisticsPending'],
      'statisticsGap': data['statisticsGap'],
      'readFailed': data['readFailed'],
      'samples': _sampleCount(data),
      'summaries': (data['summaries'] as List).length,
      'history': (data['history'] as List).length,
      'models': [for (final row in data['summaries'] as List) row['modelId']],
      'metrics': [
        for (final row in data['history'] as List) {'modelId': row['modelId'], 'tokens': row['tokens'], 'ttftMillis': row['ttftMillis'], 'decodeMillis': row['decodeMillis'], 'responseMillis': row['responseMillis'], 'tokensPerSecond': row['tokensPerSecond']},
      ],
    })}\n',
  );
}

Future<void> _waitForFile(File file) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    if (await file.exists() && await file.readAsString() == 'acquired') return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('calls.sqlite BEGIN IMMEDIATE lock was not acquired');
}

Future<void> _captureThroughput(
  FlutterDriverSession driver,
  Directory output,
  String name,
  String threadId, {
  Map<String, dynamic>? expected,
}) async {
  await _waitForKey(driver, 'thread-throughput');
  final snapshot = await _waitForSelectedThroughput(driver, threadId);
  final workspace = snapshot['workspace'];
  final selected = workspace is Map ? workspace['threadId'] : null;
  if (selected != threadId) {
    throw StateError('selected thread $selected is not paced thread $threadId');
  }
  final diagnostics = snapshot['driverDiagnostics'];
  final runtime = diagnostics is Map ? diagnostics['runtime'] : null;
  final throughput = runtime is Map ? runtime['throughput'] : null;
  if (throughput is! Map) {
    throw StateError('canonical throughput pair missing for $threadId');
  }
  final outputTokens = throughput['outputTokens'];
  final responseMillis = throughput['responseMillis'];
  final tokensPerSecond = throughput['tokensPerSecond'];
  if (outputTokens is! num ||
      responseMillis is! num ||
      tokensPerSecond is! num ||
      outputTokens <= 0 ||
      responseMillis <= 0 ||
      !tokensPerSecond.isFinite ||
      tokensPerSecond <= 0) {
    throw StateError('incomplete canonical throughput pair: $throughput');
  }
  if (expected != null) {
    final previous = expected['throughput'];
    if (previous is! Map ||
        previous['outputTokens'] != outputTokens ||
        previous['responseMillis'] != responseMillis ||
        previous['tokensPerSecond'] != tokensPerSecond) {
      throw StateError(
        'restart throughput diverged from first sample: $previous vs $throughput',
      );
    }
  }
  final evidence = {
    'threadId': threadId,
    'throughput': throughput,
    'tokensPerSecond': tokensPerSecond,
    'turnOutputTokens': runtime is Map ? runtime['turnOutputTokens'] : null,
    'responseMillis': runtime is Map ? runtime['responseMillis'] : null,
  };
  await File(
    '${output.path}/$name.json',
  ).writeAsString('${const JsonEncoder.withIndent('  ').convert(evidence)}\n');
  await File('${output.path}/$name.png')
      .writeAsBytes(await driver.screenshot());
  await File('${output.path}/$name-tree.txt')
      .writeAsString(await driver.renderTree());
  await File('${output.path}/statistics-paced-thread-id.txt')
      .writeAsString(threadId);
}

Future<Map<String, dynamic>> _waitForSelectedThroughput(
  FlutterDriverSession driver,
  String threadId,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  Map<String, dynamic>? last;
  while (DateTime.now().isBefore(deadline)) {
    last = await driver.readSnapshot();
    final workspace = last['workspace'];
    final diagnostics = last['driverDiagnostics'];
    final runtime = diagnostics is Map ? diagnostics['runtime'] : null;
    final throughput = runtime is Map ? runtime['throughput'] : null;
    if (workspace is Map &&
        workspace['threadId'] == threadId &&
        throughput is Map &&
        throughput['outputTokens'] is num &&
        throughput['responseMillis'] is num &&
        throughput['tokensPerSecond'] is num &&
        throughput['outputTokens'] > 0 &&
        throughput['responseMillis'] > 0 &&
        (throughput['tokensPerSecond'] as num).isFinite &&
        throughput['tokensPerSecond'] > 0) {
      return last;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  throw StateError(
    'canonical throughput was not ready for $threadId: ${last?['driverDiagnostics']}',
  );
}

Map<String, Object?> _failureSummary(Map<String, dynamic> snapshot) {
  final workspace = snapshot['workspace'];
  final navigation = snapshot['navigation'];
  final persistence = snapshot['persistence'];
  final diagnostics = snapshot['driverDiagnostics'];
  final composer = navigation is Map ? navigation['newThreadComposer'] : null;
  final draft = composer is Map ? composer['draft'] : null;
  return {
    'workspace': workspace is Map
        ? {
            'threadId': workspace['threadId'],
            'threadStatus': workspace['threadStatus'],
            'isBusy': workspace['isBusy'],
            'syncState': workspace['syncState'],
          }
        : null,
    'navigation': navigation is Map
        ? {
            'selectedProjectId': navigation['selectedProjectId'],
            'selectedThreadId': navigation['selectedThreadId'],
            'isStartPage': navigation['isStartPage'],
            'draftLength': draft is String ? draft.length : null,
            'composerPhase': composer is Map ? composer['phase'] : null,
          }
        : null,
    'runtime': diagnostics is Map ? diagnostics['runtime'] : null,
    'persistence': persistence,
  };
}
