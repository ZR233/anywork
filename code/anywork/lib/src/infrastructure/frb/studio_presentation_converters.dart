part of 'studio_api.dart';

HistoryCut _historyCutFromFrb(frb_presentation.BridgeHistoryCut value) =>
    HistoryCut(value.token);

OpenHistory _openHistoryFromFrb(
  frb_presentation.BridgeOpenHistoryReader value,
) => OpenHistory(
  readerId: value.readerId,
  historyProtocolVersion: value.historyProtocolVersion,
);

frb_presentation.BridgeHistoryCut _historyCutToFrb(HistoryCut value) =>
    frb_presentation.BridgeHistoryCut(token: value.token);

frb_presentation.BridgeHistoryDemand _historyDemandToFrb(HistoryDemand value) =>
    frb_presentation.BridgeHistoryDemand(
      maxRows: value.maxRows,
      maxBytes: value.maxBytes,
    );

frb_presentation.BridgeHistoryEventsQuery _historyEventsQueryToFrb(
  HistoryEventsQuery value,
) => switch (value) {
  AllHistoryEvents() =>
    const frb_presentation.BridgeHistoryEventsQuery.allEvents(),
  EntityHistoryEvents(:final entityId) =>
    frb_presentation.BridgeHistoryEventsQuery.entity(entityId: entityId),
  TurnHistoryEvents(:final turnId) =>
    frb_presentation.BridgeHistoryEventsQuery.turn(turnId: turnId),
  SourceHistoryEvents(:final source) =>
    frb_presentation.BridgeHistoryEventsQuery.source(
      source: _chatSourceToFrb(source),
    ),
  CallHistoryEvents(:final callId) =>
    frb_presentation.BridgeHistoryEventsQuery.call(callId: callId),
  OriginalsHistoryEvents(:final queryClass, :final parentId) =>
    frb_presentation.BridgeHistoryEventsQuery.originals(
      queryClass: queryClass,
      parentId: parentId,
    ),
  TextOriginalHistoryEvents() =>
    const frb_presentation.BridgeHistoryEventsQuery.textOriginals(),
};

HistoryTimelineRole _historyTimelineRoleFromFrb(
  frb_presentation.BridgeHistoryTimelineRole value,
) => switch (value) {
  frb_presentation.BridgeHistoryTimelineRole.boundary =>
    HistoryTimelineRole.boundary,
  frb_presentation.BridgeHistoryTimelineRole.work => HistoryTimelineRole.work,
  frb_presentation.BridgeHistoryTimelineRole.hidden =>
    HistoryTimelineRole.hidden,
};

HistoryBusinessRowScope _historyBusinessRowScopeFromFrb(
  frb_presentation.BridgeHistoryBusinessRowScope value,
) => switch (value) {
  frb_presentation.BridgeHistoryBusinessRowScope.turn =>
    HistoryBusinessRowScope.turn,
  frb_presentation.BridgeHistoryBusinessRowScope.source =>
    HistoryBusinessRowScope.source,
  frb_presentation.BridgeHistoryBusinessRowScope.cost =>
    HistoryBusinessRowScope.cost,
  frb_presentation.BridgeHistoryBusinessRowScope.accounting =>
    HistoryBusinessRowScope.accounting,
};

HistoryBusinessRowHead _historyBusinessRowHeadFromFrb(
  frb_presentation.BridgeHistoryBusinessRowHead value,
) => switch (value) {
  frb_presentation.BridgeHistoryBusinessRowHead_Turn(:final field0) =>
    TurnHistoryBusinessRow(_historyTurnHeadFromFrb(field0)),
  frb_presentation.BridgeHistoryBusinessRowHead_Source(:final field0) =>
    SourceHistoryBusinessRow(_historySourceHeadFromFrb(field0)),
  frb_presentation.BridgeHistoryBusinessRowHead_Cost(:final field0) =>
    CostHistoryBusinessRow(_historyCostHeadFromFrb(field0)),
  frb_presentation.BridgeHistoryBusinessRowHead_Accounting(:final field0) =>
    AccountingHistoryBusinessRow(_historyAccountingHeadFromFrb(field0)),
};

