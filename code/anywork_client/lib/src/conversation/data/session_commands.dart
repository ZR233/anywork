part of 'session_owner.dart';

/// Actual work belongs to this concrete Session, not to an observer or route.
/// The registry is the sole result/receipt store. Unknown work retains its
/// original typed closure and never dispatches again, including during cleanup.
final class _ConversationCommands {
  _ConversationCommands(this.session)
    : lifetime = ResourceLifetime(session._budget);
  final ConversationSessionOwner session;
  final ResourceLifetime lifetime;
  final Map<int, _ConversationCommandOwner> _work = {};
  final Map<String, Future<void>> _lanes = {};

  OperationTicket<Unit> compact(ThreadFacetStamp origin) => _run<Unit>(
    origin: origin,
    facet: ThreadFacet.context,
    target: 'compact:${session.threadId}',
    lane: 'thread:${session.threadId}',
    rejectDuplicate: true,
    dispatch: (id) async {
      await session._commands.compactThread(session.threadId, operationId: id);
      return const Unit();
    },
    receipt: (_) => null,
  );

  OperationTicket<CommitReceipt> setMode(
    ThreadFacetStamp origin,
    String mode,
  ) => _run<CommitReceipt>(
    origin: origin,
    facet: ThreadFacet.configuration,
    target: 'mode:${session.threadId}',
    lane: 'thread:${session.threadId}',
    dispatch: (id) => session._commands.setThreadMode(
      session.threadId,
      mode,
      operationId: id,
    ),
    receipt: (value) => value,
    validate: (_, receipt) {
      _targets(receipt!, origin, {
        'thread-mode:${session.threadId}',
        'thread-directory',
      });
    },
    observe: (_, owner) =>
        _observeConfiguration(owner, origin, 'thread-mode:${session.threadId}'),
  );

  OperationTicket<ThreadModelRouteCommandReply> setRoute(
    ThreadFacetStamp origin,
    String accountId,
    String modelId,
    String? effort,
    int routeRevision,
    int settingsRevision, {
    OperationId? operationId,
  }) => _run<ThreadModelRouteCommandReply>(
    operationId: operationId,
    retryIntent: (accountId, modelId, effort),
    origin: origin,
    facet: ThreadFacet.configuration,
    target: 'route:${session.threadId}',
    lane: 'thread:${session.threadId}',
    prepare: () {
      _revision(routeRevision);
      _revision(settingsRevision);
      return Future.value();
    },
    dispatch: (id) => session._commands.setThreadModelRoute(
      session.threadId,
      operationId: id,
      accountId: accountId,
      modelId: modelId,
      effort: effort,
      expectedModelRouteRevision: routeRevision,
      expectedSettingsRevision: settingsRevision,
    ),
    receipt: (value) => value.receipt,
    validate: (value, receipt) {
      if (value.runtime.threadId != session.threadId)
        throw readProtocol('The route result belongs to another Thread.');
      _targets(receipt!, origin, {
        'thread-route:${session.threadId}',
        if (value.modeDefaultSaved) 'settings',
      });
      final route = value.runtime.modelRoute;
      final target = _target(receipt, 'thread-route:${session.threadId}');
      if (route == null ||
          route.revision != target.revision ||
          route.revision < routeRevision ||
          route.accountId != accountId ||
          route.modelId != modelId) {
        throw readProtocol(
          'The route result contradicts its frozen target and receipt.',
        );
      }
    },
    observe: (_, owner) => _observeConfiguration(
      owner,
      origin,
      'thread-route:${session.threadId}',
    ),
  );

