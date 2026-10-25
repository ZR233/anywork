part of 'drafts_repository.dart';

final class _AttachmentWork extends _DraftWork {
  _AttachmentWork(
    _DraftsRepository repo,
    _DraftHandle handle,
    this.writer,
    this.context,
    this.sources,
    this.image,
  ) : stamp = handle.record.attachmentStamp,
      generation = handle.record.attachmentGeneration,
      super(repo, handle, writer.ticket, 'draft-attachment');
  final DraftStamp stamp;
  final int generation;
  final OperationWriter<Unit> writer;
  final AttachmentAdmissionContext context;
  List<AttachmentDraftSource> sources;
  Uint8List? image;
  AttachmentAdmission? reservation;
  AttachmentAdmissionJob? _job;
  _DraftJobCleanup? _jobCleanup;
  bool _dispatched = false;
  bool _unknown = false;
  bool _acknowledged = false;
  bool _invalidHandle = false;
  String? _path;
  ResourcePermit? _stagePermit;
  bool _stageAttempted = false;
  StudioFailure? _stagingFailure;
  ({Object cause, StackTrace stack})? _admissionFailure;
  @override
  bool get unknown => _unknown || (reservation?.unresolved ?? false);
  @override
  bool get resourcesDone =>
      _path == null && (_jobCleanup == null || _jobCleanup!.clean);
  @override
  List<FeedCloseIssue> get resourceIssues => [
    ...?_jobCleanup?.issues,
    if (_path != null && !faults.containsKey('staging'))
      resourcePendingIssue('clipboardStagingRetained'),
  ];

  void reserveSources() {
    if (image != null || reservation != null) return;
    reservation = repo.ledger.reserveAdmission(
      draft: handle.record,
      operationId: writer.ticket.id,
      sources: sources,
      expectedStamp: stamp,
      expectedGeneration: generation,
    );
  }

  void abort(Object error, StackTrace stack) {
    _admissionFailure = (cause: error, stack: stack);
    start();
  }

  void _attachJob(AttachmentAdmissionJob job) {
    _job = job;
    _jobCleanup = _DraftJobCleanup(
      repo,
      () => job.operationId,
      job.requestClose,
      job.close,
      job.retryClose,
    );
    _jobCleanup!._captureIdentity();
    if (closing || repo._sealed) _jobCleanup!.requestClose();
    _invalidHandle = true;
    if (job.operationId != writer.ticket.id)
      throw resourceProtocol(
        'The admission handle belongs to another operation.',
      );
    _invalidHandle = false;
  }

  Future<List<AttachmentMetadata>> _result() async {
    final job = _job!;
    _invalidHandle = true;
    if (job.operationId != writer.ticket.id)
      throw resourceProtocol('The admission operation identity changed.');
    _invalidHandle = false;
    return job.result();
  }

  @override
  void requestClose() {
    super.requestClose();
    _jobCleanup?.requestClose();
  }

  @override
  Future<void> run() async {
    if (_admissionFailure case final failure?)
      Error.throwWithStackTrace(failure.cause, failure.stack);
    checkDispatch();
    final bytes = image;
    if (bytes != null) {
      if (repo.stageImage == null || repo.cleanupImage == null)
        throw _draftFailure(
          StudioFailureCode.unavailable,
          'Clipboard staging and cleanup are not configured.',
        );
      _stagePermit = repo.budget.acquire(
        ResourceKind.attachment,
        owner: '$owner:staging',
        phase: ResourcePhase.opening,
      );
      try {
        _path = await repo.stageImage!(bytes);
      } finally {
        image = null;
        if (_path == null) {
          _stagePermit?.release();
          _stagePermit = null;
        }
      }
      if (_path == null)
        throw const RejectedCommandDispatchFailure(
          failure: StudioFailure(
            code: StudioFailureCode.cancelled,
            message: 'Clipboard staging returned no file.',
            retryable: false,
            correlationId: 'clipboard-staging',
          ),
        );
      sources = List.unmodifiable([AttachmentDraftSource.localFile(_path!)]);
    }
    checkDispatch();
    // Synchronous reservation precedes the first admission await. Staging has
    // its own permit until the path is genuinely cleaned, not a canonical field.
    reserveSources();
    final admitted = reservation!;
    await admitted.dispatch(() async {
      checkDispatch();
      _dispatched = true;
      _attachJob(
        await repo.attachments.begin(writer.ticket.id, context, sources),
      );
      return _result();
    });
    _unknown = false;
    await _finishKnown();
  }

