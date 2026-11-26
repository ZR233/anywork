part of 'studio_api.dart';

CurrentContentRef _currentContentRefFromFrb(
  frb_presentation.BridgeCurrentContentRef value,
) => CurrentContentRef(
  ownerId: value.ownerId,
  domain: value.domain,
  entityId: value.entityId,
  contentKey: value.contentKey,
  generation: value.generation,
);

CurrentStateField _currentStateFieldFromFrb(
  frb_presentation.BridgeCurrentStateField value,
) => switch (value) {
  frb_presentation.BridgeCurrentStateField_Body(
    :final field,
    :final reference,
    :final byteLength,
  ) =>
    BodyCurrentStateField(
      field: field,
      reference: _currentContentRefFromFrb(reference),
      byteLength: exactTimelineInt(byteLength, 'State field byte length'),
    ),
  frb_presentation.BridgeCurrentStateField_Collection(
    :final field,
    :final reference,
    :final count,
  ) =>
    CollectionCurrentStateField(
      field: field,
      reference: _currentCollectionRefFromFrb(reference),
      count: exactTimelineInt(count, 'State collection count'),
    ),
};

CurrentCollectionRef _currentCollectionRefFromFrb(
  frb_presentation.BridgeCurrentCollectionRef value,
) => CurrentCollectionRef(
  ownerId: value.ownerId,
  collection: value.collection,
  revision: exactTimelineInt(value.revision, 'current collection revision'),
);

BodyRef _bodyRefFromFrb(frb_presentation.BridgeBodyRef value) => BodyRef(
  databaseId: value.databaseId,
  bodyId: value.bodyId,
  ownerEventId: value.ownerEventId,
  bodyKey: value.bodyKey,
  role: value.role,
  byteLength: exactTimelineInt(value.byteLength, 'body length'),
  mediaType: value.mediaType,
  inlineText: value.inlineText,
);

frb_presentation.BridgeBodyRef _bodyRefToFrb(BodyRef value) =>
    frb_presentation.BridgeBodyRef(
      databaseId: value.databaseId,
      bodyId: value.bodyId,
      ownerEventId: value.ownerEventId,
      bodyKey: value.bodyKey,
      role: value.role,
      byteLength: BigInt.from(value.byteLength),
      mediaType: value.mediaType,
      inlineText: value.inlineText,
    );

BodyWindow _bodyWindowFromFrb(frb_presentation.BridgeBodyWindow value) =>
    BodyWindow(
      offset: exactTimelineInt(value.offset, 'body offset'),
      text: value.text,
      bytesBase64: value.bytesBase64,
      totalBytes: exactTimelineInt(value.totalBytes, 'body length'),
      eof: value.eof,
    );

frb_presentation.BridgeSessionDetailKind _sessionDetailKindToFrb(
  SessionDetailKind kind,
) => switch (kind) {
  SessionDetailKind.plan => frb_presentation.BridgeSessionDetailKind.plan,
  SessionDetailKind.interactions =>
    frb_presentation.BridgeSessionDetailKind.interactions,
  SessionDetailKind.todo => frb_presentation.BridgeSessionDetailKind.todo,
  SessionDetailKind.workflow =>
    frb_presentation.BridgeSessionDetailKind.workflow,
  SessionDetailKind.activeSkills =>
    frb_presentation.BridgeSessionDetailKind.activeSkills,
  SessionDetailKind.activeMcpServers =>
    frb_presentation.BridgeSessionDetailKind.activeMcpServers,
  SessionDetailKind.activeLspServers =>
    frb_presentation.BridgeSessionDetailKind.activeLspServers,
};

SessionDetailWindow _sessionDetailWindowFromFrb(
  frb_presentation.BridgeSessionDetailWindow value,
) => SessionDetailWindow(
  ownerEpoch: value.ownerEpoch,
  revision: exactTimelineInt(value.revision, 'session detail revision'),
  offset: exactTimelineInt(value.offset, 'session detail offset'),
  totalBytes: exactTimelineInt(value.totalBytes, 'session detail length'),
  bytes: value.bytes,
);

int? _timelineMillisFromFrb(Object? value) =>
    value == null ? null : _exactSignedTimelineInt(value);

