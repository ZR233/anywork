import '../../../resources.dart';
import '../domain/draft_values.dart';

/// Composition-only command capability. begin registers the original identity
/// before native side effects; find only locates that call and never dispatches.
/// A missing lookup is not evidence that the original call was rejected.
abstract interface class AttachmentAdmissionPort {
  Future<AttachmentAdmissionJob> begin(
    OperationId id,
    AttachmentAdmissionContext context,
    List<AttachmentDraftSource> sources,
  );
  Future<AttachmentAdmissionJob?> find(OperationId id);

  /// true and false both prove the original entry is no longer retained.
  /// Exceptions retain the SDK ledger's ID, cleanup responsibility and permit.
  Future<bool> remove(String draftId);
}

/// The original native task/result owner, not a feed or an immutable value.
/// Failed results use CommandDispatchFailure with actual dispatch evidence;
/// ordinary errors or lost replies cannot be guessed into a rejection.
abstract interface class AttachmentAdmissionJob {
  OperationId get operationId;
  Future<List<AttachmentMetadata>> result();

  /// Seal observation without aborting accepted admission. result still joins
  /// the original task while closing; successful entries belong to the ledger.
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}
