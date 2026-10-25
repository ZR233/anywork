import 'dart:async';

import '../../../resources_ports.dart';
import '../../operations/data/command_dispatch_failure.dart';
import '../domain/draft_values.dart';
import 'attachment_draft_record.dart';

part 'attachment_admission.dart';
part 'attachment_cleanup_entry.dart';

/// Repository-private ownership, not another canonical draft store. Register
/// once, before any admission: late handoffs remain inside this original owner
/// even after the shared lifetime has sealed admission.
final class AttachmentLedger implements ResourceOwner {
  AttachmentLedger({
    required ResourceLifetime lifetime,
    required Future<bool> Function(String draftId) removeNative,
    Iterable<AttachmentDraftReferences> Function()? retainedDraftReferences,
  }) : _lifetime = lifetime,
       _removeNative = removeNative,
       _retainedDraftReferences = retainedDraftReferences,
       attempt = lifetime.nextAttempt() {
    lifetime.register(this);
  }

  final ResourceLifetime _lifetime;
  final Future<bool> Function(String draftId) _removeNative;
  final Iterable<AttachmentDraftReferences> Function()?
  _retainedDraftReferences;
  @override
  final int attempt;
  @override
  String get owner => 'draft-attachments';
  final Map<String, _AttachmentEntry> _entries = {};
  final Map<OperationId, AttachmentAdmission> _admissions = {};
  final Map<OperationId, FrozenAttachmentReference> _frozen = {};
  final Set<_AttachmentEntry> _overflow = Set.identity();
  bool _sealed = false;
  bool _closing = false;
  DateTime? _deadline;
  Future<void>? _cleaning;
  _AttachmentCleanupFailure? _coordinationFailure;

  @override
  bool get released =>
      _sealed &&
      _entries.isEmpty &&
      _admissions.isEmpty &&
      _frozen.isEmpty &&
      _overflow.isEmpty &&
      _cleaning == null &&
      _coordinationFailure == null;

  int get overflowCount => _overflow.length;
  List<String> get overflowAttachmentIds =>
      List.unmodifiable([for (final entry in _overflow) entry.metadata.id]);

  void _admit() {
    _lifetime.admit();
    if (_sealed) throw resourceCancelled;
  }

  void _admitAttachments() {
    _admit();
    if (_overflow.isNotEmpty) throw _overflowFailure;
  }

  StudioFailure get _overflowFailure => StudioFailure(
    code: StudioFailureCode.overloaded,
    message:
        'Attachment admission is blocked by $overflowCount unbudgeted attachment entries.',
    retryable: true,
    correlationId: 'draft-attachments:overflow',
    details: StudioFailureDetails.resourceLimit(
      resource: ResourceKind.attachment.name,
      capacity: _lifetime.budget.capacities[ResourceKind.attachment] ?? 0,
    ),
  );

