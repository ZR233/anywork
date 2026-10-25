part of 'drafts_repository.dart';

/// One admitted Drafts action. The lifetime and this original work retain late
/// handles; a ticket/observer ending does not drop cleanup or unknown outcomes.
abstract class _DraftWork implements ResourceOwner {
  _DraftWork(this.repo, this.handle, this.operation, String label)
    : attempt = repo.lifetime.nextAttempt(),
      owner = '$label:${operation.id.value}' {
    repo.lifetime.register(this);
    repo._work.add(this);
    try {
      _operationWatch = operation.state.watch((_) => _scheduleCleanup());
    } catch (error, stack) {
      _setupFailure = (cause: error, stack: stack);
      repo.remember(error, stack);
    }
  }
  final _DraftsRepository repo;
  final _DraftHandle handle;
  final OperationObservation operation;
  @override
  final int attempt;
  @override
  final String owner;
  Observation? _operationWatch;
  ({Object cause, StackTrace stack})? _setupFailure;
  final Map<String, FeedCloseIssue> faults = {};
  Future<void>? _running;
  final Completer<void> _started = Completer();
  Future<void>? _cleaning;
  bool _done = false;
  bool closing = false;
  bool _released = false;
  bool _scheduled = false;
  @override
  bool get released => _released;
  bool get unknown;
  bool get resourcesDone;
  bool get archiveCleanupEligible => true;
  Future<void> run();
  Future<void> fail(Object error, StackTrace stack);
  Future<void> recover();
  Future<void> cleanResources({required bool retry});
  List<FeedCloseIssue> get resourceIssues;

  void start() {
    if (_running != null) return;
    final done = Completer<void>();
    _running = done.future;
    _started.complete();
    Future<void> execute() async {
      await Future<void>.value();
      try {
        if (_setupFailure case final failure?)
          Error.throwWithStackTrace(failure.cause, failure.stack);
        await run();
      } catch (error, stack) {
        repo.remember(error, stack);
        await fail(error, stack);
      }
    }

    Future<void> work;
    try {
      work = repo.lifetime.accepted(this, execute);
    } catch (error, stack) {
      work = Future<void>.sync(() => fail(error, stack));
    }
    unawaited(
      work.then<void>(
        (_) {
          _done = true;
          done.complete();
          _scheduleCleanup();
        },
        onError: (Object error, StackTrace stack) {
          note('settlement', error, stack, CleanupRecovery.terminal);
          _done = true;
          done.complete();
          _scheduleCleanup();
        },
      ),
    );
  }

  void checkDispatch() {
    if (closing || repo._sealed)
      throw const RejectedCommandDispatchFailure(failure: resourceCancelled);
  }

  void note(
    String stage,
    Object error,
    StackTrace stack, [
    CleanupRecovery recovery = CleanupRecovery.retryClose,
  ]) {
    repo.remember(error, stack);
    faults[stage] = resourceCleanupIssue(error, recovery);
  }

  void _scheduleCleanup() {
    if (_scheduled || _released) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      if (_done && !_released) cleanup(retry: false).ignore();
    });
  }

  @override
  void requestClose() {
    closing = true;
  }

  @override
  Future<void> cleanup({required bool retry}) {
    if (_cleaning case final pending?) return pending;
    if (_released) return Future.value();
    final done = Completer<void>();
    _cleaning = done.future;
    unawaited(
      Future<void>.sync(() async {
        await _started.future;
        if (_running case final running?) await running;
        if (unknown && (closing || retry)) await recover();
        if (retry) {
          try {
            await repo.ledger.retryOperationCleanup(operation.id);
          } catch (error, stack) {
            repo.remember(error, stack);
          }
        }
        await cleanResources(retry: retry);
        repo.refreshIssues(handle);
        if (retry) faults.remove('cleanup');
        if (!unknown &&
            resourcesDone &&
            repo.ledger.cleanupIssuesForOperation(operation.id).isEmpty &&
            faults.keys.every((key) => key == 'operation-watch')) {
          try {
            _operationWatch?.cancel();
            _operationWatch = null;
            faults.remove('operation-watch');
          } catch (error, stack) {
            note('operation-watch', error, stack);
            return;
          }
          _released = true;
          repo._prune(this);
        }
      }).then<void>(
        (_) {
          _cleaning = null;
          done.complete();
        },
        onError: (Object error, StackTrace stack) {
          note('cleanup', error, stack);
          _cleaning = null;
          done.complete();
        },
      ),
    );
    return done.future;
  }

  @override
  List<FeedCloseIssue> get issues => [
    ...faults.values,
    ...resourceIssues,
    for (final issue in repo.ledger.cleanupIssuesForOperation(operation.id))
      resourceCleanupIssue(issue.error, CleanupRecovery.retryClose),
    if (!_done || _cleaning != null) resourcePendingIssue('draftWorkPending'),
    if (unknown) resourcePendingIssue('originalDraftOutcomeUnknown'),
  ];
}