StudioModelRecoveryNotice _recoveryNoticeFromFrb(
  frb_presentation.BridgeModelRecoveryNotice value,
) => StudioModelRecoveryNotice(
  phase: StudioModelRecoveryPhase.values.byName(value.phase.name),
  retryCount: value.retryCount,
  maxRetries: value.maxRetries,
  effectiveWaitMillis: value.effectiveWaitMillis,
  failureKind: value.failureKind,
  reason: StudioProviderRecovery.values.asNameMap()[value.reason],
  failure: value.failure == null ? null : _turnFailureFromFrb(value.failure!),
);

TimelineItem _timelineItemFromFrb(
  frb_presentation.BridgeTimelineItem value,
) => switch (value) {
  final frb_presentation.BridgeTimelineItem_UserMessage row =>
    TimelineUserMessage(
      id: row.id,
      seq: exactTimelineInt(row.seq, 'sequence'),
      turnId: row.turnId,
      inputId: row.inputId,
      channel: row.channel,
      text: row.text,
      attachments: jsonDecode(row.attachmentsJson) as List<Object?>,
      occurredAtMs: _timelineMillisFromFrb(row.occurredAtMs),
    ),
  final frb_presentation.BridgeTimelineItem_AssistantText row =>
    TimelineAssistantText(
      id: row.id,
      seq: exactTimelineInt(row.seq, 'sequence'),
      turnId: row.turnId,
      attemptId: row.attemptId,
      channel: row.channel,
      text: row.text,
      bodyRef: row.bodyRef == null ? null : _bodyRefFromFrb(row.bodyRef!),
      isFinalTurnDelivery: row.isFinalTurnDelivery,
      outcome: row.outcome,
      modelRecovery: row.modelRecovery == null
          ? null
          : _recoveryNoticeFromFrb(row.modelRecovery!),
      occurredAtMs: _timelineMillisFromFrb(row.occurredAtMs),
    ),
  final frb_presentation.BridgeTimelineItem_WorkGroup row => TimelineWorkGroup(
    id: row.id,
    firstSeq: exactTimelineInt(row.firstSeq, 'first sequence'),
    lastSeq: exactTimelineInt(row.lastSeq, 'last sequence'),
    afterBoundarySeq: _exactNullableTimelineInt(
      row.afterBoundarySeq,
      'previous boundary sequence',
    ),
    beforeBoundarySeq: _exactNullableTimelineInt(
      row.beforeBoundarySeq,
      'next boundary sequence',
    ),
    memberCount: row.memberCount,
    summary: row.summary,
    status: WorkGroupStatus.values.byName(row.status.name),
    startedAtMs: _timelineMillisFromFrb(row.startedAtMs),
    finishedAtMs: _timelineMillisFromFrb(row.finishedAtMs),
  ),
  final frb_presentation.BridgeTimelineItem_Compaction row =>
    TimelineCompaction(
      id: row.id,
      seq: exactTimelineInt(row.seq, 'sequence'),
      turnId: row.turnId,
      summary: row.summary,
      outcome: row.outcome,
      tokensBefore: _exactNullableTimelineInt(
        row.tokensBefore,
        'pre-compaction tokens',
      ),
      tokensAfter: _exactNullableTimelineInt(
        row.tokensAfter,
        'post-compaction tokens',
      ),
      occurredAtMs: _timelineMillisFromFrb(row.occurredAtMs),
    ),
  final frb_presentation.BridgeTimelineItem_PlanResolution row =>
    TimelinePlanResolution(
      id: row.id,
      seq: exactTimelineInt(row.seq, 'sequence'),
      turnId: row.turnId,
      decision: row.decision,
      document: row.document,
      documentRef: row.documentRef == null
          ? null
          : _bodyRefFromFrb(row.documentRef!),
      feedback: row.feedback,
      occurredAtMs: _timelineMillisFromFrb(row.occurredAtMs),
    ),
  final frb_presentation.BridgeTimelineItem_ConnectionNotice row =>
    TimelineConnectionNotice(
      id: row.id,
      seq: exactTimelineInt(row.seq, 'sequence'),
      turnId: row.turnId,
      scope: row.scope,
      state: row.state,
      transport: row.transport,
      fallbackTransport: row.fallbackTransport,
      attempt: row.attempt,
      maxAttempts: row.maxAttempts,
      recoverable: row.recoverable,
      reason: row.reason,
      durationMs: _exactNullableTimelineInt(
        row.durationMs,
        'connection duration',
      ),
      occurredAtMs: _timelineMillisFromFrb(row.occurredAtMs),
    ),
  final frb_presentation.BridgeTimelineItem_TurnOutcome row =>
    TimelineTurnOutcome(
      id: row.id,
      seq: exactTimelineInt(row.seq, 'sequence'),
      turnId: row.turnId,
      inputId: row.inputId,
      outcome: row.outcome,
      message: row.message,
      turnFailure: row.turnFailure == null
          ? null
          : _turnFailureFromFrb(row.turnFailure!),
      occurredAtMs: _timelineMillisFromFrb(row.occurredAtMs),
    ),
  final frb_presentation.BridgeTimelineItem_StandaloneTool row =>
    TimelineStandaloneTool(
      id: row.id,
      seq: exactTimelineInt(row.seq, 'sequence'),
      turnId: row.turnId,
      callId: row.callId,
      toolName: row.toolName,
      presentationContract: row.presentationContract,
      state: row.state,
      summary: row.summary,
      payloadJson: row.payloadJson,
      bodies: row.bodies.map(_bodyRefFromFrb),
      occurredAtMs: _timelineMillisFromFrb(row.occurredAtMs),
    ),
  final frb_presentation.BridgeTimelineItem_Fallback row => TimelineFallback(
    id: row.id,
    seq: exactTimelineInt(row.seq, 'sequence'),
    eventId: row.eventId,
    eventKind: row.eventKind,
    reason: row.reason,
    rawPreview: row.rawPreview,
    occurredAtMs: _timelineMillisFromFrb(row.occurredAtMs),
  ),
};

