import 'dart:async';

import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart' show LatestValue;
import 'package:anywork_client/workspace.dart';
import 'package:anywork_client/workspace_ports.dart';

import '../../platform/error_log.dart';
import 'exit_deadline.dart';
import 'exit_participant.dart';
import 'exit_state.dart';
import 'native_exit_host.dart';

/// One application instance, one first intent/deadline and one native finalizer.
///
/// Timeout is an observation result, never cancellation/join evidence. Every
/// original Future/participant remains strongly held here for recovery; actual
/// resource handles and permits remain with their original domain owners.
final class ApplicationExitCoordinator {
  ApplicationExitCoordinator({
    required ApplicationLifecyclePort lifecycle,
    required NativeExitHost host,
    required ApplicationEditProducerRegistry editProducers,
    required List<ApplicationCloseParticipant> participants,
    required void Function() sealOperations,
    required void Function() detachPresentation,
    required String? Function() readyUpdateVersion,
    Future<void> Function()? releaseDesktopShell,
    Future<void> Function(Duration remaining, bool allowReading)? presentNotice,
  }) : _lifecycle = lifecycle,
       _host = host,
       _editProducers = editProducers,
       _participants = List.unmodifiable(participants),
       _sealOperations = sealOperations,
       _detachPresentation = detachPresentation,
       _readyUpdateVersion = readyUpdateVersion,
       _releaseDesktopShell = releaseDesktopShell,
       _presentNotice = presentNotice;

  final ApplicationLifecyclePort _lifecycle;
  final NativeExitHost _host;
  final ApplicationEditProducerRegistry _editProducers;
  final List<ApplicationCloseParticipant> _participants;
  final void Function() _sealOperations;
  final void Function() _detachPresentation;
  final String? Function() _readyUpdateVersion;
  final Future<void> Function()? _releaseDesktopShell;
  final Future<void> Function(Duration remaining, bool allowReading)? _presentNotice;

  final _state = LatestValue(const ApplicationExitState(
    phase: ApplicationExitPhase.running,
    intent: null,
    readyUpdateVersion: null,
    unresolved: [],
    externalIssues: [],
    report: null,
    diagnosticsIssue: null,
  ));
  ReadonlyLatestValue<ApplicationExitState> get state => _state.readonly;

  final List<StudioShutdownIssue> _sealingIssues = [];
  final List<_CloseAttempt> _closeAttempts = [];
  final List<Future<void>> _externalTasks = [];
  ExitDeadline? _deadline;
  Future<StudioExitReport>? _exit;
  Future<void>? _hostExit;
  Future<void>? _arming;
  Future<void>? _beginRuntime;
  Future<StudioExitReport>? _nativeFinalizer;
  Future<void>? _diagnostics;
  int _attemptSequence = 0;

  /// Root-only action. Repeated requests join the original responsibility,
  /// including updateRestart after ordinary exit (and the reverse).
  Future<StudioExitReport> exit(ExitIntent intent) {
    final existing = _exit;
    if (existing != null) return existing;
    final completion = Completer<StudioExitReport>();
    _exit = completion.future;
    final deadline = ExitDeadline();
    _deadline = deadline;
    // Arm the independent native watchdog before running any Dart producer or
    // diagnostic callback. A stuck isolate must not postpone the first limit.
    final arm = Future<int>.sync(_host.beginExit);
    _arming = arm.then<void>(deadline.anchor, onError: (Object error, StackTrace stack) {
      // Failure is not permission to manufacture a new thirty-second budget.
      _sealingIssues.add(_issue('host-begin-exit', error, stack));
    });
    String? version;
    _synchronously('update-notice', () => version = _readyUpdateVersion());
    _state.publish(_state.value.copyWith(
      phase: ApplicationExitPhase.sealing,
      intent: intent,
      readyUpdateVersion: version,
    ));

    // Finish valid auto-save handoffs while repositories still accept them.
    // A failing producer must not prevent any other owner receiving seal.
    // Seal registration first. Unregister/reentrant navigation cannot remove a
    // producer from this strong snapshot halfway through shutdown.
    final producers = _editProducers.sealAndSnapshot();
    for (final producer in producers) {
      _synchronously('edit-producer', producer.sealAndHandoff);
    }
    for (final participant in _participants) {
      _synchronously(participant.name, participant.seal);
    }
    _synchronously('operations', _sealOperations);
    // The builder outside the Router observes exiting above. This additional
    // synchronous detach closes unpublished/display candidates immediately.
    _synchronously('presentation-detach', _detachPresentation);
    unawaited(_drive(intent, deadline).then(
      completion.complete,
      onError: completion.completeError,
    ));
    return completion.future;
  }

