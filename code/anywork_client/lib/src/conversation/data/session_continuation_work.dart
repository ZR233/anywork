part of 'session_owner.dart';

const _continuationConflict = StudioFailure(
  code: StudioFailureCode.conflict,
  message: 'The continuation intent does not match its original Session, operation or route.',
  retryable: false,
  correlationId: 'continuation-intent',
);
const _childRequiresParent = StudioFailure(
  code: StudioFailureCode.permissionDenied,
  message: 'A child agent is continued and instructed by the main session, not by the user',
  retryable: false,
  correlationId: 'child-requires-parent-scheduling',
  details: StudioFailureDetails.reason(reason: 'childThreadRequiresParentScheduling'),
);

/// One control input, with no prompt text or synthetic Turn. Only named result
/// queries may recover a lost response; neither cleanup nor a repeated intent
/// dispatches another continue command.
final class _ContinueThreadWork implements ResourceOwner {
  _ContinueThreadWork(this.session, this.origin, this.continuationId, this.routeRevision)
      : attempt = session._commandActions.lifetime.nextAttempt();
  final ConversationSessionOwner session;
  final ThreadFacetStamp origin;
  final String continuationId;
  final int routeRevision;
  late final OperationWriter<ContinueThreadReply> writer;
  bool writerAssigned = false;
  @override
  final int attempt;
  @override
  String get owner => 'continue:${session.threadId}:$continuationId';
  final _done = Completer<void>();
  Future<ContinuationOperationView?>? _querying;
  Future<ContinuationOperationView?>? _lastSettlement;
  SubmissionExecutionLease? _lease;
  ResourcePermit? _permit;
  ContinueThreadReply? _reply;
  ContinuationOperationView? _view;
  StudioFailure? _failure;
  StudioFailure? _settlementFailure;
  bool _issued = false;
  bool _confirmed = false;
  bool _unknown = false;
  bool _rejected = false;
  bool _closed = false;
  bool _evidenceReleased = false;

  void notStarted() {
    _rejected = true;
    if (writerAssigned) writer.rejected(conversationCancelled);
    if (!_done.isCompleted) _done.complete();
    unawaited(_releaseEvidence().catchError((Object error, StackTrace stack) {
      session.lastCause = error;
      session.lastStack = stack;
      _failure ??= conversationFailure(error);
    }));
  }

  void retain() {
        _lease = session.retainForSubmission(expectedOrigin: origin);
        _lease!.bindExecutionTurns(
          consume: (_, __, ___) {
            // No query is awaited by its own reliable execution handoff.
            if (_done.isCompleted && !_closed) scheduleMicrotask(() {
              try { query().ignore(); } catch (error, stack) { _fail(error, stack, querying: true); }
            });
            return Future.value();
          },
          onFailure: (failure) {
            _failure = failure;
            if (writerAssigned) writer.evidenceFailed(failure);
          },
        );
  }

  void start() {
    unawaited(session._commandActions.lifetime.accepted(this, () async {
      try {
        _permit = session._budget.acquire(ResourceKind.pendingOperation, owner: owner);
        session.requireSettlementOrigin(origin);
        if (_closed) throw conversationCancelled;
        _issued = true;
        final reply = await session._commands.continueThread(
          session.threadId,
          operationId: writer.ticket.id,
          expectedContinuationId: continuationId,
          expectedModelRouteRevision: routeRevision,
        );
        _confirmed = true;
        _validate(reply);
        _reply = reply;
        writer.accepted(reply, reply.receipt);
      } catch (error, stack) {
        _fail(error, stack);
      } finally {
        _permit?.release();
        _done.complete();
      }
      if (!_rejected) {
        // This is settlement of the already registered control input, not a
        // new public query. Closing cannot revoke its saving responsibility.
        try { await _settlementQuery(); } catch (_) { /* Original query retains the cause. */ }
      }
      if (_rejected) await _releaseEvidence();
    }));
  }

  bool _validReceipt(CommitReceipt receipt) {
    final targets = receipt.targets.whereType<ResourceStamp>().toList();
    return receipt.operationId == writer.ticket.id &&
        receipt.requiresIdentityObservation && receipt.effect == EffectPoint.immediate &&
        !receipt.effective && !receipt.durable && targets.length == 2 &&
        receipt.targets.length == 2 && targets.every((target) => target.ownerEpoch == origin.runtimeEpoch && target.revision >= 0) &&
        targets.map((target) => target.resourceKey).toSet().containsAll({
          'thread-input:${writer.ticket.id.value}', 'thread-continuation:$continuationId',
        });
  }

  void _validate(ContinueThreadReply reply) {
    if (reply.threadId != session.threadId || reply.inputId != writer.ticket.id.value ||
        reply.continuationId != continuationId || reply.cursor < 0 ||
        !_validReceipt(reply.receipt) ||
        reply.receipt.targets.whereType<ResourceStamp>().singleWhere((target) => target.resourceKey == 'thread-continuation:$continuationId').revision != reply.cursor) {
      throw readProtocol('The continuation reply contradicts its frozen control input.');
    }
  }

  Future<ContinuationOperationView?> query() {
    if (_closed) return Future.error(conversationCancelled);
    if (released) return Future.value(_view);
    session.requireSettlementOrigin(origin);
    return session._commandActions.lifetime.accepted(this, _settlementQuery);
  }