WorkGroupMember _workGroupMemberFromFrb(
  frb_presentation.BridgeWorkGroupMember value,
) => switch (value) {
  final frb_presentation.BridgeWorkGroupMember_Reasoning row =>
    WorkGroupReasoning(
      id: row.id,
      seq: exactTimelineInt(row.seq, 'sequence'),
      text: row.text,
      summary: row.summary,
      bodyRef: row.bodyRef == null ? null : _bodyRefFromFrb(row.bodyRef!),
      outcome: row.outcome,
      startedAtMs: _timelineMillisFromFrb(row.startedAtMs),
      finishedAtMs: _timelineMillisFromFrb(row.finishedAtMs),
    ),
  final frb_presentation.BridgeWorkGroupMember_ToolCall row =>
    WorkGroupToolCall(
      id: row.id,
      seq: exactTimelineInt(row.seq, 'sequence'),
      callId: row.callId,
      turnId: row.turnId,
      toolName: row.toolName,
      presentationContract: row.presentationContract,
      status: row.status,
      summary: row.summary,
      arguments: row.arguments,
      resultPreview: row.resultPreview,
      payloadJson: row.payloadJson,
      bodies: row.bodies.map(_bodyRefFromFrb),
      waitJson: row.waitJson,
      startedAtMs: _timelineMillisFromFrb(row.startedAtMs),
      finishedAtMs: _timelineMillisFromFrb(row.finishedAtMs),
    ),
  final frb_presentation.BridgeWorkGroupMember_Agent row => WorkGroupAgent(
    id: row.id,
    seq: exactTimelineInt(row.seq, 'sequence'),
    agentId: row.agentId,
    name: row.name,
    status: row.status,
    summary: row.summary,
    payloadJson: row.payloadJson,
    startedAtMs: _timelineMillisFromFrb(row.startedAtMs),
    finishedAtMs: _timelineMillisFromFrb(row.finishedAtMs),
  ),
  final frb_presentation.BridgeWorkGroupMember_FileChange row =>
    WorkGroupFileChange(
      id: row.id,
      seq: exactTimelineInt(row.seq, 'sequence'),
      summary: row.summary,
      payloadJson: row.payloadJson,
      bodies: row.bodies.map(_bodyRefFromFrb),
      occurredAtMs: _timelineMillisFromFrb(row.occurredAtMs),
    ),
  final frb_presentation.BridgeWorkGroupMember_Skill row => WorkGroupSkill(
    id: row.id,
    seq: exactTimelineInt(row.seq, 'sequence'),
    name: row.name,
    summary: row.summary,
    payloadJson: row.payloadJson,
    occurredAtMs: _timelineMillisFromFrb(row.occurredAtMs),
  ),
  final frb_presentation.BridgeWorkGroupMember_Fallback row =>
    WorkGroupFallback(
      id: row.id,
      seq: exactTimelineInt(row.seq, 'sequence'),
      eventId: row.eventId,
      eventKind: row.eventKind,
      reason: row.reason,
      occurredAtMs: _timelineMillisFromFrb(row.occurredAtMs),
    ),
};

