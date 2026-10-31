part of 'studio_api.dart';

ConversationDescriptor _descriptorFromFrb(
  frb_descriptor.BridgeTimelineDescriptor value,
) => value.when(
  text: (value) => ConversationTextDescriptor(
    channel: switch (value.channel) {
      frb_item.BridgeThreadTextChannel.user => ThreadTextChannel.user,
      frb_item.BridgeThreadTextChannel.parentAgent =>
        ThreadTextChannel.parentAgent,
      frb_item.BridgeThreadTextChannel.commentary =>
        ThreadTextChannel.commentary,
      frb_item.BridgeThreadTextChannel.final_ => ThreadTextChannel.finalAnswer,
    },
    attachments: List.unmodifiable(value.attachments.map(_attachmentFromFrb)),
    outcome: _conversationContentOutcome(value.outcome),
  ),
  thinking: (value) => ConversationThinkingDescriptor(
    outcome: _conversationContentOutcome(value.outcome),
  ),
  tool: _toolDescriptorFromFrb,
  raw: (value) => ConversationRawDescriptor(
    origin: switch (value.origin) {
      frb_item.BridgeRawItemOrigin.stored => ThreadRawItemOrigin.stored,
      frb_item.BridgeRawItemOrigin.runtimeControl =>
        ThreadRawItemOrigin.runtimeControl,
    },
    payloads: List.unmodifiable(
      value.payloads.map(
        (payload) => ConversationRawPayloadDescriptor(
          format: payload.format,
          version: payload.version,
        ),
      ),
    ),
    notice: value.notice,
    recordedAt: _dateFromUnix(value.recordedAt),
  ),
  agent: (identity, outcome) => ConversationAgentDescriptor(
    identity: ThreadAgentIdentityView(
      id: identity.id,
      path: identity.path,
      parentPath: identity.parentPath,
      role: identity.role,
      task: identity.task,
      depth: identity.depth,
    ),
    outcome: outcome.when(
      succeeded: (at, summary) => ConversationAgentSucceeded(
        SucceededThreadAgentView(_dateFromUnix(at), summary),
      ),
      denied: (at, reason) => ConversationAgentDenied(
        DeniedThreadAgentView(_dateFromUnix(at), reason),
      ),
      failed: (at, error) => ConversationAgentFailed(
        FailedThreadAgentView(_dateFromUnix(at), error),
      ),
      cancelled: (at, reason) => ConversationAgentCancelled(
        CancelledThreadAgentView(_dateFromUnix(at), reason),
      ),
    ),
  ),
  turn: (outcome, inputId) => ConversationTurnDescriptor(
    inputId: inputId,
    outcome: outcome.when(
      completed: (startedAt, completedAt, completion) =>
          ConversationTurnCompleted(
            CompletedStudioTurnState(
              startedAt: _exactNullableSignedTimelineInt(startedAt),
              completedAt: _exactSignedTimelineInt(completedAt),
              completion: switch (completion) {
                frb.BridgeTurnCompletion.normal => StudioTurnCompletion.normal,
                frb.BridgeTurnCompletion.interactionRequested =>
                  StudioTurnCompletion.interactionRequested,
              },
            ),
          ),
      cancelled: (startedAt, requestedAt, completedAt, cause) =>
          ConversationTurnCancelled(
            CancelledStudioTurnState(
              startedAt: _exactNullableSignedTimelineInt(startedAt),
              requestedAt: _exactSignedTimelineInt(requestedAt),
              completedAt: _exactSignedTimelineInt(completedAt),
              cause: _turnCancellationCauseFromFrb(cause),
            ),
          ),
      failed: (startedAt, completedAt, failure) => ConversationTurnFailed(
        FailedStudioTurnState(
          startedAt: _exactNullableSignedTimelineInt(startedAt),
          completedAt: _exactSignedTimelineInt(completedAt),
          failure: _turnFailureFromFrb(failure),
        ),
      ),
      budgetLimited: (startedAt, completedAt, limit, rollover) =>
          ConversationTurnBudgetLimited(
            BudgetLimitedStudioTurnState(
              startedAt: _exactNullableSignedTimelineInt(startedAt),
              completedAt: _exactSignedTimelineInt(completedAt),
              limit: StudioTurnBudgetLimit(
                kind: StudioTurnBudgetLimitKind.values.byName(limit.kind.name),
                usage: StudioTurnBudgetUsage(
                  modelSteps: limit.usage.modelSteps,
                  toolCalls: limit.usage.toolCalls,
                  waitCalls: limit.usage.waitCalls,
                  elapsedMs: _exactTimelineInt(
                    limit.usage.elapsedMs,
                    'elapsed ms',
                  ),
                ),
              ),
              rollover: rollover.when(
                notAttempted: () => const RolloverNotAttempted(),
                succeeded: () => const RolloverSucceeded(),
                failed: (error) => RolloverFailed(error: error),
              ),
            ),
          ),
    ),
  ),
  inference: (inferenceId, model, outcome) => ConversationInferenceDescriptor(
    inferenceId: inferenceId,
    model: model,
    outcome: outcome.when(
      completed: (at, usage) => ConversationInferenceCompleted(
        CompletedThreadInferenceView(
          _dateFromUnix(at),
          ThreadInferenceUsageView(
            promptTokens: _exactTimelineInt(
              usage.promptTokens,
              'prompt tokens',
            ),
            completionTokens: _exactTimelineInt(
              usage.completionTokens,
              'completion tokens',
            ),
            cachedPromptTokens: _exactTimelineInt(
              usage.cachedPromptTokens,
              'cached tokens',
            ),
            totalTokens: _exactTimelineInt(usage.totalTokens, 'total tokens'),
          ),
        ),
      ),
      failed: (at, error) => ConversationInferenceFailed(
        FailedThreadInferenceView(_dateFromUnix(at), error),
      ),
      cancelled: (at, reason) => ConversationInferenceCancelled(
        CancelledThreadInferenceView(_dateFromUnix(at), reason),
      ),
    ),
  ),
  skill: (name, source, providerId, resourceBase, cause, activatedAt) =>
      ConversationSkillDescriptor(
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
      ),
  file: (path, mediaType, completedAt) => ConversationFileDescriptor(
    ThreadFileItemStateView(path, mediaType, _dateFromUnix(completedAt)),
  ),
  contextCompaction: (beforeTokens, afterTokens, compactedAt) =>
      ConversationContextCompactionDescriptor(
        ThreadContextCompactionItemStateView(
          beforeTokens == null
              ? null
              : _exactTimelineInt(beforeTokens, 'before tokens'),
          afterTokens == null
              ? null
              : _exactTimelineInt(afterTokens, 'after tokens'),
          _dateFromUnix(compactedAt),
        ),
      ),
  plan: (interactionId, documentVersion, contentHash, decision) =>
      ConversationPlanDescriptor(
        interactionId: interactionId,
        documentVersion: _exactNullableTimelineInt(
          documentVersion,
          'plan version',
        ),
        contentHash: contentHash,
        decision: switch (decision) {
          frb_descriptor.BridgeTimelinePlanDecision.approved =>
            ConversationPlanDecision.approved,
          frb_descriptor.BridgeTimelinePlanDecision.revisionRequested =>
            ConversationPlanDecision.revisionRequested,
          frb_descriptor.BridgeTimelinePlanDecision.cancelled =>
            ConversationPlanDecision.cancelled,
          frb_descriptor.BridgeTimelinePlanDecision.resolved =>
            ConversationPlanDecision.resolved,
        },
      ),
);

ConversationContentOutcome _conversationContentOutcome(
  frb_descriptor.BridgeTimelineContentOutcome value,
) => value.when(
  completed: (at) => ConversationContentCompleted(
    CompletedThreadContentView(_dateFromUnix(at)),
  ),
  failed: (at, error) => ConversationContentFailed(
    FailedThreadContentView(_dateFromUnix(at), error),
  ),
  cancelled: (at, reason) => ConversationContentCancelled(
    CancelledThreadContentView(_dateFromUnix(at), reason),
  ),
);
