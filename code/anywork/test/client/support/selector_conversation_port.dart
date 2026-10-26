import 'dart:async';

import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/drafts.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace.dart';

import '../../../../anywork_client/test/support/conversation_fixture.dart';
import '../../../../anywork_client/test/support/drafts_native_fixture.dart';
import '../../../../anywork_client/test/support/profile_native_pin.dart';
import 'selector_configuration_port.dart';

ThreadFacetStamp selectorFacet(
  ThreadFacet facet,
  int revision, {
  int incarnation = 1,
  String runtime = 'selector-native',
}) => ThreadFacetStamp(
  runtimeEpoch: runtime,
  incarnation: incarnation,
  facet: facet,
  revision: revision,
);
ThreadFeedIdentity selectorFeed<T>(FacetOpen<T> opening, ThreadFacet facet) =>
    ThreadFeedIdentity(
      feedId: opening.feed.feedId,
      runtimeEpoch: 'selector-native',
      incarnation: 1,
      facet: facet,
      mode: opening.mode,
    );
ReadScopeIdentity selectorScope(ThreadFacetStamp origin, String name) =>
    ReadScopeIdentity(
      scopeId: '$name-${origin.revision}',
      runtimeEpoch: origin.runtimeEpoch,
      incarnation: origin.incarnation,
      sourceRevision: origin.revision,
    );
ThreadExecutionBaseline selectorExecution({
  ThreadStatus status = ThreadStatus.idle,
  AgentExecution? execution,
  ContinuationView? continuation,
  TurnBrief? active,
  TurnBrief? terminal,
}) => ThreadExecutionBaseline(
  status: status,
  execution: execution,
  continuation: continuation,
  activeTurn: active,
  recentTerminalTurn: terminal,
  interactions: const InteractionIndexHeader(
    reference: InteractionIndexRef(entry: 10, revision: 1),
    total: 0,
    pending: 0,
  ),
  activity: null,
  storage: null,
);

/// Native frames and original read materials only. Values are explicitly
/// declared by tests independently of command replies; no command applies a
/// reducer or normalizes a requested route in this port.
final class SelectorConversationPort implements ConversationObservationPort {
  final facets = FixtureConversationPort();
  ThreadStatus initialStatus = ThreadStatus.idle;
  ThreadExecutionBaseline? initialExecution;
  List<InteractionBrief> indexBriefs = const [];
  final _indexRevisions = <String, int>{};
  bool activeWorkflow = false;
  final routes = <int, ThreadModelRoute>{
    1: const ThreadModelRoute(
      botId: null,
      accountId: 'account-0',
      modelId: 'text',
      effort: 'low',
      revision: 8,
      available: true,
      unavailableReason: null,
    ),
  };
  final reads =
      <
        ({
          String threadId,
          ThreadConfigurationReadRef reference,
          ThreadFacetStamp origin,
        })
      >[];
  final executionRevisions = <String, int>{};
  final configurationRevisions = <String, int>{};
  TurnReadHeader? turn;

  @override
  Future<FeedConnection<ThreadExecutionFrame>> openThreadExecution(
    String threadId, {
    required ThreadObservationMode mode,
  }) async {
    final result = facets.openThreadExecution(threadId, mode: mode);
    final opening = facets.execution.last;
    executionRevisions[opening.feed.feedId] = 1;
    _indexRevisions[opening.feed.feedId] = initialExecution?.interactions.reference.revision ?? 1;
    unawaited(
      opening.feed.listened.future.then(
        (_) => opening.feed.emit(
          ThreadExecutionFrame.data(
            deliverySequence: 1,
            event: ThreadExecutionEvent.baseline(
              identity: selectorFeed(opening, ThreadFacet.execution),
              stamp: selectorFacet(ThreadFacet.execution, 1),
              value: initialExecution ?? selectorExecution(
                status: mode == ThreadObservationMode.cold
                    ? ThreadStatus.closed
                    : initialStatus,
              ),
            ),
          ),
        ),
      ),
    );
    return result;
  }

