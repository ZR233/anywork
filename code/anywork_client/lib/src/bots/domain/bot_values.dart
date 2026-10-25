import 'package:freezed_annotation/freezed_annotation.dart';

part 'bot_values.freezed.dart';

enum BotPlatform { feishuChina }

enum BotCredentialAvailability { missing, sessionOnly, stored, unavailable }

@freezed
abstract class BotModelRoute with _$BotModelRoute {
  const factory BotModelRoute({
    required String accountId,
    required String modelId,
    required String? effort,
  }) = _BotModelRoute;
}

/// Desired enablement and an established connection are independent facts.
@Freezed(toStringOverride: false)
sealed class BotConnectionState with _$BotConnectionState {
  const factory BotConnectionState.disabled() = BotConnectionDisabled;
  const factory BotConnectionState.connecting() = BotConnectionConnecting;
  const factory BotConnectionState.connected() = BotConnectionConnected;
  const factory BotConnectionState.reconnecting({
    required int? nextAttemptAt,
    required int attempt,
  }) = BotConnectionReconnecting;
  const factory BotConnectionState.failed({
    required String code,
    required String message,
    required bool retryable,
    required String? platformCode,
  }) = BotConnectionFailed;
}

/// Availability never settles an in-progress credential/configuration operation.
@Freezed(toStringOverride: false)
sealed class BotCredentialOperation with _$BotCredentialOperation {
  const factory BotCredentialOperation.idle() = BotCredentialOperationIdle;
  const factory BotCredentialOperation.preparing({
    required String operationId,
  }) = BotCredentialOperationPreparing;
  const factory BotCredentialOperation.commitUncertain({
    required String operationId,
  }) = BotCredentialOperationCommitUncertain;
  const factory BotCredentialOperation.cleanupPending({
    required String operationId,
    required bool configCommitted,
  }) = BotCredentialOperationCleanupPending;
}

/// Authorization URLs are short-lived UI material, not printable diagnostics.
@Freezed(toStringOverride: false)
sealed class BotRegistrationStatus with _$BotRegistrationStatus {
  const BotRegistrationStatus._();

  const factory BotRegistrationStatus.idle() = BotRegistrationIdle;
  const factory BotRegistrationStatus.preparing({required String attemptId}) =
      BotRegistrationPreparing;
  const factory BotRegistrationStatus.waiting({
    required String attemptId,
    required String verificationUrl,
    required int expiresAt,
    required int intervalSeconds,
  }) = BotRegistrationWaiting;
  const factory BotRegistrationStatus.slowDown({
    required String attemptId,
    required String verificationUrl,
    required int expiresAt,
    required int intervalSeconds,
  }) = BotRegistrationSlowDown;
  const factory BotRegistrationStatus.completed({required String attemptId}) =
      BotRegistrationCompleted;
  const factory BotRegistrationStatus.committing({
    required String attemptId,
    required String botId,
  }) = BotRegistrationCommitting;
  const factory BotRegistrationStatus.denied({
    required String attemptId,
    required String message,
  }) = BotRegistrationDenied;
  const factory BotRegistrationStatus.expired({required String attemptId}) =
      BotRegistrationExpired;
  const factory BotRegistrationStatus.cancelled({required String attemptId}) =
      BotRegistrationCancelled;
  const factory BotRegistrationStatus.failed({
    required String attemptId,
    required String code,
    required String message,
    required bool retryable,
  }) = BotRegistrationFailed;

  @override
  String toString() => 'BotRegistrationStatus(<redacted>)';
}

@Freezed(toStringOverride: false)
abstract class BotPairingRequest with _$BotPairingRequest {
  const factory BotPairingRequest({
    required String requestId,
    required String botId,
    required String openId,
    required String? displayName,
    required int createdAt,
  }) = _BotPairingRequest;
}

@Freezed(toStringOverride: false)
abstract class BotDiagnostic with _$BotDiagnostic {
  const factory BotDiagnostic({
    required String code,
    required String message,
    required bool retryable,
    required String? platformCode,
    required String? guidance,
  }) = _BotDiagnostic;
}

/// Only a determined configuration belongs in this collection; pending
/// candidates are published separately as BotPendingCredentialOperation.
@Freezed(toStringOverride: false)
final class BotSnapshot with _$BotSnapshot {
  BotSnapshot({
    required this.lastActivityAt,
    required this.id,
    required this.name,
    required this.projectId,
    required this.appId,
    required this.platform,
    required this.enabled,
    required this.toolsEnabled,
    required this.modelRoute,
    required this.workspacePath,
    required this.configRevision,
    required List<String> trustedOpenIds,
    required List<String> trustedChatIds,
    required this.connection,
    required this.credential,
    required this.credentialOperation,
    required List<BotPairingRequest> pairing,
    required this.diagnostic,
    required this.canChangeProject,
    required this.canChangeAppId,
    required this.createdAt,
    required this.updatedAt,
  }) : trustedOpenIds = List.unmodifiable(trustedOpenIds),
       trustedChatIds = List.unmodifiable(trustedChatIds),
       pairing = List.unmodifiable(pairing);

  final int? lastActivityAt;
  final String id;
  final String name;
  final String projectId;
  final String appId;
  final BotPlatform platform;
  final bool enabled;
  final bool toolsEnabled;
  final BotModelRoute? modelRoute;
  final String workspacePath;
  final int configRevision;
  final List<String> trustedOpenIds;
  final List<String> trustedChatIds;
  final BotConnectionState connection;
  final BotCredentialAvailability credential;
  final BotCredentialOperation credentialOperation;
  final List<BotPairingRequest> pairing;
  final BotDiagnostic? diagnostic;
  final bool canChangeProject;
  final bool canChangeAppId;
  final int createdAt;
  final int updatedAt;
}

@Freezed(toStringOverride: false)
abstract class BotPendingCredentialOperation
    with _$BotPendingCredentialOperation {
  const factory BotPendingCredentialOperation({
    required String botId,
    required BotCredentialOperation credentialOperation,
    required BotDiagnostic? diagnostic,
  }) = _BotPendingCredentialOperation;
}

@Freezed(toStringOverride: false)
abstract class BotRegistrationAttempt with _$BotRegistrationAttempt {
  const factory BotRegistrationAttempt({
    required String attemptId,
    required String name,
    required String projectId,
    required BotRegistrationStatus status,
    required String? completedBotId,
  }) = _BotRegistrationAttempt;
}

/// The Rust-owned Bots topic value. There is deliberately no synthetic empty
/// constructor: before a real source value arrives, the repository is unknown.
@Freezed(toStringOverride: false)
final class BotsStateSnapshot with _$BotsStateSnapshot {
  BotsStateSnapshot({
    required this.revision,
    required this.updatedAt,
    required List<BotSnapshot> bots,
    required this.registration,
    required List<BotPendingCredentialOperation> pendingCredentialOperations,
  }) : bots = List.unmodifiable(bots),
       pendingCredentialOperations = List.unmodifiable(
         pendingCredentialOperations,
       );

  final int revision;
  final int updatedAt;
  final List<BotSnapshot> bots;
  final BotRegistrationAttempt? registration;
  final List<BotPendingCredentialOperation> pendingCredentialOperations;
}
