part of 'session_owner.dart';

enum _StopOutcome {
  rejected,
  unknown,
  accepted,
  confirmedWithoutReceipt,
  committedUnobserved,
}

/// One exact Stop invocation in the Session's original evidence collection.
/// There is no FIFO, second feed, retry-send or lookup by current Thread ID.
final class _StopTurnWork extends _ExecutionEvidenceOwner {
  _StopTurnWork({
    required this.session,
    required this.writer,
    required this.origin,
    required this.target,
    required CreatedInputExecutionBinding? binding,
    required AttemptId? originalAttempt,
  }) : super(
         threadId: session.threadId,
         attemptId: session.nextAttempt(),
         execution: session.execution,
         source: null,
         created: binding,
         readOwners: session.readOwners,
         observationPort: session.observationPort,
         release: session._releaseEvidence,
       ) {
    _sourceAttempt = originalAttempt;
  }

  final ConversationSessionOwner session;
  final OperationWriter<Unit> writer;
  final ThreadFacetStamp origin;
  final TurnReadRef target;
  final Completer<void> _taskDone = Completer<void>();
  final Map<String, FeedCloseIssue> _issues = {};
  final Map<String, ({Object cause, StackTrace stack})> _causes = {};
  final Set<String> _completed = {};
  final Set<String> _stepsRunning = {};
  ResourcePermit? _taskPermit;
  ResourcePermit? _observerPermit;
  Observation? _operationWatch;
  Future<void>? _cleaning;
  _StopOutcome? _outcome;
  StudioFailure? _outcomeFailure;
  CommitReceipt? _receipt;
  InterruptTurnReply? _reply;
  String? _turnId;
  int _observedRevision = -1;
  int _dispatchRevision = -1;
  bool _authoritative = false;
  bool _dispatched = false;
  bool _terminalProof = false;
  bool _abandoned = false;
  bool _closing = false;
  bool _cleanupScheduled = false;
  bool _allowRelease = false;
  StudioFailure? _abandonFailure;

  void start() {
    // The Session registered this object before any watch, value read or adapter
    // can reenter. Completion exists even for synchronous preparation failure.
    try {
      _bindConsumer(
        consume: _consumeExecution,
        onFailure: writer.evidenceFailed,
      );
      _checkInitialTarget();
      _taskPermit = session._budget.acquire(
        ResourceKind.pendingOperation,
        owner: 'stop-dispatch:${writer.ticket.id.value}',
      );
      _observerPermit = session._budget.acquire(
        ResourceKind.observer,
        owner: 'stop-evidence:${writer.ticket.id.value}',
      );
      _operationWatch = writer.ticket.state.watch((_) => _scheduleCleanup());
      _checkActive();
      session._applyDemand();
    } catch (error, stack) {
      _chooseFailure(error, stack);
      _finishTask();
      return;
    }
    unawaited(
      Future<void>.sync(_run).then<void>(
        (_) {
          _finishTask();
        },
        onError: (Object error, StackTrace stack) {
          _chooseFailure(error, stack);
          _finishTask();
        },
      ),
    );
  }

  void _checkInitialTarget() {
    if (session._sealed ||
        session._stopAdmissionRetired ||
        session.readAdmissionClosed ||
        !session._selected)
      throw conversationCancelled;
    session.requireOrigin(origin);
    final stamp = session._readyExecutionStamp;
    final active = execution.value.value?.activeTurn;
    if (stamp == null ||
        origin.facet != ThreadFacet.execution ||
        origin.revision < 0 ||
        target.entry < 0 ||
        target.revision < 0 ||
        active == null ||
        active.reference != target ||
        active.revision != target.revision ||
        !_busy(active))
      throw _stopStaleTarget;
    if (_sourceAttempt == null ||
        _sourceAttempt != session._feeds.executionAttemptId ||
        !identical(_created?.source, session._executionBinding?.source))
      throw _stopStaleTarget;
    _source = (
      runtimeEpoch: origin.runtimeEpoch,
      incarnation: origin.incarnation,
    );
    _observedRevision = stamp.revision;
    _authoritative = true;
  }

