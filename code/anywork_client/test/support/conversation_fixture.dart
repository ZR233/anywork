import 'dart:async';

import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/drafts.dart'
    show InputAcceptanceEvidence, StudioPromptInput, SubmitPromptReceipt;
import 'package:anywork_client/modes.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace_ports.dart';

import 'scripted_feed.dart';
import 'thread_metadata_fixture.dart';
import 'timeline_transport.dart';

/// Public assembly with controlled external inputs, not another Session or
/// reducer. Silent facets keep their real feed owners alive without inventing
/// business baselines to exercise the independent Timeline capability.
final class ConversationFixture {
  ConversationFixture({
    ResourceBudget? budget,
    FixtureConversationContext? context,
    ConversationCommandPort? commands,
    ReadonlyLatestValue<AgentDirectoryState> Function()? agentDirectory,
    String clientId = 'conversation-test',
  }) : budget = budget ?? ResourceBudget(),
       context = context ?? FixtureConversationContext() {
    operations = OperationRegistry(clientId: clientId, budget: this.budget);
    agents = ResourceSource(
      const AgentDirectoryState(
        projection: ProductProjection(stamp: null, header: null,
          sync: ResourceSyncState(phase: ResourceSyncPhase.idle, error: null, retryExhausted: false)),
        sourceStatus: null, agents: CollectionMirror.unavailable(lastKnown: null)),
      this.budget, 'fixture-agent-directory',
    );
    final assembly = createConversationRepository(
      port: facets,
      context: this.context,
      commands: commands ?? const UnscriptedConversationCommands(),
      timeline: timeline,
      budget: this.budget,
      operations: operations,
      agentDirectory: agentDirectory ?? () => agents.readonly,
    );
    repository = assembly.repository;
    demand = assembly.demand;
    archive = assembly.archive;
  }

  final ResourceBudget budget;
  final FixtureConversationContext context;
  final facets = FixtureConversationPort();
  final timeline = TimelineOpenQueue();
  late final OperationRegistry operations;
  late final ResourceSource<AgentDirectoryState> agents;
  late final ConversationRepository repository;
  late final ConversationDemand demand;
  late final WorkspaceArchiveCapturePort archive;
  int _selectionGeneration = 0;

  ConversationSession select(String threadId) {
    demand.select(
      threadId: threadId,
      needsOpen: false,
      selectionGeneration: ++_selectionGeneration,
    );
    return repository.active.value!;
  }

  void deselect() => demand.select(
    threadId: null,
    needsOpen: false,
    selectionGeneration: ++_selectionGeneration,
  );

  /// Answers every still-pending scripted Timeline open with one real native
  /// connection. The fixture owns that native side, so an unanswered open keeps
  /// the production join genuinely pending instead of proving the close clean.
  void acceptPendingTimelineOpens() {
    for (var index = 0; index < timeline.requests.length; index++) {
      final request = timeline.requests[index];
      if (request.result.isCompleted) continue;
      request.result.complete(TestTimelineConnection());
    }
  }
}

