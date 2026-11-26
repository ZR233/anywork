part of 'studio_api.dart';

ThreadActivityKind _threadActivityKindFromFrb(
  frb_activity.BridgeThreadActivityKind value,
) => switch (value) {
  frb_activity.BridgeThreadActivityKind.preparing =>
    ThreadActivityKind.preparing,
  frb_activity.BridgeThreadActivityKind.compacting =>
    ThreadActivityKind.compacting,
  frb_activity.BridgeThreadActivityKind.waitingApi =>
    ThreadActivityKind.waitingApi,
  frb_activity.BridgeThreadActivityKind.thinking => ThreadActivityKind.thinking,
  frb_activity.BridgeThreadActivityKind.responding =>
    ThreadActivityKind.responding,
  frb_activity.BridgeThreadActivityKind.planning => ThreadActivityKind.planning,
  frb_activity.BridgeThreadActivityKind.runningTool =>
    ThreadActivityKind.runningTool,
  frb_activity.BridgeThreadActivityKind.awaitingApproval =>
    ThreadActivityKind.awaitingApproval,
  frb_activity.BridgeThreadActivityKind.awaitingInput =>
    ThreadActivityKind.awaitingInput,
  frb_activity.BridgeThreadActivityKind.stopping => ThreadActivityKind.stopping,
};

ThreadActivityView _threadActivityFromFrb(
  frb_activity.BridgeThreadActivity value,
) {
  return ThreadActivityView(
    threadId: value.threadId,
    deferred: [
      for (final field in value.deferred_) _currentStateFieldFromFrb(field),
    ],
    identity: value.identity,
    revision: exactTimelineInt(value.revision, 'state counter'),
    turnId: value.turnId,
    executionId: value.executionId,
    inputId: value.inputId,
    attemptId: value.attemptId,
    kind: _threadActivityKindFromFrb(value.kind),
    summary: value.summary,
    summaryTruncated: value.summaryTruncated,
    thinkingSummary: value.thinkingSummary,
    thinkingSeconds: value.thinkingSeconds?.toInt(),
    tools: ThreadActivityTools(
      count: value.tools.count,
      background: value.tools.background,
      active: [
        for (final tool in value.tools.active) _activityToolFromFrb(tool),
      ],
      latestStarted: value.tools.latestStarted == null
          ? null
          : _activityToolFromFrb(value.tools.latestStarted!),
    ),
  );
}

ThreadActivityToolEntry _activityToolFromFrb(
  frb_activity.BridgeThreadActivityToolEntry value,
) {
  return ThreadActivityToolEntry(
    callId: value.callId,
    taskId: value.taskId,
    name: value.name,
    summary: value.summary,
    arguments: switch (value.arguments) {
      frb_activity.BridgeThreadActivityArguments.commandLine =>
        ThreadActivityArgumentsKind.commandLine,
      frb_activity.BridgeThreadActivityArguments.opaque =>
        ThreadActivityArgumentsKind.opaque,
      frb_activity.BridgeThreadActivityArguments.streaming =>
        ThreadActivityArgumentsKind.streaming,
      frb_activity.BridgeThreadActivityArguments.unavailable =>
        ThreadActivityArgumentsKind.unavailable,
    },
    state: _activityToolStateFromFrb(value.state),
    ordinal: _exactNullableTimelineInt(value.ordinal, 'state counter'),
    startedAt: value.startedAt?.toInt(),
    wait: value.wait == null ? null : _waitFromFrb(value.wait!),
  );
}

ThreadActivityToolState _activityToolStateFromFrb(
  frb_activity.BridgeThreadActivityToolState value,
) {
  return switch (value) {
    frb_activity.BridgeThreadActivityToolState.running =>
      ThreadActivityToolState.running,
    frb_activity.BridgeThreadActivityToolState.awaitingApproval =>
      ThreadActivityToolState.awaitingApproval,
    frb_activity.BridgeThreadActivityToolState.cancelling =>
      ThreadActivityToolState.cancelling,
    frb_activity.BridgeThreadActivityToolState.finished =>
      ThreadActivityToolState.finished,
  };
}

