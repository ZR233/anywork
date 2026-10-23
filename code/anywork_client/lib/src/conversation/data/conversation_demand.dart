import '../../../drafts.dart' show SubmitPromptReceipt;
import '../../../resources.dart';
import '../domain/conversation_repository.dart';
import '../domain/facet_state.dart';
import '../domain/thread_identity.dart';
import 'conversation_observation_port.dart' show CreatedInputExecutionSource;

/// Selection is an explicit composition capability, not a side effect of reads.
abstract interface class ConversationDemand {
  void select({required String? threadId, required bool needsOpen, required int selectionGeneration});
  Future<CloseReport> retire(String threadId, {DateTime? deadline});
  void retrySelected(String threadId);
  SubmissionExecutionLease retainForSubmission(ConversationSession exact,
      {required ThreadFacetStamp expectedOrigin});
  /// Only the original operation's real successful creation receipt admits this.
  SubmissionExecutionLease retainForCreatedInput(ConversationSession exact,
      {required SubmitPromptReceipt receipt, required CreatedInputExecutionSource source});
}

/// A specific execution demand, not a Session writer or native close capability.
abstract interface class SubmissionExecutionLease {
  String get threadId;
  AttemptId get attemptId;
  ReadonlyLatestValue<ThreadExecutionState> get execution;
  Future<ThreadFacetStamp> get ready;
  void release();
}
