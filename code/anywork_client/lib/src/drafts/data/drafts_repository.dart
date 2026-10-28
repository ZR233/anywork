import 'dart:async';
import 'dart:typed_data';

import '../../../configuration.dart';
import '../../../conversation_ports.dart';
import '../../../models.dart' show AccountModelKey;
import '../../../modes.dart';
import '../../../operations_ports.dart';
import '../../../resources_ports.dart';
import '../../../workspace.dart';
import '../../../workspace_ports.dart'
    show
        WorkspaceSubmissionSelection,
        WorkspaceArchiveCapturePort,
        WorkspaceArchiveCapture,
        WorkspaceProjectArchiveCapture,
        WorkspaceThreadArchiveCapture;
import '../../conversation/data/conversation_mirror.dart';
import '../domain/draft_values.dart';
import '../domain/drafts_repository.dart';
import '../domain/submission_values.dart';
import 'attachment_admission_port.dart';
import 'attachment_binary_port.dart';
import 'attachment_binary_read_owner.dart';
import 'attachment_draft_record.dart';
import 'attachment_ledger.dart';
import 'composer_draft_record.dart';
import 'new_thread_creation_port.dart';
import 'start_draft_record.dart';
import 'submitted_input_observer.dart';

part 'draft_handles.dart';
part 'draft_routes.dart';
part 'draft_work.dart';
part 'draft_attachment_work.dart';
part 'draft_submission_work.dart';
part 'draft_archive.dart';

/// Constructs local owners only. Explicit prepare/read/command demands open
/// resources; obtaining a handle never activates a Thread or writes settings.
({DraftsRepository repository, WorkspaceArchiveCapturePort archive})
createDraftsRepository({
  required ConfigurationRepository configuration,
  required WorkspaceRepository workspace,
  required WorkspaceSubmissionSelection submissionSelection,
  required ConversationRepository conversations,
  required ConversationDemand conversationDemand,
  required ConversationCommandPort conversationCommands,
  required AttachmentAdmissionPort attachments,
  required NewThreadCreationPort creations,
  required AttachmentBinaryPort binary,
  required ResourceBudget budget,
  required OperationRecorder operations,
  Future<String?> Function(Uint8List)? clipboardImageStager,
  Future<void> Function(String)? clipboardImageCleanup,
}) {
  final permit = budget.acquire(
    ResourceKind.readModel,
    owner: 'drafts-repository',
  );
  _DraftsRepository? owner;
  try {
    owner = _DraftsRepository(
      configuration,
      workspace,
      submissionSelection,
      conversations,
      conversationDemand,
      conversationCommands,
      attachments,
      creations,
      binary,
      budget,
      operations,
      permit,
      clipboardImageStager,
      clipboardImageCleanup,
    );
    owner.initialize();
    return (repository: owner, archive: owner);
  } catch (error, stack) {
    try {
      owner?.preferences.close();
    } catch (cleanupError, cleanupStack) {
      owner?.remember(cleanupError, cleanupStack);
    } finally {
      permit.release();
    }
    Error.throwWithStackTrace(error, stack);
  }
}