ThreadStorageStateView _threadStorageFromFrb(
  frb_activity.BridgeThreadStorageState value,
) {
  return ThreadStorageStateView(
    fault: switch (value.fault) {
      frb_activity.BridgeHistoryFault.queueFull => ThreadHistoryFault.queueFull,
      frb_activity.BridgeHistoryFault.writeFailed =>
        ThreadHistoryFault.writeFailed,
      frb_activity.BridgeHistoryFault.writerUnavailable =>
        ThreadHistoryFault.writerUnavailable,
      frb_activity.BridgeHistoryFault.noProgress =>
        ThreadHistoryFault.noProgress,
      frb_activity.BridgeHistoryFault.checkpointFailed =>
        ThreadHistoryFault.checkpointFailed,
      frb_activity.BridgeHistoryFault.blobFailed =>
        ThreadHistoryFault.blobFailed,
      null => null,
    },
    faultGeneration: exactTimelineInt(value.faultGeneration, 'state counter'),
    acceptedSequence: _exactNullableTimelineInt(
      value.acceptedSequence,
      'state counter',
    ),
    durableSequence: _exactNullableTimelineInt(
      value.durableSequence,
      'state counter',
    ),
    execution: switch (value.execution) {
      frb_activity.BridgeThreadStorageExecution.running =>
        ThreadStorageExecution.running,
      frb_activity.BridgeThreadStorageExecution.pausing =>
        ThreadStorageExecution.pausing,
      frb_activity.BridgeThreadStorageExecution.paused =>
        ThreadStorageExecution.paused,
    },
    pressurePaused: value.pressurePaused,
    resumeRequired: value.resumeRequired,
    canResume: value.canResume,
    lastError: value.lastError,
  );
}

StudioThread _threadFromFrb(frb.BridgeThread value) {
  return StudioThread(
    id: value.id,
    workspaceId: value.workspaceId,
    title: value.title,
    mode: value.mode == null ? null : ThreadModeId.fromId(value.mode!),
    delegationMode: _delegationModeFromFrb(value.delegationMode),
    delegationPreference: _delegationPreferenceFromFrb(
      value.delegationPreference,
    ),
    frozenModel: value.frozenModel == null
        ? null
        : _savedRouteFromFrb(value.frozenModel!),
    workspaceMode: ThreadWorkspaceMode.fromId(value.workspaceMode),
    workspacePath: value.workspacePath,
    createdAt: dateFromUnix(value.createdAt),
    updatedAt: dateFromUnix(value.updatedAt),
    lastUserMessageAt: value.lastUserMessageAt == null
        ? null
        : dateFromUnix(value.lastUserMessageAt!),
    parentThreadId: value.parentThreadId,
    rootThreadId: value.rootThreadId,
    agentPath: value.agentPath,
    role: value.role,
    status: _threadStatusFromFrb(value.status),
    archived: value.archived,
  );
}

ThreadWaitPresentationView _waitFromFrb(
  frb_item.BridgeThreadWaitPresentation value,
) {
  return ThreadWaitPresentationView(
    intent: value.intent.when(
      events: (targets, timeoutMs) => ThreadWaitEventsIntentView(
        targets: [
          for (final target in targets)
            ThreadWaitTargetView(
              taskId: target.taskId,
              toolName: target.toolName,
              summary: target.summary,
              summaryTruncated: target.summaryTruncated,
              status: switch (target.status) {
                frb_item.BridgeThreadWaitTargetStatus.running =>
                  ThreadWaitTargetStatusView.running,
                frb_item.BridgeThreadWaitTargetStatus.succeeded =>
                  ThreadWaitTargetStatusView.succeeded,
                frb_item.BridgeThreadWaitTargetStatus.failed =>
                  ThreadWaitTargetStatusView.failed,
                frb_item.BridgeThreadWaitTargetStatus.cancelled =>
                  ThreadWaitTargetStatusView.cancelled,
                frb_item.BridgeThreadWaitTargetStatus.interrupted =>
                  ThreadWaitTargetStatusView.interrupted,
                null => null,
              },
            ),
        ],
        timeoutMs: exactTimelineInt(timeoutMs, 'state counter'),
      ),
      timer: (durationMs) => ThreadWaitTimerIntentView(
        durationMs: exactTimelineInt(durationMs, 'state counter'),
      ),
    ),
    state: switch (value.state) {
      frb_item.BridgeThreadWaitState.waiting => ThreadWaitStateView.waiting,
      frb_item.BridgeThreadWaitState.ready => ThreadWaitStateView.ready,
      frb_item.BridgeThreadWaitState.timedOut => ThreadWaitStateView.timedOut,
      frb_item.BridgeThreadWaitState.elapsed => ThreadWaitStateView.elapsed,
      frb_item.BridgeThreadWaitState.cancelled => ThreadWaitStateView.cancelled,
      frb_item.BridgeThreadWaitState.failed => ThreadWaitStateView.failed,
      frb_item.BridgeThreadWaitState.interrupted =>
        ThreadWaitStateView.interrupted,
    },
    messagesReady: value.messagesReady,
  );
}

