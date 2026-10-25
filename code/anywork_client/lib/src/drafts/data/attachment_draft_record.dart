import '../../../resources.dart';
import '../domain/draft_values.dart';

/// The existing record remains the only canonical attachment/text writer.
/// Implementations are concrete draft identities, not keys derived from IDs.
abstract interface class AttachmentDraftRecord {
  DraftStamp get attachmentStamp;
  int get attachmentGeneration;
  List<AttachmentMetadata> get attachmentMetadata;

  /// One publication for a fully validated native batch. A stale generation or
  /// sealed record refuses the entire batch, never a prefix of it.
  bool adoptAttachments(
    List<AttachmentMetadata> metadata, {
    required int generation,
  });
}
