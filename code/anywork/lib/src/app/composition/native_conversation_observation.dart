import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../../infrastructure/frb/conversation/authoring_port.dart';
import '../../infrastructure/frb/conversation/configuration_port.dart';
import '../../infrastructure/frb/conversation/context_port.dart';
import '../../infrastructure/frb/conversation/execution_port.dart';
import '../../infrastructure/frb/conversation/metrics_port.dart';

/// Joins the existing typed native leaves. This owns no feed, cache or Session;
/// each call preserves the caller's original Thread, mode and read origin.
final class NativeConversationObservation
    implements ConversationObservationPort {
  const NativeConversationObservation();

  @override
  Future<FeedConnection<ThreadExecutionFrame>> openThreadExecution(
    String threadId, {
    required ThreadObservationMode mode,
  }) => openFrbThreadExecution(threadId, mode: mode);

  @override
  Future<FeedConnection<ThreadMetricsFrame>> openThreadMetrics(
    String threadId, {
    required ThreadObservationMode mode,
  }) => openFrbThreadMetrics(threadId, mode: mode);

  @override
  Future<FeedConnection<ThreadContextFrame>> openThreadContext(
    String threadId, {
    required ThreadObservationMode mode,
  }) => openFrbThreadContext(threadId, mode: mode);

  @override
  Future<FeedConnection<ThreadConfigurationFrame>> openThreadConfiguration(
    String threadId, {
    required ThreadObservationMode mode,
  }) => openFrbThreadConfiguration(threadId, mode: mode);

  @override
  Future<FeedConnection<ThreadAuthoringFrame>> openThreadAuthoring(
    String threadId, {
    required ThreadObservationMode mode,
  }) => openFrbThreadAuthoring(threadId, mode: mode);

  @override
  Future<TurnReadConnection> openTurnRead(
    String threadId,
    TurnReadRef reference, {
    required ThreadFacetStamp origin,
  }) => openFrbTurnRead(threadId, reference, origin: origin);

  @override
  Future<InteractionIndexReadConnection> openInteractionIndexRead(
    String threadId,
    InteractionIndexRef reference, {
    required ThreadFacetStamp origin,
  }) => openFrbInteractionIndexRead(threadId, reference, origin: origin);

  @override
  Future<InteractionReadRef> resolveInteractionReadRef(
    String threadId,
    String interactionId, {
    required int revision,
    required ThreadFacetStamp origin,
  }) => resolveFrbInteractionReadRef(
    threadId,
    interactionId,
    revision: revision,
    origin: origin,
  );

  @override
  Future<InteractionReadConnection> openInteractionRead(
    String threadId,
    InteractionReadRef reference, {
    required ThreadFacetStamp origin,
  }) => openFrbInteractionRead(threadId, reference, origin: origin);

  @override
  Future<ActivityReadConnection> openActivityRead(
    String threadId,
    ActivityReadRef reference, {
    required ThreadFacetStamp origin,
  }) => openFrbActivityRead(threadId, reference, origin: origin);

  @override
  Future<StorageReadConnection> openStorageRead(
    String threadId,
    StorageReadRef reference, {
    required ThreadFacetStamp origin,
  }) => openFrbStorageRead(threadId, reference, origin: origin);

  @override
  Future<MetricsIdentityReadConnection> openMetricsIdentityRead(
    String threadId,
    MetricsIdentityRef reference, {
    required ThreadFacetStamp origin,
  }) => openFrbMetricsIdentityRead(threadId, reference, origin: origin);

  @override
  Future<ContextReadConnection> openContextRead(
    String threadId,
    ContextReadRef reference, {
    required ThreadFacetStamp origin,
  }) => openFrbThreadContextRead(threadId, reference, origin: origin);

  @override
  Future<ThreadConfigurationReadConnection> openThreadConfigurationRead(
    String threadId,
    ThreadConfigurationReadRef reference, {
    required ThreadFacetStamp origin,
  }) => openFrbThreadConfigurationRead(threadId, reference, origin: origin);

  @override
  Future<TodoReadConnection> openTodoRead(
    String threadId,
    TodoReadRef reference, {
    required ThreadFacetStamp origin,
  }) => openFrbTodoRead(threadId, reference, origin: origin);

  @override
  Future<WorkflowReadConnection> openWorkflowRead(
    String threadId,
    WorkflowReadRef reference, {
    required ThreadFacetStamp origin,
  }) => openFrbWorkflowRead(threadId, reference, origin: origin);

  @override
  Future<PlanDocumentReadConnection> openPlanDocumentRead(
    String threadId,
    PlanDocumentRef reference, {
    required ThreadFacetStamp origin,
  }) => openFrbPlanDocumentRead(threadId, reference, origin: origin);
}
