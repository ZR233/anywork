part of 'drafts_repository.dart';

final RegExp _inputDigest = RegExp(r'^sha256:[0-9a-f]{64}$');
void _validateInputReceipt(
  SubmitPromptReceipt receipt,
  String threadId,
  String inputId,
) {
  if (receipt.threadId != threadId ||
      receipt.inputId != inputId ||
      receipt.cursor < 0 ||
      !_inputDigest.hasMatch(receipt.requestDigest))
    throw resourceProtocol(
      'The receipt contradicts the original frozen input.',
    );
}

OperationTicket<SubmitPromptReceipt> _submitComposer(
  _DraftsRepository repo,
  _Composer handle,
  Future<void> Function()? prepare,
) {
  repo.ensureOpen();
  final frozen = handle.state.value;
  final exact = repo.conversations.existingSession(handle.threadId);
  final execution = exact?.execution.value;
  final config = exact?.configuration.value;
  repo._admitting = true;
  late final OperationWriter<SubmitPromptReceipt> writer;
  try {
    writer = repo.operations.begin<SubmitPromptReceipt>(
      target: 'composer:${handle.threadId}',
      draft: frozen.stamp,
    );
  } catch (_) {
    repo._admitting = false;
    rethrow;
  }
  FrozenAttachmentReference? references;
  _ComposerWork? work;
  try {
    handle.record.checkSubmissionAdmission();
    if (exact == null)
      throw _draftFailure(
        StudioFailureCode.unavailable,
        'The original Thread Session is not ready.',
      );
    final origin = execution?.stamp;
    final route = config?.value?.modelRoute;
    if (execution == null ||
        config == null ||
        execution.sync.phase != FacetSyncPhase.ready ||
        execution.value == null ||
        origin == null ||
        origin.facet != ThreadFacet.execution ||
        origin.runtimeEpoch.isEmpty ||
        origin.incarnation < 1 ||
        config.sync.phase != FacetSyncPhase.ready ||
        config.stamp == null ||
        config.stamp!.facet != ThreadFacet.configuration ||
        config.stamp!.runtimeEpoch != origin.runtimeEpoch ||
        config.stamp!.incarnation != origin.incarnation ||
        route == null ||
        !route.available ||
        route.revision < 0) {
      throw _draftFailure(
        StudioFailureCode.unavailable,
        'The original execution and model route are not ready together.',
      );
    }
    if (execution.value?.status == ThreadStatus.closing ||
        execution.value?.status == ThreadStatus.closed) {
      throw _draftFailure(
        StudioFailureCode.unavailable,
        'The original Thread is closing.',
      );
    }
    references = repo.ledger.freeze(
      handle.record,
      expectedStamp: frozen.stamp,
      operationId: writer.ticket.id,
    );
    final input = StudioPromptInput(
      inputId: writer.ticket.id.value,
      text: frozen.text.trim(),
      attachmentDraftIds: references.attachmentIds,
    );
    work = _ComposerWork(
      repo,
      handle,
      writer,
      input,
      references,
      exact,
      origin,
      route.revision,
      prepare,
    );
    work.bindEvidence(
      repo.demand.retainForSubmission(exact, expectedOrigin: origin),
      origin: origin,
      expectedThreadId: exact.threadId,
    );
    work.start();
    repo._admitting = false;
    handle.record.beginSubmission(writer.ticket.id, input.inputId);
  } catch (error, stack) {
    repo.remember(error, stack);
    if (work != null) {
      work.startFailure(error, stack);
    } else {
      references?.rejected().ignore();
      writer.rejected(_dispatchFailure(error));
    }
  } finally {
    repo._admitting = false;
  }
  return writer.ticket;
}

