import 'package:anywork_client/bots.dart';

import '../../../../rust/api/studio/types/bots.dart' as native;
import '../../shared/exact_numbers.dart';

BotModelRoute botModelRouteFromBridge(native.BridgeBotModelRoute value) =>
    BotModelRoute(
      accountId: value.accountId,
      modelId: value.modelId,
      effort: value.effort,
    );

BotDiagnostic botDiagnosticFromBridge(native.BridgeBotDiagnostic value) =>
    BotDiagnostic(
      code: value.code,
      message: value.message,
      retryable: value.retryable,
      platformCode: value.platformCode,
      guidance: value.guidance,
    );

BotConnectionState botConnectionFromBridge(
  native.BridgeBotConnectionState value,
) => switch (value) {
  native.BridgeBotConnectionState_Disabled() =>
    const BotConnectionState.disabled(),
  native.BridgeBotConnectionState_Connecting() =>
    const BotConnectionState.connecting(),
  native.BridgeBotConnectionState_Connected() =>
    const BotConnectionState.connected(),
  native.BridgeBotConnectionState_Reconnecting(
    :final nextAttemptAt,
    :final attempt,
  ) =>
    BotConnectionState.reconnecting(
      nextAttemptAt: nextAttemptAt == null
          ? null
          : exactI64(
              BigInt.from(nextAttemptAt),
              'bot next attempt Unix seconds',
            ),
      attempt: attempt,
    ),
  native.BridgeBotConnectionState_Failed(
    :final code,
    :final message,
    :final retryable,
    :final platformCode,
  ) =>
    BotConnectionState.failed(
      code: code,
      message: message,
      retryable: retryable,
      platformCode: platformCode,
    ),
};

BotCredentialOperation botCredentialOperationFromBridge(
  native.BridgeBotCredentialOperation value,
) => switch (value) {
  native.BridgeBotCredentialOperation_Idle() =>
    const BotCredentialOperation.idle(),
  native.BridgeBotCredentialOperation_Preparing(:final operationId) =>
    BotCredentialOperation.preparing(operationId: operationId),
  native.BridgeBotCredentialOperation_CommitUncertain(:final operationId) =>
    BotCredentialOperation.commitUncertain(operationId: operationId),
  native.BridgeBotCredentialOperation_CleanupPending(
    :final operationId,
    :final configCommitted,
  ) =>
    BotCredentialOperation.cleanupPending(
      operationId: operationId,
      configCommitted: configCommitted,
    ),
};

BotSnapshot botSnapshotFromBridge(
  native.BridgeBotSnapshot value,
) => BotSnapshot(
  lastActivityAt: value.lastActivityAt == null
      ? null
      : exactI64(
          BigInt.from(value.lastActivityAt!),
          'bot last activity Unix seconds',
        ),
  id: value.id,
  name: value.name,
  projectId: value.projectId,
  appId: value.appId,
  platform: switch (value.platform) {
    native.BridgeBotPlatform.feishuChina => BotPlatform.feishuChina,
  },
  enabled: value.enabled,
  toolsEnabled: value.toolsEnabled,
  modelRoute: value.modelRoute == null
      ? null
      : botModelRouteFromBridge(value.modelRoute!),
  workspacePath: value.workspacePath,
  configRevision: exactU64(value.configRevision, 'bot configuration revision'),
  trustedOpenIds: List.unmodifiable(value.trustedOpenIds),
  trustedChatIds: List.unmodifiable(value.trustedChatIds),
  connection: botConnectionFromBridge(value.connection),
  credential: switch (value.credential) {
    native.BridgeBotCredentialAvailability.missing =>
      BotCredentialAvailability.missing,
    native.BridgeBotCredentialAvailability.sessionOnly =>
      BotCredentialAvailability.sessionOnly,
    native.BridgeBotCredentialAvailability.stored =>
      BotCredentialAvailability.stored,
    native.BridgeBotCredentialAvailability.unavailable =>
      BotCredentialAvailability.unavailable,
  },
  credentialOperation: botCredentialOperationFromBridge(
    value.credentialOperation,
  ),
  pairing: List.unmodifiable([
    for (final request in value.pairing)
      BotPairingRequest(
        requestId: request.requestId,
        botId: request.botId,
        openId: request.openId,
        displayName: request.displayName,
        createdAt: exactI64(
          BigInt.from(request.createdAt),
          'bot pairing Unix seconds',
        ),
      ),
  ]),
  diagnostic: value.diagnostic == null
      ? null
      : botDiagnosticFromBridge(value.diagnostic!),
  canChangeProject: value.canChangeProject,
  canChangeAppId: value.canChangeAppId,
  createdAt: exactI64(BigInt.from(value.createdAt), 'bot created Unix seconds'),
  updatedAt: exactI64(BigInt.from(value.updatedAt), 'bot updated Unix seconds'),
);
