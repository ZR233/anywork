part of 'studio_api.dart';

ThreadStreamFrame _threadStreamFrameFromFrb(
  frb.BridgeThreadSubscriptionUpdate value,
) {
  return value.when(
    snapshot: (snapshot) =>
        ThreadSnapshotFrame(workspace: _threadWorkspaceFromSnapshot(snapshot)),
    notification: (envelope) {
      final threadId = envelope.threadId;
      final revision = _exactTimelineInt(envelope.revision, 'state counter');
      final epoch = _exactTimelineInt(envelope.epoch, 'state counter');
      final baseRevision = _exactTimelineInt(
        envelope.baseRevision,
        'state counter',
      );
      return envelope.notification.when(
        turnStarted: (turn) => ThreadNotificationFrame(
          threadId: threadId,
          revision: revision,
          epoch: epoch,
          baseRevision: baseRevision,
          update: ThreadTurnUpdate(_turnFromFrb(turn)),
        ),
        turnUpdated: (turn) => ThreadNotificationFrame(
          threadId: threadId,
          revision: revision,
          epoch: epoch,
          baseRevision: baseRevision,
          update: ThreadTurnUpdate(_turnFromFrb(turn)),
        ),
        turnCompleted: (turn) => ThreadNotificationFrame(
          threadId: threadId,
          revision: revision,
          epoch: epoch,
          baseRevision: baseRevision,
          update: ThreadTurnUpdate(_turnFromFrb(turn)),
        ),
        interactionChanged: (interaction) => ThreadNotificationFrame(
          threadId: threadId,
          revision: revision,
          epoch: epoch,
          baseRevision: baseRevision,
          update: ThreadInteractionUpdate(
            interaction: _interactionFromFrb(interaction),
            pending: _interactionIsPending(interaction),
          ),
        ),
        threadRuntimeUpdated: (runtime) => ThreadNotificationFrame(
          threadId: threadId,
          revision: revision,
          epoch: epoch,
          baseRevision: baseRevision,
          update: ThreadRuntimeUpdate(
            runtime: _threadRuntimeFromFrb(runtime),
            todo: _todoFromFrb(runtime.todo),
          ),
        ),
        activityChanged: (activity) => ThreadNotificationFrame(
          threadId: threadId,
          revision: revision,
          epoch: epoch,
          baseRevision: baseRevision,
          update: ThreadActivityUpdate(
            activity: activity == null
                ? null
                : _threadActivityFromFrb(activity),
          ),
        ),
        storageChanged: (storage) => ThreadNotificationFrame(
          threadId: threadId,
          revision: revision,
          epoch: epoch,
          baseRevision: baseRevision,
          update: ThreadStorageUpdate(
            storage: storage == null ? null : _threadStorageFromFrb(storage),
          ),
        ),
        lagged: (dropped) => ThreadResyncRequiredFrame(
          threadId: threadId,
          dropped: _exactTimelineInt(dropped, 'state counter'),
          epoch: epoch,
        ),
      );
    },
  );
}

/// 订阅首帧只投影当前状态；条目正文由独立的 Timeline 内容尾部（一致小页基线 +
/// 连续补丁）交付，因此这里不产生条目正文、Turn 摘要或回源锚点。
ThreadWorkspace _threadWorkspaceFromSnapshot(frb.BridgeThreadSnapshot value) {
  return ThreadWorkspace(
    thread: _threadFromFrb(value.thread),
    revision: _exactTimelineInt(value.revision, 'state counter'),
    interactions: value.interactions
        .where(_interactionIsPending)
        .map(_interactionFromFrb)
        .toList(),
    runtime: value.runtime == null
        ? _emptyRuntimeView()
        : _threadRuntimeFromFrb(value.runtime!),
    activeTurn: value.activeTurn == null
        ? null
        : _turnFromFrb(value.activeTurn!),
    todo: _todoFromFrb(value.runtime?.todo),
    activity: value.activity == null
        ? null
        : _threadActivityFromFrb(value.activity!),
    storage: value.storage == null
        ? null
        : _threadStorageFromFrb(value.storage!),
  );
}

