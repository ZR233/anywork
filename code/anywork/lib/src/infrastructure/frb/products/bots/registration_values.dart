import 'package:anywork_client/bots.dart';

import '../../../../rust/api/studio/types/bots.dart' as native;
import '../../shared/exact_numbers.dart';

BotRegistrationAttempt botRegistrationFromBridge(
  native.BridgeBotRegistrationAttempt value,
) => BotRegistrationAttempt(
  attemptId: value.attemptId,
  name: value.name,
  projectId: value.projectId,
  status: botRegistrationStatusFromBridge(value.status),
  completedBotId: value.completedBotId,
);

BotRegistrationStatus botRegistrationStatusFromBridge(
  native.BridgeBotRegistrationStatus value,
) => switch (value) {
  native.BridgeBotRegistrationStatus_Idle() =>
    const BotRegistrationStatus.idle(),
  native.BridgeBotRegistrationStatus_Preparing(:final attemptId) =>
    BotRegistrationStatus.preparing(attemptId: attemptId),
  native.BridgeBotRegistrationStatus_Waiting(
    :final attemptId,
    :final verificationUrl,
    :final expiresAt,
    :final intervalSeconds,
  ) =>
    BotRegistrationStatus.waiting(
      attemptId: attemptId,
      verificationUrl: verificationUrl,
      expiresAt: exactI64(
        BigInt.from(expiresAt),
        'bot registration expiry Unix seconds',
      ),
      intervalSeconds: intervalSeconds,
    ),
  native.BridgeBotRegistrationStatus_SlowDown(
    :final attemptId,
    :final verificationUrl,
    :final expiresAt,
    :final intervalSeconds,
  ) =>
    BotRegistrationStatus.slowDown(
      attemptId: attemptId,
      verificationUrl: verificationUrl,
      expiresAt: exactI64(
        BigInt.from(expiresAt),
        'bot registration expiry Unix seconds',
      ),
      intervalSeconds: intervalSeconds,
    ),
  native.BridgeBotRegistrationStatus_Completed(:final attemptId) =>
    BotRegistrationStatus.completed(attemptId: attemptId),
  native.BridgeBotRegistrationStatus_Committing(
    :final attemptId,
    :final botId,
  ) =>
    BotRegistrationStatus.committing(attemptId: attemptId, botId: botId),
  native.BridgeBotRegistrationStatus_Denied(:final attemptId, :final message) =>
    BotRegistrationStatus.denied(attemptId: attemptId, message: message),
  native.BridgeBotRegistrationStatus_Expired(:final attemptId) =>
    BotRegistrationStatus.expired(attemptId: attemptId),
  native.BridgeBotRegistrationStatus_Cancelled(:final attemptId) =>
    BotRegistrationStatus.cancelled(attemptId: attemptId),
  native.BridgeBotRegistrationStatus_Failed(
    :final attemptId,
    :final code,
    :final message,
    :final retryable,
  ) =>
    BotRegistrationStatus.failed(
      attemptId: attemptId,
      code: code,
      message: message,
      retryable: retryable,
    ),
};
