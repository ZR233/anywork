import 'dart:async';

import 'package:anywork_client/lifecycle.dart';
import 'package:anywork_client/studio_client.dart';

import 'directory_feed.dart';
import 'product_topic_owner.dart';

ThreadWorkspace emptyConversationWorkspace(String threadId) => ThreadWorkspace(
  thread: StudioThread(
    id: threadId,
    workspaceId: 'workspace',
    title: 'Thread',
    mode: ThreadModeId.auto,
    delegationMode: DelegationMode.profile,
    delegationPreference: DelegationPreference.balanced,
    updatedAt: DateTime.utc(2026),
    workspacePath: '/workspace',
  ),
  revision: 0,
  interactions: const [],
  runtime: const ThreadRuntimeView(
    modelId: 'model',
    contextTokens: 0,
    contextWindow: 1,
    totalTokens: 0,
    costLabel: '',
    activeSkills: [],
    activeMcpServers: [],
    activeLspServers: [],
  ),
);

SessionUsageSummary emptySessionUsage() => SessionUsageSummary(
  appliedSequence: 0,
  totals: const SessionUsageTotals(
    inferenceCount: 0,
    promptTokens: 0,
    completionTokens: 0,
    cachedPromptTokens: 0,
    cacheWriteTokens: 0,
    reasoningTokens: 0,
    totalTokens: 0,
  ),
  cache: const SessionUsageCache(
    inputTokens: 0,
    readTokens: 0,
    sampleCount: 0,
    incomplete: false,
  ),
  context: const SessionUsageContext(tokens: 0),
  throughput: const SessionUsageThroughput(
    turnId: '',
    completionTokens: 0,
    responseMillis: 0,
  ),
  diagnostics: SessionUsageDiagnostics(
    incompleteCalls: 0,
    missingCalls: 0,
    partialCalls: 0,
    invalidCalls: 0,
    overflowCalls: 0,
    byOutcome: [],
    byPurpose: [],
    otherPurposeCalls: 0,
    byIssue: [],
    recentGaps: [],
    legacyUnknown: false,
    legacyIncomplete: false,
    countsOverflowed: false,
  ),
  pricing: SessionUsagePricing(
    incomplete: false,
    estimatedCosts: [],
    estimatedCacheSavings: [],
  ),
);

SessionMetaSnapshot sessionMetaForWorkspace(ThreadWorkspace workspace) =>
    SessionMetaSnapshot(
      threadId: workspace.thread.id,
      status: workspace.thread.status,
      title: workspace.thread.title,
      parentThreadId: workspace.thread.parentThreadId,
      rootThreadId: workspace.thread.rootThreadId,
      ownerEpoch: 'owner',
      revision: workspace.revision,
      activeTurn: workspace.activeTurn,
      lastTurn: workspace.lastTurn,
      activity: workspace.activity,
      usage: emptySessionUsage(),
      contextMetrics: usageForRuntime(workspace.runtime),
      modelRoute: workspace.modelRoute,
      runtime: snapshotForWorkspace(workspace),
      storageState: workspace.storage,
      interactions: workspace.interactions,
      pendingInteractionCount: workspace.interactions.length,
      plan: workspace.runtime.plan,
      mode: workspace.thread.mode,
      executionPresent: workspace.runtime.execution != null,
    );

