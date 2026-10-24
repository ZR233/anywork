part of 'studio_api.dart';

BotsStateSnapshot _botsStateFromFrb(
  frb_bots_types.BridgeBotsStateSnapshot value,
) {
  return BotsStateSnapshot(
    revision: value.revision.toInt(),
    updatedAt: value.updatedAt.toInt(),
    bots: [for (final bot in value.bots) _botSnapshotFromFrb(bot)],
    registration: value.registration == null
        ? null
        : _registrationAttemptFromFrb(value.registration!),
    pendingCredentialOperations: [
      for (final pending in value.pendingCredentialOperations)
        _pendingCredentialFromFrb(pending),
    ],
  );
}

BotSnapshot _botSnapshotFromFrb(frb_bots_types.BridgeBotSnapshot value) {
  return BotSnapshot(
    lastActivityAt: value.lastActivityAt,
    id: value.id,
    name: value.name,
    projectId: value.projectId,
    appId: value.appId,
    platform: BotPlatform.feishuChina,
    enabled: value.enabled,
    toolsEnabled: value.toolsEnabled,
    modelRoute: value.modelRoute == null
        ? null
        : BotModelRoute(
            accountId: value.modelRoute!.accountId,
            modelId: value.modelRoute!.modelId,
            effort: value.modelRoute!.effort,
          ),
    workspacePath: value.workspacePath,
    configRevision: value.configRevision.toInt(),
    trustedOpenIds: List<String>.unmodifiable(value.trustedOpenIds),
    trustedChatIds: List<String>.unmodifiable(value.trustedChatIds),
    connection: _botConnectionFromFrb(value.connection),
    credential: switch (value.credential) {
      frb_bots_types.BridgeBotCredentialAvailability.missing =>
        BotCredentialAvailability.missing,
      frb_bots_types.BridgeBotCredentialAvailability.sessionOnly =>
        BotCredentialAvailability.sessionOnly,
      frb_bots_types.BridgeBotCredentialAvailability.stored =>
        BotCredentialAvailability.stored,
      frb_bots_types.BridgeBotCredentialAvailability.unavailable =>
        BotCredentialAvailability.unavailable,
    },
    credentialOperation: _credentialOperationFromFrb(value.credentialOperation),
    pairing: [for (final item in value.pairing) _pairingFromFrb(item)],
    diagnostic: value.diagnostic == null
        ? null
        : _botDiagnosticFromFrb(value.diagnostic!),
    canChangeProject: value.canChangeProject,
    canChangeAppId: value.canChangeAppId,
    createdAt: value.createdAt.toInt(),
    updatedAt: value.updatedAt.toInt(),
  );
}

BotConnectionState _botConnectionFromFrb(
  frb_bots_types.BridgeBotConnectionState value,
) {
  return switch (value) {
    frb_bots_types.BridgeBotConnectionState_Disabled() =>
      const BotConnectionDisabled(),
    frb_bots_types.BridgeBotConnectionState_Connecting() =>
      const BotConnectionConnecting(),
    frb_bots_types.BridgeBotConnectionState_Connected() =>
      const BotConnectionConnected(),
    frb_bots_types.BridgeBotConnectionState_Reconnecting(
      :final nextAttemptAt,
      :final attempt,
    ) =>
      BotConnectionReconnecting(
        nextAttemptAt: nextAttemptAt?.toInt(),
        attempt: attempt,
      ),
    frb_bots_types.BridgeBotConnectionState_Failed(
      :final code,
      :final message,
      :final retryable,
      :final platformCode,
    ) =>
      BotConnectionFailed(
        code: code,
        message: message,
        retryable: retryable,
        platformCode: platformCode,
      ),
  };
}

