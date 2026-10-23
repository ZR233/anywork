import 'dart:async';

import '../../../conversation.dart' show ConversationTurn, QueuedTurn, RunningTurn, CompletedTurn,
    CancelledTurn, FailedTurn, BudgetLimitedTurn, ThreadExecutionState, ThreadFacet, ThreadFacetStamp;
import '../../../operations_ports.dart';
import '../../../resources.dart';
import '../../../resources_ports.dart';
import '../domain/submission_values.dart';

/// A repository-owned, non-polling observation of one frozen input.
///
/// The execution source and release callback belong to a specific Session demand,
/// not the selected Thread. This owner never reads or claims Timeline content.
final class SubmittedInputObserver<T> {
  /// Takes the original demand on entry, even if permit/watch admission fails.
  /// Clean rollback rethrows the original error; failed rollback carries cleanup.
  factory SubmittedInputObserver({
    required String threadId,
    required String inputId,
    required ThreadFacetStamp origin,
    required AttemptId attemptId,
    required ReadonlyLatestValue<ThreadExecutionState> execution,
    required OperationWriter<T> operation,
    required ResourceBudget budget,
    required Future<InputAcceptanceEvidence?> Function() readAcceptance,
    required void Function() releaseDemand,
  }) {
    final owner = SubmittedInputObserver<T>._(threadId: threadId, inputId: inputId,
      origin: origin, attemptId: attemptId, execution: execution, operation: operation,
      budget: budget, readAcceptance: readAcceptance, releaseDemand: releaseDemand);
    try {
      owner._install();
      return owner;
    } catch (error, stack) {
      owner._lastCause = error;
      owner._lastStack = stack;
      owner._closing = true;
      owner._release();
      if (owner._released) Error.throwWithStackTrace(error, stack);
      // A concrete failed-construction owner, not an exception bus. The caller
      // receives its original failure AND the still-owned terminal close report.
      throw SubmittedInputObserverConstructionFailure<T>._(error, stack, owner);
    }
  }

  SubmittedInputObserver._({required this.threadId, required this.inputId,
    required this.origin, required this.attemptId,
    required ReadonlyLatestValue<ThreadExecutionState> execution,
    required OperationWriter<T> operation, required ResourceBudget budget,
    required Future<InputAcceptanceEvidence?> Function() readAcceptance,
    required void Function() releaseDemand}) : _execution = execution,
       _operation = operation,
       _budget = budget,
       _readAcceptance = readAcceptance,
       _releaseDemand = releaseDemand;

  void _install() {
    var installing = true;
    Object? callbackFailure;
    StackTrace? callbackStack;
    try {
      _permit = _budget.acquire(ResourceKind.observer,
        owner: 'input-evidence:${_operation.ticket.id.value}');
      // Protect the exact operation record independently of page/Widget observers.
      _retainedOperation = _operation.ticket.state.watch((_) {});
      _source = _execution.watch((state) {
        if (!installing) { _considerExecution(state); return; }
        try { _considerExecution(state); } catch (error, stack) {
          callbackFailure ??= error;
          callbackStack ??= stack;
    }
      });
      if (callbackFailure case final error?) Error.throwWithStackTrace(error, callbackStack!);
      _considerExecution(_execution.value);
    } finally {
      installing = false;
    }
  }

  static final RegExp _digest = RegExp(r'^sha256:[0-9a-f]{64}$');

  final String threadId;
  final String inputId;
  SubmitPromptReceipt? _receipt;
  final ThreadFacetStamp origin;
  final AttemptId attemptId;
  final ReadonlyLatestValue<ThreadExecutionState> _execution;
  final OperationWriter<T> _operation;
  final ResourceBudget _budget;
  final Future<InputAcceptanceEvidence?> Function() _readAcceptance;
  final void Function() _releaseDemand;
  ResourcePermit? _permit;
  Observation? _source;
  Observation? _retainedOperation;
  Future<void>? _pending;
  int? _durableSequence;
  int? _storageIncarnation;
  bool _storageSeen = false;
  bool _dirty = false;
  bool _closing = false;
  bool _finished = false;
  bool _released = false;
  final Map<String, FeedCloseIssue> _cleanupIssues = {};
  final Map<String, ({Object cause, StackTrace stack})> _cleanupCauses = {};
  final Set<String> _cleanupAttempted = {};
  bool _demandReleased = false;
  Object? _lastCause;
  StackTrace? _lastStack;

  bool get isFinished => _finished;
  bool get hasPendingQuery => _pending != null;
  Object? get lastCause => _lastCause;
  StackTrace? get lastStack => _lastStack;