TimelinePatch _timelinePatchFromFrb(
  frb_presentation.BridgeTimelinePatch value,
) => switch (value) {
  frb_presentation.BridgeTimelinePatch_Reset(
    :final items,
    :final hasMoreOlder,
    :final olderCursor,
    :final revision,
  ) =>
    TimelineReset(
      items: items.map(_timelineItemFromFrb),
      hasMoreOlder: hasMoreOlder,
      olderCursor: olderCursor,
      revision: exactTimelineInt(revision, 'reset revision'),
    ),
  frb_presentation.BridgeTimelinePatch_PrependOlder(
    :final items,
    :final hasMoreOlder,
    :final olderCursor,
  ) =>
    TimelinePrependOlder(
      items: items.map(_timelineItemFromFrb),
      hasMoreOlder: hasMoreOlder,
      olderCursor: olderCursor,
    ),
  frb_presentation.BridgeTimelinePatch_Append(:final items) => TimelineAppend(
    items: items.map(_timelineItemFromFrb),
  ),
  frb_presentation.BridgeTimelinePatch_Update(:final item) => TimelineUpdate(
    item: _timelineItemFromFrb(item),
  ),
  frb_presentation.BridgeTimelinePatch_Remove(:final itemId) => TimelineRemove(
    itemId: itemId,
  ),
};

LiveStatusSnapshot _liveStatusFromFrb(
  frb_presentation.BridgeLiveStatusSnapshot value,
) => LiveStatusSnapshot(
  revision: exactTimelineInt(value.revision, 'live status revision'),
  phase: switch (value.phase) {
    frb_presentation.BridgeLiveStatusPhase_Idle() => const LiveStatusIdle(),
    final frb_presentation.BridgeLiveStatusPhase_Working phase =>
      LiveStatusWorking(
        items: phase.items.map(_liveWorkItemFromFrb),
        reasoningPreview: phase.reasoningPreview,
        startedAtMs: _timelineMillisFromFrb(phase.startedAtMs),
      ),
    final frb_presentation.BridgeLiveStatusPhase_StreamingText phase =>
      LiveStatusStreamingText(
        attemptId: phase.attemptId,
        itemId: phase.itemId,
        text: phase.text,
        startedAtMs: _timelineMillisFromFrb(phase.startedAtMs),
      ),
    final frb_presentation.BridgeLiveStatusPhase_Compacting phase =>
      LiveStatusCompacting(
        manual: phase.manual,
        startedAtMs: _timelineMillisFromFrb(phase.startedAtMs),
      ),
    final frb_presentation.BridgeLiveStatusPhase_Reconnecting phase =>
      LiveStatusReconnecting(
        attemptId: phase.attemptId,
        message: phase.message,
        retryAfterMs: _exactNullableTimelineInt(
          phase.retryAfterMs,
          'retry delay',
        ),
        attempt: phase.attempt,
        maxAttempts: phase.maxAttempts,
      ),
    final frb_presentation.BridgeLiveStatusPhase_Stopping phase =>
      LiveStatusStopping(
        startedAtMs: _timelineMillisFromFrb(phase.startedAtMs),
      ),
  },
  attentions: value.attentions.map(
    (attention) => LiveAttention(
      id: attention.id,
      kind: attention.kind,
      summary: attention.summary,
      callId: attention.callId,
    ),
  ),
  suppressedByInteraction: value.suppressedByInteraction,
);

