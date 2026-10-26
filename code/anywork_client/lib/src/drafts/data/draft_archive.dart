part of 'drafts_repository.dart';

/// Pure membership is supervised by its accepted archive capture, not by the
/// repository's ordinary seal sweep or a newly activated Conversation Session.
final class _DraftMetadata implements ResourceOwner {
  _DraftMetadata(this.repo, this.threadId)
    : attempt = repo.lifetime.nextAttempt() {
    _value.future.ignore();
  }
  final _DraftsRepository repo;
  final String threadId;
  @override
  final int attempt;
  @override
  String get owner => 'draft-archive-metadata:$threadId';
  final Completer<WorkspaceThreadRecord> _value = Completer();
  ThreadMetadata? _reader;
  Observation? _watch;
  ProductReadOrigin? _origin;
  Future<void>? _reading;
  Future<void>? _opening;
  Future<void>? _cleaning;
  CloseReport? _report;
  FeedCloseIssue? _failure;
  bool _closing = false;
  bool _started = false;
  @override
  bool get released =>
      _closing &&
      _watch == null &&
      _opening == null &&
      _reading == null &&
      _failure == null &&
      (_reader == null || _report != null && _report!.unresolved.isEmpty);

  Future<WorkspaceThreadRecord> read() {
    if (_closing) return _value.future;
    if (!_started) {
      _started = true;
      final opening = Completer<void>();
      _opening = opening.future;
      try {
        // Capture reserved this exact preparation before repository seal. The
        // underlying Workspace reader still enforces its own real admission.
        final reader = _reader = repo.workspace.thread(threadId);
        if (reader.threadId != threadId)
          throw resourceProtocol(
            'The archive metadata handle changed its original Thread.',
          );
        final state = reader.state;
        _watch = state.watch(_consider);
        if (_closing)
          requestClose();
        else
          _consider(state.value);
        if (!_value.isCompleted) {
          final done = Completer<void>();
          _reading = done.future;
          unawaited(
            Future<void>.sync(reader.retry).then<void>(
              (_) {
                _reading = null;
                done.complete();
              },
              onError: (Object error, StackTrace stack) {
                repo.remember(error, stack);
                if (!_value.isCompleted) _value.completeError(error, stack);
                _reading = null;
                done.complete();
              },
            ),
          );
        }
      } catch (error, stack) {
        repo.remember(error, stack);
        if (!_value.isCompleted) _value.completeError(error, stack);
      } finally {
        _opening = null;
        opening.complete();
      }
    }
    return _value.future;
  }

  void _consider(ThreadMetadataState state) {
    if (_value.isCompleted) return;
    try {
      if (state.readError case final error?) throw error;
      if (state.projection.sync.error case final error?) throw error;
      if (state.projection.sync.phase == ResourceSyncPhase.failed) {
        throw resourceProtocol(
          'Failed archive metadata has no typed source error.',
        );
      }
      if (state.projection.sync.phase == ResourceSyncPhase.closed)
        throw resourceCancelled;
      final stamp = state.projection.stamp;
      if (stamp == null) return;
      if (_origin != null && _origin != stamp.origin)
        throw _draftFailure(
          StudioFailureCode.superseded,
          'The captured metadata source was replaced.',
        );
      _origin ??= stamp.origin;
      final value = state.value;
      if (value is FailedReadValue<WorkspaceThreadRecord, ProductEntityRef>)
        throw value.error;
      if (state.projection.sync.phase != ResourceSyncPhase.ready ||
          value is! ReadyReadValue<WorkspaceThreadRecord, ProductEntityRef>)
        return;
      if (value.current.origin != stamp.origin ||
          value.current.value.id != threadId) {
        throw resourceProtocol(
          'Archive metadata is not from its original Thread/source.',
        );
      }
      _value.complete(value.current.value);
    } catch (error, stack) {
      repo.remember(error, stack);
      _value.completeError(error, stack);
    }
  }

  @override
  void requestClose() {
    _closing = true;
    if (!_value.isCompleted) _value.completeError(resourceCancelled);
    try {
      _watch?.cancel();
      _watch = null;
      _reader?.requestClose();
    } catch (error, stack) {
      repo.remember(error, stack);
      _failure = resourceCleanupIssue(error, CleanupRecovery.retryClose);
    }
  }