  /// Reserves the whole source count synchronously, before admission dispatch
  /// may await. Failure here is known pre-dispatch and rolls back only these permits.
  /// Clipboard may supply its original pre-staging capture after the actual
  /// source path becomes available; it cannot adopt into a later generation.
  AttachmentAdmission reserveAdmission({
    required AttachmentDraftRecord draft,
    required OperationId operationId,
    required List<AttachmentDraftSource> sources,
    DraftStamp? expectedStamp,
    int? expectedGeneration,
  }) {
    _admitAttachments();
    if (_admissions.containsKey(operationId)) {
      throw resourceProtocol(
        'This operation already has an attachment admission.',
      );
    }
    final snapshot = List<AttachmentDraftSource>.unmodifiable(sources);
    if (snapshot.isEmpty)
      throw const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'Attachment sources cannot be empty.',
        retryable: false,
        correlationId: 'attachment-admission',
      );
    final admission = AttachmentAdmission._(
      this,
      draft,
      operationId,
      snapshot,
      expectedStamp ?? draft.attachmentStamp,
      expectedGeneration ?? draft.attachmentGeneration,
      _lifetime.nextAttempt(),
    );
    _admissions[operationId] = admission;
    try {
      for (var index = 0; index < snapshot.length; index++) {
        admission._slots.add(
          _AttachmentPermitSlot(
            _lifetime.budget.acquire(
              ResourceKind.attachment,
              owner: '${admission.owner}:$index',
              phase: ResourcePhase.opening,
            ),
          ),
        );
      }
    } catch (error, stack) {
      // No external callback has been invoked. Publish the rollback before a
      // permit release can synchronously notify another budget borrower.
      _admissions.remove(operationId);
      admission._settle();
      for (final slot in admission._slots) {
        slot.handoff();
      }
      Error.throwWithStackTrace(resourceFailure(error), stack);
    }
    return admission;
  }

  /// Share already-owned metadata with a concrete draft. New IDs can enter only
  /// through a reservation. References exist before the record publishes/reenters.
  bool adoptKnown(
    AttachmentDraftRecord draft,
    List<AttachmentMetadata> metadata, {
    required int generation,
  }) {
    _admitAttachments();
    return _adoptKnown(draft, metadata, generation: generation);
  }

  // Already-reserved native work may finish while another batch has overflow.
  // This does not admit an external reference or obtain new attachment capacity.
  bool _adoptKnown(
    AttachmentDraftRecord draft,
    List<AttachmentMetadata> metadata, {
    required int generation,
  }) {
    _admit();
    final snapshot = List<AttachmentMetadata>.unmodifiable(metadata);
    final entries = <_AttachmentEntry>[];
    final ids = <String>{};
    for (final item in snapshot) {
      final entry = _entries[item.id];
      if (!ids.add(item.id) ||
          entry == null ||
          entry.metadata != item ||
          !entry.budgeted ||
          entry.retiring) {
        throw resourceProtocol(
          'A draft can adopt only matching, owned attachment metadata.',
        );
      }
      entries.add(entry);
    }
    final previous =
        Map<_AttachmentEntry, _DraftAttachmentReference?>.identity();
    final claimed = <_DraftAttachmentReference>[];
    for (final entry in entries) {
      entry.affectedDrafts.add(draft);
      previous[entry] = entry.drafts[draft];
      final reference = _DraftAttachmentReference(entry);
      claimed.add(reference);
      entry.drafts[draft] = reference;
    }
    var adopted = false;
    try {
      adopted = draft.adoptAttachments(snapshot, generation: generation);
      return adopted;
    } finally {
      if (!adopted) {
        for (final reference in claimed) {
          final entry = reference.entry;
          if (!identical(entry.drafts[draft], reference)) continue;
          final old = previous[entry];
          if (old == null)
            entry.drafts.remove(draft);
          else
            entry.drafts[draft] = old;
        }
      }
      for (final entry in entries) {
        entry.refreshPermits();
      }
    }
  }

  /// Capture before beginSubmission publishes or any presentation/dispatch await.
  /// No lookup by a reconstructed draft ID, and no second attachment list writer.
  FrozenAttachmentReference freeze(
    AttachmentDraftRecord draft, {
    required DraftStamp expectedStamp,
    required OperationId operationId,
  }) {
    _admit();
    if (_frozen.containsKey(operationId) ||
        draft.attachmentStamp != expectedStamp) {
      throw resourceProtocol(
        'The frozen operation or concrete draft stamp does not match.',
      );
    }
    final metadata = List<AttachmentMetadata>.unmodifiable(
      draft.attachmentMetadata,
    );
    final entries = <_AttachmentEntry>[];
    final ids = <String>{};
    for (final item in metadata) {
      final entry = _entries[item.id];
      if (!ids.add(item.id) ||
          entry == null ||
          entry.metadata != item ||
          !entry.drafts.containsKey(draft) ||
          entry.retiring) {
        throw resourceProtocol(
          'The frozen draft does not own this exact attachment.',
        );
      }
      entries.add(entry);
    }
    final draftReferences = AttachmentDraftReferences._(
      draft,
      expectedStamp,
      draft.attachmentGeneration,
      List.unmodifiable([for (final entry in entries) entry.drafts[draft]!]),
    );
    final reference = FrozenAttachmentReference._(
      this,
      draftReferences,
      operationId,
      List<_AttachmentEntry>.unmodifiable(entries),
      _lifetime.nextAttempt(),
    );
    _frozen[operationId] = reference;
    for (final entry in entries) {
      entry.frozen.add(reference);
    }
    return reference;
  }

  /// Capture BEFORE publishing remove/discard/acknowledged canonical state.
  /// A reentrant adoption on this same record installs a different reference;
  /// detaching this capture can never remove that newer reference by ID alone.
  AttachmentDraftReferences captureDraft(
    AttachmentDraftRecord draft, {
    List<String>? attachmentIds,
  }) {
    final ids = attachmentIds == null ? null : Set<String>.of(attachmentIds);
    return AttachmentDraftReferences._(
      draft,
      draft.attachmentStamp,
      draft.attachmentGeneration,
      List.unmodifiable([
        for (final ownedEntry in _entries.values)
          if (ids == null || ids.contains(ownedEntry.metadata.id))
            if (ownedEntry.drafts[draft] case final reference?) reference,
      ]),
    );
  }

  /// Diagnostics are snapshots. Removed canonical attachments can still have
  /// cleanup issues, associated with the original record and operation.
  List<AttachmentCleanupIssue> cleanupIssuesFor(AttachmentDraftRecord draft) =>
      List.unmodifiable([
        for (final entry in _entries.values)
          if (entry.affectedDrafts.contains(draft) &&
              (entry.failure != null || entry.overflow != null))
            AttachmentCleanupIssue(
              attachmentDraftId: entry.metadata.id,
              error: resourceFailure((entry.failure ?? entry.overflow)!.cause),
            ),
      ]);

  List<AttachmentCleanupIssue> cleanupIssuesForOperation(
    OperationId operationId,
  ) => List.unmodifiable([
    for (final entry in _entries.values)
      if (entry.operations.contains(operationId) &&
          (entry.failure != null || entry.overflow != null))
        AttachmentCleanupIssue(
          attachmentDraftId: entry.metadata.id,
          error: resourceFailure((entry.failure ?? entry.overflow)!.cause),
        ),
  ]);

  /// Retry only this original operation's known objects, never a later draft's
  /// references, an unrelated failed entry or the original business admission.
  Future<void> retryOperationCleanup(OperationId operationId) =>
      Future.wait<void>([
        for (final entry in List<_AttachmentEntry>.of(_entries.values))
          if (entry.operations.contains(operationId) && !entry.referenced)
            entry.cleanup(retry: true),
      ]).then<void>((_) {});

  Future<void> _deleteUnreferenced(Iterable<_AttachmentEntry> entries) async {
    // Start every independent deletion even if a sibling fails. Each start
    // publishes its Future before invoking native or budget-release callbacks.
    final work = <Future<void>>[
      for (final entry in List<_AttachmentEntry>.of(entries))
        if (!entry.referenced) entry.cleanup(retry: false),
    ];
    await Future.wait(work);
  }

  void seal() {
    _sealed = true;
  }

  Set<_DraftAttachmentReference> _captureReferences() =>
      Set<_DraftAttachmentReference>.identity()..addAll([
        for (final captured
            in _retainedDraftReferences?.call() ??
                const <AttachmentDraftReferences>[])
          ...captured._references,
      ]);

  // Captures borrow the original concrete draft references, including one that
  // another overlapping capture already detached from the editable record.
  bool _retainsEntry(_AttachmentEntry entry) => _captureReferences().any(
    (reference) => identical(reference.entry, entry),
  );

  bool hasDraftReferences(AttachmentDraftRecord draft) =>
      _entries.values.any((entry) => entry.drafts.containsKey(draft));

  @override
  void requestClose() {
    seal();
    _closing = true;
    final retained = _captureReferences();
    for (final entry in _entries.values) {
      // Repeated close sweeps can release newly proven unrelated references.
      // The union is by reference identity, never a global capture-count gate.
      entry.drafts.removeWhere((_, reference) => !retained.contains(reference));
      entry.refreshPermits();
    }
    for (final admission in List.of(_admissions.values)) {
      if (!admission._started) admission.abandonBeforeDispatch();
    }
    // Frozen operations (pending or Unknown) and admissions retain their refs.
  }

  @override
  Future<void> cleanup({required bool retry}) {
    final existing = _cleaning;
    if (existing != null) {
      // A classification/decision can release more original references while
      // a sibling delete is still pending. Start those independent deletes now.
      _deleteUnreferenced(_entries.values).ignore();
      return existing;
    }
    final done = Completer<void>();
    _cleaning = done.future;
    final retriable = Set<_AttachmentEntry>.identity();
    if (retry) {
      retriable.addAll(_entries.values.where((entry) => entry.failure != null));
    }
    unawaited(
      Future<void>.sync(() => _drain(retriable)).then<void>(
        (_) {
          _coordinationFailure = null;
          _cleaning = null;
          done.complete();
        },
        onError: (Object error, StackTrace stack) {
          // Individual failures are kept by the entry. An unexpected coordinator
          // failure is not cached forever; the original lifetime retains its cause.
          _remember(error, stack);
          _coordinationFailure = _AttachmentCleanupFailure(
            error,
            stack,
            resourceCleanupIssue(error, CleanupRecovery.retryClose),
          );
          _cleaning = null;
          done.completeError(error, stack);
        },
      ),
    );
    return done.future;
  }

  Future<void> _drain(Set<_AttachmentEntry> retriable) async {
    while (true) {
      final work = <Future<void>>[];
      for (final admission in List.of(_admissions.values)) {
        final joining = admission._joining;
        if (joining != null)
          work.add(
            joining.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
          );
      }
      for (final entry in List.of(_entries.values)) {
        if (entry.referenced) continue;
        final retry = retriable.remove(entry);
        if (entry.deleting || entry.failure == null || retry) {
          work.add(
            entry
                .cleanup(retry: retry)
                .then<void>((_) {}, onError: (Object _, StackTrace __) {}),
          );
        }
      }
      if (work.isEmpty) return;
      await Future.wait(work);
      // Re-scan actual owners: a late original admission can have registered
      // additional IDs/deletes while the first snapshot was being joined.
    }
  }

  Future<CloseReport> close({DateTime? deadline}) {
    // Freeze the bound before requestClose can release undispatched permits and
    // synchronously reenter close through a budget availability observer.
    _boundDeadline(deadline);
    requestClose();
    return _observe(deadline: _deadline, retry: false);
  }

  /// This may be used while still open; it does not discard live drafts, seal
  /// them, query an admission, or retry any submit command.
  Future<CloseReport> retryCleanup({DateTime? deadline}) {
    if (_closing) _boundDeadline(deadline);
    return _observe(deadline: _closing ? _deadline : deadline, retry: true);
  }

  void _boundDeadline(DateTime? deadline) {
    if (deadline != null &&
        (_deadline == null || deadline.isBefore(_deadline!))) {
      _deadline = deadline;
    }
  }

  Future<CloseReport> _observe({
    DateTime? deadline,
    required bool retry,
  }) async {
    final work = cleanup(retry: retry);
    try {
      final remainingUntilDeadline = deadline?.difference(DateTime.now());
      if (remainingUntilDeadline == null)
        await work;
      else if (remainingUntilDeadline <= Duration.zero)
        work.ignore();
      else
        await work.timeout(remainingUntilDeadline);
    } on TimeoutException {
      // Observation ended, not the registered delete/admission or its permit.
    } catch (error, stack) {
      // cleanup has already retained the exact cause and typed report issue.
      _remember(error, stack);
    }
    return report();
  }

  CloseReport report() => CloseReport(
    unresolved: [
      if (_overflow.isNotEmpty)
        UnresolvedResource(
          owner: 'draft-attachments:overflow',
          attemptId: AttemptId(attempt),
          issues: [
            resourceCleanupIssue(
              _overflowFailure,
              CleanupRecovery.awaitCompletion,
            ),
          ],
        ),
      if (_coordinationFailure case final failure?)
        UnresolvedResource(
          owner: 'draft-attachments:cleanup',
          attemptId: AttemptId(attempt),
          issues: [failure.issue],
        ),
      for (final admission in _admissions.values)
        UnresolvedResource(
          owner: admission.owner,
          attemptId: AttemptId(admission.attempt),
          issues: admission._issues,
        ),
      for (final reference in _frozen.values)
        UnresolvedResource(
          owner: reference.owner,
          attemptId: AttemptId(reference.attempt),
          issues: [reference._issue],
        ),
      for (final entry in _entries.values)
        UnresolvedResource(
          owner: entry.owner,
          attemptId: AttemptId(entry.attempt),
          issues: entry.issues,
        ),
    ],
  );

  @override
  List<FeedCloseIssue> get issues => List.unmodifiable([
    for (final unresolved in report().unresolved) ...[
      // The shared lifetime has one registered ledger. Keep exact child owner
      // identity visible there too, without replacing its original typed issues.
      FeedCloseIssue(
        diagnostic: StudioShutdownIssue(
          stage: 'draft-attachments',
          code: 'attachmentOwnerRetained',
          message: 'An attachment responsibility is still retained.',
          retryable: true,
          correlationId: unresolved.owner,
        ),
        recovery: CleanupRecovery.awaitCompletion,
      ),
      ...unresolved.issues,
    ],
  ]);

  void _pruneAdmission(AttachmentAdmission admission) {
    if (admission._settled &&
        admission._joining == null &&
        identical(_admissions[admission.operationId], admission)) {
      _admissions.remove(admission.operationId);
    }
  }

  void _remember(Object cause, StackTrace stack) {
    _lifetime.lastCause = cause;
    _lifetime.lastStack = stack;
  }
}

