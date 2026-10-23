import '../../../resources.dart';
import '../domain/authoring_values.dart';
import '../domain/conversation_repository.dart';
import '../domain/facet_state.dart';
import '../domain/read_scopes.dart';
import '../domain/thread_identity.dart';
import 'connection_owner.dart';
import 'conversation_observation_port.dart';
import 'read_connections.dart';
import 'read_scope_owners.dart';
import 'session_reads.dart';
import 'session_ui_demand.dart';

/// Concrete-Session-bound scope admission. No lookup by the current selection.
abstract class ConversationScopeAccess implements ConversationSession {
  ConversationObservationPort get observationPort;
  ConversationSessionReads get readOwners;
  bool get readAdmissionClosed;
  ConversationUiDemand? get readUiDemand;
  ThreadFacetStamp? get currentProjection;

  ConversationUiDemand requireUiDemand() {
    final demand = readUiDemand;
    if (readAdmissionClosed || demand == null || demand.retired) throw conversationCancelled;
    return demand;
  }

  ThreadFacetStamp requireOrigin(ThreadFacetStamp origin) {
    if (readAdmissionClosed) throw conversationCancelled;
    final (stamp, sync) = switch (origin.facet) {
      ThreadFacet.execution => (execution.value.stamp, execution.value.sync),
      ThreadFacet.metrics => (metrics.value.stamp, metrics.value.sync),
      ThreadFacet.context => (context.value.stamp, context.value.sync),
      ThreadFacet.configuration => (configuration.value.stamp, configuration.value.sync),
      ThreadFacet.authoring => (authoring.value.stamp, authoring.value.sync),
    };
    final projection = currentProjection;
    if (sync.phase != FacetSyncPhase.ready || stamp == null || projection == null ||
        projection.runtimeEpoch != origin.runtimeEpoch || projection.incarnation != origin.incarnation ||
        stamp.runtimeEpoch != origin.runtimeEpoch || stamp.incarnation != origin.incarnation ||
        origin.revision < 0 || origin.revision > stamp.revision) {
      throw const StudioFailure(code: StudioFailureCode.superseded,
        message: 'The requested source is not the original active Session incarnation.',
        retryable: true, correlationId: 'conversation-read-origin');
    }
    return stamp;
  }
  void requireReference(bool valid) {
    if (!valid) throw const StudioFailure(code: StudioFailureCode.superseded,
      message: 'The requested typed reference is no longer a current delivered reference.',
      retryable: true, correlationId: 'conversation-read-reference');
  }

