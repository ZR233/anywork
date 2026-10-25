import 'package:anywork_client/conversation.dart';

import '../../../rust/api/studio/types/thread_stream.dart' as native;
import '../products/models/numeric_values.dart';
import '../shared/exact_numbers.dart';
import '../shared/read_converters.dart';
import 'scalar_converters.dart';

ThreadRuntimeSnapshot commandRuntimeFromBridge(
  native.BridgeThreadRuntimeSnapshot value,
) => ThreadRuntimeSnapshot(
  threadId: value.threadId,
  modelRoute: value.modelRoute == null
      ? null
      : ThreadModelRoute(
          botId: value.modelRoute!.botId,
          accountId: value.modelRoute!.accountId,
          modelId: value.modelRoute!.modelId,
          effort: value.modelRoute!.effort,
          revision: exactU64(
            value.modelRoute!.revision,
            'command model route revision',
          ),
          available: value.modelRoute!.available,
          unavailableReason: value.modelRoute!.unavailableReason,
        ),
  usage: commandUsageFromBridge(value.usage),
  liveUsage: value.liveUsage == null
      ? null
      : ThreadRuntimeLiveUsage(
          turnId: value.liveUsage!.turnId,
          attemptId: value.liveUsage!.attemptId,
          completionTokens: nullableU64(
            value.liveUsage!.completionTokens,
            'command live completion tokens',
          ),
          responseMillis: nullableU64(
            value.liveUsage!.responseMillis,
            'command live response milliseconds',
          ),
          latestContextTokens: nullableU64(
            value.liveUsage!.latestContextTokens,
            'command live context tokens',
          ),
          state: observationStateFromBridge(value.liveUsage!.state),
          observationSequence: exactU64(
            value.liveUsage!.observationSequence,
            'command observation sequence',
          ),
        ),
  turnCompletionTokens: exactU64(
    value.turnCompletionTokens,
    'command Turn completion tokens',
  ),
  turnResponseMillis: exactU64(
    value.turnResponseMillis,
    'command Turn response milliseconds',
  ),
  todo: value.todo == null
      ? null
      : ThreadTodoSnapshot(
          callId: value.todo!.callId,
          agentId: value.todo!.agentId,
          path: value.todo!.path,
          parentPath: value.todo!.parentPath,
          explanation: value.todo!.explanation,
          items: [
            for (final item in value.todo!.items)
              ThreadTodoItem(
                step: item.step,
                status: switch (item.status) {
                  native.BridgeTodoStatus.pending => TodoItemStatus.pending,
                  native.BridgeTodoStatus.inProgress =>
                    TodoItemStatus.inProgress,
                  native.BridgeTodoStatus.completed => TodoItemStatus.completed,
                },
              ),
          ],
        ),
  activeSkills: value.activeSkills,
  activeMcpServers: value.activeMcpServers,
  activeLspServers: value.activeLspServers,
  progress: value.progress,
  mcpHealth: value.mcpHealth == null
      ? null
      : ThreadMcpHealthSnapshot(
          generation: exactU64(
            value.mcpHealth!.generation,
            'command MCP generation',
          ),
          servers: [
            for (final server in value.mcpHealth!.servers)
              ThreadMcpAvailability(
                server: ThreadMcpServer(
                  id: server.server.id,
                  source: server.server.source,
                  transport: server.server.transport,
                  endpoint: server.server.endpoint,
                  builtIn: server.server.builtIn,
                ),
                availability: server.availability,
                message: server.message,
                lastCheckedAt: nullableI64(
                  server.lastCheckedAt == null
                      ? null
                      : BigInt.from(server.lastCheckedAt!),
                  'command MCP checked Unix seconds',
                ),
                toolCount: nullableU64(
                  server.toolCount,
                  'command MCP tool count',
                ),
              ),
          ],
        ),
  workflow: value.workflow == null
      ? null
      : ThreadWorkflowSnapshot(
          revision: exactU64(
            value.workflow!.revision,
            'command workflow revision',
          ),
          currentRun: value.workflow!.currentRun == null
              ? null
              : commandWorkflowRunFromBridge(value.workflow!.currentRun!),
        ),
  plan: value.plan == null
      ? null
      : ThreadPlanSnapshot(
          revision: exactU64(value.plan!.revision, 'command Plan revision'),
          state: planPhaseFromBridge(value.plan!.state),
          document: value.plan!.document == null
              ? null
              : ThreadPlanDocument(
                  version: exactU64(
                    value.plan!.document!.version,
                    'command Plan document version',
                  ),
                  markdown: value.plan!.document!.markdown,
                  contentHash: value.plan!.document!.contentHash,
                ),
          updatedAt: exactI64(
            BigInt.from(value.plan!.updatedAt),
            'command Plan updated Unix seconds',
          ),
        ),
  updatedAt: exactI64(
    BigInt.from(value.updatedAt),
    'command runtime updated Unix seconds',
  ),
);