StudioTurnView _turnFromFrb(frb.BridgeTurn value) {
  return StudioTurnView(
    inputId: value.inputId,
    turnId: value.id,
    threadId: value.threadId,
    revision: exactTimelineInt(value.revision, 'state counter'),
    state: _turnStateFromFrb(value.state),
    updatedAt: dateFromUnix(value.updatedAt),
  );
}

StudioTurnState _turnStateFromFrb(frb.BridgeTurnState value) {
  return value.when(
    queued: (queuedAt) => QueuedStudioTurnState(queuedAt: queuedAt.toInt()),
    running: (startedAt, phase) => RunningStudioTurnState(
      startedAt: startedAt.toInt(),
      activity: switch (phase) {
        frb.BridgeTurnPhase.preparing => StudioTurnActivity.preparing,
        frb.BridgeTurnPhase.thinking => StudioTurnActivity.thinking,
        frb.BridgeTurnPhase.responding => StudioTurnActivity.responding,
        frb.BridgeTurnPhase.planning => StudioTurnActivity.planning,
        frb.BridgeTurnPhase.runningTool => StudioTurnActivity.runningTool,
        frb.BridgeTurnPhase.persisting => StudioTurnActivity.persisting,
      },
    ),
    completed: (startedAt, completedAt, completion) => CompletedStudioTurnState(
      startedAt: startedAt?.toInt(),
      completedAt: completedAt.toInt(),
      completion: switch (completion) {
        frb.BridgeTurnCompletion.normal => StudioTurnCompletion.normal,
        frb.BridgeTurnCompletion.interactionRequested =>
          StudioTurnCompletion.interactionRequested,
      },
    ),
    cancelled: (startedAt, requestedAt, completedAt, cause) =>
        CancelledStudioTurnState(
          startedAt: startedAt?.toInt(),
          requestedAt: requestedAt.toInt(),
          completedAt: completedAt.toInt(),
          cause: _turnCancellationCauseFromFrb(cause),
        ),
    failed: (startedAt, completedAt, failure) => FailedStudioTurnState(
      startedAt: startedAt?.toInt(),
      completedAt: completedAt.toInt(),
      failure: _turnFailureFromFrb(failure),
    ),
    budgetLimited: (startedAt, completedAt, limit, rollover) =>
        BudgetLimitedStudioTurnState(
          startedAt: startedAt?.toInt(),
          completedAt: completedAt.toInt(),
          limit: StudioTurnBudgetLimit(
            kind: StudioTurnBudgetLimitKind.values.byName(limit.kind.name),
            usage: StudioTurnBudgetUsage(
              modelSteps: limit.usage.modelSteps,
              toolCalls: limit.usage.toolCalls,
              waitCalls: limit.usage.waitCalls,
              elapsedMs: exactTimelineInt(
                limit.usage.elapsedMs,
                'state counter',
              ),
            ),
          ),
          rollover: rollover.when(
            notAttempted: () => const RolloverNotAttempted(),
            succeeded: () => const RolloverSucceeded(),
            failed: (error) => RolloverFailed(error: error),
          ),
        ),
  );
}

