import 'package:anywork_client/bots.dart';
import 'package:anywork_client/resources.dart';

import 'driver_snapshot.dart';

/// Published Bots values only. Never synchronizes the Repository, reads a
/// credential, exposes authorization URLs or settles an independent operation.
DriverBotsObservation projectBotsState(BotsState state) {
  final material = state.snapshot;
  final projection = state.projection;
  if (projection.sync.phase != ResourceSyncPhase.ready ||
      material == null ||
      material.origin != projection.stamp?.origin ||
      material.value.revision != projection.header?.botsRevision) {
    return const DriverBotsUnknown(
      'Current Bots Repository source not available',
    );
  }
  final value = material.value;
  final registration = value.registration;
  return DriverBotsValue(
    revision: value.revision,
    bots: [
      for (final bot in value.bots)
        DriverBotValue(
          id: bot.id,
          name: bot.name,
          enabled: bot.enabled,
          credential: bot.credential.name,
          connectionKind: switch (bot.connection) {
            BotConnectionDisabled() => 'disabled',
            BotConnectionConnecting() => 'connecting',
            BotConnectionConnected() => 'connected',
            BotConnectionReconnecting() => 'reconnecting',
            BotConnectionFailed() => 'failed',
          },
          pendingKind: credentialOperationKind(bot.credentialOperation),
          configCommitted: credentialCommitFact(bot.credentialOperation),
          configRevision: bot.configRevision,
          trustedUserCount: bot.trustedOpenIds.length,
          trustedGroupCount: bot.trustedChatIds.length,
          pairingCount: bot.pairing.length,
          canChangeProject: bot.canChangeProject,
          canChangeAppId: bot.canChangeAppId,
        ),
    ],
    pending: [
      for (final pending in value.pendingCredentialOperations)
        DriverCredentialOperationValue(
          botId: pending.botId,
          kind: credentialOperationKind(pending.credentialOperation) ?? 'idle',
          configCommitted: credentialCommitFact(pending.credentialOperation),
        ),
    ],
    registrationAttemptId: registration?.attemptId,
    registrationKind: switch (registration?.status) {
      null || BotRegistrationIdle() => null,
      BotRegistrationPreparing() => 'preparing',
      BotRegistrationWaiting() => 'waiting',
      BotRegistrationSlowDown() => 'slowDown',
      BotRegistrationCompleted() => 'completed',
      BotRegistrationCommitting() => 'committing',
      BotRegistrationDenied() => 'denied',
      BotRegistrationExpired() => 'expired',
      BotRegistrationCancelled() => 'cancelled',
      BotRegistrationFailed() => 'failed',
    },
    registrationBotId: switch (registration?.status) {
      BotRegistrationCommitting(:final botId) => botId,
      _ => null,
    },
    completedBotId: registration?.completedBotId,
  );
}

String? credentialOperationKind(BotCredentialOperation operation) =>
    switch (operation) {
      BotCredentialOperationIdle() => null,
      BotCredentialOperationPreparing() => 'preparing',
      BotCredentialOperationCommitUncertain() => 'commitUncertain',
      BotCredentialOperationCleanupPending() => 'cleanupPending',
    };

bool? credentialCommitFact(BotCredentialOperation operation) =>
    switch (operation) {
      BotCredentialOperationCleanupPending(:final configCommitted) =>
        configCommitted,
      _ => null,
    };