  Future<void> _finishKnown() async {
    sources = const [];
    await _cleanupStage(retry: false);
    await _jobCleanup?.cleanup(retry: false);
    repo.refreshIssues(handle);
    final issue = [...faults.values, ...?_jobCleanup?.issues].firstOrNull;
    final failure =
        _stagingFailure ??
        _jobCleanup?.failure ??
        (issue == null ? null : _issueFailure(issue));
    if (_acknowledged) {
      if (failure != null) writer.evidenceFailed(failure);
      return;
    }
    _acknowledged = true;
    if (failure == null)
      writer.acknowledged(const Unit());
    else
      writer.acknowledgedSynchronizationFailed(failure, value: const Unit());
  }

  @override
  Future<void> fail(Object error, StackTrace stack) async {
    final failure = _dispatchFailure(error);
    final rejected = !_dispatched || error is RejectedCommandDispatchFailure;
    if (_acknowledged) {
      // A later result/cleanup failure cannot revoke confirmed native success.
      _unknown = reservation?.unresolved ?? false;
      writer.evidenceFailed(failure);
    } else if (_dispatched &&
        error is ConfirmedWithoutUsableReceiptCommandDispatchFailure) {
      // The metadata is still unavailable: retain the original reservation and
      // staging, while reporting the actual success/synchronization distinction.
      _acknowledged = true;
      _unknown = true;
      writer.acknowledgedSynchronizationFailed(failure, value: const Unit());
      _stagePermit?.mark(ResourcePhase.unresolved);
    } else if (rejected) {
      if (!_dispatched && (reservation?.unresolved ?? false))
        reservation!.abandonBeforeDispatch();
      writer.rejected(failure);
      _unknown = false;
    } else if (reservation != null && !reservation!.unresolved) {
      _unknown = false;
      if (!_acknowledged) {
        _acknowledged = true;
        writer.acknowledgedSynchronizationFailed(failure, value: const Unit());
      } else
        writer.evidenceFailed(failure);
    } else {
      if (!_unknown)
        writer.unknownOutcome(failure);
      else
        writer.evidenceFailed(failure);
      _unknown = true;
      _stagePermit?.mark(ResourcePhase.unresolved);
    }
    if (!unknown) {
      sources = const [];
      await _cleanupStage(retry: false);
      await _jobCleanup?.cleanup(retry: false);
    }
    repo.refreshIssues(handle);
  }

  @override
  Future<void> recover() async {
    try {
      if (_job == null || _jobCleanup?.clean == true) {
        final found = await repo.attachments.find(writer.ticket.id);
        if (found == null) return; // absence is not rejection or a new begin
        _attachJob(found);
      }
      final admitted = reservation;
      if (admitted == null || !admitted.unresolved) return;
      await admitted.joinOriginal(_result);
      _unknown = false;
      await _finishKnown();
    } catch (error, stack) {
      repo.remember(error, stack);
      await fail(error, stack);
    }
  }

  Future<void> _cleanupStage({required bool retry}) async {
    final path = _path;
    if (path == null || unknown || _stageAttempted && !retry) return;
    _stageAttempted = true;
    try {
      await repo.cleanupImage!(path);
      _path = null;
      _stagePermit?.release();
      _stagePermit = null;
      faults.remove('staging');
      _stagingFailure = null;
    } catch (error, stack) {
      _stagingFailure = _dispatchFailure(error);
      note('staging', error, stack);
      _stagePermit?.mark(ResourcePhase.unresolved);
    }
  }

  @override
  Future<void> cleanResources({required bool retry}) async {
    if (!unknown) await _cleanupStage(retry: retry);
    if (!unknown || closing || _invalidHandle)
      await _jobCleanup?.cleanup(retry: retry);
    if ((!unknown || _invalidHandle) && _jobCleanup?.clean == true) {
      _job = null;
      _jobCleanup = null;
      _invalidHandle = false;
    }
    if (!unknown && retry) faults.remove('cleanup');
  }
}

StudioFailure _dispatchFailure(Object error) => switch (error) {
  CommandDispatchFailure(:final failure) => failure,
  _ => resourceFailure(error),
};
StudioFailure _issueFailure(FeedCloseIssue issue) => StudioFailure(
  code:
      StudioFailureCode.values
          .where((code) => code.name == issue.diagnostic.code)
          .firstOrNull ??
      StudioFailureCode.internal,
  message: issue.diagnostic.message,
  retryable: issue.diagnostic.retryable,
  correlationId: issue.diagnostic.correlationId,
);
