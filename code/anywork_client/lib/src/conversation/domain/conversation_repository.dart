import '../../../operations.dart';
import '../../../resources.dart';
import 'authoring_values.dart';
import 'conversation_activation_failure.dart';
import 'conversation_timeline.dart';
import 'continuation_values.dart';
import 'facet_state.dart';
import 'interaction_index_state.dart';
import 'interaction_values.dart';
import 'read_scopes.dart';
import 'thread_command_reply.dart';
import 'thread_identity.dart';
import 'stop_execution_result.dart';

abstract interface class ConversationRepository {
  ReadonlyLatestValue<ConversationSession?> get active;
  ReadonlyLatestValue<ConversationActivationFailure?> get activationFailure;
  void retryActivation({
    required String threadId,
    required int selectionGeneration,
  });
  ConversationSession? existingSession(String threadId);
  ConversationSession session(String threadId);
  /// Freezes the original complete AgentDirectory source and delivered member.
  /// Does not select, activate, create a Session or acquire a draft.
  StopExecutionResult stopDirectoryExecution({
    required ProductProjectionStamp origin,
    required ProductEntityRef member,
    required String executionId,
  });
  void seal();
  Future<CloseReport> close({DateTime? deadline});

  /// Continues original retired cleanup only; does not seal active Sessions or
  /// the Repository. Application shutdown must request seal/close separately.
  Future<CloseReport> retryCleanup({DateTime? deadline});
}

/// A runtime owner, not a Freezed value. A borrower cannot close the Session.
abstract interface class ConversationSession {
  String get threadId;
  /// False until canonical metadata proves this is a user-addressable root.
  bool get acceptsUserInput;
  ReadonlyLatestValue<ThreadExecutionState> get execution;
  ReadonlyLatestValue<ThreadMetricsState> get metrics;
  ReadonlyLatestValue<ThreadContextState> get context;
  ReadonlyLatestValue<ThreadConfigurationState> get configuration;
  ReadonlyLatestValue<ThreadAuthoringState> get authoring;
  ReadonlyLatestValue<InteractionIndexReadState> get interactions;
  ConversationTimeline get timeline;
  Future<void> retry(ThreadFacet facet);
  Future<void> loadInteractionsPage({int limit = 32});

  /// origin must be this Session's Context source. Freezes the concrete Session
  /// and operation before dispatch. Success is
  /// CommandResult.acknowledged(Unit): native returns no receipt, external CAS,
  /// NoChange, target stamp, or effect/durability evidence. Context stays feed-owned.
  OperationTicket<Unit> compactThread({required ThreadFacetStamp origin});

  /// Only the native receipt is reported. origin binds the Configuration source;
  /// it is not an external expected-version CAS. No revision-based NoChange.
  OperationTicket<CommitReceipt> setThreadMode({
    required ThreadFacetStamp origin,
    required String mode,
  });

  /// origin binds the Configuration source. Both expected versions and the
  /// route are frozen before the first await.
  /// A known CAS rejection may be explicitly resubmitted with the same route
  /// and new expected versions; this method never retries a rejected/unknown call.
  /// Pass the rejected ticket's operationId to retain that business identity.
  /// The same Session/incarnation and immutable route are required. The returned
  /// attempt has its own result; an earlier ticket's result never changes.
  OperationTicket<ThreadModelRouteCommandReply> setThreadModelRoute({
    required ThreadFacetStamp origin,
    OperationId? operationId,
    required String accountId,
    required String modelId,
    String? effort,
    required int expectedModelRouteRevision,
    required int expectedSettingsRevision,
  });

  /// The execution origin, interaction identity/version and immutable resolution
  /// remain bound to this Session. A caller may explicitly retry a known CAS
  /// rejection with the same resolution and a new version, never an unknown call.
  OperationTicket<InteractionCommandReply> respondInteraction({
    required ThreadFacetStamp origin,
    OperationId? operationId,
    required String interactionId,
    required int expectedInteractionRevision,
    required InteractionResolutionCommand resolution,
  });
  OperationTicket<InteractionCommandReply> respondHostedInteraction({
    required ThreadFacetStamp origin,
    required InteractionReadRef reference,
    required String targetThreadId,
    OperationId? operationId,
    required String interactionId,
    required int expectedInteractionRevision,
    required InteractionResolutionCommand resolution,
  });
  Future<InteractionReadScope> openHostedInteraction({
    required ThreadFacetStamp origin,
    required InteractionReadRef reference,
    required String targetThreadId,
  });
  StopExecutionResult stopExecution({
    required ThreadFacetStamp origin,
    required String executionId,
  });
  OperationTicket<ContinueThreadReply> continueThread({
    required ThreadFacetStamp origin,
    OperationId? operationId,
    required String continuationId,
    required int expectedModelRouteRevision,
  });
  /// Queries only a continuation admitted by this exact Session. Never resends.
  Future<ContinuationOperationView?> readContinuationOperation(OperationId operationId);
  Future<TurnReadScope> openTurn(
    TurnReadRef reference, {
    required ThreadFacetStamp origin,
  });
  Future<ActivityReadScope> openActivity(
    ActivityReadRef reference, {
    required ThreadFacetStamp origin,
  });
  Future<StorageReadScope> openStorage(
    StorageReadRef reference, {
    required ThreadFacetStamp origin,
  });
  Future<MetricsIdentityReadScope> openMetricsIdentity(
    MetricsIdentityRef reference, {
    required ThreadFacetStamp origin,
  });
  Future<ContextReadScope> openContext(
    ContextReadRef reference, {
    required ThreadFacetStamp origin,
  });
  Future<ThreadConfigurationReadScope> openConfiguration(
    ThreadConfigurationReadRef reference, {
    required ThreadFacetStamp origin,
  });
  Future<TodoReadScope> openTodo(
    TodoReadRef reference, {
    required ThreadFacetStamp origin,
  });
  Future<WorkflowReadScope> openWorkflow(
    WorkflowReadRef reference, {
    required ThreadFacetStamp origin,
  });
  Future<PlanDocumentReadScope> openPlanDocument(
    PlanDocumentRef reference, {
    required ThreadFacetStamp origin,
  });
  Future<InteractionReadScope> openInteraction({
    required String interactionId,
    required int expectedRevision,
    required int expectedIncarnation,
  });
}