  @override
  Future<void> cleanup({required bool retry}) {
    if (_cleaning case final pending?) return pending;
    if (released) return Future<void>.value();
    final done = Completer<void>();
    _cleaning = done.future;
    unawaited(
      Future<void>.sync(() async {
        requestClose();
        if (_opening case final opening?) await opening;
        requestClose(); // Also seals an original reader/watch handed back late.
        final reader = _reader;
        var closeFailed = false;
        try {
          if (reader != null)
            _report = await (retry ? reader.retryCleanup() : reader.close());
        } catch (error, stack) {
          closeFailed = true;
          repo.remember(error, stack);
          _failure = resourceCleanupIssue(error, CleanupRecovery.retryClose);
        }
        // A failed close observation does not abandon the actual read Future.
        if (_reading case final reading?) await reading;
        if (!closeFailed && _watch == null) _failure = null;
      }).then<void>(
        (_) {
          _cleaning = null;
          done.complete();
        },
        onError: (Object error, StackTrace stack) {
          repo.remember(error, stack);
          _failure = resourceCleanupIssue(error, CleanupRecovery.retryClose);
          _cleaning = null;
          done.complete();
        },
      ),
    );
    return done.future;
  }

  @override
  List<FeedCloseIssue> get issues => [
    if (_failure case final issue?) issue,
    if (_report case final report?)
      for (final resource in report.unresolved) ...resource.issues,
    if (!released &&
        _failure == null &&
        (_report == null || _report!.unresolved.isEmpty))
      resourcePendingIssue('draftMetadataPending'),
  ];
}

final class _DraftArchiveEntry {
  _DraftArchiveEntry(
    this.handle,
    this.references,
    this.work,
    this.metadata,
    List<Future<void>> preparing,
  ) : preparing = Set<Future<void>>.identity()..addAll(preparing) {
    for (final task in preparing) {
      unawaited(
        task.then<void>(
          (_) {
            this.preparing.remove(task);
          },
          onError: (Object _, StackTrace __) {
            this.preparing.remove(task);
          },
        ),
      );
    }
  }
  final _DraftHandle handle;
  final AttachmentDraftReferences references;
  final List<_DraftWork> work;
  final _DraftMetadata? metadata;
  final Set<Future<void>> preparing;
  WorkspaceThreadRecord? membership;
  Future<void>? membershipWork;
  bool membershipDone = false;
  StudioFailure? membershipError;
  bool releasingReferences = false;
  bool detached = false;

  /// The exact record identity this capture discarded. A later edit publishes a
  /// new stamp or attachment generation, so retirement can never clear it.
  DraftStamp? detachedStamp;
  int? detachedGeneration;
  bool referencesStarted = false;
  Future<void>? detaching;
  bool detachDone = false;
}

List<_DraftArchiveEntry> _archiveEntries(
  _DraftsRepository repo, {
  String? projectId,
}) => [
  for (final handle in [...repo._composers.values, ...repo._starts.values])
    if (!handle.disposed &&
        (handle is _Composer ||
            handle is _Start && handle.projectId == projectId))
      _DraftArchiveEntry(
        handle,
        repo.ledger.captureDraft(handle.record),
        List.unmodifiable(
          repo._work.where((work) => identical(work.handle, handle)),
        ),
        handle is _Composer ? _DraftMetadata(repo, handle.threadId) : null,
        handle is _Start ? List.of(handle._routeWork) : const [],
      ),
];

WorkspaceProjectArchiveCapture _captureProject(
  _DraftsRepository repo,
  String id,
  WorkspaceState frozen,
) {
  repo.ensureOpen();
  return _DraftProjectArchive(
    repo,
    id,
    frozen,
    _archiveEntries(repo, projectId: id),
  );
}

WorkspaceThreadArchiveCapture _captureThread(
  _DraftsRepository repo,
  String id,
  WorkspaceState frozen,
) {
  repo.ensureOpen();
  return _DraftThreadArchive(repo, id, frozen, _archiveEntries(repo));
}