ThreadActivityView _threadActivityFromFrb(
  frb_activity.BridgeThreadActivity value,
) {
  return ThreadActivityView(
    threadId: value.threadId,
    identity: value.identity,
    revision: _exactTimelineInt(value.revision, 'state counter'),
    turnId: value.turnId,
    inputId: value.inputId,
    attemptId: value.attemptId,
    kind: switch (value.kind) {
      frb_activity.BridgeThreadActivityKind.preparing =>
        ThreadActivityKind.preparing,
      frb_activity.BridgeThreadActivityKind.compacting =>
        ThreadActivityKind.compacting,
      frb_activity.BridgeThreadActivityKind.waitingApi =>
        ThreadActivityKind.waitingApi,
      frb_activity.BridgeThreadActivityKind.thinking =>
        ThreadActivityKind.thinking,
      frb_activity.BridgeThreadActivityKind.responding =>
        ThreadActivityKind.responding,
      frb_activity.BridgeThreadActivityKind.planning =>
        ThreadActivityKind.planning,
      frb_activity.BridgeThreadActivityKind.runningTool =>
        ThreadActivityKind.runningTool,
      frb_activity.BridgeThreadActivityKind.awaitingApproval =>
        ThreadActivityKind.awaitingApproval,
      frb_activity.BridgeThreadActivityKind.awaitingInput =>
        ThreadActivityKind.awaitingInput,
      frb_activity.BridgeThreadActivityKind.stopping =>
        ThreadActivityKind.stopping,
    },
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
    startedAt: _frbNullableInt(value.startedAt),
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
    faultGeneration: _exactTimelineInt(value.faultGeneration, 'state counter'),
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

/// 按活动身份读取的完整详情映射；`revision` 为 `null` 表示纯内存推导，如实保留未知。
ThreadActivityDetail _activityDetailFromFrb(
  frb_activity.BridgeThreadActivityDetail value,
) {
  return value.when(
    current: (activity, reasoning, response, tools) =>
        CurrentThreadActivityDetail(
          activity: _threadActivityFromFrb(activity),
          reasoning: [
            for (final part in reasoning) _activityContentPartFromFrb(part),
          ],
          response: [
            for (final part in response) _activityContentPartFromFrb(part),
          ],
          tools: [for (final tool in tools) _activityToolDetailFromFrb(tool)],
        ),
    superseded: (activity, requestedActivityId) =>
        SupersededThreadActivityDetail(
          activity: _threadActivityFromFrb(activity),
          requestedActivityId: requestedActivityId,
        ),
    ended: (threadId, activityId) =>
        EndedThreadActivityDetail(threadId: threadId, activityId: activityId),
  );
}

ThreadActivityContentPart _activityContentPartFromFrb(
  frb_activity.BridgeThreadActivityContentPart value,
) {
  return ThreadActivityContentPart(
    itemId: value.itemId,
    revision: _exactNullableTimelineInt(value.revision, 'state counter'),
    complete: value.complete,
    text: value.text,
  );
}

ThreadActivityToolDetail _activityToolDetailFromFrb(
  frb_activity.BridgeThreadActivityToolDetail value,
) {
  return ThreadActivityToolDetail(
    callId: value.callId,
    taskId: value.taskId,
    name: value.name,
    state: _activityToolStateFromFrb(value.state),
    arguments: value.arguments,
    output: value.output,
    ordinal: _exactNullableTimelineInt(value.ordinal, 'state counter'),
    startedAt: _frbNullableInt(value.startedAt),
    wait: value.wait == null ? null : _waitFromFrb(value.wait!),
  );
}

StudioThread _threadFromFrb(frb.BridgeThread value) {
  return StudioThread(
    id: value.id,
    projectId: value.projectId,
    title: value.title,
    mode: ThreadModeId.fromId(value.mode),
    delegationMode: _delegationModeFromFrb(value.delegationMode),
    delegationPreference: _delegationPreferenceFromFrb(
      value.delegationPreference,
    ),
    frozenModel: value.frozenModel == null
        ? null
        : _savedRouteFromFrb(value.frozenModel!),
    workspaceMode: ThreadWorkspaceMode.fromId(value.workspaceMode),
    workspacePath: value.workspacePath,
    createdAt: _dateFromUnix(value.createdAt),
    updatedAt: _dateFromUnix(value.updatedAt),
    lastUserMessageAt: value.lastUserMessageAt == null
        ? null
        : _dateFromUnix(value.lastUserMessageAt!),
    parentThreadId: value.parentThreadId,
    rootThreadId: value.rootThreadId,
    agentPath: value.agentPath,
    role: value.role,
    status: switch (value.status) {
      frb.BridgeThreadStatus.idle => ThreadStatusView.idle,
      frb.BridgeThreadStatus.queued => ThreadStatusView.queued,
      frb.BridgeThreadStatus.running => ThreadStatusView.running,
      frb.BridgeThreadStatus.waitingTool => ThreadStatusView.waitingTool,
      frb.BridgeThreadStatus.waitingInteraction =>
        ThreadStatusView.waitingInteraction,
      frb.BridgeThreadStatus.cancelling => ThreadStatusView.cancelling,
      frb.BridgeThreadStatus.closing => ThreadStatusView.closing,
      frb.BridgeThreadStatus.closed => ThreadStatusView.closed,
      frb.BridgeThreadStatus.faulted => ThreadStatusView.faulted,
    },
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
        timeoutMs: _exactTimelineInt(timeoutMs, 'state counter'),
      ),
      timer: (durationMs) => ThreadWaitTimerIntentView(
        durationMs: _exactTimelineInt(durationMs, 'state counter'),
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

ThreadContentLifecycleView _contentLifecycleFromFrb(
  frb_item.BridgeThreadContentLifecycle value,
) {
  return value.when(
    streaming: () => const StreamingThreadContentView(),
    completed: (completedAt) =>
        CompletedThreadContentView(_dateFromUnix(completedAt)),
    failed: (failedAt, error) =>
        FailedThreadContentView(_dateFromUnix(failedAt), error),
    cancelled: (cancelledAt, reason) =>
        CancelledThreadContentView(_dateFromUnix(cancelledAt), reason),
  );
}

ThreadAttachmentView _attachmentFromFrb(frb_item.BridgeThreadAttachment value) {
  return ThreadAttachmentView(
    id: value.id,
    modality: switch (value.modality) {
      frb_attachment_types.BridgeAttachmentModality.image =>
        AttachmentModalityView.image,
      frb_attachment_types.BridgeAttachmentModality.video =>
        AttachmentModalityView.video,
      frb_attachment_types.BridgeAttachmentModality.file =>
        AttachmentModalityView.file,
    },
    mediaType: value.mediaType,
    filename: value.filename,
    width: value.width,
    height: value.height,
    byteSize: _exactTimelineInt(value.byteSize, 'state counter'),
  );
}

ThreadAgentLifecycleView _agentLifecycleFromFrb(
  frb_item.BridgeThreadAgentState value,
) {
  return value.when(
    queued: () => const QueuedThreadAgentView(),
    running: () => const RunningThreadAgentView(),
    succeeded: (completedAt, summary) =>
        SucceededThreadAgentView(_dateFromUnix(completedAt), summary),
    denied: (deniedAt, reason) =>
        DeniedThreadAgentView(_dateFromUnix(deniedAt), reason),
    cancelled: (cancelledAt, reason) =>
        CancelledThreadAgentView(_dateFromUnix(cancelledAt), reason),
    failed: (failedAt, error) =>
        FailedThreadAgentView(_dateFromUnix(failedAt), error),
  );
}

ThreadInferenceLifecycleView _inferenceLifecycleFromFrb(
  frb_item.BridgeThreadInferenceState value,
) {
  return value.when(
    running: () => const RunningThreadInferenceView(),
    completed: (completedAt, usage) => CompletedThreadInferenceView(
      _dateFromUnix(completedAt),
      ThreadInferenceUsageView(
        promptTokens: _exactTimelineInt(usage.promptTokens, 'state counter'),
        completionTokens: _exactTimelineInt(
          usage.completionTokens,
          'state counter',
        ),
        cachedPromptTokens: _exactTimelineInt(
          usage.cachedPromptTokens,
          'state counter',
        ),
        totalTokens: _exactTimelineInt(usage.totalTokens, 'state counter'),
      ),
    ),
    failed: (failedAt, error) =>
        FailedThreadInferenceView(_dateFromUnix(failedAt), error),
    cancelled: (cancelledAt, reason) =>
        CancelledThreadInferenceView(_dateFromUnix(cancelledAt), reason),
  );
}

StudioTurnView _turnFromFrb(frb.BridgeTurn value) {
  return StudioTurnView(
    inputId: value.inputId,
    turnId: value.id,
    threadId: value.threadId,
    revision: _exactTimelineInt(value.revision, 'state counter'),
    state: _turnStateFromFrb(value.state),
    updatedAt: _dateFromUnix(value.updatedAt),
  );
}

StudioTurnState _turnStateFromFrb(frb.BridgeTurnState value) {
  return value.when(
    queued: (queuedAt) => QueuedStudioTurnState(queuedAt: _frbInt(queuedAt)),
    running: (startedAt, phase) => RunningStudioTurnState(
      startedAt: _frbInt(startedAt),
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
      startedAt: _frbNullableInt(startedAt),
      completedAt: _frbInt(completedAt),
      completion: switch (completion) {
        frb.BridgeTurnCompletion.normal => StudioTurnCompletion.normal,
        frb.BridgeTurnCompletion.interactionRequested =>
          StudioTurnCompletion.interactionRequested,
      },
    ),
    cancelled: (startedAt, requestedAt, completedAt, cause) =>
        CancelledStudioTurnState(
          startedAt: _frbNullableInt(startedAt),
          requestedAt: _frbInt(requestedAt),
          completedAt: _frbInt(completedAt),
          cause: _turnCancellationCauseFromFrb(cause),
        ),
    failed: (startedAt, completedAt, failure) => FailedStudioTurnState(
      startedAt: _frbNullableInt(startedAt),
      completedAt: _frbInt(completedAt),
      failure: _turnFailureFromFrb(failure),
    ),
    budgetLimited: (startedAt, completedAt, limit, rollover) =>
        BudgetLimitedStudioTurnState(
          startedAt: _frbNullableInt(startedAt),
          completedAt: _frbInt(completedAt),
          limit: StudioTurnBudgetLimit(
            kind: StudioTurnBudgetLimitKind.values.byName(limit.kind.name),
            usage: StudioTurnBudgetUsage(
              modelSteps: limit.usage.modelSteps,
              toolCalls: limit.usage.toolCalls,
              waitCalls: limit.usage.waitCalls,
              elapsedMs: _exactTimelineInt(
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
  return StudioTurnFailureView(
    category: value.category,
    providerKind: value.providerKind,
    code: value.code,
    httpStatus: value.httpStatus,
    message: value.message,
    retryable: value.retryable,
    retryAfterMs: _exactNullableTimelineInt(
      value.retryAfterMs,
      'state counter',
    ),
  );
}

ThreadRuntimeView _threadRuntimeFromFrb(frb.BridgeThreadRuntimeSnapshot value) {
  final usage = value.usage;
  final estimatedCosts = usage.estimatedCosts
      .map(
        (cost) => RuntimeCostView(currency: cost.currency, amount: cost.amount),
      )
      .toList(growable: false);
  final costLabel = formatRuntimeCosts(estimatedCosts);
  return ThreadRuntimeView(
    modelId: usage.modelId,
    modelRoute: value.modelRoute == null
        ? null
        : ThreadModelRouteView(
            botId: value.modelRoute!.botId,
            accountId: value.modelRoute!.accountId,
            modelId: value.modelRoute!.modelId,
            effort: value.modelRoute!.effort,
            revision: _exactTimelineInt(
              value.modelRoute!.revision,
              'state counter',
            ),
            available: value.modelRoute!.available,
            unavailableReason: value.modelRoute!.unavailableReason,
          ),
    liveUsage: value.liveUsage == null
        ? null
        : ThreadRuntimeLiveUsageView(
            turnId: value.liveUsage!.turnId,
            attemptId: value.liveUsage!.attemptId,
            completionTokens: _exactNullableTimelineInt(
              value.liveUsage!.completionTokens,
              'state counter',
            ),
            responseMillis: _exactNullableTimelineInt(
              value.liveUsage!.responseMillis,
              'state counter',
            ),
            latestContextTokens: _exactNullableTimelineInt(
              value.liveUsage!.latestContextTokens,
              'state counter',
            ),
            state:
                value.liveUsage!.state == frb.BridgeThreadRuntimeUsageState.live
                ? ThreadRuntimeUsageState.live
                : ThreadRuntimeUsageState.authoritative,
            observationSequence: _exactTimelineInt(
              value.liveUsage!.observationSequence,
              'state counter',
            ),
          ),
    contextTokens: _exactTimelineInt(
      usage.latestContextTokens,
      'state counter',
    ),
    contextWindow:
        _exactNullableTimelineInt(usage.contextWindow, 'state counter') ?? 0,
    maxContextWindow: _exactNullableTimelineInt(
      usage.maxContextWindow,
      'state counter',
    ),
    autoCompactLimit: _exactNullableTimelineInt(
      usage.autoCompactLimit,
      'state counter',
    ),
    totalTokens: _exactTimelineInt(usage.totalTokens, 'state counter'),
    promptTokens: _exactTimelineInt(usage.promptTokens, 'state counter'),
    completionTokens: _exactTimelineInt(
      usage.completionTokens,
      'state counter',
    ),
    cachedPromptTokens: _exactTimelineInt(
      usage.cachedPromptTokens,
      'state counter',
    ),
    cacheWriteTokens: _exactTimelineInt(
      usage.cacheWriteTokens,
      'state counter',
    ),
    reasoningTokens: _exactTimelineInt(usage.reasoningTokens, 'state counter'),
    inferenceCount: _exactTimelineInt(usage.inferenceCount, 'state counter'),
    cacheUsage: CacheUsageView(
      inputTokens: _exactTimelineInt(
        usage.cacheUsage.inputTokens,
        'state counter',
      ),
      cacheReadTokens: _exactTimelineInt(
        usage.cacheUsage.cacheReadTokens,
        'state counter',
      ),
      hitRate: usage.cacheUsage.hitRate,
      hasIncompleteUsage: usage.cacheUsage.hasIncompleteUsage,
    ),
    estimatedCosts: estimatedCosts,
    estimatedCacheSavings: usage.estimatedCacheSavings
        .map(
          (cost) =>
              RuntimeCostView(currency: cost.currency, amount: cost.amount),
        )
        .toList(growable: false),
    hasUnpricedUsage: usage.hasUnpricedUsage,
    hasIncompleteUsage: usage.hasIncompleteUsage,
    promptGeneration: _exactNullableTimelineInt(
      usage.promptGeneration,
      'state counter',
    ),
    promptCachePolicy: usage.promptCachePolicy,
    prefixChangedReason: usage.prefixChangedReason?.name,
    turnCompletionTokens: _exactTimelineInt(
      value.turnCompletionTokens,
      'state counter',
    ),
    turnResponseMillis: _exactTimelineInt(
      value.turnResponseMillis,
      'state counter',
    ),
    costLabel: costLabel,
    activeSkills: value.activeSkills,
    activeMcpServers: value.activeMcpServers,
    activeLspServers: value.activeLspServers,
    workflow: value.workflow == null
        ? null
        : _workflowRuntimeFromFrb(value.workflow!),
    plan: value.plan == null ? null : _planRuntimeFromFrb(value.plan!),
    execution: value.execution == null
        ? null
        : _agentExecutionFromFrb(value.execution!),
    continuation: value.continuation == null
        ? null
        : _continuationFromFrb(value.continuation!),
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
  createdAt: _dateFromUnix(continuation.createdAt),
  claimed: continuation.claimed,
);

PlanRuntimeView _planRuntimeFromFrb(frb.BridgePlanRuntimeSnapshot value) {
  final document = value.document;
  return PlanRuntimeView(
    revision: _exactTimelineInt(value.revision, 'state counter'),
    state: switch (value.state) {
      frb.BridgePlanPhase.drafting => PlanRuntimePhase.drafting,
      frb.BridgePlanPhase.awaitingConfirmation =>
        PlanRuntimePhase.awaitingConfirmation,
      frb.BridgePlanPhase.revisionRequested =>
        PlanRuntimePhase.revisionRequested,
      frb.BridgePlanPhase.approved => PlanRuntimePhase.approved,
    },
    document: document == null
        ? null
        : PlanDocumentView(
            version: _exactTimelineInt(document.version, 'state counter'),
            markdown: document.markdown,
            contentHash: document.contentHash,
          ),
    updatedAt: _dateFromUnix(value.updatedAt),
  );
}

WorkflowRuntimeView _workflowRuntimeFromFrb(
  frb.BridgeWorkflowRuntimeSnapshot value,
) {
  final run = value.currentRun;
  return WorkflowRuntimeView(
    revision: _exactTimelineInt(value.revision, 'state counter'),
    currentRun: run == null
        ? null
        : WorkflowRunView(
            lineageId: run.lineageId,
            runId: run.runId,
            modeId: run.modeId,
            graphRevision: _exactTimelineInt(
              run.graphRevision,
              'state counter',
            ),
            graphHash: run.graphHash,
            currentStateId: run.currentStateId,
            terminal: run.lifecycle == frb.BridgeWorkflowRunLifecycle.terminal,
            startedAt: _dateFromUnix(run.startedAt),
            updatedAt: _dateFromUnix(run.updatedAt),
            currentStateTitle: run.currentStateTitle,
            modeDisplayName: run.modeDisplayName,
            modeDeleted: run.modeDeleted,
          ),
  );
}

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
              isOther: question.isOther,
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
  return PendingInteraction(
    id: value.interactionId,
    threadId: value.scope.threadId,
    turnId: value.scope.turnId,
    kind: mapped.kind,
    title: _interactionTitle(mapped.kind, mapped.payload),
    body: _interactionBody(mapped.kind, mapped.payload),
    payload: mapped.payload,
    revision: _exactTimelineInt(value.revision, 'state counter'),
  );
}

/// Canonical interaction kind 标签；未知标签返回 `null`，由调用方保留已有事实。
InteractionKind? _interactionKindFromLabel(String label) => switch (label) {
  'userInput' => InteractionKind.userInput,
  'toolApproval' => InteractionKind.toolApproval,
  _ => null,
};

ContinuationOperationState _continuationStateFromFrb(
  frb_command.BridgeContinuationOperationState state,
) => switch (state) {
  frb_command.BridgeContinuationOperationState_Pending() =>
    const PendingContinuation(),
  frb_command.BridgeContinuationOperationState_Consumed(:final turnId) =>
    ConsumedContinuation(turnId),
  frb_command.BridgeContinuationOperationState_Discarded() =>
    const DiscardedContinuation(),
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
      code: _studioFailureCode(bridge.code),
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

/// 传输中立错误码到领域错误码的完整映射；每个桥变体都必须显式落位。
StudioFailureCode _studioFailureCode(frb.BridgeErrorCode code) {
  return switch (code) {
    frb.BridgeErrorCode.notInitialized => StudioFailureCode.notInitialized,
    frb.BridgeErrorCode.runtimeStopped => StudioFailureCode.runtimeStopped,
    frb.BridgeErrorCode.instanceBusy => StudioFailureCode.instanceBusy,
    frb.BridgeErrorCode.invalidArgument => StudioFailureCode.invalidArgument,
    frb.BridgeErrorCode.notFound => StudioFailureCode.notFound,
    frb.BridgeErrorCode.busy => StudioFailureCode.busy,
    frb.BridgeErrorCode.conflict => StudioFailureCode.conflict,
    frb.BridgeErrorCode.staleRevision => StudioFailureCode.staleRevision,
    frb.BridgeErrorCode.permissionDenied => StudioFailureCode.permissionDenied,
    frb.BridgeErrorCode.cancelled => StudioFailureCode.cancelled,
    frb.BridgeErrorCode.cancellationTooLate =>
      StudioFailureCode.cancellationTooLate,
    frb.BridgeErrorCode.overloaded => StudioFailureCode.overloaded,
    frb.BridgeErrorCode.unavailable => StudioFailureCode.unavailable,
    frb.BridgeErrorCode.protocol => StudioFailureCode.protocol,
    frb.BridgeErrorCode.storage => StudioFailureCode.storage,
    frb.BridgeErrorCode.update => StudioFailureCode.update,
    frb.BridgeErrorCode.internal => StudioFailureCode.internal,
  };
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