  ThreadFacetStamp _checkActive() {
    final state = execution.value;
    final stamp = state.stamp;
    final active = state.value?.activeTurn;
    if (_closing || session._sealed || _abandoned) throw conversationCancelled;
    if (!_authoritative ||
        stamp == null ||
        state.sync.phase != FacetSyncPhase.ready ||
        stamp.facet != ThreadFacet.execution ||
        !_sameProjection(origin, stamp) ||
        session._feeds.executionAttemptId != _sourceAttempt ||
        !identical(_created?.source, session._executionBinding?.source) ||
        stamp.revision < _observedRevision ||
        active == null ||
        active.reference.entry != target.entry ||
        !_busy(active)) {
      throw _stopStaleTarget;
    }
    return stamp;
  }

  Future<void> _run() async {
    TurnReadScope? scope;
    try {
      _checkActive();
      scope = await _readOwners.openExecutionTurn(
        evidence: this,
        origin: origin,
        reference: target,
        accepts: () =>
            !_closing && !session._sealed && !_abandoned && !_turnReadsClosed,
        open: () =>
            _observationPort.openTurnRead(threadId, target, origin: origin),
      );
      final header = await scope.header();
      final originalThread = await _readIdentity(scope, header.threadId);
      final originalTurn = await _readIdentity(scope, header.id);
      if (originalThread != threadId ||
          header.revision != target.revision ||
          !_busyHeader(header)) {
        throw readProtocol(
          'The frozen Stop read does not identify its original busy Turn.',
        );
      }
      _turnId = originalTurn;
    } catch (error, stack) {
      _chooseFailure(error, stack);
    } finally {
      if (scope != null) {
        try {
          scope.requestClose();
          final report = await scope.close();
          if (!report.complete)
            throw const StudioFailure(
              code: StudioFailureCode.unavailable,
              message:
                  'The original Stop identity read has unresolved cleanup.',
              retryable: true,
              correlationId: 'stop-read-cleanup',
            );
        } catch (error, stack) {
          _chooseFailure(error, stack);
        }
      }
    }
    if (_outcome != null) return;
    try {
      // Same entry may progress through revisions while the frozen read is in
      // flight. Never replace that read ref or dispatch to a different entry.
      _dispatchRevision = _checkActive().revision;
      _dispatched = true;
      final reply = await session._commands.interruptTurn(
        threadId,
        _turnId!,
        operationId: writer.ticket.id,
      );
      _reply = reply;
      final failure = _validateReply();
      if (failure == null) {
        _receipt = reply.receipt;
        _outcome = _StopOutcome.accepted;
      } else {
        _outcome = _StopOutcome.confirmedWithoutReceipt;
        _outcomeFailure = failure;
        _remember('stopReply', failure, StackTrace.current, cleanup: false);
      }
    } catch (error, stack) {
      _chooseFailure(error, stack);
    }
  }

  Future<String> _readIdentity(TurnReadScope scope, ReadText value) async {
    if (value is InlineReadText) return value.text;
    final field = value as DeferredReadText;
    if (field.fieldId < 0 || field.utf8Bytes < 0)
      throw readProtocol('The Stop identity text descriptor is invalid.');
    var offset = 0;
    final text = StringBuffer();
    while (offset < field.utf8Bytes) {
      if (_closing || session._sealed || _abandoned)
        throw conversationCancelled;
      final chunk = await scope.text(
        field.fieldId,
        offset: offset,
        maxBytes: 65536,
      );
      final bytes = utf8.encode(chunk.text).length;
      final end = offset + bytes;
      if (chunk.fieldId != field.fieldId ||
          chunk.offset != offset ||
          bytes == 0 ||
          bytes > 65536 ||
          end > field.utf8Bytes ||
          (chunk.nextOffset == null
              ? end != field.utf8Bytes
              : end == field.utf8Bytes || chunk.nextOffset != end)) {
        throw readProtocol(
          'The original Stop identity did not make exact UTF-8 progress.',
        );
      }
      text.write(chunk.text);
      offset = end;
    }
    return text.toString();
  }

  StudioFailure? _validateReply() {
    final reply = _reply!;
    if (reply.threadId != threadId ||
        reply.turnId != _turnId ||
        !_validReceipt(reply.receipt) ||
        reply.receipt.disposition !=
            (reply.interrupted
                ? CommitDisposition.applied
                : CommitDisposition.noChange)) {
      return readProtocol(
        'The Stop reply contradicts its original operation, Thread, Turn or receipt contract.',
      );
    }
    return null;
  }