OperationTicket<StartNewThreadResult> _submitStart(
  _DraftsRepository repo,
  _Start handle,
) {
  repo.ensureOpen();
  final frozen = handle.state.value;
  WorkspaceIntentStamp? expected;
  Object? captureFailure;
  StackTrace? captureStack;
  try {
    if (repo._creating != null)
      throw _draftFailure(
        StudioFailureCode.busy,
        'The original creation has not actually settled.',
      );
    expected = repo.selection.capture(handle.projectId);
  } catch (error, stack) {
    captureFailure = error;
    captureStack = stack;
  }
  repo._admitting = true;
  late final OperationWriter<StartNewThreadResult> writer;
  try {
    writer = repo.operations.begin<StartNewThreadResult>(
      target: 'start:${handle.projectId}',
      draft: frozen.stamp,
    );
  } catch (_) {
    repo._admitting = false;
    rethrow;
  }
  FrozenAttachmentReference? references;
  _CreateWork? work;
  try {
    if (captureFailure != null)
      Error.throwWithStackTrace(captureFailure, captureStack!);
    handle.record.checkSubmissionAdmission();
    if (repo._creating != null)
      throw _draftFailure(
        StudioFailureCode.busy,
        'The original creation has not actually settled.',
      );
    final prepared = frozen.routePreparation;
    if (prepared is! ReadyStartRoutePreparation ||
        prepared.result.sources != _routeSources(repo) ||
        prepared.result.intent != _routeIntent(repo, frozen.mode)) {
      throw _draftFailure(
        StudioFailureCode.unavailable,
        'Explicitly prepare the current Start route before submitting.',
      );
    }
    references = repo.ledger.freeze(
      handle.record,
      expectedStamp: frozen.stamp,
      operationId: writer.ticket.id,
    );
    final input = StudioPromptInput(
      inputId: writer.ticket.id.value,
      text: frozen.text.trim(),
      attachmentDraftIds: references.attachmentIds,
    );
    final request = NewThreadCreationRequest(
      projectId: handle.projectId,
      input: input,
      mode: frozen.mode,
      route: prepared.result.route,
      workspaceMode: frozen.workspaceMode,
      delegationMode:
          frozen.delegationModeOverride ?? prepared.result.defaults.mode,
      delegationPreference:
          frozen.delegationPreferenceOverride ??
          prepared.result.defaults.preference,
    );
    work = _CreateWork(
      repo,
      handle,
      writer,
      input,
      references,
      request,
      expected!,
    );
    repo._creating = work;
    work.start();
    repo._admitting = false;
    handle.record.beginSubmission(writer.ticket.id, input.inputId);
  } catch (error, stack) {
    repo.remember(error, stack);
    if (work != null)
      work.startFailure(error, stack);
    else {
      references?.rejected().ignore();
      writer.rejected(_dispatchFailure(error));
    }
  } finally {
    repo._admitting = false;
  }
  return writer.ticket;
}

abstract class _SubmissionWork<T> extends _DraftWork {
  _SubmissionWork(
    _DraftsRepository repo,
    _DraftHandle handle,
    this.writer,
    this.input,
    this.references,
  ) : super(repo, handle, writer.ticket, 'draft-submission');
  final OperationWriter<T> writer;
  final StudioPromptInput input;
  final FrozenAttachmentReference references;
  SubmissionExecutionLease? lease;
  SubmittedInputObserver<T>? observer;
  CloseReport? _observerReport;
  bool _observerOwnsLease = false;
  bool _observerConstructionFailed = false;
  bool _unknown = false;
  bool _confirmedWithoutReceipt = false;
  bool dispatched = false;
  bool referenceFinished = false;
  bool published = false;
  T? value;
  ({Object cause, StackTrace stack})? _startFailure;
  @override
  bool get unknown => _unknown;
  @override
  bool get archiveCleanupEligible => false;
  bool get evidenceDone => observer == null
      ? lease == null
      : _observerReport != null && _observerReport!.unresolved.isEmpty;
  @override
  List<FeedCloseIssue> get resourceIssues => [
    if (_observerReport case final report?)
      for (final item in report.unresolved) ...item.issues,
    if (!evidenceDone && _observerReport == null)
      resourcePendingIssue('inputEvidenceRetained'),
  ];

  @override
  void requestClose() {
    super.requestClose();
    try {
      observer?.requestClose();
    } finally {
      try {
        lease?.requestCloseTurnReads();
      } catch (error, stack) {
        note('execution-demand', error, stack);
      }
    }
  }

  void startFailure(Object error, StackTrace stack) {
    _startFailure = (cause: error, stack: stack);
    if (_running == null) start();
  }

  void checkStart() {
    if (_startFailure case final failure?)
      Error.throwWithStackTrace(failure.cause, failure.stack);
    checkDispatch();
  }