abstract class _DraftArchive implements WorkspaceArchiveCapture, ResourceOwner {
  _DraftArchive(
    this.repo,
    this.id,
    this.frozen,
    List<_DraftArchiveEntry> entries,
  ) : entries = List.unmodifiable(entries),
      attempt = repo.lifetime.nextAttempt() {
    repo.lifetime.register(this);
    repo._archives.add(this);
  }
  final _DraftsRepository repo;
  final String id;
  final WorkspaceState frozen;
  final List<_DraftArchiveEntry> entries;
  @override
  final int attempt;
  @override
  String get owner => 'draft-archive:$id';
  Object? _original;
  Object? _confirmation;
  Future<void>? _preparing;
  bool _prepared = false;
  bool _prepareDone = false;
  bool _released = false;
  int _revision = 0;
  Future<void>? _cleaning;
  FeedCloseIssue? _cleanupFailure;
  DateTime? _deadline;
  List<_DraftArchiveEntry> _selected = const [];
  final Map<_DraftArchiveEntry, FeedCloseIssue> _failures = Map.identity();

  bool couldAffect(_DraftArchiveEntry entry);
  bool _retains(_DraftArchiveEntry entry) {
    if (_released) return false;
    if (_confirmation != null) {
      return _selected.contains(entry) &&
          (!entry.detachDone || _failures.containsKey(entry));
    }
    return couldAffect(entry);
  }

  bool retainsRecord(_DraftHandle handle) => entries.any(
    (entry) => identical(entry.handle, handle) && _retains(entry),
  );

  /// The exact records a *confirmed* archive really removed. A release without
  /// a native archive decision, a failed prepare and any failed detach keep their
  /// user draft and never appear here. A record edited after its detach also
  /// keeps its live draft, because only the discarded identity qualifies.
  Iterable<_DraftHandle> get retiredHandles sync* {
    if (_confirmation == null) return;
    for (final entry in _selected) {
      if (!entry.detachDone || !entry.detached || _failures.containsKey(entry))
        continue;
      final record = entry.handle.record;
      if (record.attachmentStamp != entry.detachedStamp ||
          record.attachmentGeneration != entry.detachedGeneration)
        continue;
      yield entry.handle;
    }
  }

  Iterable<AttachmentDraftReferences> get retainedDraftReferences => [
    for (final entry in entries)
      if (_retains(entry) && !entry.releasingReferences) entry.references,
  ];

  void validateMembership(WorkspaceThreadRecord value) {
    if (value.projectId.isEmpty)
      throw resourceProtocol(
        'Archive membership has no original Project identity.',
      );
  }

  Future<void> readMembership(_DraftArchiveEntry entry) {
    if (entry.membershipWork case final pending?) return pending;
    final done = Completer<void>();
    entry.membershipWork = done.future;
    done.future.ignore();
    unawaited(
      Future<void>.sync(() async {
        final value = await entry.metadata!.read();
        validateMembership(value);
        entry.membership = value;
      }).then<void>(
        (_) {
          entry.membershipDone = true;
          _revision++;
          done.complete();
          repo.archiveChanged(this);
        },
        onError: (Object error, StackTrace stack) {
          repo.remember(error, stack);
          entry.membershipError = resourceFailure(error);
          entry.membershipDone = true;
          _revision++;
          done.completeError(error, stack);
          repo.archiveChanged(this);
        },
      ),
    );
    return done.future;
  }

  Future<void> _cleanupMetadata(
    _DraftArchiveEntry entry, {
    required bool retry,
  }) async {
    if (entry.membershipWork case final work?) {
      await work.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    }
    await entry.metadata!.cleanup(retry: retry);
  }

  @override
  bool get released =>
      (_released || _confirmation != null) && report().complete;
  @override
  List<FeedCloseIssue> get issues => [
    for (final unresolved in report().unresolved) ...unresolved.issues,
  ];
  @override
  void requestClose() {
    // Repository admission is already sealed. This accepted capture must still
    // prepare and receive its original decision; seal is not a rejection proof.
  }

  void _releaseMetadata() {
    for (final entry in entries) {
      entry.metadata?.requestClose();
    }
  }

  Future<void> prepareOriginal(
    Object original,
    Future<void> Function() action,
  ) {
    if (_released ||
        _confirmation != null ||
        _original != null && _original != original)
      return Future.error(_archiveConflict);
    if (_preparing case final pending?) return pending;
    _original = original;
    final done = Completer<void>();
    _preparing = done.future;
    done.future.ignore();
    _revision++;
    repo.archiveChanged(this);
    unawaited(
      Future<void>.sync(action).then<void>(
        (_) {
          _prepareDone = true;
          _revision++;
          if (_released)
            done.completeError(resourceCancelled);
          else {
            _prepared = true;
            done.complete();
          }
          repo.archiveChanged(this);
        },
        onError: (Object error, StackTrace stack) {
          // A failed prepare cannot have dispatched archive. Cancel sibling value
          // waits, but retain/join their actual readers and late handoffs in cleanup.
          repo.remember(error, stack);
          _prepareDone = true;
          _released = true;
          _revision++;
          _releaseMetadata();
          done.completeError(error, stack);
          repo.archiveChanged(this);
          cleanup(retry: false).ignore();
        },
      ),
    );
    return done.future;
  }

