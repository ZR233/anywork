// Manual native-GUI wait/sleep/child observation journey, not a Flutter test gate.
//
// It drives the isolated GUI through Flutter Driver against the wait-events
// fixture: real `sleep` / `exec` / `wait` / `spawn_agent` tools, screenshots of
// live waiting and history cards, and typed timeline snapshots. Required wait
// keys are `conversation-activity`, `conversation-activity-details`,
// `wait-card:<itemId>`, `wait-details:<itemId>` and `wait-diagnostics:<itemId>`.
// Missing or untappable required controls fail the journey.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'flutter_driver_session.dart';
import 'tool_probe.dart';
import 'realtime_journey.dart'
    show
        conversationActivity,
        isBusy,
        isDurableSettled,
        timelineRows,
        turnFailed,
        turnId,
        turnStatus,
        workspaceOf;
import 'timeline_observation.dart';
import 'window_control.dart';

const _markSleepFirst = '[[wait_sleep_first]]';
const _markToolFirst = '[[wait_tool_first]]';
const _markChild = '[[wait_child]]';
const _markChildConfirm = '[[wait_child_confirm]]';
const _markAlreadyReady = '[[wait_already_ready]]';
const _markTimeout = '[[wait_timeout]]';
const _markCancel = '[[wait_cancel]]';
const _markCancelPrepare = '[[wait_cancel_prepare]]';
const _markCancelQuery = '[[wait_cancel_query]]';

const _terminalToolStatuses = <String>{
  'succeeded',
  'failed',
  'denied',
  'cancelled',
  'interrupted',
};

const _liveToolStatuses = <String>{'started', 'streaming', 'running'};

const _narrowWindowWidth = 640;
const _narrowWindowHeight = 600;

const _waitActivityTitles = <String>{
  'Waiting for tools',
  '等待工具完成',
  'Waiting for a subagent or new message',
  '等待子代理或新消息',
};

Future<void> main(List<String> args) async {
  if (args.length != 4) {
    stderr.writeln(
      'usage: wait_events_journey.dart VM_URL PROJECT_DIR OUTPUT_DIR COORD_DIR',
    );
    exitCode = 64;
    return;
  }
  final output = Directory(args[2]);
  final coord = Directory(args[3]);
  final FlutterDriverSession driver;
  try {
    driver = await FlutterDriverSession.connect(vmServiceUrl: args[0]);
  } catch (error, stackTrace) {
    await _recordConnectFailure(output, coord, error);
    Error.throwWithStackTrace(error, stackTrace);
  }
  final FlutterDriver probe;
  try {
    probe = await FlutterDriver.connect(
      dartVmServiceUrl: args[0],
      printCommunication: false,
      logCommunicationToFile: false,
    );
  } catch (error, stackTrace) {
    try {
      await driver.close().timeout(const Duration(seconds: 5));
    } catch (error, stack) {
      stderr.writeln('Driver evidence/cleanup failed: $error\n$stack');
    }
    await _recordConnectFailure(output, coord, error);
    Error.throwWithStackTrace(error, stackTrace);
  }
  final journey = WaitEventsJourney(
    driver: driver,
    probe: probe,
    project: args[1],
    output: output,
    coord: coord,
  );
  Object? failure;
  StackTrace? failureStack;
  try {
    await journey.run();
  } catch (error, stackTrace) {
    failure = error;
    failureStack = stackTrace;
    await journey.captureFailure();
  }
  Object? probeCloseFailure;
  try {
    await probe.close().timeout(const Duration(seconds: 5));
  } catch (error) {
    probeCloseFailure = error;
    journey.shutdownError ??= 'probe close failed: $error';
  }
  Object? shutdownFailure;
  try {
    await _shutdown(driver);
  } catch (error) {
    shutdownFailure = error;
  }
  shutdownFailure ??= probeCloseFailure;
  if (shutdownFailure != null) {
    journey.shutdownError ??= shutdownFailure.toString();
  }
  if (failure == null) {
    if (shutdownFailure != null || journey.shutdownError != null) {
      journey.stage = 'shutdown_failed';
    } else if (journey.failed) {
      journey.stage = 'checks_failed';
    } else {
      journey.stage = 'complete';
    }
  }
  await journey.writeSummary(
    failure: failure,
    shutdownFailure: shutdownFailure,
  );
  await journey.mark(journey.stage);
  if (failure != null) {
    Error.throwWithStackTrace(failure, failureStack!);
  }
  await journey.raiseIfFailed(shutdownFailure);
}

Future<void> _shutdown(FlutterDriverSession driver) async {
  Object? failure;
  StackTrace? failureStack;
  try {
    final result = jsonDecode(
      await driver
          .requestData('shutdown', timeout: const Duration(seconds: 60))
          .timeout(const Duration(seconds: 65)),
    );
    if (result is! Map || result['shutdown'] != 'completed') {
      throw StateError('native GUI shutdown did not report completion');
    }
  } catch (error, stack) {
    failure = error;
    failureStack = stack;
  }
  try {
    await driver.close().timeout(const Duration(seconds: 5));
  } catch (error, stack) {
    if (failure == null) Error.throwWithStackTrace(error, stack);
    stderr.writeln('Driver cleanup also failed: $error\n$stack');
  }
  if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
}

Future<void> _recordConnectFailure(
  Directory output,
  Directory coord,
  Object error,
) async {
  try {
    await File('${coord.path}/wait-events-stage')
        .writeAsString('connect_failed');
    final summary = <String, Object?>{
      'scenario': 'wait-events',
      'verdict': 'pending',
      'status': 'failed',
      'stage': 'connect_failed',
      'error': error.toString(),
      'shutdownError': null,
      'failedChecks': const <String>[],
      'checks': const <String, Object?>{},
      'captures': const <Object?>[],
      'pendingEvidence': const <String>[],
      'completedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await File(
      '${output.path}/wait-events-summary.json',
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(summary)}\n');
  } catch (error, stack) {
    stderr.writeln('Driver evidence/cleanup failed: $error\n$stack');
  }
}

class WaitEventsJourney {
  WaitEventsJourney({
    required this.driver,
    required this.probe,
    required this.project,
    required this.output,
    required this.coord,
  });

  final FlutterDriverSession driver;
  final FlutterDriver probe;
  final String project;
  final Directory output;
  final Directory coord;
  final Map<String, Object?> checks = <String, Object?>{};
  final Map<String, Object?> observations = <String, Object?>{};
  final List<Map<String, Object?>> captures = <Map<String, Object?>>[];
  final List<String> pendingEvidence = <String>[];
  String stage = 'created';
  String? shutdownError;

  File get stageFile => File('${coord.path}/wait-events-stage');

  bool get failed =>
      checks.values.any((value) => value != true) || shutdownError != null;

  Future<void> run() async {
    await mark('connected');
    await _openProject();
    await capture('project-opened');
    await _sleepFirst();
    await _toolFirst();
    await _childWake();
    await _alreadyReady();
    await _timeout();
    await _cancelWait();
    await _layoutContracts();
    pendingEvidence.add(
      'reduce-animations and text scale have no public Driver command; '
      'narrow-window evidence uses the existing owned-window resize helper',
    );
  }

  Future<void> mark(String value) async {
    stage = value;
    await stageFile.writeAsString(value);
  }

  Future<Map<String, dynamic>> snapshot() => driver.readSnapshot();

