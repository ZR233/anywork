part of 'studio_api.dart';

ThreadStreamFrame _threadStreamFrameFromFrb(
  frb.BridgeThreadSubscriptionUpdate value,
) {
  return value.when(
    snapshot: (snapshot) =>
        ThreadSnapshotFrame(workspace: _threadWorkspaceFromSnapshot(snapshot)),
    notification: (envelope) {
      final threadId = envelope.threadId;
      final revision = envelope.revision.toInt();
      final epoch = envelope.epoch.toInt();
      final baseRevision = envelope.baseRevision.toInt();
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
          dropped: dropped.toInt(),
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
    revision: value.revision.toInt(),
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
    revision: value.revision.toInt(),
    turnId: value.turnId,
    inputId: value.inputId,
    attemptId: value.attemptId,
    kind: switch (value.kind) {
      frb_activity.BridgeThreadActivityKind.preparing =>
        ThreadActivityKind.preparing,
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
    ordinal: value.ordinal?.toInt(),
    startedAt: _frbNullableInt(value.startedAt),
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
    faultGeneration: value.faultGeneration.toInt(),
    acceptedSequence: value.acceptedSequence?.toInt(),
    durableSequence: value.durableSequence?.toInt(),
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
    revision: value.revision?.toInt(),
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
    ordinal: value.ordinal?.toInt(),
    startedAt: _frbNullableInt(value.startedAt),
  );
}

StudioThread _threadFromFrb(frb.BridgeThread value) {
  return StudioThread(
    id: value.id,
    projectId: value.projectId,
    title: value.title,
    mode: ThreadModeId.fromId(value.mode),
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

ThreadItemView _threadItemFromFrb(
  frb_item.BridgeThreadItem value, {
  ThreadContextDisposition contextDisposition = ThreadContextDisposition.active,
  bool exactNumbers = false,
}) {
  return ThreadItemView(
    id: value.id,
    threadId: value.threadId,
    turnId: value.turnId,
    ordinal: exactNumbers
        ? _exactTimelineInt(value.ordinal, 'item ordinal')
        : value.ordinal.toInt(),
    revision: exactNumbers
        ? _exactTimelineInt(value.revision, 'item revision')
        : value.revision.toInt(),
    createdAt: _dateFromUnix(value.createdAt),
    updatedAt: _dateFromUnix(value.updatedAt),
    state: _threadItemStateFromFrb(value.state),
    contextDisposition: contextDisposition,
  );
}

ThreadItemStateView _threadItemStateFromFrb(
  frb_item.BridgeThreadItemState value,
) {
  return value.when(
    text: (channel, text, attachments, lifecycle) => ThreadTextItemStateView(
      channel: switch (channel) {
        frb_item.BridgeThreadTextChannel.user => ThreadTextChannel.user,
        frb_item.BridgeThreadTextChannel.parentAgent =>
          ThreadTextChannel.parentAgent,
        frb_item.BridgeThreadTextChannel.commentary =>
          ThreadTextChannel.commentary,
        frb_item.BridgeThreadTextChannel.final_ =>
          ThreadTextChannel.finalAnswer,
      },
      text: text,
      attachments: attachments.map(_attachmentFromFrb).toList(),
      lifecycle: _contentLifecycleFromFrb(lifecycle),
    ),
    thinking: (summary, content, lifecycle) => ThreadThinkingItemStateView(
      summary: summary,
      content: content,
      lifecycle: _contentLifecycleFromFrb(lifecycle),
    ),
    tool: (invocation, state, userInput) => ThreadToolItemStateView(
      invocation: ThreadToolInvocationView(
        taskId: invocation.taskId,
        toolCallId: invocation.toolCallId,
        callId: invocation.callId,
        providerItemId: invocation.providerItemId,
        name: invocation.name,
        arguments: invocation.arguments,
        workingDirectory: invocation.workingDirectory,
      ),
      lifecycle: _toolLifecycleFromFrb(state),
      userInput: userInput == null ? null : _userInputFromFrb(userInput),
    ),
    agent: (identity, state) => ThreadAgentItemStateView(
      identity: ThreadAgentIdentityView(
        id: identity.id,
        path: identity.path,
        parentPath: identity.parentPath,
        role: identity.role,
        task: identity.task,
        depth: identity.depth,
      ),
      lifecycle: _agentLifecycleFromFrb(state),
    ),
    turn: (state, inputId) =>
        ThreadTurnItemStateView(_turnStateFromFrb(state), inputId: inputId),
    inference: (inferenceId, model, state) => ThreadInferenceItemStateView(
      inferenceId: inferenceId,
      model: model,
      lifecycle: _inferenceLifecycleFromFrb(state),
    ),
    skill: (name, source, providerId, resourceBase, cause, activatedAt) =>
        ThreadSkillItemStateView(
          name: name,
          source: source,
          providerId: providerId,
          resourceBase: resourceBase.when(
            directory: (path) =>
                SkillResourceBaseView(SkillResourceBaseKind.directory, path),
            url: (url) => SkillResourceBaseView(SkillResourceBaseKind.url, url),
            opaque: (description) => SkillResourceBaseView(
              SkillResourceBaseKind.opaque,
              description,
            ),
          ),
          cause: cause.when(
            tool: (toolCallId) => SkillActivationCauseView(
              SkillActivationCauseKind.tool,
              toolCallId,
            ),
            userGesture: (invocationId) => SkillActivationCauseView(
              SkillActivationCauseKind.userGesture,
              invocationId,
            ),
          ),
          activatedAt: _dateFromUnix(activatedAt),
        ),
    file: (path, mediaType, completedAt) =>
        ThreadFileItemStateView(path, mediaType, _dateFromUnix(completedAt)),
    raw: (payloads, notice, recordedAt) => ThreadRawItemStateView(
      payloads
          .map(
            (payload) => RawHistoryPayload(
              payload.format,
              payload.version,
              payload.content,
            ),
          )
          .toList(),
      notice,
      _dateFromUnix(recordedAt),
    ),
    contextCompaction: (beforeTokens, afterTokens, compactedAt) =>
        ThreadContextCompactionItemStateView(
          beforeTokens?.toInt(),
          afterTokens?.toInt(),
          _dateFromUnix(compactedAt),
        ),
  );
}

/// 普通问答投影 → domain typed 视图：问题顺序、权威状态与脱敏标记原样过桥。
ThreadToolUserInputView _userInputFromFrb(
  frb_item.BridgeThreadUserInput value,
) {
  return ThreadToolUserInputView(
    interactionId: value.interactionId,
    questions: [
      for (final question in value.questions)
        UserQuestionView(
          id: question.id,
          header: question.header,
          question: question.question,
          isOther: question.isOther,
          isSecret: question.isSecret,
          options: [
            for (final option in question.options)
              UserQuestionOptionView(
                label: option.label,
                description: option.description,
              ),
          ],
        ),
    ],
    state: value.state.when(
      pending: () => const PendingThreadToolUserInputView(),
      resolved: (answers) => ResolvedThreadToolUserInputView([
        for (final answer in answers)
          ThreadUserInputAnswerView(
            questionId: answer.questionId,
            answers: answer.answers,
            redacted: answer.redacted,
          ),
      ]),
      cancelled: () => const CancelledThreadToolUserInputView(),
    ),
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
    byteSize: value.byteSize.toInt(),
  );
}

ThreadToolLifecycleView _toolLifecycleFromFrb(
  frb_item.BridgeThreadToolState value,
) {
  return value.when(
    queued: () => const QueuedThreadToolView(),
    cancelling: (streamedOutput) => CancellingThreadToolView(streamedOutput),
    interrupted: (interruptedAt, reason) =>
        InterruptedThreadToolView(_dateFromUnix(interruptedAt), reason),
    started: () => const StartedThreadToolView(),
    streaming: () => const StreamingThreadToolView(),
    awaitingApproval: () => const AwaitingApprovalThreadToolView(),
    approved: () => const ApprovedThreadToolView(),
    running: (streamedOutput) => RunningThreadToolView(streamedOutput),
    succeeded: (completedAt, output) => SucceededThreadToolView(
      _dateFromUnix(completedAt),
      _toolOutputFromFrb(output),
    ),
    failed: (failedAt, failure, output) => FailedThreadToolView(
      _dateFromUnix(failedAt),
      ThreadToolFailureView(
        kind: switch (failure.kind) {
          frb_item.BridgeThreadToolFailureKind.execution =>
            ThreadToolFailureKindView.execution,
          frb_item.BridgeThreadToolFailureKind.timedOut =>
            ThreadToolFailureKindView.timedOut,
          frb_item.BridgeThreadToolFailureKind.budgetLimited =>
            ThreadToolFailureKindView.budgetLimited,
        },
        message: failure.message,
      ),
      output == null ? null : _toolOutputFromFrb(output),
    ),
    denied: (deniedAt, reason) =>
        DeniedThreadToolView(_dateFromUnix(deniedAt), reason),
    cancelled: (cancelledAt, reason) =>
        CancelledThreadToolView(_dateFromUnix(cancelledAt), reason),
  );
}

ThreadToolOutputView _toolOutputFromFrb(frb_item.BridgeThreadToolOutput value) {
  return ThreadToolOutputView(
    result: value.result,
    attachments: value.attachments.map(_attachmentFromFrb).toList(),
    outputArtifacts: value.outputArtifactsJson
        .map(JsonLeafDecoder.decode)
        .toList(),
    exitCode: value.exitCode,
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
        promptTokens: usage.promptTokens.toInt(),
        completionTokens: usage.completionTokens.toInt(),
        cachedPromptTokens: usage.cachedPromptTokens.toInt(),
        totalTokens: usage.totalTokens.toInt(),
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
    revision: value.revision.toInt(),
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
              elapsedMs: limit.usage.elapsedMs.toInt(),
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
    retryAfterMs: value.retryAfterMs?.toInt(),
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
            accountId: value.modelRoute!.accountId,
            modelId: value.modelRoute!.modelId,
            effort: value.modelRoute!.effort,
            revision: value.modelRoute!.revision.toInt(),
            available: value.modelRoute!.available,
            unavailableReason: value.modelRoute!.unavailableReason,
          ),
    liveUsage: value.liveUsage == null
        ? null
        : ThreadRuntimeLiveUsageView(
            turnId: value.liveUsage!.turnId,
            attemptId: value.liveUsage!.attemptId,
            completionTokens: value.liveUsage!.completionTokens?.toInt(),
            decodeMillis: value.liveUsage!.decodeMillis?.toInt(),
            latestContextTokens: value.liveUsage!.latestContextTokens?.toInt(),
            state:
                value.liveUsage!.state == frb.BridgeThreadRuntimeUsageState.live
                ? ThreadRuntimeUsageState.live
                : ThreadRuntimeUsageState.authoritative,
            observationSequence: value.liveUsage!.observationSequence.toInt(),
          ),
    contextTokens: usage.latestContextTokens.toInt(),
    contextWindow: usage.contextWindow?.toInt() ?? 0,
    maxContextWindow: usage.maxContextWindow?.toInt(),
    autoCompactLimit: usage.autoCompactLimit?.toInt(),
    totalTokens: usage.totalTokens.toInt(),
    promptTokens: usage.promptTokens.toInt(),
    completionTokens: usage.completionTokens.toInt(),
    cachedPromptTokens: usage.cachedPromptTokens.toInt(),
    cacheWriteTokens: usage.cacheWriteTokens.toInt(),
    reasoningTokens: usage.reasoningTokens.toInt(),
    inferenceCount: usage.inferenceCount.toInt(),
    cacheUsage: CacheUsageView(
      inputTokens: usage.cacheUsage.inputTokens.toInt(),
      cacheReadTokens: usage.cacheUsage.cacheReadTokens.toInt(),
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
    promptGeneration: usage.promptGeneration?.toInt(),
    promptCachePolicy: usage.promptCachePolicy,
    prefixChangedReason: usage.prefixChangedReason?.name,
    turnCompletionTokens: value.turnCompletionTokens.toInt(),
    turnDecodeMillis: value.turnDecodeMillis.toInt(),
    costLabel: costLabel,
    activeSkills: value.activeSkills,
    activeMcpServers: value.activeMcpServers,
    activeLspServers: value.activeLspServers,
    workflow: value.workflow == null
        ? null
        : _workflowRuntimeFromFrb(value.workflow!),
    plan: value.plan == null ? null : _planRuntimeFromFrb(value.plan!),
  );
}

PlanRuntimeView _planRuntimeFromFrb(frb.BridgePlanRuntimeSnapshot value) {
  final document = value.document;
  return PlanRuntimeView(
    revision: value.revision.toInt(),
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
            version: document.version.toInt(),
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
    revision: value.revision.toInt(),
    currentRun: run == null
        ? null
        : WorkflowRunView(
            lineageId: run.lineageId,
            runId: run.runId,
            modeId: run.modeId,
            graphRevision: run.graphRevision.toInt(),
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
            arguments: JsonLeafDecoder.decode(argumentsJson),
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
  );
}

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

int _compareThreadItems(ThreadItemView left, ThreadItemView right) {
  final ordinal = left.ordinal.compareTo(right.ordinal);
  return ordinal != 0 ? ordinal : left.id.compareTo(right.id);
}

abstract final class JsonLeafDecoder {
  static Object? decode(String json) {
    try {
      return jsonDecode(json);
    } on FormatException catch (error) {
      throw FormatException('Invalid typed bridge JSON leaf: ${error.message}');
    }
  }

  static Map<String, Object?> decodeObject(String json) {
    final value = decode(json);
    if (value is Map<String, Object?>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    throw const FormatException('Typed bridge JSON leaf must be an object');
  }
}

/// 把任意错误统一包装成 typed [StudioFailure]。
///
/// 保留桥错误已有的 `code`/`message`/`correlationId`（含关闭路径）；已知变体通过穷尽
/// switch 映射，未知桥变体不再触发 `values.byName` 抛出的 `ArgumentError`，非桥错误也
/// 统一为 typed 失败而不是漏出未包装的分支。
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
    ),
    _ => StudioFailure(
      code: StudioFailureCode.internal,
      message: error.toString(),
      retryable: false,
      correlationId: newStudioCorrelationId(),
    ),
  };
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