LiveWorkItem _liveWorkItemFromFrb(frb_presentation.BridgeLiveWorkItem value) =>
    LiveWorkItem(
      id: value.id,
      callId: value.callId,
      kind: value.kind,
      toolName: value.toolName,
      status: value.status,
      summary: value.summary,
      startedAtMs: _timelineMillisFromFrb(value.startedAtMs),
      finishedAtMs: _timelineMillisFromFrb(value.finishedAtMs),
    );

ConversationFeedEvent _conversationEventFromFrb(
  frb_presentation.BridgeConversationEvent value,
) => switch (value) {
  frb_presentation.BridgeConversationEvent_Timeline(:final patch) =>
    ConversationTimeline(patch: _timelinePatchFromFrb(patch)),
  frb_presentation.BridgeConversationEvent_LiveStatus(:final snapshot) =>
    ConversationLiveStatus(snapshot: _liveStatusFromFrb(snapshot)),
  frb_presentation.BridgeConversationEvent_SessionMeta(:final snapshot) =>
    ConversationSessionMeta(snapshot: _sessionMetaFromFrb(snapshot)),
  frb_presentation.BridgeConversationEvent_InputPresented(
    :final inputId,
    :final itemId,
  ) =>
    ConversationInputPresented(inputId: inputId, itemId: itemId),
  frb_presentation.BridgeConversationEvent_ResyncRequired(:final reason) =>
    ConversationResyncRequired(reason: reason),
};

SessionMetaSnapshot _sessionMetaFromFrb(
  frb_presentation.BridgeSessionMetaSnapshot value,
) => SessionMetaSnapshot(
  threadId: value.threadId,
  status: _threadStatusFromFrb(value.status),
  title: value.title,
  parentThreadId: value.parentThreadId,
  rootThreadId: value.rootThreadId,
  ownerEpoch: value.ownerEpoch,
  revision: exactTimelineInt(value.revision, 'session metadata revision'),
  activeTurn: value.activeTurn == null ? null : _turnFromFrb(value.activeTurn!),
  lastTurn: value.lastTurn == null ? null : _turnFromFrb(value.lastTurn!),
  activity: value.activity == null
      ? null
      : _threadActivityFromFrb(value.activity!),
  usage: _sessionUsageFromFrb(value.usage),
  contextMetrics: value.contextMetrics == null
      ? null
      : _conversationRuntimeUsageFromFrb(value.contextMetrics!),
  modelRoute: _threadModelRouteFromFrb(value.modelRoute),
  runtime: value.runtime == null
      ? null
      : _conversationRuntimeFromFrb(value.runtime!),
  storageState: value.storageState == null
      ? null
      : _threadStorageFromFrb(value.storageState!),
  interactions: value.interactions
      .where(_interactionIsPending)
      .map(_interactionFromFrb),
  pendingInteractionCount: value.pendingInteractionCount,
  plan: value.plan == null ? null : planRuntimeFromFrb(value.plan!),
  mode: value.mode == null ? null : ThreadModeId.fromId(value.mode!),
  executionPresent: value.executionPresent,
);

