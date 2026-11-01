// Manual native-GUI wait/sleep/child observation journey, not a Flutter test gate.
//
// It drives the isolated GUI through Flutter Driver against the wait-events
// fixture: real `sleep` / `exec` / `wait` / `spawn_agent` tools, screenshots of
// live current tools JSON and completed history, with separate qualifications.
// Live controls use the production currentCollection/Entry factories; completed
// item controls below require their own actual Children Message identity.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'flutter_driver_session.dart';
import 'current_tools_observation.dart';
import 'current_tools_driver.dart';
import 'tool_probe.dart';
import 'realtime_journey.dart'
    show
        isBusy,
        isDurableSettled,
        timelineRows,
        turnFailed,
        turnId,
        turnStatus,
        workspaceOf;
import 'timeline_observation.dart';
import 'timeline_scope_driver.dart';
import 'pointer_scroll.dart';
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

const _narrowWindowWidth = 640;
const _narrowWindowHeight = 600;

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
    } catch (_) {}
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
  try {
    final result = jsonDecode(
      await driver
          .requestData('shutdown', timeout: const Duration(seconds: 60))
          .timeout(const Duration(seconds: 65)),
    );
    if (result is! Map || result['shutdown'] != 'completed') {
      throw StateError('native GUI shutdown did not report completion');
    }
  } finally {
    try {
      await driver.close().timeout(const Duration(seconds: 5));
    } catch (_) {}
  }
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
  } catch (_) {}
}

final class _WaitChildrenScope {
  _WaitChildrenScope(CurrentToolsObservation current, this.generation)
    : threadId = current.threadId,
      mainGeneration = current.mainGeneration,
      turnId = current.turnId!,
      parentId = current.requireChildrenParentId(),
      activityId = current.activityId;
  final String threadId, turnId, parentId;
  final String? activityId;
  final int generation, mainGeneration;
  Object get owner => (threadId, mainGeneration, turnId, parentId, activityId);

  Map<String, Object?> evidence() => {
    'threadId': threadId,
    'mainGeneration': mainGeneration,
    'turnId': turnId,
    'childrenParentId': parentId,
    'activityId': activityId,
  };