  void bindEvidence(
    SubmissionExecutionLease original, {
    ThreadFacetStamp? origin,
    required String expectedThreadId,
  }) {
    lease = original;
    if (original.threadId != expectedThreadId ||
        origin != null && origin.facet != ThreadFacet.execution) {
      throw resourceProtocol(
        'The input evidence lease changed its original Thread or facet.',
      );
    }
    original.bindExecutionTurns(
      consume: (handoff, stamp, turns) {
        if (!identical(handoff, original))
          throw resourceProtocol(
            'The execution handoff replaced its original lease.',
          );
        if (closing || repo._sealed) {
          original.requestCloseTurnReads();
          return Future.value();
        }
        _installObserver(original, stamp);
        return observer!.consumeTurns(original, stamp, turns);
      },
      onFailure: writer.evidenceFailed,
    );
    if (origin != null) _installObserver(original, origin);
    if (closing || repo._sealed) original.requestCloseTurnReads();
  }

  void _installObserver(
    SubmissionExecutionLease original,
    ThreadFacetStamp origin,
  ) {
    if (observer != null) return;
    _observerOwnsLease =
        true; // Constructor takes demand on entry, including rollback.
    try {
      observer = SubmittedInputObserver<T>(
        threadId: original.threadId,
        inputId: input.inputId,
        origin: origin,
        attemptId: original.attemptId,
        execution: original.execution,
        original: original,
        operation: writer,
        budget: repo.budget,
        readAcceptance: () =>
            repo.commands.readInputAcceptance(original.threadId, input.inputId),
        releaseDemand: () {
          original.release();
          lease = null;
        },
      );
    } on SubmittedInputObserverConstructionFailure<T> catch (error) {
      observer = error.cleanup;
      _observerConstructionFailed = true;
      Error.throwWithStackTrace(error.failure, error.causeStack);
    } catch (_) {
      _observerOwnsLease = false;
      rethrow;
    }
  }

  bool acknowledgeRecord() => switch (handle) {
    _Composer(:final record) => record.acknowledged(
      writer.ticket.id,
      references.stamp,
    ),
    _Start(:final record) => record.acknowledged(
      writer.ticket.id,
      references.stamp,
    ),
  };
  void failRecord(StudioFailure error, {required bool unknown}) {
    switch (handle) {
      case _Composer(:final record):
        record.failed(
          writer.ticket.id,
          input.inputId,
          references.stamp,
          error,
          unknown: unknown,
        );
      case _Start(:final record):
        record.failed(
          writer.ticket.id,
          input.inputId,
          references.stamp,
          error,
          unknown: unknown,
        );
    }
  }

  Future<void> transferReferences() async {
    if (referenceFinished) return;
    referenceFinished = true;
    final clear = acknowledgeRecord();
    await Future.wait([
      if (clear) references.draftReferences.detach(),
      references.acknowledged(),
    ]);
    repo.refreshIssues(handle);
  }

  Future<void> finishValue(
    T result,
    SubmitPromptReceipt receipt, {
    StudioFailure? synchronizationError,
  }) async {
    value = result;
    _unknown = false;
    StudioFailure? failure = synchronizationError;
    try {
      observer?.acceptReceipt(receipt);
    } catch (error, stack) {
      repo.remember(error, stack);
      failure ??= resourceFailure(error);
    }
    try {
      await transferReferences();
    } catch (error, stack) {
      repo.remember(error, stack);
      failure ??= resourceFailure(error);
    }
    if (published) {
      if (failure != null) writer.evidenceFailed(failure);
      return;
    }
    published = true;
    if (failure == null)
      writer.acknowledged(result);
    else
      writer.acknowledgedSynchronizationFailed(failure, value: result);
  }

  @override
  Future<void> fail(Object error, StackTrace stack) async {
    final failure = _dispatchFailure(error);
    if (value != null) {
      if (!published) {
        published = true;
        writer.acknowledgedSynchronizationFailed(failure, value: value);
      } else
        writer.evidenceFailed(failure);
      return;
    }
    if (_confirmedWithoutReceipt ||
        dispatched &&
            error is ConfirmedWithoutUsableReceiptCommandDispatchFailure) {
      _confirmedWithoutReceipt = true;
      _unknown = true;
      references.unknown(failure);
      failRecord(failure, unknown: true);
      if (!published) {
        published = true;
        writer.acknowledgedSynchronizationFailed(failure);
      } else
        writer.evidenceFailed(failure);
    } else if (!dispatched || error is RejectedCommandDispatchFailure) {
      _unknown = false;
      failRecord(failure, unknown: false);
      if (!referenceFinished) {
        referenceFinished = true;
        try {
          await references.rejected();
        } catch (cleanupError, cleanupStack) {
          repo.remember(cleanupError, cleanupStack);
        }
      }
      writer.rejected(failure);
    } else {
      references.unknown(failure);
      failRecord(failure, unknown: true);
      if (!_unknown)
        writer.unknownOutcome(failure);
      else
        writer.evidenceFailed(failure);
      _unknown = true;
    }
  }