HistoryBusinessRowEntry _historyBusinessRowEntryFromFrb(
  frb_presentation.BridgeHistoryBusinessRowEntry value,
) => HistoryBusinessRowEntry(
  rowKey: value.rowKey,
  anchorSeq: _exactTimelineInt(value.anchorSeq, 'history anchor'),
  headSeq: _exactTimelineInt(value.headSeq, 'history head'),
  head: _historyBusinessRowHeadFromFrb(value.head),
);

HistoryBusinessPage _historyBusinessPageFromFrb(
  frb_presentation.BridgeHistoryBusinessPage value,
) => HistoryBusinessPage(
  cut: _historyCutFromFrb(value.cut),
  entries: value.entries.map(_historyBusinessRowEntryFromFrb).toList(),
  next: value.next,
);

HistoryTurnHead _historyTurnHeadFromFrb(
  frb_presentation.BridgeHistoryTurnHead value,
) => HistoryTurnHead(
  turnId: value.turnId,
  inputId: value.inputId,
  runId: value.runId,
  state: HistoryTurnState.values.byName(value.state.name),
  phase: value.phase == null
      ? null
      : CurrentTurnPhase.values.byName(_currentTurnPhase(value.phase!).name),
  contextDisposition: switch (value.contextDisposition) {
    frb_presentation.BridgeHistoryContextDisposition.active =>
      HistoryContextDisposition.active,
    frb_presentation.BridgeHistoryContextDisposition.rolledBack =>
      HistoryContextDisposition.rolledBack,
  },
  queuedAt: _timelineTimestampFromFrb(value.queuedAt),
  startedAt: _timelineTimestampFromFrb(value.startedAt),
  finishedAt: _timelineTimestampFromFrb(value.finishedAt),
  updatedAt: _timelineTimestampFromFrb(value.updatedAt)!,
  detailEventId: value.detailEventId,
);

HistorySourceHead _historySourceHeadFromFrb(
  frb_presentation.BridgeHistorySourceHead value,
) => HistorySourceHead(
  source: _chatSourceFromFrb(value.source),
  lifecycle: switch (value.lifecycle) {
    frb_presentation.BridgeHistorySourceLifecycle_Unknown() =>
      const HistorySourceLifecycle(kind: HistorySourceLifecycleKind.unknown),
    frb_presentation.BridgeHistorySourceLifecycle_Active() =>
      const HistorySourceLifecycle(kind: HistorySourceLifecycleKind.active),
    frb_presentation.BridgeHistorySourceLifecycle_Ended(:final outcome) =>
      HistorySourceLifecycle(
        kind: HistorySourceLifecycleKind.ended,
        outcome: ChatTerminalOutcome.values.byName(outcome.name),
      ),
  },
  startedAt: _timelineTimestampFromFrb(value.startedAt),
  endedAt: _timelineTimestampFromFrb(value.endedAt),
  observedAt: _timelineTimestampFromFrb(value.observedAt),
  detailEventId: value.detailEventId,
);

HistoryCostHead _historyCostHeadFromFrb(
  frb_presentation.BridgeHistoryCostHead value,
) => HistoryCostHead(
  purpose: value.purpose,
  currency: value.currency,
  costDelta: value.costDelta,
  costTotal: value.costTotal,
  cacheSavingsDelta: value.cacheSavingsDelta,
  cacheSavingsTotal: value.cacheSavingsTotal,
  updatedAt: _timelineTimestampFromFrb(value.updatedAt)!,
  detailEventId: value.detailEventId,
);

