part of 'studio_api.dart';

BotAudienceCloseReason _botAudienceCloseReasonFromFrb(
  frb_audience.BridgeBotAudienceCloseReason value,
) => switch (value) {
  frb_audience.BridgeBotAudienceCloseReason.localClose =>
    BotAudienceCloseReason.localClose,
  frb_audience.BridgeBotAudienceCloseReason.botDisabled =>
    BotAudienceCloseReason.botDisabled,
  frb_audience.BridgeBotAudienceCloseReason.trustRevoked =>
    BotAudienceCloseReason.trustRevoked,
  frb_audience.BridgeBotAudienceCloseReason.bindingReplaced =>
    BotAudienceCloseReason.bindingReplaced,
  frb_audience.BridgeBotAudienceCloseReason.bindingUnavailable =>
    BotAudienceCloseReason.bindingUnavailable,
  frb_audience.BridgeBotAudienceCloseReason.startCancelled =>
    BotAudienceCloseReason.startCancelled,
  frb_audience.BridgeBotAudienceCloseReason.startFailed =>
    BotAudienceCloseReason.startFailed,
};

ThreadAudienceUnavailableReason _threadAudienceUnavailableReasonFromFrb(
  frb_audience.BridgeThreadAudienceUnavailableReason value,
) => switch (value) {
  frb_audience.BridgeThreadAudienceUnavailableReason.ownershipUnproven =>
    ThreadAudienceUnavailableReason.ownershipUnproven,
  frb_audience.BridgeThreadAudienceUnavailableReason.invalidOwnership =>
    ThreadAudienceUnavailableReason.invalidOwnership,
  frb_audience.BridgeThreadAudienceUnavailableReason.botUnavailable =>
    ThreadAudienceUnavailableReason.botUnavailable,
  frb_audience.BridgeThreadAudienceUnavailableReason.stateUnreadable =>
    ThreadAudienceUnavailableReason.stateUnreadable,
  frb_audience.BridgeThreadAudienceUnavailableReason.inconsistentScope =>
    ThreadAudienceUnavailableReason.inconsistentScope,
  frb_audience.BridgeThreadAudienceUnavailableReason.bindingUnavailable =>
    ThreadAudienceUnavailableReason.bindingUnavailable,
  frb_audience.BridgeThreadAudienceUnavailableReason.runtimeClosed =>
    ThreadAudienceUnavailableReason.runtimeClosed,
};

BotAudienceItemsUnavailableReason _botAudienceItemsUnavailableReasonFromFrb(
  frb_delivery.BridgeBotAudienceItemsUnavailableReason value,
) => switch (value) {
  frb_delivery.BridgeBotAudienceItemsUnavailableReason.ownerUnavailable =>
    BotAudienceItemsUnavailableReason.ownerUnavailable,
  frb_delivery.BridgeBotAudienceItemsUnavailableReason.ledgerUnreadable =>
    BotAudienceItemsUnavailableReason.ledgerUnreadable,
  frb_delivery
      .BridgeBotAudienceItemsUnavailableReason
      .canonicalReadInvalidated =>
    BotAudienceItemsUnavailableReason.canonicalReadInvalidated,
  frb_delivery.BridgeBotAudienceItemsUnavailableReason.scopeChanged =>
    BotAudienceItemsUnavailableReason.scopeChanged,
};

BotAuthorizationPhase _botAuthorizationPhaseFromFrb(
  frb_delivery.BridgeBotAuthorizationPhase value,
) => switch (value) {
  frb_delivery.BridgeBotAuthorizationPhase.pendingStart =>
    BotAuthorizationPhase.pendingStart,
  frb_delivery.BridgeBotAuthorizationPhase.active =>
    BotAuthorizationPhase.active,
  frb_delivery.BridgeBotAuthorizationPhase.paused =>
    BotAuthorizationPhase.paused,
  frb_delivery.BridgeBotAuthorizationPhase.closed =>
    BotAuthorizationPhase.closed,
};