  /// Construction reserves the watches before the submitting action's first
  /// await. A real native receipt activates one immediate bounded identity read.
  void acceptReceipt(SubmitPromptReceipt receipt) {
    if (_closing) throw const StudioFailure(code: StudioFailureCode.cancelled,
      message: 'The original input evidence owner is closing.', retryable: false,
      correlationId: 'input-identity-closed');
    if (receipt.threadId != threadId || receipt.inputId != inputId ||
        receipt.cursor < 0 || !_digest.hasMatch(receipt.requestDigest) ||
        (_receipt != null && _receipt != receipt)) {
      throw _protocol('The submission receipt contradicts its frozen native input identity.');
    }
    if (_receipt == receipt) return;
    _receipt = receipt;
    _requestRead();
  }

  bool _sameOrigin(ThreadFacetStamp stamp) =>
      stamp.runtimeEpoch == origin.runtimeEpoch &&
      stamp.incarnation == origin.incarnation &&
      stamp.facet == ThreadFacet.execution;

  void _considerExecution(ThreadExecutionState state) {
    if (_closing || _finished) return;
    final stamp = state.stamp;
    if (stamp == null || stamp.runtimeEpoch != origin.runtimeEpoch || stamp.facet != ThreadFacet.execution) return;
    final failure = state.sync.error;
    if (failure != null) _operation.evidenceFailed(failure);
    final storage = state.value?.storage;
    if (storage == null) return;
    final next = storage.durableSequence;
    final incarnationChanged = _storageIncarnation != null && _storageIncarnation != stamp.incarnation;
    final changed = !_storageSeen || incarnationChanged || next != _durableSequence;
      _storageSeen = true;
    _storageIncarnation = stamp.incarnation;
      _durableSequence = next;
    // A replacement projection on this concrete Session may cue a pure read of
    // the same frozen runtime/Thread history, but is never receipt evidence.
    if (changed && _receipt != null && (next != null || incarnationChanged)) _requestRead();
  }

  /// Called only from a materialized, original-owner execution Turn fact.
  void considerTurn(ConversationTurn turn, {required ThreadFacetStamp stamp}) {
    if (_closing || _finished || !_sameOrigin(stamp) ||
        turn.threadId != threadId || turn.inputId != inputId) {
      return;
    }
    _operation.identityObserved();
    final started = switch (turn.state) {
      RunningTurn() => true,
      CompletedTurn(:final startedAt) || CancelledTurn(:final startedAt) ||
      FailedTurn(:final startedAt) || BudgetLimitedTurn(:final startedAt) => startedAt != null,
      QueuedTurn() => false,
    };
    if (started) _operation.effective();
    // No Turn terminal/saved flag can mark this input durable.
  }

  void _requestRead() {
    if (_closing || _finished || _receipt == null) return;
    if (_pending != null) {
      _dirty = true;
      return;
    }
    final completion = Completer<void>();
    // Install completion before calling an adapter or a synchronous listener.
    _pending = completion.future;
    _dirty = false;
    unawaited(_read(completion));
  }

  Future<void> _read(Completer<void> completion) async {
    ResourcePermit? queryPermit;
    try {
      queryPermit = _budget.acquire(ResourceKind.pendingOperation,
          owner: 'input-read:${_operation.ticket.id.value}');
      final evidence = await _readAcceptance();
      if (!_closing && !_finished) _considerEvidence(evidence);
    } catch (error, stack) {
      // Query errors are diagnostics, not a rejection or authorization to resend.
      _lastCause = error;
      _lastStack = stack;
      final failure = switch (error) {
        StudioFailure() => error,
        ResourceBudgetExceeded() => error.failure,
        _ => const StudioFailure(
          code: StudioFailureCode.internal,
          message: 'The input identity query failed.',
          retryable: false,
          correlationId: 'input-identity-query',
        ),
      };
      try {
        _operation.evidenceFailed(failure);
      } catch (reportError, reportStack) {
        // Preserve reporting failures too; the original query still joins.
        _lastCause = reportError;
        _lastStack = reportStack;
      }
    } finally {
      queryPermit?.release();
      _pending = null;
      completion.complete();
      if (_closing || _finished) {
        _release();
      } else if (_dirty) {
        _requestRead();
      }
    }
  }