HistoryAccountingHead _historyAccountingHeadFromFrb(
  frb_presentation.BridgeHistoryAccountingHead value,
) => HistoryAccountingHead(
  promptTokens: _exactTimelineInt(value.promptTokens, 'prompt tokens'),
  completionTokens: _exactTimelineInt(
    value.completionTokens,
    'completion tokens',
  ),
  cachedPromptTokens: _exactTimelineInt(
    value.cachedPromptTokens,
    'cached prompt tokens',
  ),
  cacheWriteTokens: _exactTimelineInt(
    value.cacheWriteTokens,
    'cache write tokens',
  ),
  reasoningTokens: _exactTimelineInt(value.reasoningTokens, 'reasoning tokens'),
  inferenceCount: _exactTimelineInt(value.inferenceCount, 'inference count'),
  totalTokens: _exactTimelineInt(value.totalTokens, 'total tokens'),
  cacheUsage: _cacheUsageFromFrb(value.cacheUsage),
  hasIncompleteUsage: value.hasIncompleteUsage,
  hasUnpricedUsage: value.hasUnpricedUsage,
  updatedAt: _timelineTimestampFromFrb(value.updatedAt)!,
  detailEventId: value.detailEventId,
);

HistoryEventRecord _historyEventRecordFromFrb(
  frb_presentation.BridgeHistoryEventRecord value,
) => HistoryEventRecord(
  seq: _exactTimelineInt(value.seq, 'history event sequence'),
  eventId: value.eventId,
  kind: value.kind,
  timelineRole: _historyTimelineRoleFromFrb(value.timelineRole),
  occurredAt: _timelineTimestampFromFrb(value.occurredAt),
  recordedAt: _timelineTimestampFromFrb(value.recordedAt)!,
  runId: value.runId,
  turnId: value.turnId,
  attemptId: value.attemptId,
  callId: value.callId,
  entityId: value.entityId,
  messageId: value.messageId,
  toolName: value.toolName,
  source: value.source == null ? null : _chatSourceFromFrb(value.source!),
  original: value.original == null
      ? null
      : HistoryOriginalInfo(
          queryClass: value.original!.queryClass,
          parentId: value.original!.parentId,
          originalKind: ChatAtomKind.values.byName(
            value.original!.originalKind.name,
          ),
          toolName: value.original!.toolName,
        ),
  rowScope: value.rowScope == null
      ? null
      : _historyBusinessRowScopeFromFrb(value.rowScope!),
  rowKey: value.rowKey,
  payloadSchema: value.payloadSchema,
  payloadJson: value.payloadJson,
);

HistoryTimelineEntry _historyTimelineEntryFromFrb(
  frb_presentation.BridgeHistoryTimelineEntry value,
) => HistoryTimelineEntry(
  event: _historyEventRecordFromFrb(value.event),
  hasFoldedAfter: value.hasFoldedAfter,
  tailFoldedEndedAt: _timelineTimestampFromFrb(value.tailFoldedEndedAt),
);

HistoryTimelinePage _historyTimelinePageFromFrb(
  frb_presentation.BridgeHistoryTimelinePage value,
) => HistoryTimelinePage(
  cut: _historyCutFromFrb(value.cut),
  entries: value.entries.map(_historyTimelineEntryFromFrb).toList(),
  hasFoldedBeforeOldest: value.hasFoldedBeforeOldest,
  next: value.next,
);

HistoryWorkRangePage _historyWorkRangePageFromFrb(
  frb_presentation.BridgeHistoryWorkRangePage value,
) => HistoryWorkRangePage(
  cut: _historyCutFromFrb(value.cut),
  afterSeq: value.afterSeq == null
      ? null
      : _exactTimelineInt(value.afterSeq!, 'history work range afterSeq'),
  beforeSeq: value.beforeSeq == null
      ? null
      : _exactTimelineInt(value.beforeSeq!, 'history work range beforeSeq'),
  events: value.events.map(_historyEventRecordFromFrb).toList(),
  next: value.next,
);