  Future<void> cleanEvidence({required bool retry}) async {
    if (observer case final original?) {
      if (closing ||
          _observerConstructionFailed ||
          original.isFinished ||
          value == null && !_unknown) {
        _observerReport = await original.close(retry: retry);
        if (_observerReport!.complete) faults.remove('execution-demand');
      }
    } else if (!_observerOwnsLease && lease != null) {
      try {
        _observerReport = await lease!.closeTurnReads(retry: retry);
        if (_observerReport!.complete) {
          lease!.release();
          lease = null;
          faults.remove('execution-demand');
        }
      } catch (error, stack) {
        note('execution-demand', error, stack);
      }
    }
  }
}

final class _ComposerWork extends _SubmissionWork<SubmitPromptReceipt> {
  _ComposerWork(
    super.repo,
    _Composer super.handle,
    super.writer,
    super.input,
    super.references,
    this.exact,
    this.origin,
    this.routeRevision,
    this.prepare,
  );
  final ConversationSession exact;
  final ThreadFacetStamp origin;
  final int routeRevision;
  final Future<void> Function()? prepare;
  @override
  bool get resourcesDone => evidenceDone && referenceFinished;
  @override
  Future<void> run() async {
    checkStart();
    if (prepare != null) await prepare!();
    checkDispatch();
    dispatched = true;
    final receipt = await repo.commands.submitPrompt(
      exact.threadId,
      input,
      expectedModelRouteRevision: routeRevision,
    );
    _validateInputReceipt(receipt, exact.threadId, input.inputId);
    await finishValue(receipt, receipt);
  }

  @override
  Future<void> recover() async {
    // No native receipt lookup exists for this command. A history miss or a
    // saved Turn cannot synthesize its receipt or authorize a second submit.
  }
  @override
  Future<void> cleanResources({required bool retry}) =>
      cleanEvidence(retry: retry);
}

final class _CreateWork extends _SubmissionWork<StartNewThreadResult> {
  _CreateWork(
    super.repo,
    _Start super.handle,
    super.writer,
    super.input,
    super.references,
    this.request,
    this.expected,
  );
  final NewThreadCreationRequest request;
  final WorkspaceIntentStamp expected;
  NewThreadCreation? _creation;
  _DraftJobCleanup? _jobCleanup;
  Observation? _progress;
  bool _workerEnded = false;
  bool _invalidHandle = false;
  StudioFailure? _progressFailure;
  @override
  bool get resourcesDone =>
      evidenceDone &&
      referenceFinished &&
      (_jobCleanup == null || _jobCleanup!.clean) &&
      _progress == null;
  @override
  List<FeedCloseIssue> get resourceIssues => [
    ...super.resourceIssues,
    ...?_jobCleanup?.issues,
  ];

  void _attachCreation(NewThreadCreation creation) {
    _creation = creation;
    _jobCleanup = _DraftJobCleanup(
      repo,
      () => creation.operationId,
      creation.requestClose,
      creation.close,
      creation.retryClose,
    );
    _jobCleanup!._captureIdentity();
    if (closing || repo._sealed) _jobCleanup!.requestClose();
    _invalidHandle = true;
    _checkCreation();
    _invalidHandle = false;
    if (!closing && !repo._sealed) {
      try {
        final progress = creation.progress;
        _progress = progress.watch(_considerProgress);
        if (closing || repo._sealed)
          _cancelProgress();
        else
          _considerProgress(progress.value);
      } catch (error, stack) {
        repo.remember(error, stack);
        _progressFailure = resourceFailure(error);
        writer.evidenceFailed(_progressFailure!);
      }
    }
  }

  void _checkCreation() {
    _invalidHandle = true;
    final original = _creation!;
    if (original.operationId != writer.ticket.id ||
        original.projectId != request.projectId ||
        original.inputId != input.inputId)
      throw resourceProtocol(
        'The creation handle changed its original operation/project/input identity.',
      );
    _invalidHandle = false;
  }