/// Read-only factory consumers have no command scenario. Fail at the actual
/// boundary if one is unexpectedly invoked; never fabricate a success receipt.
class UnscriptedConversationCommands implements ConversationCommandPort {
  const UnscriptedConversationCommands();
  @override
  Future<void> compactThread(
    String threadId, {
    required OperationId operationId,
  }) => throw UnsupportedError('Unscripted manual compaction');
  @override
  Future<CommitReceipt> setThreadMode(
    String threadId,
    String mode, {
    required OperationId operationId,
  }) => throw UnsupportedError('Unscripted Thread mode change');
  @override
  Future<ThreadModelRouteCommandReply> setThreadModelRoute(
    String threadId, {
    required OperationId operationId,
    required String accountId,
    required String modelId,
    required String? effort,
    required int expectedModelRouteRevision,
    required int expectedSettingsRevision,
  }) => throw UnsupportedError('Unscripted Thread model route change');
  @override
  Future<InteractionCommandReply> respondInteraction(
    String threadId,
    String interactionId, {
    required OperationId operationId,
    required int expectedInteractionRevision,
    required InteractionResolutionCommand resolution,
  }) => throw UnsupportedError('Unscripted interaction response');
  @override
  Future<SubmitPromptReceipt> submitPrompt(
    String threadId,
    StudioPromptInput input, {
    required int expectedModelRouteRevision,
  }) => throw UnsupportedError('Unscripted prompt submission');
  @override
  Future<InputAcceptanceEvidence?> readInputAcceptance(
    String threadId,
    String inputId,
  ) => throw UnsupportedError('Unscripted input acceptance read');
  @override
  Future<StopExecutionReply> stopExecution(
    String threadId,
    String turnId, {
    required OperationId operationId,
  }) => throw UnsupportedError('Unscripted exact Turn interrupt');
  @override
  Future<ContinueThreadReply> continueThread(String threadId, {
    required OperationId operationId, required String expectedContinuationId,
    required int expectedModelRouteRevision,
  }) => throw UnsupportedError('Unscripted continuation');
  @override
  Future<ContinuationOperationView?> readContinuationOperation(String threadId, OperationId operationId) =>
      throw UnsupportedError('Unscripted continuation operation read');
}

WorkspaceThreadRecord fixtureThread(
  String threadId, {
  String? parentThreadId,
  String role = 'root',
}) => WorkspaceThreadRecord(
  id: threadId,
  projectId: 'project',
  title: 'Synthetic Thread',
  mode: ThreadModeId.simple,
  delegationMode: DelegationMode.automatic,
  delegationPreference: DelegationPreference.balanced,
  frozenModel: null,
  workspaceMode: ThreadWorkspaceMode.local,
  workspacePath: '/workspace/$threadId',
  rootThreadId: parentThreadId ?? threadId,
  parentThreadId: parentThreadId,
  role: role,
  agentPath: 'root',
  status: ThreadStatus.idle,
  createdAt: 1700000000,
  updatedAt: 1700000001,
  lastUserMessageAt: null,
  archived: false,
);

final class FixtureConversationContext implements ConversationContextPort {
  final metadataRequests = <String>[];
  final metadataOwners = <ThreadMetadata>[];
  final recoveryRequests = <WorkspaceThreadRecord>[];
  ThreadMetadata Function(String)? metadata;
  Future<ConversationRecoveryAccess> Function(WorkspaceThreadRecord)? recovery;

  @override
  ThreadMetadata openThreadMetadata(String threadId) {
    metadataRequests.add(threadId);
    final owner =
        metadata?.call(threadId) ??
        ScriptedThreadMetadata(
          threadId,
          initial: metadataState(record: fixtureThread(threadId)),
        );
    metadataOwners.add(owner);
    return owner;
  }

  @override
  Future<ConversationRecoveryAccess> readRecoveryAccess(
    WorkspaceThreadRecord thread,
  ) {
    recoveryRequests.add(thread);
    return recovery?.call(thread) ??
        Future.value(const ConversationRecoveryAccess.allowed());
  }
}

final class FacetOpen<T> {
  const FacetOpen(this.threadId, this.mode, this.feed);
  final String threadId;
  final ThreadObservationMode mode;
  final ScriptedFeed<T> feed;
}