BotCredentialOperation _credentialOperationFromFrb(
  frb_bots_types.BridgeBotCredentialOperation value,
) {
  return switch (value) {
    frb_bots_types.BridgeBotCredentialOperation_Idle() =>
      const BotCredentialOperationIdle(),
    frb_bots_types.BridgeBotCredentialOperation_Preparing(:final operationId) =>
      BotCredentialOperationPreparing(operationId: operationId),
    frb_bots_types.BridgeBotCredentialOperation_CommitUncertain(
      :final operationId,
    ) =>
      BotCredentialOperationCommitUncertain(operationId: operationId),
    frb_bots_types.BridgeBotCredentialOperation_CleanupPending(
      :final operationId,
      :final configCommitted,
    ) =>
      BotCredentialOperationCleanupPending(
        operationId: operationId,
        configCommitted: configCommitted,
      ),
  };
}

BotPairingRequest _pairingFromFrb(
  frb_bots_types.BridgeBotPairingRequest value,
) {
  return BotPairingRequest(
    requestId: value.requestId,
    botId: value.botId,
    openId: value.openId,
    displayName: value.displayName,
    createdAt: value.createdAt.toInt(),
  );
}

BotDiagnostic _botDiagnosticFromFrb(frb_bots_types.BridgeBotDiagnostic value) {
  return BotDiagnostic(
    code: value.code,
    message: value.message,
    retryable: value.retryable,
    platformCode: value.platformCode,
    guidance: value.guidance,
  );
}

BotPendingCredentialOperation _pendingCredentialFromFrb(
  frb_bots_types.BridgeBotPendingCredentialOperation value,
) {
  return BotPendingCredentialOperation(
    botId: value.botId,
    credentialOperation: _credentialOperationFromFrb(value.credentialOperation),
    diagnostic: value.diagnostic == null
        ? null
        : _botDiagnosticFromFrb(value.diagnostic!),
  );
}

BotRegistrationAttempt _registrationAttemptFromFrb(
  frb_bots_types.BridgeBotRegistrationAttempt value,
) {
  return BotRegistrationAttempt(
    attemptId: value.attemptId,
    name: value.name,
    projectId: value.projectId,
    status: _registrationStatusFromFrb(value.status),
    completedBotId: value.completedBotId,
  );
}

BotRegistrationStatus _registrationStatusFromFrb(
  frb_bots_types.BridgeBotRegistrationStatus value,
) {
  return switch (value) {
    frb_bots_types.BridgeBotRegistrationStatus_Idle() =>
      const BotRegistrationIdle(),
    frb_bots_types.BridgeBotRegistrationStatus_Preparing(:final attemptId) =>
      BotRegistrationPreparing(attemptId: attemptId),
    frb_bots_types.BridgeBotRegistrationStatus_Waiting(
      :final attemptId,
      :final verificationUrl,
      :final expiresAt,
      :final intervalSeconds,
    ) =>
      BotRegistrationWaiting(
        attemptId: attemptId,
        verificationUrl: verificationUrl,
        expiresAt: expiresAt.toInt(),
        intervalSeconds: intervalSeconds,
      ),
    frb_bots_types.BridgeBotRegistrationStatus_SlowDown(
      :final attemptId,
      :final verificationUrl,
      :final expiresAt,
      :final intervalSeconds,
    ) =>
      BotRegistrationSlowDown(
        attemptId: attemptId,
        verificationUrl: verificationUrl,
        expiresAt: expiresAt.toInt(),
        intervalSeconds: intervalSeconds,
      ),
    frb_bots_types.BridgeBotRegistrationStatus_Completed(:final attemptId) =>
      BotRegistrationCompleted(attemptId: attemptId),
    frb_bots_types.BridgeBotRegistrationStatus_Committing(
      :final attemptId,
      :final botId,
    ) =>
      BotRegistrationCommitting(attemptId: attemptId, botId: botId),
    frb_bots_types.BridgeBotRegistrationStatus_Denied(
      :final attemptId,
      :final message,
    ) =>
      BotRegistrationDenied(attemptId: attemptId, message: message),
    frb_bots_types.BridgeBotRegistrationStatus_Expired(:final attemptId) =>
      BotRegistrationExpired(attemptId: attemptId),
    frb_bots_types.BridgeBotRegistrationStatus_Cancelled(:final attemptId) =>
      BotRegistrationCancelled(attemptId: attemptId),
    frb_bots_types.BridgeBotRegistrationStatus_Failed(
      :final attemptId,
      :final code,
      :final message,
      :final retryable,
    ) =>
      BotRegistrationFailed(
        attemptId: attemptId,
        code: code,
        message: message,
        retryable: retryable,
      ),
  };
}