  @override
  Future<FeedConnection<ThreadConfigurationFrame>> openThreadConfiguration(
    String threadId, {
    required ThreadObservationMode mode,
  }) async {
    final result = facets.openThreadConfiguration(threadId, mode: mode);
    final opening = facets.configuration.last;
    configurationRevisions[opening.feed.feedId] = 1;
    unawaited(
      opening.feed.listened.future.then(
        (_) => opening.feed.emit(
          ThreadConfigurationFrame.data(
            deliverySequence: 1,
            event: ThreadConfigurationEvent.baseline(
              identity: selectorFeed(opening, ThreadFacet.configuration),
              stamp: selectorFacet(ThreadFacet.configuration, 1),
              value: configurationValue(1),
            ),
          ),
        ),
      ),
    );
    return result;
  }

  ThreadConfigurationValue configurationValue(
    int revision, {
    int? modeBindingRevision,
  }) => ThreadConfigurationValue(
    details: ThreadConfigurationReadRef(entry: 12, revision: revision),
    sources: selectorPair.stamp,
    modeRevision: 1,
    modeBindingRevision: modeBindingRevision,
    modelRoute: ModelRouteBrief(
      revision: routes[revision]!.revision,
      available: routes[revision]!.available,
      hasUnavailableReason: routes[revision]!.unavailableReason != null,
    ),
    activeSkillCount: 0,
    activeMcp: ThreadCapabilitySupport.unsupported,
    activeLsp: ThreadCapabilitySupport.unsupported,
    mcpHealth: ThreadCapabilitySupport.unsupported,
  );

  Future<void> publishRoute(
    ThreadModelRoute value, {
    int? modeBindingRevision,
  }) async {
    final opening = facets.configuration.last;
    final revision = configurationRevisions.update(
      opening.feed.feedId,
      (value) => value + 1,
    );
    routes[revision] = value;
    opening.feed.emit(
      ThreadConfigurationFrame.data(
        deliverySequence: revision,
        event: ThreadConfigurationEvent.replace(
          stamp: selectorFacet(ThreadFacet.configuration, revision),
          value: configurationValue(
            revision,
            modeBindingRevision: modeBindingRevision,
          ),
        ),
      ),
    );
    await opening.feed.acknowledged(revision);
  }

  Future<void> publishExecution(ThreadExecutionBaseline value) async {
    final opening = facets.execution.last;
    final revision = executionRevisions.update(
      opening.feed.feedId,
      (value) => value + 1,
    );
    opening.feed.emit(
      ThreadExecutionFrame.data(
        deliverySequence: revision,
        event: ThreadExecutionEvent.change(
          stamp: selectorFacet(ThreadFacet.execution, revision),
          baseRevision: revision - 1,
          value: ThreadExecutionChange(
            status: value.status,
            execution: ExecutionReplacement.replace(value: value.execution),
            continuation: ContinuationReplacement.replace(value: value.continuation),
            turns: TurnsReplacement(
              activeTurn: value.activeTurn,
              recentTerminalTurn: value.recentTerminalTurn,
            ),
            interactions: null,
            activity: const ActivityReplacement.unchanged(),
            storage: const StorageReplacement.unchanged(),
          ),
        ),
      ),
    );
    await opening.feed.acknowledged(revision);
  }

