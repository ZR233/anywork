import '../../../resources.dart';
import 'authoring_values.dart';
import 'conversation_activation_failure.dart';
import 'conversation_timeline.dart';
import 'facet_state.dart';
import 'interaction_index_state.dart';
import 'read_scopes.dart';
import 'thread_identity.dart';

abstract interface class ConversationRepository {
  ReadonlyLatestValue<ConversationSession?> get active;
  ReadonlyLatestValue<ConversationActivationFailure?> get activationFailure;
  void retryActivation({required String threadId, required int selectionGeneration});
  ConversationSession? existingSession(String threadId);
  ConversationSession session(String threadId);
  void seal();
  Future<CloseReport> close({DateTime? deadline});
  Future<CloseReport> retryCleanup({DateTime? deadline});
}

/// A runtime owner, not a Freezed value. A borrower cannot close the Session.
abstract interface class ConversationSession {
  String get threadId;
  ReadonlyLatestValue<ThreadExecutionState> get execution;
  ReadonlyLatestValue<ThreadMetricsState> get metrics;
  ReadonlyLatestValue<ThreadContextState> get context;
  ReadonlyLatestValue<ThreadConfigurationState> get configuration;
  ReadonlyLatestValue<ThreadAuthoringState> get authoring;
  ReadonlyLatestValue<InteractionIndexReadState> get interactions;
  ConversationTimeline get timeline;
  Future<void> retry(ThreadFacet facet);
  Future<void> loadInteractionsPage({int limit = 32});
  Future<TurnReadScope> openTurn(TurnReadRef reference, {required ThreadFacetStamp origin});
  Future<ActivityReadScope> openActivity(ActivityReadRef reference, {required ThreadFacetStamp origin});
  Future<StorageReadScope> openStorage(StorageReadRef reference, {required ThreadFacetStamp origin});
  Future<MetricsIdentityReadScope> openMetricsIdentity(MetricsIdentityRef reference, {required ThreadFacetStamp origin});
  Future<ContextReadScope> openContext(ContextReadRef reference, {required ThreadFacetStamp origin});
  Future<ThreadConfigurationReadScope> openConfiguration(ThreadConfigurationReadRef reference, {required ThreadFacetStamp origin});
  Future<TodoReadScope> openTodo(TodoReadRef reference, {required ThreadFacetStamp origin});
  Future<WorkflowReadScope> openWorkflow(WorkflowReadRef reference, {required ThreadFacetStamp origin});
  Future<PlanDocumentReadScope> openPlanDocument(PlanDocumentRef reference, {required ThreadFacetStamp origin});
  Future<InteractionReadScope> openInteraction({required String interactionId,
    required int expectedRevision, required int expectedIncarnation});
}
