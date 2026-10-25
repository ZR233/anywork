import 'dart:async';

import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/startup_repository.dart';
import '../domain/startup_values.dart';
import 'startup_port.dart';
import 'startup_progress_owner.dart';
import 'startup_reads.dart';
import 'startup_state_view.dart';

StartupRepository createStartupRepository({
  required StartupPort port,
  required OperationRecorder operations,
  required ResourceBudget budget,
}) => _StartupRepository(port, operations, budget);

final class _StartupRepository implements StartupRepository {
  _StartupRepository(this._port, this._operations, this._budget) {
    _view = StartupStateView(_source, _budget);
    _reads = StartupReads(_port, _budget);
  }

  final StartupPort _port;
  final OperationRecorder _operations;
  final ResourceBudget _budget;
  final LatestValue<StartupState> _source = LatestValue(
    const StartupState.idle(),
  );
  late final StartupStateView _view;
  late final StartupReads _reads;
  final Map<AttemptId, _StartupAttempt> _attempts = {};
  final List<(Object, StackTrace)> _causes = [];
  final List<UnresolvedResource> _cleanupIssues = [];
  _StartupAttempt? _active;
  OperationTicket<RuntimeReady>? _ready;
  Future<void>? _cleanup;
  int _sequence = 0;
  bool _sealed = false;
  bool _closed = false;
  bool _unknown = false;

  @override
  ReadonlyLatestValue<StartupState> get state => _view;

  void _ensureOpen() {
    if (_sealed) throw _cancelled;
  }

  @override
  OperationTicket<RuntimeReady> start() {
    _ensureOpen();
    if (_active case final attempt?) return attempt.writer.ticket;
    if (_ready case final ticket?) return ticket;
    if (_unknown || _attempts.isNotEmpty) {
      throw const StudioFailure(
        code: StudioFailureCode.conflict,
        message: 'The previous startup still owns unresolved work or an unknown outcome.',
        retryable: false,
        correlationId: '',
      );
    }
    final ResourcePermit permit;
    try {
      permit = _budget.acquire(
        ResourceKind.observer,
        owner: 'startup-progress',
        phase: ResourcePhase.opening,
      );
    } on ResourceBudgetExceeded catch (error) {
      throw error.failure;
    }
    final OperationWriter<RuntimeReady> writer;
    try {
      writer = _operations.begin<RuntimeReady>(target: 'startup');
    } catch (_) {
      permit.release();
      rethrow;
    }
    final attempt = _StartupAttempt(AttemptId(++_sequence), writer, permit);
    _attempts[attempt.id] = attempt;
    _active = attempt;
    // Ownership, ticket and permit precede every library/native await.
    _source.publish(
      const StartupState.starting(
        attemptId: null,
        phase: StartupPhase.loadingLibrary(),
      ),
    );
    unawaited(_run(attempt));
    return writer.ticket;
  }

  Future<void> _run(_StartupAttempt attempt) async {
    RuntimeReady? confirmed;
    var startIssued = false;
    try {
      _ensureOpen();
      await _port.initializeLibrary();
      _ensureOpen();
      _source.publish(
        const StartupState.starting(
          attemptId: null,
          phase: StartupPhase.preparingAttempt(),
        ),
      );
      final nativeAttempt = await _port.prepareStartupAttempt();
      attempt.nativeAttempt = nativeAttempt;
      _ensureOpen();
      final progress = StartupProgressOwner(
        port: _port,
        attemptId: nativeAttempt,
        onStage: (stage) {
          if (!_sealed && identical(_active, attempt)) {
            _source.publish(
              StartupState.starting(
                attemptId: nativeAttempt,
                phase: StartupPhase.native(stage: stage),
              ),
            );
          }
        },
      );
      attempt.progress = progress;
      await progress.open();
      _ensureOpen();
      attempt.permit.mark(ResourcePhase.active);
      startIssued = true;
      confirmed = await _port.startStudioRuntime(nativeAttempt);
      // Stage Data and ordered terminal control are real work, not a latest poll.
      await progress.finish();
      if (!_sealed) {
        _source.publish(
          StartupState.ready(attemptId: nativeAttempt, result: confirmed),
        );
      }
      attempt.writer.acknowledged(confirmed);
      _ready = attempt.writer.ticket;
    } catch (error, stack) {
      _causes.add((error, stack));
      final failure = error is CommandDispatchFailure
          ? error.failure
          : error is StudioFailure
          ? error
          : _protocol('Startup did not complete through its typed boundary');
      if (!_sealed) {
        _source.publish(
          StartupState.failed(attemptId: attempt.nativeAttempt, error: failure),
        );
      }
      if (confirmed != null) {
        attempt.writer.acknowledgedSynchronizationFailed(
          failure,
          value: confirmed,
        );
        _ready = attempt.writer.ticket;
      } else {
        switch (error) {
          case RejectedCommandDispatchFailure():
            attempt.writer.rejected(failure);
          case ConfirmedWithoutUsableReceiptCommandDispatchFailure():
            attempt.writer.acknowledgedSynchronizationFailed(failure);
            _unknown = true;
          case CommittedButUnobservedCommandDispatchFailure(:final receipt):
            attempt.writer.synchronizationFailed(failure, receipt: receipt);
            _unknown = true;
          case UnknownOutcomeCommandDispatchFailure():
            attempt.writer.unknownOutcome(failure);
            _unknown = true;
          default:
            if (startIssued) {
              attempt.writer.unknownOutcome(failure);
              _unknown = true;
            } else {
              attempt.writer.rejected(failure);
            }
        }
      }
    } finally {
      try {
        await attempt.progress?.close();
      } catch (error, stack) {
        _causes.add((error, stack));
        attempt.issue = _issue(error, 'startupCleanupFailed');
      }
      attempt.done.complete();
      if (identical(_active, attempt)) _active = null;
      _releaseAttempt(attempt);
    }
  }