frb_bots_types.BridgeBotSecretUpdate _secretUpdateToFrb(BotSecretUpdate value) {
  return switch (value) {
    BotSecretPreserve() =>
      const frb_bots_types.BridgeBotSecretUpdate.preserve(),
    BotSecretReplace(:final value) =>
      frb_bots_types.BridgeBotSecretUpdate.replace(value: value),
    BotSecretClear() => const frb_bots_types.BridgeBotSecretUpdate.clear(),
  };
}

frb_bots_types.BridgeSaveBotRequest _saveBotToFrb(SaveBotRequest request) {
  return frb_bots_types.BridgeSaveBotRequest(
    modelRoute: request.modelRoute == null
        ? null
        : frb_bots_types.BridgeBotModelRoute(
            accountId: request.modelRoute!.accountId,
            modelId: request.modelRoute!.modelId,
            effort: request.modelRoute!.effort,
          ),
    operationId: request.operationId,
    botId: request.botId,
    expectedConfigRevision: BigInt.from(request.expectedConfigRevision),
    name: request.name,
    projectId: request.projectId,
    appId: request.appId,
    secret: _secretUpdateToFrb(request.secret),
    enabled: request.enabled,
    toolsEnabled: request.toolsEnabled,
  );
}

BotsCommandReply _botsCommandReplyFromFrb(
  frb_bots_types.BridgeBotsCommandReply value,
) {
  return BotsCommandReply(
    snapshot: _botsStateFromFrb(value.snapshot),
    receipt: _commandReceiptFromFrb(value.receipt),
    stamp: value.stamp == null
        ? null
        : ResourceStamp(
            resourceKey: value.stamp!.resourceKey,
            ownerEpoch: value.stamp!.ownerEpoch,
            revision: value.stamp!.revision.toInt(),
          ),
  );
}

BotConversationPage _conversationPageFromFrb(
  frb_bots_types.BridgeBotConversationPage value,
) {
  return BotConversationPage(
    botId: value.botId,
    conversations: [
      for (final item in value.conversations) _conversationFromFrb(item),
    ],
    nextCursor: value.nextCursor,
  );
}

BotConversation _conversationFromFrb(
  frb_bots_types.BridgeBotConversation value,
) {
  return BotConversation(
    chatId: value.chatId,
    kind: switch (value.kind) {
      frb_bots_types.BridgeBotConversationKind.group =>
        BotConversationKind.group,
      frb_bots_types.BridgeBotConversationKind.direct =>
        BotConversationKind.direct,
    },
    source: switch (value.source) {
      frb_bots_types.BridgeBotConversationSource.remoteGroup =>
        BotConversationSource.remoteGroup,
      frb_bots_types.BridgeBotConversationSource.observedDirect =>
        BotConversationSource.observedDirect,
    },
    name: value.name,
    lastObservedAt: value.lastObservedAt?.toInt(),
    threadBinding: value.threadBinding == null
        ? null
        : _threadBindingFromFrb(value.threadBinding!),
  );
}

BotConversationThreadBinding _threadBindingFromFrb(
  frb_bots_types.BridgeBotConversationThreadBinding value,
) {
  return BotConversationThreadBinding(
    botId: value.botId,
    chatId: value.chatId,
    projectId: value.projectId,
    threadId: value.threadId,
    revision: value.revision.toInt(),
    state: switch (value.state) {
      frb_bots_types.BridgeBotConversationThreadState.creating =>
        BotConversationThreadState.creating,
      frb_bots_types.BridgeBotConversationThreadState.bound =>
        BotConversationThreadState.bound,
      frb_bots_types.BridgeBotConversationThreadState.needsAttention =>
        BotConversationThreadState.needsAttention,
    },
    diagnostic: value.diagnostic == null
        ? null
        : _botDiagnosticFromFrb(value.diagnostic!),
  );
}

