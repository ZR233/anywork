import 'package:freezed_annotation/freezed_annotation.dart';

import 'authoring_values.dart';
import 'configuration_values.dart';
import 'context_values.dart';
import 'metrics_values.dart';

part 'thread_runtime_snapshot.freezed.dart';

/// The complete runtime evidence returned by a command, without feed identity.
/// It is never promoted to a current facet by inventing an epoch or read ref.
@Freezed(toStringOverride: false)
final class ThreadRuntimeSnapshot with _$ThreadRuntimeSnapshot {
  ThreadRuntimeSnapshot({
    required this.threadId,
    required this.modelRoute,
    required this.usage,
    required this.liveUsage,
    required this.turnCompletionTokens,
    required this.turnResponseMillis,
    required this.todo,
    required List<String> activeSkills,
    required List<String> activeMcpServers,
    required List<String> activeLspServers,
    required this.progress,
    required this.mcpHealth,
    required this.workflow,
    required this.plan,
    required this.updatedAt,
  }) : activeSkills = List.unmodifiable(activeSkills),
       activeMcpServers = List.unmodifiable(activeMcpServers),
       activeLspServers = List.unmodifiable(activeLspServers);
  final String threadId;
  final ThreadModelRoute? modelRoute;
  final ThreadRuntimeUsage usage;
  final ThreadRuntimeLiveUsage? liveUsage;
  final int turnCompletionTokens;
  final int turnResponseMillis;
  final ThreadTodoSnapshot? todo;
  final List<String> activeSkills;
  final List<String> activeMcpServers;
  final List<String> activeLspServers;
  final String? progress;
  final ThreadMcpHealthSnapshot? mcpHealth;
  final ThreadWorkflowSnapshot? workflow;
  final ThreadPlanSnapshot? plan;
  final int updatedAt;
}

@Freezed(toStringOverride: false)
final class ThreadRuntimeUsage with _$ThreadRuntimeUsage {
  ThreadRuntimeUsage({
    required this.hasIncompleteUsage,
    required this.modelId,
    required this.contextWindow,
    required this.maxContextWindow,
    required this.autoCompactLimit,
    required this.latestContextTokens,
    required this.promptTokens,
    required this.completionTokens,
    required this.cachedPromptTokens,
    required this.cacheWriteTokens,
    required this.reasoningTokens,
    required this.inferenceCount,
    required this.totalTokens,
    required this.cacheUsage,
    required List<ThreadRuntimeCost> estimatedCosts,
    required List<ThreadRuntimeCost> estimatedCacheSavings,
    required this.hasUnpricedUsage,
    required this.promptGeneration,
    required this.promptCachePolicy,
    required this.prefixChangedReason,
    required this.updatedAt,
  }) : estimatedCosts = List.unmodifiable(estimatedCosts),
       estimatedCacheSavings = List.unmodifiable(estimatedCacheSavings);
  final bool hasIncompleteUsage;
  final String modelId;
  final int? contextWindow;
  final int? maxContextWindow;
  final int? autoCompactLimit;
  final int latestContextTokens;
  final int promptTokens;
  final int completionTokens;
  final int cachedPromptTokens;
  final int cacheWriteTokens;
  final int reasoningTokens;
  final int inferenceCount;
  final int totalTokens;
  final CacheUsageSummary cacheUsage;
  final List<ThreadRuntimeCost> estimatedCosts;
  final List<ThreadRuntimeCost> estimatedCacheSavings;
  final bool hasUnpricedUsage;
  final int? promptGeneration;
  final String? promptCachePolicy;
  final PromptPrefixChangedReason? prefixChangedReason;
  final int updatedAt;
}

@Freezed(toStringOverride: false)
final class ThreadRuntimeCost with _$ThreadRuntimeCost {
  const ThreadRuntimeCost({required this.currency, required this.amount});
  final String currency;
  final double amount;
}