StudioTurnCancellationCause _turnCancellationCauseFromFrb(
  frb.BridgeTurnCancellationCause value,
) {
  return value.when(
    unspecified: () => const UnspecifiedTurnCancellation(),
    userRequested: () => const UserRequestedTurnCancellation(),
    runtimeShutdown: () => const RuntimeShutdownTurnCancellation(),
    agentClosed: () => const AgentClosedTurnCancellation(),
    interrupted: () => const InterruptedTurnCancellation(),
    recovery: () => const RecoveryTurnCancellation(),
    coalesced: (targetTurnId) =>
        CoalescedTurnCancellation(targetTurnId: targetTurnId),
  );
}

StudioTurnFailureView _turnFailureFromFrb(frb.BridgeTurnFailureDto value) {
  final recovery = value.recovery;
  return StudioTurnFailureView(
    category: value.category,
    providerKind: value.providerKind,
    code: value.code,
    httpStatus: value.httpStatus,
    message: value.message,
    retryDisposition: StudioRetryDisposition.values.byName(
      value.retryDisposition,
    ),
    retryAfterMs: value.retryAfterMs,
    errorType: value.errorType,
    requestId: value.requestId,
    stage: StudioProviderFailureStage.values.asNameMap()[value.stage],
    recovery: recovery == null
        ? null
        : StudioModelRecoveryInfo(
            retryCount: recovery.retryCount,
            maxRetries: recovery.maxRetries,
            effectiveWaitMillis: recovery.effectiveWaitMillis,
            reason: StudioProviderRecovery.values.asNameMap()[recovery.reason],
            stopReason: StudioModelRecoveryStopReason.values
                .asNameMap()[recovery.stopReason],
            error: recovery.error,
          ),
  );
}

ThreadRuntimeView _threadRuntimeFromFrb(frb.BridgeThreadRuntimeSnapshot value) {
  final usage = _conversationRuntimeUsageFromFrb(value.usage);
  return ThreadRuntimeView(
    deferred: value.deferred_.map(_currentStateFieldFromFrb).toList(),
    usageDiagnostics: usage.diagnostics,
    modelId: usage.modelId,
    liveUsage: _liveUsageFromFrb(value.liveUsage),
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
    estimatedCosts: usage.estimatedCosts,
    estimatedCacheSavings: usage.estimatedCacheSavings,
    hasUnpricedUsage: usage.hasUnpricedUsage,
    hasIncompleteUsage: usage.hasIncompleteUsage,
    promptGeneration: usage.promptGeneration,
    promptCachePolicy: usage.promptCachePolicy,
    prefixChangedReason: usage.prefixChangedReason?.name,
    turnCompletionTokens: exactTimelineInt(
      value.turnCompletionTokens,
      'turn completion tokens',
    ),
    turnResponseMillis: exactTimelineInt(
      value.turnResponseMillis,
      'turn response duration',
    ),
    costLabel: formatRuntimeCosts(usage.estimatedCosts),
    activeSkills: value.activeSkills,
    activeMcpServers: value.activeMcpServers,
    activeLspServers: value.activeLspServers,
    workflow: value.workflow == null
        ? null
        : _workflowRuntimeFromFrb(value.workflow!),
    plan: value.plan == null ? null : planRuntimeFromFrb(value.plan!),
    execution: value.execution == null
        ? null
        : _agentExecutionFromFrb(value.execution!),
    continuation: value.continuation == null
        ? null
        : _continuationFromFrb(value.continuation!),
  );
}