  Future<Map<String, dynamic>> waitFor(
    bool Function(Map<String, dynamic>) predicate,
    String label, {
    Duration timeout = const Duration(seconds: 90),
    bool Function(Map<String, dynamic>)? abort,
  }) async {
    final deadline = DateTime.now().add(timeout);
    Map<String, dynamic>? last;
    while (DateTime.now().isBefore(deadline)) {
      final current = await snapshot();
      last = current;
      if (predicate(current)) return current;
      if (abort != null && abort(current)) {
        throw StateError('$label aborted: ${_summarize(current)}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    throw StateError(
      'timed out waiting for $label: ${last == null ? '{}' : _summarize(last)}',
    );
  }

  Future<void> capture(String name, {bool tree = false}) async {
    await mark(name);
    final state = await snapshot();
    final record = <String, Object?>{
      'name': name,
      'at': DateTime.now().toUtc().toIso8601String(),
      'summary': _summarize(state),
    };
    await File(
      '${output.path}/wait-events-$name.json',
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(state)}\n');
    try {
      await File('${output.path}/wait-events-$name.png')
          .writeAsBytes(await driver.screenshot());
      record['screenshot'] = true;
    } catch (error) {
      record['screenshot'] = false;
      record['screenshotError'] = '$error';
      captures.add(record);
      throw StateError('required screenshot "$name" failed: $error');
    }
    if (tree) {
      try {
        await File('${output.path}/wait-events-$name-tree.txt')
            .writeAsString(await driver.renderTree());
        record['tree'] = true;
      } catch (error) {
        record['tree'] = false;
        record['treeError'] = '$error';
      }
    }
    captures.add(record);
  }

  Future<void> captureFailure() async {
    try {
      await capture('failure', tree: true);
    } catch (error, stack) {
      stderr.writeln('Driver evidence/cleanup failed: $error\n$stack');
    }
  }

  Future<void> _openProject() async {
    await driver.waitFor(
      find.byValueKey('sidebar-open-project'),
      timeout: const Duration(seconds: 60),
    );
    await _tap('sidebar-open-project');
    await _tap('add-project-local');
    await driver.waitFor(
      find.byValueKey('add-project-continue-ready'),
      timeout: const Duration(seconds: 30),
    );
    await _tap('add-project-continue-ready');
    await driver.waitFor(
      find.byValueKey('project-path-input'),
      timeout: const Duration(seconds: 30),
    );
    await _tap('project-path-input');
    await driver.enterText(project);
    await _tap('project-path-submit');
    await driver.waitFor(
      find.byValueKey('composer-input'),
      timeout: const Duration(seconds: 60),
    );
  }

  Future<void> _tap(String key) async {
    await driver.rawTap(
      find.byValueKey(key),
      timeout: const Duration(seconds: 30),
    );
  }

  Future<SubmitContext> _submit(String prompt, String label) async {
    final before = await snapshot();
    await mark('${label}_submit');
    await driver.waitFor(
      find.byValueKey('composer-input'),
      timeout: const Duration(seconds: 30),
    );
    await _tap('composer-input');
    await driver.enterText(prompt);
    await _tap('composer-submit');
    return SubmitContext(
      priorTurnId: turnId(before),
      submittedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<Map<String, dynamic>> _awaitNewTurn(
    SubmitContext context,
    String label,
  ) {
    return waitFor(
      (snapshot) => turnId(snapshot) != context.priorTurnId,
      '${label}_running',
      timeout: const Duration(seconds: 30),
    );
  }

  Future<Map<String, dynamic>> _awaitSettled(String turn, String label) {
    return waitFor(
      (snapshot) => turnId(snapshot) == turn && isDurableSettled(snapshot),
      '${label}_settled',
      timeout: const Duration(seconds: 180),
      abort: (snapshot) =>
          turnFailed(snapshot) && turnId(snapshot) == turn && !isBusy(snapshot),
    );
  }

  /// Turn 已到达 completed。后台 sleep 可以继续 Running，不能要求整个 Thread idle。
  Future<Map<String, dynamic>> _awaitTurnCompleted(String turn, String label) {
    return waitFor(
      (snapshot) =>
          turnId(snapshot) == turn && turnStatus(snapshot) == 'completed',
      '${label}_completed',
      timeout: const Duration(seconds: 60),
      abort: turnFailed,
    );
  }

  Future<void> _sleepFirst() async {
    final context = await _submit(
      '$_markSleepFirst wait until the short timer wins',
      'sleep_first',
    );
    final running = await _awaitNewTurn(context, 'sleep_first');
    final turn = turnId(running)!;
    final waiting = await waitFor(
      (snapshot) {
        final wait = _toolByCallPrefix(snapshot, 'sleep-first-wait-t');
        final sleep = _toolByCallPrefix(snapshot, 'sleep-first-sleep-t');
        final exec = _toolByCallPrefix(snapshot, 'sleep-first-exec-t');
        return wait != null &&
            !_terminalToolStatuses.contains(wait['status']) &&
            sleep != null &&
            exec != null &&
            _liveToolStatuses.contains(exec['status']);
      },
      'sleep_first_waiting',
      timeout: const Duration(seconds: 20),
      abort: turnFailed,
    );
    final firstWait = _requireCallPrefix(waiting, 'sleep-first-wait-t');
    final firstWaitCallId = firstWait['callId'] as String;
    final firstWaitItemId = firstWait['itemId'] as String;
    final sleepCallId =
        _requireCallPrefix(waiting, 'sleep-first-sleep-t')['callId'] as String;
    final execCallId =
        _requireCallPrefix(waiting, 'sleep-first-exec-t')['callId'] as String;
    await _observeWaitUi(waiting, 'sleep-first-waiting', firstWaitItemId);
    await capture('sleep-first-waiting', tree: true);
    checks['sleepFirstWaitLive'] = true;
    checks['sleepFirstExecStillRunning'] = _liveToolStatuses.contains(
      _toolByCallPrefix(waiting, 'sleep-first-exec-t')?['status'],
    );
    final waitSucceeded = await waitFor(
      (snapshot) {
        final wait = _toolByCallId(snapshot, firstWaitCallId);
        return wait != null && wait['status'] == 'succeeded';
      },
      'sleep_first_wait_succeeded',
      timeout: const Duration(seconds: 20),
      abort: turnFailed,
    );
    final waitAtReturn = _toolByCallId(waitSucceeded, firstWaitCallId)!;
    final waitResultAtReturn = _decodeWaitResult(
      waitAtReturn['result'] as String?,
    );
    final sleepAtReturn = _requireWaitTask(
      waitResultAtReturn,
      'task:$sleepCallId',
    );
    final execAtReturn = _requireWaitTask(
      waitResultAtReturn,
      'task:$execCallId',
    );
    checks['sleepFirstWaitReadyWhileExecRunning'] =
        waitResultAtReturn['timedOut'] == false &&
        sleepAtReturn['status'] == 'succeeded' &&
        execAtReturn['status'] == 'running' &&
        execAtReturn['cancelRequested'] == false;
    if (checks['sleepFirstWaitReadyWhileExecRunning'] != true) {
      throw StateError(
        'sleep-first wait result at return did not show sleep succeeded '
        'and exec still running: $waitResultAtReturn',
      );
    }
    await capture('sleep-first-wait-returned');
    observations['sleepFirstReadyWindow'] = {
      'kind': 'waitResultAtReturn',
      'waitCallId': firstWaitCallId,
      'waitResult': waitResultAtReturn,
      'selectedTaskStatesAtReturn': {
        'sleep': sleepAtReturn,
        'exec': execAtReturn,
      },
    };
    final settled = await _awaitSettled(turn, 'sleep_first');
    await capture('sleep-first-settled');
    final followWait = _requireCallPrefix(settled, 'sleep-first-wait-exec-t');
    final sleep = _requireCallPrefix(settled, 'sleep-first-sleep-t');
    final exec = _requireCallPrefix(settled, 'sleep-first-exec-t');
    final firstWaitSettled = _requireCallPrefix(settled, 'sleep-first-wait-t');
    final waitResultLater = _decodeWaitResult(
      firstWaitSettled['result'] as String?,
    );
    checks['sleepFirstSleepSucceeded'] = sleep['status'] == 'succeeded';
    checks['sleepFirstExecSucceeded'] = exec['status'] == 'succeeded';
    checks['sleepFirstWaitReady'] =
        firstWaitSettled['status'] == 'succeeded' &&
        waitResultLater['timedOut'] == false;
    checks['sleepFirstFollowWaitSucceeded'] =
        followWait['status'] == 'succeeded';
    observations['sleepFirst'] = {
      'waitAtReturn': waitResultAtReturn,
      'waitLater': waitResultLater,
      'firstWaitCallId': firstWaitCallId,
      'followWaitCallId': followWait['callId'],
      'sleepCallId': sleepCallId,
      'execCallId': execCallId,
      'sleepStatusLater': sleep['status'],
      'execStatusLater': exec['status'],
      'waitItemId': firstWaitItemId,
      'selectedTaskStatesAtReturn': {
        'sleep': sleepAtReturn,
        'exec': execAtReturn,
      },
    };
    await _expandHistoryWait(firstWaitItemId, 'sleep-first-history');
  }

  Future<void> _toolFirst() async {
    final context = await _submit(
      '$_markToolFirst wait until the short command wins',
      'tool_first',
    );
    final running = await _awaitNewTurn(context, 'tool_first');
    final turn = turnId(running)!;
    final waiting = await waitFor(
      (snapshot) {
        final wait = _toolByCallPrefix(snapshot, 'tool-first-wait-t');
        final sleep = _toolByCallPrefix(snapshot, 'tool-first-sleep-t');
        final exec = _toolByCallPrefix(snapshot, 'tool-first-exec-t');
        return wait != null &&
            !_terminalToolStatuses.contains(wait['status']) &&
            sleep != null &&
            !_terminalToolStatuses.contains(sleep['status']) &&
            exec != null;
      },
      'tool_first_waiting',
      timeout: const Duration(seconds: 20),
      abort: turnFailed,
    );
    final waitLive = _requireCallPrefix(waiting, 'tool-first-wait-t');
    final waitCallId = waitLive['callId'] as String;
    final waitItemId = waitLive['itemId'] as String;
    final execCallId =
        _requireCallPrefix(waiting, 'tool-first-exec-t')['callId'] as String;
    final sleepCallId =
        _requireCallPrefix(waiting, 'tool-first-sleep-t')['callId'] as String;
    await _observeWaitUi(waiting, 'tool-first-waiting', waitItemId);
    await capture('tool-first-waiting');
    checks['toolFirstWaitLive'] = true;
    checks['toolFirstSleepStillRunning'] = !_terminalToolStatuses.contains(
      _toolByCallPrefix(waiting, 'tool-first-sleep-t')?['status'],
    );
    final waitSucceeded = await waitFor(
      (snapshot) {
        final wait = _toolByCallId(snapshot, waitCallId);
        return wait != null && wait['status'] == 'succeeded';
      },
      'tool_first_wait_succeeded',
      timeout: const Duration(seconds: 20),
      abort: turnFailed,
    );
    final waitAtReturn = _toolByCallId(waitSucceeded, waitCallId)!;
    final waitResultAtReturn = _decodeWaitResult(
      waitAtReturn['result'] as String?,
    );
    final execAtReturn = _requireWaitTask(
      waitResultAtReturn,
      'task:$execCallId',
    );
    final sleepAtReturn = _requireWaitTask(
      waitResultAtReturn,
      'task:$sleepCallId',
    );
    checks['toolFirstWaitReadyWhileSleepRunning'] =
        waitResultAtReturn['timedOut'] == false &&
        execAtReturn['status'] == 'succeeded' &&
        sleepAtReturn['status'] == 'running' &&
        sleepAtReturn['cancelRequested'] == false;
    if (checks['toolFirstWaitReadyWhileSleepRunning'] != true) {
      throw StateError(
        'tool-first wait result at return did not show exec succeeded '
        'and sleep still running: $waitResultAtReturn',
      );
    }
    await capture('tool-first-wait-returned');
    observations['toolFirstReadyWindow'] = {
      'kind': 'waitResultAtReturn',
      'waitCallId': waitCallId,
      'waitResult': waitResultAtReturn,
      'selectedTaskStatesAtReturn': {
        'exec': execAtReturn,
        'sleep': sleepAtReturn,
      },
    };
    final settled = await _awaitSettled(turn, 'tool_first');
    await capture('tool-first-settled');
    final wait = _requireCallPrefix(settled, 'tool-first-wait-t');
    final exec = _requireCallPrefix(settled, 'tool-first-exec-t');
    final sleep = _requireCallPrefix(settled, 'tool-first-sleep-t');
    final waitResultLater = _decodeWaitResult(wait['result'] as String?);
    checks['toolFirstExecSucceeded'] = exec['status'] == 'succeeded';
    checks['toolFirstWaitReady'] =
        wait['status'] == 'succeeded' && waitResultLater['timedOut'] == false;
    observations['toolFirst'] = {
      'waitAtReturn': waitResultAtReturn,
      'waitLater': waitResultLater,
      'waitCallId': waitCallId,
      'execCallId': execCallId,
      'sleepCallId': sleepCallId,
      'execStatusLater': exec['status'],
      'sleepStatusLater': sleep['status'],
      'waitItemId': waitItemId,
      'selectedTaskStatesAtReturn': {
        'exec': execAtReturn,
        'sleep': sleepAtReturn,
      },
    };
    await _expandHistoryWait(waitItemId, 'tool-first-history');
  }

  Future<void> _childWake() async {
    final before = await snapshot();
    final rootThreadId = workspaceOf(before)?['threadId'] as String?;
    if (rootThreadId == null || rootThreadId.isEmpty) {
      throw StateError('root Thread id missing before child wait');
    }
    final context = await _submit(
      '$_markChild spawn a child and wait with a still-running timer',
      'child',
    );
    final running = await _awaitNewTurn(context, 'child');
    final turn = turnId(running)!;
    final waiting = await waitFor(
      (snapshot) {
        final wait = _toolByCallPrefix(snapshot, 'child-wait-t');
        final spawn = _toolByCallPrefix(snapshot, 'child-spawn-t');
        final sleep = _toolByCallPrefix(snapshot, 'child-parent-sleep-t');
        return wait != null &&
            !_terminalToolStatuses.contains(wait['status']) &&
            spawn != null &&
            sleep != null;
      },
      'child_waiting',
      timeout: const Duration(seconds: 40),
      abort: turnFailed,
    );
    final waitLive = _requireCallPrefix(waiting, 'child-wait-t');
    final waitCallId = waitLive['callId'] as String;
    final waitItemId = waitLive['itemId'] as String;
    final parentSleepCallId =
        _requireCallPrefix(waiting, 'child-parent-sleep-t')['callId'] as String;
    checks['childWaitLive'] = !_terminalToolStatuses.contains(
      waitLive['status'],
    );
    observations['childWaiting'] = {
      'kind': 'liveSnapshotAtObservation',
      'callId': waitCallId,
      'itemId': waitItemId,
      'status': waitLive['status'],
    };
    await capture('child-wait-observed', tree: true);
    final spawned = await waitFor(
      (snapshot) =>
          _agents(snapshot).any((agent) => agent['threadId'] != rootThreadId),
      'child_agent',
      timeout: const Duration(seconds: 60),
      abort: turnFailed,
    );
    final child = _agents(spawned).firstWhere(
      (agent) =>
          agent['threadId'] is String && agent['threadId'] != rootThreadId,
    );
    observations['childAgent'] = {
      'id': child['id'],
      'threadId': child['threadId'],
      'task': child['task'],
      'status': child['status'],
    };
    checks['childAgentCreated'] = child['id'] is String && child['id'] != '';
    final settled = await _awaitSettled(turn, 'child');
    await capture('child-settled');
    final wait = _toolByCallId(settled, waitCallId);
    if (wait == null) {
      throw StateError('child wait $waitCallId missing after settle');
    }
    final waitResultAtReturn = _decodeWaitResult(wait['result'] as String?);
    final parentSleepAtReturn = _requireWaitTask(
      waitResultAtReturn,
      'task:$parentSleepCallId',
    );
    checks['childWaitWokenByMessage'] =
        wait['status'] == 'succeeded' &&
        waitResultAtReturn['messagesReady'] == true &&
        waitResultAtReturn['timedOut'] == false &&
        parentSleepAtReturn['status'] == 'running' &&
        parentSleepAtReturn['cancelRequested'] == false;
    if (checks['childWaitWokenByMessage'] != true) {
      throw StateError(
        'child wait result at return did not show messagesReady with '
        'parent sleep still running: $waitResultAtReturn',
      );
    }
    checks['childSleepStillVisible'] =
        _toolByCallPrefix(settled, 'child-parent-sleep-t') != null;
    final confirm = await _submit(
      '$_markChildConfirm confirm the child report arrived once',
      'child_confirm',
    );
    final confirmRunning = await _awaitNewTurn(confirm, 'child_confirm');
    final confirmTurn = turnId(confirmRunning)!;
    final confirmSettled = await _awaitSettled(confirmTurn, 'child_confirm');
    await capture('child-confirm');
    checks['childConfirmTurnCompleted'] =
        turnId(confirmSettled) == confirmTurn &&
        isDurableSettled(confirmSettled);
    if (checks['childConfirmTurnCompleted'] != true) {
      throw StateError(
        'child confirm turn $confirmTurn did not durable-settle: '
        '${_summarize(confirmSettled)}',
      );
    }
    observations['childWait'] = {
      'kind': 'waitResultAtReturn',
      'waitCallId': waitCallId,
      'waitResult': waitResultAtReturn,
      'selectedTaskStatesAtReturn': {'parentSleep': parentSleepAtReturn},
      'confirmTurnId': confirmTurn,
      'reportMultiplicityVerifiedBy': 'fixture-model-request-boundary',
    };
    await _expandHistoryWait(waitItemId, 'child-history');
  }

  Future<void> _alreadyReady() async {
    final context = await _submit(
      '$_markAlreadyReady wait on the already completed timer',
      'already_ready',
    );
    final running = await _awaitNewTurn(context, 'already_ready');
    final turn = turnId(running)!;
    final settled = await _awaitSettled(turn, 'already_ready');
    await capture('already-ready');
    final wait = _requireCallPrefix(settled, 'already-ready-wait-t');
    final waitResult = _decodeWaitResult(wait['result'] as String?);
    checks['alreadyReadyImmediate'] =
        wait['status'] == 'succeeded' && waitResult['timedOut'] == false;
    observations['alreadyReady'] = {
      'wait': waitResult,
      'waitCallId': wait['callId'],
      'waitItemId': wait['itemId'],
    };
  }

  Future<void> _timeout() async {
    final context = await _submit(
      '$_markTimeout wait with a short timeout on a long timer',
      'timeout',
    );
    final running = await _awaitNewTurn(context, 'timeout');
    final turn = turnId(running)!;
    final waiting = await waitFor(
      (snapshot) {
        final wait = _toolByCallPrefix(snapshot, 'timeout-wait-t');
        final sleep = _toolByCallPrefix(snapshot, 'timeout-sleep-t');
        return wait != null &&
            !_terminalToolStatuses.contains(wait['status']) &&
            sleep != null;
      },
      'timeout_waiting',
      timeout: const Duration(seconds: 15),
      abort: turnFailed,
    );
    final waitLive = _requireCallPrefix(waiting, 'timeout-wait-t');
    final waitCallId = waitLive['callId'] as String;
    final waitItemId = waitLive['itemId'] as String;
    final sleepCallId =
        _requireCallPrefix(waiting, 'timeout-sleep-t')['callId'] as String;
    checks['timeoutWaitLive'] = !_terminalToolStatuses.contains(
      waitLive['status'],
    );
    observations['timeoutWaiting'] = {
      'kind': 'liveSnapshotAtObservation',
      'callId': waitCallId,
      'itemId': waitItemId,
      'status': waitLive['status'],
    };
    await capture('timeout-wait-observed');
    final settled = await _awaitSettled(turn, 'timeout');
    await capture('timeout-settled');
    final wait = _toolByCallId(settled, waitCallId);
    if (wait == null) {
      throw StateError('timeout wait $waitCallId missing after settle');
    }
    final waitResultAtReturn = _decodeWaitResult(wait['result'] as String?);
    if (wait['status'] != 'succeeded' ||
        waitResultAtReturn['timedOut'] != true) {
      throw StateError(
        'timeout wait did not succeed with timedOut=true: '
        'status=${wait['status']} result=$waitResultAtReturn',
      );
    }
    final sleepAtReturn = _requireWaitTask(
      waitResultAtReturn,
      'task:$sleepCallId',
    );
    checks['timeoutIsNotFailure'] =
        wait['status'] == 'succeeded' &&
        waitResultAtReturn['timedOut'] == true &&
        waitResultAtReturn['messagesReady'] == false &&
        sleepAtReturn['status'] == 'running' &&
        sleepAtReturn['cancelRequested'] == false;
    if (checks['timeoutIsNotFailure'] != true) {
      throw StateError(
        'timeout wait result at return did not keep sleep running: '
        '$waitResultAtReturn',
      );
    }
    observations['timeout'] = {
      'kind': 'waitResultAtReturn',
      'waitResult': waitResultAtReturn,
      'waitCallId': waitCallId,
      'sleepCallId': sleepCallId,
      'waitItemId': waitItemId,
      'selectedTaskStatesAtReturn': {'sleep': sleepAtReturn},
    };
    await _expandHistoryWait(waitItemId, 'timeout-history');
  }

  Future<void> _cancelWait() async {
    final prepare = await _submit(
      '$_markCancelPrepare start a long background timer and finish this Turn',
      'cancel_prepare',
    );
    final prepareRunning = await _awaitNewTurn(prepare, 'cancel_prepare');
    final prepareTurn = turnId(prepareRunning)!;
    final prepareSleep = await waitFor(
      (snapshot) {
        final sleep = _toolByCallPrefix(snapshot, 'cancel-sleep-t');
        return turnId(snapshot) == prepareTurn &&
            sleep != null &&
            _liveToolStatuses.contains(sleep['status']);
      },
      'cancel_prepare_sleep_running',
      timeout: const Duration(seconds: 20),
      abort: turnFailed,
    );
    final sleepCallId = _toolByCallPrefix(
      prepareSleep,
      'cancel-sleep-t',
    )?['callId'];
    if (sleepCallId is! String || sleepCallId.isEmpty) {
      throw StateError('cancel prepare did not expose a cancel-sleep callId');
    }
    final prepareDone = await _awaitTurnCompleted(
      prepareTurn,
      'cancel_prepare',
    );
    await capture('cancel-prepare');
    checks['cancelPrepareTurnCompleted'] =
        turnStatus(prepareDone) == 'completed';
    checks['cancelPrepareSleepStillRunning'] = _liveToolStatuses.contains(
      _toolByCallId(prepareDone, sleepCallId)?['status'],
    );

    final observe = await _submit(
      '$_markCancel wait only the previous Turn timer so stop cancels wait',
      'cancel_observe',
    );
    final observeRunning = await _awaitNewTurn(observe, 'cancel_observe');
    final observeTurn = turnId(observeRunning)!;
    checks['cancelObserveDistinctTurn'] = observeTurn != prepareTurn;
    final waiting = await waitFor(
      (snapshot) {
        final wait = _toolByCallPrefix(snapshot, 'cancel-wait-t');
        return turnId(snapshot) == observeTurn &&
            wait != null &&
            !_terminalToolStatuses.contains(wait['status']);
      },
      'cancel_waiting',
      timeout: const Duration(seconds: 20),
      abort: turnFailed,
    );
    final waitLive = _requireCallPrefix(waiting, 'cancel-wait-t');
    final waitItemId = waitLive['itemId'] as String;
    await _observeWaitUi(waiting, 'cancel-waiting', waitItemId);
    await capture('cancel-waiting');
    checks['cancelWaitLive'] = true;
    await driver.waitFor(
      find.byValueKey('composer-stop'),
      timeout: const Duration(seconds: 15),
    );
    await _tap('composer-stop');
    final cancelled = await waitFor(
      (snapshot) =>
          turnId(snapshot) == observeTurn &&
          turnStatus(snapshot) == 'cancelled',
      'cancel_cancelled',
      timeout: const Duration(seconds: 30),
    );
    await capture('cancel-cancelled');
    checks['cancelWaitObservation'] = turnStatus(cancelled) == 'cancelled';
    checks['cancelObserveDidNotReusePrepareTurn'] =
        turnId(cancelled) == observeTurn && observeTurn != prepareTurn;

    final query = await _submit(
      '$_markCancelQuery query then cancel the leftover timer from Turn A',
      'cancel_query',
    );
    final queryRunning = await _awaitNewTurn(query, 'cancel_query');
    final queryTurn = turnId(queryRunning)!;
    checks['cancelQueryDistinctTurn'] =
        queryTurn != prepareTurn && queryTurn != observeTurn;
    final queried = await waitFor(
      (snapshot) {
        final queryTool = _toolByCallPrefix(snapshot, 'cancel-query-t');
        return turnId(snapshot) == queryTurn &&
            queryTool != null &&
            queryTool['status'] == 'succeeded';
      },
      'cancel_query_succeeded',
      timeout: const Duration(seconds: 30),
      abort: turnFailed,
    );
    final queryTool = _requireCallPrefix(queried, 'cancel-query-t');
    final queryTask = _decodeTaskQuery(queryTool['result'] as String?);
    final expectedTaskId = 'task:$sleepCallId';
    checks['cancelTargetQuerySucceeded'] = queryTool['status'] == 'succeeded';
    checks['cancelTargetTaskId'] = queryTask['taskId'] == expectedTaskId;
    checks['cancelTargetStillRunning'] = queryTask['status'] == 'running';
    checks['cancelTargetNotCancelRequested'] =
        queryTask['cancelRequested'] == false;
    checks['cancelTargetStillObservable'] =
        checks['cancelTargetQuerySucceeded'] == true &&
        checks['cancelTargetTaskId'] == true &&
        checks['cancelTargetStillRunning'] == true &&
        checks['cancelTargetNotCancelRequested'] == true;
    final settled = await _awaitTurnCompleted(queryTurn, 'cancel_query');
    await capture('cancel-query');
    final cancelTool = _requireCallPrefix(settled, 'cancel-query-cancel-t');
    checks['cancelTargetCancelledAfterQuery'] =
        cancelTool['status'] == 'succeeded';
    observations['cancelQuery'] = {
      'prepareTurnId': prepareTurn,
      'observeTurnId': observeTurn,
      'queryTurnId': queryTurn,
      'sleepCallId': sleepCallId,
      'expectedTaskId': expectedTaskId,
      'queryStatus': queryTool['status'],
      'queryTask': queryTask,
      'cancelStatus': cancelTool['status'],
    };
  }

  Future<void> _layoutContracts() async {
    final pidRaw = await driver.requestData(
      'pid',
      timeout: const Duration(seconds: 15),
    );
    final decoded = jsonDecode(pidRaw);
    final pid = decoded is Map ? decoded['pid'] : null;
    if (pid is! int || pid <= 0) {
      pendingEvidence.add(
        'narrow window: driver pid was unavailable, so the wait-card layout '
        'was not resized',
      );
      return;
    }
    final narrow = resizeOwnedWindow(
      guiPid: pid,
      width: _narrowWindowWidth,
      height: _narrowWindowHeight,
    );
    if (!narrow.resized) {
      pendingEvidence.add(
        'narrow window: ${narrow.reason}; wait-card wrap evidence is pending',
      );
      return;
    }
    try {
      await capture('narrow');
      checks['narrowWindowCaptured'] = true;
    } finally {
      final restored = resizeOwnedWindow(
        guiPid: pid,
        width: narrow.original!.width,
        height: narrow.original!.height,
      );
      if (!restored.resized) {
        throw StateError('could not restore GUI window: ${restored.reason}');
      }
    }
  }

  Future<void> _observeWaitUi(
    Map<String, dynamic> waiting,
    String label,
    String itemId,
  ) async {
    observations['${label}IncomingActivity'] = conversationActivity(waiting);
    await driver.waitFor(
      find.byValueKey('conversation-activity'),
      timeout: const Duration(seconds: 10),
    );
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    final activityFinder = find.byValueKey('conversation-activity');
    final detailsFinder = find.byValueKey('conversation-activity-details');
    final titleFinder = find.descendant(
      of: activityFinder,
      matching: find.byType('Text'),
      firstMatchOnly: true,
    );
    String? trackingIdentity;
    var tappedThisIdentity = false;
    Map<String, dynamic>? last;
    while (DateTime.now().isBefore(deadline)) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) break;
      final current = await snapshot();
      last = current;
      if (turnFailed(current)) {
        throw StateError(
          '${label}_activity_live_wait aborted: ${_summarize(current)}',
        );
      }
      _requireLiveWait(current, itemId, label);
      final view = conversationActivity(current);
      if (view == null || view['expandable'] != true) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        continue;
      }
      checks['${label}ActivityExpandable'] = true;
      final String title;
      try {
        await driver.waitFor(titleFinder, timeout: remaining);
        title = await driver.getText(titleFinder);
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        continue;
      }
      if (!_waitActivityTitles.contains(title)) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        continue;
      }
      final afterTitle = await snapshot();
      last = afterTitle;
      if (turnFailed(afterTitle)) {
        throw StateError(
          '${label}_activity_live_wait aborted: ${_summarize(afterTitle)}',
        );
      }
      _requireLiveWait(afterTitle, itemId, label);
      final fresh = conversationActivity(afterTitle);
      final identity = fresh?['identity'];
      if (fresh == null ||
          fresh['expandable'] != true ||
          identity is! String ||
          identity.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        continue;
      }
      if (trackingIdentity != identity) {
        trackingIdentity = identity;
        tappedThisIdentity = false;
      }
      if (fresh['expanded'] != true) {
        if (!tappedThisIdentity) {
          await _tap('conversation-activity');
          tappedThisIdentity = true;
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
        continue;
      }
      try {
        await driver.waitFor(detailsFinder, timeout: remaining);
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        continue;
      }
      final beforeCapture = await snapshot();
      last = beforeCapture;
      _requireLiveWait(beforeCapture, itemId, label);
      final beforeView = conversationActivity(beforeCapture);
      if (beforeView?['identity'] != identity ||
          beforeView?['expanded'] != true) {
        trackingIdentity = beforeView?['identity'] as String?;
        tappedThisIdentity = beforeView?['expanded'] == true;
        await Future<void>.delayed(const Duration(milliseconds: 150));
        continue;
      }
      observations['${label}Activity'] = beforeView;
      observations['${label}ActivityTitle'] = title;
      await capture('$label-activity-expanded');
      final afterCapture = await snapshot();
      last = afterCapture;
      final capturedActivity = conversationActivity(afterCapture);
      final waitStill = _toolByItemId(afterCapture, itemId);
      final capturedLive =
          waitStill != null &&
          !_terminalToolStatuses.contains(waitStill['status']);
      final capturedOk =
          capturedActivity?['identity'] == identity &&
          capturedActivity?['expanded'] == true &&
          capturedLive;
      checks['${label}ActivityExpanded'] = capturedOk;
      if (!capturedOk) {
        if (!capturedLive) {
          throw StateError(
            'wait $itemId was no longer waiting after $label capture: $waitStill',
          );
        }
        trackingIdentity = capturedActivity?['identity'] as String?;
        tappedThisIdentity = capturedActivity?['expanded'] == true;
        await Future<void>.delayed(const Duration(milliseconds: 150));
        continue;
      }
      if (capturedActivity?['identity'] == identity &&
          capturedActivity?['expanded'] == true) {
        await _tap('conversation-activity');
      }
      checks['${label}WaitItemId'] = true;
      await _tryTapWaitCard(itemId, label);
      return;
    }
    if (checks['${label}ActivityExpandable'] != true) {
      checks['${label}ActivityExpandable'] = false;
    }
    throw StateError(
      '$label timed out waiting for live wait activity: '
      '${_summarize(last ?? const <String, dynamic>{})}',
    );
  }

  void _requireLiveWait(
    Map<String, dynamic> snapshot,
    String itemId,
    String label,
  ) {
    final waitStill = _toolByItemId(snapshot, itemId);
    if (waitStill == null ||
        _terminalToolStatuses.contains(waitStill['status'])) {
      throw StateError(
        'wait $itemId was no longer waiting during $label: $waitStill',
      );
    }
  }

  Future<void> _expandHistoryWait(String? itemId, String label) async {
    if (itemId == null || itemId.isEmpty) {
      checks['${label}WaitItemId'] = false;
      throw StateError('history wait card missing itemId for $label');
    }
    checks['${label}WaitItemId'] = true;
    await _tryTapWaitCard(itemId, label);
    await capture(label);
  }

  /// Wait cards keep the original tool item identity. Ordinary tools may hide
  /// inside a presentation group; expand that group before locating wait-card.
  Future<void> _revealWaitItem(String itemId, String label) async {
    final timeline = TimelineObservation.parse(await snapshot());
    timeline.requireConsistentIds();
    final group = timeline.presentationFor(itemId);
    observations['${label}Presentation'] = <String, Object?>{
      'id': group.id,
      'kind': group.kind,
      'expanded': group.expanded,
      'memberIds': group.memberIds,
    };
    _requireWaitJoinedWithAdjacentTools(timeline, itemId, label, group);
    if (group.kind == 'activity') {
      if (group.expanded) {
        await _collapseActivityGroup(group.id, itemId, label);
      }
      await _captureCollapsedActivityIfNeeded(label);
      final summary = 'timeline-activity-summary-${group.id}';
      final summaryFinder = find.byValueKey(summary);
      await driver.waitFor(summaryFinder, timeout: const Duration(seconds: 10));
      final summaryHeader = _headerOf(summaryFinder);
      await _scrollHeaderIntoView(summaryHeader);
      await driver.rawTap(summaryHeader);
      await waitFor(
        (snapshot) {
          final current = TimelineObservation.optional(snapshot);
          if (current == null) return false;
          return current.presentationFor(itemId).expanded;
        },
        '${label}_presentation_expanded',
        timeout: const Duration(seconds: 10),
      );
      await _captureExpandedActivityIfNeeded(label);
    }
    checks['${label}PresentationLocated'] = true;
  }

  void _requireWaitJoinedWithAdjacentTools(
    TimelineObservation timeline,
    String itemId,
    String label,
    TimelinePresentationObservation group,
  ) {
    if (group.kind != 'activity') {
      throw StateError(
        '$label wait $itemId is presented as ${group.kind} instead of an activity group: ${group.memberIds}',
      );
    }
    if (!group.memberIds.contains(itemId)) {
      throw StateError(
        '$label activity ${group.id} lost wait identity $itemId: ${group.memberIds}',
      );
    }
    final wait = timeline.item(itemId);
    if (wait == null) {
      throw StateError('$label wait $itemId is missing from canonical items');
    }
    final expected = _expectedVisibleActivityRun(timeline, wait);
    if (!expected.contains(itemId)) {
      throw StateError(
        '$label visible activity run for $itemId is empty or lost the wait: $expected',
      );
    }
    final missing = [
      for (final id in expected)
        if (!group.memberIds.contains(id)) id,
    ];
    if (missing.isNotEmpty) {
      throw StateError(
        '$label activity ${group.id} is missing visible same-turn neighbors $missing; expected $expected actual ${group.memberIds}',
      );
    }
    final extras = [
      for (final id in group.memberIds)
        if (!expected.contains(id)) id,
    ];
    if (extras.isNotEmpty) {
      throw StateError(
        '$label activity ${group.id} joined unexpected members $extras; expected $expected actual ${group.memberIds}',
      );
    }
    checks['${label}WaitJoinedAdjacentTools'] = true;
    observations['${label}VisibleActivityRun'] = expected;
    observations['${label}AdjacentJoinableNeighbors'] = [
      for (final id in expected)
        if (id != itemId) id,
    ];
  }

  /// Canonical `itemIds` include hidden inference/file/healthy-turn rows.
  /// Visible same-turn activity neighbors skip those bookkeeping items and
  /// stop at body, userInput/plan, image groups, failed turns, or another turn.
  List<String> _expectedVisibleActivityRun(
    TimelineObservation timeline,
    TimelineItemObservation wait,
  ) {
    final waitIndex = timeline.itemIds.indexOf(wait.id);
    if (waitIndex < 0) {
      throw StateError('wait ${wait.id} is missing from canonical itemIds');
    }
    final before = <String>[];
    for (var index = waitIndex - 1; index >= 0; index--) {
      final item = timeline.item(timeline.itemIds[index]);
      if (item == null) {
        throw StateError(
          'canonical item ${timeline.itemIds[index]} is missing from items',
        );
      }
      if (!_timelineItemIsVisible(item)) continue;
      if (!_isSameTurnActivityNeighbor(item)) break;
      before.add(item.id);
    }
    final after = <String>[];
    for (var index = waitIndex + 1; index < timeline.itemIds.length; index++) {
      final item = timeline.item(timeline.itemIds[index]);
      if (item == null) {
        throw StateError(
          'canonical item ${timeline.itemIds[index]} is missing from items',
        );
      }
      if (!_timelineItemIsVisible(item)) continue;
      if (!_isSameTurnActivityNeighbor(item)) break;
      after.add(item.id);
    }
    return [...before.reversed, wait.id, ...after];
  }

  bool _timelineItemIsVisible(TimelineItemObservation item) {
    return switch (item.kind) {
      'inference' || 'file' => false,
      'turn' => item.terminal && item.text.trim().isNotEmpty,
      _ => true,
    };
  }

  bool _isSameTurnActivityNeighbor(TimelineItemObservation item) {
    if (item.kind == 'userMessage' ||
        item.kind == 'parentAgentMessage' ||
        item.kind == 'agentMessage' ||
        item.kind == 'raw' ||
        item.kind == 'turn') {
      return false;
    }
    if (item.userInput != null) return false;
    if (_isImageActivity(item)) return false;
    if (item.kind == 'reasoning') return true;
    if (item.kind == 'toolCall' && item.tool != null) return true;
    return false;
  }

  bool _isImageActivity(TimelineItemObservation item) {
    if (item.kind != 'toolCall') return false;
    if (item.tool?.name == 'view_image') return true;
    return item.tool?.attachments.any(
          (attachment) => attachment.modality == 'image',
        ) ??
        false;
  }

  Future<void> _captureCollapsedActivityIfNeeded(String label) async {
    if (checks['activityGroupCollapsedCaptured'] == true) return;
    await capture('activity-group-collapsed');
    checks['activityGroupCollapsedCaptured'] = true;
    observations['activityGroupCollapsedFrom'] = label;
  }

  Future<void> _captureExpandedActivityIfNeeded(String label) async {
    if (checks['activityGroupExpandedCaptured'] == true) return;
    await capture('activity-group-expanded');
    checks['activityGroupExpandedCaptured'] = true;
    observations['activityGroupExpandedFrom'] = label;
  }

  Future<void> _collapseActivityGroup(
    String groupId,
    String itemId,
    String label,
  ) async {
    final summary = 'timeline-activity-summary-$groupId';
    final summaryFinder = find.byValueKey(summary);
    await driver.waitFor(summaryFinder, timeout: const Duration(seconds: 10));
    final summaryHeader = _headerOf(summaryFinder);
    await _scrollHeaderIntoView(summaryHeader);
    await driver.rawTap(summaryHeader);
    await waitFor(
      (snapshot) {
        final current = TimelineObservation.optional(snapshot);
        if (current == null) return false;
        return !current.presentationFor(itemId).expanded;
      },
      '${label}_presentation_collapsed_for_screenshot',
      timeout: const Duration(seconds: 10),
    );
  }

  /// ListTile ancestor of a summary text key such as
  /// `timeline-activity-summary-<id>`. Wait-card panels already contain their
  /// ListTile, so their header is a descendant of the ExpansionTile.
  SerializableFinder _headerOf(SerializableFinder child) => find.ancestor(
    of: child,
    matching: find.byType('ListTile'),
    firstMatchOnly: true,
  );

  Future<void> _scrollHeaderIntoView(SerializableFinder header) async {
    await driver.scrollUntilVisible(
      find.byValueKey('timeline-scrollable'),
      header,
      dyScroll: -80,
      timeout: const Duration(seconds: 15),
    );
    await _scrollNestedUntilVisible(header);
    final top = await driver.getTopLeft(header);
    final bottom = await driver.getBottomRight(header);
    if (bottom.dy - top.dy <= 0) {
      throw StateError('header geometry is empty after scrolling: $header');
    }
  }

  /// Group contents use a nested 320px scrollable. Outer timeline scrolling
  /// cannot reveal a wait card that remains clipped inside the group.
  Future<void> _scrollNestedUntilVisible(SerializableFinder item) async {
    final nested = find.ancestor(
      of: item,
      matching: find.byType('Scrollable'),
      firstMatchOnly: true,
    );
    // Groups with <=5 members keep a nested 320px scrollable. Larger lazy
    // lists are out of this fixture; missing ancestor is a layout precondition,
    // not a retry/fallback.
    try {
      await driver.waitFor(nested, timeout: const Duration(seconds: 2));
    } on DriverError catch (error) {
      if (_isMissingFinder(error)) return;
      throw StateError('nested group Scrollable lookup failed: $error');
    } catch (error) {
      throw StateError('nested group Scrollable lookup failed: $error');
    }
    await driver.scrollUntilVisible(
      nested,
      item,
      dyScroll: -80,
      timeout: const Duration(seconds: 15),
    );
  }

  bool _isMissingFinder(DriverError error) {
    final message = error.message.toLowerCase();
    return message.contains('timeout') ||
        message.contains('not found') ||
        message.contains('no matching');
  }

  Future<void> _tryTapWaitCard(String itemId, String label) async {
    final card = 'wait-card:$itemId';
    final details = 'wait-details:$itemId';
    final diagnostics = 'wait-diagnostics:$itemId';
    await _revealWaitItem(itemId, label);
    final cardFinder = find.byValueKey(card);
    try {
      await driver.waitFor(cardFinder, timeout: const Duration(seconds: 10));
      checks['${label}WaitCardPresent'] = true;
    } catch (error) {
      checks['${label}WaitCardPresent'] = false;
      throw StateError('required $card missing during $label: $error');
    }
    final tileFinder = find.descendant(
      of: cardFinder,
      matching: find.byType('ExpansionTile'),
      firstMatchOnly: true,
    );
    await driver.waitFor(tileFinder, timeout: const Duration(seconds: 10));
    final cardHeader = find.descendant(
      of: tileFinder,
      matching: find.byType('ListTile'),
      firstMatchOnly: true,
    );
    await _expandTileIfCollapsed(
      tile: tileFinder,
      header: cardHeader,
      label: '${label}_wait_card',
    );
    final detailsFinder = find.byValueKey(details);
    try {
      await driver.waitFor(detailsFinder, timeout: const Duration(seconds: 10));
      await _scrollHeaderIntoView(detailsFinder);
      await _requireInTimelineViewport(detailsFinder, details);
      checks['${label}WaitDetailsPresent'] = true;
    } catch (error) {
      checks['${label}WaitDetailsPresent'] = false;
      throw StateError('required $details missing during $label: $error');
    }
    final diagnosticsFinder = find.byValueKey(diagnostics);
    try {
      await driver.waitFor(
        diagnosticsFinder,
        timeout: const Duration(seconds: 10),
      );
      checks['${label}WaitDiagnosticsPresent'] = true;
    } catch (error) {
      checks['${label}WaitDiagnosticsPresent'] = false;
      throw StateError('required $diagnostics missing during $label: $error');
    }
    final diagnosticsHeader = find.descendant(
      of: diagnosticsFinder,
      matching: find.byType('ListTile'),
      firstMatchOnly: true,
    );
    await _expandTileIfCollapsed(
      tile: diagnosticsFinder,
      header: diagnosticsHeader,
      label: '${label}_wait_diagnostics',
    );
    observations['${label}WaitKey'] = card;
  }

  /// Public ExpansionTile controller via existing ToolProbe `observe`.
  /// `geometry` is not a ToolProbe action in this tree.
  Future<bool> _tileExpanded(SerializableFinder tile, String label) async {
    final result = await probe.sendCommand(ToolProbe(tile, 'observe'));
    final samples = result['samples'];
    if (samples is! List || samples.isEmpty) {
      throw StateError('ToolProbe observe returned no samples during $label');
    }
    final sample = samples.last;
    if (sample is! Map) {
      throw StateError('ToolProbe observe sample is not a map during $label');
    }
    final expanded = sample['expanded'];
    if (expanded is! bool) {
      throw StateError(
        'ToolProbe expanded missing or not bool during $label: $expanded',
      );
    }
    return expanded;
  }

  Future<void> _awaitTileExpanded(SerializableFinder tile, String label) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    bool? last;
    while (DateTime.now().isBefore(deadline)) {
      last = await _tileExpanded(tile, label);
      if (last) return;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    throw StateError(
      '$label ExpansionTile did not report expanded=true (last=$last)',
    );
  }

  Future<void> _expandTileIfCollapsed({
    required SerializableFinder tile,
    required SerializableFinder header,
    required String label,
  }) async {
    await _scrollHeaderIntoView(header);
    final expanded = await _tileExpanded(tile, label);
    if (!expanded) {
      await driver.rawTap(header);
    }
    await _awaitTileExpanded(tile, label);
  }

  Future<void> _requireInTimelineViewport(
    SerializableFinder finder,
    String label,
  ) async {
    final top = await driver.getTopLeft(finder);
    final bottom = await driver.getBottomRight(finder);
    if (bottom.dy - top.dy <= 0 || bottom.dx - top.dx <= 0) {
      throw StateError('$label geometry is empty');
    }
    final viewport = find.byValueKey('timeline-scrollable');
    final viewportTop = await driver.getTopLeft(viewport);
    final viewportBottom = await driver.getBottomRight(viewport);
    final overlapTop = top.dy > viewportTop.dy ? top.dy : viewportTop.dy;
    final overlapBottom = bottom.dy < viewportBottom.dy
        ? bottom.dy
        : viewportBottom.dy;
    if (overlapBottom - overlapTop <= 0) {
      throw StateError('$label is outside the timeline viewport');
    }
  }

  Map<String, dynamic>? _toolByItemId(
    Map<String, dynamic> snapshot,
    String itemId,
  ) {
    for (final row in timelineRows(snapshot)) {
      final tools = row['tools'];
      if (tools is! List) continue;
      for (final tool in tools) {
        if (tool is Map && tool['itemId'] == itemId) {
          return tool.cast<String, dynamic>();
        }
      }
    }
    return null;
  }

  Map<String, dynamic>? _toolByCallId(
    Map<String, dynamic> snapshot,
    String callId,
  ) {
    for (final row in timelineRows(snapshot)) {
      final tools = row['tools'];
      if (tools is! List) continue;
      for (final tool in tools) {
        if (tool is Map && tool['callId'] == callId) {
          return tool.cast<String, dynamic>();
        }
      }
    }
    return null;
  }

  /// Fixture call ids are `{slug}-t{generation}-call`. Each business stage owns
  /// a unique slug; generation stays 0 for these one-shot parent Turns.
  Map<String, dynamic>? _toolByCallPrefix(
    Map<String, dynamic> snapshot,
    String prefix,
  ) {
    for (final row in timelineRows(snapshot)) {
      final tools = row['tools'];
      if (tools is! List) continue;
      for (final tool in tools) {
        if (tool is Map &&
            tool['callId'] is String &&
            (tool['callId'] as String).startsWith(prefix)) {
          return tool.cast<String, dynamic>();
        }
      }
    }
    return null;
  }

  Map<String, dynamic> _requireCallPrefix(
    Map<String, dynamic> snapshot,
    String prefix,
  ) {
    final tool = _toolByCallPrefix(snapshot, prefix);
    if (tool == null) {
      throw StateError(
        'missing tool callId prefix $prefix in ${_summarize(snapshot)}',
      );
    }
    return tool;
  }

  /// Official lightweight WaitTasksView task lookup. Only `taskId` is canonical.
  Map<String, Object?> _requireWaitTask(
    Map<String, Object?> waitResult,
    String taskId,
  ) {
    final tasks = waitResult['tasks'];
    if (tasks is! List) {
      throw StateError(
        'wait result tasks missing or not a List for $taskId: $waitResult',
      );
    }
    for (final task in tasks) {
      if (task is Map && task['taskId'] == taskId) {
        return task.map((key, value) => MapEntry(key.toString(), value));
      }
    }
    throw StateError('wait result missing exact taskId $taskId: $waitResult');
  }

  Map<String, Object?> _decodeWaitResult(String? result) {
    if (result == null || result.isEmpty) {
      return const <String, Object?>{};
    }
    try {
      final decoded = jsonDecode(result);
      if (decoded is Map) return decoded.cast<String, Object?>();
    } on FormatException {
      final start = result.indexOf('{');
      if (start >= 0) {
        try {
          final decoded = jsonDecode(result.substring(start));
          if (decoded is Map) return decoded.cast<String, Object?>();
        } on FormatException {
          return <String, Object?>{'raw': result};
        }
      }
    }
    return <String, Object?>{'raw': result};
  }

  Map<String, Object?> _decodeTaskQuery(String? result) {
    final decoded = _decodeWaitResult(result);
    final task = decoded['task'];
    if (task is Map) {
      return task.map((key, value) => MapEntry(key.toString(), value));
    }
    return decoded;
  }

  List<Map<String, dynamic>> _agents(Map<String, dynamic> snapshot) {
    final agents = workspaceOf(snapshot)?['agents'];
    if (agents is! List) return const [];
    return [
      for (final agent in agents)
        if (agent is Map) agent.cast<String, dynamic>(),
    ];
  }

  Map<String, Object?> _summarize(Map<String, dynamic> snapshot) {
    final tools = <Map<String, Object?>>[];
    for (final row in timelineRows(snapshot)) {
      final rowTools = row['tools'];
      if (rowTools is! List) continue;
      for (final tool in rowTools) {
        if (tool is! Map) continue;
        tools.add(<String, Object?>{
          'name': tool['name'],
          'status': tool['status'],
          'callId': tool['callId'],
          'itemId': tool['itemId'],
        });
      }
    }
    return <String, Object?>{
      'turnId': turnId(snapshot),
      'turnStatus': turnStatus(snapshot),
      'isBusy': isBusy(snapshot),
      'activity': conversationActivity(snapshot)?['summary'],
      'tools': tools,
      'itemCount': TimelineObservation.optional(snapshot)?.itemCount,
    };
  }

  Future<void> writeSummary({
    required Object? failure,
    required Object? shutdownFailure,
  }) async {
    final failedChecks = checks.entries
        .where((entry) => entry.value != true)
        .map((entry) => entry.key)
        .toList(growable: false);
    final summary = <String, Object?>{
      'scenario': 'wait-events',
      'verdict': 'pending',
      'status': failure != null || failedChecks.isNotEmpty
          ? 'failed'
          : 'complete',
      'stage': stage,
      'error': failure?.toString(),
      'shutdownError': shutdownFailure?.toString() ?? shutdownError,
      'failedChecks': failedChecks,
      'checks': checks,
      'captures': captures,
      'observations': observations,
      'pendingEvidence': pendingEvidence,
      'completedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await File(
      '${output.path}/wait-events-summary.json',
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(summary)}\n');
  }

  Future<void> raiseIfFailed(Object? shutdownFailure) async {
    final failedChecks = checks.entries
        .where((entry) => entry.value != true)
        .map((entry) => entry.key)
        .toList(growable: false);
    if (failedChecks.isNotEmpty) {
      throw StateError('wait-events checks failed: ${failedChecks.join(', ')}');
    }
    if (shutdownFailure != null) {
      throw StateError('native GUI shutdown failed: $shutdownFailure');
    }
  }
}

class SubmitContext {
  const SubmitContext({required this.priorTurnId, required this.submittedAt});

  final String? priorTurnId;
  final int submittedAt;
}