  bool _validReceipt(CommitReceipt receipt) =>
      receipt.operationId == writer.ticket.id &&
      receipt.requiresIdentityObservation &&
      receipt.effect == EffectPoint.immediate &&
      !receipt.effective &&
      !receipt.durable &&
      receipt.targets.isEmpty;

  void _chooseFailure(Object error, StackTrace stack) {
    _remember('stopExecution', error, stack, cleanup: false);
    if (_outcome != null) return;
    final failure = error is CommandDispatchFailure
        ? error.failure
        : conversationFailure(error);
    _outcomeFailure = failure;
    if (_reply != null) {
      _outcome = _StopOutcome.confirmedWithoutReceipt;
      _outcomeFailure = readProtocol(
        'The confirmed Stop reply could not be validated for its frozen target.',
      );
    } else if (!_dispatched || error is RejectedCommandDispatchFailure) {
      _outcome = _StopOutcome.rejected;
    } else if (error is CommittedButUnobservedCommandDispatchFailure &&
        _validReceipt(error.receipt)) {
      _receipt = error.receipt;
      _outcome = _StopOutcome.committedUnobserved;
    } else if (error is CommittedButUnobservedCommandDispatchFailure ||
        error is ConfirmedWithoutUsableReceiptCommandDispatchFailure) {
      _outcome = _StopOutcome.confirmedWithoutReceipt;
      if (error is CommittedButUnobservedCommandDispatchFailure) {
        _outcomeFailure = readProtocol(
          'The confirmed Stop receipt does not match its original invocation.',
        );
      }
    } else {
      // InvalidArgument/Conflict may follow a partial mailbox cancellation.
      // Only actual dispatch evidence can classify that work as rejected.
      _outcome = _StopOutcome.unknown;
    }
  }

  void _finishTask() {
    _settle(<String>{});
    _step('stopDispatchPermit', () {
      final permit = _taskPermit;
      if (permit != null && !permit.isReleased) permit.release();
      if (permit != null && !permit.isReleased)
        throw readProtocol(
          'The original Stop dispatch permit did not release.',
        );
      _taskPermit = null;
    }, <String>{});
    if (!_taskDone.isCompleted) _taskDone.complete();
    _scheduleCleanup();
  }

  void _settle(Set<String> retryStages) {
    final outcome = _outcome;
    if (outcome == null) return;
    _step('stopResult', () {
      switch (outcome) {
        case _StopOutcome.accepted:
          writer.accepted(const Unit(), _receipt!);
        case _StopOutcome.rejected:
          writer.rejected(_outcomeFailure!);
        case _StopOutcome.unknown:
          writer.unknownOutcome(_outcomeFailure!);
        case _StopOutcome.confirmedWithoutReceipt:
          writer.acknowledgedSynchronizationFailed(
            _outcomeFailure!,
            value: const Unit(),
          );
        case _StopOutcome.committedUnobserved:
          writer.synchronizationFailed(
            _outcomeFailure!,
            value: const Unit(),
            receipt: _receipt!,
          );
      }
    }, retryStages);
    if (_completed.contains('stopResult') &&
        _receipt != null &&
        _terminalProof) {
      _step('stopObserved', writer.identityObserved, retryStages);
      if (_completed.contains('stopObserved'))
        _step('stopEffective', writer.effective, retryStages);
    } else if (_completed.contains('stopResult') &&
        _receipt != null &&
        _abandoned) {
      _step('stopObservationEnded', () {
        final state = writer.ticket.state.value;
        if (!state.observed &&
            state.failurePhase != OperationFailurePhase.syncFailed) {
          writer.synchronizationFailed(
            _abandonFailure ?? conversationCancelled,
            value: const Unit(),
            receipt: _receipt!,
          );
        }
      }, retryStages);
    }
  }

  Future<void> _consumeExecution(
    ThreadFacetStamp stamp,
    TurnBrief? active,
    List<TurnBrief> _,
  ) {
    if (stamp.revision < _observedRevision) throw _stopStaleTarget;
    _observedRevision = stamp.revision;
    _authoritative = true;
    if (_dispatched &&
        stamp.revision > _dispatchRevision &&
        (active == null ||
            active.reference.entry != target.entry ||
            !_busy(active))) {
      _terminalProof = true;
      _settle(<String>{});
      _scheduleCleanup();
    }
    return Future.value();
  }