  Future<CloseReport> confirm(
    Object result,
    bool Function(_DraftArchiveEntry) matches,
    DateTime? deadline,
  ) {
    if (_released ||
        !_prepared ||
        _confirmation != null && _confirmation != result)
      return Future.error(_archiveConflict);
    if (_confirmation == null) {
      _confirmation = result;
      _selected = List.unmodifiable(entries.where(matches));
      // Complete removed IDs are now authoritative. Pending classification is
      // no longer needed, but the original read/close work is still truly joined.
      _releaseMetadata();
      _revision++;
      repo.archiveChanged(this);
    }
    return observe(deadline, retry: false);
  }

  @override
  Future<CloseReport> releaseWithoutArchive({DateTime? deadline}) {
    if (_confirmation != null) return Future.error(_archiveConflict);
    if (!_released) {
      _released = true;
      _revision++;
      _releaseMetadata();
      repo.archiveChanged(this);
    }
    return observe(deadline, retry: false);
  }

  @override
  Future<CloseReport> retryCleanup({DateTime? deadline}) =>
      observe(deadline, retry: true);

  bool get _settled => _released || _confirmation != null;

  /// Work that becomes eligible only with the original archive decision or an
  /// explicit release. It owns no dependency on a sibling metadata/native close
  /// join, so a decision arriving while such a join is still pending starts this
  /// work immediately instead of waiting behind unrelated records.
  List<Future<void>> _settledWork({required bool retry}) => [
    if (_settled) ...[
      // Preserve detach-before-sibling-cleanup ordering and the original
      // stamp/generation/ref guards.
      for (final entry in _selected) _detach(entry, retry: retry),
      for (final entry in _selected)
        for (final work in entry.work)
          if (work.archiveCleanupEligible) work.cleanup(retry: retry),
      for (final entry in entries)
        for (final route in List.of(entry.preparing))
          route.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    ],
  ];