  void requireMain(
    TimelineObservation timeline, {
    bool originalGeneration = true,
  }) {
    if (timeline.threadId != threadId ||
        (originalGeneration && timeline.generation != mainGeneration)) {
      throw StaleCurrentTools('Original completed-member Main lease retired');
    }
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
  late final CurrentToolsDriver _currentTools = CurrentToolsDriver.session(
    driver,
  );
  final Map<String, Map<String, Object?>> _liveWaitEvidence = {};
  final Map<String, _WaitChildrenScope> _childrenByTurn = {};
  final Map<String, String> _completedItemParents = {};

  Duration _remaining(Stopwatch clock, Duration budget) {
    final left = budget - clock.elapsed;
    if (left <= Duration.zero) {
      throw StateError('Original observation deadline expired');
    }
    return left;
  }

  TimelineChildrenObservation _qualifiedChildren(
    Map<String, dynamic> snapshot,
    _WaitChildrenScope scope, {
    bool running = false,
  }) {
    final timeline = TimelineObservation.parse(snapshot);
    scope.requireMain(timeline, originalGeneration: running);
    if (running) {
      final current = CurrentToolsObservation.optional(snapshot);
      if (turnId(snapshot) != scope.turnId ||
          turnStatus(snapshot) != 'running' ||
          current == null ||
          !current.expanded ||
          current.owner != scope.owner) {
        throw StaleCurrentTools(
          'Original Running Turn/current parent retired before its result',
        );
      }
    }
    final child = timeline.childrenFor(scope.parentId);
    if (child?.error != null) {
      throw StateError('Original Children read failed: ${child!.error}');
    }
    if (child == null || !child.ready || child.appliedSets < 1) {
      throw StaleCurrentTools('Original completed-member display is absent');
    }
    if (running && child.generation != scope.generation) {
      throw StaleCurrentTools('Original Children display generation retired');
    }
    return child;
  }

  Future<_WaitChildrenScope> _openCurrentChildren(
    String turn, {
    required Duration timeout,
  }) async {
    final clock = Stopwatch()..start();
    final before = await snapshot();
    if (turnId(before) != turn || turnStatus(before) != 'running') {
      throw StaleCurrentTools('No original Running Turn for completed members');
    }
    final original = CurrentToolsObservation.optional(before);
    if (original == null || original.turnId != turn) {
      throw StaleCurrentTools('Original current head is absent');
    }
    final parent = original.requireChildrenParentId();
    final existing = _childrenByTurn[turn];
    if (existing != null) {
      // An activity can retire its UI while the same Turn continues. Reopen
      // only that Turn's actual parent, never rebind a previous display lease.
      existing.requireMain(TimelineObservation.parse(before));
      if (original.threadId != existing.threadId ||
          parent != existing.parentId) {
        throw StateError('Original completed-member parent changed');
      }
      try {
        _qualifiedChildren(before, existing, running: true);
        return existing;
      } on StaleCurrentTools catch (error) {
        observations['${turn}CompletedParentRetired'] = {
          ...existing.evidence(),
          'childrenGeneration': existing.generation,
          'reason': error.toString(),
        };
      }
    }
    final opened = await _currentTools.openCompletedItems(
      turnId: turn,
      timeout: _remaining(clock, timeout),
    );
    if (opened.owner != original.owner) {
      throw StaleCurrentTools('Current identity changed while opening members');
    }
    final scopes = TimelineScopeDriver.session(driver);
    do {
      final candidate = await scopes.read();
      final current = CurrentToolsObservation.optional(candidate);
      final timeline = TimelineObservation.parse(candidate);
      if (turnId(candidate) != turn ||
          turnStatus(candidate) != 'running' ||
          current?.owner != original.owner ||
          current?.expanded != true) {
        throw StaleCurrentTools('Original parent retired before Children Set');
      }
      if (timeline.threadId != original.threadId ||
          timeline.generation != original.mainGeneration) {
        throw StaleCurrentTools('Main lease changed while opening members');
      }
      final child = timeline.childrenFor(parent);
      if (child?.error != null) {
        throw StateError('Original Children read failed: ${child!.error}');
      }
      if (child != null && child.ready && child.appliedSets > 0) {
        _remaining(clock, timeout);
        final scope = _WaitChildrenScope(opened, child.generation);
        _childrenByTurn[turn] = scope;
        observations['${turn}CompletedParent'] = {
          ...opened.evidence(),
          'childrenGeneration': child.generation,
          'appliedSets': child.appliedSets,
        };
        return scope;
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    } while (clock.elapsed < timeout);
    throw StateError('Original current Children did not accept Set in time');
  }

  Future<Map<String, dynamic>> _waitForCompletedTool(
    String turn,
    String label, {
    String? callId,
    String? prefix,
    required String contract,
    required Duration timeout,
  }) async {
    if ((callId == null) == (prefix == null)) {
      throw ArgumentError('Exactly one original call identity is required');
    }
    final clock = Stopwatch()..start();
    Map<String, dynamic>? returned;
    _WaitChildrenScope? acceptedScope;
    while (clock.elapsed < timeout) {
      final before = await snapshot();
      if (turnFailed(before) ||
          turnId(before) != turn ||
          turnStatus(before) != 'running') {
        throw StateError('$label lost its original Running Turn before result');
      }
      try {
        final scope = await _openCurrentChildren(
          turn,
          timeout: _remaining(clock, timeout),
        );
        final candidate = await snapshot();
        _qualifiedChildren(candidate, scope, running: true);
        final tool = callId == null
            ? _toolByCallPrefix(candidate, prefix!, parentId: scope.parentId)
            : _toolByCallId(candidate, callId, parentId: scope.parentId);
        if (tool != null) {
          if (tool['presentationContract'] != contract) {
            throw StateError('$label has an unexpected typed tool contract');
          }
          if (tool['status'] == 'succeeded') {
            returned = candidate;
            acceptedScope = scope;
            break;
          }
        }
      } on StaleCurrentTools catch (error) {
        observations['${label}CompletedRequalification'] = error.toString();
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    if (returned == null || acceptedScope == null) {
      throw StateError(
        '$label has no qualified completed result within $timeout',
      );
    }
    final scope = acceptedScope;
    _remaining(clock, timeout);
    final child = _qualifiedChildren(returned, scope, running: true);
    final tool = callId == null
        ? _toolByCallPrefix(returned, prefix!, parentId: scope.parentId)!
        : _toolByCallId(returned, callId, parentId: scope.parentId)!;
    observations['${label}CompletedReturn'] = {
      ...scope.evidence(),
      'childrenGeneration': child.generation,
      'appliedSets': child.appliedSets,
      'appliedAppends': child.appliedAppends,
      'callId': tool['callId'],
      'itemId': tool['itemId'],
      'presentationContract': tool['presentationContract'],
      'observedTurnStatus': turnStatus(returned),
    };
    return returned;
  }

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
    } catch (_) {}
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

  Future<Map<String, dynamic>> _awaitSettled(
    String turn,
    String label, {
    Duration timeout = const Duration(seconds: 180),
  }) async {
    final clock = Stopwatch()..start();
    final settled = await waitFor(
      (snapshot) => turnId(snapshot) == turn && isDurableSettled(snapshot),
      '${label}_settled',
      timeout: timeout,
      abort: (snapshot) =>
          turnFailed(snapshot) && turnId(snapshot) == turn && !isBusy(snapshot),
    );
    final scope = _childrenByTurn[turn];
    if (scope == null) return settled;
    final shown = await _openHistoricalChildren(
      scope,
      timeout: _remaining(clock, timeout),
    );
    if (turnId(shown) != turn || !isDurableSettled(shown)) {
      throw StateError(
        'Original settled Turn changed during history expansion',
      );
    }
    return shown;
  }

  /// Turn 已到达 completed。后台 sleep 可以继续 Running，不能要求整个 Thread idle。
  Future<Map<String, dynamic>> _awaitTurnCompleted(
    String turn,
    String label,
  ) async {
    final clock = Stopwatch()..start();
    const budget = Duration(seconds: 60);
    final completed = await waitFor(
      (snapshot) =>
          turnId(snapshot) == turn && turnStatus(snapshot) == 'completed',
      '${label}_completed',
      timeout: budget,
      abort: turnFailed,
    );
    final scope = _childrenByTurn[turn];
    if (scope == null) return completed;
    return _openHistoricalChildren(scope, timeout: _remaining(clock, budget));
  }

  Future<Map<String, dynamic>> _openHistoricalChildren(
    _WaitChildrenScope scope, {
    required Duration timeout,
  }) async {
    final clock = Stopwatch()..start();
    final scopes = TimelineScopeDriver.session(driver);
    final before = TimelineObservation.parse(await scopes.read());
    scope.requireMain(before, originalGeneration: false);
    final shown = await scopes.setExpanded(scope.parentId, true);
    final after = TimelineObservation.parse(shown);
    scope.requireMain(after, originalGeneration: false);
    if (after.generation != before.generation) {
      throw StaleCurrentTools('Historical Main retired during expansion');
    }
    _remaining(clock, timeout);
    _qualifiedChildren(shown, scope);
    return shown;
  }

  Future<Map<String, dynamic>> _waitForCurrentTools(
    bool Function(CurrentToolsObservation) predicate,
    String label, {
    required String turn,
    required List<String> prefixes,
    required Duration timeout,
  }) async {
    final clock = Stopwatch()..start();
    Duration actionBudget() {
      final left = timeout - clock.elapsed;
      return left < const Duration(seconds: 10)
          ? left
          : const Duration(seconds: 10);
    }

    Map<String, dynamic>? last;
    while (clock.elapsed < timeout) {
      last = await snapshot();
      if (turnFailed(last)) {
        throw StateError('$label aborted: ${_summarize(last)}');
      }
      final current = CurrentToolsObservation.optional(last);
      if (current?.turnId == turn && current?.activityId != null) {
        try {
          var page = await _currentTools.openTools(
            turnId: turn,
            timeout: actionBudget(),
          );
          while (clock.elapsed < timeout) {
            var candidate = await snapshot();
            last = candidate;
            var fresh =
                CurrentToolsObservation.optional(candidate) ??
                (throw StaleCurrentTools(
                  'Current tools retired before sampling',
                ));
            fresh.requireSame(page);
            for (final entry in fresh.collection!.entries) {
              if (entry.inline == null &&
                  prefixes.any(entry.id.startsWith) &&
                  fresh.decode(entry) == null) {
                await _currentTools.inspect(
                  fresh,
                  entry,
                  timeout: actionBudget(),
                );
                final afterWindow = await snapshot();
                final admitted =
                    CurrentToolsObservation.optional(afterWindow) ??
                    (throw StaleCurrentTools(
                      'Current entry retired after opening its window',
                    ));
                admitted.requireSame(fresh);
                fresh = admitted;
                candidate = afterWindow;
                last = afterWindow;
              }
            }
            if (predicate(fresh)) {
              // Do not bind completed members to the preceding model/tool
              // activity while still searching for the target Waiting.
              await _openCurrentChildren(turn, timeout: actionBudget());
              candidate = await snapshot();
              last = candidate;
              final admitted =
                  CurrentToolsObservation.optional(candidate) ??
                  (throw StaleCurrentTools(
                    'Current retired while opening its parent',
                  ));
              admitted.requireSame(fresh);
              if (predicate(admitted)) {
                _remaining(clock, timeout);
                return candidate;
              }
            }
            if (fresh.collection!.continuation == null) break;
            page = await _currentTools.next(fresh, timeout: actionBudget());
          }
        } on StaleCurrentTools catch (error) {
          // A new public current identity may be sought within the original
          // observation budget. No old entry/page/cursor is carried forward.
          observations['${label}Requalification'] = error.toString();
        } on CurrentToolsNotReady catch (error) {
          observations['${label}CurrentPending'] = error.toString();
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    throw StateError(
      '$label has no qualified typed current observation: ${_summarize(last ?? {})}',
    );
  }

  CurrentToolObservation _requireCurrentPrefix(
    Map<String, dynamic> snapshot,
    String prefix,
  ) {
    final current = CurrentToolsObservation.optional(snapshot);
    final tool = current?.toolByPrefix(prefix);
    if (tool == null) {
      throw StateError('Current visible tools have no original call $prefix');
    }
    return tool;
  }

  String _currentTask(CurrentToolObservation tool) {
    final task = tool.taskId;
    if (task == null) {
      throw StateError('Current call ${tool.callId} has no task identity');
    }
    return task;
  }

  void _requireWaitingTargets(
    CurrentToolObservation wait,
    List<CurrentToolObservation> selected,
  ) {
    final presentation = wait.wait;
    final expected = [for (final tool in selected) _currentTask(tool)];
    if (!wait.waiting || presentation?.targetsRunning(expected) != true) {
      throw StateError(
        'Typed Waiting does not name the exact running targets: ${wait.evidence()}',
      );
    }
  }

  Future<CurrentToolObservation> _readCurrentBackgroundCall(
    String callId,
    String taskId,
  ) async {
    final current = CurrentToolsObservation.optional(await snapshot());
    if (current == null) {
      throw StateError('Current background task $taskId is not observable');
    }
    final clock = Stopwatch()..start();
    var visible = await _currentTools.openTools(turnId: current.turnId);
    while (clock.elapsed < const Duration(seconds: 10)) {
      final tool = visible.toolByCallId(callId);
      if (tool != null) {
        if (tool.taskId != taskId) {
          throw StateError(
            'Current call $callId has a different task identity',
          );
        }
        return tool;
      }
      if (visible.collection!.continuation == null) break;
      visible = await _currentTools.next(
        visible,
        timeout: const Duration(seconds: 10) - clock.elapsed,
      );
    }
    throw StateError(
      'Original background call $callId/$taskId is not on the current tools pages',
    );
  }

  Future<void> _sleepFirst() async {
    final context = await _submit(
      '$_markSleepFirst wait until the short timer wins',
      'sleep_first',
    );
    final running = await _awaitNewTurn(context, 'sleep_first');
    final turn = turnId(running)!;
    final waiting = await _waitForCurrentTools(
      (current) {
        final wait = current.toolByPrefix('sleep-first-wait-t');
        final sleep = current.toolByPrefix('sleep-first-sleep-t');
        final exec = current.toolByPrefix('sleep-first-exec-t');
        return wait?.waiting == true &&
            wait?.wait?.kind == 'events' &&
            sleep?.waiting == true &&
            sleep?.wait?.kind == 'timer' &&
            exec?.state == 'running' &&
            wait?.wait?.targetsRunning([sleep?.taskId, exec?.taskId]) == true;
      },
      'sleep_first_waiting',
      turn: turn,
      prefixes: const [
        'sleep-first-wait-t',
        'sleep-first-sleep-t',
        'sleep-first-exec-t',
      ],
      timeout: const Duration(seconds: 20),
    );
    final firstWait = _requireCurrentPrefix(waiting, 'sleep-first-wait-t');
    final liveSleep = _requireCurrentPrefix(waiting, 'sleep-first-sleep-t');
    final liveExec = _requireCurrentPrefix(waiting, 'sleep-first-exec-t');
    _requireWaitingTargets(firstWait, [liveSleep, liveExec]);
    final firstWaitCallId = firstWait.callId;
    final firstWaitEntryId = firstWait.entry.id;
    final sleepCallId = liveSleep.callId;
    final execCallId = liveExec.callId;
    await _observeWaitUi(waiting, 'sleep-first-waiting', firstWaitEntryId);
    await capture('sleep-first-waiting', tree: true);
    checks['sleepFirstWaitLive'] = firstWait.waiting;
    checks['sleepFirstExecStillRunning'] =
        firstWait.wait!.target(_currentTask(liveExec))?.status == 'running';
    final waitSucceeded = await _waitForCompletedTool(
      turn,
      'sleep_first_wait_succeeded',
      callId: firstWaitCallId,
      contract: 'builtin.wait@1',
      timeout: const Duration(seconds: 20),
    );
    final waitAtReturn = _toolByCallId(waitSucceeded, firstWaitCallId)!;
    final waitResultAtReturn = _decodeWaitResult(
      waitAtReturn['result'] as String?,
    );
    final sleepAtReturn = _requireWaitTask(
      waitResultAtReturn,
      _currentTask(liveSleep),
    );
    final execAtReturn = _requireWaitTask(
      waitResultAtReturn,
      _currentTask(liveExec),
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
    final sleep = _requireCallPrefix(
      settled,
      'sleep-first-sleep-t',
      contract: 'builtin.sleep@1',
    );
    final exec = _requireCallPrefix(
      settled,
      'sleep-first-exec-t',
      contract: 'builtin.exec@2',
    );
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
      'waitEntryId': firstWaitEntryId,
      'selectedTaskStatesAtReturn': {
        'sleep': sleepAtReturn,
        'exec': execAtReturn,
      },
    };
    await _recordWaitDisplayTransition(firstWaitEntryId, 'sleepFirst');
    await _expandHistoryWait(
      firstWaitSettled['itemId'] as String?,
      'sleep-first-history',
    );
  }

  Future<void> _toolFirst() async {
    final context = await _submit(
      '$_markToolFirst wait until the short command wins',
      'tool_first',
    );
    final running = await _awaitNewTurn(context, 'tool_first');
    final turn = turnId(running)!;
    final waiting = await _waitForCurrentTools(
      (current) {
        final wait = current.toolByPrefix('tool-first-wait-t');
        final sleep = current.toolByPrefix('tool-first-sleep-t');
        final exec = current.toolByPrefix('tool-first-exec-t');
        return wait?.waiting == true &&
            wait?.wait?.kind == 'events' &&
            sleep?.waiting == true &&
            sleep?.wait?.kind == 'timer' &&
            exec != null &&
            wait?.wait?.targetsRunning([exec.taskId, sleep?.taskId]) == true;
      },
      'tool_first_waiting',
      turn: turn,
      prefixes: const [
        'tool-first-wait-t',
        'tool-first-sleep-t',
        'tool-first-exec-t',
      ],
      timeout: const Duration(seconds: 20),
    );
    final waitLive = _requireCurrentPrefix(waiting, 'tool-first-wait-t');
    final liveSleep = _requireCurrentPrefix(waiting, 'tool-first-sleep-t');
    final liveExec = _requireCurrentPrefix(waiting, 'tool-first-exec-t');
    _requireWaitingTargets(waitLive, [liveExec, liveSleep]);
    final waitCallId = waitLive.callId;
    final waitEntryId = waitLive.entry.id;
    final execCallId = liveExec.callId;
    final sleepCallId = liveSleep.callId;
    await _observeWaitUi(waiting, 'tool-first-waiting', waitEntryId);
    await capture('tool-first-waiting');
    checks['toolFirstWaitLive'] = waitLive.waiting;
    checks['toolFirstSleepStillRunning'] =
        waitLive.wait!.target(_currentTask(liveSleep))?.status == 'running';
    final waitSucceeded = await _waitForCompletedTool(
      turn,
      'tool_first_wait_succeeded',
      callId: waitCallId,
      contract: 'builtin.wait@1',
      timeout: const Duration(seconds: 20),
    );
    final waitAtReturn = _toolByCallId(waitSucceeded, waitCallId)!;
    final waitResultAtReturn = _decodeWaitResult(
      waitAtReturn['result'] as String?,
    );
    final execAtReturn = _requireWaitTask(
      waitResultAtReturn,
      _currentTask(liveExec),
    );
    final sleepAtReturn = _requireWaitTask(
      waitResultAtReturn,
      _currentTask(liveSleep),
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
    final exec = _requireCallPrefix(
      settled,
      'tool-first-exec-t',
      contract: 'builtin.exec@2',
    );
    final sleep = _requireCallPrefix(
      settled,
      'tool-first-sleep-t',
      contract: 'builtin.sleep@1',
    );
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
      'waitEntryId': waitEntryId,
      'selectedTaskStatesAtReturn': {
        'exec': execAtReturn,
        'sleep': sleepAtReturn,
      },
    };
    await _recordWaitDisplayTransition(waitEntryId, 'toolFirst');
    await _expandHistoryWait(wait['itemId'] as String?, 'tool-first-history');
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
    final waiting = await _waitForCurrentTools(
      (current) {
        final wait = current.toolByPrefix('child-wait-t');
        final sleep = current.toolByPrefix('child-parent-sleep-t');
        return wait?.waiting == true &&
            wait?.wait?.kind == 'events' &&
            sleep?.waiting == true &&
            sleep?.wait?.kind == 'timer' &&
            wait?.wait?.targetsRunning([sleep?.taskId]) == true;
      },
      'child_waiting',
      turn: turn,
      prefixes: const ['child-wait-t', 'child-parent-sleep-t'],
      timeout: const Duration(seconds: 40),
    );
    final waitLive = _requireCurrentPrefix(waiting, 'child-wait-t');
    final liveSleep = _requireCurrentPrefix(waiting, 'child-parent-sleep-t');
    _requireWaitingTargets(waitLive, [liveSleep]);
    final waitCallId = waitLive.callId;
    final parentSleepCallId = liveSleep.callId;
    checks['childWaitLive'] = waitLive.waiting;
    observations['childWaiting'] = {
      ...CurrentToolsObservation.optional(waiting)!.evidence(),
      ...waitLive.evidence(),
    };
    await capture('child-wait-observed', tree: true);
    final returnClock = Stopwatch()..start();
    const returnBudget = Duration(seconds: 180);
    final returned = await _waitForCompletedTool(
      turn,
      'child_wait_returned',
      callId: waitCallId,
      contract: 'builtin.wait@1',
      timeout: returnBudget,
    );
    final wait = _toolByCallId(returned, waitCallId);
    if (wait == null) {
      throw StateError('child wait $waitCallId missing at original return');
    }
    final waitResultAtReturn = _decodeWaitResult(wait['result'] as String?);
    final parentSleepAtReturn = _requireWaitTask(
      waitResultAtReturn,
      _currentTask(liveSleep),
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
    // The separate child-discovery budget remains 60s; result observation and
    // later settling share the original 180s settling budget.
    final settleBudget = _remaining(returnClock, returnBudget);
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
    await _awaitSettled(turn, 'child', timeout: settleBudget);
    await capture('child-settled');
    final backgroundSleep = await _readCurrentBackgroundCall(
      parentSleepCallId,
      _currentTask(liveSleep),
    );
    checks['childSleepStillVisible'] = backgroundSleep.state == 'running';
    final childId = child['threadId'] as String;
    await _tap('agent-switcher');
    await _tap('agent-thread-$childId');
    final childView = await waitFor(
      (snapshot) =>
          workspaceOf(snapshot)?['threadId'] == childId &&
          TimelineObservation.optional(snapshot)?.threadId == childId &&
          TimelineObservation.optional(snapshot)?.ready == true,
      'child_readonly_view',
      timeout: const Duration(seconds: 30),
    );
    await driver.waitFor(find.byValueKey('agent-readonly-panel'));
    await driver.waitForAbsent(find.byValueKey('composer-input'));
    await driver.waitForAbsent(find.byValueKey('composer-submit'));
    checks['childReadOnlyViewer'] =
        (workspaceOf(childView)?['composer'] as Map?)?['mode'] ==
        'runtimeDriven';
    if (checks['childReadOnlyViewer'] != true) {
      throw StateError('child view exposed an editable composer');
    }
    await capture('child-readonly');
    await _tap('agent-switcher');
    await _tap('agent-thread-$rootThreadId');
    await waitFor(
      (snapshot) =>
          workspaceOf(snapshot)?['threadId'] == rootThreadId &&
          TimelineObservation.optional(snapshot)?.threadId == rootThreadId &&
          TimelineObservation.optional(snapshot)?.ready == true,
      'child_return_root',
      timeout: const Duration(seconds: 30),
    );
    await driver.waitFor(find.byValueKey('composer-input'));
    checks['childReturnRoot'] = true;
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
    await _expandHistoryWait(wait['itemId'] as String?, 'child-history');
  }

  Future<void> _alreadyReady() async {
    final context = await _submit(
      '$_markAlreadyReady wait on the already completed timer',
      'already_ready',
    );
    final running = await _awaitNewTurn(context, 'already_ready');
    final turn = turnId(running)!;
    final clock = Stopwatch()..start();
    const budget = Duration(seconds: 180);
    final returned = await _waitForCompletedTool(
      turn,
      'already_ready_returned',
      prefix: 'already-ready-wait-t',
      contract: 'builtin.wait@1',
      timeout: budget,
    );
    final wait = _requireCallPrefix(returned, 'already-ready-wait-t');
    final waitResult = _decodeWaitResult(wait['result'] as String?);
    checks['alreadyReadyImmediate'] =
        wait['status'] == 'succeeded' && waitResult['timedOut'] == false;
    observations['alreadyReady'] = {
      'wait': waitResult,
      'waitCallId': wait['callId'],
      'waitItemId': wait['itemId'],
      'publicResultObservedWhileRunning': true,
      'immediateReturnLatency': 'notObservable',
    };
    pendingEvidence.add(
      'already-ready: original Running-Turn result proves readiness without '
      'timeout; UI sampling does not independently measure tool return latency',
    );
    await _awaitSettled(
      turn,
      'already_ready',
      timeout: _remaining(clock, budget),
    );
    await capture('already-ready');
  }

  Future<void> _timeout() async {
    final context = await _submit(
      '$_markTimeout wait with a short timeout on a long timer',
      'timeout',
    );
    final running = await _awaitNewTurn(context, 'timeout');
    final turn = turnId(running)!;
    final waiting = await _waitForCurrentTools(
      (current) {
        final wait = current.toolByPrefix('timeout-wait-t');
        final sleep = current.toolByPrefix('timeout-sleep-t');
        return wait?.waiting == true &&
            wait?.wait?.kind == 'events' &&
            sleep?.waiting == true &&
            sleep?.wait?.kind == 'timer' &&
            wait?.wait?.targetsRunning([sleep?.taskId]) == true;
      },
      'timeout_waiting',
      turn: turn,
      prefixes: const ['timeout-wait-t', 'timeout-sleep-t'],
      timeout: const Duration(seconds: 15),
    );
    final waitLive = _requireCurrentPrefix(waiting, 'timeout-wait-t');
    final liveSleep = _requireCurrentPrefix(waiting, 'timeout-sleep-t');
    _requireWaitingTargets(waitLive, [liveSleep]);
    final waitCallId = waitLive.callId;
    final waitEntryId = waitLive.entry.id;
    final sleepCallId = liveSleep.callId;
    checks['timeoutWaitLive'] = waitLive.waiting;
    observations['timeoutWaiting'] = {
      ...CurrentToolsObservation.optional(waiting)!.evidence(),
      ...waitLive.evidence(),
    };
    await capture('timeout-wait-observed');
    final clock = Stopwatch()..start();
    const budget = Duration(seconds: 180);
    final returned = await _waitForCompletedTool(
      turn,
      'timeout_wait_returned',
      callId: waitCallId,
      contract: 'builtin.wait@1',
      timeout: budget,
    );
    final wait = _toolByCallId(returned, waitCallId);
    if (wait == null) {
      throw StateError('timeout wait $waitCallId missing at original return');
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
      _currentTask(liveSleep),
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
      'waitEntryId': waitEntryId,
      'selectedTaskStatesAtReturn': {'sleep': sleepAtReturn},
    };
    await _awaitSettled(turn, 'timeout', timeout: _remaining(clock, budget));
    await capture('timeout-settled');
    await _expandHistoryWait(wait['itemId'] as String?, 'timeout-history');
  }

  Future<void> _cancelWait() async {
    final prepare = await _submit(
      '$_markCancelPrepare start a long background timer and finish this Turn',
      'cancel_prepare',
    );
    final prepareRunning = await _awaitNewTurn(prepare, 'cancel_prepare');
    final prepareTurn = turnId(prepareRunning)!;
    final prepareSleep = await _waitForCurrentTools(
      (current) {
        final sleep = current.toolByPrefix('cancel-sleep-t');
        return sleep?.waiting == true &&
            sleep?.wait?.kind == 'timer' &&
            sleep?.taskId != null;
      },
      'cancel_prepare_sleep_running',
      turn: prepareTurn,
      prefixes: const ['cancel-sleep-t'],
      timeout: const Duration(seconds: 20),
    );
    final liveSleep = _requireCurrentPrefix(prepareSleep, 'cancel-sleep-t');
    final sleepCallId = liveSleep.callId;
    final prepareDone = await _awaitTurnCompleted(
      prepareTurn,
      'cancel_prepare',
    );
    await capture('cancel-prepare');
    checks['cancelPrepareTurnCompleted'] =
        turnStatus(prepareDone) == 'completed';
    final backgroundSleep = await _readCurrentBackgroundCall(
      sleepCallId,
      _currentTask(liveSleep),
    );
    checks['cancelPrepareSleepStillRunning'] =
        backgroundSleep.state == 'running' &&
        backgroundSleep.wait?.state == 'waiting';

    final observe = await _submit(
      '$_markCancel wait only the previous Turn timer so stop cancels wait',
      'cancel_observe',
    );
    final observeRunning = await _awaitNewTurn(observe, 'cancel_observe');
    final observeTurn = turnId(observeRunning)!;
    checks['cancelObserveDistinctTurn'] = observeTurn != prepareTurn;
    final waiting = await _waitForCurrentTools(
      (current) {
        final wait = current.toolByPrefix('cancel-wait-t');
        return wait?.waiting == true &&
            wait?.wait?.targetsRunning([liveSleep.taskId]) == true;
      },
      'cancel_waiting',
      turn: observeTurn,
      prefixes: const ['cancel-wait-t'],
      timeout: const Duration(seconds: 20),
    );
    final waitLive = _requireCurrentPrefix(waiting, 'cancel-wait-t');
    _requireWaitingTargets(waitLive, [liveSleep]);
    final waitEntryId = waitLive.entry.id;
    await _observeWaitUi(waiting, 'cancel-waiting', waitEntryId);
    await capture('cancel-waiting');
    checks['cancelWaitLive'] = waitLive.waiting;
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
    final queried = await _waitForCompletedTool(
      queryTurn,
      'cancel_query_succeeded',
      prefix: 'cancel-query-t',
      contract: 'generic@1',
      timeout: const Duration(seconds: 30),
    );
    final queryTool = _requireCallPrefix(
      queried,
      'cancel-query-t',
      contract: 'generic@1',
    );
    final queryTask = _decodeTaskQuery(queryTool['result'] as String?);
    final expectedTaskId = _currentTask(liveSleep);
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
    final cancelTool = _requireCallPrefix(
      settled,
      'cancel-query-cancel-t',
      contract: 'generic@1',
    );
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
    String entryId,
  ) async {
    final original = CurrentToolsObservation.optional(waiting);
    if (original == null) {
      throw StaleCurrentTools('Waiting current display is absent');
    }
    original.requirePage();
    final entry = original.collection!.entries.singleWhere(
      (value) => value.id == entryId,
    );
    final tool = original.decode(entry);
    if (tool == null || !tool.waiting || tool.wait?.kind != 'events') {
      throw StateError('$label has no original typed event Waiting');
    }
    final shown = await _currentTools.inspect(original, entry);
    if (!shown.waiting) {
      throw StateError('$label public JSON is no longer Waiting');
    }
    observations['${label}Current'] = {
      ...original.evidence(),
      ...shown.evidence(),
    };
    await capture('$label-current-json');
    final current = CurrentToolsObservation.optional(await snapshot());
    if (current == null) {
      throw StaleCurrentTools('Waiting display retired during capture');
    }
    current.requireSame(original);
    final captured = current.toolByCallId(tool.callId);
    if (captured == null || captured.entry.id != entryId || !captured.waiting) {
      throw StateError('$label has no typed Waiting at capture completion');
    }
    final proof = <String, Object?>{
      ...current.evidence(),
      ...captured.evidence(),
      'publicJsonExpanded': true,
    };
    _liveWaitEvidence[entryId] = proof;
    observations['${label}WaitingEvidence'] = proof;
    checks['${label}TypedWaiting'] = captured.waiting;
    checks['${label}CurrentToolsExpanded'] =
        current.expanded && current.collection!.expanded;
    checks['${label}PublicJsonExpanded'] = true;
  }

  /// Current and completed widgets are different resources. Keep the original
  /// live expansion evidence, rather than requiring a deleted cross-layer tile.
  Future<void> _recordWaitDisplayTransition(
    String entryId,
    String label,
  ) async {
    final proof = _liveWaitEvidence[entryId];
    if (proof == null || proof['publicJsonExpanded'] != true) {
      throw StateError('$label has no real current entry expansion evidence');
    }
    observations['${label}ExpansionTransition'] = {
      'currentEntryToCompletedPanelExpansion': 'notApplicable',
      'reason': 'A current collection entry retires independently of the completed Children Message.',
      'liveProof': proof,
      'completedCoverage': 'The separate completed-item checks below require its actual item identity.',
    };
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

  /// Completed wait calls are independent Children Messages. Open only their
  /// actual parent Turn; no same-Turn GUI grouping or neighbor joining exists.
  Future<void> _revealWaitItem(String itemId, String label) async {
    final scopes = TimelineScopeDriver.session(driver);
    final parent = _completedItemParents[itemId];
    if (parent == null) {
      throw StateError('$label has no captured original item/parent identity');
    }
    final scope = _childrenByTurn.values.singleWhere(
      (scope) => scope.parentId == parent,
    );
    final history = scopes.history(
      loadMainOlder: () async {
        scope.requireMain(
          TimelineObservation.parse(await scopes.read()),
          originalGeneration: false,
        );
        await driver.requestData('load-older');
      },
      scrollOlder: (target) async {
        await driver.sendCommand(
          PointerScroll(target, -1000000, timeout: const Duration(seconds: 30)),
        );
      },
    );
    var pages = 0;
    var timeline = TimelineObservation.parse(await scopes.read());
    scope.requireMain(timeline, originalGeneration: false);
    final mainGeneration = timeline.generation;
    while (!timeline.items.any((item) => item.childrenParentId == parent)) {
      if (timeline.olderCursor == null || pages++ >= history.maxPages) {
        throw StateError('$label original parent is absent within page budget');
      }
      final before = timeline;
      await history.loadMainOlder();
      final shown = await waitFor(
        (candidate) {
          final main = TimelineObservation.parse(candidate);
          scope.requireMain(main, originalGeneration: false);
          if (main.generation != mainGeneration) {
            throw StaleCurrentTools('Historical Main retired during paging');
          }
          if (main.olderError != null) {
            throw StateError('Main paging failed: ${main.olderError}');
          }
          return !main.loadingOlder && main.olderCursor != before.olderCursor;
        },
        '${label}_parent_page',
        timeout: history.pageTimeout,
      );
      timeline = TimelineObservation.parse(shown);
    }
    final shown = await _openHistoricalChildren(
      scope,
      timeout: const Duration(seconds: 30),
    );
    timeline = TimelineObservation.parse(shown);
    if (timeline.generation != mainGeneration) {
      throw StaleCurrentTools('Historical Main retired before item paging');
    }
    final turn = timeline.items.singleWhere(
      (item) => item.childrenParentId == parent,
    );
    var child = _qualifiedChildren(shown, scope);
    while (!child.itemIds.contains(itemId)) {
      if (child.olderCursor == null || pages++ >= history.maxPages) {
        throw StateError('$label original wait is absent within page budget');
      }
      final before = child;
      await history.loadChildrenOlder(turn, child);
      final page = await waitFor(
        (candidate) {
          if (TimelineObservation.parse(candidate).generation !=
              mainGeneration) {
            throw StaleCurrentTools(
              'Historical Main retired during item paging',
            );
          }
          final current = _qualifiedChildren(candidate, scope);
          if (current.generation != before.generation) {
            throw StaleCurrentTools(
              'Historical Children retired during paging',
            );
          }
          return !current.loadingOlder &&
              current.olderCursor != before.olderCursor;
        },
        '${label}_item_page',
        timeout: history.pageTimeout,
      );
      child = _qualifiedChildren(page, scope);
    }
    final wait = child.items.singleWhere((item) => item.id == itemId);
    if (wait.kind != 'tool' ||
        wait.tool == null ||
        wait.tool!.presentationContract != 'builtin.wait@1' ||
        !_terminalToolStatuses.contains(wait.tool!.status) ||
        child.appliedSets < 1) {
      throw StateError(
        '$label has no completed wait in its actual admitted Children scope',
      );
    }
    await scopes.revealItem(itemId);
    observations['${label}Children'] = {
      'parentId': child.parentId,
      'generation': child.generation,
      'itemIds': child.itemIds,
      'appliedSets': child.appliedSets,
      'appliedPrepends': child.appliedPrepends,
      'appliedAppends': child.appliedAppends,
      'obsoleteGroupJoin': 'notApplicable',
    };
    checks['${label}ChildrenLocated'] = true;
  }

  /// Activity summary keys identify the real InkWell control. Wait-card
  /// panels still use the ListTile inside their official ExpansionTile.
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

  /// Each real Children Chat owns its own 320px viewport. Reveal the target
  /// inside that list as well as inside the outer Main timeline.
  Future<void> _scrollNestedUntilVisible(SerializableFinder item) async {
    final nested = find.ancestor(
      of: item,
      matching: find.byType('Scrollable'),
      firstMatchOnly: true,
    );
    await driver.waitFor(nested, timeout: const Duration(seconds: 2));
    await driver.scrollUntilVisible(
      nested,
      item,
      dyScroll: -80,
      timeout: const Duration(seconds: 15),
    );
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
      await _requireInTimelineViewport(detailsFinder, details, itemId);
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
    String itemId,
  ) async {
    final parent = _completedItemParents[itemId];
    if (parent == null) throw StateError('Missing original viewport parent');
    final scope = _childrenByTurn.values.singleWhere(
      (scope) => scope.parentId == parent,
    );
    final before = await snapshot();
    final originalChild = _qualifiedChildren(before, scope);
    final timeline = TimelineObservation.parse(before);
    final turn = timeline.items.singleWhere(
      (item) => item.childrenParentId == parent,
    );
    final childViewport = find.descendant(
      of: find.byValueKey('chat-item:${turn.id}'),
      matching: find.byType('Scrollable'),
      firstMatchOnly: true,
    );
    final top = await driver.getTopLeft(finder);
    final bottom = await driver.getBottomRight(finder);
    if (bottom.dy - top.dy <= 0 || bottom.dx - top.dx <= 0) {
      throw StateError('$label geometry is empty');
    }
    var left = top.dx, right = bottom.dx, upper = top.dy, lower = bottom.dy;
    for (final viewport in [
      find.byValueKey('timeline-scrollable'),
      childViewport,
    ]) {
      final a = await driver.getTopLeft(viewport);
      final b = await driver.getBottomRight(viewport);
      if (b.dx <= a.dx || b.dy <= a.dy) {
        throw StateError('$label has an empty actual viewport');
      }
      if (a.dx > left) left = a.dx;
      if (b.dx < right) right = b.dx;
      if (a.dy > upper) upper = a.dy;
      if (b.dy < lower) lower = b.dy;
    }
    if (right <= left || lower <= upper) {
      throw StateError('$label is clipped by Main or its actual Children Chat');
    }
    final after = await snapshot();
    if (TimelineObservation.parse(after).generation != timeline.generation) {
      throw StaleCurrentTools('Main viewport retired during measurement');
    }
    final currentChild = _qualifiedChildren(after, scope);
    if (currentChild.generation != originalChild.generation) {
      throw StaleCurrentTools('Children viewport retired during measurement');
    }
  }

  Map<String, dynamic>? _toolByCallId(
    Map<String, dynamic> snapshot,
    String callId, {
    String? parentId,
  }) {
    Map<String, dynamic>? match;
    for (final tool in _completedTools(snapshot, parentId: parentId)) {
      if (tool['callId'] == callId) {
        if (match != null) throw StateError('Ambiguous terminal call $callId');
        match = tool;
      }
    }
    return match;
  }

  /// Fixture call ids are `{slug}-t{generation}-call`. Each business stage owns
  /// a unique slug; generation stays 0 for these one-shot parent Turns.
  Map<String, dynamic>? _toolByCallPrefix(
    Map<String, dynamic> snapshot,
    String prefix, {
    String? parentId,
  }) {
    Map<String, dynamic>? match;
    for (final tool in _completedTools(snapshot, parentId: parentId)) {
      if (tool['callId'] is String &&
          (tool['callId'] as String).startsWith(prefix)) {
        if (match != null) throw StateError('Ambiguous original call $prefix');
        match = tool;
      }
    }
    return match;
  }

  /// Terminal results are visible only in explicitly opened Children.
  /// A sealed background-start receipt is a separate immutable item, not the
  /// terminal result of the same call. Preserve it in history, but do not accept
  /// it as result evidence or mistake it for a duplicate terminal.
  /// These records are never used by the live current Waiting predicates.
  Iterable<Map<String, dynamic>> _completedTools(
    Map<String, dynamic> snapshot, {
    String? parentId,
  }) sync* {
    final timeline = TimelineObservation.parse(snapshot);
    final scope = parentId == null
        ? _childrenByTurn[turnId(snapshot)]
        : _childrenByTurn.values
              .where((scope) => scope.parentId == parentId)
              .singleOrNull;
    if (scope == null) {
      throw StateError('No captured original completed-member parent');
    }
    scope.requireMain(timeline, originalGeneration: false);
    final child = timeline.childrenFor(scope.parentId);
    if (child?.error != null) {
      throw StateError('Original Children read failed: ${child!.error}');
    }
    if (child == null || !child.ready || child.appliedSets < 1) return;
    for (final item in child.items) {
      final tool = item.frozenFields()['tool'];
      if (tool is Map && _terminalToolStatuses.contains(tool['status'])) {
        _completedItemParents[item.id] = scope.parentId;
        yield {...tool.cast<String, dynamic>(), 'itemId': item.id};
      }
    }
  }

  Map<String, dynamic> _requireCallPrefix(
    Map<String, dynamic> snapshot,
    String prefix, {
    String contract = 'builtin.wait@1',
  }) {
    final tool = _toolByCallPrefix(snapshot, prefix);
    if (tool == null) {
      throw StateError(
        'missing tool callId prefix $prefix in ${_summarize(snapshot)}',
      );
    }
    if (tool['presentationContract'] != contract) {
      throw StateError('$prefix has an unexpected typed tool contract');
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
      'current': CurrentToolsObservation.optional(snapshot)?.evidence(),
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
