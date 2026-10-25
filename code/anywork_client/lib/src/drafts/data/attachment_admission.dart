part of 'attachment_ledger.dart';

/// One original admission identity, including an unknown reply. `joinOriginal`
/// accepts only a query/join of that call, never a replacement dispatch. Cleanup
/// never invokes either callback. Staging/path ownership stays with the factory.
final class AttachmentAdmission {
  AttachmentAdmission._(
    this._ledger,
    this.draft,
    this.operationId,
    List<AttachmentDraftSource> sources,
    this.stamp,
    this.generation,
    this.attempt,
  ) : _sources = sources,
      sourceCount = sources.length;

  final AttachmentLedger _ledger;
  final AttachmentDraftRecord draft;
  final OperationId operationId;
  List<AttachmentDraftSource>? _sources;
  final int sourceCount;

  /// Frozen inputs are retained only while their original outcome is unresolved.
  List<AttachmentDraftSource>? get sources => _sources;
  final DraftStamp stamp;
  final int generation;
  final int attempt;
  final List<_AttachmentPermitSlot> _slots = [];
  final Map<String, _AttachmentEntry> _known = {};
  Future<bool>? _joining;
  bool _started = false;
  bool _settled = false;
  bool _adoptAllowed = true;
  ({Object cause, StackTrace stack})? _failure;

  String get owner => 'attachment-admission:${operationId.value}:$attempt';
  bool get unresolved => !_settled;

  Future<bool> dispatch(Future<List<AttachmentMetadata>> Function() action) {
    // A reservation made before a resource fault does not authorize starting a
    // new native admission while that fault is still being cleaned.
    _ledger._admitAttachments();
    if (_started || _settled)
      throw resourceProtocol('An admission can dispatch only once.');
    _started = true;
    return _run(action);
  }

  /// Explicitly joins the SAME native operation. No new operation/input identity
  /// and no new attachment reservation. The native owner, not a timeout, supplies
  /// definitive evidence. This remains legal after seal for accepted work.
  Future<bool> joinOriginal(Future<List<AttachmentMetadata>> Function() join) {
    final joining = _joining;
    if (joining != null) return joining;
    if (!_started || _settled)
      throw resourceProtocol(
        'There is no unresolved original admission to join.',
      );
    return _run(join);
  }

  /// A factory can fail clipboard staging before dispatch. It must not use this
  /// once native admission started, even when the reply was lost.
  void abandonBeforeDispatch() {
    if (_started)
      throw resourceProtocol('A dispatched admission cannot be abandoned.');
    if (_settled) return;
    _settle();
    _ledger._pruneAdmission(this);
    for (final slot in _slots) {
      slot.handoff();
    }
  }

  Future<bool> _run(Future<List<AttachmentMetadata>> Function() action) {
    final done = Completer<bool>();
    _joining = done.future;
    // The original owner supervises errors even when the UI drops its ticket.
    done.future.ignore();
    unawaited(
      Future<bool>.sync(() async {
        final List<AttachmentMetadata> reply;
        try {
          reply = await action();
        } catch (error, stack) {
          _remember(error, stack);
          if (error is RejectedCommandDispatchFailure) {
            // Only actual pre-dispatch/rejection evidence can settle without IDs.
            // If a previous malformed reply exposed IDs, they still have owners.
            _settle();
            for (final slot in _slots) {
              slot.handoff();
            }
            try {
              await _ledger._deleteUnreferenced(_known.values);
            } catch (cleanupError, cleanupStack) {
              _ledger._remember(cleanupError, cleanupStack);
            }
          } else {
            for (final slot in _slots) {
              slot.markUnknown();
            }
          }
          Error.throwWithStackTrace(error, stack);
        }

        // No await between receiving the reply, registering EVERY known ID and
        // attaching the original reservation. Validation cannot orphan a suffix.
        final result = _receive(List<AttachmentMetadata>.unmodifiable(reply));
        Object? primary = result.error;
        StackTrace? primaryStack = primary == null ? null : StackTrace.current;
        try {
          await _ledger._deleteUnreferenced(_known.values);
        } catch (error, stack) {
          primary ??= error;
          primaryStack ??= stack;
        }
        if (primary != null) Error.throwWithStackTrace(primary, primaryStack!);
        return result.adopted;
      }).then<void>(
        (adopted) {
          _joining = null;
          _ledger._pruneAdmission(this);
          done.complete(adopted);
        },
        onError: (Object error, StackTrace stack) {
          _remember(error, stack);
          _joining = null;
          _ledger._pruneAdmission(this);
          done.completeError(error, stack);
        },
      ),
    );
    return done.future;
  }