  void _considerProgress(ThreadPreparationProgress? progress) {
    if (progress == null || value != null || closing || repo._sealed) return;
    if (progress.projectId != request.projectId ||
        progress.inputId != input.inputId) {
      _progressFailure = resourceProtocol(
        'Creation progress belongs to another input.',
      );
      writer.evidenceFailed(_progressFailure!);
      return;
    }
    (handle as _Start).record.progress(writer.ticket.id, progress);
  }

  void _cancelProgress() {
    try {
      _progress?.cancel();
      _progress = null;
      faults.remove('preparation-watch');
    } catch (error, stack) {
      note('preparation-watch', error, stack);
    }
  }

  void _settleGate() {
    if ((_workerEnded ||
            !_invalidHandle &&
                _creation != null &&
                _jobCleanup?.clean == true) &&
        identical(repo._creating, this))
      repo._creating = null;
  }

  @override
  void requestClose() {
    try {
      super.requestClose();
    } finally {
      _jobCleanup?.requestClose();
      _cancelProgress();
    }
  }

  @override
  Future<void> run() async {
    checkStart();
    dispatched = true;
    _attachCreation(await repo.creations.begin(writer.ticket.id, request));
    await _joinResult();
  }

  Future<void> _joinResult() async {
    _checkCreation();
    final StartNewThreadResult result;
    try {
      result = await _creation!.result();
      _workerEnded = true;
    } on RejectedCommandDispatchFailure {
      _workerEnded = true;
      rethrow;
    } finally {
      _settleGate();
    }
    if (result.thread.projectId != request.projectId ||
        result.thread.id.isEmpty) {
      throw resourceProtocol(
        'The created Thread belongs to another frozen project.',
      );
    }
    _validateInputReceipt(result.receipt, result.thread.id, input.inputId);
    value =
        result; // A source/read/selection failure cannot revoke known success.
    StudioFailure? syncFailure = _progressFailure;
    try {
      if (closing || repo._sealed) throw resourceCancelled;
      final source = await _creation!.executionSource();
      if (closing || repo._sealed) throw resourceCancelled;
      if (source.threadId != result.thread.id ||
          source.inputId != input.inputId) {
        throw resourceProtocol(
          'The created input source belongs to another successful result.',
        );
      }
      final exact = repo.conversations.session(result.thread.id);
      final retained = repo.demand.retainForCreatedInput(
        exact,
        receipt: result.receipt,
        source: source,
      );
      bindEvidence(retained, expectedThreadId: result.thread.id);
      if (closing || repo._sealed) throw resourceCancelled;
      final origin = await retained.ready;
      if (closing || repo._sealed) throw resourceCancelled;
      // The first (even empty) baseline normally installed this observer in the
      // pre-ACK handoff. An already-ready original source needs no replayed Turn.
      _installObserver(retained, origin);
    } catch (error, stack) {
      repo.remember(error, stack);
      syncFailure = resourceFailure(error);
    }
    try {
      repo.selection.adoptCreatedThread(result.thread, expected);
    } catch (error, stack) {
      repo.remember(error, stack);
      syncFailure ??= resourceFailure(error);
    }
    await finishValue(
      result,
      result.receipt,
      synchronizationError: syncFailure,
    );
  }

  @override
  Future<void> recover() async {
    try {
      if (_creation == null || _jobCleanup?.clean == true) {
        final original = await repo.creations.find(writer.ticket.id);
        if (original == null) return;
        _attachCreation(original);
      }
      await _joinResult();
    } catch (error, stack) {
      repo.remember(error, stack);
      await fail(error, stack);
    } finally {
      _settleGate();
    }
  }

  @override
  Future<void> fail(Object error, StackTrace stack) async {
    if (!dispatched || error is RejectedCommandDispatchFailure)
      _workerEnded = true;
    await super.fail(error, stack);
    _settleGate();
  }

  @override
  Future<void> cleanResources({required bool retry}) async {
    await cleanEvidence(retry: retry);
    if (closing || value != null || !unknown) _cancelProgress();
    if (closing ||
        _invalidHandle ||
        evidenceDone && (!unknown || _workerEnded)) {
      await _jobCleanup?.cleanup(retry: retry);
      _settleGate();
    }
    if (_jobCleanup?.clean == true && (!unknown || _invalidHandle)) {
      _creation = null;
      _jobCleanup = null;
      _invalidHandle = false;
    }
  }
}