  void _considerEvidence(InputAcceptanceEvidence? evidence) {
    final receipt = _receipt;
    if (evidence == null || receipt == null) return;
    if (evidence.acceptedSequence != receipt.cursor) {
      throw _protocol('The persisted input sequence contradicts its acceptance receipt.');
    }
    final digest = evidence.requestDigest;
    if (digest == null || digest.isEmpty) return;
    if (!_digest.hasMatch(digest) || digest != receipt.requestDigest) {
      throw _protocol('The persisted input digest contradicts its acceptance receipt.');
    }
    _operation.identityObserved();
    if (evidence.disposition == PersistedInputDisposition.consumed) {
      _operation.effective();
    }
    _operation.durable();
    // Discarded is durable but not effective. Do not await an impossible Turn.
    _finished = true;
    _cancelSource();
    _dirty = false;
  }

  void requestClose() {
    if (_closing) return;
    _closing = true;
    _dirty = false;
    _cancelSource();
    if (_pending == null) _release();
  }

  /// Each wait observes the real current work; deadline results are not cached.
  Future<CloseReport> close({DateTime? deadline}) async {
    requestClose();
    final pending = _pending;
    if (pending != null) {
      if (deadline == null) {
        await pending;
      } else {
        final remaining = deadline.difference(DateTime.now());
        if (remaining > Duration.zero) {
          try {
            await pending.timeout(remaining);
          } on TimeoutException {
            // The original completion and query permit remain owned here.
          }
        }
      }
    }
    if (_pending == null) {
      _release();
      if (_cleanupIssues.isEmpty) return CloseReport(unresolved: []);
    }
    return CloseReport(unresolved: [
      UnresolvedResource(
        owner: 'input-evidence:${_operation.ticket.id.value}',
        attemptId: attemptId,
        issues: [
          ..._cleanupIssues.values,
          if (_pending != null) const FeedCloseIssue(
          diagnostic: StudioShutdownIssue(
            stage: 'inputIdentityQuery',
            code: 'queryPending',
            message: 'The original input identity query is still in flight.',
            retryable: true,
            correlationId: 'input-identity-query',
          ),
          recovery: CleanupRecovery.awaitCompletion,
          ),
        ],
      ),
    ]);
  }

  void _release() {
    if (_released) return;
    _cancelSource();
    _cleanup('inputIdentityDemand', () { _releaseDemand(); _demandReleased = true; });
    if (_demandReleased) {
      _cleanup('inputIdentityOperationWatch', () {
      _retainedOperation?.cancel();
      _retainedOperation = null;
      });
    }
    if (_cleanupIssues.isEmpty) {
      _cleanup('inputIdentityPermit', () { _permit?.release(); _permit = null; });
    }
    _released = _cleanupIssues.isEmpty && _demandReleased;
    final permit = _permit;
    if (!_released && permit != null && !permit.isReleased) permit.mark(ResourcePhase.unresolved);
  }

  void _cancelSource() => _cleanup('inputIdentityWatch', () { _source?.cancel(); _source = null; });

  void _cleanup(String stage, void Function() action) {
    if (!_cleanupAttempted.add(stage)) return;
    try { action(); } catch (error, stack) {
      _cleanupCauses[stage] = (cause: error, stack: stack);
      _lastCause = error;
      _lastStack = stack;
      final failure = error is StudioFailure ? error : const StudioFailure(
        code: StudioFailureCode.internal, message: 'The original input evidence cleanup failed.',
        retryable: false, correlationId: 'input-identity-cleanup');
      _cleanupIssues[stage] = FeedCloseIssue(diagnostic: StudioShutdownIssue(stage: stage,
        code: failure.code.name, message: failure.message, retryable: failure.retryable,
        correlationId: failure.correlationId), recovery: CleanupRecovery.terminal);
    }
  }

  StudioFailure _protocol(String message) => StudioFailure(
    code: StudioFailureCode.protocol,
    message: message,
    retryable: false,
    correlationId: 'input-identity-protocol',
  );
}

/// Internal construction failure carrying the exact cleanup capability that
/// cannot be discarded when rollback itself failed. Not exported as SDK state.
final class SubmittedInputObserverConstructionFailure<T> implements Exception {
  SubmittedInputObserverConstructionFailure._(this.cause, this.causeStack, this.cleanup);
  final Object cause;
  final StackTrace causeStack;
  final SubmittedInputObserver<T> cleanup;
  StudioFailure get failure => switch (cause) {
    StudioFailure failure => failure,
    ResourceBudgetExceeded error => error.failure,
    _ => const StudioFailure(code: StudioFailureCode.internal,
      message: 'The input evidence observer could not be installed.', retryable: false,
      correlationId: 'input-identity-construction'),
  };
}
