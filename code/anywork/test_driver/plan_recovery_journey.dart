import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

import 'flutter_driver_session.dart';
import 'sidebar_navigation.dart';
import 'window_control.dart';
// Public snapshot helpers shared with the realtime/history journeys: this
// journey reads the same Driver projection and must not fork a second reading.
import 'realtime_journey.dart';

/// The Approve-branch prompt; it matches `GUI_PLAN_RECOVERY_APPROVE_PROMPT`.
const _approvePrompt = 'Local GUI plan recovery approve fixture';

/// The Revise-branch prompt; it matches `GUI_PLAN_RECOVERY_REVISE_PROMPT`.
const _revisePrompt = 'Local GUI plan recovery revise fixture';

/// The Approve-branch Plan markdown; it matches `GUI_PLAN_RECOVERY_APPROVE_PLAN`
/// byte for byte, so the restored card body and the continuation identity are
/// equality checks, never substring guesses.
const _approvePlan =
    '# Plan Recovery Approve Blueprint\n'
    '\n'
    '## Goal\n'
    '\n'
    'Prove a pending Plan confirmation survives a normal GUI shutdown and restart.\n'
    '\n'
    '## Steps\n'
    '\n'
    '1. Keep the pending confirmation restorable across a normal shutdown.\n'
    '2. Reopen the same session and restore the exact Plan body and identity.\n'
    '3. Approve the restored Plan and continue exactly once.';

/// The Revise-branch Plan markdown; it matches `GUI_PLAN_RECOVERY_REVISE_PLAN`.
const _revisePlan =
    '# Plan Recovery Revision Blueprint\n'
    '\n'
    '## Goal\n'
    '\n'
    'Exercise the Revise path on a restored pending Plan confirmation.\n'
    '\n'
    '## Steps\n'
    '\n'
    '1. Restore the pending Plan after the second normal shutdown.\n'
    '2. Request a revision with concrete feedback.\n'
    '3. Approve the rewritten Plan and finish the continuation.';

/// The rewritten Plan; it matches `GUI_PLAN_RECOVERY_REVISED_PLAN`.
const _revisedPlan =
    '# Plan Recovery Revision Blueprint\n'
    '\n'
    '## Goal\n'
    '\n'
    'Exercise the Revise path on a restored pending Plan confirmation.\n'
    '\n'
    '## Revised Steps\n'
    '\n'
    '1. Restore the pending Plan after the second normal shutdown.\n'
    '2. Request a revision with concrete feedback that tightens the wording.\n'
    '3. Approve the rewritten Plan and finish the continuation exactly once.';

/// Final answers of the two continuations; they match
/// `GUI_PLAN_RECOVERY_APPROVE_ANSWER` / `GUI_PLAN_RECOVERY_REVISE_ANSWER`.
const _approveAnswer = 'plan recovery approve answer complete';
const _reviseAnswer = 'plan recovery revise answer complete';

/// The revision feedback the journey submits through the plan feedback bar.
const _revisionFeedback =
    'Tighten the wording of the final step and keep the delivery scope '
    'unchanged.';

/// Turn statuses from which the awaited settle can no longer arrive. A
/// `completed` Turn is deliberately absent: while persistence is still
/// flushing it must keep waiting for the durable settle, not abort.
const _failedTurnStatuses = <String>{'failed', 'cancelled', 'budgetLimited'};

/// Marker files the coordinator writes after it proved the reopened card window
/// recorded no additional account request.
const _quietRestartMarker = 'plan-recovery-quiet-restart';
const _quietRecheckMarker = 'plan-recovery-quiet-recheck';

/// 会话阅读区域的可定位句柄：`StudioDriverKeys.timeline` 的真实值
/// （`lib/src/shared/studio_driver_keys.dart` → `ValueKey('timeline-scrollable')`）。
///
/// Host Driver 脚本在 `dart run` 下运行，不能 import 含 Flutter `ValueKey` 的 app 侧
/// key 文件，因此这里保留与源码一一对应的 pure-Dart 字符串。
const _readingAreaKey = 'timeline-scrollable';

/// Plan reading layout contract (design/13-plan.md §13.5). The assertions compare
/// real widget geometry, so these are the documented UI bounds rather than a
/// second copy of the product layout constants.
const _minimumConversationWidth = 400.0;
const _minimumPlanWidth = 360.0;
const _planDividerThickness = 1.0;
const _rectEpsilon = 1.0;

/// 计划详情头部的右内边距（`PlanDetailPanel` 头部 `EdgeInsets.fromLTRB(16, 12, 8, 12)`）。
/// 关闭动作是组内最后一个控件，它的布局盒右缘必须落在面板右缘减该值处。
const _planHeaderContentInset = 8.0;

/// 计划动作组在真实桌面上的布局盒下限。
///
/// 桌面 `ThemeData.materialTapTargetSize` 默认 `shrinkWrap`，主题又显式
/// `VisualDensity.compact`：未声明密度的按钮在 Linux GUI 上只有 32px 高（padded 命中区
/// 也会因 compact 从 48 掉到 40）。计划动作显式要求标准密度 + padded 后，布局盒是 48
/// （视觉 40）。这里用 44 作为下限，既能挡住 32/40 的退化，也不把 Material 常量复制成
/// 精确断言。
const _minDesktopActionBox = 44.0;

/// Shift+Enter 需要的官方键值（Flutter `keyboard_key.g.dart`）：
/// `LogicalKeyboardKey.enter == 0x0010000000d`、`PhysicalKeyboardKey.enter == 0x00070028`。
///
/// Host Driver 脚本在 `dart run` 下运行，不能 import `package:flutter/services.dart`
/// （会引入 `dart:ui`），因此这里只保留这两个已核对的整数常量。
const _logicalEnterKeyId = 0x0010000000d;
const _physicalEnterUsbHidUsage = 0x00070028;

/// Narrow/short window used to prove the full-width fallback is usable.
const _narrowPlanWindowWidth = 640;
const _narrowPlanWindowHeight = 620;
const _resizeSettleDeadline = Duration(seconds: 3);

/// The identity evidence shared between journey phases through the output dir.
const _observedFile = 'plan-recovery-observed.json';