  Future<void> publishInteractionIndex(List<InteractionBrief> entries) async {
    final opening = facets.execution.last;
    final previous = executionRevisions[opening.feed.feedId]!;
    final revision = previous + 1;
    executionRevisions[opening.feed.feedId] = revision;
    final previousIndex = _indexRevisions[opening.feed.feedId]!;
    final indexRevision = previousIndex + 1;
    _indexRevisions[opening.feed.feedId] = indexRevision;
    final removed = [for (final previous in indexBriefs)
      if (!entries.any((entry) => entry.reference.entry == previous.reference.entry)) previous.reference.entry];
    indexBriefs = List.unmodifiable(entries);
    opening.feed.emit(ThreadExecutionFrame.data(
      deliverySequence: revision,
      event: ThreadExecutionEvent.change(
        stamp: selectorFacet(ThreadFacet.execution, revision), baseRevision: previous,
        value: ThreadExecutionChange(status: null, turns: null,
          interactions: InteractionDelta(baseIndexRevision: previousIndex,
            index: InteractionIndexHeader(reference: InteractionIndexRef(entry: 10, revision: indexRevision), total: entries.length, pending: entries.where((entry) => entry.status == InteractionStatus.pending).length),
            upserted: entries, removedEntries: removed, terminalFacts: const []),
          activity: const ActivityReplacement.unchanged(), storage: const StorageReplacement.unchanged()),
      ),
    ));
    await opening.feed.acknowledged(revision);
  }

  @override
  Future<FeedConnection<ThreadAuthoringFrame>> openThreadAuthoring(
    String threadId, {
    required ThreadObservationMode mode,
  }) async {
    final result = facets.openThreadAuthoring(threadId, mode: mode);
    final opening = facets.authoring.last;
    unawaited(
      opening.feed.listened.future.then(
        (_) => opening.feed.emit(
          ThreadAuthoringFrame.data(
            deliverySequence: 1,
            event: ThreadAuthoringEvent.baseline(
              identity: selectorFeed(opening, ThreadFacet.authoring),
              stamp: selectorFacet(ThreadFacet.authoring, 1),
              value: ThreadAuthoringBaseline(
                todo: null,
                plan: null,
                workflow: activeWorkflow
                    ? const WorkflowBrief(
                        reference: WorkflowReadRef(entry: 20, revision: 1),
                        revision: 1,
                        hasCurrentRun: true,
                        lifecycle: WorkflowLifecycle.active,
                        modeDeleted: false,
                      )
                    : null,
                progress: ThreadCapabilitySupport.unsupported,
              ),
            ),
          ),
        ),
      ),
    );
    return result;
  }

  @override
  Future<FeedConnection<ThreadMetricsFrame>> openThreadMetrics(
    String threadId, {
    required ThreadObservationMode mode,
  }) => facets.openThreadMetrics(threadId, mode: mode);
  @override
  Future<FeedConnection<ThreadContextFrame>> openThreadContext(
    String threadId, {
    required ThreadObservationMode mode,
  }) => facets.openThreadContext(threadId, mode: mode);
  @override
  Future<ThreadConfigurationReadConnection> openThreadConfigurationRead(
    String threadId,
    ThreadConfigurationReadRef reference, {
    required ThreadFacetStamp origin,
  }) async {
    reads.add((threadId: threadId, reference: reference, origin: origin));
    return _ConfigurationPin(
      selectorScope(origin, 'route'),
      routes[reference.revision]!,
    );
  }

  @override
  Future<WorkflowReadConnection> openWorkflowRead(
    String threadId,
    WorkflowReadRef reference, {
    required ThreadFacetStamp origin,
  }) async => _WorkflowPin(selectorScope(origin, 'workflow'));
  @override
  Future<InteractionIndexReadConnection> openInteractionIndexRead(
    String threadId,
    InteractionIndexRef reference, {
    required ThreadFacetStamp origin,
  }) {
    final scripted = facets.interactionIndexOpen;
    if (scripted != null) return scripted(threadId, reference, origin);
    return Future.value(_IndexPin(selectorScope(origin, 'interactions').copyWith(sourceRevision: reference.revision), indexBriefs));
  }
  @override
  Future<InteractionReadRef> resolveInteractionReadRef(String threadId, String interactionId, {required int revision, required ThreadFacetStamp origin}) => facets.resolveInteractionReadRef(threadId, interactionId, revision: revision, origin: origin);
  @override
  Future<InteractionReadConnection> openInteractionRead(
    String threadId, InteractionReadRef reference, {required ThreadFacetStamp origin}
  ) => facets.openInteractionRead(threadId, reference, origin: origin);
  @override
  Future<TurnReadConnection> openTurnRead(
    String threadId,
    TurnReadRef reference, {
    required ThreadFacetStamp origin,
  }) async => _TurnPin(turn!);
  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted selector facet read: ${invocation.memberName}',
  );
}