  OperationTicket<InteractionCommandReply> respond(
    ThreadFacetStamp origin,
    String interactionId,
    int expectedRevision,
    InteractionResolutionCommand resolution, {
    OperationId? operationId,
    InteractionReadRef? hostedReference,
    String? targetThreadId,
  }) => _run<InteractionCommandReply>(
    operationId: operationId,
    retryIntent: (interactionId, resolution, hostedReference, targetThreadId),
    interactionReference: hostedReference,
    origin: origin,
    facet: ThreadFacet.execution,
    target: 'interaction:$interactionId',
    lane: 'interaction:$interactionId',
    // Native accepts a globally-addressed interaction ID, not a Thread. Verify
    // the original immutable read before sending, not after a foreign write.
    prepare: () async {
      if (!session.acceptsUserInput) throw _childRequiresParent;
      _revision(expectedRevision);
      if (hostedReference != null &&
          hostedReference.revision != expectedRevision)
        throw _continuationConflict;
      await _readInteraction(
        origin,
        interactionId,
        expectedRevision,
        hostedReference: hostedReference,
        targetThreadId: targetThreadId,
        rejectChildPlan: true,
      );
    },
    dispatch: (id) => session._commands.respondInteraction(
      session.threadId,
      interactionId,
      operationId: id,
      expectedInteractionRevision: expectedRevision,
      resolution: resolution,
    ),
    receipt: (value) => value.receipt,
    validate: (value, receipt) {
      final interaction = value.interaction;
      _targets(receipt!, origin, {'interaction:$interactionId'});
      if (interaction.interactionId != interactionId ||
          interaction.scope.threadId != (targetThreadId ?? session.threadId) ||
          interaction.revision < expectedRevision ||
          interaction.revision !=
              _target(receipt, 'interaction:$interactionId').revision ||
          !receipt.requiresIdentityObservation ||
          interaction.content.status == InteractionStatus.pending) {
        throw readProtocol(
          'The interaction reply contradicts its frozen identity or observation contract.',
        );
      }
    },
    observe: (value, owner) async {
      // Native locators cannot be upgraded at an old, unexposed source revision.
      // Only this registered command waits for its original entry's reliable
      // fact; public hosted membership is never relaxed for a reply DTO.
      final readOrigin =
          hostedReference == null ||
              value.interaction.revision == hostedReference.revision
          ? origin
          : await owner.waitForInteractionReceipt(value.interaction.revision);
      await _readInteraction(
        readOrigin,
        interactionId,
        value.interaction.revision,
        expected: value,
        hostedReference: hostedReference == null
            ? null
            : hostedReference.copyWith(revision: value.interaction.revision),
        targetThreadId: targetThreadId,
      );
      // Only this real original-version read supplies canonical evidence, not
      // the command's DTO, local revision arithmetic or a fabricated read scope.
      session._operations.observe(value.receipt.targets.single);
    },
  );

  void observeExecution(ThreadFacetStamp stamp, InteractionDelta? delta) {
    if (delta == null) return;
    for (final work in List.of(_work.values)) {
      if (work is _ConversationCommand && !_sameProjection(work.origin, stamp))
        continue;
      if (work is _ConversationCommand) {
        for (final fact in [...delta.upserted, ...delta.terminalFacts]) {
          work.observeInteraction(stamp, fact);
        }
      }
    }
  }

  void _check(ThreadFacetStamp origin, ThreadFacet facet) {
    lifetime.admit();
    session.requireOrigin(origin);
    _requireFacet(origin, facet);
  }

  /// Settlement admission for an already admitted command. The accepted receipt
  /// and the original-source observation still settle after the owner stopped
  /// admitting new business; this never admits new work.
  void _settle(ThreadFacetStamp origin, ThreadFacet facet) {
    session.requireSettlementOrigin(origin);
    _requireFacet(origin, facet);
  }

