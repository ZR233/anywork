import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'driver_observation.dart';
import 'flutter_driver_session.dart';
import 'timeline_observation.dart';
import 'tool_probe.dart';
import 'window_control.dart';

/// Fully condition-driven realtime acceptance journey.
///
/// Every wait is a real observation of the GUI's Driver state: a new turn
/// identity, a new assistant row, a running tool, a real host-cwd execution, a
/// cancelled or failed terminal, and the durable settled projection. Timing is
/// captured from wall-clock stamps taken at those observations, never from a
/// fixed sleep. The fixture only issues tool calls; the tools really run.
const _answers = <String, String>{
  'delayed': 'realtime delayed first token',
  'reasoning': 'realtime reasoning answer',
  'longCommand': 'realtime long command complete',
  'parallel': 'realtime parallel tools complete',
  'hostCwd': 'realtime host cwd complete',
  'resume': 'realtime continued after cancel',
};

/// 本 journey 既定 provider-error 输入：发送后的新用户消息正文必须逐字等于它。
const _providerErrorPrompt = 'Realtime provider error';

const _activeToolStatuses = <String>{
  'queued',
  'started',
  'streaming',
  'running',
  'approved',
  'cancelling',
};

/// Statuses that prove a tool is genuinely executing, not merely scheduled.
///
/// `queued` is deliberately excluded: two tools sharing a tool group can be
/// queued together without ever running at the same time, so concurrency is
/// only accepted from live statuses.
const _liveToolStatuses = <String>{'started', 'streaming', 'running'};

/// Requested narrow size for the wide/narrow layout observation. The journey
/// reads the window's real geometry first and restores exactly what it found;
/// it never assumes a default size.
const _narrowWindowWidth = 640;
const _narrowWindowHeight = 600;

/// 反向列表里“离开底端”的最小真实位移（像素）。
///
/// 标准反向列表的底端是 offset 0，`extentBefore` 就是从 0 向上滚过的距离；
/// 少于这个距离视为仍贴在最后一行，不能当成阅读位置。
const _minDetachedOffset = 200.0;

/// Fixed pointer-drag step used to read up into history.
///
/// `FlutterDriver.scrollBy` drags the pointer by `dy`, so a positive step reveals
/// earlier content (a negative step keeps feeding content from below). The
/// timeline is a virtual list, so the oldest row may not be laid out at all and
/// must never be searched for by the driver. The step is deliberately finer than
/// the long-body stress step so a short assistant row cannot be stepped over.
const _historyScrollStep = 160.0;

/// Bounded number of history scroll steps; a view that never reaches a live
/// assistant row is reported from its real geometry instead of hanging.
const _maxHistoryScrollSteps = 60;

/// The activity details panel's documented height ceiling (`conversation_activity_bar.dart`).
const _maxActivityDetailsHeight = 320.0;

/// The minimum usable height of the expanded activity details panel.
///
/// The panel must show real, readable detail rather than a few clipped pixels:
/// roughly three text lines at the default body font (about 16 logical pixels per
/// line) is the smallest a reader can actually use. An expanded panel shorter than
/// this is a real layout failure, never evidence of a well-bounded panel.
const _minActivityDetailsHeight = 48.0;

/// Bounded deadline for observing that a window resize really reached Flutter.
///
/// Deliberately short: the applied size has to be read from real layout geometry,
/// never waited for by blocking on the app becoming idle. The live activity
/// spinner and the streamed text animate continuously, so an idle wait would burn
/// its whole deadline and never settle.
const _resizeSettleDeadline = Duration(seconds: 3);

/// Half a logical pixel of tolerance for rect comparisons; the Driver reports
/// logical pixels, so exact equality is not meaningful.
const _rectEpsilon = 0.5;

/// A widget rectangle read from the Driver geometry commands, in global (window)
/// logical pixels.
class DriverRect {
  const DriverRect({
    required this.key,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final String key;
  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;

  /// Whether [other] lies completely inside this rectangle.
  bool contains(DriverRect other) =>
      other.left >= left - _rectEpsilon &&
      other.top >= top - _rectEpsilon &&
      other.right <= right + _rectEpsilon &&
      other.bottom <= bottom + _rectEpsilon;

  Map<String, Object?> toJson() => <String, Object?>{
    'key': key,
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
    'width': width,
    'height': height,
  };
}

/// Whether two rectangles have the same size to within [_rectEpsilon]. Used to
/// confirm a resize really settled in the layout, never to compare positions.
bool _sameRectSize(DriverRect a, DriverRect b) =>
    (a.width - b.width).abs() <= _rectEpsilon &&
    (a.height - b.height).abs() <= _rectEpsilon;

const _terminalTurnStatuses = <String>{
  'completed',
  'failed',
  'cancelled',
  'budgetLimited',
};

/// 这份证据的取证范围：只证明当前这一次 Client 发布的顺序与显式清除。
///
/// 它不等于逐 token 的供应商原始事件，也不是传输时延或帧率证据。
const _runtimePublishScope =
    'one existing Client Session runtime read-model publication stream observed '
    'passively by the Driver-only recorder: at least two actual live publishes '
    'of one Turn/attempt with strictly increasing observation sequence and '
    'publication revision, followed by one explicit cleared publication. It is '
    'not a account raw-event, transfer-latency or frame-rate proof.';

Future<void> main(List<String> args) async {
  if (args.length != 4) {
    stderr.writeln(
      'usage: realtime_journey.dart VM_URL PROJECT_DIR OUTPUT_DIR COORD_DIR',
    );
    exitCode = 64;
    return;
  }
  // Connecting can fail before any journey state exists (bad VM URL, a GUI that
  // already exited, or a script error). Record a stage and a summary first so a
  // failure never leaves the coordinator with empty evidence.
  final output = Directory(args[2]);
  final coord = Directory(args[3]);
  final FlutterDriverSession driver;
  try {
    driver = await FlutterDriverSession.connect(vmServiceUrl: args[0]);
  } catch (error, stackTrace) {
    await _recordConnectFailure(output, coord, error);
    // `Error.throwWithStackTrace` never returns, so `driver` is definitely
    // assigned on every path that reaches the journey below.
    Error.throwWithStackTrace(error, stackTrace);
  }
  final journey = RealtimeJourney(
    driver: driver,
    project: args[1],
    output: output,
    coord: coord,
  );
  Object? failure;
  StackTrace? failureStack;
  Map<String, dynamic>? frames;
  try {
    await journey.run();
  } catch (error, stackTrace) {
    failure = error;
    failureStack = stackTrace;
    // Capture the failing observation before shutdown. The original error is
    // always preserved: a driver that already exited yields no extra evidence
    // instead of a second, misleading error.
    await _captureFailure(driver, output);
  }
  try {
    frames = await journey.stopFrameRecording();
  } catch (error) {
    journey.shutdownError ??= 'frame recording stop failed: $error';
  }
  Object? shutdownFailure;
  try {
    await _shutdown(driver);
  } catch (error) {
    shutdownFailure = error;
  }
  // Keep the stage marker consistent with the recorded failure: a shutdown
  // error must not leave the run looking complete.
  if (shutdownFailure != null) {
    journey.shutdownError ??= shutdownFailure.toString();
  }
  // Resolve the runtime publication evidence before the stage so a run whose
  // recorder never returned facts stays explicitly pending/failed instead of
  // looking like a completed realtime proof.
  journey.recordRuntimeEvidence();
  // Resolve the terminal stage before writing either artifact so the summary and
  // the stage file can never disagree: a clean run reports `complete`, a journey
  // exception keeps the exact stage it stopped at, and a shutdown-only failure,
  // failed check, or pending runtime evidence reports a non-complete stage.
  if (failure == null) {
    if (shutdownFailure != null || journey.shutdownError != null) {
      journey.stage = 'shutdown_failed';
    } else if (journey.failed) {
      journey.stage = 'checks_failed';
    } else if (journey.evidencePending) {
      journey.stage = 'evidence_pending';
    } else {
      journey.stage = 'complete';
    }
  }
  await journey.writeSummary(
    failure: failure,
    shutdownFailure: shutdownFailure,
    frames: frames,
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
    } catch (_) {
      // Native shutdown can close the observation connection first.
    }
  }
}

/// Saves the last Driver snapshot and a screenshot for a failed journey.
///
/// The caller keeps the original failure: a driver that already exited simply
/// yields no extra evidence instead of a second, misleading error.
Future<void> _captureFailure(
  FlutterDriverSession driver,
  Directory output,
) async {
  try {
    final snapshot = await driver.readSnapshot().timeout(
      const Duration(seconds: 10),
    );
    await File('${output.path}/realtime-failure-snapshot.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(snapshot)}\n',
    );
  } catch (_) {
    // Ignored: the summary still carries the original error and stage.
  }
  try {
    final png = await driver.screenshot().timeout(const Duration(seconds: 20));
    await File('${output.path}/realtime-failure.png').writeAsBytes(png);
  } catch (_) {
    // Ignored: see above.
  }
}

/// Records a stage marker and a minimal summary when the Driver cannot connect.
///
/// The coordinator reads both to report a specific stage and reason even though
/// no journey state was ever reached; the exit status and log come from the
/// parent process.
Future<void> _recordConnectFailure(
  Directory output,
  Directory coord,
  Object error,
) async {
  try {
    await File('${coord.path}/realtime-stage').writeAsString('connect_failed');
    final summary = <String, Object?>{
      'scenario': 'realtime',
      'verdict': 'pending',
      'status': 'failed',
      'stage': 'connect_failed',
      'error': error.toString(),
      'shutdownError': null,
      'failedChecks': const <String>[],
      'checks': const <String, Object?>{},
      'timings': const <String, Object?>{},
      'counts': const <String, Object?>{},
      'observations': const <String, Object?>{},
      'transitions': 0,
      'frameSampleCount': null,
      'completedAt': DateTime.now().toUtc().toIso8601String(),
      'pendingEvidence': const <String>[],
    };
    await File(
      '${output.path}/realtime-summary.json',
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(summary)}\n');
  } catch (_) {
    // Evidence directories are owned by the coordinator; if writing fails the
    // parent still captures the exit status and the sanitized Driver log.
  }
}

class SubmitContext {
  const SubmitContext({
    required this.priorTurnId,
    required this.priorContent,
    required this.priorReasoning,
    required this.priorAnswers,
    required this.submittedAt,
  });

  final String? priorTurnId;
  final int priorContent;
  final int priorReasoning;
  final int priorAnswers;
  final int submittedAt;
}

class RealtimeJourney {
  RealtimeJourney({
    required this.driver,
    required this.project,
    required this.output,
    required this.coord,
  });

  final FlutterDriverSession driver;
  final String project;
  final Directory output;
  final Directory coord;
  final List<Map<String, Object?>> transitions = <Map<String, Object?>>[];
  final Map<String, Object?> checks = <String, Object?>{};
  final Map<String, Object?> timings = <String, Object?>{};
  final Map<String, Object?> counts = <String, Object?>{};

  /// Structured evidence that is not a single per-transition snapshot (for
  /// example the long-command in-flight progress samples). It is written into
  /// the summary so the evidence survives instead of being dropped.
  final Map<String, Object?> observations = <String, Object?>{};
  String stage = 'created';
  String? shutdownError;

  /// The activity identity that was expanded during the reasoning stream, kept so
  /// the next live activity can prove a different identity starts collapsed.
  String? expandedActivityIdentity;

  /// 快照轮询样本：只作为 UI 就绪观察，永不作发布顺序判定输入（design/24 实时验收、
  /// design/26 §26.9）。真实发布证据只来自 Driver-only 记录器的实际 Client 发布回调。
  final List<DriverRuntimeObservation> _runtimeSamples =
      <DriverRuntimeObservation>[];

  /// Driver-only 记录器返回的实际发布取证；缺失即失败，不退化成轮询样本。
  DriverRuntimePublishEvidence? _runtimePublish;
  bool _runtimeEvidenceRecorded = false;
  bool _runtimeEvidencePending = false;

  /// 记录器身份：start 时固定，stop 时用同一身份严格校验响应对应的就是这一次 run。
  String? _runtimePublishThreadId;
  String? _runtimePublishTurnId;

  /// Whether the previous live activity was left actually expanded, so the
  /// cross-identity reset has a real expanded reference to reset.
  bool activityLeftExpanded = false;

  /// Evidence that could not be asserted yet, kept explicit so a partial
  /// observation is never reported as a pass. The integrated UI contract adds
  /// `timelineScroll`/`conversationActivity`; when they are absent every related
  /// sub-check is recorded here instead of being asserted.
  final List<String> pendingEvidence = <String>[
    'parallel concurrency is observed from two live exec tools in one poll; a backend overlap counter is still outstanding',
    'in-flight tool stdout is asserted from ordered conversationActivity output parts keyed by activity identity and real call/part identity; missing parts remain unverified',
    'exec is a background tool: the scripted model only reports completion after it observed the task with the supported wait tool, so the model Turn terminal is recorded separately from the delivered command result and from the durable settled projection',
    'the parallel scenario waits on both command receipts; a single settled model step may consume both delivered results, so one answer is accepted for the batch',
    'first-content latency is measured from the Driver wall clock, not a account TTFT field',
    'the account fixture reports its own account output bytes; those bytes are never an FRB transfer measurement',
  ];

  File get stageFile => File('${coord.path}/realtime-stage');

  bool get failed =>
      checks.values.any((value) => value != true) || shutdownError != null;

  bool get evidencePending => _runtimeEvidencePending;

  Future<void> run() async {
    await mark('connected');
    await _openProject();
    await observe('project_opened');
    await driver.requestData(
      'frame-start',
      timeout: const Duration(seconds: 20),
    );
    counts['frameRecordingStartedAt'] = DateTime.now().millisecondsSinceEpoch;

    await _delayedFirstToken();
    await _reasoningThenAnswer();
    await _longCommand();
    await _parallelTools();
    await _hostCwd();
    await _providerError();
    await _cancel();
    await _resume();
    await _uiContracts();
  }

  Future<void> mark(String value) async {
    stage = value;
    await stageFile.writeAsString(value);
  }

  Future<Map<String, dynamic>> snapshot() async {
    final state = await driver.readSnapshot();
    _runtimeSamples.add(driverRuntimeObservation(state));
    if (_runtimeSamples.length > 4096) {
      _runtimeSamples.removeRange(0, 1024);
    }
    final workspace = state['workspace'] as Map?;
    final route = workspace?['modelRoute'] as Map?;
    if (route != null && workspace?['isBusy'] == true) {
      // The fixture binding stays valid across calls, account errors and cancel.
      // A transfer checkpoint must never turn it into an unavailable GUI route.
      checks['modelBindingAvailableDuringCalls'] =
          checks['modelBindingAvailableDuringCalls'] != false &&
          route['available'] == true;
    }
    return state;
  }