final class FixtureConversationPort implements ConversationObservationPort {
  final execution = <FacetOpen<ThreadExecutionFrame>>[];
  final _executionWaiters = <int, Completer<FacetOpen<ThreadExecutionFrame>>>{};
  final metrics = <FacetOpen<ThreadMetricsFrame>>[];
  final _metricsWaiters = <int, Completer<FacetOpen<ThreadMetricsFrame>>>{};
  final context = <FacetOpen<ThreadContextFrame>>[];
  final configuration = <FacetOpen<ThreadConfigurationFrame>>[];
  final _configurationWaiters =
      <int, Completer<FacetOpen<ThreadConfigurationFrame>>>{};
  final authoring = <FacetOpen<ThreadAuthoringFrame>>[];
  final _authoringWaiters = <int, Completer<FacetOpen<ThreadAuthoringFrame>>>{};
  final plans = <PlanDocumentOpen>[];
  final _planWaiters = <int, Completer<PlanDocumentOpen>>{};
  Future<TurnReadConnection> Function(String, TurnReadRef, ThreadFacetStamp)?
  turnOpen;
  Future<InteractionReadRef> Function(String, String, int, ThreadFacetStamp)?
  interactionResolve;
  Future<InteractionReadConnection> Function(
    String,
    InteractionReadRef,
    ThreadFacetStamp,
  )?
  interactionOpen;
  Future<InteractionIndexReadConnection> Function(String, InteractionIndexRef, ThreadFacetStamp)? interactionIndexOpen;

  @override
  Future<InteractionIndexReadConnection> openInteractionIndexRead(String threadId, InteractionIndexRef reference, {required ThreadFacetStamp origin}) {
    final action = interactionIndexOpen;
    if (action == null) throw UnsupportedError('Unscripted interaction index read');
    return action(threadId, reference, origin);
  }
  Future<ThreadConfigurationReadConnection> Function(
    String,
    ThreadConfigurationReadRef,
    ThreadFacetStamp,
  )?
  configurationOpen;
  int _sequence = 0;

  Future<FacetOpen<ThreadExecutionFrame>> executionOpened(int index) =>
      index < execution.length
      ? Future.value(execution[index])
      : _executionWaiters
            .putIfAbsent(index, Completer<FacetOpen<ThreadExecutionFrame>>.new)
            .future;
  Future<FacetOpen<ThreadConfigurationFrame>> configurationOpened(int index) =>
      index < configuration.length
      ? Future.value(configuration[index])
      : _configurationWaiters
            .putIfAbsent(
              index,
              Completer<FacetOpen<ThreadConfigurationFrame>>.new,
            )
            .future;

  Future<FacetOpen<ThreadAuthoringFrame>> authoringOpened(int index) =>
      index < authoring.length
      ? Future.value(authoring[index])
      : _authoringWaiters
            .putIfAbsent(index, Completer<FacetOpen<ThreadAuthoringFrame>>.new)
            .future;

  Future<PlanDocumentOpen> planOpened(int index) => index < plans.length
      ? Future.value(plans[index])
      : _planWaiters.putIfAbsent(index, Completer<PlanDocumentOpen>.new).future;

  @override
  Future<PlanDocumentReadConnection> openPlanDocumentRead(
    String threadId,
    PlanDocumentRef reference, {
    required ThreadFacetStamp origin,
  }) {
    final call = PlanDocumentOpen(threadId, reference, origin, plans.length);
    plans.add(call);
    _planWaiters.remove(call.index)?.complete(call);
    return call.reply.future;
  }

  @override
  Future<TurnReadConnection> openTurnRead(
    String threadId,
    TurnReadRef reference, {
    required ThreadFacetStamp origin,
  }) {
    final open = turnOpen;
    if (open == null) throw UnsupportedError('Unscripted original Turn read');
    return open(threadId, reference, origin);
  }

  @override
  Future<InteractionReadRef> resolveInteractionReadRef(
    String threadId,
    String interactionId, {
    required int revision,
    required ThreadFacetStamp origin,
  }) {
    final resolve = interactionResolve;
    if (resolve == null)
      throw UnsupportedError('Unscripted original interaction resolution');
    return resolve(threadId, interactionId, revision, origin);
  }