  void _requireFacet(ThreadFacetStamp origin, ThreadFacet facet) {
    if (origin.facet != facet)
      throw const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'The action requires its original named facet.',
        retryable: false,
        correlationId: 'conversation-command-origin',
      );
  }

  OperationTicket<T> _run<T>({
    required ThreadFacetStamp origin,
    required ThreadFacet facet,
    OperationId? operationId,
    Object? retryIntent,
    InteractionReadRef? interactionReference,
    required String target,
    required String lane,
    required Future<T> Function(OperationId) dispatch,
    required CommitReceipt? Function(T) receipt,
    Future<void> Function()? prepare,
    void Function(T, CommitReceipt?)? validate,
    Future<void> Function(T, _ConversationCommand<T>)? observe,
    bool rejectDuplicate = false,
  }) {
    _check(origin, facet);
    _ConversationCommand<T>? retried;
    if (operationId != null) {
      for (final work in _work.values) {
        if (work is _ConversationCommand<T> &&
            work.writer?.ticket.id == operationId &&
            identical(
              session._operations.observations.lookup(operationId)?.state,
              work.writer?.ticket.state,
            ))
          retried = work;
      }
      if (retried == null || !retried.canRetry)
        throw const StudioFailure(
          code: StudioFailureCode.conflict,
          message: 'The original intent has no known CAS rejection to retry.',
          retryable: false,
          correlationId: 'conversation-command-retry',
        );
      if (retryIntent == null ||
          retried.retryIntent != retryIntent ||
          retried.target != target ||
          !_sameProjection(retried.origin, origin))
        throw const StudioFailure(
          code: StudioFailureCode.invalidArgument,
          message: 'A retry cannot change the original intent or Session incarnation.',
          retryable: false,
          correlationId: 'conversation-command-retry-intent',
        );
    }
    _work.removeWhere(
      (_, work) =>
          work.released &&
          !(work is _ConversationCommand &&
              work.canRetry &&
              identical(
                session._operations.observations
                    .lookup(work.writer!.ticket.id)
                    ?.state,
                work.writer!.ticket.state,
              )),
    );
    for (final work in _work.values) {
      if (work.lane == lane && work.unknown ||
          rejectDuplicate &&
              work.target == target &&
              !work.dispatchDone.isCompleted) {
        throw const StudioFailure(
          code: StudioFailureCode.conflict,
          message: 'The original target already has an unresolved or duplicate command.',
          retryable: false,
          correlationId: 'conversation-command-pending',
        );
      }
    }
    final previous = _lanes[lane];
    final owner = _ConversationCommand<T>(
      this,
      origin,
      facet,
      target,
      lane,
      dispatch,
      receipt,
      prepare,
      validate,
      observe,
      retryIntent: retryIntent,
      interactionReference: interactionReference,
    );
    _work[owner.attempt] = owner;
    _lanes[lane] = owner.dispatchDone.future;
    try {
      owner.writer = session._operations.begin<T>(
        target: target,
        operationId: operationId,
        requireIdentityObservation: observe != null,
      );
      if (retried != null) retried.retryConsumed = true;
      lifetime.register(owner);
      owner.start(previous);
    } catch (error, stack) {
      owner.notStarted(error, stack);
      if (owner.writer == null) rethrow;
    }
    return owner.writer!.ticket;
  }

  void _dispatchSettled(_ConversationCommandOwner owner) {
    if (!owner.dispatchDone.isCompleted) owner.dispatchDone.complete();
    if (identical(_lanes[owner.lane], owner.dispatchDone.future)) {
      unawaited(_lanes.remove(owner.lane));
    }
  }

  Future<void> _observeConfiguration<T>(
    _ConversationCommand<T> owner,
    ThreadFacetStamp origin,
    String key,
  ) async {
    final revision = _target(owner.receipt!, key).revision;
    await owner.waitFor(session.configuration, (state) {
      final stamp = state.stamp;
      if (stamp != null && !_sameProjection(stamp, origin))
        throw _submissionSuperseded;
      if (state.sync.error case final error?) throw error;
      if (state.sync.phase != FacetSyncPhase.ready ||
          stamp == null ||
          state.value == null)
        return false;
      final observed = key.startsWith('thread-mode:')
          ? state.value!.modeBindingRevision
          : state.value!.modelRoute?.revision;
      return observed != null && observed >= revision;
    });
  }

  Future<void> _readInteraction(
    ThreadFacetStamp origin,
    String id,
    int revision, {
    InteractionCommandReply? expected,
    InteractionReadRef? hostedReference,
    String? targetThreadId,
    bool rejectChildPlan = false,
  }) async {
    session.requireOrigin(origin);
    final scope = hostedReference == null
        ? await session.openInteraction(
            interactionId: id,
            expectedRevision: revision,
            expectedIncarnation: origin.incarnation,
          )
        : rejectChildPlan
        ? await session.openHostedInteraction(
            origin: origin,
            reference: hostedReference,
            targetThreadId: targetThreadId ?? session.threadId,
          )
        : expected != null
        ? await session.openInteractionReference(origin, hostedReference)
        : throw readProtocol(
            'Only a validated hosted receipt may use the internal observation read.',
          );
    Object? primaryFailure;
    try {
      session.requireOrigin(origin);
      final header = await scope.header();
      final readText = (int fieldId, int offset) =>
          scope.text(fieldId, offset: offset, maxBytes: 65536);
      final actualTarget = await materializeReadText(
        header.threadId,
        read: readText,
      );
      if (actualTarget != (targetThreadId ?? session.threadId) ||
          await materializeReadText(header.interactionId, read: readText) !=
              id) {
        throw readProtocol(
          'The hosted interaction reference does not identify its original target.',
        );
      }
      if (rejectChildPlan &&
          actualTarget != session.threadId &&
          header.purpose is PlanConfirmationPurposeRead)
        throw _childRequiresParent;
      if (rejectChildPlan &&
          header.content is UserInputContentRead &&
          header.purpose is GeneralInteractionPurposeRead) {
        var offset = 0;
        final count = (header.content as UserInputContentRead).questionCount;
        while (offset < count) {
          final page = await scope.questions(offset: offset, limit: 32);
          for (final question in page.items) {
            if (await materializeReadText(question.id, read: readText) ==
                'plan_confirmation') {
              throw const StudioFailure(
                code: StudioFailureCode.invalidArgument,
                message: 'The plan_confirmation question identity is reserved for the Plan command.',
                retryable: false,
                correlationId: 'reserved-plan-question',
              );
            }
          }
          if (page.nextOffset == null) break;
          offset = page.nextOffset!;
        }
      }
      if (expected != null) {
        final status = switch (header.state) {
          PendingInteractionRead() => InteractionStatus.pending,
          ResolvedUserInputRead() ||
          ResolvedApprovalRead() => InteractionStatus.resolved,
          CancelledInteractionRead() => InteractionStatus.cancelled,
          ExpiredInteractionRead() => InteractionStatus.expired,
        };
        if (header.scope.runtimeEpoch != origin.runtimeEpoch ||
            header.scope.incarnation != origin.incarnation ||
            header.revision != revision ||
            status != expected.interaction.content.status ||
            await materializeReadText(
                  header.turnId,
                  read: (fieldId, offset) =>
                      scope.text(fieldId, offset: offset, maxBytes: 65536),
                ) !=
                expected.interaction.scope.turnId) {
          throw readProtocol(
            'The canonical interaction read did not observe the original command target.',
          );
        }
      }
      session.requireOrigin(origin);
    } catch (error) {
      primaryFailure = error;
      rethrow;
    } finally {
      try {
        scope.requestClose();
        if (!(await scope.close()).complete)
          throw const StudioFailure(
            code: StudioFailureCode.unavailable,
            message:
                'The original interaction command read has unresolved cleanup.',
            retryable: true,
            correlationId: 'interaction-command-read-cleanup',
          );
      } catch (error, stack) {
        // The read owner retains its unresolved cleanup. Do not overwrite an
        // earlier typed read failure with the subsequent close diagnostic.
        if (primaryFailure == null) rethrow;
        session.lastCause = error;
        session.lastStack = stack;
      }
    }
  }

  void seal() => lifetime.seal();
  Future<CloseReport> close({DateTime? deadline, required bool retry}) =>
      lifetime.close(deadline: deadline, retry: retry);
}