BotCanonicalUnavailableReason _botCanonicalUnavailableReasonFromFrb(
  frb_delivery.BridgeBotCanonicalUnavailableReason value,
) => switch (value) {
  frb_delivery.BridgeBotCanonicalUnavailableReason.missing =>
    BotCanonicalUnavailableReason.missing,
  frb_delivery.BridgeBotCanonicalUnavailableReason.readInvalidated =>
    BotCanonicalUnavailableReason.readInvalidated,
  frb_delivery.BridgeBotCanonicalUnavailableReason.storageUnavailable =>
    BotCanonicalUnavailableReason.storageUnavailable,
  frb_delivery.BridgeBotCanonicalUnavailableReason.invalidMetadata =>
    BotCanonicalUnavailableReason.invalidMetadata,
  frb_delivery.BridgeBotCanonicalUnavailableReason.startProofUnavailable =>
    BotCanonicalUnavailableReason.startProofUnavailable,
};

BotCardOperationKind _botCardOperationKindFromFrb(
  frb_delivery.BridgeBotCardOperationKind value,
) => switch (value) {
  frb_delivery.BridgeBotCardOperationKind.create => BotCardOperationKind.create,
  frb_delivery.BridgeBotCardOperationKind.send => BotCardOperationKind.send,
  frb_delivery.BridgeBotCardOperationKind.content =>
    BotCardOperationKind.content,
  frb_delivery.BridgeBotCardOperationKind.settings =>
    BotCardOperationKind.settings,
};

BotFileBlockReason _botFileBlockReasonFromFrb(
  frb_delivery.BridgeBotFileBlockReason value,
) => switch (value) {
  frb_delivery.BridgeBotFileBlockReason.emptyFile =>
    BotFileBlockReason.emptyFile,
  frb_delivery.BridgeBotFileBlockReason.platformSizeLimit =>
    BotFileBlockReason.platformSizeLimit,
  frb_delivery.BridgeBotFileBlockReason.sourceUnavailable =>
    BotFileBlockReason.sourceUnavailable,
  frb_delivery.BridgeBotFileBlockReason.budgetUnavailable =>
    BotFileBlockReason.budgetUnavailable,
};

BotFileOutcome _botFileOutcomeFromFrb(
  frb_delivery.BridgeBotFileOutcome value,
) => switch (value) {
  frb_delivery.BridgeBotFileOutcome.pending => BotFileOutcome.pending,
  frb_delivery.BridgeBotFileOutcome.delivered => BotFileOutcome.delivered,
  frb_delivery.BridgeBotFileOutcome.partial => BotFileOutcome.partial,
  frb_delivery.BridgeBotFileOutcome.rejected => BotFileOutcome.rejected,
  frb_delivery.BridgeBotFileOutcome.unknown => BotFileOutcome.unknown,
  frb_delivery.BridgeBotFileOutcome.stopped => BotFileOutcome.stopped,
};

BotItemExclusion _botItemExclusionFromFrb(
  frb_delivery.BridgeBotItemExclusion value,
) => switch (value) {
  frb_delivery.BridgeBotItemExclusion.nonPublicContent =>
    BotItemExclusion.nonPublicContent,
  frb_delivery.BridgeBotItemExclusion.outsideAuthorization =>
    BotItemExclusion.outsideAuthorization,
  frb_delivery.BridgeBotItemExclusion.excludedStartedTurn =>
    BotItemExclusion.excludedStartedTurn,
  frb_delivery.BridgeBotItemExclusion.legacyOnly => BotItemExclusion.legacyOnly,
};

BotPublicTextChannel _botPublicTextChannelFromFrb(
  frb_delivery.BridgeBotPublicTextChannel value,
) => switch (value) {
  frb_delivery.BridgeBotPublicTextChannel.commentary =>
    BotPublicTextChannel.commentary,
  frb_delivery.BridgeBotPublicTextChannel.final_ =>
    BotPublicTextChannel.finalAnswer,
};