HistoryEventsPage _historyEventsPageFromFrb(
  frb_presentation.BridgeHistoryEventsPage value,
) => HistoryEventsPage(
  cut: _historyCutFromFrb(value.cut),
  entries: value.entries.map(_historyEventRecordFromFrb).toList(),
  next: value.next,
);

HistoryEventBodyRef _historyBodyRefFromFrb(
  frb_presentation.BridgeHistoryEventBodyRef value,
) => HistoryEventBodyRef(
  databaseId: value.databaseId,
  ownerEventId: value.ownerEventId,
  bodyKey: value.bodyKey,
  bodyId: value.bodyId,
  byteStart: _exactTimelineInt(value.byteStart, 'history body start'),
  byteLength: _exactTimelineInt(value.byteLength, 'history body length'),
);

frb_presentation.BridgeHistoryEventBodyRef _historyBodyRefToFrb(
  HistoryEventBodyRef value,
) => frb_presentation.BridgeHistoryEventBodyRef(
  databaseId: value.databaseId,
  ownerEventId: value.ownerEventId,
  bodyKey: value.bodyKey,
  bodyId: value.bodyId,
  byteStart: BigInt.from(value.byteStart),
  byteLength: BigInt.from(value.byteLength),
);

HistoryBodyWindow _historyBodyWindowFromFrb(
  frb_presentation.BridgeHistoryBodyWindow value,
) => HistoryBodyWindow(
  offset: _exactTimelineInt(value.offset, 'history body offset'),
  bytes: value.bytes,
  totalLength: _exactTimelineInt(value.totalLength, 'history body length'),
  mediaType: value.mediaType,
);

HistoryBodyPage _historyBodyPageFromFrb(
  frb_presentation.BridgeHistoryBodyPage value,
) => HistoryBodyPage(
  ownerEventId: value.ownerEventId,
  entries: [
    for (final entry in value.entries)
      HistoryBodyEntry(
        ordinal: _exactTimelineInt(entry.ordinal, 'history body ordinal'),
        bodyKey: entry.bodyKey,
        role: switch (entry.role) {
          frb_presentation.BridgeHistoryBodyRole_CanonicalPayload() =>
            const HistoryBodyRole(HistoryBodyRoleKind.canonicalPayload),
          frb_presentation.BridgeHistoryBodyRole_CanonicalMetadata() =>
            const HistoryBodyRole(HistoryBodyRoleKind.canonicalMetadata),
          frb_presentation.BridgeHistoryBodyRole_Body() =>
            const HistoryBodyRole(HistoryBodyRoleKind.body),
          frb_presentation.BridgeHistoryBodyRole_ReasoningSummary() =>
            const HistoryBodyRole(HistoryBodyRoleKind.reasoningSummary),
          frb_presentation.BridgeHistoryBodyRole_ToolArguments() =>
            const HistoryBodyRole(HistoryBodyRoleKind.toolArguments),
          frb_presentation.BridgeHistoryBodyRole_ToolOutput() =>
            const HistoryBodyRole(HistoryBodyRoleKind.toolOutput),
          frb_presentation.BridgeHistoryBodyRole_Attachment() =>
            const HistoryBodyRole(HistoryBodyRoleKind.attachment),
          frb_presentation.BridgeHistoryBodyRole_WaitPresentation() =>
            const HistoryBodyRole(HistoryBodyRoleKind.waitPresentation),
          frb_presentation.BridgeHistoryBodyRole_Other(:final name) =>
            HistoryBodyRole(HistoryBodyRoleKind.other, name: name),
        },
        reference: _historyBodyRefFromFrb(entry.reference),
        mediaType: entry.mediaType,
      ),
  ],
  next: value.next,
);

HistoryAccounting? _historyAccountingFromFrb(
  frb_presentation.BridgeHistoryAccounting? value,
) => value == null
    ? null
    : HistoryAccounting(_historyAccountingHeadFromFrb(value.head));

CurrentRevision _currentRevisionFromFrb(
  frb_presentation.BridgeCurrentRevision value,
) => CurrentRevision(
  ownerId: value.ownerId,
  revision: _exactTimelineInt(value.revision, 'current revision'),
);