  void _startSettledWork({required bool retry}) {
    final work = _settledWork(retry: retry);
    if (work.isEmpty) return;
    Future.wait(work)
        .then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) {
            repo.remember(error, stack);
            _cleanupFailure = resourceCleanupIssue(
              error,
              CleanupRecovery.retryClose,
            );
          },
        )
        .ignore();
  }

  @override
  Future<void> cleanup({required bool retry}) {
    if (_cleaning case final pending?) {
      // The decision can arrive while an original metadata read or native close
      // is still pending. Join that work, but never hold the already eligible
      // detach/cleanup behind it.
      _startSettledWork(retry: retry);
      return pending;
    }
    if (released) return Future<void>.value();
    final done = Completer<void>();
    _cleaning = done.future;
    unawaited(
      Future<void>.sync(() async {
        var changed = true;
        var retryPass = retry;
        while (changed) {
          final revision = _revision;
          // Join only a real preparation already published by its caller. With
          // no prepare/decision yet, report the reservation instead of inventing
          // a permanently pending decision Future or closing unused metadata.
          if (_preparing case final preparing?) {
            await preparing.then<void>(
              (_) {},
              onError: (Object _, StackTrace __) {},
            );
          }
          await Future.wait([
            ..._settledWork(retry: retryPass),
            if (_prepareDone || _released)
              for (final entry in entries)
                if (entry.metadata != null)
                  _cleanupMetadata(entry, retry: retryPass),
          ]);
          changed = revision != _revision;
          retryPass = false;
        }
        _cleanupFailure = null;
      }).then<void>(
        (_) {
          _cleaning = null;
          done.complete();
          if (released) repo.archiveChanged(this);
        },
        onError: (Object error, StackTrace stack) {
          repo.remember(error, stack);
          _cleanupFailure = resourceCleanupIssue(
            error,
            CleanupRecovery.retryClose,
          );
          _cleaning = null;
          done.complete();
        },
      ),
    );
    return done.future;
  }

  Future<void> _detach(_DraftArchiveEntry entry, {required bool retry}) {
    final previous = entry.detaching;
    if (previous != null &&
        (!entry.detachDone || !retry || !_failures.containsKey(entry)))
      return previous;
    final done = Completer<void>();
    // Register before clearing canonical state can synchronously reenter this
    // capture, or metadata/cleanup callbacks can observe a transient Clean.
    entry.detaching = done.future;
    entry.detachDone = false;
    unawaited(
      Future<void>.sync(() async {
        try {
          // Release only this capture's borrow before canonical publication can
          // reenter. Another capture's same concrete references remain protected.
          entry.releasingReferences = true;
          if (!entry.detached &&
              !entry.handle.disposed &&
              entry.references.current) {
            entry.detached = entry.handle.discardCaptured(entry.references);
            if (entry.detached) {
              entry.detachedStamp = entry.handle.record.attachmentStamp;
              entry.detachedGeneration =
                  entry.handle.record.attachmentGeneration;
            }
          }
          if (entry.detached) {
            if (entry.referencesStarted && retry)
              await entry.references.retryCleanup();
            else {
              entry.referencesStarted = true;
              await entry.references.detach();
            }
          } else {
            // Another capture may have removed the original ref, or a newer edit
            // may still own it. Never detach a stale capture: join only deletable
            // original entries and leave every remaining canonical/frozen/borrow
            // owner intact. Wrapper Futures need not be shared; the entry is.
            await entry.references.joinCleanup(retry: retry);
          }
          _failures.remove(entry);
        } catch (error, stack) {
          repo.remember(error, stack);
          _failures[entry] = resourceCleanupIssue(
            error,
            CleanupRecovery.retryClose,
          );
        }
      }).then<void>(
        (_) {
          entry.detachDone = true;
          _revision++;
          done.complete();
          repo.archiveChanged(this);
        },
        onError: (Object error, StackTrace stack) {
          repo.remember(error, stack);
          _failures[entry] = resourceCleanupIssue(
            error,
            CleanupRecovery.retryClose,
          );
          entry.detachDone = true;
          _revision++;
          done.complete();
          repo.archiveChanged(this);
        },
      ),
    );
    return done.future;
  }

  Future<CloseReport> observe(DateTime? deadline, {required bool retry}) async {
    if (deadline != null &&
        (_deadline == null || deadline.isBefore(_deadline!)))
      _deadline = deadline;
    await _observeDraftWork(cleanup(retry: retry), _deadline);
    return report();
  }

  CloseReport report() => CloseReport(
    unresolved: [
      if (!_released && _confirmation == null)
        UnresolvedResource(
          owner: owner,
          attemptId: AttemptId(attempt),
          issues: [
            resourcePendingIssue(
              _preparing == null
                  ? 'draftArchiveAwaitingPreparation'
                  : 'draftArchiveAwaitingDecision',
            ),
          ],
        ),
      if (_cleaning != null)
        UnresolvedResource(
          owner: owner,
          attemptId: AttemptId(attempt),
          issues: [resourcePendingIssue('draftArchiveCleanupPending')],
        ),
      if (_cleanupFailure case final issue?)
        UnresolvedResource(
          owner: owner,
          attemptId: AttemptId(attempt),
          issues: [issue],
        ),
      if (_preparing != null && !_prepareDone)
        UnresolvedResource(
          owner: 'draft-archive:$id',
          attemptId: AttemptId(attempt),
          issues: [resourcePendingIssue('draftArchivePreparePending')],
        ),
      for (final entry in entries)
        if (entry.metadata != null && !entry.metadata!.released)
          UnresolvedResource(
            owner: entry.metadata!.owner,
            attemptId: AttemptId(entry.metadata!.attempt),
            issues: entry.metadata!.issues,
          ),
      for (final entry in entries)
        if (entry.membershipWork != null && !entry.membershipDone)
          UnresolvedResource(
            owner: 'draft-archive-membership:$id',
            attemptId: AttemptId(attempt),
            issues: [resourcePendingIssue('capturedMembershipReadPending')],
          ),
      if (!_released && _confirmation == null)
        for (final entry in entries)
          if (entry.membershipError case final error?)
            UnresolvedResource(
              owner: 'draft-archive-membership:$id',
              attemptId: AttemptId(attempt),
              issues: [
                resourceCleanupIssue(error, CleanupRecovery.awaitCompletion),
              ],
            ),
      for (final entry in entries)
        if (entry.preparing.isNotEmpty)
          UnresolvedResource(
            owner: 'draft-archive-route:$id',
            attemptId: AttemptId(attempt),
            issues: [resourcePendingIssue('capturedRouteReadPending')],
          ),
      for (final entry in _selected) ...[
        if (!entry.detachDone)
          UnresolvedResource(
            owner: 'draft-archive:$id',
            attemptId: AttemptId(attempt),
            issues: [resourcePendingIssue('capturedDraftDetachPending')],
          ),
        if (_failures[entry] case final issue?)
          UnresolvedResource(
            owner: 'draft-archive:$id',
            attemptId: AttemptId(attempt),
            issues: [issue],
          ),
        for (final work in entry.work)
          if (work.archiveCleanupEligible && !work.released)
            UnresolvedResource(
              owner: work.owner,
              attemptId: AttemptId(work.attempt),
              issues: work.issues.isEmpty
                  ? [resourcePendingIssue('capturedDraftWorkPending')]
                  : work.issues,
            ),
      ],
    ],
  );
}