BotTextIntegrity _botTextIntegrityFromFrb(
  frb_delivery.BridgeBotTextIntegrity value,
) => switch (value) {
  frb_delivery.BridgeBotTextIntegrity.full => BotTextIntegrity.full,
  frb_delivery.BridgeBotTextIntegrity.truncated => BotTextIntegrity.truncated,
};

BotConversationKind _botConversationKindFromFrb(
  frb_bots_types.BridgeBotConversationKind value,
) => switch (value) {
  frb_bots_types.BridgeBotConversationKind.direct => BotConversationKind.direct,
  frb_bots_types.BridgeBotConversationKind.group => BotConversationKind.group,
};

BotSendStopReason _botSendStopReasonFromFrb(
  frb_bots_types.BridgeBotSendStopReason value,
) => switch (value) {
  frb_bots_types.BridgeBotSendStopReason.cancelled =>
    BotSendStopReason.cancelled,
  frb_bots_types.BridgeBotSendStopReason.localFailure =>
    BotSendStopReason.localFailure,
};

BotAudienceStart _botAudienceStartFromFrb(
  frb_audience.BridgeBotAudienceStart value,
) => BotAudienceStart(
  commitSequence: _exactTimelineInt(value.commitSequence, 'audience value'),
  excludedTurnId: value.excludedTurnId,
);

BotAudienceTarget _botAudienceTargetFromFrb(
  frb_audience.BridgeBotAudienceTarget value,
) => BotAudienceTarget(
  botId: value.botId,
  botName: value.botName,
  chatId: value.chatId,
  chatName: value.chatName,
  kind: _botConversationKindFromFrb(value.kind),
);

BotAuthorizationId _botAuthorizationIdFromFrb(
  frb_audience.BridgeBotAuthorizationId value,
) => BotAuthorizationId(
  botId: value.botId,
  chatId: value.chatId,
  generation: _exactTimelineInt(value.generation, 'audience value'),
);

BotAuthorizationRef _botAuthorizationRefFromFrb(
  frb_audience.BridgeBotAuthorizationRef value,
) => BotAuthorizationRef(
  id: _botAuthorizationIdFromFrb(value.id),
  revision: _exactTimelineInt(value.revision, 'audience value'),
);

BotClosedAuthorization _botClosedAuthorizationFromFrb(
  frb_audience.BridgeBotClosedAuthorization value,
) => BotClosedAuthorization(
  authorization: _botAuthorizationRefFromFrb(value.authorization),
  bindingRevision: _exactTimelineInt(value.bindingRevision, 'audience value'),
  start: _botClosedStartFromFrb(value.start),
  reason: _botAudienceCloseReasonFromFrb(value.reason),
  closedAt: value.closedAt,
);

BotDeliverySummary _botDeliverySummaryFromFrb(
  frb_audience.BridgeBotDeliverySummary value,
) => BotDeliverySummary(
  version: _exactTimelineInt(value.version, 'audience value'),
  pendingItems: value.pendingItems,
  unknownOperations: value.unknownOperations,
  incompleteItems: value.incompleteItems,
  countsCapped: value.countsCapped,
);

BotLegacyFinalSummary _botLegacyFinalSummaryFromFrb(
  frb_audience.BridgeBotLegacyFinalSummary value,
) => BotLegacyFinalSummary(
  unfinishedChains: value.unfinishedChains,
  unknownOperations: value.unknownOperations,
  needsAttention: value.needsAttention,
  countsCapped: value.countsCapped,
);

BotPendingAuthorization _botPendingAuthorizationFromFrb(
  frb_audience.BridgeBotPendingAuthorization value,
) => BotPendingAuthorization(
  authorization: _botAuthorizationRefFromFrb(value.authorization),
  operationId: value.operationId,
  diagnostic: value.diagnostic == null
      ? null
      : _botDiagnosticFromFrb(value.diagnostic!),
);

BotStartedAuthorization _botStartedAuthorizationFromFrb(
  frb_audience.BridgeBotStartedAuthorization value,
) => BotStartedAuthorization(
  authorization: _botAuthorizationRefFromFrb(value.authorization),
  bindingRevision: _exactTimelineInt(value.bindingRevision, 'audience value'),
  start: _botAudienceStartFromFrb(value.start),
);