OpenCurrent _openCurrentFromFrb(
  frb_presentation.BridgeOpenCurrentReader value,
) => OpenCurrent(
  readerId: value.readerId,
  currentProtocolVersion: value.currentProtocolVersion,
  currentOwnerId: value.currentOwnerId,
);

frb_presentation.BridgeCurrentRevision _currentRevisionToFrb(
  CurrentRevision value,
) => frb_presentation.BridgeCurrentRevision(
  ownerId: value.ownerId,
  revision: BigInt.from(value.revision),
);

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
      byteLength: _exactTimelineInt(byteLength, 'State field byte length'),
    ),
  frb_presentation.BridgeCurrentStateField_Collection(
    :final field,
    :final reference,
    :final count,
  ) =>
    CollectionCurrentStateField(
      field: field,
      reference: _currentCollectionRefFromFrb(reference),
      count: _exactTimelineInt(count, 'State collection count'),
    ),
};

frb_presentation.BridgeCurrentContentRef _currentContentRefToFrb(
  CurrentContentRef value,
) => frb_presentation.BridgeCurrentContentRef(
  ownerId: value.ownerId,
  domain: value.domain,
  entityId: value.entityId,
  contentKey: value.contentKey,
  generation: value.generation,
);

CurrentCollectionRef _currentCollectionRefFromFrb(
  frb_presentation.BridgeCurrentCollectionRef value,
) => CurrentCollectionRef(
  ownerId: value.ownerId,
  collection: value.collection,
  revision: _exactTimelineInt(value.revision, 'current collection revision'),
);

frb_presentation.BridgeCurrentCollectionRef _currentCollectionRefToFrb(
  CurrentCollectionRef value,
) => frb_presentation.BridgeCurrentCollectionRef(
  ownerId: value.ownerId,
  collection: value.collection,
  revision: BigInt.from(value.revision),
);

CurrentPayloadData _currentPayloadFromFrb(
  frb_presentation.BridgeCurrentPayloadData value,
) => switch (value) {
  frb_presentation.BridgeCurrentPayloadData_Inline(:final bytes) =>
    InlineCurrentPayload(bytes: bytes),
  frb_presentation.BridgeCurrentPayloadData_Deferred(
    :final reference,
    :final byteLength,
  ) =>
    DeferredCurrentPayload(
      reference: _currentContentRefFromFrb(reference),
      byteLength: _exactTimelineInt(byteLength, 'current payload length'),
    ),
};

CurrentCollectionPage _currentCollectionPageFromFrb(
  frb_presentation.BridgeCurrentCollectionPage value,
) => CurrentCollectionPage(
  revision: _exactTimelineInt(value.revision, 'current revision'),
  entries: [
    for (final entry in value.entries)
      CurrentCollectionEntry(
        id: entry.id,
        position: _exactSignedTimelineInt(entry.position),
        payload: _currentPayloadFromFrb(entry.payload),
      ),
  ],
  continuation: value.continuation,
);