@Freezed(toStringOverride: false)
final class ThreadRuntimeLiveUsage with _$ThreadRuntimeLiveUsage {
  const ThreadRuntimeLiveUsage({
    required this.turnId,
    required this.attemptId,
    required this.completionTokens,
    required this.responseMillis,
    required this.latestContextTokens,
    required this.state,
    required this.observationSequence,
  });
  final String turnId;
  final String attemptId;
  final int? completionTokens;
  final int? responseMillis;
  final int? latestContextTokens;
  final TurnObservationState state;
  final int observationSequence;
}

@Freezed(toStringOverride: false)
final class ThreadTodoSnapshot with _$ThreadTodoSnapshot {
  ThreadTodoSnapshot({
    required this.callId,
    required this.agentId,
    required this.path,
    required this.parentPath,
    required this.explanation,
    required List<ThreadTodoItem> items,
  }) : items = List.unmodifiable(items);
  final String callId;
  final String? agentId;
  final String? path;
  final String? parentPath;
  final String? explanation;
  final List<ThreadTodoItem> items;
}

@Freezed(toStringOverride: false)
final class ThreadTodoItem with _$ThreadTodoItem {
  const ThreadTodoItem({required this.step, required this.status});
  final String step;
  final TodoItemStatus status;
}

@Freezed(toStringOverride: false)
final class ThreadMcpHealthSnapshot with _$ThreadMcpHealthSnapshot {
  ThreadMcpHealthSnapshot({
    required this.generation,
    required List<ThreadMcpAvailability> servers,
  }) : servers = List.unmodifiable(servers);
  final int generation;
  final List<ThreadMcpAvailability> servers;
}

@Freezed(toStringOverride: false)
final class ThreadMcpAvailability with _$ThreadMcpAvailability {
  const ThreadMcpAvailability({
    required this.server,
    required this.availability,
    required this.message,
    required this.lastCheckedAt,
    required this.toolCount,
  });
  final ThreadMcpServer server;
  final String availability;
  final String? message;
  final int? lastCheckedAt;
  final int? toolCount;
}

@Freezed(toStringOverride: false)
final class ThreadMcpServer with _$ThreadMcpServer {
  const ThreadMcpServer({
    required this.id,
    required this.source,
    required this.transport,
    required this.endpoint,
    required this.builtIn,
  });
  final String id;
  final String source;
  final String transport;
  final String endpoint;
  final bool builtIn;
}

@Freezed(toStringOverride: false)
final class ThreadWorkflowSnapshot with _$ThreadWorkflowSnapshot {
  const ThreadWorkflowSnapshot({
    required this.revision,
    required this.currentRun,
  });
  final int revision;
  final ThreadWorkflowRun? currentRun;
}

@Freezed(toStringOverride: false)
final class ThreadWorkflowRun with _$ThreadWorkflowRun {
  const ThreadWorkflowRun({
    required this.lineageId,
    required this.runId,
    required this.modeId,
    required this.graphRevision,
    required this.graphHash,
    required this.lifecycle,
    required this.currentStateId,
    required this.startedAt,
    required this.updatedAt,
    required this.currentStateTitle,
    required this.modeDisplayName,
    required this.modeDeleted,
  });
  final String lineageId;
  final String runId;
  final String modeId;
  final int graphRevision;
  final String graphHash;
  final WorkflowLifecycle lifecycle;
  final String currentStateId;
  final int startedAt;
  final int updatedAt;
  final String currentStateTitle;
  final String modeDisplayName;
  final bool modeDeleted;
}

@Freezed(toStringOverride: false)
final class ThreadPlanSnapshot with _$ThreadPlanSnapshot {
  const ThreadPlanSnapshot({
    required this.revision,
    required this.state,
    required this.document,
    required this.updatedAt,
  });
  final int revision;
  final PlanPhase state;
  final ThreadPlanDocument? document;
  final int updatedAt;
}

@Freezed(toStringOverride: false)
final class ThreadPlanDocument with _$ThreadPlanDocument {
  const ThreadPlanDocument({
    required this.version,
    required this.markdown,
    required this.contentHash,
  });
  final int version;
  final String markdown;
  final String contentHash;
}