final class SelectorRouteCall {
  SelectorRouteCall(
    this.threadId,
    this.operationId,
    this.selection,
    this.routeRevision,
    this.settingsRevision,
  );
  final String threadId;
  final OperationId operationId;
  final ModelSelection selection;
  final int routeRevision;
  final int settingsRevision;
  final reply = Completer<ThreadModelRouteCommandReply>();
}

final class SelectorModeCall {
  SelectorModeCall(this.threadId, this.mode, this.operationId);
  final String threadId, mode;
  final OperationId operationId;
  final reply = Completer<CommitReceipt>();
}

final class SelectorCommands extends UnscriptedConversationCommands {
  final routes = DraftCalls<SelectorRouteCall>();
  final modes = DraftCalls<SelectorModeCall>();
  final prompts = DraftCalls<DraftPromptCall>();
  final acceptances = DraftCalls<DraftAcceptanceCall>();
  final interrupts =
      DraftCalls<
        ({
          String threadId,
          String executionId,
          OperationId operationId,
          Completer<StopExecutionReply> reply,
        })
      >();
  @override
  Future<StopExecutionReply> stopExecution(
    String threadId,
    String executionId, {
    required OperationId operationId,
  }) {
    final reply = Completer<StopExecutionReply>();
    interrupts.add((
      threadId: threadId,
      executionId: executionId,
      operationId: operationId,
      reply: reply,
    ));
    return reply.future;
  }

  final continues = DraftCalls<SelectorContinueCall>();
  final continuationReads = DraftCalls<SelectorContinuationRead>();
  Future<ContinuationOperationView?> Function(String, OperationId)? continuationQuery;

  @override
  Future<ContinueThreadReply> continueThread(
    String threadId, {
    required OperationId operationId,
    required String expectedContinuationId,
    required int expectedModelRouteRevision,
  }) {
    final call = SelectorContinueCall(
      threadId, operationId, expectedContinuationId, expectedModelRouteRevision,
    );
    continues.add(call);
    return call.reply.future;
  }

  @override
  Future<ContinuationOperationView?> readContinuationOperation(
    String threadId,
    OperationId operationId,
  ) {
    if (continuationQuery case final query?) return query(threadId, operationId);
    final call = SelectorContinuationRead(threadId, operationId);
    continuationReads.add(call);
    return call.reply.future;
  }

  @override
  Future<SubmitPromptReceipt> submitPrompt(
    String threadId,
    StudioPromptInput input, {
    required int expectedModelRouteRevision,
  }) {
    final call = DraftPromptCall(threadId, input, expectedModelRouteRevision);
    prompts.add(call);
    return call.reply.future;
  }

  @override
  Future<InputAcceptanceEvidence?> readInputAcceptance(
    String threadId,
    String inputId,
  ) {
    final call = DraftAcceptanceCall(threadId, inputId);
    acceptances.add(call);
    return call.reply.future;
  }

  @override
  Future<ThreadModelRouteCommandReply> setThreadModelRoute(
    String threadId, {
    required OperationId operationId,
    required String accountId,
    required String modelId,
    required String? effort,
    required int expectedModelRouteRevision,
    required int expectedSettingsRevision,
  }) {
    final call = SelectorRouteCall(
      threadId,
      operationId,
      ModelSelection(
        model: AccountModelKey(accountId: accountId, modelId: modelId),
        effort: effort,
      ),
      expectedModelRouteRevision,
      expectedSettingsRevision,
    );
    routes.add(call);
    return call.reply.future;
  }