class TestConversationFeed implements ConversationFeedHandle {
  TestConversationFeed({
    this.threadId = 'thread',
    SessionMetaSnapshot? initialMeta,
  }) : sessionMetaSnapshot =
           initialMeta ??
           sessionMetaForWorkspace(emptyConversationWorkspace(threadId));
  @override
  final String threadId;
  @override
  SessionMetaSnapshot sessionMetaSnapshot;
  @override
  LiveStatusSnapshot liveStatusSnapshot = LiveStatusSnapshot(
    revision: 0,
    phase: const LiveStatusIdle(),
    attentions: [],
    suppressedByInteraction: false,
  );
  final controller = StreamController<ConversationFeedEvent>();
  final requestCloseStarted = Completer<void>();
  final closeStarted = Completer<void>();
  final closeCompleted = Completer<void>();
  Completer<void>? closeGate;
  Object? closeFailure;
  int closeCalls = 0;
  int requestCloseCalls = 0;
  @override
  Stream<ConversationFeedEvent> get events => controller.stream;
  void send(ConversationFeedEvent event) {
    if (requestCloseStarted.isCompleted) return;
    if (event case ConversationSessionMeta(:final snapshot))
      sessionMetaSnapshot = snapshot;
    if (event case ConversationLiveStatus(:final snapshot))
      liveStatusSnapshot = snapshot;
    controller.add(event);
  }