/// Close bookkeeping for one concrete job handle. Current report/cause only;
/// terminal issues are actual unresolved obligations, not retry history.
final class _DraftJobCleanup {
  _DraftJobCleanup(
    this.repo,
    this.identity,
    this.request,
    this.closeNative,
    this.retryNative,
  );
  final _DraftsRepository repo;
  final OperationId Function() identity;
  final void Function() request;
  final Future<FeedCloseReport> Function() closeNative;
  final Future<FeedCloseReport> Function() retryNative;
  FeedCloseReport? _report;
  final Map<String, ({Object cause, StackTrace stack, FeedCloseIssue issue})>
  _failures = {};
  final Set<FeedCloseIssue> _terminal = {};
  String? _id;
  Future<void>? _running;
  bool _attempted = false;
  bool get clean =>
      _report?.outcome is CleanFeedCloseOutcome &&
      _failures.isEmpty &&
      _terminal.isEmpty;
  StudioFailure? get failure =>
      _failures.isEmpty ? null : _dispatchFailure(_failures.values.first.cause);
  List<FeedCloseIssue> get issues => [
    if (_report?.outcome case UnresolvedFeedCloseOutcome(:final issues))
      ...issues,
    ..._terminal,
    for (final failure in _failures.values) failure.issue,
    if (_running != null || !clean && _failures.isEmpty && _report == null)
      resourcePendingIssue('nativeDraftJobRetained'),
  ];
  void _remember(String stage, Object error, StackTrace stack) {
    repo.remember(error, stack);
    _failures[stage] = (
      cause: error,
      stack: stack,
      issue: resourceCleanupIssue(error, CleanupRecovery.retryClose),
    );
  }

  void _captureIdentity() {
    try {
      final id = _id ?? identity().value;
      if (id.isEmpty)
        throw resourceProtocol('The original draft job has no identity.');
      _id = id;
      _failures.remove('identity');
    } catch (error, stack) {
      _remember('identity', error, stack);
    }
  }

  void requestClose() {
    try {
      request();
      _failures.remove('request');
    } catch (error, stack) {
      _remember('request', error, stack);
    }
  }

  Future<void> cleanup({required bool retry}) {
    if (_running case final pending?) return pending;
    if (clean || _attempted && !retry) return Future.value();
    final done = Completer<void>();
    _running = done.future;
    _attempted = true;
    unawaited(
      Future<void>.sync(() async {
        try {
          // Capture the original job ID before adapter disposal, never from report.
          _captureIdentity();
          requestClose();
          final report = await (retry ? retryNative() : closeNative());
          if (_id == null) _captureIdentity();
          if (_id == null || _id!.isEmpty || report.feedId != _id) {
            throw resourceProtocol(
              'The draft job close report changed its original identity.',
            );
          }
          _report = report;
          _failures.remove('close');
          if (report.outcome is CleanFeedCloseOutcome) {
            // Verified actual close supersedes an earlier request-only failure.
            _failures.remove('request');
          }
          if (report.outcome case UnresolvedFeedCloseOutcome(:final issues)) {
            _terminal.addAll(
              issues.where(
                (issue) => issue.recovery == CleanupRecovery.terminal,
              ),
            );
          }
        } catch (error, stack) {
          _remember('close', error, stack);
        }
      }).then<void>(
        (_) {
          _running = null;
          done.complete();
        },
        onError: (Object error, StackTrace stack) {
          _remember('close', error, stack);
          _running = null;
          done.complete();
        },
      ),
    );
    return done.future;
  }
}

final class _LocalDraftWork extends _DraftWork {
  _LocalDraftWork(
    _DraftsRepository repo,
    _DraftHandle handle,
    this.writer,
    this.references,
  ) : super(repo, handle, writer.ticket, 'draft-edit');
  final OperationWriter<Unit> writer;
  final AttachmentDraftReferences references;
  bool edited = false;
  ({Object error, StackTrace stack})? _aborted;
  void abort(Object error, StackTrace stack) {
    _aborted = (error: error, stack: stack);
    start();
  }

  @override
  bool get unknown => false;
  @override
  bool get resourcesDone => references.cleanupIssues.isEmpty;
  @override
  List<FeedCloseIssue> get resourceIssues => references.cleanupIssues;
  @override
  Future<void> run() async {
    if (_aborted case final aborted?)
      Error.throwWithStackTrace(aborted.error, aborted.stack);
    if (!edited) checkDispatch();
    await references.detach();
    writer.acknowledged(const Unit());
  }

  @override
  Future<void> fail(Object error, StackTrace stack) async {
    if (!edited) {
      writer.rejected(_dispatchFailure(error));
      return;
    }
    // A local mutation already published before seal still owns its detach.
    // The captured Future is idempotent, including an already failed delete.
    try {
      await references.detach();
      writer.acknowledged(const Unit());
    } catch (cleanupError, cleanupStack) {
      repo.remember(cleanupError, cleanupStack);
      writer.acknowledgedSynchronizationFailed(
        resourceFailure(cleanupError),
        value: const Unit(),
      );
    }
  }

  @override
  Future<void> recover() async {}
  @override
  Future<void> cleanResources({required bool retry}) async {
    if (retry) await references.retryCleanup();
  }
}
