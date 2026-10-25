import 'dart:async';
import 'dart:convert';

import '../../../conversation.dart'
    show
        TurnBrief,
        TurnReadScope,
        TurnReadHeader,
        QueuedTurnRead,
        RunningTurnRead,
        CompletedTurnRead,
        CancelledTurnRead,
        FailedTurnRead,
        BudgetLimitedTurnRead,
        ThreadExecutionState,
        ThreadFacet,
        ThreadFacetStamp;
import '../../../conversation_ports.dart' show SubmissionExecutionLease;
import '../../../operations_ports.dart';
import '../../../resources_ports.dart';
import '../domain/submission_values.dart';

/// A repository-owned, non-polling observation of one frozen input.
///
/// The execution source and release callback belong to a specific Session demand,
/// not the selected Thread. This owner never reads or claims Timeline content.
final class SubmittedInputObserver<T> {
  /// Takes the original demand on entry, even if permit/watch admission fails.
  /// Failed construction carries the original, asynchronous cleanup capability.
  factory SubmittedInputObserver({
    required String threadId,
    required String inputId,
    required ThreadFacetStamp origin,
    required AttemptId attemptId,
    required ReadonlyLatestValue<ThreadExecutionState> execution,
    required SubmissionExecutionLease original,
    required OperationWriter<T> operation,
    required ResourceBudget budget,
    required Future<InputAcceptanceEvidence?> Function() readAcceptance,
    required void Function() releaseDemand,
  }) {
    final owner = SubmittedInputObserver<T>._(
      threadId: threadId,
      inputId: inputId,
      origin: origin,
      attemptId: attemptId,
      execution: execution,
      original: original,
      operation: operation,
      budget: budget,
      readAcceptance: readAcceptance,
      releaseDemand: releaseDemand,
    );
    try {
      owner._install();
      return owner;
    } catch (error, stack) {
      owner._lastCause = error;
      owner._lastStack = stack;
      owner.requestClose();
      unawaited(owner._startJoin());
      // A concrete failed-construction owner, not an exception bus. The caller
      // receives its original failure AND the still-owned terminal close report.
      throw SubmittedInputObserverConstructionFailure<T>._(error, stack, owner);
    }
  }

  SubmittedInputObserver._({
    required this.threadId,
    required this.inputId,
    required this.origin,
    required this.attemptId,
    required ReadonlyLatestValue<ThreadExecutionState> execution,
    required SubmissionExecutionLease original,
    required OperationWriter<T> operation,
    required ResourceBudget budget,
    required Future<InputAcceptanceEvidence?> Function() readAcceptance,
    required void Function() releaseDemand,
  }) : _execution = execution,
       _original = original,
       _operation = operation,
       _budget = budget,
       _readAcceptance = readAcceptance,
       _releaseDemand = releaseDemand;