  /// Private continuation of this registered ResourceOwner. It freezes the
  /// original Thread/operation, survives lifetime seal, and is joined by both
  /// the original dispatch work and cleanup. It never dispatches continue.
  Future<ContinuationOperationView?> _settlementQuery() {
    if (_querying case final existing?) return existing;
    final done = Completer<ContinuationOperationView?>();
    _querying = done.future;
    _lastSettlement = done.future;
    done.future.ignore();
    unawaited(Future<ContinuationOperationView?>.sync(() async {
      try {
        await _done.future;
        if (_rejected) return null;
        final view = await session._commands.readContinuationOperation(session.threadId, writer.ticket.id);
        // No ordinary read_input_acceptance or lifecycle Idle can supply this.
        if (view != null) {
          final reply = ContinueThreadReply(threadId: view.threadId, inputId: view.inputId,
              continuationId: view.continuationId, cursor: view.acceptedSequence, receipt: view.receipt);
          _validate(reply);
          if (view.operationId != writer.ticket.id ||
              _reply != null && (_reply!.inputId != view.inputId || _reply!.cursor != view.acceptedSequence) ||
              view.state is ConsumedContinuation && (view.state as ConsumedContinuation).turnId.isEmpty) throw readProtocol('The continuation query changed the original operation identity.');
          if (_view?.durable == true && !view.durable) throw readProtocol('Continuation durability regressed.');
          _reply ??= reply;
          _confirmed = true;
          _unknown = false;
          _view = view;
          _settlementFailure = view.durable ? null : _continuationNotDurable;
          // An accepted native error may not carry a usable receipt. The
          // existing registry keeps that accurate acknowledgement separately;
          // the named query still exposes its real receipt and durable facts.
          if (!writer.ticket.state.value.acknowledged) writer.accepted(_reply!, _reply!.receipt);
          for (final target in view.receipt.targets) { session._operations.observe(target); }
          writer.identityObserved();
          if (view.state is ConsumedContinuation) writer.effective();
          if (view.durable) writer.durable();
          if (view.durable && (_closed || view.state is! PendingContinuation)) await _releaseEvidence();
        } else {
          _settlementFailure = _continuationNotDurable;
        }
        return view;
      } catch (error, stack) {
        _settlementFailure = error is CommandDispatchFailure ? error.failure : conversationFailure(error);
        _fail(error, stack, querying: true);
        rethrow;
      }
    }).then<void>((value) {
      _querying = null;
      done.complete(value);
    }, onError: (Object error, StackTrace stack) {
      _querying = null;
      done.completeError(error, stack);
    }));
    return done.future;
  }

  void _fail(Object error, StackTrace stack, {bool querying = false}) {
    session.lastCause = error;
    session.lastStack = stack;
    final failure = error is CommandDispatchFailure ? error.failure : conversationFailure(error);
    _failure ??= failure;
    if (querying) {
      writer.evidenceFailed(failure);
      return;
    }
    if (error is CommittedButUnobservedCommandDispatchFailure) {
      _confirmed = true;
      if (_validReceipt(error.receipt)) {
      writer.synchronizationFailed(failure, receipt: error.receipt);
      } else {
        writer.acknowledgedSynchronizationFailed(failure);
      }
    } else if (_confirmed || error is ConfirmedWithoutUsableReceiptCommandDispatchFailure) {
      _confirmed = true;
      writer.acknowledgedSynchronizationFailed(failure);
    } else if (!_issued || error is RejectedCommandDispatchFailure) {
      _rejected = true;
      writer.rejected(failure);
    } else {
      _unknown = true;
      writer.unknownOutcome(failure);
    }
  }

  Future<void> _releaseEvidence({bool retry = false}) async {
    if (_evidenceReleased) return;
    final lease = _lease;
    if (lease != null) {
      lease.requestCloseTurnReads();
      final report = await lease.closeTurnReads(retry: retry);
      if (!report.complete) throw readProtocol('Continuation execution observation has unresolved cleanup.');
      lease.release();
    }
    _evidenceReleased = true;
  }

  @override
  bool get released => _done.isCompleted && _querying == null && _evidenceReleased &&
      !_unknown && (_rejected || _view?.durable == true);
  @override
  void requestClose() { _closed = true; }
  @override
  Future<void> cleanup({required bool retry}) async {
    await _done.future;
    if (!_rejected && (_querying != null || _view?.durable != true)) {
      // A normal close joins the already started attempt, including its failure.
      // Only an explicit cleanup retry starts another same-operation read.
      final settlement = _querying ??
          (retry || _lastSettlement == null ? _settlementQuery() : _lastSettlement!);
      try { await settlement; } catch (_) { /* Original query cause is retained. */ }
    }
    await _releaseEvidence(retry: retry);
  }
  @override
  List<FeedCloseIssue> get issues => released ? const [] : [
    conversationIssue('continuationOperation', _settlementFailure ?? _failure ?? _continuationNotDurable,
        _done.isCompleted && _querying == null ? CleanupRecovery.retryClose : CleanupRecovery.awaitCompletion),
  ];
}

const _continuationNotDurable = StudioFailure(
  code: StudioFailureCode.unavailable,
  message: 'The original continuation operation has not yet supplied durable saving evidence.',
  retryable: true,
  correlationId: 'continuation-durable-settlement',
);