Future<void> main(List<String> args) async {
  if (args.length != 5 ||
      !const ['first', 'restart', 'recheck'].contains(args[0])) {
    stderr.writeln(
      'usage: plan_recovery_journey.dart first|restart|recheck VM_URL '
      'PROJECT_DIR OUTPUT_DIR COORD_DIR',
    );
    exitCode = 64;
    return;
  }
  final phase = args[0];
  final output = Directory(args[3]);
  final coord = Directory(args[4]);
  final FlutterDriverSession driver;
  try {
    driver = await FlutterDriverSession.connect(vmServiceUrl: args[1]);
  } catch (error, stackTrace) {
    await _recordConnectFailure(phase, coord, output, error);
    // Never returns: the journey below can then rely on `driver` being set.
    Error.throwWithStackTrace(error, stackTrace);
  }
  final journey = PlanRecoveryJourney(
    driver: driver,
    phase: phase,
    project: args[2],
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
    // Capture the failing observation before shutdown; the original error is
    // always preserved.
    await journey.captureFailure();
  }
  Object? shutdownFailure;
  try {
    await journey.shutdown();
  } catch (error) {
    shutdownFailure = error;
    journey.shutdownError ??= '$error';
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
  journey.raiseIfFailed(shutdownFailure);
}

/// Records a stage marker and a minimal summary when the Driver cannot connect.
Future<void> _recordConnectFailure(
  String phase,
  Directory coord,
  Directory output,
  Object error,
) async {
  try {
    await File('${coord.path}/plan-recovery-stage')
        .writeAsString('${phase}_connect_failed');
    final summary = <String, Object?>{
      'scenario': 'plan-recovery',
      'phase': phase,
      'verdict': 'pending',
      'status': 'failed',
      'stage': '${phase}_connect_failed',
      'error': '$error',
      'shutdownError': null,
      'failedChecks': const <String>[],
      'checks': const <String, Object?>{},
      'observations': const <String, Object?>{},
      'counts': const <String, Object?>{},
      'completedAt': DateTime.now().toUtc().toIso8601String(),
      'pendingEvidence': const <String>[],
    };
    await File(
      '${output.path}/plan-recovery-$phase-summary.json',
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(summary)}\n');
  } catch (_) {
    // The coordinator still records the exit status and the sanitized log.
  }
}

/// Acceptance journey for the Plan confirmation recovery contract.
///
/// Three GUI lifecycles share one isolated home and one strict fixture script.
/// The `first` phase submits a real `plan_submit` through the GUI and shuts the
/// GUI down normally while the confirmation is pending. The `restart` phase
/// proves the reopened session restores the exact Plan body and interaction
/// identity, that no account request happens before the answer (the
/// coordinator's quiet marker), then approves and creates the Revise-branch
/// session before a second normal shutdown. The `recheck` phase restores that
/// second pending Plan, answers Revise (which must produce a rewritten Plan
/// confirmation with a fresh interaction identity), approves it, and proves
/// neither answered Plan re-pops. The strict fixture script rejects any extra
/// or duplicated model request, so the journey itself never needs to guess
/// whether a continuation ran twice.
class PlanRecoveryJourney {
  PlanRecoveryJourney({
    required this.driver,
    required this.phase,
    required this.project,
    required this.output,
    required this.coord,
  });

  final FlutterDriverSession driver;
  final String phase;
  final String project;
  final Directory output;
  final Directory coord;
  final Map<String, Object?> checks = <String, Object?>{};
  final Map<String, Object?> observations = <String, Object?>{};
  final Map<String, Object?> counts = <String, Object?>{};
  String stage = 'created';
  String? shutdownError;

  /// Observations that stay with the human reviewer rather than being asserted
  /// here; the coordinator records the account-side request counts.
  final List<String> pendingEvidence = <String>[
    'the coordinator owns the fixture request counters: the quiet windows '
        'before each answer are proved from the fixture status file, not from '
        'the Driver clock alone (see plan-recovery-requests-*.json)',
    'the strict fixture script rejects any unexpected model request, so a '
        'duplicated continuation or an early execution surfaces as a rejected '
        'request in fixture-status.json rather than a GUI observation',
  ];

  File get stageFile => File('${coord.path}/plan-recovery-stage');

  bool get failed => checks.values.any((value) => value != true);

  Future<void> run() async {
    switch (phase) {
      case 'first':
        await _runFirst();
      case 'restart':
        await _runRestart();
      case 'recheck':
        await _runRecheck();
      default:
        throw StateError('plan-recovery: unknown phase $phase');
    }
  }

  // ----------------------------------------------------------------- first --

  /// Submits the Approve-branch Plan and leaves the pending card on screen.
  Future<void> _runFirst() async {
    await mark('plan_recovery_first_connected');
    await _openProject();
    // A fresh home opens on the start page: no Thread exists yet (`workspace`
    // is null), so waiting for one before submitting can never succeed. The
    // submission itself creates session A through the real start-page composer
    // (`startNewThread`), exactly like the statistics journey's first turn.
    final existingThread = threadIdOf(await snapshot());
    if (existingThread != null) {
      throw StateError(
        'plan-recovery: first phase expected the start page, found thread '
        '$existingThread',
      );
    }
    await _submit(_approvePrompt);
    final initial = await waitFor(
      (snapshot) => (threadIdOf(snapshot) ?? '').isNotEmpty,
      'first_thread_ready',
    );
    final threadId = threadIdOf(initial)!;
    final card = await _waitForPlanCard('first_approve', _approvePlan);
    // The Thread is brand new, so its only Turn is the submission's: an
    // attached card Turn keeps proving the submission drove the model Turn.
    checks['firstCardTurnAttached'] = (turnId(card)?.isNotEmpty) ?? false;
    final interaction = activeInteractionOf(card)!;
    checks['firstCardIsUserInput'] = interaction['kind'] == 'userInput';
    checks['firstCardBodyMatchesPlan'] = interaction['body'] == _approvePlan;
    counts['approveThreadId'] = threadId;
    counts['approveInteractionId'] = interaction['id'];
    counts['approveTurnId'] = interaction['turnId'];
    observations['firstCard'] = summarize(card);
    await _openPlanDetails('first');
    await shot('first-card');
    await _writeObserved(<String, Object?>{
      'approveBranch': <String, Object?>{
        'threadId': threadId,
        'interactionId': interaction['id'],
        'planMarkdown': interaction['body'],
        'turnId': interaction['turnId'],
      },
    });
    await mark('plan_recovery_first_card');
  }

  // --------------------------------------------------------------- restart --

  /// Restores and approves the first Plan, then stages the Revise branch.
  Future<void> _runRestart() async {
    await mark('plan_recovery_restart_connected');
    final observed = await _readObserved();
    final branch = _branchOf(observed, 'approveBranch');
    final threadId = branch['threadId'] as String;
    final expectedInteractionId = branch['interactionId'] as String;
    await _ensureThreadOpen(threadId, 'restart_approve');
    final card = await _waitForPlanCard(
      'restart_approve',
      _approvePlan,
      expectedInteractionId: expectedInteractionId,
    );
    final interaction = activeInteractionOf(card)!;
    checks['approveIdentityRestored'] =
        interaction['id'] == branch['interactionId'];
    checks['approveTurnIdentityRestored'] =
        interaction['turnId'] == branch['turnId'];
    checks['approveBodyRestored'] = interaction['body'] == _approvePlan;
    counts['reopenedApproveInteractionId'] = interaction['id'];
    observations['restartCard'] = summarize(card);
    await _openPlanDetails('restart');
    await shot('restart-card-restored');
    await mark('plan_recovery_reopened');
    // The coordinator proves this window recorded no account request before
    // the journey is allowed to answer.
    await _awaitMarker(
      _quietRestartMarker,
      'restart_quiet',
      const Duration(seconds: 180),
    );

    final priorTurn = turnId(card)!;
    final priorUserRows = userMessageCount(card);
    await _tapForEffect(
      'plan-approve',
      (snapshot) => activeInteractionOf(snapshot) == null,
      'restart_approve',
    );
    await _cardDismissed('restart_approve');
    await _awaitAnswered(
      'restart_approve',
      priorTurn,
      _approveAnswer,
      priorUserRows,
    );
    await shot('restart-answered');
    await _openApprovedPlanFromOverflow(
      'restart_approved',
      expectedMarkdown: _approvePlan,
    );
    // 已回答的计划必须留下可展开的历史回执，而不是只靠当前 Plan 正文。
    await _planReceiptContract('restart_approved');

    // Stage the Revise branch: a second session with its own pending Plan, so
    // the second normal shutdown also happens while a confirmation is pending.
    await _tapForEffect(
      'sidebar-new-session',
      threadDeselected,
      'restart_new_session',
    );
    await driver.waitFor(
      find.byValueKey('composer-input'),
      timeout: const Duration(seconds: 60),
    );
    // `beginNewThread` returns to the start page (`selectedThreadId` null);
    // session B is created by the submission itself, so the prompt is sent
    // first and the distinct Thread id is awaited afterwards.
    await _submit(_revisePrompt);
    final reviseInitial = await waitFor((snapshot) {
      final current = threadIdOf(snapshot);
      return current != null && current != threadId;
    }, 'restart_revise_thread_ready');
    final reviseThreadId = threadIdOf(reviseInitial)!;
    final reviseCard = await _waitForPlanCard('restart_revise', _revisePlan);
    checks['reviseCardTurnAttached'] =
        (turnId(reviseCard)?.isNotEmpty) ?? false;
    final reviseInteraction = activeInteractionOf(reviseCard)!;
    checks['reviseCardBodyMatchesPlan'] =
        reviseInteraction['body'] == _revisePlan;
    checks['reviseInteractionDistinct'] =
        reviseInteraction['id'] != expectedInteractionId;
    counts['reviseThreadId'] = reviseThreadId;
    counts['reviseInteractionId'] = reviseInteraction['id'];
    observations['restartReviseCard'] = summarize(reviseCard);
    await _openPlanDetails('restart_revise');
    await shot('restart-revise-card');
    await _writeObserved(<String, Object?>{
      'reviseBranch': <String, Object?>{
        'threadId': reviseThreadId,
        'interactionId': reviseInteraction['id'],
        'planMarkdown': reviseInteraction['body'],
        'turnId': reviseInteraction['turnId'],
      },
    });
    await mark('plan_recovery_revise_card');
  }

  // --------------------------------------------------------------- recheck --

  /// Restores the second Plan, answers Revise then Approve, and proves neither
  /// answered Plan re-pops.
  Future<void> _runRecheck() async {
    await mark('plan_recovery_recheck_connected');
    final observed = await _readObserved();
    final branch = _branchOf(observed, 'reviseBranch');
    final threadId = branch['threadId'] as String;
    final expectedInteractionId = branch['interactionId'] as String;
    final approveThreadId =
        _branchOf(observed, 'approveBranch')['threadId'] as String;
    await _ensureThreadOpen(threadId, 'recheck_revise');
    final card = await _waitForPlanCard(
      'recheck_revise',
      _revisePlan,
      expectedInteractionId: expectedInteractionId,
    );
    final interaction = activeInteractionOf(card)!;
    checks['reviseIdentityRestored'] =
        interaction['id'] == branch['interactionId'];
    checks['reviseTurnIdentityRestored'] =
        interaction['turnId'] == branch['turnId'];
    checks['reviseBodyRestored'] = interaction['body'] == _revisePlan;
    counts['reopenedReviseInteractionId'] = interaction['id'];
    observations['recheckCard'] = summarize(card);
    await _openPlanDetails('recheck');
    await shot('recheck-card-restored');
    await mark('plan_recovery_recheck_reopened');
    await _awaitMarker(
      _quietRecheckMarker,
      'recheck_quiet',
      const Duration(seconds: 180),
    );

    // Revise: the feedback bar is the only writer of the Revise answer. The
    // focus tap goes through the raw pointer path like the composer: the
    // stock `Tap` command's `hitTestable()` pre-filter never yields
    // candidates on the Linux embedder. The answer itself is submitted with
    // Enter, not with the button, so the journey exercises the same text input
    // action the engine produces for a real Return key.
    await _planReadingLayoutContract('recheck', expectedInteractionId);
    await _narrowPlanLayoutContract('recheck', expectedInteractionId);
    await _answerPlanByEnter(
      'recheck_revise',
      expectedInteractionId: expectedInteractionId,
    );
    await _cardDismissed(
      'recheck_revise',
      replacedInteractionId: expectedInteractionId,
    );

    // The rewritten Plan must arrive as a new pending confirmation with its own
    // interaction identity; a stale identity would mean the old card was reused.
    final revisedCard = await _waitForPlanCard('recheck_revised', _revisedPlan);
    final revisedInteraction = activeInteractionOf(revisedCard)!;
    checks['revisedCardBodyMatchesPlan'] =
        revisedInteraction['body'] == _revisedPlan;
    checks['revisedCardNewIdentity'] =
        revisedInteraction['id'] is String &&
        (revisedInteraction['id'] as String).isNotEmpty &&
        revisedInteraction['id'] != expectedInteractionId;
    counts['revisedInteractionId'] = revisedInteraction['id'];
    observations['recheckRevisedCard'] = summarize(revisedCard);
    await _openPlanDetails('recheck_revised');
    await shot('recheck-revised-card');

    final revisedTurn = turnId(revisedCard)!;
    final revisedUserRows = userMessageCount(revisedCard);
    await _tapForEffect(
      'plan-approve',
      (snapshot) => activeInteractionOf(snapshot) == null,
      'recheck_revised',
    );
    await _cardDismissed('recheck_revised');
    await _awaitAnswered(
      'recheck_revised',
      revisedTurn,
      _reviseAnswer,
      revisedUserRows,
    );
    await shot('recheck-answered');
    await _openApprovedPlanFromOverflow(
      'recheck_revised_approved',
      expectedMarkdown: _revisedPlan,
    );
    // 修改意见必须作为历史回执保留原始全文，而不是只留在已消失的反馈栏里。
    await _planReceiptContract(
      'recheck_revised_approved',
      expectedReply: _revisionFeedback,
    );

    // Neither answered Plan may re-pop, in either reopened session.
    await _ensureThreadOpen(approveThreadId, 'recheck_approve_thread');
    final approveThread = await _assertNoPendingPlan('recheck_approve_thread');
    checks['answeredApprovePlanNotRepop'] =
        activeInteractionOf(approveThread) == null;
    observations['recheckApproveThreadFinal'] = summarize(approveThread);
    // 重开旧会话后，已批准计划的历史回执仍可读。
    await _planReceiptContract('recheck_approve_receipt');
    await _openApprovedPlanFromOverflow(
      'recheck_approve_reopen',
      expectedMarkdown: _approvePlan,
    );
    await _ensureThreadOpen(threadId, 'recheck_revise_thread');
    final reviseThread = await _assertNoPendingPlan('recheck_revise_thread');
    checks['answeredRevisePlanNotRepop'] =
        activeInteractionOf(reviseThread) == null;
    observations['recheckReviseThreadFinal'] = summarize(reviseThread);
    await shot('recheck-no-repop');
    await mark('plan_recovery_recheck_complete');
  }

  // --------------------------------------------------------------- helpers --

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

  /// Taps [key] and proves the action through an explicit desired widget
  /// state instead of the tap response alone.
  ///
  /// The Driver transport can drop a command response after the app already
  /// performed the action (the 03 run opened the details panel while the
  /// rawTap response never arrived), so a timed-out tap with the desired
  /// widget already visible counts as done. The tap is never replayed, any
  /// other error propagates untouched, and a missing effect rethrows the
  /// original timeout.
  Future<void> _tapForWidget(
    String key,
    String desiredKey,
    String label, {
    required bool present,
  }) async {
    try {
      await _tap(key);
    } on TimeoutException catch (error, stackTrace) {
      var recovered = false;
      try {
        // The tap timeout closed the observation client; a snapshot read
        // re-establishes it before the widget check.
        await snapshot();
        recovered = await _widgetHolds(desiredKey, present: present);
      } on Object {
        // The confirmation itself failed: the original timeout stays the
        // reported failure.
      }
      if (!recovered) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      counts['${label}TapConfirmedByEffect'] = true;
      return;
    }
    if (present) {
      await driver.waitFor(
        find.byValueKey(desiredKey),
        timeout: const Duration(seconds: 30),
      );
    } else {
      await driver.waitForAbsent(
        find.byValueKey(desiredKey),
        timeout: const Duration(seconds: 30),
      );
    }
  }

  /// Whether the widget exists (or is gone), bounded for one confirmation.
  Future<bool> _widgetHolds(String key, {required bool present}) async {
    try {
      if (present) {
        await driver.waitFor(
          find.byValueKey(key),
          timeout: const Duration(seconds: 10),
        );
      } else {
        await driver.waitForAbsent(
          find.byValueKey(key),
          timeout: const Duration(seconds: 10),
        );
      }
      return true;
    } on Object {
      return false;
    }
  }

  /// 只在目标状态尚未成立时才点击 [key]。
  ///
  /// 产品会自动打开待确认计划的详情面板，驱动不能无条件 toggle：面板已经打开时再点
  /// 摘要卡会把它关掉（third-pass 的 `plan-details` 等待超时正是这样产生的）。这里先读
  /// 当前可见状态，已满足就直接返回并留下证据；确实没满足才点击一次，并等待明确的
  /// 后置状态。它只用于无副作用的界面开关，不用于批准/修订这类有副作用的决定。
  Future<void> _ensureWidgetState(
    String key,
    String desiredKey,
    String label, {
    required bool present,
  }) async {
    if (await _widgetHolds(desiredKey, present: present)) {
      counts['${label}AlreadySatisfied'] = true;
      return;
    }
    await _tapForWidget(key, desiredKey, label, present: present);
  }

  /// Taps [key] and proves the action through a snapshot-level [effect].
  ///
  /// Same recovery rule as [_tapForWidget]: a timed-out tap whose effect
  /// arrives within [grace] counts as done and is never replayed; otherwise
  /// the original timeout is rethrown. The effect wait reads through the
  /// reconnecting snapshot channel.
  Future<void> _tapForEffect(
    String key,
    bool Function(Map<String, dynamic>) effect,
    String label, {
    Duration grace = const Duration(seconds: 30),
  }) async {
    try {
      await _tap(key);
    } on TimeoutException catch (error, stackTrace) {
      var recovered = false;
      try {
        await waitFor(effect, '${label}_tap_effect', timeout: grace);
        recovered = true;
      } on Object {
        // The effect never arrived: the original timeout stays the failure.
      }
      if (!recovered) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      counts['${label}TapConfirmedByEffect'] = true;
      return;
    }
  }

  String? threadIdOf(Map<String, dynamic> snapshot) {
    final value = workspaceOf(snapshot)?['threadId'];
    return value is String ? value : null;
  }

  /// Whether the start page is active again (no Thread selected), the effect
  /// of the sidebar's new-session action.
  bool threadDeselected(Map<String, dynamic> snapshot) {
    final navigation = snapshot['navigation'];
    return navigation is Map && navigation['selectedThreadId'] == null;
  }

  Map<String, dynamic>? activeInteractionOf(Map<String, dynamic> snapshot) {
    final value = workspaceOf(snapshot)?['activeInteraction'];
    return value is Map<String, dynamic> ? value : null;
  }

  /// The pending-confirmation settle projection.
  ///
  /// A Thread waiting on a Plan confirmation is deliberately not `idle`: its
  /// status is `waitingInteraction`, so the generic idle-settle wait never
  /// applies here. What must still hold is that nothing is running and durable
  /// persistence is ready with nothing pending, which is exactly the checkpoint
  /// state a later normal shutdown has to persist.
  bool planCardSettled(Map<String, dynamic> snapshot) {
    final workspace = workspaceOf(snapshot);
    final persistence = snapshot['persistence'];
    return workspace != null &&
        workspace['threadStatus'] == 'waitingInteraction' &&
        workspace['isBusy'] == false &&
        workspace['syncState'] == 'ready' &&
        persistence is Map &&
        persistence['kind'] == 'ready' &&
        persistence['pendingCommits'] == 0;
  }

  /// Whether durable persistence is faulted: a write failed with an error
  /// (`degraded`) or the writer is blocked. Both need intervention, so a wait
  /// for the durable settle reports them immediately instead of burning its
  /// timeout; `flushing` and `recovering` are healthy transients that keep
  /// waiting.
  bool persistenceFaulted(Map<String, dynamic> snapshot) {
    final persistence = snapshot['persistence'];
    return persistence is Map &&
        const ['degraded', 'blocked'].contains(persistence['kind']);
  }

  /// Visible user rows in the current timeline window. The plan continuation is
  /// delivered with the hidden presentation, so it must never add one.
  int userMessageCount(Map<String, dynamic> snapshot) =>
      timelineRows(snapshot)
          .where((row) => row['type'] == 'userMessage')
          .length;

  /// Waits for the pending Plan confirmation card and its durable checkpoint.
  ///
  /// When [expectedInteractionId] is non-null the restored identity must equal
  /// it; the caller records the equality as its own check. Brand-new sessions
  /// prove the submission drove the Turn through the attached card Turn check
  /// instead: a fresh Thread has no earlier Turn to differ from.
  Future<Map<String, dynamic>> _waitForPlanCard(
    String label,
    String expectedMarkdown, {
    String? expectedInteractionId,
  }) async {
    await driver.waitFor(
      find.byValueKey('plan-summary'),
      timeout: const Duration(seconds: 90),
    );
    await driver.waitFor(
      find.byValueKey('plan-approve'),
      timeout: const Duration(seconds: 30),
    );
    await driver.waitFor(
      find.byValueKey('plan-feedback-input'),
      timeout: const Duration(seconds: 30),
    );
    // The pending confirmation must also be durably checkpointed before the
    // journey relies on it, so a shutdown here can never lose the card.
    final card = await waitFor(
      (snapshot) {
        final interaction = activeInteractionOf(snapshot);
        return interaction != null &&
            interaction['body'] == expectedMarkdown &&
            (expectedInteractionId == null ||
                interaction['id'] == expectedInteractionId) &&
            planCardSettled(snapshot);
      },
      '${label}_card_settled',
      timeout: const Duration(seconds: 180),
      abort: threadFaulted,
    );
    // 待确认期间只有尾部唯一摘要入口：**当前 pending 计划行**不得渲染历史回执，
    // 但上一轮已回答的旧计划回执必须仍在（修订会连续产生多条计划行）。
    final planRows = _planRows(card);
    final pendingRows = planRows.where((row) => row.pending).toList();
    final resolvedRows = planRows.where((row) => !row.pending).toList();
    var pendingTiles = 0;
    for (final row in pendingRows) {
      if (await _widgetHoldsByKey(
        find.byValueKey('timeline-plan-receipt-${row.id}'),
      )) {
        pendingTiles++;
      }
    }
    var resolvedTiles = 0;
    for (final row in resolvedRows) {
      if (await _widgetHoldsByKey(
        find.byValueKey('timeline-plan-receipt-${row.id}'),
      )) {
        resolvedTiles++;
      }
    }
    checks['${label}PendingPlanRowUnique'] = pendingRows.length == 1;
    checks['${label}PendingHidesPlanReceipt'] =
        pendingRows.length == 1 && pendingTiles == 0;
    checks['${label}ResolvedPlanReceiptsKept'] =
        resolvedTiles == resolvedRows.length;
    counts['${label}PendingPlanRows'] = pendingRows.length;
    counts['${label}ResolvedPlanRows'] = resolvedRows.length;
    counts['${label}ResolvedPlanReceiptTiles'] = resolvedTiles;
    observations['${label}PlanRows'] = [
      for (final row in planRows)
        {'id': row.id, 'pending': row.pending, 'decision': row.decision},
    ];
    // The normal composer must be replaced while the Plan is pending.
    try {
      await driver.waitForAbsent(
        find.byValueKey('composer-input'),
        timeout: const Duration(seconds: 10),
      );
      checks['${label}ComposerReplaced'] = true;
    } on Object {
      checks['${label}ComposerReplaced'] = false;
    }
    return card;
  }

  /// Opens the approved Plan through the overflow menu and proves the same
  /// document is still readable after confirmation has left the timeline.
  Future<void> _openApprovedPlanFromOverflow(
    String label, {
    required String expectedMarkdown,
  }) async {
    await waitFor((snapshot) {
      final plan = snapshot['plan'];
      return plan is Map &&
          plan['state'] == 'approved' &&
          plan['markdown'] == expectedMarkdown;
    }, '${label}_plan_projection');
    await _ensureWidgetState(
      'status-overflow',
      'status-plan-entry',
      '$label-overflow-open',
      present: true,
    );
    // 入口本身是显式的一次打开动作：只有面板尚未打开时才点它。
    await _ensureWidgetState(
      'status-plan-entry',
      'plan-details',
      '$label-plan-entry',
      present: true,
    );
    await driver.waitFor(
      find.byValueKey('plan-details-scroll'),
      timeout: const Duration(seconds: 30),
    );
    final opened = await snapshot();
    final plan = opened['plan'];
    checks['${label}PlanDetailsVisible'] = true;
    checks['${label}PlanMarkdownMatches'] =
        plan is Map && plan['markdown'] == expectedMarkdown;
    checks['${label}PlanPanelRendersMarkdown'] = await _planPanelRendersHeading(
      expectedMarkdown,
    );
    await shot('$label-approved-details');
    await _ensureWidgetState(
      'plan-details-close',
      'plan-details',
      '$label-details-close',
      present: false,
    );
    checks['${label}PlanDetailsClosed'] = true;
  }

  /// Visible H1 of [markdown] after the Markdown renderer strips `# `.
  String _planHeadingText(String markdown) {
    for (final line in markdown.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('# ')) {
        final heading = trimmed.substring(2).trim();
        if (heading.isNotEmpty) return heading;
      }
    }
    throw StateError('plan markdown has no H1 heading: $markdown');
  }

  /// Proves the open details panel itself rendered [expectedMarkdown]'s heading.
  ///
  /// The snapshot only proves the runtime projection. The current renderer
  /// uses RichText subclasses, which the stock ByText finder does not match.
  /// Read the actual body's render tree through the official Driver command;
  /// only InlineSpan text properties count, never creator strings or the
  /// separate panel title. Missing/truncated diagnostics remain failures.
  Future<bool> _planPanelRendersHeading(String expectedMarkdown) async {
    final heading = _planHeadingText(expectedMarkdown);
    final tree = await driver.sendCommand(
      GetDiagnosticsTree(
        find.byValueKey('plan-details-markdown'),
        DiagnosticsType.renderObject,
        subtreeDepth: 128,
        timeout: const Duration(seconds: 10),
      ),
    );
    final texts = <String>[];
    void visit(Map node) {
      final children = node['children'];
      if (node['truncated'] == true ||
          (node['hasChildren'] == true &&
              (children is! List || children.isEmpty))) {
        throw StateError('plan body render diagnostics were truncated');
      }
      for (final property in node['properties'] as List? ?? const []) {
        if (property is Map &&
            property['name'] == 'text' &&
            property['value'] is String) {
          texts.add(property['value'] as String);
        }
      }
      for (final child in children as List? ?? const []) {
        if (child is! Map) {
          throw StateError('invalid plan body render diagnostic child');
        }
        visit(child);
      }
    }

    visit(tree);
    if (texts.isEmpty) {
      throw StateError('plan body render diagnostics contain no text');
    }
    return texts.contains(heading);
  }

  /// Opens and closes the read-only Plan details panel through the product UI.
  ///
  /// 打开是幂等的：pending 计划由产品自动打开，此时直接读当前可见状态与截图，
  /// 不再 toggle；确实关闭时才点击一次并等待面板出现。关闭同理。
  Future<void> _openPlanDetails(String label) async {
    await _ensureWidgetState(
      'plan-summary',
      'plan-details',
      '$label-details-open',
      present: true,
    );
    await driver.waitFor(
      find.byValueKey('plan-details-scroll'),
      timeout: const Duration(seconds: 30),
    );
    await shot('$label-details');
    await _ensureWidgetState(
      'plan-details-close',
      'plan-details',
      '$label-details-close',
      present: false,
    );
  }

  /// Waits until the confirmation card is dismissed.
  ///
  /// On the Approve path nothing replaces the card, so its widgets, the
  /// composer and the interaction itself must all be gone. On the Revise path
  /// a rewritten card follows immediately and the transient gap between the
  /// two cards is shorter than a reliable poll, so the dismissal fact there is
  /// the old interaction identity no longer being active; the caller then
  /// verifies the replacement card itself (widgets, body and identity).
  Future<void> _cardDismissed(
    String label, {
    String? replacedInteractionId,
  }) async {
    if (replacedInteractionId == null) {
      await driver.waitForAbsent(
        find.byValueKey('plan-summary'),
        timeout: const Duration(seconds: 60),
      );
      await driver.waitForAbsent(
        find.byValueKey('plan-approve'),
        timeout: const Duration(seconds: 30),
      );
      await driver.waitForAbsent(
        find.byValueKey('plan-feedback-input'),
        timeout: const Duration(seconds: 30),
      );
      await driver.waitFor(
        find.byValueKey('composer-input'),
        timeout: const Duration(seconds: 60),
      );
    }
    // The dismissal fact is the interaction itself going away - or, on the
    // Revise path, being replaced - while the continuation Turn may already be
    // running, so busy-ness deliberately stays out of this predicate.
    final dismissed = await waitFor(
      (snapshot) {
        final interaction = activeInteractionOf(snapshot);
        return interaction == null ||
            (replacedInteractionId != null &&
                interaction['id'] != replacedInteractionId);
      },
      '${label}_card_dismissed',
      timeout: const Duration(seconds: 60),
    );
    checks['${label}CardDismissed'] = true;
    counts['${label}DismissedAt'] = DateTime.now().millisecondsSinceEpoch;
    observations['${label}Dismissed'] = summarize(dismissed);
  }

  /// Waits for the continuation Turn to complete and settle with exactly one
  /// answer and no new visible user row.
  Future<Map<String, dynamic>> _awaitAnswered(
    String label,
    String priorTurnId,
    String answer,
    int priorUserRows,
  ) async {
    final running = await waitFor(
      (snapshot) => turnId(snapshot) != null && turnId(snapshot) != priorTurnId,
      '${label}_continuation_running',
      timeout: const Duration(seconds: 90),
      abort: threadFaulted,
    );
    final turn = turnId(running)!;
    final settled = await waitFor(
      (snapshot) =>
          turnId(snapshot) == turn &&
          turnStatus(snapshot) == 'completed' &&
          isDurableSettled(snapshot),
      '${label}_continuation_settled',
      timeout: const Duration(seconds: 240),
      // Only genuine failures abort: a completed Turn may still be flushing
      // to durable storage, which is exactly the settle being waited for.
      abort: (snapshot) =>
          turnFailed(snapshot) ||
          persistenceFaulted(snapshot) ||
          (turnId(snapshot) == turn &&
              _failedTurnStatuses.contains(turnStatus(snapshot))),
    );
    final matches = answerMatchCount(settled, answer);
    checks['${label}ContinuationAnswered'] = matches >= 1;
    checks['${label}AnswerExactlyOnce'] = matches == 1;
    checks['${label}NoVisibleContinuationUserRow'] =
        userMessageCount(settled) == priorUserRows;
    counts['${label}AnswerMatches'] = matches;
    counts['${label}ContinuationTurnId'] = turn;
    return settled;
  }

  /// Ensures exactly the target session is the open workspace.
  Future<void> _ensureThreadOpen(String threadId, String label) async {
    if (threadIdOf(await snapshot()) == threadId) return;
    await revealSidebarThread(driver, threadId);
    await _tapForEffect(
      'thread-row-$threadId',
      (snapshot) => threadIdOf(snapshot) == threadId,
      '${label}_open',
      grace: const Duration(seconds: 60),
    );
    await waitFor(
      (snapshot) => threadIdOf(snapshot) == threadId,
      '${label}_opened',
      timeout: const Duration(seconds: 60),
    );
    await clearSidebarSearch(driver);
  }

  /// Proves no pending Plan confirmation exists in the current workspace.
  Future<Map<String, dynamic>> _assertNoPendingPlan(String label) async {
    await driver.waitForAbsent(
      find.byValueKey('plan-summary'),
      timeout: const Duration(seconds: 30),
    );
    await driver.waitForAbsent(
      find.byValueKey('plan-approve'),
      timeout: const Duration(seconds: 30),
    );
    await driver.waitFor(
      find.byValueKey('composer-input'),
      timeout: const Duration(seconds: 60),
    );
    return waitFor(
      (snapshot) =>
          activeInteractionOf(snapshot) == null && isDurableSettled(snapshot),
      '${label}_no_pending_plan',
      timeout: const Duration(seconds: 60),
    );
  }

  Future<void> _awaitMarker(String name, String label, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    final file = File('${coord.path}/$name');
    while (DateTime.now().isBefore(deadline)) {
      if (await file.exists()) return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw StateError(
      'timed out waiting for the coordinator marker $name ($label)',
    );
  }

  // -------------------------------------------------------- plan layout --

  /// 反馈文本框的当前正文；Driver `getText` 对 `TextField` 直接返回 `controller.text`。
  Future<String?> _readFeedbackText() async {
    try {
      return await driver.getText(find.byValueKey('plan-feedback-input'));
    } on Object {
      return null;
    }
  }

  /// 真实几何：Driver 的 offset 命令读当前布局，不读产品常量。
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

  /// 计划动作组与输入框的真实几何对齐（读取实际 RenderBox，不看视觉猜测）。
  ///
  /// 容差取 [_rectEpsilon]：两侧横向 padding 一致时右缘应完全相等；按钮比较的是布局盒，
  /// 标准的 tap-target 内边距两侧一致，因此不算作偏差。
  void _recordActionAlignment({
    required String prefix,
    required DriverRect? feedback,
    required DriverRect? revise,
    required DriverRect? approve,
  }) {
    final readable = feedback != null && revise != null && approve != null;
    checks['${prefix}ActionGeometryReadable'] = readable;
    if (!readable) return;
    checks['${prefix}ActionsAlignToInputEdge'] =
        (approve.right - feedback.right).abs() <= _rectEpsilon;
    // 布局盒同高：两侧都含标准 tap target，因此这里证明的是盒尺寸一致，
    // 不声称 Material 视觉高度逐像素相等。
    checks['${prefix}ActionsShareLayoutBoxHeight'] =
        (revise.height - approve.height).abs() <= _rectEpsilon;
    checks['${prefix}ActionsShareLayoutBoxBaseline'] =
        ((revise.top + revise.bottom) - (approve.top + approve.bottom)).abs() <=
        _rectEpsilon * 2;
    checks['${prefix}PrimaryActionRightmost'] =
        approve.left > revise.left &&
        (approve.left - revise.right - 8).abs() <= _rectEpsilon;
    checks['${prefix}ActionsMeetHitTarget'] =
        revise.height >= _minDesktopActionBox &&
        approve.height >= _minDesktopActionBox;
    observations['${prefix}ActionRects'] = {
      'feedback': feedback.toJson(),
      'revise': revise.toJson(),
      'approve': approve.toJson(),
    };
  }

  /// 计划详情头部的阅读/关闭动作组：靠右、同一基线、标准命中尺寸。
  ///
  /// [expectReadingToggle] 描述该布局是否可能有并排阅读切换：宽布局必须有它；
  /// 窄窗口本来就无法并排，此时断言它确实缺席、关闭按钮仍在且命中尺寸达标——
  /// 不能因为 toggle 为 null 就把整组检查一起跳过。
  ///
  /// [panel] 是计划详情面板本身的矩形：动作组必须锚在它的内容右边界
  /// （panel.right − 头部右内边距），旧实现的宽松动作槽会把关闭按钮留在面板中间。
  void _recordHeaderAlignment({
    required String prefix,
    required bool expectReadingToggle,
    required DriverRect? panel,
    required DriverRect? toggle,
    required DriverRect? close,
  }) {
    final anchored =
        panel != null &&
        close != null &&
        (panel.right - close.right - _planHeaderContentInset).abs() <=
            _rectEpsilon;
    checks['${prefix}HeaderActionsAlignToContentEdge'] = anchored;
    if (!expectReadingToggle) {
      checks['${prefix}HeaderActionsReadable'] = close != null;
      checks['${prefix}HeaderReadingToggleAbsent'] = toggle == null;
      checks['${prefix}HeaderActionsMeetHitTarget'] =
          close != null &&
          close.width >= _minDesktopActionBox &&
          close.height >= _minDesktopActionBox;
      observations['${prefix}HeaderActionRects'] = {
        'panel': panel?.toJson(),
        'readingMode': toggle?.toJson(),
        'close': close?.toJson(),
      };
      return;
    }
    final readable = toggle != null && close != null;
    checks['${prefix}HeaderActionsReadable'] = readable;
    if (!readable) return;
    checks['${prefix}HeaderActionsShareBaseline'] =
        ((toggle.top + toggle.bottom) - (close.top + close.bottom)).abs() <=
        _rectEpsilon * 2;
    // 关闭是组内最后一个动作：阅读切换必须在它左侧且保持 4px 组内间距。
    checks['${prefix}HeaderActionsOrderedRightToLeft'] =
        toggle.right < close.left &&
        (close.left - toggle.right - 4).abs() <= _rectEpsilon;
    checks['${prefix}HeaderActionsMeetHitTarget'] =
        toggle.height >= _minDesktopActionBox &&
        close.width >= _minDesktopActionBox &&
        close.height >= _minDesktopActionBox;
    observations['${prefix}HeaderActionRects'] = {
      'panel': panel?.toJson(),
      'readingMode': toggle.toJson(),
      'close': close.toJson(),
    };
  }

  /// 并排阅读布局契约：计划可宽于对话、对话守住最小宽度、全宽/并排往返保持宽度。
  Future<void> _planReadingLayoutContract(
    String label,
    String expectedInteractionId,
  ) async {
    await _ensureWidgetState(
      'plan-summary',
      'plan-details',
      '${label}_layout_open',
      present: true,
    );
    await driver.waitFor(
      find.byValueKey('plan-details-scroll'),
      timeout: const Duration(seconds: 30),
    );
    var conversation = await _readRect(_readingAreaKey);
    var plan = await _readRect('plan-details');
    var divider = await _readRect('plan-resize-handle');
    observations['${label}SideBySideRects'] = {
      'conversation': conversation?.toJson(),
      'plan': plan?.toJson(),
      'divider': divider?.toJson(),
    };
    await shot('$label-plan-side-by-side');

    // 并排有两条失败路径，必须分开：窗口确实不足以并排（可判定、先加宽），
    // 与几何本身读不到（缺陷，必须失败传播）。两者都不允许静默记 pending。
    WindowGeometry? restoreGeometry;
    int? resizePid;
    final widestNeeded =
        2 * _minimumConversationWidth + _planDividerThickness + 3;
    final paneTooNarrow =
        divider == null ||
        plan == null ||
        conversation == null ||
        plan.width + conversation.width + _planDividerThickness < widestNeeded;
    if (paneTooNarrow) {
      resizePid = await _guiProcessId();
      final shell = await _readRect('studio-shell');
      if (resizePid != null && shell != null) {
        final widened = resizeOwnedWindow(
          guiPid: resizePid,
          width: (shell.width + 520).round(),
          height: shell.height.round(),
        );
        if (widened.resized) {
          restoreGeometry = widened.original;
          await _settleAfterResize(shell, expectNarrower: false);
          conversation = await _readRect(_readingAreaKey);
          plan = await _readRect('plan-details');
          divider = await _readRect('plan-resize-handle');
          observations['${label}SideBySideRectsWidened'] = {
            'conversation': conversation?.toJson(),
            'plan': plan?.toJson(),
            'divider': divider?.toJson(),
          };
        } else {
          pendingEvidence.add(
            'plan layout: the window could not be widened for the split '
            'observation (${widened.reason})',
          );
        }
      } else {
        pendingEvidence.add(
          'plan layout: the GUI process id or shell geometry was unavailable, '
          'so the window could not be widened for the split observation',
        );
      }
    }

    try {
      if (conversation == null || plan == null || divider == null) {
        // 加宽后仍没有并排分隔条或几何不可读：这是真实失败，不是环境观察。
        checks['${label}SideBySideReadable'] = false;
        checks['${label}SplitGeometryReadable'] = false;
        observations['${label}SideBySideFailure'] = {
          'conversation': conversation?.toJson(),
          'plan': plan?.toJson(),
          'divider': divider?.toJson(),
        };
        await _ensureWidgetState(
          'plan-details-close',
          'plan-details',
          '${label}_layout_close',
          present: false,
        );
        return;
      }
      checks['${label}SplitGeometryReadable'] = true;
      checks['${label}SideBySideReadable'] =
          plan.width >= _minimumPlanWidth &&
          conversation.width >= _minimumConversationWidth;

      // 视觉契约：动作组沿输入框右缘、两按钮同高同基线且主操作在右；头部动作组同基线。
      _recordActionAlignment(
        prefix: label,
        feedback: await _readRect('plan-feedback-input'),
        revise: await _readRect('plan-submit-revision'),
        approve: await _readRect('plan-approve'),
      );
      _recordHeaderAlignment(
        prefix: label,
        expectReadingToggle: true,
        panel: plan,
        toggle: await _readRect('plan-details-reading-mode'),
        close: await _readRect('plan-details-close'),
      );
      await shot('$label-plan-actions-aligned');

      // 先收窄计划：这一方向在任何可用宽度下都有空间，证明拖动确实交给组件。
      await driver.dragBy(
        find.byValueKey('plan-resize-handle'),
        dx: 160,
        timeout: const Duration(seconds: 30),
      );
      final narrowedPlan = await _readRect('plan-details');
      final widenedConversation = await _readRect(_readingAreaKey);
      checks['${label}DragNarrowsPlan'] =
          narrowedPlan != null &&
          widenedConversation != null &&
          narrowedPlan.width < plan.width - _rectEpsilon &&
          widenedConversation.width > conversation.width + _rectEpsilon;
      checks['${label}PlanHonoursMinimum'] =
          narrowedPlan != null &&
          narrowedPlan.width >= _minimumPlanWidth - _rectEpsilon;
      await shot('$label-plan-dragged-narrow');

      // 再向左拖到极限：计划可以宽于对话，对话守住 400px 下限（组件求解边界）。
      await driver.dragBy(
        find.byValueKey('plan-resize-handle'),
        dx: -12000,
        timeout: const Duration(seconds: 30),
      );
      final widePlan = await _readRect('plan-details');
      final wideConversation = await _readRect(_readingAreaKey);
      checks['${label}ConversationFloorHolds'] =
          wideConversation != null &&
          (wideConversation.width - _minimumConversationWidth).abs() <=
              _rectEpsilon;
      await shot('$label-plan-limit');
      if (widePlan == null || wideConversation == null) {
        throw StateError('plan layout: the limit geometry could not be read');
      }
      // 计划宽度可以超过可用宽度的一半（旧实现的上限正是可用宽度的一半）。
      final available =
          widePlan.width + wideConversation.width + _planDividerThickness;
      checks['${label}PlanCanExceedConversation'] =
          widePlan.width > available / 2;

      // 展开阅读：占满会话阅读区域，且不再有无意义的分隔条。
      await _ensureWidgetState(
        'plan-details-reading-mode',
        'plan-resize-handle',
        '${label}_reading_full_width',
        present: false,
      );
      final fullWidth = await _readRect('plan-details');
      checks['${label}FullWidthReading'] =
          fullWidth != null && fullWidth.width >= available - _rectEpsilon;
      checks['${label}FullWidthKeepsFeedbackBar'] =
          await _widgetHolds('plan-feedback-input', present: true) &&
          await _widgetHolds('plan-approve', present: true);
      await shot('$label-plan-full-width');

      // 恢复并排：宽度回到展开前，阅读布局切换不重置宽度。
      await _ensureWidgetState(
        'plan-details-reading-mode',
        'plan-resize-handle',
        '${label}_reading_restore_split',
        present: true,
      );
      final restored = await _readRect('plan-details');
      checks['${label}RestoreKeepsWidth'] =
          restored != null &&
          (restored.width - widePlan.width).abs() <= _rectEpsilon;
      await shot('$label-plan-restore-split');

      await _ensureWidgetState(
        'plan-details-close',
        'plan-details',
        '${label}_layout_close',
        present: false,
      );
      // 关闭后普通输入与摘要入口都回来，反馈栏仍是同一交互的唯一写入者。
      checks['${label}LayoutInteractionsCurrent'] =
          activeInteractionOf(await snapshot())?['id'] == expectedInteractionId;
    } finally {
      if (restoreGeometry != null && resizePid != null) {
        final restoredWindow = resizeOwnedWindow(
          guiPid: resizePid,
          width: restoreGeometry.width,
          height: restoreGeometry.height,
        );
        if (!restoredWindow.resized) {
          throw StateError(
            'plan layout: could not restore GUI window '
            '(${restoredWindow.reason})',
          );
        }
        await _settleAfterResize(null, expectNarrower: false);
      }
    }
  }

  /// 窄窗与短窗：直接全宽阅读，计划正文、反馈与决定按钮都仍在窗口内。
  Future<void> _narrowPlanLayoutContract(
    String label,
    String expectedInteractionId,
  ) async {
    final guiPid = await _guiProcessId();
    if (guiPid == null) {
      // 窄/短窗几何是必需证据：拿不到 GUI pid 就是能力缺失，必须失败传播。
      checks['${label}NarrowWindowResized'] = false;
      pendingEvidence.add(
        'narrow plan layout: the driver did not expose the GUI process id',
      );
      return;
    }
    await _ensureWidgetState(
      'plan-summary',
      'plan-details',
      '${label}_narrow_open',
      present: true,
    );
    final wideShell = await _readRect('studio-shell');
    final narrow = resizeOwnedWindow(
      guiPid: guiPid,
      width: _narrowPlanWindowWidth,
      height: _narrowPlanWindowHeight,
    );
    if (!narrow.resized) {
      // 窗口无法改小时窄/短窗布局无法判定：记录失败而不是跳过。
      checks['${label}NarrowWindowResized'] = false;
      pendingEvidence.add(
        'narrow plan layout: driver could not resize the GUI window '
        '(${narrow.reason})',
      );
      return;
    }
    final original = narrow.original!;
    try {
      checks['${label}NarrowWindowResized'] = narrow.applied != null;
      await _settleAfterResize(wideShell, expectNarrower: true);
      final shell = await _readRect('studio-shell');
      // 全宽阅读覆盖的是会话阅读区域，而不是含侧栏的整个窗口。
      final readingArea = await _readRect(_readingAreaKey);
      final plan = await _readRect('plan-details');
      final feedback = await _readRect('plan-feedback-input');
      final approve = await _readRect('plan-approve');
      final dividerAbsent = !await _widgetHolds(
        'plan-resize-handle',
        present: true,
      );
      checks['${label}NarrowUsesFullWidthReading'] = dividerAbsent;
      checks['${label}NarrowPlanCoversReadingArea'] =
          readingArea != null &&
          plan != null &&
          (plan.width - readingArea.width).abs() <= _rectEpsilon;
      checks['${label}NarrowFeedbackReachable'] =
          shell != null &&
          feedback != null &&
          approve != null &&
          shell.contains(feedback) &&
          shell.contains(approve);
      observations['${label}NarrowRects'] = {
        'shell': shell?.toJson(),
        'readingArea': readingArea?.toJson(),
        'plan': plan?.toJson(),
        'feedback': feedback?.toJson(),
        'approve': approve?.toJson(),
      };
      checks['${label}NarrowInteractionCurrent'] =
          activeInteractionOf(await snapshot())?['id'] == expectedInteractionId;
      // 窄/短窗同样要求动作组沿输入右缘、两按钮同高且完整可达。
      _recordActionAlignment(
        prefix: '${label}Narrow',
        feedback: feedback,
        revise: await _readRect('plan-submit-revision'),
        approve: approve,
      );
      // 窄窗口无法并排：阅读切换本就不存在，这里断言它缺席而关闭仍可达。
      _recordHeaderAlignment(
        prefix: '${label}Narrow',
        expectReadingToggle: false,
        panel: plan,
        toggle: await _readRect('plan-details-reading-mode'),
        close: await _readRect('plan-details-close'),
      );
      await shot('$label-plan-narrow-short');
    } finally {
      final restored = resizeOwnedWindow(
        guiPid: guiPid,
        width: original.width,
        height: original.height,
      );
      if (!restored.resized) {
        throw StateError(
          'narrow plan layout: could not restore GUI window '
          '(${restored.reason})',
        );
      }
    }
    await _settleAfterResize(null, expectNarrower: false);
    await _ensureWidgetState(
      'plan-details-close',
      'plan-details',
      '${label}_narrow_close',
      present: false,
    );
  }

  /// Reads the GUI process id so the X11 window is matched by `_NET_WM_PID`.
  Future<int?> _guiProcessId() async {
    try {
      final decoded = jsonDecode(
        await driver.requestData('pid', timeout: const Duration(seconds: 15)),
      );
      final pid = decoded is Map ? decoded['pid'] : null;
      if (pid is int && pid > 0) return pid;
    } on Object {
      // Recorded as pending evidence by the caller.
    }
    return null;
  }

  /// Bounded wait for the new geometry to reach Flutter's real layout.
  Future<void> _settleAfterResize(
    DriverRect? before, {
    required bool expectNarrower,
  }) async {
    final deadline = DateTime.now().add(_resizeSettleDeadline);
    while (DateTime.now().isBefore(deadline)) {
      final current = await _readRect('studio-shell');
      if (current != null && current.width > 0) {
        final changed =
            before == null ||
            (current.width - before.width).abs() > _rectEpsilon ||
            (current.height - before.height).abs() > _rectEpsilon;
        final directionOk =
            before == null ||
            (expectNarrower
                ? current.width <= before.width + _rectEpsilon
                : current.width >= before.width - _rectEpsilon);
        if (changed && directionOk) return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
  }

  // ------------------------------------------------------ plan answers --

  /// 计划反馈栏的真实键盘路径：空输入与 Shift+Enter 不回答，Enter 才提交一次。
  Future<void> _answerPlanByEnter(
    String label, {
    required String expectedInteractionId,
  }) async {
    await _tap('plan-feedback-input');
    await driver.enterText(' ');
    await driver.sendTextInputAction(TextInputAction.send);
    // 空（仅空白）反馈按同一准入判定被拒绝：给命令一个可观测窗口，不看按钮状态。
    await Future<void>.delayed(const Duration(seconds: 2));
    final afterBlank = activeInteractionOf(await snapshot());
    checks['${label}BlankEnterDoesNotAnswer'] =
        afterBlank != null && afterBlank['id'] == expectedInteractionId;

    await driver.enterText('draft line');
    await driver.pressKey(
      _logicalEnterKeyId,
      _physicalEnterUsbHidUsage,
      shift: true,
    );
    // 直接读同一个 TextField 的正文（Driver `getText` 对 TextField 读
    // `controller.text`）：不等待光标闪烁等动画清空，也不用睡眠兜底。
    final composed = await _readFeedbackText();
    observations['${label}ShiftEnterText'] = composed;
    checks['${label}ShiftEnterAddsLine'] = composed == 'draft line\n';
    final afterShift = activeInteractionOf(await snapshot());
    checks['${label}ShiftEnterDoesNotAnswer'] =
        afterShift != null && afterShift['id'] == expectedInteractionId;
    await shot('$label-shift-enter-line');

    // 演示后用原精确反馈覆盖正文，再走 Enter 的真实提交路径。
    await driver.enterText(_revisionFeedback);
    try {
      await driver.sendTextInputAction(TextInputAction.send);
    } on TimeoutException catch (error, stackTrace) {
      var recovered = false;
      try {
        await waitFor(
          (snapshot) {
            final interaction = activeInteractionOf(snapshot);
            return interaction == null ||
                interaction['id'] != expectedInteractionId;
          },
          '${label}_enter_effect',
          timeout: const Duration(seconds: 30),
        );
        recovered = true;
      } on Object {
        // The effect never arrived: the original timeout stays the failure.
      }
      if (!recovered) Error.throwWithStackTrace(error, stackTrace);
      counts['${label}EnterConfirmedByEffect'] = true;
    }
  }

  // ----------------------------------------------------- plan receipts --

  /// 已回答计划的回执：先待确认不出现第二张卡，回答后出现可展开的原回复。
  Future<void> _planReceiptContract(
    String label, {
    String? expectedReply,
  }) async {
    final Map<String, dynamic> current = await snapshot();
    final rows = [
      for (final row in _planRows(current))
        if (!row.pending) row.id,
    ];
    if (rows.isEmpty) {
      checks['${label}PlanReceiptRow'] = false;
      return;
    }
    var tiles = 0;
    var replyFound = expectedReply == null;
    for (final rowId in rows) {
      final tile = find.byValueKey('timeline-plan-receipt-$rowId');
      if (!await _widgetHoldsByKey(
        find.byValueKey('timeline-plan-receipt-$rowId'),
      )) {
        continue;
      }
      tiles++;
      final reply = find.byValueKey('timeline-plan-receipt-reply-$rowId');
      // 展开同样按当前可见状态决定：已经展开就不再点（再点会收起并让后置断言超时）。
      var expanded = false;
      try {
        await driver.waitFor(reply, timeout: const Duration(seconds: 2));
        expanded = true;
        counts['${label}ReceiptAlreadyExpanded'] = true;
      } on Object {
        expanded = false;
      }
      if (!expanded) {
        await driver.rawTap(tile, timeout: const Duration(seconds: 30));
      }
      try {
        await driver.waitFor(reply, timeout: const Duration(seconds: 10));
      } on Object {
        continue;
      }
      if (expectedReply != null &&
          !replyFound &&
          await _widgetHoldsByKey(
            find.descendant(of: reply, matching: find.text(expectedReply)),
          )) {
        replyFound = true;
      }
    }
    // 有已回答的计划行就必须渲染计划专用回执；退回普通问答或什么都不显示都会失败。
    checks['${label}PlanReceiptRow'] = tiles > 0;
    checks['${label}PlanReceiptReplies'] = replyFound;
    counts['${label}PlanReceiptTiles'] = tiles;
    counts['${label}PlanReceiptRows'] = rows.length;
    observations['${label}PlanReceiptRows'] = rows;
    if (expectedReply != null) {
      checks['${label}PlanReceiptKeepsFeedback'] = replyFound;
    }
    await shot('$label-plan-receipt');
  }

  /// 快照里的计划确认行（driver 只读 typed 投影）。
  ///
  /// `pending` 来自 canonical 交互状态（`userInput.state == 'pending'`），不是从工具
  /// arguments/result 或当前 Plan 反推；`decision` 是已回答回执的权威决定。驱动据此
  /// 只对「当前待确认行」断言不出现历史回执，同时要求旧 resolved 回执仍然存在。
  List<({String id, bool pending, String? decision})> _planRows(
    Map<String, dynamic> snapshot,
  ) {
    final rows = <({String id, bool pending, String? decision})>[];
    for (final row in timelineRows(snapshot)) {
      final id = row['id'];
      final userInput = row['userInput'];
      if (row['type'] != 'userInput' ||
          id is! String ||
          userInput is! Map<String, dynamic> ||
          userInput['isPlanConfirmation'] != true) {
        continue;
      }
      rows.add((
        id: id,
        pending: userInput['state'] == 'pending',
        decision: userInput['planDecision'] as String?,
      ));
    }
    return rows;
  }

  Future<bool> _widgetHoldsByKey(SerializableFinder finder) async {
    try {
      await driver.waitFor(finder, timeout: const Duration(seconds: 10));
      return true;
    } on Object {
      return false;
    }
  }

  /// Reads the shared identity evidence written by earlier phases.
  Future<Map<String, dynamic>> _readObserved() async {
    final file = File('${output.path}/$_observedFile');
    if (!await file.exists()) {
      throw StateError(
        'plan-recovery: $phase needs ${file.path} from an earlier phase',
      );
    }
    final value = jsonDecode(await file.readAsString());
    if (value is! Map<String, dynamic>) {
      throw StateError(
        'plan-recovery: observed identity file is not an object',
      );
    }
    return value;
  }

  Map<String, dynamic> _branchOf(Map<String, dynamic> observed, String branch) {
    final value = observed[branch];
    if (value is! Map<String, dynamic> ||
        (value['threadId'] as String?) == null ||
        (value['interactionId'] as String?) == null ||
        (value['turnId'] as String?) == null) {
      throw StateError(
        'plan-recovery: observed identity file has no complete $branch branch',
      );
    }
    return value;
  }

  /// Merges one branch into the shared identity file without dropping earlier
  /// branches, so later phases can still read them.
  Future<void> _writeObserved(Map<String, Object?> branch) async {
    final file = File('${output.path}/$_observedFile');
    Map<String, dynamic> current = <String, dynamic>{};
    if (await file.exists()) {
      final value = jsonDecode(await file.readAsString());
      if (value is Map<String, dynamic>) current = value;
    }
    current.addAll(branch);
    await file.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(current)}\n',
    );
  }

  Future<void> mark(String value) async {
    stage = value;
    // The per-stage marker is an append-only fact: shutdown and the final
    // summary rewrite the latest-stage file within moments, so a coordinator
    // polling that file's content could skip a stage between two polls.
    await File('${coord.path}/plan-recovery-stage-$value').writeAsString(value);
    await stageFile.writeAsString(value);
  }

  Future<Map<String, dynamic>> snapshot() => driver.readSnapshot();

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
      if (abort != null && abort(current)) {
        throw StateError('$label aborted: ${summarize(current)}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError(
      'timed out waiting for $label: '
      '${last == null ? const {} : summarize(last)}',
    );
  }

  Future<void> shot(String name) async {
    await File('${output.path}/plan-recovery-$name.png')
        .writeAsBytes(await driver.screenshot());
  }

  /// Saves the last snapshot and a screenshot for a failed journey.
  Future<void> captureFailure() async {
    try {
      await File(
        '${output.path}/plan-recovery-$phase-failure-snapshot.json',
      ).writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(await driver.readSnapshot().timeout(const Duration(seconds: 10)))}\n',
      );
    } on Object {
      // Ignored: the summary still carries the original error and stage.
    }
    try {
      final png = await driver.screenshot().timeout(
        const Duration(seconds: 20),
      );
      await File('${output.path}/plan-recovery-$phase-failure.png')
          .writeAsBytes(png);
    } on Object {
      // Ignored: see above.
    }
  }

  Future<void> shutdown() async {
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

  Future<void> writeSummary({
    required Object? failure,
    required Object? shutdownFailure,
  }) async {
    final failedChecks = checks.entries
        .where((entry) => entry.value != true)
        .map((entry) => entry.key)
        .toList(growable: false);
    final summary = <String, Object?>{
      'scenario': 'plan-recovery',
      'phase': phase,
      'verdict': 'pending',
      'status': failure == null && failedChecks.isEmpty ? 'complete' : 'failed',
      'stage': stage,
      'error': failure?.toString(),
      'shutdownError': shutdownFailure?.toString() ?? shutdownError,
      'failedChecks': failedChecks,
      'checks': checks,
      'observations': observations,
      'counts': counts,
      'completedAt': DateTime.now().toUtc().toIso8601String(),
      'pendingEvidence': pendingEvidence,
    };
    await File(
      '${output.path}/plan-recovery-$phase-summary.json',
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(summary)}\n');
  }

  void raiseIfFailed(Object? shutdownFailure) {
    final failedChecks = checks.entries
        .where((entry) => entry.value != true)
        .map((entry) => entry.key)
        .toList(growable: false);
    if (failedChecks.isNotEmpty) {
      throw StateError(
        'plan-recovery $phase checks failed: ${failedChecks.join(', ')}',
      );
    }
    if (shutdownFailure != null || shutdownError != null) {
      throw StateError(
        'plan-recovery $phase native GUI shutdown failed: '
        '${shutdownFailure ?? shutdownError}',
      );
    }
  }
}