/// Permission to release only the captured draft-side references, not an extra
/// attachment owner. It stores no canonical text/metadata and cannot clear a
/// record. Archive callers must also check their original record/stamp/generation
/// before clearing; ordinary remove/discard detach after their own publication.
final class AttachmentDraftReferences {
  AttachmentDraftReferences._(
    this.draft,
    this.stamp,
    this.generation,
    this._references,
  );
  final AttachmentDraftRecord draft;
  final DraftStamp stamp;
  final int generation;
  final List<_DraftAttachmentReference> _references;
  Future<void>? _detaching;

  bool get current =>
      draft.attachmentStamp == stamp &&
      draft.attachmentGeneration == generation;

  List<FeedCloseIssue> get cleanupIssues => List.unmodifiable([
    for (final entry in _references.map((reference) => reference.entry).toSet())
      if (!entry.cleaned && !entry.referenced) ...entry.issues,
  ]);

  /// Join only this capture's original entries without subtracting draft refs.
  /// A newer canonical ref, frozen operation or another capture remains a real
  /// owner; otherwise cleanup starts/joins the entry's one actual deletion.
  Future<void> joinCleanup({required bool retry}) async {
    await Future.wait([
      for (final entry
          in _references.map((reference) => reference.entry).toSet())
        if (!entry.referenced) entry.cleanup(retry: retry),
    ]);
  }