  @override
  Future<TurnReadScope> openTurn(TurnReadRef reference, {required ThreadFacetStamp origin}) {
    requireOrigin(origin);
    final value = execution.value.value;
    requireReference(origin.facet == ThreadFacet.execution &&
      (value?.activeTurn?.reference == reference || value?.recentTerminalTurn?.reference == reference));
    return readOwners.open<TurnReadConnection, TurnScopeOwner>(origin: origin, demand: requireUiDemand(),
      open: () => observationPort.openTurnRead(threadId, reference, origin: origin),
      build: (owner) => TurnScopeOwner(owner, origin, expectedRevision: reference.revision, expectedThreadId: threadId));
  }
  @override
  Future<ActivityReadScope> openActivity(ActivityReadRef reference, {required ThreadFacetStamp origin}) {
    requireOrigin(origin); requireReference(origin.facet == ThreadFacet.execution && execution.value.value?.activity?.reference == reference);
    return readOwners.open<ActivityReadConnection, ActivityScopeOwner>(origin: origin, demand: requireUiDemand(),
      open: () => observationPort.openActivityRead(threadId, reference, origin: origin),
      build: (owner) => ActivityScopeOwner(owner, origin, expectedRevision: reference.revision, expectedThreadId: threadId));
  }
  @override
  Future<StorageReadScope> openStorage(StorageReadRef reference, {required ThreadFacetStamp origin}) {
    requireOrigin(origin); requireReference(origin.facet == ThreadFacet.execution && execution.value.value?.storage?.reference == reference);
    return readOwners.open<StorageReadConnection, StorageScopeOwner>(origin: origin, demand: requireUiDemand(),
      open: () => observationPort.openStorageRead(threadId, reference, origin: origin),
      build: (owner) => StorageScopeOwner(owner, origin, expectedRevision: reference.revision));
  }
  @override
  Future<MetricsIdentityReadScope> openMetricsIdentity(MetricsIdentityRef reference, {required ThreadFacetStamp origin}) {
    requireOrigin(origin);
    final metricsValue = metrics.value.value;
    requireReference((origin.facet == ThreadFacet.metrics &&
      (metricsValue?.live?.identity == reference || metricsValue?.authoritative?.identity == reference)) ||
      (origin.facet == ThreadFacet.context && context.value.value?.liveContext?.identity == reference));
    return readOwners.open<MetricsIdentityReadConnection, MetricsIdentityScopeOwner>(origin: origin, demand: requireUiDemand(),
      open: () => observationPort.openMetricsIdentityRead(threadId, reference, origin: origin),
      build: (owner) => MetricsIdentityScopeOwner(owner, origin));
  }
  @override
  Future<ContextReadScope> openContext(ContextReadRef reference, {required ThreadFacetStamp origin}) {
    requireOrigin(origin); requireReference(origin.facet == ThreadFacet.context && context.value.value?.details == reference);
    return readOwners.open<ContextReadConnection, ContextScopeOwner>(origin: origin, demand: requireUiDemand(),
      open: () => observationPort.openContextRead(threadId, reference, origin: origin),
      build: (owner) => ContextScopeOwner(owner, origin, expectedRevision: reference.revision));
  }
  @override
  Future<ThreadConfigurationReadScope> openConfiguration(ThreadConfigurationReadRef reference, {required ThreadFacetStamp origin}) {
    requireOrigin(origin); requireReference(origin.facet == ThreadFacet.configuration && configuration.value.value?.details == reference);
    return readOwners.open<ThreadConfigurationReadConnection, ConfigurationScopeOwner>(origin: origin, demand: requireUiDemand(),
      open: () => observationPort.openThreadConfigurationRead(threadId, reference, origin: origin),
      build: (owner) => ConfigurationScopeOwner(owner, origin, expectedRevision: reference.revision));
  }
  @override
  Future<TodoReadScope> openTodo(TodoReadRef reference, {required ThreadFacetStamp origin}) {
    requireOrigin(origin); requireReference(origin.facet == ThreadFacet.authoring && authoring.value.value?.todo?.reference == reference);
    return readOwners.open<TodoReadConnection, TodoScopeOwner>(origin: origin, demand: requireUiDemand(),
      open: () => observationPort.openTodoRead(threadId, reference, origin: origin),
      build: (owner) => TodoScopeOwner(owner, origin, expectedRevision: reference.revision));
  }
  @override
  Future<WorkflowReadScope> openWorkflow(WorkflowReadRef reference, {required ThreadFacetStamp origin}) {
    requireOrigin(origin); requireReference(origin.facet == ThreadFacet.authoring && authoring.value.value?.workflow?.reference == reference);
    return readOwners.open<WorkflowReadConnection, WorkflowScopeOwner>(origin: origin, demand: requireUiDemand(),
      open: () => observationPort.openWorkflowRead(threadId, reference, origin: origin),
      build: (owner) => WorkflowScopeOwner(owner, origin, expectedRevision: reference.revision));
  }
  @override
  Future<PlanDocumentReadScope> openPlanDocument(PlanDocumentRef reference, {required ThreadFacetStamp origin}) {
    requireOrigin(origin); requireReference(origin.facet == ThreadFacet.authoring && authoring.value.value?.plan?.document == reference);
    return readOwners.open<PlanDocumentReadConnection, PlanDocumentScopeOwner>(origin: origin, demand: requireUiDemand(),
      open: () => observationPort.openPlanDocumentRead(threadId, reference, origin: origin),
      build: (owner) => PlanDocumentScopeOwner(owner, origin, reference.version, reference.contentHash));
  }

  Future<InteractionIndexScopeOwner> openIndexReference(ThreadFacetStamp origin, InteractionIndexRef reference) {
    requireOrigin(origin); requireReference(origin.facet == ThreadFacet.execution && execution.value.value?.interactions.reference == reference);
    return readOwners.open<InteractionIndexReadConnection, InteractionIndexScopeOwner>(origin: origin, demand: requireUiDemand(),
      open: () => observationPort.openInteractionIndexRead(threadId, reference, origin: origin),
      build: (owner) => InteractionIndexScopeOwner(owner, origin, expectedRevision: reference.revision));
  }
  Future<InteractionScopeOwner> openInteractionReference(ThreadFacetStamp origin, InteractionReadRef reference) {
    requireOrigin(origin); requireReference(origin.facet == ThreadFacet.execution);
    return readOwners.open<InteractionReadConnection, InteractionScopeOwner>(origin: origin, demand: requireUiDemand(),
      open: () => observationPort.openInteractionRead(threadId, reference, origin: origin),
      build: (owner) => InteractionScopeOwner(owner, origin, expectedRevision: reference.revision, expectedThreadId: threadId));
  }
  @override
  Future<InteractionReadScope> openInteraction({required String interactionId,
      required int expectedRevision, required int expectedIncarnation}) {
    if (readAdmissionClosed) throw conversationCancelled;
    final origin = execution.value.stamp;
    requireReference(origin != null && origin.incarnation == expectedIncarnation && expectedRevision >= 0);
    final frozen = origin!;
    requireOrigin(frozen);
    return readOwners.open<InteractionReadConnection, InteractionScopeOwner>(origin: frozen, demand: requireUiDemand(),
      open: () async {
        final reference = await observationPort.resolveInteractionReadRef(threadId, interactionId,
          revision: expectedRevision, origin: frozen);
        requireOrigin(frozen);
        if (reference.revision != expectedRevision) throw readProtocol('The interaction resolver replaced the requested revision.');
        return observationPort.openInteractionRead(threadId, reference, origin: frozen);
      }, build: (owner) => InteractionScopeOwner(owner, frozen, expectedRevision: expectedRevision,
        expectedThreadId: threadId, expectedInteractionId: interactionId));
  }
}