BotSyncCas _botSyncCasFromFrb(frb_audience.BridgeBotSyncCas value) =>
    BotSyncCas(
      bindingRevision: _exactTimelineInt(
        value.bindingRevision,
        'audience value',
      ),
      authorizationHead: _botAuthorizationHeadFromFrb(value.authorizationHead),
    );

BotThreadAudience _botThreadAudienceFromFrb(
  frb_audience.BridgeBotThreadAudience value,
) => BotThreadAudience(
  target: _botAudienceTargetFromFrb(value.target),
  binding: _botThreadBindingPositionFromFrb(value.binding),
  latestClosed: value.latestClosed == null
      ? null
      : _botClosedAuthorizationFromFrb(value.latestClosed!),
  hasOlderClosed: value.hasOlderClosed,
  delivery: _botDeliverySummaryFromFrb(value.delivery),
  legacyFinal: _botLegacyFinalSummaryFromFrb(value.legacyFinal),
);

BotAudienceItemStatus _botAudienceItemStatusFromFrb(
  frb_delivery.BridgeBotAudienceItemStatus value,
) => BotAudienceItemStatus(
  itemId: value.itemId,
  canonical: _botAudienceCanonicalItemFromFrb(value.canonical),
  delivery: _botItemDeliveryFromFrb(value.delivery),
);

BotCardOperationSummary _botCardOperationSummaryFromFrb(
  frb_delivery.BridgeBotCardOperationSummary value,
) => BotCardOperationSummary(
  operationId: value.operationId,
  contentRevision: _exactTimelineInt(value.contentRevision, 'audience value'),
  action: _botCardOperationKindFromFrb(value.action),
  result: _botPlatformResultFromFrb(value.result),
);

BotItemLedgerSummary _botItemLedgerSummaryFromFrb(
  frb_delivery.BridgeBotItemLedgerSummary value,
) => BotItemLedgerSummary(
  observedRevision: _exactTimelineInt(value.observedRevision, 'audience value'),
  projected: _botItemPresentationFromFrb(value.projected),
  accepted: _botItemPresentationFromFrb(value.accepted),
  platform: _botItemPlatformFromFrb(value.platform),
);

ChangeBotThreadSyncReply _changeBotThreadSyncReplyFromFrb(
  frb_delivery.BridgeChangeBotThreadSyncReply value,
) => ChangeBotThreadSyncReply(
  threadId: value.threadId,
  audience: _threadAudienceFromFrb(value.audience),
  state: _botThreadSyncCommandStateFromFrb(value.state),
  receipt: _commandReceiptFromFrb(value.receipt),
);

ReadThreadAudienceItemsReply _readThreadAudienceItemsReplyFromFrb(
  frb_delivery.BridgeReadThreadAudienceItemsReply value,
) => ReadThreadAudienceItemsReply(
  threadId: value.threadId,
  authorization: _botAuthorizationIdFromFrb(value.authorization),
  result: _botAudienceItemsReadFromFrb(value.result),
);

ReadThreadClosedAuthorizationsReply _readThreadClosedAuthorizationsReplyFromFrb(
  frb_delivery.BridgeReadThreadClosedAuthorizationsReply value,
) => ReadThreadClosedAuthorizationsReply(
  threadId: value.threadId,
  result: _threadClosedAuthorizationsReadFromFrb(value.result),
);

ThreadClosedAuthorizationPage _threadClosedAuthorizationPageFromFrb(
  frb_delivery.BridgeThreadClosedAuthorizationPage value,
) => ThreadClosedAuthorizationPage(
  target: _botAudienceTargetFromFrb(value.target),
  authorizations: [
    for (final element in value.authorizations)
      _botClosedAuthorizationFromFrb(element),
  ],
  nextCursor: value.nextCursor,
);