  @override
  Future<StartupRecovery?> readRecovery(RuntimeStartupReadRef reference) {
    _ensureOpen();
    return _reads.recovery(reference);
  }

  @override
  Future<StartupActiveTurnPage> readActiveTurns(
    RuntimeStartupReadRef reference, {
    int offset = 0,
    int limit = 32,
  }) {
    _ensureOpen();
    return _reads.activeTurns(reference, offset: offset, limit: limit);
  }

  @override
  void seal() {
    if (_sealed) return;
    _sealed = true;
    for (final attempt in _attempts.values) {
      attempt.progress?.requestClose();
    }
    _reads.seal();
  }

  @override
  Future<CloseReport> close({DateTime? deadline}) {
    seal();
    _view.close();
    if (!_closed) {
      _closed = true;
      _beginCleanup(retry: false);
    }
    return _waitCleanup(deadline);
  }

  @override
  Future<CloseReport> retryCleanup({DateTime? deadline}) {
    if (!_closed)
      throw _protocol('Close startup before explicitly retrying cleanup');
    _beginCleanup(retry: true);
    return _waitCleanup(deadline);
  }

  void _beginCleanup({required bool retry}) {
    if (_cleanup != null) return;
    final work = _join(retry, AttemptId(++_sequence));
    _cleanup = work;
    unawaited(
      work.whenComplete(() {
        if (identical(_cleanup, work)) _cleanup = null;
      }),
    );
  }

  Future<void> _join(bool retry, AttemptId cleanupId) async {
    final attempts = List.of(_attempts.values);
    for (final attempt in attempts) {
      attempt.progress?.requestClose();
    }
    try {
      await Future.wait([
        for (final attempt in attempts) _joinAttempt(attempt, retry),
        _reads.close(retry: retry),
      ]);
    } catch (error, stack) {
      _causes.add((error, stack));
      _cleanupIssues.add(
        UnresolvedResource(
          owner: 'startup-cleanup',
          attemptId: cleanupId,
          issues: [_issue(error, 'startupOwnerJoinFailed')],
        ),
      );
    }
  }

  Future<void> _joinAttempt(_StartupAttempt attempt, bool retry) async {
    await Future.wait([
      attempt.done.future,
      if (attempt.progress case final progress?) progress.close(retry: retry),
    ]);
    _releaseAttempt(attempt);
  }

  void _releaseAttempt(_StartupAttempt attempt) {
    if (!attempt.done.isCompleted || attempt.issue != null) return;
    if (attempt.progress != null && !attempt.progress!.complete) {
      attempt.permit.mark(ResourcePhase.unresolved);
      return;
    }
    attempt.permit.release();
    _attempts.remove(attempt.id);
  }

  Future<CloseReport> _waitCleanup(DateTime? deadline) async {
    final work = _cleanup;
    if (work != null) {
      try {
        if (deadline == null) {
          await work;
        } else {
          final remaining = deadline.difference(DateTime.now());
          await work.timeout(remaining.isNegative ? Duration.zero : remaining);
        }
      } on TimeoutException {
        // The actual work/handles and permits remain owned, with no new timer.
      }
    }
    return CloseReport(
      unresolved: [
        for (final attempt in _attempts.values)
          UnresolvedResource(
            owner: 'startup',
            attemptId: attempt.id,
            issues: [
              ...?attempt.progress?.issues,
              if (attempt.issue case final issue?) issue,
              if (!attempt.done.isCompleted ||
                  attempt.progress?.pending == true)
                _pending,
            ],
          ),
        ..._reads.unresolved,
        ..._cleanupIssues,
      ],
    );
  }

  static const _pending = FeedCloseIssue(
    diagnostic: StudioShutdownIssue(
      stage: 'startup',
      code: 'awaitingCompletion',
      message: 'Accepted startup work has not finished.',
      retryable: true,
      correlationId: '',
    ),
    recovery: CleanupRecovery.awaitCompletion,
  );

  static FeedCloseIssue _issue(Object error, String code) => FeedCloseIssue(
    diagnostic: StudioShutdownIssue(
      stage: 'startup',
      code: error is StudioFailure ? error.code.name : code,
      message: error is StudioFailure
          ? error.message
          : 'Startup owner cleanup failed.',
      retryable: error is StudioFailure && error.retryable,
      correlationId: error is StudioFailure ? error.correlationId : '',
    ),
    recovery: CleanupRecovery.terminal,
  );

  static StudioFailure _protocol(String message) => StudioFailure(
    code: StudioFailureCode.protocol,
    message: message,
    retryable: false,
    correlationId: '',
  );

  static const _cancelled = StudioFailure(
    code: StudioFailureCode.cancelled,
    message: 'Startup admission is sealed.',
    retryable: false,
    correlationId: '',
  );
}

final class _StartupAttempt {
  _StartupAttempt(this.id, this.writer, this.permit);
  final AttemptId id;
  final OperationWriter<RuntimeReady> writer;
  final ResourcePermit permit;
  final Completer<void> done = Completer<void>();
  int? nativeAttempt;
  StartupProgressOwner? progress;
  FeedCloseIssue? issue;
}