void _revision(int revision) {
  if (revision < 0)
    throw const StudioFailure(
      code: StudioFailureCode.invalidArgument,
      message: 'The expected command revision must be nonnegative.',
      retryable: false,
      correlationId: 'conversation-command-revision',
    );
}

ResourceStamp _target(CommitReceipt receipt, String key) => receipt.targets
    .whereType<ResourceStamp>()
    .singleWhere((stamp) => stamp.resourceKey == key);

void _targets(
  CommitReceipt receipt,
  ThreadFacetStamp origin,
  Set<String> keys,
) {
  if (receipt.targets.length != keys.length ||
      receipt.targets.any(
        (target) =>
            target is! ResourceStamp ||
            target.ownerEpoch != origin.runtimeEpoch ||
            target.revision < 0 ||
            !keys.contains(target.resourceKey),
      ) ||
      receipt.targets
              .whereType<ResourceStamp>()
              .map((target) => target.resourceKey)
              .toSet()
              .length !=
          keys.length) {
    throw readProtocol(
      'The command receipt does not belong to its original resource owner and targets.',
    );
  }
}

abstract class _ConversationCommandOwner implements ResourceOwner {
  _ConversationCommandOwner(this.actions, this.target, this.lane)
    : attempt = actions.lifetime.nextAttempt();
  final _ConversationCommands actions;
  final String target;
  final String lane;
  @override
  final int attempt;
  final Completer<void> dispatchDone = Completer<void>();
  bool unknown = false;
}