CurrentProjection _currentProjectionFromFrb(
  frb_presentation.BridgeCurrentProjection value,
) => CurrentProjection(
  logicalStatus: ThreadStatusView.values.byName(value.logicalStatus.name),
  executionPresent: value.executionPresent,
  active: value.active == null
      ? null
      : CurrentActivityHead(
          id: value.active!.id,
          kind: _threadActivityKindFromFrb(value.active!.kind),
          summary: value.active!.summary,
          thinkingSummary: value.active!.thinkingSummary,
          thinkingSeconds: value.active!.thinkingSeconds == null
              ? null
              : _exactTimelineInt(
                  value.active!.thinkingSeconds!,
                  'current thinking seconds',
                ),
          toolCount: value.active!.toolCount,
          backgroundToolCount: value.active!.backgroundToolCount,
          latestTool: value.active!.latestTool == null
              ? null
              : CurrentToolHead(
                  callId: value.active!.latestTool!.callId,
                  name: value.active!.latestTool!.name,
                  state: ThreadActivityToolState.values.byName(
                    value.active!.latestTool!.state.name,
                  ),
                ),
        ),
  activeTurn: value.activeTurn == null
      ? null
      : CurrentTurnHead(
          id: value.activeTurn!.id,
          phase: _currentTurnPhase(value.activeTurn!.phase),
        ),
  sources: value.sources.map(_chatSourceStateFromFrb).toList(),
  atoms: value.atoms.map(_currentAtomFromFrb).toList(),
  plan: value.plan == null
      ? null
      : CurrentPlanHead(
          revision: _exactTimelineInt(
            value.plan!.revision,
            'current plan revision',
          ),
          phase: PlanRuntimePhase.values.byName(value.plan!.phase.name),
          document: value.plan!.document == null
              ? null
              : _currentContentRefFromFrb(value.plan!.document!),
        ),
  interactions: value.interactions == null
      ? null
      : _currentCollectionRefFromFrb(value.interactions!),
  previews: [
    for (final preview in value.previews)
      CurrentContentPreview(
        id: preview.id,
        role: CurrentContentRole.values.byName(preview.role.name),
        textChannel: preview.textChannel == null
            ? null
            : ThreadTextChannel.values.byName(preview.textChannel!.name),
        text: preview.text,
        reference: _currentContentRefFromFrb(preview.reference),
      ),
  ],
  collections: value.collections.map(_currentCollectionRefFromFrb).toList(),
  modelRecovery: value.modelRecovery == null
      ? null
      : CurrentModelRecovery(
          attempt: value.modelRecovery!.attempt,
          maxAttempts: value.modelRecovery!.maxAttempts,
          reason: value.modelRecovery!.reason,
        ),
);

CurrentAtom _currentAtomFromFrb(frb_presentation.BridgeCurrentAtom value) =>
    CurrentAtom(
      id: value.id,
      source: _chatSourceFromFrb(value.source),
      sourceState: value.sourceState == null
          ? null
          : _chatSourceStateFromFrb(value.sourceState!),
      sourceOrder: _exactNullableTimelineInt(value.sourceOrder, 'source order'),
      kind: ChatAtomKind.values.byName(value.kind.name),
      delivery: ChatDeliveryKind.values.byName(value.delivery.name),
      lifecycle: switch (value.lifecycle) {
        frb_chat_types.BridgeChatAtomLifecycle_Active(
          :final started,
          :final status,
        ) =>
          ActiveChatAtom(
            started: started == null ? null : _chatPositionFromFrb(started),
            status: ChatActiveStatus.values.byName(status.name),
          ),
        frb_chat_types.BridgeChatAtomLifecycle_Terminal(
          :final started,
          :final ended,
          :final outcome,
        ) =>
          TerminalChatAtom(
            started: started == null ? null : _chatPositionFromFrb(started),
            ended: ended == null ? null : _chatPositionFromFrb(ended),
            outcome: ChatTerminalOutcome.values.byName(outcome.name),
          ),
      },
      turnId: value.turnId,
      attemptId: value.attemptId,
      tool: value.tool == null
          ? null
          : ChatToolIdentity(
              callId: value.tool!.callId,
              name: value.tool!.name,
            ),
      wait: value.wait == null ? null : _waitFromFrb(value.wait!),
      textChannel: value.textChannel == null
          ? null
          : ThreadTextChannel.values.byName(value.textChannel!.name),
      startedAt: _timelineTimestampFromFrb(value.startedAt),
      finishedAt: _timelineTimestampFromFrb(value.finishedAt),
      contentPresent: value.contentPresent,
      contents: [
        for (final content in value.contents)
          CurrentAtomContent(
            role: ChatContentRole.values.byName(content.role.name),
            reference: _currentContentRefFromFrb(content.reference),
          ),
      ],
    );