  /// Native/tray/system adapters all call the same instance action. Driver can
  /// call exit() to inspect its typed result without terminating the process.
  Future<void> requestHostExit(ExitIntent intent) {
    final existing = _hostExit;
    if (existing != null) return existing;
    final completion = Completer<void>();
    _hostExit = completion.future;
    unawaited(_finishHost(intent).then(
      completion.complete,
      onError: completion.completeError,
    ));
    return completion.future;
  }

  Future<StudioExitReport> _drive(ExitIntent intent, ExitDeadline deadline) async {
    await _arming;

    final externalIssues = List<StudioShutdownIssue>.of(_sealingIssues);
    _state.publish(_state.value.copyWith(
      phase: ApplicationExitPhase.closingDartOwners,
      externalIssues: List.unmodifiable(externalIssues),
    ));

    // Begin is only arm/cancel, not finalize. Attach error observation before
    // waiting on any external owner, and start every independent close now.
    _beginRuntime = Future.sync(() => _lifecycle.beginRuntimeExit(
      remainingMs: deadline.cleanupMs,
    ));
    final earlyExit = _observeExternal(
      'runtime-early-exit', _beginRuntime!, deadline, externalIssues,
    );
    for (final participant in _participants) {
      final attempt = _CloseAttempt(
        participant,
        AttemptId(++_attemptSequence),
        deadline.cleanupDeadline,
      );
      _closeAttempts.add(attempt);
    }
    final closes = [
      for (final attempt in _closeAttempts)
        attempt.observe(deadline, _issue),
    ];
    final shellRelease = _releaseDesktopShell;
    Future<void>? shellObservation;
    if (shellRelease != null) {
      final task = Future<void>.sync(shellRelease);
      _externalTasks.add(task);
      shellObservation = _observeExternal(
        'desktop-shell', task, deadline, externalIssues,
      );
    }

    // Rendering never gates cancellation or a domain close. Covered Settings
    // pages are unmounted by MaterialApp.builder, not by a paused observer.
    if (_state.value.readyUpdateVersion != null) {
      await _hostNotice(deadline, allowReading: false);
    }
    final reports = await Future.wait(closes);
    await earlyExit;
    // Every registered external task has error handling from admission onward.
    // Raw shell tasks are observed by their paired bounded observer, not joined
    // unboundedly here.
    for (final report in reports) {
      for (final resource in report.unresolved) {
        externalIssues.addAll(resource.issues.map((issue) => issue.diagnostic));
      }
    }
    // The shell observation can finish independently of the close reports.
    if (shellObservation != null) await shellObservation;
    final unresolved = [for (final report in reports) ...report.unresolved];
    final frozenIssues = List<StudioShutdownIssue>.unmodifiable(externalIssues.toSet());
    _state.publish(_state.value.copyWith(
      phase: ApplicationExitPhase.finalizingRuntime,
      unresolved: unresolved,
      externalIssues: frozenIssues,
    ));

    // No external work is first observed after this point. This is the ONLY
    // native finalizer call; a timeout leaves its original Future alive.
    _nativeFinalizer = Future.sync(() => _lifecycle.shutdownRuntime(
      remainingMs: deadline.cleanupMs,
      externalIssues: frozenIssues,
      intent: intent,
    ));
    StudioExitReport report;
    try {
      report = await _nativeFinalizer!.timeout(deadline.cleanup);
    } catch (error, stack) {
      report = StudioExitReport(
        shutdown: StudioShutdownReport(
          outcome: ShutdownOutcome.degraded,
          issues: [...frozenIssues, _issue('runtime-finalizer', error, stack)],
          persistence: const PendingPersistence.unknown(),
        ),
        updateHandoff: const UpdateHandoff.notRequested(),
      );
    }
    // A contract-violating Clean must not be presented as safe. This cannot
    // undo a native release: the adapter/native implementation must enforce it.
    if (report.shutdown.outcome == ShutdownOutcome.clean &&
        (frozenIssues.isNotEmpty ||
            report.shutdown.issues.isNotEmpty ||
            report.shutdown.persistence is! DrainedPendingPersistence)) {
      report = report.copyWith(shutdown: report.shutdown.copyWith(
        outcome: ShutdownOutcome.degraded,
        issues: [
          ...frozenIssues,
          ...report.shutdown.issues,
          _issue('runtime-contract', const FormatException(
            'Clean shutdown prerequisites were not confirmed',
          ), StackTrace.current),
        ],
      ));
    }

    _state.publish(_state.value.copyWith(
      phase: ApplicationExitPhase.finishingDiagnostics,
      report: report,
    ));
    StudioShutdownIssue? diagnosticsIssue;
    // This independent diagnostic command is not another runtime finalizer and
    // must also run when startup failed or runtime was never installed.
    _diagnostics = Future.sync(_lifecycle.finishShutdownDiagnostics);
    try {
      await _diagnostics!.timeout(deadline.remaining);
    } catch (error, stack) {
      diagnosticsIssue = _issue('shutdown-diagnostics', error, stack);
    }
    _state.publish(_state.value.copyWith(
      phase: ApplicationExitPhase.finished,
      diagnosticsIssue: diagnosticsIssue,
    ));
    return report;
  }