final class _ConversationCommand<T> extends _ConversationCommandOwner {
  _ConversationCommand(
    super.actions,
    this.origin,
    this.facet,
    super.target,
    super.lane,
    this.dispatch,
    this.receiptOf,
    this.prepare,
    this.validate,
    this.observe, {
    this.retryIntent,
    this.interactionReference,
  });
  final Object? retryIntent;
  final InteractionReadRef? interactionReference;
  ThreadFacetStamp? _interactionOrigin;
  int _interactionRevision = -1;
  Completer<void> _interactionChanged = Completer<void>();

  void observeInteraction(ThreadFacetStamp source, InteractionBrief fact) {
    if (interactionReference?.entry != fact.reference.entry ||
        !_sameProjection(origin, source) ||
        fact.status == InteractionStatus.pending ||
        fact.reference.revision != fact.revision ||
        fact.revision < _interactionRevision)
      return;
    _interactionOrigin = source;
    _interactionRevision = fact.revision;
    final changed = _interactionChanged;
    _interactionChanged = Completer<void>();
    changed.complete();
  }

  Future<ThreadFacetStamp> waitForInteractionReceipt(int revision) async {
    final failed = Completer<void>();
    failed.future.ignore();
    void check(ThreadExecutionState state) {
      if (failed.isCompleted) return;
      final stamp = state.stamp;
      final error = stamp != null && !_sameProjection(stamp, origin)
          ? _submissionSuperseded
          : state.sync.error;
      if (error != null) failed.completeError(error);
    }

    final watching = actions.session.execution.watchLatest(check);
    check(watching.value);
    try {
      while (_interactionRevision < revision || _interactionOrigin == null) {
        if (_closing.isCompleted) throw conversationCancelled;
        await Future.any([
          _interactionChanged.future,
          failed.future,
          _closing.future.then<void>((_) => throw conversationCancelled),
        ]);
      }
      _settle();
      return _interactionOrigin!;
    } finally {
      watching.observation.cancel();
    }
  }

  bool retryConsumed = false;
  bool get canRetry =>
      retryIntent != null &&
      !retryConsumed &&
      _settled.isCompleted &&
      _issued &&
      !_confirmed &&
      !unknown &&
      writer?.ticket.state.value.failurePhase ==
          OperationFailurePhase.rejected &&
      {
        StudioFailureCode.conflict,
        StudioFailureCode.staleRevision,
      }.contains(_failure?.code);
  final ThreadFacetStamp origin;
  final ThreadFacet facet;
  // Retain original immutable arguments through this closure for UnknownOutcome.
  final Future<T> Function(OperationId) dispatch;
  final CommitReceipt? Function(T) receiptOf;
  final Future<void> Function()? prepare;
  final void Function(T, CommitReceipt?)? validate;
  final Future<void> Function(T, _ConversationCommand<T>)? observe;
  OperationWriter<T>? writer;
  CommitReceipt? receipt;
  T? value;
  T? returnedEvidence;
  bool _issued = false;
  bool _confirmed = false;
  final Completer<void> _settled = Completer<void>();
  final Completer<void> _closing = Completer<void>();
  final List<(Object, StackTrace)> _causes = [];
  StudioFailure? _failure;
  @override
  String get owner =>
      'conversation-command:${actions.session.threadId}:$attempt';

  void start(Future<void>? previous) {
    unawaited(
      actions.lifetime.accepted<void>(this, () async {
        try {
          if (previous != null) await previous;
          _admit();
          if (actions._work.values.any(
            (other) =>
                !identical(other, this) && other.lane == lane && other.unknown,
          )) {
            throw const StudioFailure(
              code: StudioFailureCode.conflict,
              message: 'The preceding command outcome is unknown.',
              retryable: false,
              correlationId: 'conversation-command-lane',
            );
          }
          if (prepare case final preparing?) await preparing();
          _admit();
          _issued = true;
          final returned = await dispatch(writer!.ticket.id);
          returnedEvidence = returned;
          _confirmed = true;
          final mapped = receiptOf(returned);
          if (mapped != null && mapped.operationId != writer!.ticket.id)
            throw readProtocol('The receipt belongs to another operation.');
          validate?.call(returned, mapped);
          receipt = mapped;
          value = returned;
          if (mapped == null) {
            writer!.acknowledged(returned);
          } else {
            writer!.accepted(returned, mapped);
          }
          actions._dispatchSettled(this);
          if (observe case final observing?) {
            _settle();
            await observing(returned, this);
            writer!.identityObserved();
          }
        } catch (error, stack) {
          _fail(error, stack);
        } finally {
          actions._dispatchSettled(this);
          _settled.complete();
        }
      }),
    );
  }