CurrentView _currentViewFromFrb(frb_presentation.BridgeCurrentView value) =>
    CurrentView(
      revision: _currentRevisionFromFrb(value.revision),
      state: ThreadSnapshotFrame(
        workspace: _threadWorkspaceFromSnapshot(value.state),
        schemaVersion: value.state.schemaVersion,
      ),
      projection: _currentProjectionFromFrb(value.projection),
    );

CurrentFrame _currentFrameFromFrb(frb_presentation.BridgeCurrentFrame value) =>
    switch (value) {
      frb_presentation.BridgeCurrentFrame_Reset(:final view) =>
        ResetCurrentFrame(_currentViewFromFrb(view)),
      frb_presentation.BridgeCurrentFrame_Notification(
        :final revision,
        :final notification,
      ) =>
        NotificationCurrentFrame(
          revision: _currentRevisionFromFrb(revision),
          notification: _currentNotificationFrameFromEnvelope(notification),
        ),
      frb_presentation.BridgeCurrentFrame_Projection(
        :final revision,
        :final projection,
      ) =>
        ProjectionCurrentFrame(
          revision: _currentRevisionFromFrb(revision),
          projection: _currentProjectionFromFrb(projection),
        ),
    };

CurrentTurnPhase _currentTurnPhase(frb.BridgeTurnPhase value) =>
    switch (value) {
      frb.BridgeTurnPhase.preparing => CurrentTurnPhase.preparing,
      frb.BridgeTurnPhase.thinking => CurrentTurnPhase.thinking,
      frb.BridgeTurnPhase.responding => CurrentTurnPhase.responding,
      frb.BridgeTurnPhase.planning => CurrentTurnPhase.planning,
      frb.BridgeTurnPhase.runningTool => CurrentTurnPhase.runningTool,
      frb.BridgeTurnPhase.persisting => CurrentTurnPhase.persisting,
    };

frb_chat_types.BridgeChatSourceId _chatSourceToFrb(ChatSourceId value) =>
    switch (value) {
      ForegroundTurnChatSource(:final turnId) =>
        frb_chat_types.BridgeChatSourceId.foregroundTurn(turnId: turnId),
      InputChatSource(:final inputId) =>
        frb_chat_types.BridgeChatSourceId.input(inputId: inputId),
      InboxMessageChatSource(:final sourceId, :final messageId) =>
        frb_chat_types.BridgeChatSourceId.inboxMessage(
          sourceId: sourceId,
          messageId: messageId,
        ),
      BackgroundResultChatSource(:final messageId) =>
        frb_chat_types.BridgeChatSourceId.backgroundResult(
          messageId: messageId,
        ),
      OperationChatSource(:final operationId) =>
        frb_chat_types.BridgeChatSourceId.operation(operationId: operationId),
      ReceiptChatSource(:final receiptId) =>
        frb_chat_types.BridgeChatSourceId.receipt(receiptId: receiptId),
    };

frb_chat_types.BridgeContentRange _contentRangeToFrb(ContentRange value) =>
    frb_chat_types.BridgeContentRange(
      offset: BigInt.from(value.offset),
      maxBytes: value.maxBytes,
    );

// History timestamps are in milliseconds; Current atoms use Unix seconds.
int? _timelineTimestampFromFrb(Object? value) {
  if (value == null) return null;
  return _exactSignedTimelineInt(value);
}

CacheUsageView _cacheUsageFromFrb(frb.BridgeCacheUsageSummary value) =>
    CacheUsageView(
      sampleCount: _exactTimelineInt(value.sampleCount, 'usage sample count'),
      legacySampleCountUnknown: value.legacySampleCountUnknown,
      inputTokens: _exactTimelineInt(value.inputTokens, 'input tokens'),
      cacheReadTokens: _exactTimelineInt(
        value.cacheReadTokens,
        'cache read tokens',
      ),
      hitRate: value.hitRate,
      hasIncompleteUsage: value.hasIncompleteUsage,
    );