final class _DraftsRepository
    implements DraftsRepository, WorkspaceArchiveCapturePort, ResourceOwner {
  _DraftsRepository(
    this.configuration,
    this.workspace,
    this.selection,
    this.conversations,
    this.demand,
    this.commands,
    this.attachments,
    this.creations,
    this.binary,
    this.budget,
    this.operations,
    this._permit,
    this.stageImage,
    this.cleanupImage,
  ) : lifetime = ResourceLifetime(budget),
      preferences = ConversationMirror(
        StartRoutePreferences(models: const {}, efforts: const {}),
        budget: budget,
        owner: 'drafts:routes',
      );
  final ConfigurationRepository configuration;
  final WorkspaceRepository workspace;
  final WorkspaceSubmissionSelection selection;
  final ConversationRepository conversations;
  final ConversationDemand demand;
  final ConversationCommandPort commands;
  final AttachmentAdmissionPort attachments;
  final NewThreadCreationPort creations;
  final AttachmentBinaryPort binary;
  final ResourceBudget budget;
  final OperationRecorder operations;
  final ResourcePermit _permit;
  final Future<String?> Function(Uint8List)? stageImage;
  final Future<void> Function(String)? cleanupImage;
  final ResourceLifetime lifetime;
  final ConversationMirror<StartRoutePreferences> preferences;
  late final AttachmentLedger ledger;
  final Map<String, _Composer> _composers = {};
  final Map<String, _Start> _starts = {};
  final Set<_DraftWork> _work = Set.identity();
  final Set<_DraftArchive> _archives = Set.identity();
  final Map<String, int> _routeRevisions = {};
  final Map<String, ({int revision, SelectModelStartRouteQuery query})>
  _selections = {};
  final Map<_DraftHandle, FeedCloseIssue> _disposeIssues = Map.identity();
  Observation? _configurationWatch;
  FeedCloseIssue? _watchIssue;
  _CreateWork? _creating;
  bool _sealed = false;
  bool _disposed = false;
  bool _admitting = false;
  Future<void>? _cleaning;
  Future<CloseReport>? _closing;

  /// The lifetime responsibility [_closing] settled on, and whether it settled
  /// complete. A later explicit retry installs a newer responsibility there, so
  /// a close that settled incomplete only stays shared while that responsibility
  /// is still the current one.
  Future<void>? _joined;
  int _joinGeneration = 0;
  bool _joinSettled = false;
  bool _joinComplete = false;

  /// One shared bounded observation of [_closing]; reused while it is pending.
  Future<CloseReport>? _boundedClosing;
  bool _boundedSettled = false;
  bool _archiveCleanupRequested = false;
  bool _archiveCleanupScheduled = false;
  @override
  late final int attempt;
  @override
  String get owner => 'drafts-repository';
  @override
  bool get released => _disposed;

  void initialize() {
    attempt = lifetime.nextAttempt();
    ledger = AttachmentLedger(
      lifetime: lifetime,
      removeNative: attachments.remove,
      retainedDraftReferences: () => [
        for (final capture in _archives) ...capture.retainedDraftReferences,
      ],
    );
    lifetime.register(this);
    _configurationWatch = configuration.state.watch((_) => _sourcesChanged());
  }

  void ensureOpen() {
    lifetime.admit();
    if (_sealed || _admitting)
      throw _draftFailure(
        _sealed ? StudioFailureCode.cancelled : StudioFailureCode.busy,
        'The draft owner is sealed or admitting another synchronous operation.',
      );
  }

  @override
  ComposerDraft composer(String threadId) {
    ensureOpen();
    return _composers.putIfAbsent(
      threadId,
      () => _Composer(
        this,
        ComposerDraftRecord(threadId: threadId, budget: budget),
      ),
    );
  }

  @override
  StartDraft start(String projectId) {
    ensureOpen();
    return _starts.putIfAbsent(
      projectId,
      () =>
          _Start(this, StartDraftRecord(projectId: projectId, budget: budget)),
    );
  }

  @override
  ReadonlyLatestValue<StartRoutePreferences> get startRoutes =>
      preferences.readonly;
  @override
  void setStartModel(ThreadModeId mode, String accountId, String modelId) =>
      _setStartModel(this, mode, accountId, modelId);
  @override
  void setStartEffort(ThreadModeId mode, String effort) =>
      _setStartEffort(this, mode, effort);
  void _sourcesChanged() => _invalidateSources(this);
  OperationTicket<SubmitPromptReceipt> submitComposer(
    _Composer handle,
    Future<void> Function()? prepare,
  ) => _submitComposer(this, handle, prepare);
  OperationTicket<StartNewThreadResult> submitStart(_Start handle) =>
      _submitStart(this, handle);
  @override
  WorkspaceProjectArchiveCapture captureProject(
    String projectId, {
    required WorkspaceState frozenSelection,
  }) => _captureProject(this, projectId, frozenSelection);
  @override
  WorkspaceThreadArchiveCapture captureThread(
    String threadId, {
    required WorkspaceState frozenSelection,
  }) => _captureThread(this, threadId, frozenSelection);

  @override
  Future<Uint8List> readDraftAttachment(String draftId) {
    ensureOpen();
    return AttachmentBinaryReadOwner.draft(
      lifetime: lifetime,
      port: binary,
      draftId: draftId,
    ).value;
  }

  @override
  Future<Uint8List> readThreadAttachment(String threadId, String attachmentId) {
    ensureOpen();
    return AttachmentBinaryReadOwner.thread(
      lifetime: lifetime,
      port: binary,
      threadId: threadId,
      attachmentId: attachmentId,
    ).value;
  }

  OperationWriter<T> begin<T>(_DraftHandle handle, String action) =>
      operations.begin<T>(
        target: 'draft:${handle.record.attachmentStamp.draftId}:$action',
        draft: handle.record.attachmentStamp,
      );

  OperationTicket<Unit> attach(
    _DraftHandle handle,
    List<AttachmentDraftSource> sources, {
    Uint8List? image,
  }) {
    ensureOpen();
    final frozenSources = List<AttachmentDraftSource>.unmodifiable(sources);
    final bytes = image == null ? null : Uint8List.fromList(image);
    AttachmentAdmissionContext? frozenContext;
    Object? contextFailure;
    StackTrace? contextStack;
    try {
      frozenContext = handle is _Composer
          ? AttachmentAdmissionContext.existingThread(handle.threadId)
          : AttachmentAdmissionContext.newThread(
              route: _readyStartRoute(
                this,
                (handle as _Start).state.value,
              ).route,
            );
    } catch (error, stack) {
      contextFailure = error;
      contextStack = stack;
    }
    _admitting = true;
    late final OperationWriter<Unit> writer;
    try {
      writer = begin<Unit>(handle, 'attachment');
    } finally {
      _admitting = false;
    }
    _AttachmentWork? work;
    try {
      if (contextFailure != null)
        Error.throwWithStackTrace(contextFailure, contextStack!);
      work = _AttachmentWork(
        this,
        handle,
        writer,
        frozenContext!,
        frozenSources,
        bytes,
      );
      // Local/remote admission reserves synchronously before returning a ticket.
      // Clipboard reserves once its real staged source exists, using this stamp.
      work.reserveSources();
      work.start();
    } catch (error, stack) {
      remember(error, stack);
      if (work == null)
        writer.rejected(_dispatchFailure(error));
      else
        work.abort(error, stack);
    }
    return writer.ticket;
  }

  OperationTicket<Unit> editAttachments(_DraftHandle handle, String? id) {
    ensureOpen();
    final captured = ledger.captureDraft(
      handle.record,
      attachmentIds: id == null ? null : [id],
    );
    _admitting = true;
    late final OperationWriter<Unit> writer;
    try {
      writer = begin<Unit>(handle, id == null ? 'discard' : 'remove');
    } catch (_) {
      _admitting = false;
      rethrow;
    }
    _LocalDraftWork? work;
    try {
      work = _LocalDraftWork(this, handle, writer, captured);
      _admitting = false;
      // Publish locally before returning. A subsequent edit is not discarded by
      // a queued mutation; only captured references are detached asynchronously.
      if (id == null)
        handle.discardRecord();
      else
        handle.removeRecord(id);
      work.edited = true;
      work.start();
    } catch (error, stack) {
      remember(error, stack);
      if (work == null)
        writer.rejected(_dispatchFailure(error));
      else
        work.abort(error, stack);
    } finally {
      _admitting = false;
    }
    return writer.ticket;
  }

  void refreshIssues(_DraftHandle handle) {
    if (!handle.disposed)
      handle.publishCleanup(ledger.cleanupIssuesFor(handle.record));
  }

  void _prune(_DraftWork work) {
    if (work.released) _work.remove(work);
    if (_sealed) {
      _disposeClosedRecords();
      _archiveCleanupRequested = true;
      _scheduleArchiveCleanup();
    }
  }

  void _disposeClosedRecords() {
    for (final handle in [..._composers.values, ..._starts.values]) {
      if (handle.disposed ||
          !handle.canDispose ||
          _archives.any((capture) => capture.retainsRecord(handle)) ||
          ledger.hasDraftReferences(handle.record) ||
          _work.any((work) => identical(work.handle, handle) && !work.released))
        continue;
      // Physical attachment cleanup has its own ledger owner and permit. A
      // closed unrelated record does not retain that file or another capture.
      try {
        handle.disposeRecord();
        _disposeIssues.remove(handle);
      } catch (error, stack) {
        remember(error, stack);
        _disposeIssues[handle] = resourceCleanupIssue(
          error,
          CleanupRecovery.retryClose,
        );
      }
    }
  }

  /// One really completed archive retires only its own detached records. It is
  /// deliberately narrower than [_disposeClosedRecords]: a live repository keeps
  /// every other draft, every newer edit and every record another capture still
  /// retains. The record's own dispose releases its draft permit.
  void _retireArchived(_DraftArchive capture) {
    if (_sealed || _disposed) return;
    for (final handle in capture.retiredHandles) {
      if (handle.disposed ||
          !handle.canDispose ||
          _archives.any((other) => other.retainsRecord(handle)) ||
          ledger.hasDraftReferences(handle.record) ||
          _work.any((work) => identical(work.handle, handle) && !work.released))
        continue;
      try {
        handle.disposeRecord();
        _disposeIssues.remove(handle);
        _composers.removeWhere((_, value) => identical(value, handle));
        _starts.removeWhere((_, value) => identical(value, handle));
      } catch (error, stack) {
        remember(error, stack);
        _disposeIssues[handle] = resourceCleanupIssue(
          error,
          CleanupRecovery.retryClose,
        );
      }
    }
  }

  void archiveChanged(_DraftArchive capture) {
    if (capture.released) {
      _archives.remove(capture);
      _retireArchived(capture);
    }
    if (_sealed) {
      ledger.requestClose();
      _disposeClosedRecords();
    }
    // Last overlapping borrow release can make an ID collectible while open.
    // The same completed archive is retried once the ledger really released its
    // borrows, so a still-retained record is never retired or silently dropped.
    ledger
        .cleanup(retry: false)
        .then<void>(
          (_) {
            _retireArchived(capture);
          },
          onError: (Object _, StackTrace __) {
            _retireArchived(capture);
          },
        )
        .ignore();
    if (!_sealed || _disposed) return;
    _archiveCleanupRequested = true;
    _scheduleArchiveCleanup();
  }

  void _scheduleArchiveCleanup() {
    if (_cleaning != null || _archiveCleanupScheduled) return;
    _archiveCleanupScheduled = true;
    scheduleMicrotask(() {
      _archiveCleanupScheduled = false;
      if (!_archiveCleanupRequested || _disposed) return;
      _archiveCleanupRequested = false;
      cleanup(retry: false).ignore();
    });
  }

  @override
  void seal() {
    if (_sealed) return;
    _sealed = true;
    for (final handle in [..._composers.values, ..._starts.values]) {
      handle.sealRecord();
    }
    lifetime.seal();
  }

  @override
  void requestClose() {
    try {
      _configurationWatch?.cancel();
      _configurationWatch = null;
      _watchIssue = null;
    } catch (error, stack) {
      remember(error, stack);
      _watchIssue = resourceCleanupIssue(error, CleanupRecovery.retryClose);
    }
  }

  @override
  Future<void> cleanup({required bool retry}) {
    if (_cleaning case final pending?) return pending;
    final done = Completer<void>();
    _cleaning = done.future;
    _archiveCleanupRequested = false;
    unawaited(
      Future<void>.sync(() async {
        requestClose();
        // Captures are independently registered in this same ResourceLifetime;
        // its close joins their true work. Do not put unrelated records behind
        // another capture's pending metadata/native decision.
        for (final capture in List.of(_archives)) {
          capture.cleanup(retry: retry).ignore();
        }
        ledger.requestClose();
        _disposeClosedRecords();
        await Future.wait([
          for (final work in List.of(_work)) work.cleanup(retry: retry),
          for (final start in _starts.values)
            for (final route in List.of(start._routeWork))
              route.then<void>(
                (_) {
                  _disposeClosedRecords();
                },
                onError: (Object _, StackTrace __) {
                  _disposeClosedRecords();
                },
              ),
          ledger.cleanup(retry: retry),
        ]);
        _archives.removeWhere((capture) => capture.released);
        ledger.requestClose();
        await ledger.cleanup(retry: retry);
        _disposeClosedRecords();
        if (_archives.isEmpty &&
            _watchIssue == null &&
            _disposeIssues.isEmpty &&
            [
              ..._composers.values,
              ..._starts.values,
            ].every((handle) => handle.disposed) &&
            ledger.released &&
            _work.isEmpty) {
          preferences.close();
          _permit.release();
          _disposed = true;
        }
      }).then<void>(
        (_) {
          _cleaning = null;
          done.complete();
          if (_archiveCleanupRequested) _scheduleArchiveCleanup();
        },
        onError: (Object error, StackTrace stack) {
          remember(error, stack);
          _cleaning = null;
          done.completeError(error, stack);
          if (_archiveCleanupRequested) _scheduleArchiveCleanup();
        },
      ),
    );
    return done.future;
  }

  @override
  List<FeedCloseIssue> get issues => [
    if (_watchIssue case final issue?) issue,
    ..._disposeIssues.values,
    if (!_disposed) resourcePendingIssue('draftOwnersRetained'),
  ];
  @override
  Future<CloseReport> close({DateTime? deadline}) {
    final joining = _currentJoin();
    // Repeated close shares the current join by identity, never a new wrapper
    // around the same work.
    if (deadline == null) return joining;
    // A deadline bounds this observation only: it never replaces, shortens or
    // cancels the original join, which stays the same Future above. Concurrent
    // bounded calls also share one observation instance.
    if (_boundedClosing case final pending? when !_boundedSettled)
      return pending;
    final started = _observeClose(joining, deadline);
    _boundedSettled = false;
    started
        .then(
          (_) => _boundedSettled = true,
          onError: (Object _, StackTrace __) => _boundedSettled = true,
        )
        .ignore();
    return _boundedClosing = started;
  }

  /// The close join this repository currently owes.
  ///
  /// A running join stays shared by identity, and so does one whose report
  /// already ended the whole responsibility. A join that settled incomplete is
  /// only shared while the lifetime still reports the responsibility it settled
  /// on: after a later explicit retry installed a newer one, this joins the
  /// newer responsibility instead of reporting the earlier incomplete snapshot
  /// again, and without asking the owners for another unresolved cleanup.
  Future<CloseReport> _currentJoin() {
    final cached = _closing;
    if (cached != null &&
        (!_joinSettled ||
            _joinComplete ||
            identical(_joined, lifetime.closing))) {
      return cached;
    }
    return _newJoin();
  }

  /// Publishes the one join Future, then runs the real join behind it.
  ///
  /// Sealing, owner cleanup and canonical notifications can all reenter this
  /// repository synchronously, so the identity must exist before any of them
  /// runs. Completion bookkeeping belongs to the current generation only: a
  /// later join must never be described by an older one's result.
  Future<CloseReport> _newJoin() {
    final done = Completer<CloseReport>();
    final generation = ++_joinGeneration;
    _joinSettled = false;
    _joinComplete = false;
    _joined = null;
    // 1. The one identity exists before anything can reenter close.
    _closing = done.future;
    // 2. Seal admission records before the join starts any cleanup.
    seal();
    // 3. Only now run the real join, whose startup still reenters safely.
    unawaited(
      _closeJoin().then<void>(
        (result) {
          if (generation == _joinGeneration) {
            _joinSettled = true;
            _joinComplete = result.report.complete;
            _joined = result.joined;
          }
          if (!done.isCompleted) done.complete(result.report);
        },
        onError: (Object error, StackTrace stack) {
          // A failed join never stands in for the next responsibility.
          if (generation == _joinGeneration) {
            _joinSettled = true;
            _joinComplete = false;
            _joined = null;
          }
          if (!done.isCompleted) done.completeError(error, stack);
        },
      ),
    );
    return done.future;
  }

  @override
  Future<CloseReport> retryCleanup({DateTime? deadline}) async {
    if (_sealed) {
      // The unique unbounded join stays the original responsibility. An explicit
      // retry is one additional pass over the same registered owners; it never
      // replaces that join and never degrades it to a bounded snapshot.
      _closing ??= _newJoin();
      final retried = _retryClose();
      if (deadline == null) return retried;
      return _observeClose(retried, deadline);
    }
    await _observeDraftWork(
      Future.wait([
        for (final capture in List.of(_archives)) capture.cleanup(retry: true),
        for (final work in List.of(_work)) work.cleanup(retry: true),
        ledger.cleanup(retry: true),
      ]).then<void>((_) {}),
      deadline,
    );
    for (final handle in [..._composers.values, ..._starts.values]) {
      refreshIssues(handle);
    }
    return _composeArchiveReport(lifetime.snapshotReport());
  }

  /// A capture's own unresolved owners (for example its original membership
  /// read) are part of this close responsibility, not a flattened issue list on
  /// the capture. Nested owners keep their identity; nothing is reported twice.
  CloseReport _composeArchiveReport(CloseReport report) {
    final owners = {for (final resource in report.unresolved) resource.owner};
    return CloseReport(
      unresolved: [
        ...report.unresolved,
        for (final capture in List.of(_archives))
          for (final resource in capture.report().unresolved)
            if (owners.add(resource.owner)) resource,
      ],
    );
  }

  /// One explicit retry pass over the same registered owners.
  Future<CloseReport> _retryClose() async =>
      _composeArchiveReport(await lifetime.close(retry: true));

  /// The one real close join. It is never bounded by a caller's deadline.
  ///
  /// A concurrent explicit retry installs a newer close responsibility in the
  /// same lifetime, so this join follows it instead of reporting the snapshot
  /// taken before that retry finished: the original work is joined to its real
  /// end, not to the first pass' result.
  Future<({CloseReport report, Future<void>? joined})> _closeJoin() async {
    Future<void>? followed;
    while (true) {
      final report = _composeArchiveReport(await lifetime.close());
      if (report.complete) return (report: report, joined: lifetime.closing);
      // This repository's own disposal covers only its records, ledger and
      // permit. Owners registered independently in the same lifetime — a
      // PinnedReadOwner behind an AttachmentBinaryReadOwner, for example — still
      // owe their own close, so disposal never ends this join early.
      final pending = lifetime.closing;
      if (pending == null || identical(pending, followed))
        return (report: report, joined: pending);
      followed = pending;
      await pending;
    }
  }

  Future<CloseReport> _observeClose(
    Future<CloseReport> joining,
    DateTime deadline,
  ) async {
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero)
      return _composeArchiveReport(lifetime.snapshotReport());
    try {
      return await joining.timeout(remaining);
    } on TimeoutException {
      return _composeArchiveReport(lifetime.snapshotReport());
    }
  }

  void remember(Object error, StackTrace stack) {
    lifetime.lastCause = error;
    lifetime.lastStack = stack;
  }
}

StudioFailure _draftFailure(StudioFailureCode code, String message) =>
    StudioFailure(
      code: code,
      message: message,
      retryable: code == StudioFailureCode.unavailable,
      correlationId: 'drafts',
    );

Future<void> _observeDraftWork(Future<void> work, DateTime? deadline) async {
  work.ignore();
  if (deadline == null) {
    await work;
    return;
  }
  final remaining = deadline.difference(DateTime.now());
  if (remaining <= Duration.zero) return;
  try {
    await work.timeout(remaining);
  } on TimeoutException {
    /* original owner retains work */
  }
}
