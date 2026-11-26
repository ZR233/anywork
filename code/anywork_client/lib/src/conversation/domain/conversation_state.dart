import '../../../models.dart';
import '../../studio/stores/domain_sync.dart';

/// Read-only session metadata; no timeline, read scope or revision reducer.
class ThreadSessionState {
  const ThreadSessionState({
    required this.threadId,
    this.meta,
    this.directoryRow,
    this.sync = const DomainSyncStatus(),
  });
  final String threadId;
  final SessionMetaSnapshot? meta;
  final SessionDirectoryRow? directoryRow;
  final DomainSyncStatus sync;
  bool get hasSnapshot => meta != null;
  bool get hasInteractionBaseline => hasSnapshot;
  int get revision => meta?.revision ?? 0;
  ThreadRuntimeView? get runtime => _projectRuntime(meta?.runtime);
  ThreadModelRouteView? get modelRoute => meta?.modelRoute;
  WorkflowRuntimeView? get workflow => runtime?.workflow;
  StudioTurnView? get activeTurn => meta?.activeTurn;
  StudioTurnView? get lastTurn => meta?.lastTurn;
  List<PendingInteraction> get interactions => meta?.interactions ?? const [];
  ThreadActivityView? get activity => meta?.activity;
  ThreadStorageStateView? get storage => meta?.storageState;

  /// Command context combines canonical directory identity and feed metadata.
  ThreadWorkspace? get workspace {
    final row = directoryRow;
    final value = meta;
    if (row == null || value == null || row.backend is! NativeAgentBackendView)
      return null;
    final thread = StudioThread(
      id: row.threadId,
      workspaceId: row.workspaceId,
      title: value.title ?? row.title,
      mode: value.mode,
      delegationMode: row.delegationMode,
      delegationPreference: row.delegationPreference,
      updatedAt: row.updatedAt,
      createdAt: row.createdAt,
      lastUserMessageAt: row.lastUserMessageAt,
      parentThreadId: value.parentThreadId,
      rootThreadId: value.rootThreadId,
      role: row.role,
      frozenModel: row.frozenModel,
      status: value.status,
      archived: row.archived,
      workspaceMode: row.workspaceMode,
      workspacePath: row.workspacePath,
    );
    final currentRuntime = runtime;
    if (currentRuntime == null) return null;
    return ThreadWorkspace(
      thread: thread,
      revision: value.revision,
      interactions: value.interactions,
      runtime: currentRuntime,
      modelRoute: value.modelRoute,
      activeTurn: value.activeTurn,
      latestTurn: value.lastTurn,
      todo: value.runtime?.todo,
      activity: value.activity,
      storage: value.storageState,
    );
  }

  ThreadSessionState copyWith({
    SessionMetaSnapshot? meta,
    Object? directoryRow = _unset,
    DomainSyncStatus? sync,
  }) => ThreadSessionState(
    threadId: threadId,
    meta: meta ?? this.meta,
    directoryRow: identical(directoryRow, _unset)
        ? this.directoryRow
        : directoryRow as SessionDirectoryRow?,
    sync: sync ?? this.sync,
  );
}

const _unset = Object();

ThreadRuntimeView? _projectRuntime(ConversationRuntimeSnapshot? snapshot) {
  if (snapshot == null) return null;
  final usage = snapshot.usage;
  return ThreadRuntimeView(
    modelId: usage.modelId,
    usageDiagnostics: usage.diagnostics,
    contextTokens: usage.latestContextTokens,
    contextWindow: usage.contextWindow ?? 0,
    maxContextWindow: usage.maxContextWindow,
    autoCompactLimit: usage.autoCompactLimit,
    totalTokens: usage.totalTokens,
    promptTokens: usage.promptTokens,
    completionTokens: usage.completionTokens,
    cachedPromptTokens: usage.cachedPromptTokens,
    cacheWriteTokens: usage.cacheWriteTokens,
    reasoningTokens: usage.reasoningTokens,
    inferenceCount: usage.inferenceCount,
    cacheUsage: usage.cacheUsage,
    costLabel: formatRuntimeCosts(usage.estimatedCosts),
    estimatedCosts: usage.estimatedCosts,
    estimatedCacheSavings: usage.estimatedCacheSavings,
    hasUnpricedUsage: usage.hasUnpricedUsage,
    hasIncompleteUsage: usage.hasIncompleteUsage,
    promptGeneration: usage.promptGeneration,
    promptCachePolicy: usage.promptCachePolicy,
    prefixChangedReason: usage.prefixChangedReason?.name,
    activeSkills: snapshot.activeSkills,
    activeMcpServers: snapshot.activeMcpServers,
    activeLspServers: snapshot.activeLspServers,
    turnCompletionTokens: snapshot.turnCompletionTokens,
    turnResponseMillis: snapshot.turnResponseMillis,
    liveUsage: snapshot.liveUsage,
    deferred: snapshot.deferred,
    workflow: snapshot.workflow,
    plan: snapshot.plan,
    execution: snapshot.execution,
    continuation: snapshot.continuation,
  );
}