BotAuthorizationHead _botAuthorizationHeadFromFrb(
  frb_audience.BridgeBotAuthorizationHead value,
) => value.when(
  none: () => BotAuthorizationHeadNone(),
  present: (authorization) => BotAuthorizationHeadPresent(
    authorization: _botAuthorizationRefFromFrb(authorization),
  ),
);

BotClosedStart _botClosedStartFromFrb(
  frb_audience.BridgeBotClosedStart value,
) => value.when(
  neverActivated: () => BotClosedStartNeverActivated(),
  saved: (start) => BotClosedStartSaved(start: _botAudienceStartFromFrb(start)),
);

BotCurrentSync _botCurrentSyncFromFrb(
  frb_audience.BridgeBotCurrentSync value,
) => value.when(
  preparingThread: () => BotCurrentSyncPreparingThread(),
  requiresUpgrade: () => BotCurrentSyncRequiresUpgrade(),
  pendingStart: (pending) => BotCurrentSyncPendingStart(
    pending: _botPendingAuthorizationFromFrb(pending),
  ),
  active: (authorization) => BotCurrentSyncActive(
    authorization: _botStartedAuthorizationFromFrb(authorization),
  ),
  paused: (authorization) => BotCurrentSyncPaused(
    authorization: _botStartedAuthorizationFromFrb(authorization),
  ),
  closed: () => BotCurrentSyncClosed(),
);

BotThreadBindingPosition _botThreadBindingPositionFromFrb(
  frb_audience.BridgeBotThreadBindingPosition value,
) => value.when(
  current: (cas, sync_) => BotThreadBindingPositionCurrent(
    cas: _botSyncCasFromFrb(cas),
    sync: _botCurrentSyncFromFrb(sync_),
  ),
  replaced: (lastBindingRevision, currentBindingRevision) =>
      BotThreadBindingPositionReplaced(
        lastBindingRevision: _exactTimelineInt(
          lastBindingRevision,
          'audience value',
        ),
        currentBindingRevision: _exactTimelineInt(
          currentBindingRevision,
          'audience value',
        ),
      ),
);

ThreadAudience _threadAudienceFromFrb(
  frb_audience.BridgeThreadAudience value,
) => value.when(
  unbound: () => ThreadAudienceUnbound(),
  unavailable: (reason) => ThreadAudienceUnavailable(
    reason: _threadAudienceUnavailableReasonFromFrb(reason),
  ),
  known: (audience) =>
      ThreadAudienceKnown(audience: _botThreadAudienceFromFrb(audience)),
);

BotAudienceCanonicalItem _botAudienceCanonicalItemFromFrb(
  frb_delivery.BridgeBotAudienceCanonicalItem value,
) => value.when(
  present: (revision, saved, eligibility) => BotAudienceCanonicalItemPresent(
    revision: _exactTimelineInt(revision, 'audience value'),
    saved: saved,
    eligibility: _botItemEligibilityFromFrb(eligibility),
  ),
  removed: () => BotAudienceCanonicalItemRemoved(),
  unavailable: (reason) => BotAudienceCanonicalItemUnavailable(
    reason: _botCanonicalUnavailableReasonFromFrb(reason),
  ),
);

BotAudienceItemsRead _botAudienceItemsReadFromFrb(
  frb_delivery.BridgeBotAudienceItemsRead value,
) => value.when(
  unavailable: (reason) => BotAudienceItemsReadUnavailable(
    reason: _botAudienceItemsUnavailableReasonFromFrb(reason),
  ),
  items: (authorization, phase, summaryVersion, deliveryVersion, items) =>
      BotAudienceItemsReadItems(
        authorization: _botAuthorizationRefFromFrb(authorization),
        phase: _botAuthorizationPhaseFromFrb(phase),
        summaryVersion: _exactTimelineInt(summaryVersion, 'audience value'),
        deliveryVersion: _exactTimelineInt(deliveryVersion, 'audience value'),
        items: [
          for (final element in items) _botAudienceItemStatusFromFrb(element),
        ],
      ),
);