ConversationRuntimeUsage _conversationRuntimeUsageFromFrb(
  frb.BridgeThreadRuntimeUsage value,
) => ConversationRuntimeUsage(
  diagnostics: threadUsageDiagnosticsFromFrb(value.diagnostics),
  hasIncompleteUsage: value.hasIncompleteUsage,
  modelId: value.modelId,
  contextWindow: _exactNullableTimelineInt(
    value.contextWindow,
    'context window',
  ),
  maxContextWindow: _exactNullableTimelineInt(
    value.maxContextWindow,
    'maximum context window',
  ),
  autoCompactLimit: _exactNullableTimelineInt(
    value.autoCompactLimit,
    'compaction threshold',
  ),
  latestContextTokens: exactTimelineInt(
    value.latestContextTokens,
    'context tokens',
  ),
  promptTokens: exactTimelineInt(value.promptTokens, 'prompt tokens'),
  completionTokens: exactTimelineInt(
    value.completionTokens,
    'completion tokens',
  ),
  cachedPromptTokens: exactTimelineInt(
    value.cachedPromptTokens,
    'cached prompt tokens',
  ),
  cacheWriteTokens: exactTimelineInt(
    value.cacheWriteTokens,
    'cache write tokens',
  ),
  reasoningTokens: exactTimelineInt(value.reasoningTokens, 'reasoning tokens'),
  inferenceCount: exactTimelineInt(value.inferenceCount, 'inference count'),
  totalTokens: exactTimelineInt(value.totalTokens, 'total tokens'),
  cacheUsage: CacheUsageView(
    sampleCount: exactTimelineInt(
      value.cacheUsage.sampleCount,
      'cache sample count',
    ),
    legacySampleCountUnknown: value.cacheUsage.legacySampleCountUnknown,
    inputTokens: exactTimelineInt(
      value.cacheUsage.inputTokens,
      'cache input tokens',
    ),
    cacheReadTokens: exactTimelineInt(
      value.cacheUsage.cacheReadTokens,
      'cache read tokens',
    ),
    hitRate: value.cacheUsage.hitRate,
    hasIncompleteUsage: value.cacheUsage.hasIncompleteUsage,
  ),
  estimatedCosts: value.estimatedCosts.map(_runtimeCostFromFrb),
  estimatedCacheSavings: value.estimatedCacheSavings.map(_runtimeCostFromFrb),
  hasUnpricedUsage: value.hasUnpricedUsage,
  promptGeneration: _exactNullableTimelineInt(
    value.promptGeneration,
    'prompt generation',
  ),
  promptCachePolicy: value.promptCachePolicy,
  prefixChangedReason: switch (value.prefixChangedReason) {
    final reason? => ConversationPromptPrefixChangedReason.values.byName(
      reason.name,
    ),
    null => null,
  },
  updatedAt: _exactSignedTimelineInt(value.updatedAt),
);

ThreadRuntimeLiveUsageView? _liveUsageFromFrb(
  frb.BridgeThreadRuntimeLiveUsage? value,
) {
  if (value == null) return null;
  return ThreadRuntimeLiveUsageView(
    turnId: value.turnId,
    attemptId: value.attemptId,
    completionTokens: _exactNullableTimelineInt(
      value.completionTokens,
      'live completion tokens',
    ),
    responseMillis: _exactNullableTimelineInt(
      value.responseMillis,
      'live response duration',
    ),
    latestContextTokens: _exactNullableTimelineInt(
      value.latestContextTokens,
      'live context tokens',
    ),
    state: switch (value.state) {
      frb.BridgeThreadRuntimeUsageState.live => ThreadRuntimeUsageState.live,
      frb.BridgeThreadRuntimeUsageState.authoritative =>
        ThreadRuntimeUsageState.authoritative,
    },
    observationSequence: exactTimelineInt(
      value.observationSequence,
      'observation sequence',
    ),
  );
}