ThreadRuntimeUsage commandUsageFromBridge(
  native.BridgeThreadRuntimeUsage value,
) => ThreadRuntimeUsage(
  hasIncompleteUsage: value.hasIncompleteUsage,
  modelId: value.modelId,
  contextWindow: nullableU64(value.contextWindow, 'command context window'),
  maxContextWindow: nullableU64(
    value.maxContextWindow,
    'command maximum context window',
  ),
  autoCompactLimit: nullableU64(
    value.autoCompactLimit,
    'command compact limit',
  ),
  latestContextTokens: exactU64(
    value.latestContextTokens,
    'command context tokens',
  ),
  promptTokens: exactU64(value.promptTokens, 'command prompt tokens'),
  completionTokens: exactU64(
    value.completionTokens,
    'command completion tokens',
  ),
  cachedPromptTokens: exactU64(
    value.cachedPromptTokens,
    'command cached prompt tokens',
  ),
  cacheWriteTokens: exactU64(
    value.cacheWriteTokens,
    'command cache write tokens',
  ),
  reasoningTokens: exactU64(value.reasoningTokens, 'command reasoning tokens'),
  inferenceCount: exactU64(value.inferenceCount, 'command inference count'),
  totalTokens: exactU64(value.totalTokens, 'command total tokens'),
  cacheUsage: CacheUsageSummary(
    inputTokens: exactU64(
      value.cacheUsage.inputTokens,
      'command cache input tokens',
    ),
    cacheReadTokens: exactU64(
      value.cacheUsage.cacheReadTokens,
      'command cache read tokens',
    ),
    hitRate: nullableFiniteModelNumber(
      value.cacheUsage.hitRate,
      'command cache hit rate',
    ),
    hasIncompleteUsage: value.cacheUsage.hasIncompleteUsage,
  ),
  estimatedCosts: value.estimatedCosts
      .map(commandCostFromBridge)
      .toList(growable: false),
  estimatedCacheSavings: value.estimatedCacheSavings
      .map(commandCostFromBridge)
      .toList(growable: false),
  hasUnpricedUsage: value.hasUnpricedUsage,
  promptGeneration: nullableU64(
    value.promptGeneration,
    'command prompt generation',
  ),
  promptCachePolicy: value.promptCachePolicy,
  prefixChangedReason: value.prefixChangedReason == null
      ? null
      : prefixReasonFromBridge(value.prefixChangedReason!),
  updatedAt: exactI64(
    BigInt.from(value.updatedAt),
    'command usage updated Unix seconds',
  ),
);

ThreadRuntimeCost commandCostFromBridge(native.BridgeRuntimeCostAmount value) =>
    ThreadRuntimeCost(
      currency: value.currency,
      amount: finiteModelNumber(value.amount, 'command runtime cost'),
    );

ThreadWorkflowRun commandWorkflowRunFromBridge(
  native.BridgeWorkflowRun value,
) => ThreadWorkflowRun(
  lineageId: value.lineageId,
  runId: value.runId,
  modeId: value.modeId,
  graphRevision: exactU64(
    value.graphRevision,
    'command workflow graph revision',
  ),
  graphHash: value.graphHash,
  lifecycle: workflowLifecycleFromBridge(value.lifecycle),
  currentStateId: value.currentStateId,
  startedAt: exactI64(
    BigInt.from(value.startedAt),
    'command workflow started Unix seconds',
  ),
  updatedAt: exactI64(
    BigInt.from(value.updatedAt),
    'command workflow updated Unix seconds',
  ),
  currentStateTitle: value.currentStateTitle,
  modeDisplayName: value.modeDisplayName,
  modeDeleted: value.modeDeleted,
);