  @override
  bool _bind(AttemptId attempt, CreatedInputExecutionBinding? binding) {
    if (_released || _abandoned) return false;
    if (!identical(_created?.source, binding?.source))
      return _fail(_submissionSuperseded);
    _sourceAttempt = attempt;
    _authoritative = false;
    return false;
  }

  @override
  bool _fail(StudioFailure error, [StackTrace? stack, Object? cause]) {
    if (_released) return false;
    _authoritative = false;
    _sourceFailure ??= error;
    lastCause ??= cause ?? error;
    lastStack ??= stack;
    if (_outcome != _StopOutcome.rejected &&
        _outcome != _StopOutcome.confirmedWithoutReceipt &&
        !_completed.contains('stopOperationWatch') &&
        !(_terminalProof && _completed.contains('stopEffective'))) {
      _notifyFailure();
    }
    if (session._sealed ||
        error.code == StudioFailureCode.runtimeStopped ||
        error.code == StudioFailureCode.cancelled ||
        error == _submissionSuperseded) {
      final changed = _needsSource;
      _abandoned = true;
      _abandonFailure ??= error;
      _needsSource = false;
      try {
        requestCloseTurnReads();
      } catch (closeError, closeStack) {
        _remember('stopReadCloseRequest', closeError, closeStack);
      }
      _scheduleCleanup();
      return changed;
    }
    return false;
  }

  bool get _canFinish =>
      _closing ||
      _abandoned ||
      _terminalProof ||
      _outcome == _StopOutcome.rejected ||
      _outcome == _StopOutcome.unknown ||
      _outcome == _StopOutcome.confirmedWithoutReceipt;

  void _scheduleCleanup() {
    if (_cleanupScheduled ||
        _cleaning != null ||
        _released ||
        !_taskDone.isCompleted ||
        !_canFinish)
      return;
    _cleanupScheduled = true;
    scheduleMicrotask(() {
      _cleanupScheduled = false;
      close().ignore();
    });
  }

  void requestClose() {
    _closing = true;
    // A terminal fact cannot supply a lost receipt for an Unknown invocation.
    if (!_terminalProof || _outcome == _StopOutcome.unknown)
      _fail(conversationCancelled);
    try {
      requestCloseTurnReads();
    } catch (error, stack) {
      _remember('stopReadCloseRequest', error, stack);
    }
  }

  Future<CloseReport> close({DateTime? deadline, bool retry = false}) async {
    final joining = _cleanup(retry: retry);
    await observeConversationCompletion(joining, deadline);
    if (_released) return CloseReport(unresolved: []);
    return conversationCloseReport([
      ..._turnReadReport().unresolved,
      UnresolvedResource(
        owner: 'stop:${writer.ticket.id.value}',
        attemptId: attemptId,
        issues: [
          ..._issues.values,
          if (!_taskDone.isCompleted ||
              _cleaning != null ||
              _stepsRunning.isNotEmpty)
            const FeedCloseIssue(
              diagnostic: StudioShutdownIssue(
                stage: 'stopJoin',
                code: 'stopWorkPending',
                message:
                    'The original Stop dispatch or cleanup is still in flight.',
                retryable: true,
                correlationId: 'stop-work',
              ),
              recovery: CleanupRecovery.awaitCompletion,
            ),
          if (_taskDone.isCompleted && _cleaning == null && _issues.isEmpty)
            const FeedCloseIssue(
              diagnostic: StudioShutdownIssue(
                stage: 'stopJoin',
                code: 'stopOwnerRetained',
                message:
                    'The original Stop owner still has cleanup responsibility.',
                retryable: true,
                correlationId: 'stop-work',
              ),
              recovery: CleanupRecovery.awaitCompletion,
            ),
        ],
      ),
    ]);
  }