  /// Only retry deletes from this capture's previous detach. Never subtract a
  /// newer draft reference or sweep unrelated ledger entries.
  Future<void> retryCleanup() async {
    if (_detaching == null) return;
    await joinCleanup(retry: true);
  }

  Future<void> detach() {
    final existing = _detaching;
    if (existing != null) return existing;
    final done = Completer<void>();
    _detaching = done.future;
    done.future.ignore();
    for (final reference in _references) {
      final entry = reference.entry;
      if (!identical(entry.drafts[draft], reference)) continue;
      entry.drafts.remove(draft);
      entry.refreshPermits();
    }
    // A close sweep may have removed this same captured reference reentrantly.
    // Join its actual entries too; newer/overlapping references still protect ID.
    unawaited(
      joinCleanup(retry: false).then<void>(
        (_) => done.complete(),
        onError: (Object error, StackTrace stack) =>
            done.completeError(error, stack),
      ),
    );
    return done.future;
  }
}

final class _DraftAttachmentReference {
  _DraftAttachmentReference(this.entry);
  final _AttachmentEntry entry;
}

/// A frozen reference to entries, not a copied editable draft. Success and
/// rejection both release only this operation; stamp-guarded canonical clearing
/// and its draft-side detach remain the original record/repository's duty.
final class FrozenAttachmentReference {
  FrozenAttachmentReference._(
    this._ledger,
    this.draftReferences,
    this.operationId,
    this._entries,
    this.attempt,
  );
  final AttachmentLedger _ledger;
  final AttachmentDraftReferences draftReferences;
  AttachmentDraftRecord get draft => draftReferences.draft;
  DraftStamp get stamp => draftReferences.stamp;
  final OperationId operationId;
  final List<_AttachmentEntry> _entries;
  final int attempt;
  StudioFailure? _unknown;
  Future<void>? _completion;
  String get owner => 'attachment-submission:${operationId.value}';
  List<String> get attachmentIds =>
      List.unmodifiable([for (final entry in _entries) entry.metadata.id]);

  void unknown(StudioFailure error) {
    if (_completion != null) return;
    _unknown ??= error;
    for (final entry in _entries) {
      entry.refreshPermits();
    }
  }

  FeedCloseIssue get _issue => _unknown == null
      ? resourcePendingIssue('attachmentSubmissionPending')
      : resourceCleanupIssue(_unknown!, CleanupRecovery.awaitCompletion);

  Future<void> acknowledged() => _complete();
  Future<void> rejected() => _complete();

  Future<void> _complete() {
    final existing = _completion;
    if (existing != null) return existing;
    final done = Completer<void>();
    _completion = done.future;
    done.future.ignore();
    _ledger._frozen.remove(operationId);
    for (final entry in _entries) {
      entry.frozen.remove(this);
      // This operation retains cleanup diagnostics only if releasing its last
      // reference actually starts deletion, not for every past use of an ID.
      if (!entry.referenced) entry.operations.add(operationId);
      entry.refreshPermits();
    }
    unawaited(
      _ledger
          ._deleteUnreferenced(_entries)
          .then<void>(
            (_) => done.complete(),
            onError: (Object error, StackTrace stack) =>
                done.completeError(error, stack),
          ),
    );
    return done.future;
  }
}