SessionUsageSummary _sessionUsageFromFrb(
  frb_presentation.BridgeUsageSummary value,
) {
  final binding = value.binding;
  final totals = value.totals;
  final cache = value.cache;
  final context = value.context;
  final throughput = value.throughput;
  final pricing = value.pricing;
  return SessionUsageSummary(
    appliedSequence: exactTimelineInt(value.appliedSequence, 'usage sequence'),
    binding: binding == null
        ? null
        : SessionModelUsageBinding(
            routeIdentity: binding.routeIdentity,
            model: binding.model,
            contextWindow: _exactNullableTimelineInt(
              binding.contextWindow,
              'context window',
            ),
            maxContextWindow: _exactNullableTimelineInt(
              binding.maxContextWindow,
              'maximum context window',
            ),
            autoCompactLimit: _exactNullableTimelineInt(
              binding.autoCompactLimit,
              'compaction threshold',
            ),
          ),
    totals: SessionUsageTotals(
      inferenceCount: exactTimelineInt(
        totals.inferenceCount,
        'inference count',
      ),
      promptTokens: exactTimelineInt(totals.promptTokens, 'prompt tokens'),
      completionTokens: exactTimelineInt(
        totals.completionTokens,
        'completion tokens',
      ),
      cachedPromptTokens: exactTimelineInt(
        totals.cachedPromptTokens,
        'cached prompt tokens',
      ),
      cacheWriteTokens: exactTimelineInt(
        totals.cacheWriteTokens,
        'cache write tokens',
      ),
      reasoningTokens: exactTimelineInt(
        totals.reasoningTokens,
        'reasoning tokens',
      ),
      totalTokens: exactTimelineInt(totals.totalTokens, 'total tokens'),
    ),
    cache: SessionUsageCache(
      inputTokens: exactTimelineInt(cache.inputTokens, 'cache input tokens'),
      readTokens: exactTimelineInt(cache.readTokens, 'cache read tokens'),
      sampleCount: exactTimelineInt(cache.sampleCount, 'cache sample count'),
      incomplete: cache.incomplete,
    ),
    context: SessionUsageContext(
      tokens: exactTimelineInt(context.tokens, 'context tokens'),
      latestCall: context.latestCall == null
          ? null
          : _sessionUsageObservationFromFrb(context.latestCall!),
    ),
    throughput: SessionUsageThroughput(
      turnId: throughput.turnId,
      completionTokens: exactTimelineInt(
        throughput.completionTokens,
        'turn completion tokens',
      ),
      responseMillis: exactTimelineInt(
        throughput.responseMillis,
        'turn response duration',
      ),
    ),
    diagnostics: _sessionUsageDiagnosticsFromFrb(value.diagnostics),
    pricing: SessionUsagePricing(
      incomplete: pricing.incomplete,
      estimatedCosts: pricing.estimatedCosts.map(_runtimeCostFromFrb),
      estimatedCacheSavings: pricing.estimatedCacheSavings.map(
        _runtimeCostFromFrb,
      ),
    ),
  );
}

SessionUsageDiagnostics _sessionUsageDiagnosticsFromFrb(
  frb_presentation.BridgeUsageDiagnostics value,
) => SessionUsageDiagnostics(
  incompleteCalls: exactTimelineInt(
    value.incompleteCalls,
    'incomplete call count',
  ),
  missingCalls: exactTimelineInt(value.missingCalls, 'missing call count'),
  partialCalls: exactTimelineInt(value.partialCalls, 'partial call count'),
  invalidCalls: exactTimelineInt(value.invalidCalls, 'invalid call count'),
  overflowCalls: exactTimelineInt(value.overflowCalls, 'overflowed call count'),
  byOutcome: value.byOutcome.map(usageOutcomeCountSnapshotFromFrb),
  byPurpose: value.byPurpose.map(usagePurposeCountSnapshotFromFrb),
  otherPurposeCalls: exactTimelineInt(
    value.otherPurposeCalls,
    'other purpose call count',
  ),
  byIssue: value.byIssue.map(usageIssueCountSnapshotFromFrb),
  recentGaps: value.recentGaps.map(_sessionUsageObservationFromFrb),
  legacyUnknown: value.legacyUnknown,
  legacyIncomplete: value.legacyIncomplete,
  countsOverflowed: value.countsOverflowed,
);

UsageCallSnapshot _sessionUsageObservationFromFrb(
  frb_presentation.BridgeUsageObservation value,
) {
  final source = value.source;
  return UsageCallSnapshot(
    threadId: source.threadId,
    callId: source.callId,
    turnId: source.turnId,
    effectSequence: exactTimelineInt(
      source.effectSequence,
      'usage effect sequence',
    ),
    observedAt: _exactSignedTimelineInt(source.observedAt),
    purpose: source.purpose,
    outcome: usageTerminalStatusFromFrb(source.outcome),
    status: usageReportStatusFromFrb(value.status),
    usage: usageReportFromFrb(value.usage),
    issues: value.issues.map(usageGapIssueFromFrb),
  );
}