  void _admit() {
    if (_closing.isCompleted) throw conversationCancelled;
    actions._check(origin, facet);
  }

  void _settle() => actions._settle(origin, facet);

  void notStarted(Object error, StackTrace stack) {
    _fail(error, stack);
    actions._dispatchSettled(this);
    if (!_settled.isCompleted) _settled.complete();
  }

  void _fail(Object error, StackTrace stack) {
    _causes.add((error, stack));
    actions.lifetime.lastCause = error;
    actions.lifetime.lastStack = stack;
    final failure = error is CommandDispatchFailure
        ? error.failure
        : conversationFailure(error);
    _failure ??= failure;
    final output = writer;
    if (output == null) return;
    if (error is CommittedButUnobservedCommandDispatchFailure) {
      _confirmed = true;
      if (error.receipt.operationId == output.ticket.id) {
        // A partially converted result may still have a real original receipt.
        // Domain target/epoch validation is never skipped on this failure path.
        final key = facet == ThreadFacet.execution
            ? target
            : target.startsWith('mode:')
            ? 'thread-mode:${actions.session.threadId}'
            : 'thread-route:${actions.session.threadId}';
        final keys = facet == ThreadFacet.execution
            ? {key}
            : target.startsWith('mode:')
            ? {key, 'thread-directory'}
            : {key, if (error.receipt.targets.length == 2) 'settings'};
        try {
          _targets(error.receipt, origin, keys);
          if (facet != ThreadFacet.execution ||
              error.receipt.requiresIdentityObservation)
            receipt = error.receipt;
        } catch (validationError, validationStack) {
          _causes.add((validationError, validationStack));
        }
      }
    } else if (error is ConfirmedWithoutUsableReceiptCommandDispatchFailure) {
      _confirmed = true;
    }
    if (output.ticket.state.value.observed) {
      output.evidenceFailed(failure);
    } else if (_confirmed) {
      if (receipt case final committed?) {
        output.synchronizationFailed(failure, value: value, receipt: committed);
      } else {
        output.acknowledgedSynchronizationFailed(failure, value: value);
      }
    } else if (!_issued || error is RejectedCommandDispatchFailure) {
      output.rejected(failure);
    } else {
      unknown = true;
      output.unknownOutcome(failure);
    }
  }

  Future<void> waitFor<S>(
    ReadonlyLatestValue<S> source,
    bool Function(S) matches,
  ) async {
    final observed = Completer<void>();
    void inspect(S state) {
      if (observed.isCompleted) return;
      try {
        if (matches(state)) observed.complete();
      } catch (error, stack) {
        observed.completeError(error, stack);
      }
    }

    final watch = source.watchLatest(inspect);
    inspect(watch.value);
    try {
      await Future.any([
        observed.future,
        _closing.future.then<void>((_) => throw conversationCancelled),
      ]);
    } finally {
      watch.observation.cancel();
    }
  }

  @override
  bool get released =>
      _settled.isCompleted &&
      !unknown &&
      (writer == null ||
          !_confirmed ||
          receipt == null ||
          writer!.ticket.state.value.observed);
  @override
  void requestClose() {
    if (!_closing.isCompleted) _closing.complete();
  }

  @override
  Future<void> cleanup({required bool retry}) async {
    await _settled.future;
    final output = writer;
    if (receipt != null &&
        output != null &&
        !output.ticket.state.value.observed &&
        output.ticket.state.value.failurePhase == null) {
      _fail(conversationCancelled, StackTrace.current);
    }
  }

  @override
  List<FeedCloseIssue> get issues => released
      ? const []
      : [
          conversationIssue(
            'conversationCommand',
            _failure ?? conversationCancelled,
            _settled.isCompleted
                ? CleanupRecovery.terminal
                : CleanupRecovery.awaitCompletion,
          ),
        ];
}