  ({bool adopted, StudioFailure? error}) _receive(
    List<AttachmentMetadata> reply,
  ) {
    StudioFailure? invalid;
    void reject(String message) {
      invalid ??= resourceProtocol(message);
    }

    if (reply.length != sourceCount) {
      reject('The attachment admission returned a different source count.');
    }
    final ids = <String>{};
    final batch = <_AttachmentEntry>[];
    for (var index = 0; index < reply.length; index++) {
      final metadata = reply[index];
      if (metadata.id.isEmpty) {
        reject('The attachment admission returned an empty identity.');
        continue;
      }
      if (!ids.add(metadata.id))
        reject('The attachment admission returned a duplicate identity.');
      if (metadata.mediaType.isEmpty ||
          metadata.filename.isEmpty ||
          metadata.byteSize < 0 ||
          (metadata.width != null && metadata.width! < 0) ||
          (metadata.height != null && metadata.height! < 0)) {
        reject('The attachment admission returned invalid metadata.');
      }
      var entry = _known[metadata.id];
      if (entry == null) {
        final owned = _ledger._entries[metadata.id];
        if (owned != null) {
          reject('The attachment admission reused an already owned identity.');
          entry = owned;
        } else {
          entry = _AttachmentEntry(
            _ledger,
            metadata,
            _ledger._lifetime.nextAttempt(),
          );
          _ledger._entries[metadata.id] = entry;
        }
        _known[metadata.id] = entry;
      }
      // Inconsistency is an error, never a write to the previous metadata.
      if (entry.metadata != metadata)
        reject('The attachment identity has inconsistent metadata.');
      // A corrective join may confirm an ID already cleaned after this same
      // malformed reply. That is evidence only, not permission to delete it twice
      // or adopt it again. Other retiring IDs cannot be adopted.
      final alreadyCleanedByThisAdmission = !_adoptAllowed && entry.cleaned;
      if (entry.retiring && !alreadyCleanedByThisAdmission) {
        reject('The attachment identity is already retiring.');
      }
      entry.affectedDrafts.add(draft);
      entry.operations.add(operationId);
      entry.admissions.add(this);
      batch.add(entry);
      _coverEntry(entry);
    }

    var adopted = false;
    StudioFailure? adoptionFailure;
    try {
      if (invalid == null) {
        _settle();
        // Retain all previous known IDs too: a definitive join cannot erase
        // residual cleanup exposed by an earlier malformed reply.
        for (final slot in _slots) {
          slot.handoff();
        }
        if (_adoptAllowed && !_ledger._sealed && !_ledger._closing) {
          try {
            adopted = _ledger._adoptKnown(draft, reply, generation: generation);
          } catch (error, stack) {
            _remember(error, stack);
            adoptionFailure = resourceFailure(error);
          }
        }
      } else {
        _adoptAllowed = false;
        _remember(invalid!, StackTrace.current);
        // A malformed reply is not proof that unreported native objects do not
        // exist. Keep the original reservation/operation until a real join gives
        // complete evidence, even after all currently known IDs were deleted.
        for (final slot in _slots) {
          slot.markUnknown();
        }
      }
    } finally {
      for (final entry in batch) {
        entry.admissions.remove(this);
        entry.refreshPermits();
      }
    }
    return (adopted: adopted, error: invalid ?? adoptionFailure);
  }

  void _coverEntry(_AttachmentEntry entry) {
    // Existing/shared IDs, duplicates in one reply, and repeated original joins
    // refer to the same object. They do not need another permit or debt entry.
    if (entry.cleaned || entry.budgeted || entry.overflow != null) return;
    for (final reserved in _slots) {
      if (!reserved.available) continue;
      reserved.attach(entry);
      return;
    }
    final ResourcePermit permit;
    try {
      permit = _ledger._lifetime.budget.acquire(
        ResourceKind.attachment,
        owner: entry.owner,
        phase: ResourcePhase.retiring,
      );
    } catch (error, stack) {
      // The native object already exists. Record unique, explicitly unbudgeted
      // debt BEFORE any publication, native callback or permit release can reenter
      // admission. Continue registering the reply's remaining IDs after failure.
      entry.overflow = _AttachmentCleanupFailure(
        error,
        stack,
        resourceCleanupIssue(error, CleanupRecovery.awaitCompletion),
      );
      _ledger._overflow.add(entry);
      _ledger._remember(error, stack);
      return;
    }
    final slot = _AttachmentPermitSlot(permit);
    slot.attach(entry);
    // This extra permit belongs to this known ID, not an unknown source slot.
    // Its cleanup can release it without settling the original reservation.
    slot.handoff();
  }

  void _settle() {
    _settled = true;
    _sources = null;
  }

  List<FeedCloseIssue> get _issues {
    final error = _failure?.cause;
    return [
      error == null
          ? resourcePendingIssue(
              _started
                  ? 'attachmentAdmissionPending'
                  : 'attachmentAdmissionReserved',
            )
          : resourceCleanupIssue(
              _admissionFailure(error),
              CleanupRecovery.awaitCompletion,
            ),
    ];
  }

  void _remember(Object cause, StackTrace stack) {
    _failure ??= (cause: cause, stack: stack);
    _ledger._remember(cause, stack);
  }
}

StudioFailure _admissionFailure(Object error) => switch (error) {
  CommandDispatchFailure(:final failure) => failure,
  _ => resourceFailure(error),
};
