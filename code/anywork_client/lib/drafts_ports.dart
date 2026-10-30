import 'models.dart';
export 'studio_ports.dart' show AttachmentTransport, CommandTransport;

/// Cross-domain submission coordination. It exposes no application Client.
abstract interface class DraftSubmissionCommands {
  Future<SubmitPromptReceipt> submitComposer(
    String threadId,
    StudioPromptInput input, {
    required int expectedModelRouteRevision,
  });
  Future<StartNewThreadResult?> submitNewThread({
    required String workspaceId,
    required StudioPromptInput input,
    required ThreadModeId mode,
    required ModeModelRouteView route,
    required DelegationMode delegationMode,
    required DelegationPreference delegationPreference,
    String? workspaceMode,
    required void Function(ThreadPreparationProgress) onProgress,
  });
}