  @override
  Future<InteractionReadConnection> openInteractionRead(
    String threadId,
    InteractionReadRef reference, {
    required ThreadFacetStamp origin,
  }) {
    final open = interactionOpen;
    if (open == null)
      throw UnsupportedError('Unscripted original interaction read');
    return open(threadId, reference, origin);
  }

  @override
  Future<ThreadConfigurationReadConnection> openThreadConfigurationRead(
    String threadId,
    ThreadConfigurationReadRef reference, {
    required ThreadFacetStamp origin,
  }) {
    final open = configurationOpen;
    if (open == null) {
      throw UnsupportedError('Unscripted original Thread configuration read');
    }
    return open(threadId, reference, origin);
  }

  Future<FacetOpen<ThreadMetricsFrame>> metricsOpened(int index) =>
      index < metrics.length
      ? Future.value(metrics[index])
      : _metricsWaiters
            .putIfAbsent(index, Completer<FacetOpen<ThreadMetricsFrame>>.new)
            .future;

  Future<FeedConnection<T>> _open<T>(
    List<FacetOpen<T>> requests,
    String threadId,
    ThreadObservationMode mode,
    int? Function(T) sequenceOf,
    bool Function(T) isTerminal,
  ) {
    final feed = ScriptedFeed<T>(
      feedId: 'facet-${++_sequence}-$threadId',
      sequenceOf: sequenceOf,
      isTerminal: isTerminal,
    );
    requests.add(FacetOpen(threadId, mode, feed));
    return Future.value(feed);
  }

  @override
  Future<FeedConnection<ThreadExecutionFrame>> openThreadExecution(
    String threadId, {
    required ThreadObservationMode mode,
  }) {
    final result = _open(
      execution,
      threadId,
      mode,
      (frame) => frame is ThreadExecutionData ? frame.deliverySequence : null,
      (frame) => frame is! ThreadExecutionData,
    );
    _executionWaiters.remove(execution.length - 1)?.complete(execution.last);
    return result;
  }

  @override
  Future<FeedConnection<ThreadMetricsFrame>> openThreadMetrics(
    String threadId, {
    required ThreadObservationMode mode,
  }) {
    final result = _open(
      metrics,
      threadId,
      mode,
      (frame) => frame is ThreadMetricsData ? frame.deliverySequence : null,
      (frame) => frame is! ThreadMetricsData,
    );
    _metricsWaiters.remove(metrics.length - 1)?.complete(metrics.last);
    return result;
  }

  @override
  Future<FeedConnection<ThreadContextFrame>> openThreadContext(
    String threadId, {
    required ThreadObservationMode mode,
  }) => _open(
    context,
    threadId,
    mode,
    (frame) => frame is ThreadContextData ? frame.deliverySequence : null,
    (frame) => frame is! ThreadContextData,
  );

  @override
  Future<FeedConnection<ThreadConfigurationFrame>> openThreadConfiguration(
    String threadId, {
    required ThreadObservationMode mode,
  }) {
    final result = _open(
      configuration,
      threadId,
      mode,
      (frame) =>
          frame is ThreadConfigurationData ? frame.deliverySequence : null,
      (frame) => frame is! ThreadConfigurationData,
    );
    _configurationWaiters
        .remove(configuration.length - 1)
        ?.complete(configuration.last);
    return result;
  }

  @override
  Future<FeedConnection<ThreadAuthoringFrame>> openThreadAuthoring(
    String threadId, {
    required ThreadObservationMode mode,
  }) {
    final result = _open(
      authoring,
      threadId,
      mode,
      (frame) => frame is ThreadAuthoringData ? frame.deliverySequence : null,
      (frame) => frame is! ThreadAuthoringData,
    );
    _authoringWaiters.remove(authoring.length - 1)?.complete(authoring.last);
    return result;
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted conversation read: ${invocation.memberName}',
  );
}

final class TimelineOpenRequest {
  TimelineOpenRequest(this.threadId);
  final String threadId;
  final result = Completer<StudioTimelineConnection>();
}

