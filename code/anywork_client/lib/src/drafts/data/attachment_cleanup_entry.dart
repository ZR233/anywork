part of 'attachment_ledger.dart';

/// One permit backs at most one live ID. An original unknown reservation can
/// retain the permit after that ID is cleaned, but cannot cover a second live ID.
final class _AttachmentPermitSlot {
  _AttachmentPermitSlot(this.permit);
  final ResourcePermit permit;
  _AttachmentEntry? _entry;
  bool _reserved = true;
  bool _unknown = false;

  bool get available => _entry == null && !permit.isReleased;

  void attach(_AttachmentEntry entry) {
    if (permit.isReleased || (_entry != null && !identical(_entry, entry))) {
      throw StateError(
        'An attachment permit cannot back multiple live entries.',
      );
    }
    _entry = entry;
    entry.slots.add(this);
  }

  void handoff() {
    _reserved = false;
    _unknown = false;
    refresh();
  }

  void markUnknown() {
    _unknown = true;
    refresh();
  }

  void remove(_AttachmentEntry entry) {
    if (!identical(_entry, entry)) return;
    _entry = null;
    refresh();
  }

  void refresh() {
    if (permit.isReleased) return;
    final entry = _entry;
    if (!_reserved && entry == null) {
      permit.release();
      return;
    }
    final unresolved =
        _unknown ||
        entry != null &&
            (entry.failure != null ||
                entry.frozen.any((reference) => reference._unknown != null));
    permit.mark(
      unresolved
          ? ResourcePhase.unresolved
          : _reserved || entry != null && entry.admissions.isNotEmpty
          ? ResourcePhase.opening
          : entry != null && entry.referenced
          ? ResourcePhase.active
          : ResourcePhase.retiring,
    );
  }
}

/// Keeps the actual native deletion, original issue/cause and permits. A `false`
/// native result means there is no entry and is just as final as `true`.
final class _AttachmentEntry {
  _AttachmentEntry(this.ledger, this.metadata, this.attempt);
  final AttachmentLedger ledger;
  final AttachmentMetadata metadata;
  final int attempt;
  final Map<AttachmentDraftRecord, _DraftAttachmentReference> drafts =
      Map.identity();
  final Set<AttachmentDraftRecord> affectedDrafts = Set.identity();
  final Set<OperationId> operations = {};
  final Set<FrozenAttachmentReference> frozen = Set.identity();
  final Set<AttachmentAdmission> admissions = Set.identity();
  final Set<_AttachmentPermitSlot> slots = Set.identity();
  Future<void>? _deletion;
  bool deleting = false;
  bool cleaned = false;
  bool? _nativeResult;
  _AttachmentCleanupFailure? failure;
  _AttachmentCleanupFailure? _firstFailure;
  _AttachmentCleanupFailure? overflow;

  String get owner => 'attachment:${metadata.id}';
  bool get budgeted => slots.any((slot) => !slot.permit.isReleased);
  bool get referenced =>
      drafts.isNotEmpty ||
      frozen.isNotEmpty ||
      admissions.isNotEmpty ||
      ledger._retainsEntry(this);
  bool get retiring =>
      deleting ||
      cleaned ||
      failure != null ||
      overflow != null ||
      _nativeResult != null;

  void refreshPermits() {
    for (final slot in slots) {
      slot.refresh();
    }
  }

  Future<void> cleanup({required bool retry}) {
    final existing = _deletion;
    if (existing != null && (deleting || cleaned || !retry)) return existing;
    if (referenced) return Future<void>.value();
    final done = Completer<void>();
    _deletion = done.future;
    done.future.ignore();
    deleting = true;
    refreshPermits();
    // Publish the actual cleanup future before invoking ANY injected callback.
    unawaited(
      Future<void>.sync(() async {
        if (_nativeResult == null) {
          // The factory's original OperationRegistry owns command admission.
          // Cleanup retains these attachment permits, not a second command ticket.
          _nativeResult = await ledger._removeNative(metadata.id);
        }
        // Even a failure while releasing permits must never repeat a native
        // deletion that already ended successfully (including native false).
        for (final slot in List.of(slots)) {
          slot.remove(this);
          slots.remove(slot);
        }
        failure = null;
        cleaned = true;
        if (identical(ledger._entries[metadata.id], this))
          ledger._entries.remove(metadata.id);
        // Only actual native completion clears debt. Repeated replies or a freed
        // sibling permit cannot silently relabel this object as already budgeted.
        ledger._overflow.remove(this);
      }).then<void>(
        (_) {
          deleting = false;
          done.complete();
        },
        onError: (Object error, StackTrace stack) {
          final issue = _AttachmentCleanupFailure(
            error,
            stack,
            resourceCleanupIssue(error, CleanupRecovery.retryClose),
          );
          _firstFailure ??= issue;
          failure = issue;
          ledger._remember(error, stack);
          deleting = false;
          refreshPermits();
          done.completeError(error, stack);
        },
      ),
    );
    return done.future;
  }

  List<FeedCloseIssue> get issues => [
    if (overflow != null && !cleaned) overflow!.issue,
    if (_firstFailure != null && failure != null) _firstFailure!.issue,
    if (failure != null && !identical(_firstFailure, failure)) failure!.issue,
    if (deleting) resourcePendingIssue('attachmentDeletePending'),
    if (failure == null && !deleting)
      resourcePendingIssue(
        referenced
            ? 'attachmentReferencesRetained'
            : 'attachmentCleanupPending',
      ),
  ];
}

final class _AttachmentCleanupFailure {
  _AttachmentCleanupFailure(this.cause, this.stack, this.issue);
  final Object cause;
  final StackTrace stack;
  final FeedCloseIssue issue;
}