BotItemDelivery _botItemDeliveryFromFrb(
  frb_delivery.BridgeBotItemDelivery value,
) => value.when(
  notProjected: () => BotItemDeliveryNotProjected(),
  known: (ledger) =>
      BotItemDeliveryKnown(ledger: _botItemLedgerSummaryFromFrb(ledger)),
);

BotItemEligibility _botItemEligibilityFromFrb(
  frb_delivery.BridgeBotItemEligibility value,
) => value.when(
  text: (channel) =>
      BotItemEligibilityText(channel: _botPublicTextChannelFromFrb(channel)),
  publicArtifact: () => BotItemEligibilityPublicArtifact(),
  notAuthorized: (reason) =>
      BotItemEligibilityNotAuthorized(reason: _botItemExclusionFromFrb(reason)),
);

BotItemPlatform _botItemPlatformFromFrb(
  frb_delivery.BridgeBotItemPlatform value,
) => value.when(
  none: () => BotItemPlatformNone(),
  blocked: (reason) =>
      BotItemPlatformBlocked(reason: _botFileBlockReasonFromFrb(reason)),
  card: (latestOperation) => BotItemPlatformCard(
    latestOperation: _botCardOperationSummaryFromFrb(latestOperation),
  ),
  file: (operationId, contentRevision, upload, message, outcome, localStop) =>
      BotItemPlatformFile(
        operationId: operationId,
        contentRevision: _exactTimelineInt(contentRevision, 'audience value'),
        upload: _botPlatformResultFromFrb(upload),
        message: _botPlatformResultFromFrb(message),
        outcome: _botFileOutcomeFromFrb(outcome),
        localStop: localStop == null
            ? null
            : _botSendStopReasonFromFrb(localStop),
      ),
);

BotItemPresentation _botItemPresentationFromFrb(
  frb_delivery.BridgeBotItemPresentation value,
) => value.when(
  none: () => BotItemPresentationNone(),
  text: (revision, integrity, saved) => BotItemPresentationText(
    revision: _exactTimelineInt(revision, 'audience value'),
    integrity: _botTextIntegrityFromFrb(integrity),
    saved: saved,
  ),
  file: (revision) => BotItemPresentationFile(
    revision: _exactTimelineInt(revision, 'audience content revision'),
  ),
);

BotPlatformResult _botPlatformResultFromFrb(
  frb_delivery.BridgeBotPlatformResult value,
) => value.when(
  notStarted: () => BotPlatformResultNotStarted(),
  inFlight: () => BotPlatformResultInFlight(),
  accepted: () => BotPlatformResultAccepted(),
  rejected: (diagnostic) =>
      BotPlatformResultRejected(diagnostic: _botDiagnosticFromFrb(diagnostic)),
  unknown: (diagnostic) =>
      BotPlatformResultUnknown(diagnostic: _botDiagnosticFromFrb(diagnostic)),
);

BotThreadSyncCommandState _botThreadSyncCommandStateFromFrb(
  frb_delivery.BridgeBotThreadSyncCommandState value,
) => value.when(
  settled: () => BotThreadSyncCommandStateSettled(),
  pendingStart: (authorization) => BotThreadSyncCommandStatePendingStart(
    authorization: _botAuthorizationIdFromFrb(authorization),
  ),
  superseded: (authorization) => BotThreadSyncCommandStateSuperseded(
    authorization: _botAuthorizationIdFromFrb(authorization),
  ),
);

ThreadClosedAuthorizationsRead _threadClosedAuthorizationsReadFromFrb(
  frb_delivery.BridgeThreadClosedAuthorizationsRead value,
) => value.when(
  unbound: () => ThreadClosedAuthorizationsReadUnbound(),
  unavailable: (reason) => ThreadClosedAuthorizationsReadUnavailable(
    reason: _threadAudienceUnavailableReasonFromFrb(reason),
  ),
  page: (page) => ThreadClosedAuthorizationsReadPage(
    page: _threadClosedAuthorizationPageFromFrb(page),
  ),
);