ConversationRuntimeSnapshot _conversationRuntimeFromFrb(
  frb.BridgeThreadRuntimeSnapshot value,
) => ConversationRuntimeSnapshot(
  threadId: value.threadId,
  deferred: value.deferred_.map(_currentStateFieldFromFrb),
  usage: _conversationRuntimeUsageFromFrb(value.usage),
  liveUsage: _liveUsageFromFrb(value.liveUsage),
  turnCompletionTokens: exactTimelineInt(
    value.turnCompletionTokens,
    'turn completion tokens',
  ),
  turnResponseMillis: exactTimelineInt(
    value.turnResponseMillis,
    'turn response duration',
  ),
  todo: _todoFromFrb(value.todo),
  activeSkills: value.activeSkills,
  activeMcpServers: value.activeMcpServers,
  activeLspServers: value.activeLspServers,
  progress: value.progress,
  mcpHealth: _conversationMcpHealthFromFrb(value.mcpHealth),
  workflow: value.workflow == null
      ? null
      : _workflowRuntimeFromFrb(value.workflow!),
  plan: value.plan == null ? null : planRuntimeFromFrb(value.plan!),
  execution: value.execution == null
      ? null
      : _agentExecutionFromFrb(value.execution!),
  continuation: value.continuation == null
      ? null
      : _continuationFromFrb(value.continuation!),
  updatedAt: _exactSignedTimelineInt(value.updatedAt),
);

TimelineTodoListUpdate? _todoFromFrb(frb.BridgeTodoListSnapshot? value) {
  if (value == null) return null;
  return TimelineTodoListUpdate(
    callId: value.callId,
    agentId: value.agentId,
    path: value.path,
    parentPath: value.parentPath,
    explanation: value.explanation,
    items: [
      for (final item in value.items)
        TimelineTodoItem(step: item.step, status: item.status.name),
    ],
  );
}

ConversationMcpHealthSnapshot? _conversationMcpHealthFromFrb(
  frb.BridgeThreadMcpHealthSnapshot? value,
) {
  if (value == null) return null;
  return ConversationMcpHealthSnapshot(
    generation: exactTimelineInt(value.generation, 'MCP health generation'),
    servers: [
      for (final entry in value.servers)
        ConversationMcpAvailabilityDescriptor(
          server: ConversationMcpServerDescriptor(
            id: entry.server.id,
            source: entry.server.source,
            transport: entry.server.transport,
            endpoint: entry.server.endpoint,
            builtIn: entry.server.builtIn,
          ),
          availability: entry.availability,
          message: entry.message,
          lastCheckedAt: entry.lastCheckedAt == null
              ? null
              : _exactSignedTimelineInt(entry.lastCheckedAt!),
          toolCount: _exactNullableTimelineInt(
            entry.toolCount,
            'MCP tool count',
          ),
        ),
    ],
  );
}

ThreadModelRouteView? _threadModelRouteFromFrb(
  frb.BridgeThreadModelRouteSnapshot? value,
) {
  if (value == null) return null;
  return ThreadModelRouteView(
    botId: value.botId,
    accountId: value.accountId,
    modelId: value.modelId,
    effort: value.effort,
    serviceTier: value.serviceTier,
    revision: exactTimelineInt(value.revision, 'state counter'),
    available: value.available,
    unavailableReason: value.unavailableReason,
  );
}

/// 继续点投影：身份与原因都来自规范快照，客户端不重建「可继续」资格。
ContinuationView _continuationFromFrb(
  frb.BridgeContinuationView continuation,
) => ContinuationView(
  id: continuation.id,
  sourceTurnId: continuation.sourceTurnId,
  reason: switch (continuation.reason) {
    null => null,
    frb.BridgeContinuationReason.userStop => ContinuationReason.userStop,
    frb.BridgeContinuationReason.hostShutdown =>
      ContinuationReason.hostShutdown,
    frb.BridgeContinuationReason.processInterrupted =>
      ContinuationReason.processInterrupted,
    frb.BridgeContinuationReason.stepLimit => ContinuationReason.stepLimit,
    frb.BridgeContinuationReason.executionFailed =>
      ContinuationReason.executionFailed,
  },
  createdAt: dateFromUnix(continuation.createdAt),
);

WorkflowRuntimeView _workflowRuntimeFromFrb(
  frb.BridgeWorkflowRuntimeSnapshot value,
) {
  final run = value.currentRun;
  return WorkflowRuntimeView(
    revision: exactTimelineInt(value.revision, 'state counter'),
    currentRun: run == null ? null : workflowRunFromFrb(run),
  );
}