  Future<void> _cleanup({required bool retry}) {
    if (_cleaning case final current?) return current;
    if (_released) return Future.value();
    final completion = Completer<void>();
    _cleaning = completion.future;
    final retryStages = retry ? _issues.keys.toSet() : <String>{};
    unawaited(
      Future<void>.sync(() async {
        requestClose();
        await _taskDone.future;
        _settle(retryStages);
        _step('stopDispatchPermit', () {
          final permit = _taskPermit;
          if (permit != null && !permit.isReleased) permit.release();
          if (permit != null && !permit.isReleased)
            throw readProtocol(
              'The original Stop dispatch permit did not release.',
            );
          _taskPermit = null;
        }, retryStages);
        final reads = await closeTurnReads(retry: retry);
        if (!reads.complete) return;
        _issues.remove('stopReadCloseRequest');
        if (retryStages.remove('stopCleanup')) _issues.remove('stopCleanup');
        if (!_completed.contains('stopResult') ||
            _receipt != null &&
                !(_terminalProof
                    ? _completed.contains('stopEffective')
                    : _completed.contains('stopObservationEnded')))
          return;
        _step('stopOperationWatch', () {
          final watch = _operationWatch;
          if (watch != null && !watch.isCancelled) watch.cancel();
          if (watch != null && !watch.isCancelled)
            throw readProtocol('The original Stop observation did not cancel.');
          _operationWatch = null;
        }, retryStages);
        if (_issues.keys.any(
          (stage) =>
              stage != 'stopObserverPermit' && stage != 'stopReleaseDemand',
        ))
          return;
        _step('stopObserverPermit', () {
          final permit = _observerPermit;
          if (permit != null && !permit.isReleased) permit.release();
          if (permit != null && !permit.isReleased)
            throw readProtocol(
              'The original Stop evidence permit did not release.',
            );
          _observerPermit = null;
        }, retryStages);
        if (_issues.keys.any((stage) => stage != 'stopReleaseDemand')) return;
        _allowRelease = true;
        _step('stopReleaseDemand', release, retryStages);
      }).then<void>(
        (_) {
          _cleaning = null;
          completion.complete();
        },
        onError: (Object error, StackTrace stack) {
          _remember('stopCleanup', error, stack);
          _cleaning = null;
          completion.complete();
        },
      ),
    );
    return completion.future;
  }

  @override
  void release() {
    if (_released) return;
    if (!_allowRelease)
      throw StateError('Stop cleanup has not joined its original work.');
    _needsSource = false;
    if (!_ready.isCompleted) _ready.completeError(conversationCancelled);
    requestCloseTurnReads();
    // Stop's final detach is one explicit cleanup stage. Do not let a prior
    // failed detach be retried implicitly by a later read-close observation.
    if (!_turnReadReport().complete)
      throw const StudioFailure(
        code: StudioFailureCode.unavailable,
        message: 'The original Stop evidence still has in-flight or unresolved cleanup.',
        retryable: true,
        correlationId: 'stop-evidence-cleanup',
      );
    _finishRelease();
  }

  @override
  void _finishRelease() {
    if (!_allowRelease || _released) return;
    // Keep this exact owner registered when a reentrant notification throws.
    // Session close sees the restored responsibility before any await resumes.
    try {
      _release(this);
    } catch (_) {
      if (session._evidence.isEmpty)
        session._evidenceReleased = Completer<void>();
      session._evidence.add(this);
      rethrow;
    }
    _released = true;
  }

  void _step(String stage, void Function() action, Set<String> retryStages) {
    if (_completed.contains(stage) || _stepsRunning.contains(stage)) return;
    if (_issues.containsKey(stage) && !retryStages.remove(stage)) return;
    _stepsRunning.add(stage);
    try {
      action();
      _completed.add(stage);
      _issues.remove(stage);
    } catch (error, stack) {
      _remember(stage, error, stack);
    } finally {
      _stepsRunning.remove(stage);
    }
  }

  void _remember(
    String stage,
    Object error,
    StackTrace stack, {
    bool cleanup = true,
  }) {
    _causes.putIfAbsent(stage, () => (cause: error, stack: stack));
    session.lastCause ??= error;
    session.lastStack ??= stack;
    if (cleanup)
      _issues[stage] = conversationIssue(
        stage,
        error,
        CleanupRecovery.retryClose,
      );
  }
}

bool _busy(TurnBrief turn) =>
    turn.state is QueuedTurnBrief || turn.state is RunningTurnBrief;
bool _busyHeader(TurnReadHeader turn) =>
    turn.state is QueuedTurnRead || turn.state is RunningTurnRead;
const _stopStaleTarget = StudioFailure(
  code: StudioFailureCode.superseded,
  message: 'Stop requires the originally delivered active queued or running Turn on this exact Session source.',
  retryable: false,
  correlationId: 'stop-original-target',
);