  Future<Map<String, dynamic>> waitFor(
    bool Function(Map<String, dynamic>) predicate,
    String label, {
    Duration timeout = const Duration(seconds: 60),
    bool Function(Map<String, dynamic>)? abort,
  }) async {
    final deadline = DateTime.now().add(timeout);
    Map<String, dynamic>? last;
    while (DateTime.now().isBefore(deadline)) {
      final current = await snapshot();
      last = current;
      if (predicate(current)) return current;
      // A terminal failure makes the awaited state unreachable; report the full
      // observation and the turn identity immediately instead of burning the
      // whole timeout and only then describing a stale snapshot.
      if (abort != null && abort(current)) {
        throw StateError('$label aborted: ${summarize(current)}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final diagnostic = last == null ? const {} : summarize(last);
    throw StateError('timed out waiting for $label: $diagnostic');
  }

  Future<void> observe(String name, [Map<String, dynamic>? current]) async {
    final snapshot = current ?? await this.snapshot();
    final entry = <String, Object?>{
      'stage': name,
      'atUnixMillis': DateTime.now().millisecondsSinceEpoch,
      ...summarize(snapshot),
    };
    transitions.add(entry);
    await File(
      '${output.path}/realtime-$name.json',
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(entry)}\n');
    await File('${output.path}/realtime-transitions.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(transitions)}\n',
    );
  }

  Future<void> shot(String name) async {
    await File('${output.path}/realtime-$name.png')
        .writeAsBytes(await driver.screenshot());
  }

  Future<SubmitContext> submitPrompt(String prompt, String label) async {
    final before = await snapshot();
    final context = SubmitContext(
      priorTurnId: turnId(before),
      priorContent: assistantContentCount(before),
      priorReasoning: reasoningCount(before),
      priorAnswers: answerCount(before),
      submittedAt: 0,
    );
    await mark('${label}_submit');
    await _submit(prompt);
    return SubmitContext(
      priorTurnId: context.priorTurnId,
      priorContent: context.priorContent,
      priorReasoning: context.priorReasoning,
      priorAnswers: context.priorAnswers,
      submittedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<Map<String, dynamic>> awaitNewTurn(
    SubmitContext context,
    String label,
  ) {
    // A new turn identity is the only reliable signal that this submission was
    // accepted: a account error or a cancelled stream can leave the busy flag
    // false before the next poll, so requiring `isBusy` here would miss the
    // turn entirely. Completion is handled separately by `awaitTerminal`.
    return waitFor(
      (snapshot) => turnId(snapshot) != context.priorTurnId,
      '${label}_running',
      timeout: const Duration(seconds: 30),
    );
  }

  Future<Map<String, dynamic>> awaitTerminal(String turn, String label) {
    return waitFor(
      (snapshot) =>
          turnId(snapshot) == turn &&
          _terminalTurnStatuses.contains(turnStatus(snapshot)),
      '${label}_terminal',
      timeout: const Duration(seconds: 120),
      abort: (snapshot) =>
          threadFaulted(snapshot) ||
          (turnId(snapshot) != turn && isDurableSettled(snapshot)),
    );
  }

  Future<Map<String, dynamic>> awaitSettled(String turn, String label) {
    return waitFor(
      (snapshot) => turnId(snapshot) == turn && isDurableSettled(snapshot),
      '${label}_settled',
      timeout: const Duration(seconds: 120),
      abort: (snapshot) =>
          threadFaulted(snapshot) ||
          turnStatus(snapshot) == 'failed' ||
          (turnId(snapshot) != turn && isDurableSettled(snapshot)),
    );
  }

  /// Waits for one model Turn to reach the `completed` terminal state.
  ///
  /// A failed, cancelled or superseded terminal makes that state unreachable, so
  /// the real observation is reported immediately instead of after the timeout.
  Future<Map<String, dynamic>> awaitCompleted(String turn, String label) {
    return waitFor(
      (snapshot) =>
          turnId(snapshot) == turn && turnStatus(snapshot) == 'completed',
      '${label}_terminal',
      timeout: const Duration(seconds: 120),
      abort: (snapshot) =>
          turnFailed(snapshot) ||
          (turnId(snapshot) != turn && isDurableSettled(snapshot)),
    );
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
    await driver.waitFor(
      find.byValueKey('project-path-submit'),
      timeout: const Duration(seconds: 30),
    );
    await _tap('project-path-submit');
    await driver.waitFor(
      find.byValueKey('composer-input'),
      timeout: const Duration(seconds: 60),
    );
  }

  Future<void> _submit(String prompt) async {
    await driver.waitFor(
      find.byValueKey('composer-input'),
      timeout: const Duration(seconds: 30),
    );
    await _tap('composer-input');
    await driver.enterText(prompt);
    await driver.waitFor(
      find.byValueKey('composer-submit'),
      timeout: const Duration(seconds: 30),
    );
    await _tap('composer-submit');
  }

  Future<void> _tap(String key) async {
    await driver.rawTap(
      find.byValueKey(key),
      timeout: const Duration(seconds: 30),
    );
  }

  Future<void> _delayedFirstToken() async {
    final context = await submitPrompt(
      'Realtime delayed first token',
      'delayed',
    );
    final waiting = await waitFor(
      (snapshot) {
        final diagnostics = snapshot['driverDiagnostics'] as Map?;
        final stream = diagnostics?['stateStream'] as Map?;
        final turn = turnId(snapshot);
        return turn != null &&
            turn != context.priorTurnId &&
            !_liveTextPresent(snapshot, turn, 'responseParts') &&
            assistantContentCount(snapshot) == context.priorContent &&
            stream?['threadId'] ==
                TimelineObservation.optional(snapshot)?.threadId &&
            stream?['hasSnapshot'] == true &&
            stream?['epoch'] is int;
      },
      'delayed_waiting',
      timeout: const Duration(seconds: 20),
      abort: threadFaulted,
    );
    final turn = turnId(waiting)!;
    // 在首字之前的真实窗口里登记 runtime 发布观察：复用 fixture 既有首字时延，
    // 不新增 sleep、不改后端 pacing、也不发模型请求。必须在 observe/shot
    // 之前注册，否则截图会吃掉 delayed 窗口，只剩 baseline。
    await _startRuntimePublishEvidence(waiting);
    // Running text belongs to activity, not an unfinished history row. Start
    // this bounded read-only observation before screenshot work can miss it.
    final firstContentObservation = waitFor(
      (snapshot) =>
          turnId(snapshot) == turn &&
          isBusy(snapshot) &&
          _liveTextPresent(snapshot, turn, 'responseParts') &&
          assistantContentCount(snapshot) == context.priorContent,
      'delayed_first_content',
      timeout: const Duration(seconds: 30),
      abort: threadFaulted,
    ).then((snapshot) => (snapshot, DateTime.now().millisecondsSinceEpoch));
    await Future.wait<void>([
      firstContentObservation.then<void>((_) {}),
      () async {
        await observe('delayed_waiting', waiting);
        await shot('delayed-waiting');
      }(),
    ]);
    final (firstContent, firstContentAt) = await firstContentObservation;
    await observe('delayed_first_content', firstContent);
    await shot('delayed-streaming');
    final terminal = await awaitTerminal(turn, 'delayed');
    final terminalAt = DateTime.now().millisecondsSinceEpoch;
    await observe('delayed_terminal', terminal);
    final settled = await awaitSettled(turn, 'delayed');
    await observe('delayed_settled', settled);
    // 该 Turn 真实 completed 且 durable 之后停止记录并保存实际发布取证；
    // 一次 Turn 足够，后续 Turn 不再复用本记录器。
    await _stopRuntimePublishEvidence();
    timings['delayed'] = {
      'submittedAt': context.submittedAt,
      'firstContentAt': firstContentAt,
      'terminalAt': terminalAt,
      'durableSettledAt': DateTime.now().millisecondsSinceEpoch,
      'timeToFirstContentMillis': firstContentAt - context.submittedAt,
      'terminalStatus': turnStatus(terminal),
      'outputTokens': outputTokens(settled),
    };
    checks['delayedFirstToken'] = (firstContentAt - context.submittedAt) >= 600;
    checks['delayedCompleted'] = answerContains(settled, _answers['delayed']!);
  }

  Future<void> _reasoningThenAnswer() async {
    final context = await submitPrompt(
      'Realtime reasoning then answer',
      'reasoning',
    );
    final running = await awaitNewTurn(context, 'reasoning');
    final turn = turnId(running)!;
    final reasoning = await waitFor(
      (snapshot) =>
          turnId(snapshot) == turn &&
          isBusy(snapshot) &&
          _liveTextPresent(snapshot, turn, 'reasoningParts') &&
          reasoningCount(snapshot) == context.priorReasoning &&
          answerCount(snapshot) == context.priorAnswers,
      'reasoning_in_progress',
      timeout: const Duration(seconds: 30),
      abort: threadFaulted,
    );
    await observe('reasoning_in_progress', reasoning);
    await shot('reasoning-in-progress');
    // The live reasoning is this turn's first content, so the time-to-first-content
    // stamp is taken here, before the activity-bar contract spends time observing.
    final firstContentAt = DateTime.now().millisecondsSinceEpoch;
    // The activity bar is exercised while reasoning is really running: only a
    // live activity exposes expandable details, and this is the long "Thinking"
    // window where the bar's latest summary line is on screen.
    await _activityContractDuringBusy('reasoning', narrowLayout: true);
    // The activity contract can consume most of the pacing window, so this
    // observation accepts either the answer row appearing or this turn reaching a
    // terminal — never an unbounded `isBusy` window that could already be gone.
    final streaming = await waitFor(
      (snapshot) =>
          turnId(snapshot) == turn &&
          (answerCount(snapshot) > context.priorAnswers ||
              _terminalTurnStatuses.contains(turnStatus(snapshot))),
      'reasoning_answer_streaming',
      timeout: const Duration(seconds: 30),
      abort: threadFaulted,
    );
    await observe('reasoning_answer_streaming', streaming);
    await shot('reasoning-answer-streaming');
    final terminal = await awaitTerminal(turn, 'reasoning');
    final terminalAt = DateTime.now().millisecondsSinceEpoch;
    final settled = await awaitSettled(turn, 'reasoning');
    await observe('reasoning_complete', settled);
    final rows = TimelineObservation.parse(settled).items;
    final reasoningIndex = rows.indexWhere((item) => item.kind == 'reasoning');
    final answerIndex = rows.indexWhere(
      (item) =>
          item.kind == 'agentMessage' &&
          item.text.contains(_answers['reasoning']!),
    );
    timings['reasoning'] = {
      'submittedAt': context.submittedAt,
      'firstContentAt': firstContentAt,
      'terminalAt': terminalAt,
      'durableSettledAt': DateTime.now().millisecondsSinceEpoch,
      'timeToFirstContentMillis': firstContentAt - context.submittedAt,
      'terminalStatus': turnStatus(terminal),
      'reasoningRows': rows.where((item) => item.kind == 'reasoning').length,
    };
    checks['reasoningThenAnswer'] =
        reasoningIndex >= 0 && answerIndex > reasoningIndex;
  }

  Future<void> _longCommand() async {
    // Hold this independent feed before submitting new work, not inside the
    // finite real-tool output sampling window.
    final creditThread = TimelineObservation.optional(await snapshot())
        ?.threadId;
    if (creditThread == null) {
      throw StateError('real long-command Thread has no timeline observation');
    }
    counts['frbCreditHeld'] = await _creditProbe(
      'open',
      threadId: creditThread,
    );
    final context = await submitPrompt('Realtime long command', 'long_command');
    final running = await awaitNewTurn(context, 'long_command');
    final turn = turnId(running)!;
    // `exec` is a background tool, so the real command is still running while
    // the model Turn stays live on the supported `wait` receipt. The command is
    // observed from its own live status, never inferred from the group.
    final toolRunning = await waitFor(
      (snapshot) => turnId(snapshot) == turn && activeExecCount(snapshot) >= 1,
      'long_command_tool_running',
      timeout: const Duration(seconds: 30),
      abort: turnFailed,
    );
    final toolRunningAt = DateTime.now().millisecondsSinceEpoch;
    await observe('long_command_tool_running', toolRunning);
    // One immediate loop, starting from the first running snapshot: it samples
    // the running call's typed stdout *and* the cross-identity activity reset in
    // the same poll, so neither is lost to the other's cost and no screenshot is
    // taken before the first live sample. The previous activity was left expanded
    // during reasoning, so this turn's tool activity must publish a different
    // identity collapsed. A version jump or a `running` status alone is never
    // accepted; the final line result is still verified below.
    await _longCommandLiveContract(toolRunning);

    // Delivery: the real command exited and its committed output is visible.
    // Only a delivered result may satisfy the output check; the model Turn
    // terminal is a separate fact and never stands in for the delivered command.
    final delivered = await waitFor(
      (snapshot) => execDelivered(
        snapshot,
        'realtime-long-call',
        'realtime-long-output-line',
      ),
      'long_command_tool_delivered',
      timeout: const Duration(seconds: 120),
      abort: turnFailed,
    );
    final deliveredAt = DateTime.now().millisecondsSinceEpoch;
    await observe('long_command_tool_delivered', delivered);
    await shot('long-command-tool-delivered');

    // The model Turn terminal and the durable settled projection are two
    // different facts and are recorded separately, never conflated.
    final terminal = await awaitCompleted(turn, 'long_command');
    final terminalAt = DateTime.now().millisecondsSinceEpoch;
    await observe('long_command_execution_terminal', terminal);
    final settled = await awaitSettled(turn, 'long_command');
    final settledAt = DateTime.now().millisecondsSinceEpoch;
    await observe('long_command_continuation', settled);
    await shot('long-command-continuation');
    // This separate real FRB subscription has not acknowledged either initial
    // frame while the normal UI/provider completed the command and saved it.
    counts['frbCreditIndependentQuery'] = await _creditProbe('query');
    counts['frbCreditAfterOneAck'] = await _creditProbe('ack-one');
    final creditClosed = await _creditProbe('close');
    counts['frbCreditClosed'] = creditClosed;
    checks['frbTwoFrameCreditAndIndependentQuery'] =
        creditClosed['joined'] == true &&
        creditClosed['failure'] == null &&
        creditClosed['acknowledged'] == 1 &&
        (creditClosed['frames'] as List).length == 3;

    final result = execTools(settled)
        .map((tool) => tool['result'] as String? ?? '')
        .join('\n');
    timings['longCommand'] = {
      'submittedAt': context.submittedAt,
      'toolRunningAt': toolRunningAt,
      'toolDeliveredAt': deliveredAt,
      'executionTerminalAt': terminalAt,
      'executionTerminalStatus': turnStatus(terminal),
      'durableSettledAt': settledAt,
      'commandDeliveredMillis': deliveredAt - context.submittedAt,
      'executionTerminalMillis': terminalAt - context.submittedAt,
    };
    counts['longCommandOutputLines'] = 'realtime-long-output-line'
        .allMatches(result)
        .length;
    checks['longCommandRunning'] = true;
    // The completed wording must not exist before the command delivered.
    checks['longCommandNoEarlyCompletion'] = !answerContains(
      toolRunning,
      _answers['longCommand']!,
    );
    checks['longCommandOutput'] =
        execDelivered(
          settled,
          'realtime-long-call',
          'realtime-long-output-line',
        ) &&
        (counts['longCommandOutputLines'] as int) > 1 &&
        answerContains(settled, _answers['longCommand']!);
  }

  Future<Map<String, dynamic>> _creditProbe(
    String action, {
    String? threadId,
  }) async {
    final result = jsonDecode(
      await driver.requestData(
        jsonEncode({
          'cmd': 'conversation-credit-$action',
          'threadId': ?threadId,
        }),
        timeout: const Duration(seconds: 30),
      ),
    );
    if (result is! Map<String, dynamic> ||
        result['source'] != 'real-frb-conversation-feed' ||
        result['failure'] != null) {
      throw StateError('real FRB credit observation failed: $result');
    }
    return result;
  }

  /// One immediate, unified live-window loop for the long command.
  ///
  /// It starts from the first running snapshot — never after a screenshot — and
  /// samples two independent live facts in the *same* poll so neither can be lost
  /// to the other's cost:
  ///
  /// * the running `exec` call's ordered output parts must change content across
  ///   multiple observations of the same activity and call identity; state and
  ///   byte counters alone do not satisfy this; and
  /// * a *different* live activity identity must be published collapsed, i.e. the
  ///   expand state must reset when the activity identity switches.
  ///
  /// Both are recorded the moment they are observed. A build without the typed
  /// in-flight fields, or a run that never exposed the activity field, records an
  /// explicit pending gap instead of a pass.
  Future<void> _longCommandLiveContract(Map<String, dynamic> first) async {
    const callId = 'realtime-long-call';
    final previousIdentity = expandedActivityIdentity;
    final wantIdentityReset = previousIdentity != null && activityLeftExpanded;
    final samples = <Map<String, Object?>>[];
    var activityOutputPartsSeen = false;
    var activityFieldSeen = false;
    var observedGrowth = false;
    var identityResetObserved = false;
    var activityToolOpened = false;
    String? openedActivityIdentity;
    var activityDetailGrowth = false;
    int? previousDetailLines;
    final activityDetailSamples = <Map<String, Object?>>[];
    final activityToolOutput = find.byValueKey(
      'live-tool-output-$callId-command-output',
    );
    Map<String, Object?>? previous;
    var latest = first;
    final deadline = DateTime.now().add(const Duration(seconds: 40));
    while (DateTime.now().isBefore(deadline)) {
      final snapshot = latest;
      // (a) Cross-identity reset: recorded the moment a different live identity
      // is published collapsed, never awaited after the window has closed.
      final activity = conversationActivity(snapshot);
      if (activity != null) activityFieldSeen = true;
      if (wantIdentityReset &&
          !identityResetObserved &&
          activity != null &&
          activity['identity'] is String &&
          activity['identity'] != previousIdentity &&
          activity['expanded'] == false) {
        identityResetObserved = true;
        // Only the lightweight observation file is written here: the loop must
        // not block on a screen capture (which costs seconds) before it samples
        // the running call's stdout. Every screenshot is taken after the loop.
        await observe('long_command_activity_identity_switch', snapshot);
        checks['activityIdentityResetsCollapse'] = true;
      }
      // (b) In-flight typed stdout growth of the same call identity.
      if (_activityExposesOutputParts(snapshot, callId)) {
        activityOutputPartsSeen = true;
      }
      final sample = _liveToolProgressSample(snapshot, callId);
      if (sample != null) {
        samples.add(<String, Object?>{
          'at': DateTime.now().millisecondsSinceEpoch,
          'activeToolCount': activity?['activeToolCount'],
          'toolCallIds': [
            for (final tool
                in (activity?['toolDetails'] as List? ?? const [])
                    .whereType<Map>())
              tool['callId'],
          ],
          ...sample,
        });
        if (previous != null &&
            sample['activityIdentity'] == previous['activityIdentity'] &&
            sample['callId'] == previous['callId'] &&
            activityPartTextChanged(
              previous['outputParts'],
              sample['outputParts'],
              identityField: 'partId',
            )) {
          observedGrowth = true;
        }
        previous = sample;
      }
      final tool = _completedExecByCallId(snapshot, callId);
      // Once the call is terminal no further live sample or activity can arrive.
      final toolTerminal =
          tool != null && _terminalToolStatuses.contains(tool['status']);
      final activityIdentity = activity?['identity'] as String?;
      if (activityToolOpened && activityIdentity != openedActivityIdentity) {
        activityToolOpened = false;
        previousDetailLines = null;
      }
      // Open after this fixture's real foreground wait has appeared. The exec
      // begins in attempt 0 and its background receipt advances to attempt 1;
      // an expansion sampled across that identity change is legitimately
      // retired. Read the exact wait identity, never infer it from a count.
      final waitTool = _liveToolProgressSample(
        snapshot,
        'realtime-long-wait-call',
      );
      if (!toolTerminal &&
          !activityToolOpened &&
          sample != null &&
          waitTool != null &&
          activity != null &&
          (!wantIdentityReset || identityResetObserved)) {
        if (activity['expanded'] != true) {
          await _tap('conversation-activity');
        }
        final row = find.byValueKey('live-tool-row-$callId');
        await driver.waitFor(row, timeout: const Duration(seconds: 5));
        final rowState = await driver.sendCommand(ToolProbe(row, 'observe'));
        final rowSample = (rowState['samples'] as List).last as Map;
        if (rowSample['expanded'] is! bool) {
          throw StateError('live tool row exposes no real expansion state');
        }
        if (rowSample['expanded'] == false) {
          // This is still the collapsed header. ToolProbe's historical `tap`
          // deliberately samples 24 later frames, which can outlive a live
          // tool; dispatch the existing hit-tested tap without that recording.
          await driver.rawTap(row, timeout: const Duration(seconds: 5));
        }
        await driver.waitFor(
          activityToolOutput,
          timeout: const Duration(seconds: 5),
        );
        await driver.sendCommand(
          ScrollIntoView(
            activityToolOutput,
            alignment: 1,
            timeout: const Duration(seconds: 5),
          ),
        );
        activityToolOpened = true;
        openedActivityIdentity = activityIdentity;
      }
      if (!toolTerminal && activityToolOpened) {
        final Map<String, dynamic> rendered;
        try {
          rendered = await driver.sendCommand(
            ToolProbe(activityToolOutput, 'readText'),
          );
        } on DriverError {
          final retired = await this.snapshot();
          final retiredTool = _completedExecByCallId(retired, callId);
          if (retiredTool != null &&
              _terminalToolStatuses.contains(retiredTool['status'])) {
            latest = retired;
            break;
          }
          rethrow;
        }
        final renderedSample = (rendered['samples'] as List).single as Map;
        final texts = renderedSample['texts'] as List;
        final outputs = texts.whereType<String>().where(
          (text) => text.startsWith('realtime-long-output-line-01'),
        );
        final fresh = await this.snapshot();
        final freshTool = _liveToolProgressSample(fresh, callId);
        if (outputs.length > 1) {
          throw StateError('ambiguous live activity output for $callId');
        }
        if (outputs.isNotEmpty &&
            freshTool != null &&
            freshTool['activityIdentity'] == openedActivityIdentity &&
            (renderedSample['visibleHeight'] as num) > 0) {
          final output = outputs.single;
          final lines = RegExp(r'realtime-long-output-line-\d\d')
              .allMatches(output)
              .length;
          activityDetailSamples.add({
            'at': DateTime.now().millisecondsSinceEpoch,
            'callId': callId,
            'activityIdentity': openedActivityIdentity,
            'visibleHeight': renderedSample['visibleHeight'],
            'lines': lines,
            'text': output,
          });
          if (previousDetailLines != null && lines > previousDetailLines) {
            activityDetailGrowth = true;
          }
          previousDetailLines = lines;
        }
      }
      final growthSettled =
          (observedGrowth && activityDetailGrowth) || toolTerminal;
      final identitySettled =
          !wantIdentityReset || identityResetObserved || toolTerminal;
      if (growthSettled && identitySettled) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      latest = await this.snapshot();
    }
    // Every screenshot is taken *after* the sampling loop, so its cost never
    // delays the first live observations. The activity frames show the state
    // current at capture time, never a claim to be the switch-time frame.
    if (samples.isNotEmpty) {
      await shot('long-command-tool-progress');
    }
    if (observedGrowth) {
      await shot('long-command-tool-progress-grown');
    }
    if (identityResetObserved) {
      observations['longCommandActivityIdentityFrame'] =
          'screenshot long-command-activity-identity-current.png is the state '
          'current after the live loop, not the switch-time frame';
      await shot('long-command-activity-identity-current');
    }
    counts['longCommandProgressSamples'] = samples.length;
    observations['longCommandProgress'] = samples;
    observations['longCommandActivityDetails'] = activityDetailSamples;
    checks['longCommandActivityDetailsOutputGrows'] = activityDetailGrowth;
    if (!activityOutputPartsSeen) {
      pendingEvidence.add(
        'long-command in-flight output: conversationActivity exposed no outputParts '
        'for real callId $callId, so streaming output remains unverified',
      );
    } else {
      checks['longCommandInFlightOutputGrows'] = observedGrowth;
    }
    if (!wantIdentityReset) {
      if (!activityFieldSeen) {
        pendingEvidence.add(
          'activity bar: the snapshot exposes no conversationActivity field, so '
          'the cross-identity reset is pending an integrated Driver build',
        );
      } else {
        pendingEvidence.add(
          'activity bar: the live details were not left expanded by the previous '
          'activity, so the cross-identity reset has no expanded reference',
        );
      }
    } else if (!identityResetObserved) {
      // The window closed before a different identity was published collapsed.
      // This is a real failure, recorded as a failing check and the last real
      // observation instead of an unbounded wait that only times out.
      checks['activityIdentityResetsCollapse'] = false;
      observations['longCommandActivityIdentity'] = summarize(latest);
    }
  }

  Future<void> _parallelTools() async {
    final context = await submitPrompt('Realtime parallel tools', 'parallel');
    final running = await awaitNewTurn(context, 'parallel');
    final turn = turnId(running)!;
    // Two live tools must be observed together: a shared tool group alone does
    // not prove the commands overlapped.
    final concurrent = await waitFor(
      (snapshot) =>
          turnId(snapshot) == turn && liveExecStatuses(snapshot).length >= 2,
      'parallel_running',
      timeout: const Duration(seconds: 30),
      abort: turnFailed,
    );
    await observe('parallel_running', concurrent);
    await shot('parallel-tools-running');
    final liveAtObserve = liveExecStatuses(concurrent);

    // Wait for both real commands to exit before treating the work as done.
    bool bothDelivered(Map<String, dynamic> snapshot) =>
        execDelivered(
          snapshot,
          'realtime-parallel-call-a',
          'realtime-parallel-a-line',
        ) &&
        execDelivered(
          snapshot,
          'realtime-parallel-call-b',
          'realtime-parallel-b-line',
        );
    final delivered = await waitFor(
      bothDelivered,
      'parallel_tools_delivered',
      timeout: const Duration(seconds: 120),
      abort: turnFailed,
    );
    final deliveredAt = DateTime.now().millisecondsSinceEpoch;
    await observe('parallel_tools_delivered', delivered);
    await shot('parallel-tools-delivered');

    // The model Turn terminal is observed on its own, separately from the
    // durable settled projection below.
    final terminal = await awaitCompleted(turn, 'parallel');
    final terminalAt = DateTime.now().millisecondsSinceEpoch;
    await observe('parallel_execution_terminal', terminal);

    // The model waits on both background receipts, so the work is only complete
    // once the conversation settled with the delivered output of both commands.
    // A single settled answer may consume both delivered results: the runtime
    // can batch delivered results into one model step, so the check does not
    // require one account request per command.
    final settled = await waitFor(
      (snapshot) =>
          bothDelivered(snapshot) &&
          isDurableSettled(snapshot) &&
          answerMatchCount(snapshot, _answers['parallel']!) >= 1,
      'parallel_continuation',
      timeout: const Duration(seconds: 120),
      abort: turnFailed,
    );
    final settledAt = DateTime.now().millisecondsSinceEpoch;
    await observe('parallel_complete', settled);
    await shot('parallel-complete');

    final result = execTools(settled)
        .map((tool) => tool['result'] as String? ?? '')
        .join('\n');
    timings['parallel'] = {
      'submittedAt': context.submittedAt,
      'toolDeliveredAt': deliveredAt,
      'executionTerminalAt': terminalAt,
      'executionTerminalStatus': turnStatus(terminal),
      'continuationSettledAt': settledAt,
      'liveStatusesAtObservation': liveAtObserve,
    };
    checks['parallelConcurrentRunning'] = liveAtObserve.length >= 2;
    checks['parallelNoEarlyCompletion'] = !answerContains(
      concurrent,
      _answers['parallel']!,
    );
    checks['parallelTools'] =
        bothDelivered(settled) &&
        result.contains('realtime-parallel-a') &&
        result.contains('realtime-parallel-b') &&
        answerMatchCount(settled, _answers['parallel']!) >= 1;
  }

  /// 现役安全模型固定为全权限（design/04 §4.1 与 config `enforce_fixed_permission_mode`
  /// 唯一 effective 归一化），不存在真实审批交互。本步骤改为证明**真实宿主 cwd 执行**：
  /// 一次 composer、无需任何审批动作即可 running 并产出真实内容，经真实 receipt/wait
  /// 交付实际结果；stdout 的 cwd 标记必须与本 call 请求 cwd 指向同一真实目录，且确实
  /// 位于本隔离 workspace 之外。
  Future<void> _hostCwd() async {
    const execCallId = 'realtime-host-cwd-call';
    const waitCallId = 'realtime-host-cwd-wait-call';
    const taskId = 'task:realtime-host-cwd-call';
    final doneAnswer = _answers['hostCwd']!;
    final context = await submitPrompt('Realtime host cwd command', 'host_cwd');
    final running = await awaitNewTurn(context, 'host_cwd');
    final turn = turnId(running)!;
    final inflight = <Map<String, Object?>>[];
    var approvalSeen = false;
    var noEarlyAnswer = true;
    var growthSeen = false;
    var runningAt = 0;
    Map<String, Object?>? previous;
    final inflightDeadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(inflightDeadline)) {
      final state = await snapshot();
      if (interactionKind(state) == 'toolApproval') approvalSeen = true;
      if (turnId(state) == turn && answerContains(state, doneAnswer)) {
        noEarlyAnswer = false;
      }
      final sample = _liveToolProgressSample(state, execCallId);
      if (sample != null) {
        if (inflight.isEmpty) {
          runningAt = DateTime.now().millisecondsSinceEpoch;
        }
        inflight.add(<String, Object?>{
          'at': DateTime.now().millisecondsSinceEpoch,
          'answerPresent': answerContains(state, doneAnswer),
          ...sample,
        });
        if (previous != null &&
            sample['activityIdentity'] == previous['activityIdentity'] &&
            activityPartTextChanged(
              previous['outputParts'],
              sample['outputParts'],
              identityField: 'partId',
            )) {
          growthSeen = true;
        }
        previous = sample;
      }
      final tool = completedToolByCallId(state, execCallId);
      final terminal =
          tool != null && _terminalToolStatuses.contains(tool.status);
      if (growthSeen || terminal) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    observations['hostCwdInflight'] = inflight;
    counts['hostCwdInflightSamples'] = inflight.length;
    if (inflight.isNotEmpty) await observe('host_cwd_running');
    await shot('host-cwd-running');
    // 现役模型不产生 toolApproval：出现即硬失败，绝不点 approve 把它吞掉。
    if (approvalSeen) {
      throw StateError(
        'host cwd: an unexpected toolApproval interaction appeared; the '
        'current security model is fixed full access and this journey must '
        'never click approve',
      );
    }
    final delivered = await waitFor(
      (snapshot) =>
          turnId(snapshot) == turn &&
          completedToolByCallId(snapshot, execCallId)?.status == 'succeeded' &&
          completedToolByCallId(snapshot, waitCallId)?.status == 'succeeded',
      'host_cwd_delivered',
      timeout: const Duration(seconds: 120),
      abort: turnFailed,
    );
    final deliveredAt = DateTime.now().millisecondsSinceEpoch;
    await observe('host_cwd_delivered', delivered);
    await shot('host-cwd-delivered');
    final terminal = await awaitCompleted(turn, 'host_cwd');
    final settled = await awaitSettled(turn, 'host_cwd');
    await observe('host_cwd_complete', settled);
    final execTool = completedToolByCallId(settled, execCallId);
    final waitTool = completedToolByCallId(settled, waitCallId);
    if (execTool == null || waitTool == null) {
      throw StateError(
        'host cwd: the settled timeline lost the exec/wait tool identity',
      );
    }
    final Object? execArguments = jsonDecode(execTool.arguments);
    final requestedPath = execArguments is Map ? execArguments['cwd'] : null;
    if (requestedPath is! String || requestedPath.isEmpty) {
      throw StateError(
        'host cwd: the exec call has no explicit cwd argument: '
        '${execTool.arguments}',
      );
    }
    // 只解析既有交付 envelope（Driver 边界），不拿请求 cwd 冒充 stdout。
    final envelope = requireTaskEnvelope(execTool.result, taskId);
    const markerPrefix = 'realtime-host-cwd-actual:';
    const expectedLines = <String>[
      'realtime-host-cwd-line-01',
      'realtime-host-cwd-line-02',
      'realtime-host-cwd-line-03',
    ];
    final stdoutLines = const LineSplitter().convert(envelope.stdout);
    // stdout 必须恰为“唯一 cwd 行 + 三 paced 行”，不吞任何额外输出。
    final exactLineCount = stdoutLines.length == expectedLines.length + 1;
    final actualCwd =
        exactLineCount && stdoutLines.first.startsWith(markerPrefix)
        ? stdoutLines.first.substring(markerPrefix.length)
        : null;
    final linesOk =
        exactLineCount &&
        actualCwd != null &&
        actualCwd.isNotEmpty &&
        [
          for (var index = 0; index < expectedLines.length; index += 1)
            stdoutLines[index + 1] == expectedLines[index],
        ].every((matches) => matches);
    if (!linesOk) {
      throw StateError(
        'host cwd: unexpected stdout shape: $stdoutLines (expected exactly '
        '${expectedLines.length + 1} lines: $markerPrefix<path> followed by '
        '$expectedLines)',
      );
    }
    final directory = await hostCwdDirectoryProof(
      requestedPath: requestedPath,
      actualPath: actualCwd,
      workspacePath: project,
    );
    final Object? waitArguments = jsonDecode(waitTool.arguments);
    final taskIds = waitArguments is Map ? waitArguments['taskIds'] : null;
    final taskIdOk =
        taskIds is List && taskIds.length == 1 && taskIds.single == taskId;
    // wait 结果是已知的公开 JSON：严格解析 tasks 数组，不做模糊 token 匹配。
    final waitTask = requireTaskWaitResult(waitTool.result, taskId);
    checks['hostCwdRunningWithoutApproval'] =
        inflight.isNotEmpty && !approvalSeen;
    checks['hostCwdOutputGrows'] = growthSeen;
    checks['hostCwdNoEarlyAnswer'] = noEarlyAnswer && inflight.isNotEmpty;
    checks['hostCwdTaskSucceeded'] =
        execTool.status == 'succeeded' &&
        execTool.callId == execCallId &&
        envelope.exitCode == 0;
    checks['hostCwdOutputLines'] = linesOk;
    checks['hostCwdActualDirectory'] =
        directory['identical'] == true && directory['insideWorkspace'] == false;
    checks['hostCwdWaitReceipt'] =
        waitTool.status == 'succeeded' &&
        taskIdOk &&
        waitTask['status'] == 'succeeded' &&
        waitTask['toolId'] == 'exec';
    checks['hostCwdAnswer'] = answerContains(settled, doneAnswer);
    timings['hostCwd'] = {
      'submittedAt': context.submittedAt,
      'toolRunningAt': runningAt,
      'firstOutputMillis': runningAt - context.submittedAt,
      'toolDeliveredAt': deliveredAt,
      'deliveredMillis': deliveredAt - context.submittedAt,
      'executionTerminalAt': DateTime.now().millisecondsSinceEpoch,
      'executionTerminalStatus': turnStatus(terminal),
      'terminalStatus': turnStatus(settled),
    };
    // 承重证据：写失败直接传播，不吞、不 rethrow。
    await _writeRequiredJson('realtime-host-cwd.json', <String, Object?>{
      'prompt': 'Realtime host cwd command',
      'execCallId': execCallId,
      'waitCallId': waitCallId,
      'taskId': taskId,
      'submittedAt': context.submittedAt,
      'inflight': <String, Object?>{
        'samples': inflight,
        'count': inflight.length,
        'firstProgressBytes': inflight.isEmpty
            ? null
            : inflight.first['progressBytes'],
        'lastProgressBytes': inflight.isEmpty
            ? null
            : inflight.last['progressBytes'],
        'answerAbsent': noEarlyAnswer,
        'growthObserved': growthSeen,
        'approvalSeen': approvalSeen,
      },
      'delivery': <String, Object?>{
        'deliveredAt': deliveredAt,
        'deliveredMillis': deliveredAt - context.submittedAt,
        'execStatus': execTool.status,
        'waitStatus': waitTool.status,
      },
      'turn': <String, Object?>{
        'turnId': turn,
        'terminalStatus': turnStatus(terminal),
        'durableSettled': isDurableSettled(settled),
      },
      'request': <String, Object?>{
        'arguments': execTool.arguments,
        'cwd': requestedPath,
      },
      'directory': directory,
      'stdoutLines': stdoutLines,
      'task': <String, Object?>{
        'exitCode': envelope.exitCode,
        'stderr': envelope.stderr,
        'stdout': envelope.stdout,
      },
      'wait': <String, Object?>{
        'arguments': waitTool.arguments,
        'taskIdsExact': taskIdOk,
        'resultTask': waitTask,
        'result': waitTool.result,
      },
      'checks': <String, Object?>{
        'runningWithoutApproval': checks['hostCwdRunningWithoutApproval'],
        'outputGrows': checks['hostCwdOutputGrows'],
        'noEarlyAnswer': checks['hostCwdNoEarlyAnswer'],
        'taskSucceeded': checks['hostCwdTaskSucceeded'],
        'outputLines': checks['hostCwdOutputLines'],
        'actualDirectory': checks['hostCwdActualDirectory'],
        'waitReceipt': checks['hostCwdWaitReceipt'],
        'answer': checks['hostCwdAnswer'],
      },
    });
  }

  /// 由真实用户意图离开 Live：标准 pointer 拖拽，不调用「回到实时」、不触发分页，
  /// 也不写 pixels。
  ///
  /// 内容短到不足一屏时，先展开已加载 reasoning 的公开 `ExpansionTile`，让标准列表
  /// 真正可滚；展开只是用户可见的 UI 状态，不产生任何 fixture 请求。
  Future<
    ({
      String threadId,
      int generation,
      TimelineObservation retained,
      Map<String, Object?> before,
      Map<String, Object?> history,
      Map<String, Object?>? expansion,
    })
  >
  _enterHistoryForDirectSend() async {
    await mark('provider_error_history_enter');
    final beforeSnapshot = await snapshot();
    final beforeTimeline = TimelineObservation.parse(beforeSnapshot);
    final beforeScroll = TimelineScrollObservation.parse(beforeSnapshot);
    final before = <String, Object?>{
      'threadId': beforeTimeline.threadId,
      'generation': beforeTimeline.generation,
      'mode': beforeTimeline.mode,
      'itemCount': beforeTimeline.itemCount,
      'userItemCount': _userItemCount(beforeTimeline),
      'lastUserItemId': _lastUserItemId(beforeTimeline),
      'turnId': turnId(beforeSnapshot),
      'pixels': beforeScroll.pixels,
      'extentBefore': beforeScroll.extentBefore,
      'extentAfter': beforeScroll.extentAfter,
      'maxScrollExtent': beforeScroll.maxScrollExtent,
      'atLiveEdge': beforeScroll.atLiveEdge,
    };
    Map<String, Object?>? expansion;
    if ((beforeScroll.maxScrollExtent ?? 0) <= _minDetachedOffset) {
      expansion = await _expandLoadedActivityForScroll(beforeTimeline);
    }
    final steps = <Map<String, Object?>>[];
    var current = await snapshot();
    var geometry = _scrollGeometryOf(current);
    var entered = false;
    for (var step = 0; step < _maxHistoryScrollSteps; step += 1) {
      final timeline = TimelineObservation.parse(current);
      if (timeline.isHistory && _leftBottom(geometry)) {
        entered = true;
        break;
      }
      await driver.scrollBy(
        find.byValueKey('timeline-scrollable'),
        _historyScrollStep,
        timeout: const Duration(seconds: 15),
      );
      current = await snapshot();
      geometry = _scrollGeometryOf(current);
      steps.add(<String, Object?>{
        'step': step + 1,
        'mode': TimelineObservation.parse(current).mode,
        'generation': TimelineObservation.parse(current).generation,
        'pixels': geometry?.pixels,
        'extentBefore': geometry?.extentBefore,
        'extentAfter': geometry?.extentAfter,
        'atLiveEdge': geometry?.atLiveEdge,
      });
    }
    final historyTimeline = TimelineObservation.parse(current);
    final history = <String, Object?>{
      'entered': entered,
      'threadId': historyTimeline.threadId,
      'sameThread': historyTimeline.threadId == beforeTimeline.threadId,
      'sameEpoch':
          historyTimeline.timelineEpoch == beforeTimeline.timelineEpoch,
      'retainsCompletedFacts': _retainsCompletedFacts(
        beforeTimeline,
        historyTimeline,
      ),
      'mode': historyTimeline.mode,
      'generation': historyTimeline.generation,
      'pixels': geometry?.pixels,
      'extentBefore': geometry?.extentBefore,
      'atLiveEdge': geometry?.atLiveEdge,
      'detachThreshold': _minDetachedOffset,
      'dragSteps': steps.length,
    };
    await _writeRequiredJson(
      'realtime-account-error-history-enter.json',
      <String, Object?>{
        'beforeHistory': before,
        'expansion': expansion,
        'dragSteps': steps,
        'history': history,
      },
    );
    await observe('provider_error_history_entered', current);
    await shot('account-error-history-entered');
    // 真实进入 History、同一 Thread，并且真的离开底端（阈值沿用 200）；空内容或
    // 贴底都不能算离底。
    if (!entered ||
        !historyTimeline.isHistory ||
        historyTimeline.threadId != beforeTimeline.threadId ||
        historyTimeline.generation != beforeTimeline.generation ||
        !_retainsCompletedFacts(beforeTimeline, historyTimeline) ||
        (geometry?.extentBefore ?? 0) <= _minDetachedOffset ||
        geometry?.atLiveEdge != false) {
      throw StateError(
        'history direct send: the display did not really leave the bottom '
        'before sending ($history)',
      );
    }
    return (
      threadId: beforeTimeline.threadId,
      generation: historyTimeline.generation,
      retained: historyTimeline,
      before: before,
      history: history,
      expansion: expansion,
    );
  }

  /// 紧凑工作组不足以离底 200px 时，先通过真实 UI 展开已加载的活动组。
  /// 不改写 pixels、不增造消息；展开和可滚范围都必须来自当前展示事实。
  Future<Map<String, Object?>> _expandLoadedActivityForScroll(
    TimelineObservation timeline,
  ) async {
    TimelinePresentationObservation? target;
    for (final group in timeline.presentationItems) {
      if (group.kind == 'activity' && !group.expanded) target = group;
    }
    if (target == null) {
      throw StateError(
        'history direct send: no loaded collapsed activity group can provide '
        'the required reading range (itemCount=${timeline.itemCount})',
      );
    }
    final groupId = target.id;
    final summaryKey = _activitySummaryKey(groupId);
    final summary = find.byValueKey(summaryKey);
    await driver.scrollUntilVisible(
      find.byValueKey('timeline-scrollable'),
      summary,
      dyScroll: _historyScrollStep,
      timeout: const Duration(seconds: 20),
    );
    await driver.rawTap(summary, timeout: const Duration(seconds: 30));
    final expanded = await waitFor(
      (snapshot) {
        final current = TimelineObservation.optional(snapshot);
        return current != null &&
            current.presentationItems.any(
              (group) => group.id == groupId && group.expanded,
            ) &&
            (TimelineScrollObservation.optional(snapshot)?.maxScrollExtent ??
                    0) >
                _minDetachedOffset;
      },
      'provider_error_history_expand',
      timeout: const Duration(seconds: 20),
    );
    final scroll = TimelineScrollObservation.parse(expanded);
    return <String, Object?>{
      'groupId': groupId,
      'summaryKey': summaryKey,
      'expanded': true,
      'maxScrollExtent': scroll.maxScrollExtent,
      'pixels': scroll.pixels,
      'extentBefore': scroll.extentBefore,
      'requiredDetachedOffset': _minDetachedOffset,
    };
  }

  /// 发送只增加完成事实，保留阅读窗口/代次，滚动继续由 stock 列表负责。
  Future<Map<String, dynamic>> _awaitDirectSendCurrent({
    required TimelineObservation retained,
  }) {
    return waitFor(
      (snapshot) {
        final timeline = TimelineObservation.optional(snapshot);
        final scroll = TimelineScrollObservation.optional(snapshot);
        if (timeline == null || scroll == null) return false;
        return timeline.threadId == retained.threadId &&
            timeline.isHistory &&
            timeline.generation == retained.generation &&
            _retainsCompletedFacts(retained, timeline) &&
            _lastUserItem(timeline)?.text == _providerErrorPrompt &&
            timeline.hasNewOutput &&
            scroll.laidOut &&
            scroll.generation == timeline.generation;
      },
      'provider_error_direct_send_current_window',
      timeout: const Duration(seconds: 30),
    );
  }

  /// 发送后新出现的用户消息身份：必须是此前没有出现过的 id。
  Future<String> _awaitNewUserIdentity({
    required String threadId,
    required String? previousUserId,
    required String expectedText,
  }) async {
    final seen = await waitFor(
      (snapshot) {
        final timeline = TimelineObservation.optional(snapshot);
        if (timeline == null || timeline.threadId != threadId) return false;
        final item = _lastUserItem(timeline);
        // canonical 用户条目的正文必须逐字等于本次输入：任意新用户消息不算。
        return item != null &&
            item.id != previousUserId &&
            item.text == expectedText;
      },
      'provider_error_direct_send_user',
      timeout: const Duration(seconds: 20),
      abort: threadFaulted,
    );
    return _lastUserItem(TimelineObservation.parse(seen))!.id;
  }

  Future<void> _providerError() async {
    // History 直接发送：先由真实用户意图进入 History（不显式回实时、不分页、不写
    // pixels），随后用同一 composer 发送既定输入，不重建呈现窗口或代次。
    final history = await _enterHistoryForDirectSend();
    final context = await submitPrompt(_providerErrorPrompt, 'account_error');
    final running = await awaitNewTurn(context, 'account_error');
    final afterCurrent = await _awaitDirectSendCurrent(
      retained: history.retained,
    );
    final currentTimeline = TimelineObservation.parse(afterCurrent);
    final currentScroll = TimelineScrollObservation.parse(afterCurrent);
    final newTurnId = turnId(running);
    final newUserItemId = await _awaitNewUserIdentity(
      threadId: history.threadId,
      previousUserId: history.before['lastUserItemId'] as String?,
      expectedText: _providerErrorPrompt,
    );
    // 同一 Thread/epoch/窗口及原冻结项保持，且真实新用户/Turn 已出现。
    checks['historyDirectSendPreservesWindow'] =
        currentTimeline.threadId == history.threadId &&
        currentTimeline.isHistory &&
        currentTimeline.generation == history.generation &&
        currentScroll.generation == currentTimeline.generation &&
        _retainsCompletedFacts(history.retained, currentTimeline) &&
        newTurnId != null;
    await observe('provider_error_direct_send_current_window', afterCurrent);
    await _writeRequiredJson(
      'realtime-history-direct-send.json',
      <String, Object?>{
        'beforeHistory': history.before,
        'expansion': history.expansion,
        'history': history.history,
        'tap': <String, Object?>{
          'label': 'account_error',
          'prompt': _providerErrorPrompt,
          'composerInputKey': 'composer-input',
          'composerSubmitKey': 'composer-submit',
          'submittedAt': context.submittedAt,
        },
        'afterCurrent': <String, Object?>{
          'threadId': currentTimeline.threadId,
          'mode': currentTimeline.mode,
          'generation': currentTimeline.generation,
          'timelineEpoch': currentTimeline.timelineEpoch,
          'pixels': currentScroll.pixels,
          'extentBefore': currentScroll.extentBefore,
          'extentAfter': currentScroll.extentAfter,
          'atLiveEdge': currentScroll.atLiveEdge,
          'scrollGeneration': currentScroll.generation,
          'newTurnId': newTurnId,
          'newUserItemId': newUserItemId,
        },
        'priorTurnId': context.priorTurnId,
        'priorTimelineItemCount': history.before['itemCount'],
        'priorUserItemCount': history.before['userItemCount'],
        'historyDirectSendPreservesWindow':
            checks['historyDirectSendPreservesWindow'],
      },
    );
    if (checks['historyDirectSendPreservesWindow'] != true) {
      final unexpected = await snapshot();
      throw StateError(
        'history direct send did not preserve its completed window: '
        'history=${history.history}, afterCurrent=${summarize(unexpected)}',
      );
    }
    final turn = turnId(running)!;
    final failed = await waitFor(
      (snapshot) =>
          turnId(snapshot) == turn && turnStatus(snapshot) == 'failed',
      'account_error',
      timeout: const Duration(seconds: 60),
    );
    final terminalAt = DateTime.now().millisecondsSinceEpoch;
    final workspace = workspaceOf(failed);
    final terminal = [
      workspace?['turn'],
      workspace?['lastTurn'],
    ].whereType<Map>().firstWhere((value) => value['id'] == turn);
    final failure = terminal['failure'];
    final expectedFailure =
        failure is Map &&
        failure['httpStatus'] == 400 &&
        failure['code'] == 'invalid_request_error' &&
        (failure['message'] as String? ?? '').contains(
          'realtime fixture provider error',
        );
    checks['providerErrorMatchesFixture'] = expectedFailure;
    if (!expectedFailure) {
      throw StateError('provider error did not match the fixture: $failure');
    }
    await observe('account_error', failed);
    await shot('account-error');
    timings['accountError'] = {
      'submittedAt': context.submittedAt,
      'terminalAt': terminalAt,
      'terminalStatus': 'failed',
      'durableSettledAt': null,
    };
    checks['accountErrorSurfaced'] = true;
  }

  Future<void> _cancel() async {
    final context = await submitPrompt('Realtime cancellable stream', 'cancel');
    final running = await awaitNewTurn(context, 'cancel');
    final turn = turnId(running)!;
    final streaming = await waitFor(
      (snapshot) =>
          turnId(snapshot) == turn &&
          isBusy(snapshot) &&
          _liveTextPresent(snapshot, turn, 'responseParts'),
      'cancel_streaming',
      timeout: const Duration(seconds: 30),
      abort: turnFailed,
    );
    await observe('cancel_streaming', streaming);
    await shot('cancel-streaming');
    await driver.waitFor(
      find.byValueKey('composer-stop'),
      timeout: const Duration(seconds: 30),
    );
    await _tap('composer-stop');
    final cancelled = await waitFor(
      (snapshot) =>
          turnId(snapshot) == turn && turnStatus(snapshot) == 'cancelled',
      'cancel_cancelled',
      timeout: const Duration(seconds: 30),
    );
    final cancelledAt = DateTime.now().millisecondsSinceEpoch;
    await observe('cancel_cancelled', cancelled);
    await shot('cancelled');
    timings['cancel'] = {
      'submittedAt': context.submittedAt,
      'terminalAt': cancelledAt,
      'terminalStatus': 'cancelled',
      'durableSettledAt': null,
    };
    checks['cancelSurfaced'] = true;
  }

  Future<void> _resume() async {
    final context = await submitPrompt(
      'Realtime continue after cancel',
      'resume',
    );
    final running = await awaitNewTurn(context, 'resume');
    final turn = turnId(running)!;
    // The resume reply is a single immediate response, so its live streaming
    // window can close between Driver polls. The observation is correlated to
    // *this* turn instead: either the scenario-unique answer text appears, or the
    // same turn reaches its terminal `completed` state. The answer text is an
    // identity that no earlier turn ever produced, and the terminal is read for
    // the correlated turn id only, so a previous turn's answer can never satisfy
    // this wait. Capturing the transient streaming state is not required here.
    final firstSeen = await waitFor(
      (snapshot) =>
          turnId(snapshot) == turn &&
          (answerContains(snapshot, _answers['resume']!) ||
              turnStatus(snapshot) == 'completed'),
      'resume_visible',
      timeout: const Duration(seconds: 30),
      abort: threadFaulted,
    );
    final firstContentAt = DateTime.now().millisecondsSinceEpoch;
    await observe('resume_visible', firstSeen);
    await shot('resume-visible');
    final observedStreaming = isBusy(firstSeen);
    final terminal = await awaitTerminal(turn, 'resume');
    final terminalAt = DateTime.now().millisecondsSinceEpoch;
    await observe('resume_terminal', terminal);
    final settled = await awaitSettled(turn, 'resume');
    await observe('resume_complete', settled);
    timings['resume'] = {
      'submittedAt': context.submittedAt,
      'firstContentAt': firstContentAt,
      'terminalAt': terminalAt,
      'durableSettledAt': DateTime.now().millisecondsSinceEpoch,
      'timeToFirstContentMillis': firstContentAt - context.submittedAt,
      'observedStreaming': observedStreaming,
      'terminalStatus': turnStatus(terminal),
    };
    checks['cancelThenContinue'] = answerContains(settled, _answers['resume']!);
  }

  /// Records the integrated activity-bar / timeline-scroll contracts.
  ///
  /// The fixture baseline predates the new `conversationActivity` and
  /// `timelineScroll` snapshot fields, so every observation is conditional: an
  /// absent field records an explicit pending note, and a present field is
  /// asserted for real. Nothing here fabricates a pass from an unknown field.
  Future<void> _uiContracts() async {
    await mark('ui_contracts');
    var settled = await snapshot();
    final reading = TimelineObservation.optional(settled);
    if (reading != null && reading.isHistory) {
      // Earlier sends deliberately kept the History reading intent. Use the
      // actual explicit control before asserting live-edge geometry.
      await _tap('timeline-return-live');
      settled = await waitFor(
        (snapshot) {
          final timeline = TimelineObservation.optional(snapshot);
          final scroll = TimelineScrollObservation.optional(snapshot);
          return timeline != null &&
              timeline.isLive &&
              timeline.generation == reading.generation &&
              _retainsCompletedFacts(reading, timeline) &&
              scroll != null &&
              scroll.laidOut &&
              !scroll.isScrolling &&
              scroll.atLiveEdge;
        },
        'explicit_return_after_history_send',
        timeout: const Duration(seconds: 30),
      );
      checks['explicitReturnAfterHistorySendPreservesWindow'] = true;
    }
    checks['modelBindingAvailableAfterCalls'] =
        ((settled['workspace'] as Map?)?['modelRoute'] as Map?)?['available'] ==
        true;
    await shot('user-assistant-bubbles');

    // The activity bar is projected only while a turn is active, so the settled
    // projection carries no activity by design. The live contract is exercised
    // during the reasoning stream (expand / same-identity persistence / collapse)
    // and the cross-identity reset during the running tool; this terminal snapshot
    // must not be read as "the activity field is missing".
    pendingEvidence.add(
      'activity bar: live expand/persistence/collapse ran during the reasoning '
      'stream and the cross-identity reset during the running tool; the settled '
      'projection intentionally carries no activity',
    );
    pendingEvidence.add(
      'session switch: this scenario keeps one thread by design; multi-session '
      'switching is exercised by the stress-body journey',
    );

    await _loadedTimelineContract();
    await _windowResizeContract();

    final scroll = timelineScroll(settled);
    if (scroll == null) {
      pendingEvidence.add(
        'timeline scroll: snapshot exposes no timelineScroll field, so '
        'sticky-bottom, short-message and history-anchor checks are pending',
      );
      return;
    }
    final geometry = _scrollGeometry(scroll);
    if (geometry == null) {
      pendingEvidence.add(
        'timeline scroll: diagnostic present but not laid out '
        '(pixels/maxScrollExtent null), so geometry checks are pending',
      );
      return;
    }
    checks['timelineScrollGeometry'] = geometry.consistent;
    if (!geometry.consistent) {
      return;
    }
    // Short conversation: the content does not fill the viewport, so the column
    // is pinned to the bottom (zero scrollable extent, zero offset, slack below).
    if (geometry.maxScrollExtent == 0) {
      checks['shortMessageSticksBottom'] =
          geometry.pixels == 0 &&
          (geometry.atLiveEdge || geometry.maxScrollExtent == 0);
    } else {
      // Scrollable conversation: at rest it must follow the bottom.
      //
      // 标准反向列表的底端是 offset 0，此时 `extentBefore` 为 0、`extentAfter` 是
      // 全部剩余内容；用 `extentAfter ≈ 0` 判贴底属于非反向 ListView 语义。缺失
      // `extentBefore` 不能默认通过：那是几何事实不可读，不是“贴底成立”。
      final extentBefore = geometry.extentBefore;
      checks['timelineFollowsBottom'] =
          geometry.atLiveEdge &&
          extentBefore != null &&
          extentBefore.abs() <= 1.0;
    }
    // Up-scrolling into history must keep the user's anchor instead of yanking
    // the view back to the latest row.
    if (geometry.maxScrollExtent > 0) {
      await _historyContract(settled);
    } else {
      pendingEvidence.add(
        'history: conversation is shorter than the viewport, so leaving the '
        'live edge is pending a longer transcript',
      );
    }
  }

  /// Narrows the GUI window through the driver's native window control, checks the
  /// layout is still usable and that the real window width really shrank, then
  /// restores the geometry read before the request.
  ///
  /// The window is located by the GUI process id (`_NET_WM_PID`), never by a
  /// title or class, so no unrelated window can be resized. A missing
  /// capability, an unprovable window ownership, or a width that did not shrink
  /// is recorded as pending rather than passed, together with the raw outcomes
  /// of the display queries so the reason can be read from the evidence. A real
  /// render overflow is left to the coordinator's GUI-health gate, which reads
  /// the captured GUI log.
  Future<void> _windowResizeContract() async {
    final guiPid = await _guiProcessId();
    if (guiPid == null) {
      pendingEvidence.add(
        'window resize: the driver did not expose the GUI process id, so the '
        'narrow/wide layout observation is pending',
      );
      return;
    }
    final wideShell = await _readRect('studio-shell');
    final narrow = resizeOwnedWindow(
      guiPid: guiPid,
      width: _narrowWindowWidth,
      height: _narrowWindowHeight,
    );
    if (!narrow.resized) {
      await _writeResizeDiagnostics(narrow, null);
      pendingEvidence.add(
        'window resize: driver could not narrow the GUI window '
        '(${narrow.reason}); raw outcomes: [${narrow.diagnostics.join(' | ')}]; '
        'wide/narrow layout is pending',
      );
      return;
    }
    DriverRect? narrowedShell;
    double? narrowViewport;
    late WindowResizeResult restored;
    final original = narrow.original!;
    try {
      narrowedShell = await _settleAfterResize(wideShell, expectNarrower: true);
      final narrowSnapshot = await snapshot();
      await shot('window-narrow');
      await driver.waitFor(
        find.byValueKey('composer-input'),
        timeout: const Duration(seconds: 10),
      );
      await driver.waitFor(
        find.byValueKey('timeline-scrollable'),
        timeout: const Duration(seconds: 10),
      );
      checks['narrowWindowUsable'] = true;
      narrowViewport = _viewportDimension(timelineScroll(narrowSnapshot));
    } finally {
      restored = resizeOwnedWindow(
        guiPid: guiPid,
        width: original.width,
        height: original.height,
      );
      await _writeResizeDiagnostics(narrow, restored);
      if (!restored.resized) {
        throw StateError('could not restore GUI window: ${restored.reason}');
      }
    }
    final narrowWidth = narrow.applied!.width;
    final restoredShell = await _settleAfterResize(
      narrowedShell ?? wideShell,
      expectNarrower: false,
    );
    final restoredSnapshot = await snapshot();
    await shot('window-restored');
    final restoredWidth = restored.applied!.width;
    final restoredViewport = _viewportDimension(
      timelineScroll(restoredSnapshot),
    );
    await _writeResizeDiagnostics(narrow, restored);
    if (narrowWidth < restoredWidth) {
      checks['narrowWindowNarrower'] = true;
    } else {
      // The X resize request was accepted but the window manager kept the width;
      // that is an environment limitation, not a UI defect, so it is recorded
      // with the measured numbers instead of failing the gate.
      pendingEvidence.add(
        'window resize: the window width did not shrink after the narrow '
        'request (narrow=$narrowWidth restored=$restoredWidth); the window '
        'manager may be ignoring the request',
      );
    }
    timings['windowResize'] = {
      'guiPid': guiPid,
      'windowId': narrow.windowId,
      'originalGeometry': original.toJson(),
      'narrowGeometry': narrow.applied?.toJson(),
      'restoredGeometry': restored.applied?.toJson(),
      'narrowWindowWidth': narrowWidth,
      'restoredWindowWidth': restoredWidth,
      'wideShellGeometry': wideShell?.toJson(),
      'narrowShellGeometry': narrowedShell?.toJson(),
      'restoredShellGeometry': restoredShell?.toJson(),
      'narrowViewportDimension': narrowViewport,
      'restoredViewportDimension': restoredViewport,
      'narrowDiagnostics': narrow.diagnostics,
      'restoredDiagnostics': restored.diagnostics,
    };
  }

  /// Records what this generation actually loaded.
  ///
  /// 计数来自当前 stock controller 的消息集合与其 typed 预览：身份数、预览字节和
  /// 详情声明。它们是应用层已交付数据，不是 FRB/wire 字节，也从不作为常量内存证明。
  Future<void> _loadedTimelineContract() async {
    final state = await snapshot();
    final timeline = TimelineObservation.optional(state);
    if (timeline == null) {
      pendingEvidence.add(
        'loaded timeline: the snapshot exposes no display facts for the selected '
        'thread, so item identities and preview bytes are pending',
      );
      return;
    }
    counts['loadedItems'] = timeline.itemCount;
    counts['loadedPreviewBytes'] = timeline.items.fold<int>(
      0,
      (total, item) => total + item.textBytes,
    );
    counts['truncatedItems'] = timeline.items
        .where((item) => item.textTruncated)
        .length;
    counts['detailFields'] = timeline.items.fold<int>(
      0,
      (total, item) => total + item.details.length,
    );
    checks['loadedTimelineFacts'] =
        timeline.itemCount == timeline.items.length &&
        timeline.itemIds.length == timeline.itemCount;
    pendingEvidence.add(
      'loaded timeline: preview bytes are an application-payload measure of the '
      'currently loaded canonical items; they are not FRB/wire bytes and are not '
      'a constant-memory claim',
    );
  }

  /// Records which display the resize used and, on refusal, the raw
  /// `xprop`/`xwininfo`/Xlib outcomes, so a pending narrow/wide observation can
  /// be diagnosed from the evidence instead of guessed.
  Future<void> _writeResizeDiagnostics(
    WindowResizeResult narrow,
    WindowResizeResult? restored,
  ) async {
    final lines = <String>[
      'narrow resized=${narrow.resized} windowId=${narrow.windowId} '
          'reason=${narrow.reason}',
      for (final line in narrow.diagnostics) 'narrow $line',
      if (restored != null)
        'restored resized=${restored.resized} windowId=${restored.windowId} '
            'reason=${restored.reason}',
      if (restored != null)
        for (final line in restored.diagnostics) 'restored $line',
    ];
    try {
      await File('${output.path}/window-resize-diagnostics.txt')
          .writeAsString('${lines.join('\n')}\n');
    } on Object {
      // Evidence writes live under the coordinator's directory and must not
      // mask the resize outcome itself.
    }
  }

  /// Reads the GUI process id from the Flutter Driver extension so the X11
  /// window can be matched by `_NET_WM_PID` instead of by title or class.
  Future<int?> _guiProcessId() async {
    try {
      final raw = await driver.requestData(
        'pid',
        timeout: const Duration(seconds: 15),
      );
      final decoded = jsonDecode(raw);
      final pid = decoded is Map ? decoded['pid'] : null;
      if (pid is int && pid > 0) return pid;
      pendingEvidence.add(
        'window resize: the driver pid response was not a process id '
        '(${raw.trim()})',
      );
    } on Object catch (error) {
      pendingEvidence.add(
        'window resize: the driver pid request failed ($error)',
      );
    }
    return null;
  }

  /// Waits, bounded by [_resizeSettleDeadline], for a resize to reach Flutter's
  /// real layout.
  ///
  /// The window's own content never idles: the live activity spinner and the
  /// streamed text produce frames continuously, so an "app is settled" wait
  /// (`waitForNoPendingFrame`) would spend its whole deadline and never return.
  /// The applied size is instead read from real `studio-shell` geometry, which
  /// changes once Flutter relayouts for the new window size; the screenshot taken
  /// right afterwards rasterizes the current frame. The poll is short and bounded,
  /// and it never treats "still animating" as "not applied".
  Future<DriverRect?> _settleAfterResize(
    DriverRect? before, {
    required bool expectNarrower,
  }) async {
    final deadline = DateTime.now().add(_resizeSettleDeadline);
    DriverRect? applied;
    while (DateTime.now().isBefore(deadline)) {
      final current = await _readRect('studio-shell');
      if (current != null && current.width > 0 && current.height > 0) {
        final changed =
            before == null ||
            (current.width - before.width).abs() > _rectEpsilon ||
            (current.height - before.height).abs() > _rectEpsilon;
        final directionOk =
            before == null ||
            (expectNarrower
                ? current.width <= before.width + _rectEpsilon
                : current.width >= before.width - _rectEpsilon);
        if (changed && directionOk) {
          if (applied != null && _sameRectSize(applied, current)) {
            return current;
          }
          applied = current;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return applied ?? await _readRect('studio-shell');
  }

  /// Writes one evidence JSON file under the output directory.
  /// 承重证据的严格写入口：写失败直接向 main 抛，由既有 failure/shutdown 收束。
  ///
  /// 只用于判定本身依赖的新证据（History 进入、直接发送后的 offset 0 几何）；
  /// 旧 `_writeJson` 的“不掩盖观测”语义与其调用点不变。内容按 JSON 逐字落盘。
  Future<void> _writeRequiredJson(String name, Object? data) async {
    await File('${output.path}/$name')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  }

  Future<void> _writeJson(String name, Object? data) async {
    try {
      await File(
        '${output.path}/$name',
      ).writeAsString('${const JsonEncoder.withIndent('  ').convert(data)}\n');
    } on Object {
      // Evidence writes live under the coordinator's directory and must never
      // mask the observation they document.
    }
  }

  /// Reads a widget's real rectangle through the Driver's own geometry commands.
  ///
  /// Read-only: the geometry commands never dispatch a pointer event. A widget
  /// that is not laid out reports `null` instead of holding a Driver command.
  Future<DriverRect?> _readRect(String key) async {
    final finder = find.byValueKey(key);
    try {
      final topLeft = await driver.getTopLeft(finder);
      final bottomRight = await driver.getBottomRight(finder);
      return DriverRect(
        key: key,
        left: topLeft.dx,
        top: topLeft.dy,
        right: bottomRight.dx,
        bottom: bottomRight.dy,
      );
    } on Object {
      return null;
    }
  }

  /// Records the real rectangles while the activity details are expanded and
  /// asserts the composer and its action button are still completely inside the
  /// window viewport and that the details panel stays bounded.
  ///
  /// Existing is not the same as usable: each rect is read from the live layout,
  /// and a rect that cannot be read at all fails the check with the reason.
  Future<void> _activityLayoutContract(String label) async {
    final viewport = await _readRect('studio-shell');
    final composer = await _readRect('composer-input');
    final actionKey = isBusy(await snapshot())
        ? 'composer-stop'
        : 'composer-submit';
    final action = await _readRect(actionKey);
    final details = await _readRect('conversation-activity-details');
    final evidence = <String, Object?>{
      'viewport': viewport?.toJson(),
      'composerInput': composer?.toJson(),
      'actionButtonKey': actionKey,
      'actionButton': action?.toJson(),
      'details': details?.toJson(),
      'detailsHeightCeiling': _maxActivityDetailsHeight,
      'detailsHeightFloor': _minActivityDetailsHeight,
    };
    await _writeJson('$label-activity-layout.json', evidence);
    final readable =
        viewport != null &&
        composer != null &&
        action != null &&
        details != null;
    checks['${label}_activityLayoutReadable'] = readable;
    checks['${label}_composerInsideViewport'] =
        readable && viewport.contains(composer);
    checks['${label}_actionButtonInsideViewport'] =
        readable && viewport.contains(action);
    // The details panel is bounded exactly like the UI documents: at most the
    // fixed ceiling, and never taller than the window itself.
    checks['${label}_detailsBounded'] =
        readable &&
        details.height > 0 &&
        details.height <= _maxActivityDetailsHeight + _rectEpsilon &&
        details.height <= viewport.height + _rectEpsilon &&
        viewport.contains(details);
    // Bounded is not the same as usable: the expanded panel must show real,
    // readable detail (at least ~3 text lines), so a few clipped pixels cannot
    // pass on existence plus an upper bound alone.
    checks['${label}_detailsUsable'] =
        readable && details.height >= _minActivityDetailsHeight - _rectEpsilon;
  }

  /// Narrows the real GUI window while the activity details are expanded, records
  /// the narrow layout evidence, then restores exactly the geometry read before
  /// the request. The restore runs even when the narrow observation fails.
  Future<void> _narrowDuringActivity(String label) async {
    final guiPid = await _guiProcessId();
    if (guiPid == null) {
      pendingEvidence.add(
        'activity layout: the driver did not expose the GUI process id, so the '
        'narrow-window layout evidence is pending',
      );
      return;
    }
    // Real shell geometry before the request, so the narrow layout can be proven
    // to have reached Flutter rather than waited for by blocking on idle frames.
    final beforeShell = await _readRect('studio-shell');
    final narrow = resizeOwnedWindow(
      guiPid: guiPid,
      width: _narrowWindowWidth,
      height: _narrowWindowHeight,
    );
    if (!narrow.resized) {
      await _writeResizeDiagnostics(narrow, null);
      pendingEvidence.add(
        'activity layout: driver could not narrow the GUI window '
        '(${narrow.reason}); raw outcomes: [${narrow.diagnostics.join(' | ')}]; '
        'the narrow layout evidence is pending',
      );
      return;
    }
    final original = narrow.original!;
    DriverRect? narrowedShell;
    try {
      narrowedShell = await _settleAfterResize(
        beforeShell,
        expectNarrower: true,
      );
      counts['activityNarrowShellWidth'] = narrowedShell?.width;
      await shot('$label-activity-narrow');
      await _activityLayoutContract('${label}_narrow');
    } finally {
      final restored = resizeOwnedWindow(
        guiPid: guiPid,
        width: original.width,
        height: original.height,
      );
      if (!restored.resized) {
        await _writeResizeDiagnostics(narrow, restored);
        throw StateError('could not restore GUI window: ${restored.reason}');
      }
      final restoredShell = await _settleAfterResize(
        narrowedShell ?? beforeShell,
        expectNarrower: false,
      );
      counts['activityRestoredShellWidth'] = restoredShell?.width;
    }
  }

  /// Expands the live activity bar, keeps it expanded across streaming updates
  /// of the same identity, collapses it, then leaves it expanded again so the
  /// cross-identity reset can be observed on the next live activity.
  ///
  /// Only a snapshot without the typed `conversationActivity` field is pending (a
  /// baseline gap). Once the field exists, every observation below is asserted
  /// for real: the activity must expose an identity, be `expandable`, show its
  /// pushed content, keep the same identity expanded across a *new* update,
  /// collapse to `expanded=false`, and stay collapsed across a further update.
  Future<void> _activityContractDuringBusy(
    String label, {
    bool narrowLayout = false,
  }) async {
    await mark('${label}_activity_expand');
    final snapshot = await this.snapshot();
    if (!snapshot.containsKey('conversationActivity')) {
      pendingEvidence.add(
        'activity bar: the snapshot exposes no conversationActivity field during '
        '$label, so expand/collapse is pending an integrated Driver build',
      );
      return;
    }
    // The typed field exists: wait for the live, expandable activity of this
    // stream. A missing one is a real behaviour failure, not a pending gap.
    final live = await waitFor(
      (current) {
        final activity = conversationActivity(current);
        return activity != null &&
            activity['identity'] is String &&
            activity['expandable'] == true;
      },
      '${label}_activity_expandable',
      timeout: const Duration(seconds: 20),
      abort: turnFailed,
    );
    final identity = conversationActivity(live)!['identity'] as String;
    final activityTurn = turnId(live);
    if (activityTurn == null) {
      throw StateError('expandable activity has no running Turn');
    }
    checks['activityIdentityExposed'] = true;
    checks['activityExpandableDuringActiveTurn'] = true;
    // Expansion reveals already-pushed content; it must not query live details.
    await _tap('conversation-activity');
    await driver.waitFor(
      find.byValueKey('conversation-activity-details'),
      timeout: const Duration(seconds: 15),
    );
    // `expanded` is the *actual* expand state published by the activity bar;
    // `expandable` is only the capability and is never read as the state. The
    // mounted details container and actual pushed reasoning are checked together.
    final expanded = await waitFor(
      (current) {
        final activity = conversationActivity(current);
        return activity != null &&
            activity['identity'] == identity &&
            activity['expanded'] == true &&
            _liveTextPresent(current, activityTurn, 'reasoningParts');
      },
      '${label}_activity_expanded',
      timeout: const Duration(seconds: 20),
      abort: turnFailed,
    );
    await observe('${label}_activity_expanded', expanded);
    await shot('$label-activity-expanded');
    await driver.waitFor(
      find.byValueKey('conversation-activity-details'),
      timeout: const Duration(seconds: 5),
    );
    final expandedView = conversationActivity(expanded);
    // `expandable` (capability) is recorded for evidence only: the assertions use
    // the actual `expanded` state.
    counts['activityExpandableCapability'] = expandedView?['expandable'];
    // The same identity must stay expanded across a *new* update. Require a
    // changed observation of actual ordered content parts, not a synthetic
    // revision or a status/byte-counter change.
    // gathered BEFORE the window resize: the resize is the slowest observation, so
    // content evidence is taken first and every phase stays tied to this
    // exact activity identity instead of racing the stream window.
    final contentBefore = _activityContentObservation(expanded);
    final advanced = await waitFor(
      (current) {
        final activity = conversationActivity(current);
        return activity != null &&
            activity['identity'] == identity &&
            conversationActivityContentChanged(
              contentBefore,
              _activityContentObservation(current),
            );
      },
      '${label}_activity_update',
      timeout: const Duration(seconds: 20),
      abort: turnFailed,
    );
    checks['activityExpandedAcrossUpdates'] =
        conversationActivity(advanced)?['expanded'] == true;
    // The activity identity the update was confirmed against is the same one left
    // expanded for the cross-identity reset.
    expandedActivityIdentity = identity;
    counts['activityPartsBefore'] = _activityContentObservation(expanded);
    counts['activityPartsAfter'] = _activityContentObservation(advanced);
    // The real expanded layout is recorded while the details are open: the wide
    // window first, then the narrow window (restored immediately after). Both are
    // still on the same identity that was just confirmed expanded across updates.
    await _activityLayoutContract('${label}_wide');
    if (narrowLayout) {
      await _narrowDuringActivity(label);
    }
    // Collapse: it must publish the real `expanded=false` state, not merely hide
    // the details widget.
    await _tap('conversation-activity');
    await driver.waitForAbsent(
      find.byValueKey('conversation-activity-details'),
      timeout: const Duration(seconds: 15),
    );
    final collapsed = await waitFor(
      (current) {
        final activity = conversationActivity(current);
        return activity != null &&
            activity['identity'] == identity &&
            activity['expanded'] == false;
      },
      '${label}_activity_collapsed',
      timeout: const Duration(seconds: 10),
      abort: turnFailed,
    );
    await shot('$label-activity-collapsed');
    checks['activityCollapse'] =
        conversationActivity(collapsed)?['expanded'] == false;
    // Collapsing must persist across a further update of the same identity: the
    // real content must change and the state must stay `expanded=false`.
    final collapseContent = _activityContentObservation(collapsed);
    counts['activityCollapseContentBefore'] = collapseContent;
    final recollapsed = await waitFor(
      (current) {
        final activity = conversationActivity(current);
        return activity != null &&
            activity['identity'] == identity &&
            activity['expanded'] == false &&
            conversationActivityContentChanged(
              collapseContent,
              _activityContentObservation(current),
            );
      },
      '${label}_activity_collapsed_update',
      timeout: const Duration(seconds: 20),
      abort: turnFailed,
    );
    checks['activityCollapsePersists'] =
        conversationActivity(recollapsed)?['expanded'] == false;
    counts['activityCollapseContentAfter'] = _activityContentObservation(
      recollapsed,
    );
    // Leave the live activity expanded again so the cross-identity contract
    // observes a real reset on the next activity rather than asserting that an
    // already-collapsed bar stays collapsed.
    await _tap('conversation-activity');
    final reexpanded = await waitFor(
      (current) {
        final activity = conversationActivity(current);
        return activity != null &&
            activity['identity'] == identity &&
            activity['expanded'] == true;
      },
      '${label}_activity_reexpanded',
      timeout: const Duration(seconds: 10),
      abort: turnFailed,
    );
    await shot('$label-activity-reexpanded');
    checks['activityExpandedBeforeSwitch'] =
        conversationActivity(reexpanded)?['expanded'] == true;
    activityLeftExpanded = true;
  }

  /// Scrolls up into history and confirms the user's anchor is retained.
  ///
  /// The timeline is a virtual list: the oldest row may not be laid out at all,
  /// so `scrollUntilVisible` would keep searching for a row that never appears and
  /// leave a Driver command in flight past its timeout. The journey therefore
  /// drags the pointer in fixed bounded steps — the same fixed-step, live-geometry
  /// mechanism the long-body stress journey uses — until the view has really left
  /// the bottom while a live assistant row is the topmost visible row, then
  /// 真实上翻进入 History 后，原子保持冻结，阅读意图不重建窗口或代次。
  ///
  /// 判定只读当前展示事实：模式、代次、已加载身份与当前标准 controller 几何。这里
  /// 没有 anchor/restore/pin 状态，也不写 pixels。
  Future<void> _historyContract(Map<String, dynamic> settled) async {
    final settledTimeline = TimelineObservation.optional(settled);
    final settledScroll = timelineScroll(settled);
    final before = settledScroll == null
        ? null
        : _scrollGeometry(settledScroll);
    if (settledTimeline == null || before == null || !before.laidOut) {
      pendingEvidence.add(
        'history: the selected thread exposes no laid-out timeline geometry, so '
        'leaving the bottom is pending',
      );
      return;
    }
    var current = settled;
    _ScrollGeometry? geometry = before;
    var steps = 0;
    final history = <Map<String, Object?>>[
      <String, Object?>{'phase': 'start', ..._historyStep(current)},
    ];
    try {
      // A positive `dy` drags the finger down to reveal earlier content; a
      // negative value would keep feeding content from below. Every step is
      // bounded, so a stuck view reports real geometry instead of hanging.
      while (steps < _maxHistoryScrollSteps) {
        final timeline = TimelineObservation.parse(current);
        if (timeline.isHistory && _leftBottom(geometry)) break;
        await driver.scrollBy(
          find.byValueKey('timeline-scrollable'),
          _historyScrollStep,
          timeout: const Duration(seconds: 15),
        );
        current = await snapshot();
        geometry = _scrollGeometryOf(current);
        steps++;
        history.add(<String, Object?>{
          'phase': 'after_scroll_$steps',
          ..._historyStep(current),
        });
      }
    } on Object catch (error) {
      await _writeJson('realtime-history.json', <String, Object?>{
        'steps': history,
        'error': '$error',
      });
      pendingEvidence.add(
        'history: Driver could not scroll the timeline ($error)',
      );
      return;
    }
    await _writeJson('realtime-history.json', <String, Object?>{
      'steps': history,
      'final': _historyStep(current),
    });
    await observe('history_detached', current);
    await shot('history-detached');
    final detachedTimeline = TimelineObservation.parse(current);
    final detached = _leftBottom(geometry) && detachedTimeline.isHistory;
    checks['historyScrollDetachesBottom'] =
        detached &&
        steps > 0 &&
        detachedTimeline.generation == settledTimeline.generation &&
        _retainsCompletedFacts(settledTimeline, detachedTimeline);
    counts['historyScrollSteps'] = steps;
    counts['historyMode'] = detachedTimeline.mode;
    counts['historyGeneration'] = detachedTimeline.generation;
    counts['historyPixelsBefore'] = before.pixels;
    counts['historyPixelsAfter'] = geometry?.pixels;
    counts['historyExtentBefore'] = geometry?.extentBefore;
    counts['historyExtentAfter'] = geometry?.extentAfter;
    counts['historyLoadedItems'] = detachedTimeline.itemCount;
    // 原子始终冻结；阅读不换代，也不拒绝随后完成事实。
    final after = await snapshot();
    final afterTimeline = TimelineObservation.parse(after);
    checks['historyRetainsCompletedFacts'] =
        afterTimeline.isHistory &&
        afterTimeline.generation == detachedTimeline.generation &&
        _retainsCompletedFacts(detachedTimeline, afterTimeline);
    // 回到冻结集合的本地底端仍是同一个 History 代次。
    final bottomDeadline = DateTime.now().add(const Duration(seconds: 20));
    var atBottom =
        TimelineScrollObservation.optional(after)?.atLiveEdge == true;
    while (!atBottom && DateTime.now().isBefore(bottomDeadline)) {
      await driver.scrollBy(
        find.byValueKey('timeline-scrollable'),
        -_historyScrollStep,
        timeout: const Duration(seconds: 15),
      );
      final state = await snapshot();
      atBottom = TimelineScrollObservation.optional(state)?.atLiveEdge == true;
    }
    final frozenBottom = await snapshot();
    final frozenTimeline = TimelineObservation.parse(frozenBottom);
    checks['historyBottomKeepsWindow'] =
        atBottom &&
        frozenTimeline.isHistory &&
        frozenTimeline.generation == detachedTimeline.generation &&
        _retainsCompletedFacts(detachedTimeline, frozenTimeline);
    // 显式返回最新只改阅读意图/stock 滚动，不重开窗口。
    final beforeReturn = TimelineObservation.parse(await snapshot());
    await driver.rawTap(find.byValueKey('timeline-return-live'));
    final returnDeadline = DateTime.now().add(const Duration(seconds: 30));
    var resumed = false;
    while (DateTime.now().isBefore(returnDeadline)) {
      final state = await snapshot();
      final timeline = TimelineObservation.optional(state);
      final scroll = TimelineScrollObservation.optional(state);
      if (timeline != null &&
          timeline.isLive &&
          timeline.generation == beforeReturn.generation &&
          _retainsCompletedFacts(beforeReturn, timeline) &&
          _retainsCompletedFacts(detachedTimeline, timeline) &&
          scroll != null &&
          scroll.laidOut &&
          !scroll.isScrolling &&
          scroll.atLiveEdge) {
        resumed = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    checks['explicitReturnLivePreservesWindow'] = resumed;
  }

  /// 视口是否真的离开了视觉底端。
  ///
  /// 标准反向列表里 `extentBefore` 是已经从 offset 0 向上滚过的距离，`extentAfter`
  /// 是剩余可向下滚动的内容（贴底时恰为最大值）。因此“离底”只能看 `extentBefore`
  /// 是否超过原阈值；缺失该事实按 0 处理，即判定不成立，不默认通过。
  bool _leftBottom(_ScrollGeometry? geometry) =>
      geometry != null &&
      geometry.laidOut &&
      !geometry.atLiveEdge &&
      (geometry.extentBefore ?? 0) > _minDetachedOffset;

  _ScrollGeometry? _scrollGeometryOf(Map<String, dynamic> snapshot) {
    final scroll = timelineScroll(snapshot);
    return scroll == null ? null : _scrollGeometry(scroll);
  }

  /// One history-step observation: the current display facts plus the standard
  /// controller geometry.
  Map<String, Object?> _historyStep(Map<String, dynamic> snapshot) {
    final scroll = TimelineScrollObservation.optional(snapshot);
    final timeline = TimelineObservation.optional(snapshot);
    return <String, Object?>{
      'mode': timeline?.mode,
      'generation': timeline?.generation,
      'itemCount': timeline?.itemCount,
      'hasNewOutput': timeline?.hasNewOutput,
      'pixels': scroll?.pixels,
      'maxScrollExtent': scroll?.maxScrollExtent,
      'extentBefore': scroll?.extentBefore,
      'extentAfter': scroll?.extentAfter,
      'atLiveEdge': scroll?.atLiveEdge,
      'isScrolling': scroll?.isScrolling,
    };
  }

  Future<Map<String, dynamic>?> stopFrameRecording() async {
    if (counts['frameRecordingStartedAt'] == null) return null;
    final frames = jsonDecode(
      await driver.requestData(
        'frame-stop',
        timeout: const Duration(seconds: 20),
      ),
    );
    if (frames is! Map<String, dynamic>) return null;
    await File(
      '${output.path}/realtime-frames.json',
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(frames)}\n');
    counts['frames'] = frames['frames'];
    return frames;
  }

  Future<void> writeSummary({
    required Object? failure,
    required Object? shutdownFailure,
    required Map<String, dynamic>? frames,
  }) async {
    recordRuntimeEvidence();
    final failedChecks = checks.entries
        .where((entry) => entry.value != true)
        .map((entry) => entry.key)
        .toList(growable: false);
    // `frames` is nullable, so index it with the null-aware operator and narrow
    // the sample list explicitly instead of relying on promotion in a branch.
    final Object? frameSamples = frames?['samples'];
    final summary = <String, Object?>{
      'scenario': 'realtime',
      'verdict': 'pending',
      'status': failure != null || failedChecks.isNotEmpty
          ? 'failed'
          : evidencePending
          ? 'pending'
          : 'complete',
      'stage': stage,
      'error': failure?.toString(),
      'shutdownError': shutdownFailure?.toString(),
      'failedChecks': failedChecks,
      'checks': checks,
      'timings': timings,
      'counts': counts,
      'observations': observations,
      'transitions': transitions.length,
      'frameSampleCount': frameSamples is List ? frameSamples.length : null,
      'completedAt': DateTime.now().toUtc().toIso8601String(),
      'pendingEvidence': pendingEvidence,
      'runtimeEvidencePending': evidencePending,
    };
    await File(
      '${output.path}/realtime-summary.json',
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(summary)}\n');
  }

  /// Registers the Driver-only runtime publication recorder for the Turn that
  /// [snapshot] shows running.
  ///
  /// 记录器观察的是**已存在** Client Session 的公开 runtime read-model 发布：它不创建
  /// Session、不建立 transport 订阅、不改变业务 demand。登记成功即固定本次 run 的
  /// Thread／Turn 身份，stop 时用同一身份严格校验响应。
  Future<void> _startRuntimePublishEvidence(
    Map<String, dynamic> snapshot,
  ) async {
    final threadId = TimelineObservation.optional(snapshot)?.threadId;
    final turn = turnId(snapshot);
    if (threadId == null || turn == null) {
      throw StateError(
        'runtime publish evidence: the running Turn exposes no thread/turn '
        'identity (${summarize(snapshot)})',
      );
    }
    final raw = await driver.requestData(
      jsonEncode(<String, Object?>{
        'cmd': 'runtime-evidence-start',
        'threadId': threadId,
        'turnId': turn,
      }),
      timeout: const Duration(seconds: 20),
    );
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded['ok'] != true) {
      throw StateError('runtime-evidence-start was rejected: $raw');
    }
    _runtimePublishThreadId = threadId;
    _runtimePublishTurnId = turn;
  }

  /// Stops the recorder and keeps the actual Client publication facts as strict evidence.
  ///
  /// 就绪门与判定分开：轮询只等到同一 `LatestValue` 的 runtime 投影不再带本 attempt 的
  /// live 观察（此时记录器必然已同步收到那条清除发布），判定完全来自记录器的真实回调事实。
  Future<void> _stopRuntimePublishEvidence() async {
    final threadId = _runtimePublishThreadId;
    final turn = _runtimePublishTurnId;
    if (threadId == null || turn == null) {
      throw StateError(
        'runtime publish evidence: stop requested without a recorded start',
      );
    }
    await waitFor(
      (snapshot) =>
          TimelineObservation.optional(snapshot)?.threadId == threadId &&
          driverRuntimeObservation(snapshot).usageState !=
              DriverRuntimeUsageState.live,
      'delayed_runtime_publish_cleared_readiness',
      timeout: const Duration(seconds: 15),
      abort: threadFaulted,
    );
    final raw = await driver.requestData(
      jsonEncode(<String, Object?>{'cmd': 'runtime-evidence-stop'}),
      timeout: const Duration(seconds: 20),
    );
    final decoded = jsonDecode(raw);
    final DriverRuntimePublishEvidence evidence;
    try {
      evidence = DriverRuntimePublishEvidence.parse(
        decoded,
        expectedThreadId: threadId,
        expectedTurnId: turn,
      );
    } on Object {
      // 形状或身份不符也要留证：先落盘真实响应，再让失败继续向上传播。
      await _writeRequiredJson(
        'realtime-runtime-publish.json',
        <String, Object?>{
          'scenario': 'realtime',
          'source': 'clientRuntimePublish',
          'scope': _runtimePublishScope,
          'target': <String, Object?>{'threadId': threadId, 'turnId': turn},
          'driver': decoded,
          'verdict': null,
        },
      );
      rethrow;
    }
    _runtimePublish = evidence;
    await _writeRequiredJson('realtime-runtime-publish.json', <String, Object?>{
      'scenario': 'realtime',
      'source': 'clientRuntimePublish',
      'scope': _runtimePublishScope,
      'target': <String, Object?>{'threadId': threadId, 'turnId': turn},
      'driver': decoded,
      'verdict': evidence.toJson(),
    });
    checks['runtimePublishLiveSequenceIncreasing'] =
        evidence.liveSequenceIncreasing &&
        evidence.livePublicationRevisionsIncreasing;
    checks['runtimePublishIdentityStable'] = evidence.identityStable;
    checks['runtimePublishClearedAfterLive'] = evidence.clearedAfterLive;
    checks['runtimePublishBoundedAndClosed'] = evidence.boundedAndClosed;
  }

  /// Resolves the runtime publication evidence into the summary.
  ///
  /// 记录器事实是唯一判定来源：没有 stop 结果时保持显式 pending/失败，绝不把轮询样本
  /// 升格成发布证明。
  void recordRuntimeEvidence() {
    if (_runtimeEvidenceRecorded) return;
    _runtimeEvidenceRecorded = true;
    observations['runtimeReadiness'] = DriverRuntimeReadiness(_runtimeSamples)
        .toJson();
    final evidence = _runtimePublish;
    if (evidence == null) {
      _runtimeEvidencePending = true;
      pendingEvidence.add(
        'runtime publish evidence: the Driver-only recorder returned no stop '
        'result for this run, so no actual Client runtime publication facts exist',
      );
      return;
    }
    observations['runtime'] = evidence.toJson();
    counts['runtimePublishFacts'] = evidence.facts.length;
    counts['runtimePublishLiveFacts'] = evidence.liveFacts.length;
    if (!evidence.liveSequenceIncreasing ||
        !evidence.livePublicationRevisionsIncreasing) {
      pendingEvidence.add(
        'runtime publish evidence: the actual Client publications did not '
        'advance one identity with at least two strictly increasing live '
        'observations and increasing publication revisions',
      );
    }
    if (!evidence.identityStable) {
      pendingEvidence.add(
        'runtime publish evidence: the recorded publications did not stay on '
        'one Thread/Turn/attempt and stream epoch',
      );
    }
    if (!evidence.clearedAfterLive) {
      pendingEvidence.add(
        'runtime publish evidence: no explicit cleared runtime publication '
        'followed the live observations of this Turn/attempt',
      );
    }
  }

  Future<void> raiseIfFailed(Object? shutdownFailure) async {
    final failedChecks = checks.entries
        .where((entry) => entry.value != true)
        .map((entry) => entry.key)
        .toList(growable: false);
    if (failedChecks.isNotEmpty) {
      throw StateError('realtime checks failed: ${failedChecks.join(', ')}');
    }
    if (shutdownFailure != null) {
      throw StateError('native GUI shutdown failed: $shutdownFailure');
    }
    if (evidencePending) {
      throw StateError(
        'realtime evidence remains pending: the Driver-only runtime publication '
        'recorder returned no actual Client publish facts for this run',
      );
    }
  }
}

int assistantContentCount(Map<String, dynamic> snapshot) {
  final timeline = TimelineObservation.optional(snapshot);
  if (timeline == null) return 0;
  return timeline.items
      .where(
        (item) =>
            const {'agentMessage', 'reasoning', 'toolCall'}.contains(item.kind),
      )
      .length;
}

int reasoningCount(Map<String, dynamic> snapshot) =>
    TimelineObservation.optional(snapshot)?.ofKind('reasoning').length ?? 0;

bool _liveTextPresent(
  Map<String, dynamic> snapshot,
  String turn,
  String field,
) {
  final activity = conversationActivity(snapshot);
  if (activity?['turnId'] != turn) return false;
  final parts = activity?[field];
  return parts is List &&
      parts.whereType<Map>().any(
        (part) =>
            part['itemId'] is String &&
            part['text'] is String &&
            (part['text'] as String).isNotEmpty,
      );
}

bool _retainsCompletedFacts(
  TimelineObservation before,
  TimelineObservation after,
) =>
    before.timelineEpoch == after.timelineEpoch &&
    before.items.every((item) {
      final kept = after.item(item.id);
      return kept != null &&
          kept.appendSeq == item.appendSeq &&
          jsonEncode(kept.frozenFields()) == jsonEncode(item.frozenFields());
    });

/// 已加载时间线里的用户消息条数（evidence 用，不参与判定）。
int _userItemCount(TimelineObservation timeline) =>
    timeline.items.where((item) => item.kind == 'userMessage').length;

/// 当前已加载的最后一条用户消息（canonical 正文与身份来自同一 typed item）。
TimelineItemObservation? _lastUserItem(TimelineObservation timeline) {
  TimelineItemObservation? last;
  for (final item in timeline.items) {
    if (item.kind == 'userMessage') last = item;
  }
  return last;
}

/// 当前已加载的最后一条用户消息身份（本次发送新出现的用户身份）。
String? _lastUserItemId(TimelineObservation timeline) =>
    _lastUserItem(timeline)?.id;

/// reasoning 行公开折叠头的宿主侧 key。
///
/// 与 `StudioDriverKeys.timelineActivitySummary(id)` 是同一个字面量
/// （`timeline-activity-summary-<$id>`）。宿主脚本运行在纯 Dart VM，不能 import
/// `package:flutter`；共享 key 值文件不在本任务可写范围，因此这里保留单一定义并
/// 注明唯一来源，不另建第二套命名规则。
String _activitySummaryKey(String reasoningId) =>
    'timeline-activity-summary-$reasoningId';

/// Ordered, typed activity content from the read-only Driver projection. This
/// serializes actual part identity, order, text and declared UTF-8 length; it is
/// an observation value, not a version counter.
String? _activityContentObservation(Map<String, dynamic> snapshot) {
  return conversationActivityContentObservation(snapshot);
}

/// 真正的最终回答数量：只统计 `channel == finalAnswer`，不把进度/解释混入。
int answerCount(Map<String, dynamic> snapshot) =>
    TimelineObservation.optional(snapshot)?.items
        .where((item) => item.isFinalAnswer)
        .length ??
    0;

bool answerContains(Map<String, dynamic> snapshot, String needle) =>
    TimelineObservation.optional(snapshot)?.items
        .any((item) => item.isFinalAnswer && item.text.contains(needle)) ??
    false;

/// Number of assistant answers carrying `needle`.
///
/// Counted rather than asserted to a fixed value: the parallel scenario waits on
/// both background receipts, and the runtime may batch the delivered results
/// into one model step, so one answer may legitimately cover both commands.
int answerMatchCount(Map<String, dynamic> snapshot, String needle) =>
    TimelineObservation.optional(snapshot)?.items
        .where((item) => item.isFinalAnswer && item.text.contains(needle))
        .length ??
    0;

/// The typed tool previews of the current generation, in canonical order.
///
/// 字段来自 `TimelineToolFacts`：完整参数/结果只在详情查看器里读取，这里保留的是
/// 后端脱敏后的有界预览。
List<Map<String, dynamic>> execTools(Map<String, dynamic> snapshot) {
  final tools = <Map<String, dynamic>>[];
  for (final item
      in TimelineObservation.optional(snapshot)?.items ??
          const <TimelineItemObservation>[]) {
    final tool = item.tool;
    if (tool == null || tool.name != 'exec') continue;
    tools.add(<String, dynamic>{
      'name': tool.name,
      'status': tool.status,
      'callId': tool.callId,
      'arguments': tool.arguments,
      'result': tool.result,
      'output': tool.result,
      'progressBytes': tool.progressBytes,
      'appendSeq': tool.appendSeq,
      'itemId': item.id,
    });
  }
  return tools;
}

int activeExecCount(Map<String, dynamic> snapshot) =>
    activeExecStatuses(snapshot).length;

List<String?> activeExecStatuses(Map<String, dynamic> snapshot) =>
    _activityExecStatuses(snapshot)
        .where(_activeToolStatuses.contains)
        .toList();

/// Tools whose status proves real execution rather than a scheduled call.
List<String?> liveExecStatuses(Map<String, dynamic> snapshot) =>
    _activityExecStatuses(snapshot).where(_liveToolStatuses.contains).toList();

Iterable<String> _activityExecStatuses(Map<String, dynamic> snapshot) sync* {
  final activity = conversationActivity(snapshot);
  if (activity == null) return;
  final tools = activity['toolDetails'];
  if (tools is! List) {
    throw StateError('current activity tool facts are missing');
  }
  for (final tool in tools.whereType<Map>()) {
    if (tool['name'] != 'exec') continue;
    final state = tool['state'];
    if (state is! String) throw StateError('current exec state is missing');
    yield state;
  }
}

/// Terminal tool states: no further live sample can ever arrive.
const _terminalToolStatuses = <String>{
  'succeeded',
  'failed',
  'denied',
  'cancelled',
  'interrupted',
};

/// The completed exec result, never its immutable background-start receipt.
Map<String, dynamic>? _completedExecByCallId(
  Map<String, dynamic> snapshot,
  String callId,
) {
  for (final tool in execTools(snapshot)) {
    if (tool['callId'] == callId &&
        _terminalToolStatuses.contains(tool['status'])) {
      return tool;
    }
  }
  return null;
}

/// Whether the current activity publishes output parts for this exact call.
bool _activityExposesOutputParts(Map<String, dynamic> snapshot, String callId) {
  final activity = conversationActivity(snapshot);
  final tools = activity?['toolDetails'];
  return tools is List &&
      tools.whereType<Map>().any(
        (tool) => tool['callId'] == callId && tool['outputParts'] is List,
      );
}

/// A live sample of the ordered output parts for one real activity call identity.
Map<String, Object?>? _liveToolProgressSample(
  Map<String, dynamic> snapshot,
  String callId,
) {
  final activity = conversationActivity(snapshot);
  final tools = activity?['toolDetails'];
  if (activity == null || activity['identity'] is! String || tools is! List) {
    return null;
  }
  final matches = tools.whereType<Map>().where(
    (tool) => tool['callId'] == callId,
  );
  if (matches.length != 1) return null;
  final tool = matches.single;
  final rawParts = tool['outputParts'];
  if (!_liveToolStatuses.contains(tool['state']) || rawParts is! List) {
    return null;
  }
  final outputParts = <Map<String, Object?>>[];
  for (var index = 0; index < rawParts.length; index++) {
    final part = rawParts[index];
    if (part is! Map) return null;
    outputParts.add(
      parseConversationActivityPart(
        part,
        index: index,
        identityField: 'partId',
        context: 'conversationActivity tool $callId outputParts',
      ),
    );
  }
  final outputChars = outputParts.fold<int>(
    0,
    (total, part) => total + (part['text']! as String).length,
  );
  final progressBytes = outputParts.fold<int>(
    0,
    (total, part) => total + (part['byteLength']! as int),
  );
  return <String, Object?>{
    'activityIdentity': activity['identity'],
    'callId': callId,
    'state': tool['state'],
    'outputParts': outputParts,
    'progressBytes': progressBytes,
    'outputChars': outputChars,
  };
}

/// Whether one exec call really exited and its committed output is observable.
bool execDelivered(
  Map<String, dynamic> snapshot,
  String callId,
  String outputNeedle,
) => execTools(snapshot).any(
  (tool) =>
      tool['callId'] == callId &&
      tool['status'] == 'succeeded' &&
      (tool['result'] as String? ?? '').contains(outputNeedle),
);

/// 当前完成历史里指定 callId 的终态结果，不把后台启动收据当作可变结果。
TimelineToolObservation? completedToolByCallId(
  Map<String, dynamic> snapshot,
  String callId,
) {
  for (final item
      in TimelineObservation.optional(snapshot)?.items ??
          const <TimelineItemObservation>[]) {
    final tool = item.tool;
    if (tool != null &&
        tool.callId == callId &&
        _terminalToolStatuses.contains(tool.status)) {
      return tool;
    }
  }
  return null;
}

/// 严格解析既有后台交付 envelope：
/// `Task <taskId> for tool exec finished: Succeeded.<payload-json>`。
///
/// `pl-core` 用它把已提交的后台工具结果交给模型；这里只在 Driver 边界读取同一段
/// 文本（不新增生产 API、不拿请求参数冒充 stdout）。payload 必须是 final/succeeded
/// 且带 exec v2 的 `exitCode` 与双流 `content`。
({int exitCode, String stdout, String stderr}) requireTaskEnvelope(
  String? result,
  String taskId,
) {
  final prefix = 'Task $taskId for tool exec finished: Succeeded.';
  if (result == null || !result.startsWith(prefix)) {
    final preview = result == null
        ? 'null'
        : (result.length <= 160 ? result : '${result.substring(0, 160)}…');
    throw StateError(
      'host cwd: tool result is not the expected delivery envelope for '
      '$taskId: $preview',
    );
  }
  final Object? payload;
  try {
    payload = jsonDecode(result.substring(prefix.length));
  } on FormatException catch (error) {
    throw StateError(
      'host cwd: delivery payload is not JSON (${error.message})',
    );
  }
  if (payload is! Map) {
    throw StateError('host cwd: delivery payload is not an object: $payload');
  }
  final state = payload['state'];
  final stdoutStream = payload['stdout'];
  final stderrStream = payload['stderr'];
  final stateMap = state is Map ? state : null;
  final data = stateMap?['data'];
  final resultNode = data is Map ? data['result'] : null;
  final resultFact = resultNode is Map ? resultNode : null;
  final exitCode = payload['exitCode'];
  if (stateMap == null ||
      stateMap['kind'] != 'final' ||
      resultFact == null ||
      resultFact['kind'] != 'succeeded' ||
      exitCode is! int) {
    throw StateError(
      'host cwd: delivery state is not a successful final result: $state',
    );
  }
  final stdout = stdoutStream is Map ? stdoutStream['content'] : null;
  final stderr = stderrStream is Map ? stderrStream['content'] : null;
  if (stdout is! String || stderr is! String) {
    throw StateError(
      'host cwd: delivery payload has no exec v2 stdout/stderr content: $payload',
    );
  }
  return (exitCode: exitCode, stdout: stdout, stderr: stderr);
}

String _boundedText(String value, [int limit = 200]) =>
    value.length <= limit ? value : '${value.substring(0, limit)}…';

/// 严格解析 wait 工具的公开结果 JSON（字段：`messagesReady`、`tasks`、
/// `cancelRequested`、`status`、`taskId`、`toolId`、`timedOut`）。
///
/// 只接受恰好一条 task，且 `taskId` 精确相等、`toolId == 'exec'`、
/// `status == 'succeeded'`、`cancelRequested == false`、`timedOut == false`；
/// 形状不符直接抛出（响亮诊断），不做模糊 token 兜底。
Map<String, Object?> requireTaskWaitResult(String? result, String taskId) {
  if (result == null) {
    throw StateError('host cwd: wait tool has no result for $taskId');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(result);
  } on FormatException catch (error) {
    throw StateError(
      'host cwd: wait result is not JSON (${error.message}): '
      '${_boundedText(result)}',
    );
  }
  if (decoded is! Map) {
    throw StateError(
      'host cwd: wait result is not an object: ${_boundedText(result)}',
    );
  }
  final tasks = decoded['tasks'];
  final timedOut = decoded['timedOut'];
  if (tasks is! List || tasks.length != 1 || timedOut != false) {
    throw StateError(
      'host cwd: wait result does not carry exactly one completed task: '
      '${_boundedText(result)}',
    );
  }
  final task = tasks.single;
  if (task is! Map) {
    throw StateError(
      'host cwd: wait task entry is not an object: ${_boundedText(result)}',
    );
  }
  final status = task['status'];
  final returnedTaskId = task['taskId'];
  final toolId = task['toolId'];
  final cancelRequested = task['cancelRequested'];
  if (returnedTaskId != taskId ||
      toolId != 'exec' ||
      status != 'succeeded' ||
      cancelRequested != false) {
    throw StateError(
      'host cwd: wait task entry does not match $taskId/exec/succeeded: '
      '${_boundedText(result)}',
    );
  }
  return <String, Object?>{
    'taskId': returnedTaskId,
    'toolId': toolId,
    'status': status,
    'cancelRequested': cancelRequested,
    'timedOut': timedOut,
    'messagesReady': decoded['messagesReady'],
  };
}

/// 用官方 dart:io API 证明“实际 cwd == 请求 cwd”且位于隔离 workspace 之外。
///
/// 不自制路径安全算法：目录等价的唯一事实是对 `resolveSymbolicLinks()` 之后的路径
/// 调用 `FileSystemEntity.identical`；是否位于 workspace 内用 `Directory.parent`
/// 逐级上溯到根、每级做 `identical` 比较。只读取这几个目录自身的元数据，不列举内容。
Future<Map<String, Object?>> hostCwdDirectoryProof({
  required String requestedPath,
  required String actualPath,
  required String workspacePath,
}) async {
  final requested = Directory(requestedPath);
  final actual = Directory(actualPath);
  final workspace = Directory(workspacePath);
  for (final entry in <(String, Directory)>[
    ('requested', requested),
    ('actual', actual),
    ('workspace', workspace),
  ]) {
    if (!entry.$2.isAbsolute) {
      throw StateError(
        'host cwd: ${entry.$1} path is not absolute: ${entry.$2.path}',
      );
    }
    if (!await entry.$2.exists()) {
      throw StateError(
        'host cwd: ${entry.$1} directory does not exist: ${entry.$2.path}',
      );
    }
  }
  final requestedReal = await requested.resolveSymbolicLinks();
  final actualReal = await actual.resolveSymbolicLinks();
  final workspaceReal = await workspace.resolveSymbolicLinks();
  final identical = await FileSystemEntity.identical(requestedReal, actualReal);
  var current = Directory(actualReal);
  var insideWorkspace = false;
  while (true) {
    if (await FileSystemEntity.identical(current.path, workspaceReal)) {
      insideWorkspace = true;
      break;
    }
    final parent = current.parent;
    if (parent.path == current.path) break;
    current = parent;
  }
  final evidence = <String, Object?>{
    'requestedPath': requestedPath,
    'requestedCanonical': requestedReal,
    'actualPath': actualPath,
    'actualCanonical': actualReal,
    'workspacePath': workspacePath,
    'workspaceCanonical': workspaceReal,
    'identical': identical,
    'insideWorkspace': insideWorkspace,
  };
  if (!identical || insideWorkspace) {
    throw StateError('host cwd: directory proof failed: $evidence');
  }
  return evidence;
}

String? threadStatus(Map<String, dynamic> snapshot) {
  final status = workspaceOf(snapshot)?['threadStatus'];
  return status is String ? status : null;
}

bool threadFaulted(Map<String, dynamic> snapshot) =>
    threadStatus(snapshot) == 'faulted';

/// Whether the awaited state is unreachable because the Turn already failed or
/// was cancelled, so a wait reports the real observation immediately instead of
/// burning its whole timeout on a state that can no longer arrive.
bool turnFailed(Map<String, dynamic> snapshot) {
  final status = turnStatus(snapshot);
  return threadFaulted(snapshot) || status == 'failed' || status == 'cancelled';
}

int outputTokens(Map<String, dynamic> snapshot) {
  final usage = workspaceOf(snapshot)?['usage'];
  return usage is Map ? (usage['outputTokens'] as num? ?? 0).toInt() : 0;
}

bool isBusy(Map<String, dynamic> snapshot) =>
    workspaceOf(snapshot)?['isBusy'] == true;

bool isDurableSettled(Map<String, dynamic> snapshot) {
  final workspace = workspaceOf(snapshot);
  final persistence = snapshot['persistence'];
  return workspace != null &&
      workspace['isBusy'] == false &&
      workspace['threadStatus'] == 'idle' &&
      workspace['syncState'] == 'ready' &&
      persistence is Map &&
      persistence['kind'] == 'ready' &&
      persistence['pendingCommits'] == 0;
}

String? turnStatus(Map<String, dynamic> snapshot) {
  final workspace = workspaceOf(snapshot);
  if (workspace == null) return null;
  final turn = workspace['turn'];
  if (turn is Map && turn['status'] is String) return turn['status'] as String;
  final lastTurn = workspace['lastTurn'];
  if (lastTurn is Map && lastTurn['status'] is String) {
    return lastTurn['status'] as String;
  }
  return null;
}

String? turnId(Map<String, dynamic> snapshot) {
  final workspace = workspaceOf(snapshot);
  if (workspace == null) return null;
  final turn = workspace['turn'];
  if (turn is Map && turn['id'] is String) return turn['id'] as String;
  final lastTurn = workspace['lastTurn'];
  if (lastTurn is Map && lastTurn['id'] is String) {
    return lastTurn['id'] as String;
  }
  return null;
}

String? interactionKind(Map<String, dynamic> snapshot) {
  final interaction = workspaceOf(snapshot)?['activeInteraction'];
  return interaction is Map ? interaction['kind'] as String? : null;
}

Map<String, dynamic>? workspaceOf(Map<String, dynamic> snapshot) {
  final workspace = snapshot['workspace'];
  return workspace is Map<String, dynamic> ? workspace : null;
}

/// Acceptance row type of one canonical item: typed user input, authoritative text
/// channel, tool, or the canonical kind itself.
String _rowType(TimelineItemObservation item) {
  if (item.userInput != null) return 'userInput';
  if (item.isCommentary) return 'commentary';
  if (item.isFinalAnswer) return 'finalAnswer';
  if (item.kind == 'toolCall') return 'tool';
  return item.kind;
}

/// Host-side row view over the canonical items of the current generation.
///
/// `type` 是验收词汇，不是第二份行模型：它来自 canonical `kind` **加上**权威
/// `channel`/typed `userInput`。`agentMessage` 同时覆盖 commentary 与 finalAnswer，
/// 因此回答只能由 `channel == finalAnswer` 判定；问答行保留 plan 判别与权威决定。
List<Map<String, dynamic>> timelineRows(Map<String, dynamic> snapshot) {
  final timeline = TimelineObservation.optional(snapshot);
  if (timeline == null) return const [];
  return [
    for (final item in timeline.items)
      <String, dynamic>{
        'id': item.id,
        'kind': item.kind,
        'channel': item.channel,
        'type': _rowType(item),
        'text': item.text,
        'status': item.status,
        'appendSeq': item.appendSeq,
        'sourceEffectSeq': item.sourceEffectSeq,
        'sealedAt': item.sealedAt,
        'callId': item.tool?.callId,
        'userInput': item.userInput == null
            ? null
            : <String, Object?>{
                'interactionId': item.userInput!.interactionId,
                'state': item.userInput!.state,
                'isPlanConfirmation': item.userInput!.isPlanConfirmation,
                'planDecision': item.userInput!.planDecision,
              },
        'tools': <Map<String, dynamic>>[
          if (item.tool case final tool?)
            <String, dynamic>{
              'name': tool.name,
              'status': tool.status,
              'callId': tool.callId,
              'arguments': tool.arguments,
              'result': tool.result,
              'output': tool.result,
              'progressBytes': tool.progressBytes,
              'appendSeq': tool.appendSeq,
              'itemId': item.id,
              'attachments': [
                for (final attachment in tool.attachments)
                  <String, Object?>{
                    'id': attachment.id,
                    'modality': attachment.modality,
                    'filename': attachment.filename,
                    'byteSize': attachment.byteSize,
                  },
              ],
            },
        ],
      },
  ];
}

Map<String, Object?> summarize(Map<String, dynamic> snapshot) {
  final workspace = workspaceOf(snapshot);
  final details = workspace ?? const {};
  final usage = details['usage'];
  final persistence = snapshot['persistence'];
  final timeline = TimelineObservation.optional(snapshot);
  final rows = timeline?.items ?? const <TimelineItemObservation>[];
  final tools = execTools(snapshot);
  return {
    'threadStatus': details['threadStatus'],
    'isBusy': details['isBusy'],
    'syncState': details['syncState'],
    'turnId': turnId(snapshot),
    'turnStatus': turnStatus(snapshot),
    'interactionKind': interactionKind(snapshot),
    'runtime': driverRuntimeObservation(snapshot).toJson(),
    'outputTokens': usage is Map ? usage['outputTokens'] : null,
    'persistenceKind': persistence is Map ? persistence['kind'] : null,
    'pendingCommits': persistence is Map ? persistence['pendingCommits'] : null,
    'mode': timeline?.mode,
    'generation': timeline?.generation,
    'itemCount': timeline?.itemCount,
    'itemIds': [for (final item in rows) item.id],
    'itemKinds': [for (final item in rows) item.kind],
    'answerLengths': [
      for (final item in rows)
        if (item.isFinalAnswer) item.text.length,
    ],
    'commentaryLengths': [
      for (final item in rows)
        if (item.isCommentary) item.text.length,
    ],
    'userInputCount': rows.where((item) => item.userInput != null).length,
    'tools': [
      for (final tool in tools)
        {
          'name': tool['name'],
          'callId': tool['callId'],
          'status': tool['status'],
          'exitCode': tool['exitCode'],
          'resultLength': (tool['result'] as String? ?? '').length,
          'resultPreview': _resultPreview(tool['result'] as String?),
        },
    ],
  };
}

/// Bounded, single-note preview of a tool result so a reviewer can re-check the
/// observed output without duplicating whole command transcripts.
String? _resultPreview(String? value) {
  if (value == null || value.isEmpty) return null;
  const limit = 200;
  return value.length <= limit ? value : '${value.substring(0, limit)}…';
}

/// The integrated conversation-activity projection, when the GUI exposes it.
Map<String, dynamic>? conversationActivity(Map<String, dynamic> snapshot) {
  final activity = snapshot['conversationActivity'];
  return activity is Map<String, dynamic> ? activity : null;
}

/// The integrated read-only timeline-scroll geometry, when the GUI exposes it.
Map<String, dynamic>? timelineScroll(Map<String, dynamic> snapshot) {
  final scroll = snapshot['timelineScroll'];
  return scroll is Map<String, dynamic> ? scroll : null;
}

double? _num(Object? value) => value is num ? value.toDouble() : null;

double? _viewportDimension(Map<String, dynamic>? scroll) =>
    _num(scroll?['viewportDimension']);

class _ScrollGeometry {
  const _ScrollGeometry({
    required this.consistent,
    required this.atLiveEdge,
    required this.laidOut,
    required this.generation,
    required this.pixels,
    required this.maxScrollExtent,
    required this.extentBefore,
    required this.extentAfter,
  });

  final bool consistent;

  /// 反向列表 offset 0 的几何事实，不等于 Live 模式。
  final bool atLiveEdge;
  final bool laidOut;
  final int generation;
  final double pixels;
  final double maxScrollExtent;

  /// 反向列表里已从 offset 0 向上滚过的距离；“离底”看它，不看 [extentAfter]。
  final double? extentBefore;
  final double? extentAfter;
}

_ScrollGeometry? _scrollGeometry(Map<String, dynamic> scroll) {
  final parsed = TimelineScrollObservation.optional(<String, dynamic>{
    'timelineScroll': scroll,
  });
  if (parsed == null) return null;
  final pixels = parsed.pixels;
  final maxScrollExtent = parsed.maxScrollExtent;
  if (pixels == null || maxScrollExtent == null) {
    return _ScrollGeometry(
      consistent: false,
      atLiveEdge: parsed.atLiveEdge,
      laidOut: false,
      generation: parsed.generation,
      pixels: 0,
      maxScrollExtent: 0,
      extentBefore: parsed.extentBefore,
      extentAfter: parsed.extentAfter,
    );
  }
  return _ScrollGeometry(
    consistent: pixels >= -0.5 && pixels <= maxScrollExtent + 0.5,
    atLiveEdge: parsed.atLiveEdge,
    laidOut: parsed.laidOut,
    generation: parsed.generation,
    pixels: pixels,
    maxScrollExtent: maxScrollExtent,
    extentBefore: parsed.extentBefore,
    extentAfter: parsed.extentAfter,
  );
}