  void sendError(Object error) => controller.addError(error);
  Future<void> deliver(ConversationFeedEvent event) async {
    send(event);
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Future<TimelinePatch> loadOlder({
    required String cursor,
    int limit = 50,
  }) async => TimelinePrependOlder(items: [], hasMoreOlder: false);
  @override
  Future<List<WorkGroupMember>> loadWorkGroupMembers({
    int? afterSeq,
    int? beforeSeq,
  }) async => const [];
  @override
  Future<BodyWindow> readBodyWindow({
    required BodyRef reference,
    required int offset,
    required int maxBytes,
  }) async => BodyWindow(
    offset: offset,
    text: '',
    totalBytes: reference.byteLength,
    eof: true,
  );
  Future<SessionDetailWindow> Function({
    required SessionDetailKind kind,
    required int offset,
    required int maxBytes,
  })?
  onReadSessionDetail;
  @override
  Future<SessionDetailWindow> readSessionDetail({
    required SessionDetailKind kind,
    required int offset,
    required int maxBytes,
  }) {
    final read = onReadSessionDetail;
    if (read == null) {
      return Future.error(
        UnsupportedError('Session detail $kind was not scripted'),
      );
    }
    return read(kind: kind, offset: offset, maxBytes: maxBytes);
  }

  @override
  Future<TimelinePatch> resetToLatest({int limit = 50}) async {
    final patch = TimelineReset(items: [], hasMoreOlder: false, revision: 0);
    send(ConversationTimeline(patch: patch));
    return patch;
  }

  @override
  void requestClose() {
    requestCloseCalls++;
    if (!requestCloseStarted.isCompleted) requestCloseStarted.complete();
  }

  @override
  Future<void> close() async {
    closeCalls++;
    requestClose();
    if (!closeStarted.isCompleted) closeStarted.complete();
    await closeGate?.future;
    if (closeFailure case final failure?) throw failure;
    // Unlistened streams have no consumer to join.
    unawaited(controller.close());
    if (!closeCompleted.isCompleted) closeCompleted.complete();
  }
}

class TestConversationTransport extends StudioTransport
    with DirectoryFeedFixture {
  TestConversationFeed Function(String threadId, int index)? feedFactory;
  final List<
    ({
      String threadId,
      int initialLimit,
      Completer<ConversationFeedHandle> result,
    })
  >
  feedOpens = [];
  final Map<int, Completer<void>> _feedOpening = {};
  final List<ProductTopic> productTopics = [];
  final List<TestProductTopicOwner> productTopicOwners = [];
  final Map<ProductTopic, Completer<void>> _topicOpening = {};
  final Map<ProductTopic, StreamController<ProductTopicFrame>> _topicStreams =
      {};
  @override
  Future<ConversationFeedHandle> openConversationFeed(
    String threadId, {
    int initialLimit = 50,
  }) {
    final result = Completer<ConversationFeedHandle>();
    final index = feedOpens.length;
    feedOpens.add((
      threadId: threadId,
      initialLimit: initialLimit,
      result: result,
    ));
    _feedOpening.remove(index)?.complete();
    final factory = feedFactory;
    if (factory != null) {
      try {
        result.complete(factory(threadId, index));
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    }
    return result.future;
  }

  Future<void> feedOpened(int index) => feedOpens.length > index
      ? Future.value()
      : (_feedOpening[index] ??= Completer<void>()).future;
  Future<void> productTopicOpened(ProductTopic topic) =>
      _topicStreams.containsKey(topic)
      ? Future.value()
      : (_topicOpening[topic] ??= Completer<void>()).future;

  @override
  Future<ProductTopicObservation> openProductTopic(
    ProductTopic topic, {
    required ClientResourceId resourceId,
  }) async {
    productTopics.add(topic);
    final stream = StreamController<ProductTopicFrame>();
    stream.onCancel = () {
      unawaited(stream.close());
    };
    _topicStreams[topic] = stream;
    final observation = await openTestProductTopic(
      lifecycleScope.child('topic-owner'),
      resourceId,
      stream,
    );
    productTopicOwners.add(observation.source);
    _topicOpening.remove(topic)?.complete();
    return observation;
  }

  void emitProductTopicFrame(ProductTopicFrame frame) {
    final topic = switch (frame) {
      ProductTopicBaselineFrame(:final topic) => topic,
      ProductTopicDataFrame(:final topic) => topic,
      ProductTopicLaggedFrame(:final topic) => topic,
      ProductTopicFailureFrame(:final topic) => topic,
    };
    _topicStreams[topic]?.add(frame);
  }

  Future<CloseReport> closeProductTopicStreams({
    required ClientCloseBudget budget,
  }) async {
    // The scope owns each actual topic source and its cleanup ACK. Awaiting a
    // second close() on a never-listened controller would never complete.
    final report = await lifecycleScope.close(budget: budget);
    if (report.complete) _topicStreams.clear();
    return report;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted transport capability: ${invocation.memberName}',
  );
}

ConversationRuntimeUsage usageForRuntime(ThreadRuntimeView usage) =>
    ConversationRuntimeUsage(
      diagnostics: usage.usageDiagnostics,
      hasIncompleteUsage: usage.hasIncompleteUsage,
      modelId: usage.modelId,
      contextWindow: usage.contextWindow,
      maxContextWindow: usage.maxContextWindow,
      autoCompactLimit: usage.autoCompactLimit,
      latestContextTokens: usage.contextTokens,
      promptTokens: usage.promptTokens,
      completionTokens: usage.completionTokens,
      cachedPromptTokens: usage.cachedPromptTokens,
      cacheWriteTokens: usage.cacheWriteTokens,
      reasoningTokens: usage.reasoningTokens,
      inferenceCount: usage.inferenceCount,
      totalTokens: usage.totalTokens,
      cacheUsage: usage.cacheUsage,
      estimatedCosts: usage.estimatedCosts,
      estimatedCacheSavings: usage.estimatedCacheSavings,
      hasUnpricedUsage: usage.hasUnpricedUsage,
      promptGeneration: usage.promptGeneration,
      promptCachePolicy: usage.promptCachePolicy,
      prefixChangedReason: null,
      updatedAt: 0,
    );

ConversationRuntimeSnapshot snapshotForWorkspace(ThreadWorkspace workspace) {
  final runtime = workspace.runtime;
  return ConversationRuntimeSnapshot(
    threadId: workspace.thread.id,
    deferred: runtime.deferred,
    usage: usageForRuntime(runtime),
    liveUsage: runtime.liveUsage,
    turnCompletionTokens: runtime.turnCompletionTokens,
    turnResponseMillis: runtime.turnResponseMillis,
    todo: workspace.todo,
    activeSkills: runtime.activeSkills,
    activeMcpServers: runtime.activeMcpServers,
    activeLspServers: runtime.activeLspServers,
    workflow: runtime.workflow,
    plan: runtime.plan,
    execution: runtime.execution,
    continuation: runtime.continuation,
    updatedAt: 0,
  );
}