PendingInteraction _interactionFromFrb(frb.BridgeInteractionRequest value) {
  final mapped = value.content.when(
    userInput: (questions, state) => (
      kind: InteractionKind.userInput,
      payload: UserInputInteractionPayload(
        questions: [
          for (final question in questions)
            UserQuestionView(
              id: question.id,
              header: question.header,
              question: question.question,
              isSecret: question.isSecret,
              options: [
                for (final option in question.options ?? const [])
                  UserQuestionOptionView(
                    label: option.label,
                    description: option.description,
                  ),
              ],
            ),
        ],
      ) as InteractionPayload,
    ),
    toolApproval:
        (name, argumentsJson, workingDirectory, parentAgentId, state) => (
          kind: InteractionKind.toolApproval,
          payload: ToolApprovalInteractionPayload(
            toolName: name,
            arguments: jsonDecode(argumentsJson),
            workingDirectory: workingDirectory ?? '',
            parentAgentId: parentAgentId,
          ) as InteractionPayload,
        ),
  );
  return PendingInteraction.fromPayload(
    id: value.interactionId,
    threadId: value.scope.threadId,
    turnId: value.scope.turnId,
    kind: mapped.kind,
    payload: mapped.payload,
    revision: exactTimelineInt(value.revision, 'state counter'),
  );
}

/// Canonical interaction kind 标签；未知标签返回 `null`，由调用方保留已有事实。
InteractionKind? _interactionKindFromLabel(String label) => switch (label) {
  'userInput' => InteractionKind.userInput,
  'toolApproval' => InteractionKind.toolApproval,
  _ => null,
};

bool _interactionIsPending(frb.BridgeInteractionRequest value) {
  return value.content.when(
    userInput: (questions, state) => state.when(
      pending: (operationId) => true,
      resolved: (operationId, resolvedAt, answers) => false,
      cancelled: (operationId, cancelledAt, reason) => false,
      expired: (operationId, expiredAt) => false,
    ),
    toolApproval:
        (name, argumentsJson, workingDirectory, parentAgentId, state) =>
            state.when(
              pending: (operationId) => true,
              resolved: (operationId, resolvedAt, decision, reason) => false,
              cancelled: (operationId, cancelledAt, reason) => false,
              expired: (operationId, expiredAt) => false,
            ),
  );
}

Object _studioFailure(Object error) {
  return switch (error) {
    // 已是领域错误：保持身份与堆栈，不二次包装。
    final StudioFailure failure => failure,
    final frb.BridgeError bridge => StudioFailure(
      code: studioFailureCodeFromBridge(bridge.code),
      message: bridge.message,
      retryable: bridge.retryable,
      correlationId: bridge.correlationId,
      detailsJson: bridge.detailsJson,
      reason: _failureReasonFromDetails(bridge.detailsJson),
    ),
    _ => StudioFailure(
      code: StudioFailureCode.internal,
      message: error.toString(),
      retryable: false,
      correlationId: newStudioCorrelationId(),
    ),
  };
}

/// Typed reason 只从结构化详情里的 `reason` 标签读取，不解析提示文本。
StudioFailureReason? _failureReasonFromDetails(String? detailsJson) {
  if (detailsJson == null) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(detailsJson);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  final label = decoded['reason'];
  return label is String ? StudioFailureReason.fromLabel(label) : null;
}

frb.BridgeInteractionResolution _interactionResolutionFromDomain(
  InteractionResolutionCommand resolution,
) {
  return switch (resolution) {
    UserInputResolutionCommand(:final answers) =>
      frb.BridgeInteractionResolution.userInput(
        answers: [
          for (final answer in answers)
            frb.BridgeUserInputAnswer(
              questionId: answer.questionId,
              answers: answer.answers,
            ),
        ],
      ),
    ToolApprovalResolutionCommand(:final decision, :final reason) =>
      frb.BridgeInteractionResolution.toolApproval(
        decision: switch (decision) {
          ToolApprovalDecision.approved =>
            frb.BridgeToolApprovalResolution.approved,
          ToolApprovalDecision.denied =>
            frb.BridgeToolApprovalResolution.denied,
        },
        reason: reason,
      ),
  };
}