  Future<void> _observeExternal(
    String stage,
    Future<void> original,
    ExitDeadline deadline,
    List<StudioShutdownIssue> issues,
  ) async {
    try {
      await original.timeout(deadline.cleanup);
    } catch (error, stack) {
      issues.add(_issue(stage, error, stack));
    }
  }

  Future<void> _finishHost(ExitIntent intent) async {
    final report = await exit(intent);
    final deadline = _deadline!;
    final issue = report.shutdown.issues.firstOrNull;
    try {
      await _host.updateDiagnostics(
        stage: report.shutdown.outcome.name,
        code: issue?.code,
        correlationId: issue?.correlationId,
        pendingCommits: switch (report.shutdown.persistence) {
          CountPendingPersistence(:final count) => count,
          _ => null,
        },
        remaining: deadline.remaining,
      );
    } catch (error, stack) {
      recordDartError(error, stack, stage: 'exit-diagnostics');
    }
    if (_state.value.failed) await _hostNotice(deadline, allowReading: true);
    final success = report.shutdown.outcome != ShutdownOutcome.degraded &&
        report.updateHandoff is! FailedUpdateHandoff &&
        _state.value.diagnosticsIssue == null;
    await _host.finishExit(
      exitCode: success ? 0 : 1,
      remaining: deadline.remaining,
    );
  }

  Future<void> _hostNotice(
    ExitDeadline deadline, {
    required bool allowReading,
  }) async {
    try {
      await _host.showMainWindow().timeout(deadline.remaining);
    } catch (error, stack) {
      recordDartError(error, stack, stage: 'exit-show-window');
    }
    final present = _presentNotice;
    if (present == null || deadline.remainingMs == 0) return;
    try {
      await present(deadline.remaining, allowReading).timeout(deadline.remaining);
    } catch (error, stack) {
      recordDartError(error, stack, stage: 'exit-notice');
    }
  }

  void _synchronously(String stage, void Function() action) {
    try {
      action();
    } catch (error, stack) {
      _sealingIssues.add(_issue(stage, error, stack));
    }
  }

  StudioShutdownIssue _issue(String stage, Object error, StackTrace stack) {
    final failure = error is StudioFailure ? error : null;
    final correlation = failure?.correlationId.isNotEmpty == true
        ? failure!.correlationId
        : newStudioCorrelationId();
    recordDartError(error, stack, stage: stage, correlationId: correlation);
    return StudioShutdownIssue(
      stage: stage,
      code: failure?.code.name ??
          (error is TimeoutException ? 'deadlineExceeded' : 'cleanupFailed'),
      message: failure?.message ?? 'Application cleanup did not confirm.',
      retryable: failure?.retryable ?? false,
      correlationId: correlation,
    );
  }
}

/// Keeps a pending completion after its observation deadline; retries operate
/// on the original owner, never a reopened resource or a repeated command.
final class _CloseAttempt {
  _CloseAttempt(this.participant, this.id, DateTime deadline) {
    original = Future.sync(() => participant.close(deadline: deadline));
  }

  final ApplicationCloseParticipant participant;
  final AttemptId id;
  late final Future<CloseReport> original;

  Future<CloseReport> observe(
    ExitDeadline deadline,
    StudioShutdownIssue Function(String, Object, StackTrace) issue,
  ) async {
    try {
      return await original.timeout(deadline.cleanup);
    } catch (error, stack) {
      return CloseReport(unresolved: [UnresolvedResource(
        owner: participant.name,
        attemptId: id,
        issues: [FeedCloseIssue(
          diagnostic: issue(participant.name, error, stack),
          recovery: error is TimeoutException
              ? CleanupRecovery.awaitCompletion
              : CleanupRecovery.terminal,
        )],
      )]);
    }
  }
}
