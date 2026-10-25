import '../../../drafts.dart'
    show InputAcceptanceEvidence, StudioPromptInput, SubmitPromptReceipt;
import '../../../operations.dart' show CommitReceipt;
import '../../../resources.dart' show OperationId;
import '../domain/interaction_values.dart';
import '../domain/interrupt_turn_reply.dart';
import '../domain/thread_command_reply.dart';

/// Adapter-only methods with a fully closed contract. Unspecified mutation replies
/// are not represented by temporary aliases or an aggregate transport fallback.
abstract interface class ConversationCommandPort {
  /// Native has neither an external CAS parameter nor a command receipt.
  /// operationId associates this exact invocation locally; it is not sent to
  /// compactThread or used as a native idempotence credential.
  Future<void> compactThread(
    String threadId, {
    required OperationId operationId,
  });

  /// Native performs its own concurrency checks, not caller-version CAS.
  Future<CommitReceipt> setThreadMode(
    String threadId,
    String mode, {
    required OperationId operationId,
  });
  Future<ThreadModelRouteCommandReply> setThreadModelRoute(
    String threadId, {
    required OperationId operationId,
    required String accountId,
    required String modelId,
    required String? effort,
    required int expectedModelRouteRevision,
    required int expectedSettingsRevision,
  });
  Future<InteractionCommandReply> respondInteraction(
    String threadId,
    String interactionId, {
    required OperationId operationId,
    required int expectedInteractionRevision,
    required InteractionResolutionCommand resolution,
  });
  Future<SubmitPromptReceipt> submitPrompt(
    String threadId,
    StudioPromptInput input, {
    required int expectedModelRouteRevision,
  });
  Future<InputAcceptanceEvidence?> readInputAcceptance(
    String threadId,
    String inputId,
  );

  /// Ordinary errors do not prove non-dispatch. Only an actual named dispatch
  /// failure may report rejection/confirmation; this exact command is not replayed.
  Future<InterruptTurnReply> interruptTurn(
    String threadId,
    String turnId, {
    required OperationId operationId,
  });
}
