import '../../../resources_ports.dart';
import '../../../workspace.dart' show ThreadMetadata, WorkspaceThreadRecord;
import '../domain/authoring_values.dart';
import '../domain/interaction_index_state.dart';
import '../domain/thread_frames.dart';
import '../domain/thread_identity.dart';
import 'read_connections.dart';

/// The original successful creation owner's non-activating projection borrow.
/// Its identity is native-issued; this is not an ordinary live/cold opener.
abstract interface class CreatedInputExecutionSource {
  String get threadId;
  String get inputId;
  String get runtimeEpoch;
  int get incarnation;
  Future<FeedConnection<ThreadExecutionFrame>> openExecution();
}

/// Internal admission snapshot. Only the source interface is exported by ports.
final class CreatedInputExecutionBinding {
  CreatedInputExecutionBinding(this.source)
    : threadId = source.threadId,
      inputId = source.inputId,
      runtimeEpoch = source.runtimeEpoch,
      incarnation = source.incarnation;
  final CreatedInputExecutionSource source;
  final String threadId;
  final String inputId;
  final String runtimeEpoch;
  final int incarnation;
  bool matches(ThreadFacetStamp stamp) =>
      stamp.runtimeEpoch == runtimeEpoch && stamp.incarnation == incarnation;
}

abstract interface class ConversationObservationPort {
  Future<FeedConnection<ThreadExecutionFrame>> openThreadExecution(
    String threadId, {
    required ThreadObservationMode mode,
  });
  Future<FeedConnection<ThreadMetricsFrame>> openThreadMetrics(
    String threadId, {
    required ThreadObservationMode mode,
  });
  Future<FeedConnection<ThreadContextFrame>> openThreadContext(
    String threadId, {
    required ThreadObservationMode mode,
  });
  Future<FeedConnection<ThreadConfigurationFrame>> openThreadConfiguration(
    String threadId, {
    required ThreadObservationMode mode,
  });
  Future<FeedConnection<ThreadAuthoringFrame>> openThreadAuthoring(
    String threadId, {
    required ThreadObservationMode mode,
  });

  Future<TurnReadConnection> openTurnRead(
    String threadId,
    TurnReadRef reference, {
    required ThreadFacetStamp origin,
  });
  Future<InteractionIndexReadConnection> openInteractionIndexRead(
    String threadId,
    InteractionIndexRef reference, {
    required ThreadFacetStamp origin,
  });
  Future<InteractionReadRef> resolveInteractionReadRef(
    String threadId,
    String interactionId, {
    required int revision,
    required ThreadFacetStamp origin,
  });
  Future<InteractionReadConnection> openInteractionRead(
    String threadId,
    InteractionReadRef reference, {
    required ThreadFacetStamp origin,
  });
  Future<ActivityReadConnection> openActivityRead(
    String threadId,
    ActivityReadRef reference, {
    required ThreadFacetStamp origin,
  });
  Future<StorageReadConnection> openStorageRead(
    String threadId,
    StorageReadRef reference, {
    required ThreadFacetStamp origin,
  });
  Future<MetricsIdentityReadConnection> openMetricsIdentityRead(
    String threadId,
    MetricsIdentityRef reference, {
    required ThreadFacetStamp origin,
  });
  Future<ContextReadConnection> openContextRead(
    String threadId,
    ContextReadRef reference, {
    required ThreadFacetStamp origin,
  });
  Future<ThreadConfigurationReadConnection> openThreadConfigurationRead(
    String threadId,
    ThreadConfigurationReadRef reference, {
    required ThreadFacetStamp origin,
  });
  Future<TodoReadConnection> openTodoRead(
    String threadId,
    TodoReadRef reference, {
    required ThreadFacetStamp origin,
  });
  Future<WorkflowReadConnection> openWorkflowRead(
    String threadId,
    WorkflowReadRef reference, {
    required ThreadFacetStamp origin,
  });
  Future<PlanDocumentReadConnection> openPlanDocumentRead(
    String threadId,
    PlanDocumentRef reference, {
    required ThreadFacetStamp origin,
  });
}

abstract interface class ConversationContextPort {
  ThreadMetadata openThreadMetadata(String threadId);
  Future<ConversationRecoveryAccess> readRecoveryAccess(
    WorkspaceThreadRecord thread,
  );
}