final class _DraftProjectArchive extends _DraftArchive
    implements WorkspaceProjectArchiveCapture {
  _DraftProjectArchive(super.repo, super.id, super.frozen, super.entries);
  @override
  bool couldAffect(_DraftArchiveEntry entry) =>
      entry.handle is _Start ||
      entry.membership == null ||
      entry.membership!.projectId == id;
  @override
  Future<void> prepare(ProjectRecord originalProject) =>
      prepareOriginal(originalProject, () async {
        if (originalProject.id != id) throw _archiveConflict;
        await Future.wait([
          for (final entry in entries)
            if (entry.metadata != null) readMembership(entry),
        ], eagerError: true);
      });
  @override
  Future<CloseReport> afterArchived(
    ProjectRecord archivedProject, {
    DateTime? deadline,
  }) {
    if (archivedProject.id != id) return Future.error(_archiveConflict);
    return confirm(
      archivedProject,
      (entry) => entry.handle is _Start
          ? (entry.handle as _Start).projectId == id
          : entry.membership?.projectId == id,
      deadline,
    );
  }
}

final class _DraftThreadArchive extends _DraftArchive
    implements WorkspaceThreadArchiveCapture {
  _DraftThreadArchive(super.repo, super.id, super.frozen, super.entries);
  @override
  bool couldAffect(_DraftArchiveEntry entry) =>
      entry.handle is _Composer &&
      ((entry.handle as _Composer).threadId == id ||
          entry.membership == null ||
          entry.membership!.rootThreadId == id);
  @override
  void validateMembership(WorkspaceThreadRecord value) {
    super.validateMembership(value);
    if (value.rootThreadId.isEmpty ||
        value.isRoot && value.rootThreadId != value.id) {
      throw resourceProtocol(
        'Archive membership has no valid original root identity.',
      );
    }
  }

  @override
  Future<void> prepare(
    WorkspaceThreadRecord originalRoot,
  ) => prepareOriginal(originalRoot, () async {
    if (originalRoot.id != id || !originalRoot.isRoot) throw _archiveConflict;
    for (final entry in entries) {
      if ((entry.handle as _Composer).threadId == id) {
        entry.membership = originalRoot;
        entry.metadata!
            .requestClose(); // Reserved but no extra root read needed.
      } else {
        // Classification is a pure original-owner read, not a new precondition
        // for Thread archive. Unknown/failure retains the candidate; only real
        // outside-root evidence releases it before complete native removed IDs.
        readMembership(entry).ignore();
      }
    }
  });
  @override
  Future<CloseReport> afterArchived(
    ArchiveThreadResult result, {
    DateTime? deadline,
  }) {
    if (result.archivedRootId != id || !result.removedThreadIds.contains(id))
      return Future.error(_archiveConflict);
    return confirm(
      result,
      (entry) =>
          entry.handle is _Composer &&
          result.removedThreadIds.contains(
            (entry.handle as _Composer).threadId,
          ),
      deadline,
    );
  }
}

const _archiveConflict = StudioFailure(
  code: StudioFailureCode.conflict,
  message: 'The original draft archive capture or confirmation does not match.',
  retryable: false,
  correlationId: 'drafts-archive',
);
