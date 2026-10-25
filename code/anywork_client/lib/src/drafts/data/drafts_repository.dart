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
  DateTime? _deadline;
  Future<void>? _cleaning;
  Future<CloseReport>? _closing;
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
    final context = handle is _Composer
        ? AttachmentAdmissionContext.existingThread(handle.threadId)
        : AttachmentAdmissionContext.newThread(
            (handle as _Start).record.state.value.mode,
          );
    _admitting = true;
    late final OperationWriter<Unit> writer;
    try {
      writer = begin<Unit>(handle, 'attachment');
    } finally {
      _admitting = false;
    }
    _AttachmentWork? work;
    try {
      work = _AttachmentWork(
        this,
        handle,
        writer,
        context,
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
    // Repeated close exposes the original close responsibility: callers observe
    // the same Future instead of a new wrapper around the same underlying work.
    if (_closing case final first?) return first;
    _boundDeadline(deadline);
    seal();
    return _closing ??= lifetime.close(deadline: _deadline);
  }

  @override
  Future<CloseReport> retryCleanup({DateTime? deadline}) async {
    if (_sealed) {
      _boundDeadline(deadline);
      // A retry is a new observation of the same close responsibility, so it
      // becomes the close Future later repeated close callers share.
      return _closing = lifetime.close(deadline: _deadline, retry: true);
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
    return lifetime.snapshotReport();
  }

  void _boundDeadline(DateTime? next) {
    if (next != null && (_deadline == null || next.isBefore(_deadline!)))
      _deadline = next;
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