BotConversationThreadReply _conversationThreadReplyFromFrb(
  frb_bots_types.BridgeBotConversationThreadReply value,
) {
  return BotConversationThreadReply(
    binding: _threadBindingFromFrb(value.binding),
    receipt: _commandReceiptFromFrb(value.receipt),
  );
}

BotMessagePage _messagePageFromFrb(frb_bots_types.BridgeBotMessagePage value) {
  return BotMessagePage(
    botId: value.botId,
    chatId: value.chatId,
    messages: [for (final item in value.messages) _botMessageFromFrb(item)],
    nextCursor: value.nextCursor,
  );
}

BotMessage _botMessageFromFrb(frb_bots_types.BridgeBotMessage value) {
  return BotMessage(
    messageId: value.messageId,
    chatId: value.chatId,
    senderOpenId: value.senderOpenId,
    createdAt: value.createdAt.toInt(),
    body: switch (value.body) {
      frb_bots_types.BridgeBotMessageBody_Text(:final text) =>
        BotTextMessageBody(text),
      frb_bots_types.BridgeBotMessageBody_Post(:final text) =>
        BotPostMessageBody(text),
      frb_bots_types.BridgeBotMessageBody_Unsupported(
        :final msgType,
        :final notice,
      ) =>
        BotUnsupportedMessageBody(msgType: msgType, notice: notice),
    },
  );
}

BotSendResult _sendResultFromFrb(frb_bots_types.BridgeBotSendResult value) {
  return BotSendResult(
    operationId: value.operationId,
    botId: value.botId,
    chatId: value.chatId,
    status: _sendStatusFromFrb(value.status),
    segments: [for (final item in value.segments) _sendSegmentFromFrb(item)],
    receipt: _commandReceiptFromFrb(value.receipt),
  );
}

BotSendSegment _sendSegmentFromFrb(frb_bots_types.BridgeBotSendSegment value) {
  return BotSendSegment(
    index: value.index,
    status: _sendStatusFromFrb(value.status),
    uploadStage: value.uploadStage == null
        ? null
        : _sendStageFromFrb(value.uploadStage!),
    messageStage: _sendStageFromFrb(value.messageStage),
    stopReason: switch (value.stopReason) {
      null => null,
      frb_bots_types.BridgeBotSendStopReason.cancelled =>
        BotSendStopReason.cancelled,
      frb_bots_types.BridgeBotSendStopReason.localFailure =>
        BotSendStopReason.localFailure,
    },
    platformMessageId: value.platformMessageId,
    diagnostic: value.diagnostic == null
        ? null
        : _botDiagnosticFromFrb(value.diagnostic!),
  );
}

BotSendStatus _sendStatusFromFrb(frb_bots_types.BridgeBotSendStatus value) {
  return switch (value) {
    frb_bots_types.BridgeBotSendStatus.succeeded => BotSendStatus.succeeded,
    frb_bots_types.BridgeBotSendStatus.partial => BotSendStatus.partial,
    frb_bots_types.BridgeBotSendStatus.rejected => BotSendStatus.rejected,
    frb_bots_types.BridgeBotSendStatus.unknown => BotSendStatus.unknown,
  };
}

BotSendStage _sendStageFromFrb(frb_bots_types.BridgeBotSendStage value) {
  return switch (value) {
    frb_bots_types.BridgeBotSendStage.notStarted => BotSendStage.notStarted,
    frb_bots_types.BridgeBotSendStage.accepted => BotSendStage.accepted,
    frb_bots_types.BridgeBotSendStage.rejected => BotSendStage.rejected,
    frb_bots_types.BridgeBotSendStage.unknown => BotSendStage.unknown,
  };
}
