import '../../../drafts.dart' show InputAcceptanceEvidence, StudioPromptInput, SubmitPromptReceipt;

/// Adapter-only methods with a fully closed contract. Unspecified mutation replies
/// are not represented by temporary aliases or an aggregate transport fallback.
abstract interface class ConversationCommandPort {
  Future<SubmitPromptReceipt> submitPrompt(String threadId, StudioPromptInput input,
      {required int expectedModelRouteRevision});
  Future<InputAcceptanceEvidence?> readInputAcceptance(String threadId, String inputId);
}