  @override
  Future<CommitReceipt> setThreadMode(
    String threadId,
    String mode, {
    required OperationId operationId,
  }) {
    final call = SelectorModeCall(threadId, mode, operationId);
    modes.add(call);
    return call.reply.future;
  }
}

final class SelectorContinueCall {
  SelectorContinueCall(this.threadId, this.operationId, this.continuationId, this.routeRevision);
  final String threadId;
  final OperationId operationId;
  final String continuationId;
  final int routeRevision;
  final reply = Completer<ContinueThreadReply>();
}

final class SelectorContinuationRead {
  SelectorContinuationRead(this.threadId, this.operationId);
  final String threadId;
  final OperationId operationId;
  final reply = Completer<ContinuationOperationView?>();
}

final class _ConfigurationPin extends ProfileNativePin
    implements ThreadConfigurationReadConnection {
  _ConfigurationPin(this.scope, this.route) : super(scope.scopeId);
  final ReadScopeIdentity scope;
  final ThreadModelRoute route;
  @override
  Future<ThreadConfigurationReadHeader> header() async =>
      ThreadConfigurationReadHeader(
        scope: scope,
        activeSkillCount: 0,
        route: ModelRouteReadValue(
          botId: null,
          accountId: ReadText.inline(text: route.accountId),
          modelId: ReadText.inline(text: route.modelId),
          effort: route.effort == null
              ? null
              : ReadText.inline(text: route.effort!),
          revision: route.revision,
          available: route.available,
          unavailableReason: null,
        ),
      );
  @override
  Future<SkillNamePage> activeSkills({int offset = 0, int limit = 32}) async =>
      SkillNamePage(
        scope: scope,
        offset: offset,
        total: 0,
        items: const [],
        nextOffset: null,
      );
}

final class _WorkflowPin extends ProfileNativePin
    implements WorkflowReadConnection {
  _WorkflowPin(this.scope) : super(scope.scopeId);
  final ReadScopeIdentity scope;
  @override
  Future<WorkflowReadHeader> header() async => WorkflowReadHeader(
    scope: scope,
    revision: 1,
    currentRun: const WorkflowRunReadValue(
      lineageId: ReadText.inline(text: 'selector-lineage'),
      runId: ReadText.inline(text: 'selector-run'),
      modeId: ReadText.inline(text: 'mode.task'),
      graphRevision: 1,
      graphHash: ReadText.inline(text: 'selector-graph'),
      lifecycle: WorkflowLifecycle.active,
      currentStateId: ReadText.inline(text: 'implement'),
      currentStateTitle: ReadText.inline(text: '实现'),
      modeDisplayName: ReadText.inline(text: '任务'),
      modeDeleted: false,
      startedAt: 1,
      updatedAt: 1,
    ),
  );
}

final class _IndexPin extends ProfileNativePin
    implements InteractionIndexReadConnection {
  _IndexPin(this.scope, this.briefs) : super(scope.scopeId);
  final ReadScopeIdentity scope;
  final List<InteractionBrief> briefs;
  @override
  Future<InteractionIndexReadHeader> header() async =>
      InteractionIndexReadHeader(scope: scope, total: briefs.length, pending: briefs.where((brief) => brief.status == InteractionStatus.pending).length);
  @override
  Future<InteractionBriefPage> entries({
    int offset = 0,
    int limit = 32,
  }) async => InteractionBriefPage(
    scope: scope,
    offset: offset,
    total: briefs.length,
    items: briefs.skip(offset).take(limit).toList(),
    nextOffset: null,
  );
}

final class _TurnPin extends ProfileNativePin implements TurnReadConnection {
  _TurnPin(this.value) : super(value.scope.scopeId);
  final TurnReadHeader value;
  @override
  Future<TurnReadHeader> header() async => value;
}