/// Records actual port admission, including late opens belonging to retired
/// Sessions. Waiting for an index does not start or replay an open.
final class TimelineOpenQueue implements TimelineTransport {
  final requests = <TimelineOpenRequest>[];
  final _waiters = <int, Completer<TimelineOpenRequest>>{};

  Future<TimelineOpenRequest> opened(int index) {
    if (index < requests.length) return Future.value(requests[index]);
    return _waiters
        .putIfAbsent(index, Completer<TimelineOpenRequest>.new)
        .future;
  }

  @override
  Future<StudioTimelineConnection> openTimeline(String threadId) {
    final request = TimelineOpenRequest(threadId);
    final index = requests.length;
    requests.add(request);
    _waiters.remove(index)?.complete(request);
    return request.result.future;
  }
}

/// One scripted native Plan document scope. The test supplies the exact
/// identity and body; this object only records admission and close.
final class PlanDocumentOpen {
  PlanDocumentOpen(this.threadId, this.reference, this.origin, this.index);
  final String threadId;
  final PlanDocumentRef reference;
  final ThreadFacetStamp origin;
  final int index;
  final reply = Completer<PlanDocumentReadConnection>();
  PlanDocumentReadConnection? native;
  PlanDocumentReadConnection accept(PlanDocumentReadConnection value) {
    native = value;
    reply.complete(value);
    return value;
  }
}

/// Observes receipts of the existing native-boundary fake. This decorator owns
/// no protocol, cleanup state, body cache or retry policy of its own.
final class TimelineConnectionProbe implements StudioTimelineConnection {
  TimelineConnectionProbe(this.native);
  final TestTimelineConnection native;
  final _acks = <int, Completer<void>>{};
  final _pages = <int, Completer<({String? before, int? limit})>>{};
  final _details =
      <int, Completer<({String itemId, StudioTimelineDetailQuery query})>>{};

  Future<void> acknowledged(int prefix) {
    if (native.ackedThrough >= prefix) return Future.value();
    return _acks.putIfAbsent(prefix, Completer<void>.new).future;
  }

  Future<({String? before, int? limit})> pageRequested(int index) {
    if (index < native.pageRequests.length) {
      return Future.value(native.pageRequests[index]);
    }
    return _pages
        .putIfAbsent(index, Completer<({String? before, int? limit})>.new)
        .future;
  }

  Future<({String itemId, StudioTimelineDetailQuery query})> detailRequested(
    int index,
  ) {
    if (index < native.detailRequests.length) {
      return Future.value(native.detailRequests[index]);
    }
    return _details
        .putIfAbsent(
          index,
          Completer<({String itemId, StudioTimelineDetailQuery query})>.new,
        )
        .future;
  }

  @override
  Stream<StudioTimelineFeedFrame> get events => native.events;

  @override
  Future<void> ackThrough(int deliverySequence) =>
      native.ackThrough(deliverySequence).then((_) {
        for (final prefix in _acks.keys.toList()) {
          if (prefix <= native.ackedThrough) _acks.remove(prefix)!.complete();
        }
      });

  @override
  Future<StudioTimelinePage> page({String? before, int? limit}) {
    final result = native.page(before: before, limit: limit);
    final index = native.pageRequests.length - 1;
    _pages.remove(index)?.complete(native.pageRequests[index]);
    return result;
  }

  @override
  Future<StudioTimelineDetailChunk> readDetail({
    required String itemId,
    required StudioTimelineDetailQuery query,
  }) {
    final result = native.readDetail(itemId: itemId, query: query);
    final index = native.detailRequests.length - 1;
    _details.remove(index)?.complete(native.detailRequests[index]);
    return result;
  }

  @override
  void requestClose() => native.requestClose();
  @override
  Future<FeedCloseReport> close() => native.close();
  @override
  Future<FeedCloseReport> retryClose() => native.retryClose();
}
