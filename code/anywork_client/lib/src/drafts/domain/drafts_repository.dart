import 'draft_owners.dart';

abstract interface class DraftsRepository {
  ComposerDraftOwner composer(String threadId);
  ComposerDraftOwner? existingComposer(String threadId);
  StartSessionDraftOwner get startDraft;
  AttachmentDraftsOwner get attachments;
  List<ComposerDraftOwner> projectComposers(String projectId);
  Future<void> discardProjectDrafts(
    String projectId,
    List<ComposerDraftOwner> owners,
  );
  Future<void> close();
  Future<void> retryCleanup();
}