  void _install() {
    var installing = true;
    Object? callbackFailure;
    StackTrace? callbackStack;
    try {
      _permit = _budget.acquire(
        ResourceKind.observer,
        owner: 'input-evidence:${_operation.ticket.id.value}',
      );
      // Protect the exact operation record independently of page/Widget observers.
      _retainedOperation = _operation.ticket.state.watch((_) {});
      _source = _execution.watch((state) {
        if (!installing) {
          _considerExecution(state);
          return;
        }
        try {
          _considerExecution(state);
        } catch (error, stack) {
          callbackFailure ??= error;
          callbackStack ??= stack;
        }
      });
      if (callbackFailure case final error?)
        Error.throwWithStackTrace(error, callbackStack!);
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
  final SubmissionExecutionLease _original;
  late final List<int> _inputBytes = utf8.encode(inputId);
  final OperationWriter<T> _operation;
  final ResourceBudget _budget;
  final Future<InputAcceptanceEvidence?> Function() _readAcceptance;
  final void Function() _releaseDemand;
  ResourcePermit? _permit;
  Observation? _source;
  Observation? _retainedOperation;
  Future<void>? _pending;
  Future<void>? _joining;
  CloseReport? _turnReport;
  int? _durableSequence;
  int? _storageIncarnation;
  bool _storageSeen = false;
  bool _dirty = false;
  bool _closing = false;
  bool _finished = false;
  bool _released = false;
  final Map<String, FeedCloseIssue> _cleanupIssues = {};
  final Map<String, ({Object cause, StackTrace stack})> _cleanupCauses = {};
  final Set<String> _cleanupCompleted = {};
  final Set<String> _cleanupRunning = {};
  bool _demandReleased = false;
  ({Object cause, StackTrace stack})? _turnFailure;
  Object? _lastCause;
  StackTrace? _lastStack;

  bool get isFinished => _finished;
  bool get hasPendingQuery => _pending != null;
  Object? get lastCause => _turnFailure?.cause ?? _lastCause;
  StackTrace? get lastStack => _turnFailure?.stack ?? _lastStack;

  /// Construction reserves the watches before the submitting action's first
  /// await. A real native receipt activates one immediate bounded identity read.
  void acceptReceipt(SubmitPromptReceipt receipt) {
    if (_closing)
      throw const StudioFailure(
        code: StudioFailureCode.cancelled,
        message: 'The original input evidence owner is closing.',
        retryable: false,
        correlationId: 'input-identity-closed',
      );
    if (receipt.threadId != threadId ||
        receipt.inputId != inputId ||
        receipt.cursor < 0 ||
        !_digest.hasMatch(receipt.requestDigest) ||
        (_receipt != null && _receipt != receipt)) {
      throw _protocol(
        'The submission receipt contradicts its frozen native input identity.',
      );
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
    if (stamp == null ||
        stamp.runtimeEpoch != origin.runtimeEpoch ||
        stamp.facet != ThreadFacet.execution)
      return;
    final failure = state.sync.error;
    if (failure != null) _operation.evidenceFailed(failure);
    final storage = state.value?.storage;
    if (storage == null) return;
    final next = storage.durableSequence;
    final incarnationChanged =
        _storageIncarnation != null && _storageIncarnation != stamp.incarnation;
    final changed =
        !_storageSeen || incarnationChanged || next != _durableSequence;
    _storageSeen = true;
    _storageIncarnation = stamp.incarnation;
    _durableSequence = next;
    // A replacement projection on this concrete Session may cue a pure read of
    // the same frozen runtime/Thread history, but is never receipt evidence.
    if (changed && _receipt != null && (next != null || incarnationChanged))
      _requestRead();
  }

  /// The original reliable handoff awaits only these headers/identity bytes and
  /// each used scope's close, never this observer's history query or final join.
  Future<void> consumeTurns(
    SubmissionExecutionLease original,
    ThreadFacetStamp stamp,
    List<TurnBrief> turns,
  ) async {
    if (!identical(original, _original) ||
        original.threadId != threadId ||
        !_sameOrigin(stamp)) {
      throw _protocol(
        'The Turn handoff replaced its original submission source.',
      );
    }
    for (final turn in turns) {
      if (_closing || _finished) return;
      TurnReadScope? scope;
      Object? failure;
      StackTrace? failureStack;
      try {
        scope = await original.openTurn(turn.reference, origin: stamp);
        final header = await scope.header();
        if (!_closing &&
            !_finished &&
            await _matchesInputId(scope, header.inputId) &&
            !_closing &&
            !_finished) {
          _considerHeader(header);
        }
      } catch (error, stack) {
        failure = error;
        failureStack = stack;
      } finally {
        if (scope != null) {
          try {
            scope.requestClose();
            final report = await scope.close();
            if (!report.complete)
              throw const StudioFailure(
                code: StudioFailureCode.unavailable,
                message:
                    'The original Turn identity scope has unresolved cleanup.',
                retryable: true,
                correlationId: 'input-turn-cleanup',
              );
          } catch (error, stack) {
            // The Session read owner retains every scope/report, including a
            // cleanup error in addition to the original header/query failure.
            failure ??= error;
            failureStack ??= stack;
          }
        }
      }
      if (failure case final error?) {
        _turnFailure ??= (cause: error, stack: failureStack!);
        _lastCause = error;
        _lastStack = failureStack;
        final diagnostic = switch (error) {
          StudioFailure() => error,
          ResourceBudgetExceeded() => error.failure,
          _ => const StudioFailure(
            code: StudioFailureCode.internal,
            message: 'The original Turn identity read failed.',
            retryable: false,
            correlationId: 'input-turn-query',
          ),
        };
        Error.throwWithStackTrace(diagnostic, failureStack!);
      }
    }
  }

  Future<bool> _matchesInputId(TurnReadScope scope, ReadText? value) async {
    if (value == null) return false;
    if (value is InlineReadText) return value.text == inputId;
    final field = value as DeferredReadText;
    if (field.utf8Bytes < 0 || field.fieldId < 0)
      throw _protocol('The deferred input identity is invalid.');
    if (field.utf8Bytes != _inputBytes.length) return false;
    var offset = 0;
    while (offset < _inputBytes.length) {
      if (_closing || _finished) return false;
      final remaining = _inputBytes.length - offset;
      final maxBytes = remaining < 4
          ? 4
          : (remaining < 65536 ? remaining : 65536);
      final chunk = await scope.text(
        field.fieldId,
        offset: offset,
        maxBytes: maxBytes,
      );
      final bytes = utf8.encode(chunk.text);
      final end = offset + bytes.length;
      if (chunk.fieldId != field.fieldId ||
          chunk.offset != offset ||
          bytes.isEmpty ||
          bytes.length > maxBytes ||
          end > field.utf8Bytes ||
          (chunk.nextOffset == null
              ? end != field.utf8Bytes
              : end == field.utf8Bytes || chunk.nextOffset != end)) {
        throw _protocol(
          'The deferred input identity did not make exact UTF-8 progress.',
        );
      }
      for (var i = 0; i < bytes.length; i++) {
        if (bytes[i] != _inputBytes[offset + i]) return false;
      }
      offset = end;
    }
    return true;
  }

  void _considerHeader(TurnReadHeader turn) {
    _operation.identityObserved();
    final started = switch (turn.state) {
      RunningTurnRead() => true,
      CompletedTurnRead(:final startedAt) ||
      CancelledTurnRead(:final startedAt) ||
      FailedTurnRead(:final startedAt) ||
      BudgetLimitedTurnRead(:final startedAt) => startedAt != null,
      QueuedTurnRead() => false,
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
      queryPermit = _budget.acquire(
        ResourceKind.pendingOperation,
        owner: 'input-read:${_operation.ticket.id.value}',
      );
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
        unawaited(_startJoin());
      } else if (_dirty) {
        _requestRead();
      }
    }
  }

  void _considerEvidence(InputAcceptanceEvidence? evidence) {
    final receipt = _receipt;
    if (evidence == null || receipt == null) return;
    if (evidence.acceptedSequence != receipt.cursor) {
      throw _protocol(
        'The persisted input sequence contradicts its acceptance receipt.',
      );
    }
    final digest = evidence.requestDigest;
    if (digest == null || digest.isEmpty) return;
    if (!_digest.hasMatch(digest) || digest != receipt.requestDigest) {
      throw _protocol(
        'The persisted input digest contradicts its acceptance receipt.',
      );
    }
    _operation.identityObserved();
    if (evidence.disposition == PersistedInputDisposition.consumed) {
      _operation.effective();
    }
    _operation.durable();
    // Discarded is durable but not effective. Do not await an impossible Turn.
    _finished = true;
    _cancelSource();
    _sealTurnReads();
    _dirty = false;
  }

  void requestClose() {
    if (_closing) return;
    _closing = true;
    _dirty = false;
    _cancelSource();
    _sealTurnReads();
  }

  /// Each wait observes the real current work; deadline results are not cached.
  Future<CloseReport> close({DateTime? deadline, bool retry = false}) async {
    final joining = _startJoin(retry: retry);
    // The deadline observes this join; it never replaces or cancels its work.
    if (deadline == null) {
      await joining;
    } else {
      final remaining = deadline.difference(DateTime.now());
      if (remaining > Duration.zero) {
        try {
          await joining.timeout(remaining);
        } on TimeoutException {
          // Original history, handoff, late open and native close stay owned.
        }
      }
    }
    if (_released) return CloseReport(unresolved: []);
    return CloseReport(
      unresolved: [
        ...?_turnReport?.unresolved,
        UnresolvedResource(
          owner: 'input-evidence:${_operation.ticket.id.value}',
          attemptId: attemptId,
          issues: [
            ..._cleanupIssues.values,
            if (_pending != null)
              const FeedCloseIssue(
                diagnostic: StudioShutdownIssue(
                  stage: 'inputIdentityQuery',
                  code: 'queryPending',
                  message:
                      'The original input identity query is still in flight.',
                  retryable: true,
                  correlationId: 'input-identity-query',
                ),
                recovery: CleanupRecovery.awaitCompletion,
              ),
            if (_joining != null)
              const FeedCloseIssue(
                diagnostic: StudioShutdownIssue(
                  stage: 'inputIdentityJoin',
                  code: 'evidenceJoinPending',
                  message: 'The original input evidence work has not joined.',
                  retryable: true,
                  correlationId: 'input-identity-join',
                ),
                recovery: CleanupRecovery.awaitCompletion,
              ),
            if (_cleanupRunning.isNotEmpty)
              const FeedCloseIssue(
                diagnostic: StudioShutdownIssue(
                  stage: 'inputIdentityCleanup',
                  code: 'cleanupStagePending',
                  message: 'An original input cleanup action is still running.',
                  retryable: true,
                  correlationId: 'input-identity-cleanup',
                ),
                recovery: CleanupRecovery.awaitCompletion,
              ),
            if (_pending == null && _joining == null && _cleanupIssues.isEmpty)
              const FeedCloseIssue(
                diagnostic: StudioShutdownIssue(
                  stage: 'inputIdentityJoin',
                  code: 'turnReadsRetained',
                  message: 'The original input evidence awaits its Turn read cleanup.',
                  retryable: true,
                  correlationId: 'input-identity-join',
                ),
                recovery: CleanupRecovery.awaitCompletion,
              ),
          ],
        ),
      ],
    );
  }

  void _sealTurnReads() {
    try {
      _original.requestCloseTurnReads();
    } catch (error, stack) {
      _turnCloseFailed('inputIdentityTurnReadAdmission', error, stack);
    }
  }

  Future<void> _startJoin({bool retry = false}) {
    if (_joining case final current?) return current;
    if (_released) return Future.value();
    final completion = Completer<void>();
    _joining = completion.future;
    // One explicit pass can retry each pre-existing failed stage once. A new
    // failure during this pass remains owned until the next explicit retry.
    final retryStages = retry ? _cleanupIssues.keys.toSet() : <String>{};
    unawaited(
      Future<void>.sync(() async {
        requestClose();
        if (_pending case final pending?) await pending;
        try {
          _turnReport = await _original.closeTurnReads(retry: retry);
          _cleanupIssues.remove('inputIdentityTurnReads');
          _cleanupIssues.remove('inputIdentityJoin');
          if (_turnReport!.complete) {
            _cleanupIssues.remove('inputIdentityTurnReadAdmission');
            _release(retryStages: retryStages);
          }
        } catch (error, stack) {
          _turnCloseFailed('inputIdentityTurnReads', error, stack);
        }
      }).then<void>(
        (_) {
          _joining = null;
          completion.complete();
        },
        onError: (Object error, StackTrace stack) {
          _turnCloseFailed('inputIdentityJoin', error, stack);
          _joining = null;
          completion.complete();
        },
      ),
    );
    return completion.future;
  }

  void _turnCloseFailed(String stage, Object error, StackTrace stack) {
    _cleanupCauses.putIfAbsent(stage, () => (cause: error, stack: stack));
    if (_lastCause == null) {
      _lastCause = error;
      _lastStack = stack;
    }
    final failure = error is StudioFailure
        ? error
        : const StudioFailure(
            code: StudioFailureCode.internal,
            message: 'The original Turn evidence cleanup failed.',
            retryable: false,
            correlationId: 'input-turn-cleanup',
          );
    _cleanupIssues[stage] = FeedCloseIssue(
      diagnostic: StudioShutdownIssue(
        stage: stage,
        code: failure.code.name,
        message: failure.message,
        retryable: failure.retryable,
        correlationId: failure.correlationId,
      ),
      recovery: CleanupRecovery.retryClose,
    );
  }

  void _release({required Set<String> retryStages}) {
    if (_released) return;
    _cancelSource(retryStages: retryStages);
    _cleanup('inputIdentityDemand', () {
      _releaseDemand();
      _demandReleased = true;
    }, retryStages: retryStages);
    if (_demandReleased) {
      _cleanup('inputIdentityOperationWatch', () {
        final original = _retainedOperation;
        if (original != null && !original.isCancelled) original.cancel();
        if (original != null && !original.isCancelled)
          throw _protocol('The original operation watch did not cancel.');
        _retainedOperation = null;
      }, retryStages: retryStages);
    }
    final observationsDone =
        _cleanupCompleted.contains('inputIdentityWatch') &&
        _cleanupCompleted.contains('inputIdentityDemand') &&
        _cleanupCompleted.contains('inputIdentityOperationWatch');
    if (observationsDone &&
        _cleanupRunning.isEmpty &&
        _cleanupIssues.keys.every((stage) => stage == 'inputIdentityPermit')) {
      _cleanup('inputIdentityPermit', () {
        final original = _permit;
        if (original != null && !original.isReleased) original.release();
        if (original != null && !original.isReleased)
          throw _protocol(
            'The original input evidence permit did not release.',
          );
        _permit = null;
      }, retryStages: retryStages);
    }
    _released =
        observationsDone &&
        _cleanupCompleted.contains('inputIdentityPermit') &&
        _cleanupRunning.isEmpty &&
        _cleanupIssues.isEmpty &&
        _pending == null &&
        _turnReport?.complete == true;
    final permit = _permit;
    if (!_released && permit != null && !permit.isReleased)
      permit.mark(ResourcePhase.unresolved);
  }

  void _cancelSource({Set<String>? retryStages}) =>
      _cleanup('inputIdentityWatch', () {
        final original = _source;
        if (original != null && !original.isCancelled) original.cancel();
        if (original != null && !original.isCancelled)
          throw _protocol('The original execution watch did not cancel.');
        _source = null;
      }, retryStages: retryStages);

  void _cleanup(
    String stage,
    void Function() action, {
    Set<String>? retryStages,
  }) {
    if (_cleanupCompleted.contains(stage) || _cleanupRunning.contains(stage))
      return;
    if (_cleanupIssues.containsKey(stage) &&
        !(retryStages?.remove(stage) ?? false))
      return;
    _cleanupRunning.add(stage);
    try {
      action();
      _cleanupCompleted.add(stage);
      _cleanupIssues.remove(stage);
    } catch (error, stack) {
      _cleanupCauses.putIfAbsent(stage, () => (cause: error, stack: stack));
      if (_lastCause == null) {
        _lastCause = error;
        _lastStack = stack;
      }
      final failure = error is StudioFailure
          ? error
          : const StudioFailure(
              code: StudioFailureCode.internal,
              message: 'The original input evidence cleanup failed.',
              retryable: false,
              correlationId: 'input-identity-cleanup',
            );
      _cleanupIssues[stage] = FeedCloseIssue(
        diagnostic: StudioShutdownIssue(
          stage: stage,
          code: failure.code.name,
          message: failure.message,
          retryable: failure.retryable,
          correlationId: failure.correlationId,
        ),
        recovery: CleanupRecovery.retryClose,
      );
    } finally {
      _cleanupRunning.remove(stage);
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
  SubmittedInputObserverConstructionFailure._(
    this.cause,
    this.causeStack,
    this.cleanup,
  );
  final Object cause;
  final StackTrace causeStack;
  final SubmittedInputObserver<T> cleanup;
  StudioFailure get failure => switch (cause) {
    StudioFailure failure => failure,
    ResourceBudgetExceeded error => error.failure,
    _ => const StudioFailure(
      code: StudioFailureCode.internal,
      message: 'The input evidence observer could not be installed.',
      retryable: false,
      correlationId: 'input-identity-construction',
    ),
  };
}
