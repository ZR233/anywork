import 'collection_equality.dart';

import 'command_receipts.dart';

/// 飞书中国版自建应用。
enum BotPlatform { feishuChina }

/// 机器人连接生命周期。保存成功不等于已连接。
sealed class BotConnectionState {
  const BotConnectionState();
}

final class BotConnectionDisabled extends BotConnectionState {
  const BotConnectionDisabled();

  @override
  bool operator ==(Object other) => other is BotConnectionDisabled;

  @override
  int get hashCode => 0x6201;
}

final class BotConnectionConnecting extends BotConnectionState {
  const BotConnectionConnecting();

  @override
  bool operator ==(Object other) => other is BotConnectionConnecting;

  @override
  int get hashCode => 0x6202;
}

final class BotConnectionConnected extends BotConnectionState {
  const BotConnectionConnected();

  @override
  bool operator ==(Object other) => other is BotConnectionConnected;

  @override
  int get hashCode => 0x6203;
}

final class BotConnectionReconnecting extends BotConnectionState {
  const BotConnectionReconnecting({this.nextAttemptAt, required this.attempt});

  final int? nextAttemptAt;
  final int attempt;

  @override
  bool operator ==(Object other) =>
      other is BotConnectionReconnecting &&
      nextAttemptAt == other.nextAttemptAt &&
      attempt == other.attempt;

  @override
  int get hashCode => Object.hash(0x6204, nextAttemptAt, attempt);
}

final class BotConnectionFailed extends BotConnectionState {
  const BotConnectionFailed({
    required this.code,
    required this.message,
    required this.retryable,
    this.platformCode,
  });

  final String code;
  final String message;
  final bool retryable;
  final String? platformCode;

  @override
  bool operator ==(Object other) =>
      other is BotConnectionFailed &&
      code == other.code &&
      message == other.message &&
      retryable == other.retryable &&
      platformCode == other.platformCode;

  @override
  int get hashCode =>
      Object.hash(0x6205, code, message, retryable, platformCode);
}

/// App Secret 可用性。`sessionOnly` 表示仅进程 secret lease，未永久保存。
enum BotCredentialAvailability { missing, sessionOnly, stored, unavailable }

/// 凭据/配置共同提交的公开操作状态。不含 secret、候选材料或内部版本引用。
sealed class BotCredentialOperation {
  const BotCredentialOperation();
}

final class BotCredentialOperationIdle extends BotCredentialOperation {
  const BotCredentialOperationIdle();

  @override
  bool operator ==(Object other) => other is BotCredentialOperationIdle;

  @override
  int get hashCode => 0x6210;
}

final class BotCredentialOperationPreparing extends BotCredentialOperation {
  const BotCredentialOperationPreparing({required this.operationId});

  final String operationId;

  @override
  bool operator ==(Object other) =>
      other is BotCredentialOperationPreparing &&
      operationId == other.operationId;

  @override
  int get hashCode => Object.hash(0x6211, operationId);
}

final class BotCredentialOperationCommitUncertain
    extends BotCredentialOperation {
  const BotCredentialOperationCommitUncertain({required this.operationId});

  final String operationId;

  @override
  bool operator ==(Object other) =>
      other is BotCredentialOperationCommitUncertain &&
      operationId == other.operationId;

  @override
  int get hashCode => Object.hash(0x6212, operationId);
}

final class BotCredentialOperationCleanupPending
    extends BotCredentialOperation {
  const BotCredentialOperationCleanupPending({
    required this.operationId,
    required this.configCommitted,
  });

  final String operationId;
  final bool configCommitted;

  @override
  bool operator ==(Object other) =>
      other is BotCredentialOperationCleanupPending &&
      operationId == other.operationId &&
      configCommitted == other.configCommitted;

  @override
  int get hashCode => Object.hash(0x6213, operationId, configCommitted);
}

/// 扫码注册对外状态。设备码不进入模型。
sealed class BotRegistrationStatus {
  const BotRegistrationStatus();

  String? get attemptId => switch (this) {
    BotRegistrationIdle() => null,
    BotRegistrationPreparing(:final attemptId) ||
    BotRegistrationWaiting(:final attemptId) ||
    BotRegistrationSlowDown(:final attemptId) ||
    BotRegistrationCompleted(:final attemptId) ||
    BotRegistrationCommitting(:final attemptId) ||
    BotRegistrationDenied(:final attemptId) ||
    BotRegistrationExpired(:final attemptId) ||
    BotRegistrationCancelled(:final attemptId) ||
    BotRegistrationFailed(:final attemptId) => attemptId,
  };

  /// 仅 Waiting/SlowDown 持有验证链接；其它状态必须为空。
  String? get verificationUrl => switch (this) {
    BotRegistrationWaiting(:final verificationUrl) ||
    BotRegistrationSlowDown(:final verificationUrl) => verificationUrl,
    _ => null,
  };

  @override
  String toString() => switch (this) {
    BotRegistrationIdle() => 'BotRegistrationIdle()',
    BotRegistrationPreparing(:final attemptId) =>
      'BotRegistrationPreparing(attemptId: $attemptId)',
    BotRegistrationWaiting(
      :final attemptId,
      :final expiresAt,
      :final intervalSeconds,
    ) =>
      'BotRegistrationWaiting(attemptId: $attemptId, verificationUrl: <redacted>, expiresAt: $expiresAt, intervalSeconds: $intervalSeconds)',
    BotRegistrationSlowDown(
      :final attemptId,
      :final expiresAt,
      :final intervalSeconds,
    ) =>
      'BotRegistrationSlowDown(attemptId: $attemptId, verificationUrl: <redacted>, expiresAt: $expiresAt, intervalSeconds: $intervalSeconds)',
    BotRegistrationCompleted(:final attemptId) =>
      'BotRegistrationCompleted(attemptId: $attemptId)',
    BotRegistrationCommitting(:final attemptId, :final botId) =>
      'BotRegistrationCommitting(attemptId: $attemptId, botId: $botId)',
    BotRegistrationDenied(:final attemptId, :final message) =>
      'BotRegistrationDenied(attemptId: $attemptId, message: $message)',
    BotRegistrationExpired(:final attemptId) =>
      'BotRegistrationExpired(attemptId: $attemptId)',
    BotRegistrationCancelled(:final attemptId) =>
      'BotRegistrationCancelled(attemptId: $attemptId)',
    BotRegistrationFailed(
      :final attemptId,
      :final code,
      :final message,
      :final retryable,
    ) =>
      'BotRegistrationFailed(attemptId: $attemptId, code: $code, message: $message, retryable: $retryable)',
  };
}

final class BotRegistrationIdle extends BotRegistrationStatus {
  const BotRegistrationIdle();

  @override
  bool operator ==(Object other) => other is BotRegistrationIdle;

  @override
  int get hashCode => 0x6220;
}

final class BotRegistrationPreparing extends BotRegistrationStatus {
  const BotRegistrationPreparing({required this.attemptId});

  @override
  final String attemptId;

  @override
  bool operator ==(Object other) =>
      other is BotRegistrationPreparing && attemptId == other.attemptId;

  @override
  int get hashCode => Object.hash(0x6221, attemptId);
}

final class BotRegistrationWaiting extends BotRegistrationStatus {
  const BotRegistrationWaiting({
    required this.attemptId,
    required this.verificationUrl,
    required this.expiresAt,
    required this.intervalSeconds,
  });

  @override
  final String attemptId;
  @override
  final String verificationUrl;
  final int expiresAt;
  final int intervalSeconds;

  @override
  bool operator ==(Object other) =>
      other is BotRegistrationWaiting &&
      attemptId == other.attemptId &&
      verificationUrl == other.verificationUrl &&
      expiresAt == other.expiresAt &&
      intervalSeconds == other.intervalSeconds;

  @override
  int get hashCode => Object.hash(
    0x6222,
    attemptId,
    verificationUrl,
    expiresAt,
    intervalSeconds,
  );
}

final class BotRegistrationSlowDown extends BotRegistrationStatus {
  const BotRegistrationSlowDown({
    required this.attemptId,
    required this.verificationUrl,
    required this.expiresAt,
    required this.intervalSeconds,
  });

  @override
  final String attemptId;
  @override
  final String verificationUrl;
  final int expiresAt;
  final int intervalSeconds;

  @override
  bool operator ==(Object other) =>
      other is BotRegistrationSlowDown &&
      attemptId == other.attemptId &&
      verificationUrl == other.verificationUrl &&
      expiresAt == other.expiresAt &&
      intervalSeconds == other.intervalSeconds;

  @override
  int get hashCode => Object.hash(
    0x6223,
    attemptId,
    verificationUrl,
    expiresAt,
    intervalSeconds,
  );
}

final class BotRegistrationCompleted extends BotRegistrationStatus {
  const BotRegistrationCompleted({required this.attemptId});

  @override
  final String attemptId;

  @override
  bool operator ==(Object other) =>
      other is BotRegistrationCompleted && attemptId == other.attemptId;

  @override
  int get hashCode => Object.hash(0x6224, attemptId);
}

final class BotRegistrationCommitting extends BotRegistrationStatus {
  const BotRegistrationCommitting({
    required this.attemptId,
    required this.botId,
  });

  @override
  final String attemptId;
  final String botId;

  @override
  bool operator ==(Object other) =>
      other is BotRegistrationCommitting &&
      attemptId == other.attemptId &&
      botId == other.botId;

  @override
  int get hashCode => Object.hash(0x6225, attemptId, botId);
}

final class BotRegistrationDenied extends BotRegistrationStatus {
  const BotRegistrationDenied({required this.attemptId, required this.message});

  @override
  final String attemptId;
  final String message;

  @override
  bool operator ==(Object other) =>
      other is BotRegistrationDenied &&
      attemptId == other.attemptId &&
      message == other.message;

  @override
  int get hashCode => Object.hash(0x6226, attemptId, message);
}

final class BotRegistrationExpired extends BotRegistrationStatus {
  const BotRegistrationExpired({required this.attemptId});

  @override
  final String attemptId;

  @override
  bool operator ==(Object other) =>
      other is BotRegistrationExpired && attemptId == other.attemptId;

  @override
  int get hashCode => Object.hash(0x6227, attemptId);
}

final class BotRegistrationCancelled extends BotRegistrationStatus {
  const BotRegistrationCancelled({required this.attemptId});

  @override
  final String attemptId;

  @override
  bool operator ==(Object other) =>
      other is BotRegistrationCancelled && attemptId == other.attemptId;

  @override
  int get hashCode => Object.hash(0x6228, attemptId);
}

final class BotRegistrationFailed extends BotRegistrationStatus {
  const BotRegistrationFailed({
    required this.attemptId,
    required this.code,
    required this.message,
    required this.retryable,
  });

  @override
  final String attemptId;
  final String code;
  final String message;
  final bool retryable;

  @override
  bool operator ==(Object other) =>
      other is BotRegistrationFailed &&
      attemptId == other.attemptId &&
      code == other.code &&
      message == other.message &&
      retryable == other.retryable;

  @override
  int get hashCode => Object.hash(0x6229, attemptId, code, message, retryable);
}

class BotPairingRequest {
  const BotPairingRequest({
    required this.requestId,
    required this.botId,
    required this.openId,
    this.displayName,
    required this.createdAt,
  });

  final String requestId;
  final String botId;
  final String openId;
  final String? displayName;
  final int createdAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BotPairingRequest &&
          requestId == other.requestId &&
          botId == other.botId &&
          openId == other.openId &&
          displayName == other.displayName &&
          createdAt == other.createdAt;

  @override
  int get hashCode =>
      Object.hash(requestId, botId, openId, displayName, createdAt);
}

class BotDiagnostic {
  const BotDiagnostic({
    required this.code,
    required this.message,
    required this.retryable,
    this.platformCode,
    this.guidance,
  });

  final String code;
  final String message;
  final bool retryable;
  final String? platformCode;
  final String? guidance;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BotDiagnostic &&
          code == other.code &&
          message == other.message &&
          retryable == other.retryable &&
          platformCode == other.platformCode &&
          guidance == other.guidance;

  @override
  int get hashCode =>
      Object.hash(code, message, retryable, platformCode, guidance);

  @override
  String toString() =>
      'BotDiagnostic(code: $code, retryable: $retryable, platformCode: $platformCode)';
}

class BotSnapshot {
  const BotSnapshot({
    required this.id,
    required this.name,
    required this.projectId,
    required this.appId,
    required this.platform,
    required this.enabled,
    required this.toolsEnabled,
    required this.configRevision,
    required this.trustedOpenIds,
    required this.trustedChatIds,
    required this.connection,
    required this.credential,
    this.credentialOperation = const BotCredentialOperationIdle(),
    required this.pairing,
    this.diagnostic,
    required this.canChangeProject,
    required this.canChangeAppId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String projectId;
  final String appId;
  final BotPlatform platform;
  final bool enabled;
  final bool toolsEnabled;
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BotSnapshot &&
          id == other.id &&
          name == other.name &&
          projectId == other.projectId &&
          appId == other.appId &&
          platform == other.platform &&
          enabled == other.enabled &&
          toolsEnabled == other.toolsEnabled &&
          configRevision == other.configRevision &&
          listEquals(trustedOpenIds, other.trustedOpenIds) &&
          listEquals(trustedChatIds, other.trustedChatIds) &&
          connection == other.connection &&
          credential == other.credential &&
          credentialOperation == other.credentialOperation &&
          listEquals(pairing, other.pairing) &&
          diagnostic == other.diagnostic &&
          canChangeProject == other.canChangeProject &&
          canChangeAppId == other.canChangeAppId &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    projectId,
    appId,
    platform,
    enabled,
    toolsEnabled,
    configRevision,
    Object.hashAll(trustedOpenIds),
    Object.hashAll(trustedChatIds),
    connection,
    credential,
    credentialOperation,
    Object.hashAll(pairing),
    diagnostic,
    canChangeProject,
    canChangeAppId,
    createdAt,
    updatedAt,
  );
}

class BotPendingCredentialOperation {
  const BotPendingCredentialOperation({
    required this.botId,
    required this.credentialOperation,
    this.diagnostic,
  });

  final String botId;
  final BotCredentialOperation credentialOperation;
  final BotDiagnostic? diagnostic;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BotPendingCredentialOperation &&
          botId == other.botId &&
          credentialOperation == other.credentialOperation &&
          diagnostic == other.diagnostic;

  @override
  int get hashCode => Object.hash(botId, credentialOperation, diagnostic);
}

class BotRegistrationAttempt {
  const BotRegistrationAttempt({
    required this.attemptId,
    required this.name,
    required this.projectId,
    required this.status,
    this.completedBotId,
  });

  final String attemptId;
  final String name;
  final String projectId;
  final BotRegistrationStatus status;
  final String? completedBotId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BotRegistrationAttempt &&
          attemptId == other.attemptId &&
          name == other.name &&
          projectId == other.projectId &&
          status == other.status &&
          completedBotId == other.completedBotId;

  @override
  int get hashCode =>
      Object.hash(attemptId, name, projectId, status, completedBotId);

  @override
  String toString() =>
      'BotRegistrationAttempt(attemptId: $attemptId, name: $name, projectId: $projectId, status: $status, completedBotId: $completedBotId)';
}

class BotsStateSnapshot {
  const BotsStateSnapshot({
    required this.revision,
    required this.updatedAt,
    required this.bots,
    this.registration,
    this.pendingCredentialOperations = const [],
  });

  const BotsStateSnapshot.empty()
    : revision = 0,
      updatedAt = 0,
      bots = const [],
      registration = null,
      pendingCredentialOperations = const [];

  final int revision;
  final int updatedAt;
  final List<BotSnapshot> bots;
  final BotRegistrationAttempt? registration;
  final List<BotPendingCredentialOperation> pendingCredentialOperations;

  BotSnapshot? bot(String id) {
    for (final item in bots) {
      if (item.id == id) return item;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BotsStateSnapshot &&
          revision == other.revision &&
          updatedAt == other.updatedAt &&
          listEquals(bots, other.bots) &&
          registration == other.registration &&
          listEquals(
            pendingCredentialOperations,
            other.pendingCredentialOperations,
          );

  @override
  int get hashCode => Object.hash(
    revision,
    updatedAt,
    Object.hashAll(bots),
    registration,
    Object.hashAll(pendingCredentialOperations),
  );
}

/// App Secret 替换语义。Replace 的值只作为命令输入，不得进入快照或草稿。
sealed class BotSecretUpdate {
  const BotSecretUpdate();

  static const preserve = BotSecretPreserve();
  static const clear = BotSecretClear();
  static BotSecretReplace replace(String value) => BotSecretReplace(value);

  @override
  String toString() => switch (this) {
    BotSecretPreserve() => 'BotSecretPreserve()',
    BotSecretReplace() => 'BotSecretReplace(value: <redacted>)',
    BotSecretClear() => 'BotSecretClear()',
  };
}

final class BotSecretPreserve extends BotSecretUpdate {
  const BotSecretPreserve();

  @override
  bool operator ==(Object other) => other is BotSecretPreserve;

  @override
  int get hashCode => 0x6230;
}

final class BotSecretReplace extends BotSecretUpdate {
  const BotSecretReplace(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      other is BotSecretReplace && value == other.value;

  @override
  int get hashCode => Object.hash(0x6231, value);
}

final class BotSecretClear extends BotSecretUpdate {
  const BotSecretClear();

  @override
  bool operator ==(Object other) => other is BotSecretClear;

  @override
  int get hashCode => 0x6232;
}

class SaveBotRequest {
  const SaveBotRequest({
    required this.operationId,
    this.botId,
    required this.expectedConfigRevision,
    required this.name,
    required this.projectId,
    required this.appId,
    required this.secret,
    this.enabled = false,
    this.toolsEnabled = false,
  });

  final String operationId;
  final String? botId;
  final int expectedConfigRevision;
  final String name;
  final String projectId;
  final String appId;
  final BotSecretUpdate secret;
  final bool enabled;
  final bool toolsEnabled;

  @override
  String toString() =>
      'SaveBotRequest(operationId: $operationId, botId: $botId, expectedConfigRevision: $expectedConfigRevision, name: $name, projectId: $projectId, appId: $appId, secret: $secret, enabled: $enabled, toolsEnabled: $toolsEnabled)';
}

class StartBotRegistrationRequest {
  const StartBotRegistrationRequest({
    required this.operationId,
    required this.name,
    required this.projectId,
  });

  final String operationId;
  final String name;
  final String projectId;
}

class CancelBotRegistrationRequest {
  const CancelBotRegistrationRequest({
    required this.operationId,
    required this.attemptId,
  });

  final String operationId;
  final String attemptId;
}

class SetBotEnabledRequest {
  const SetBotEnabledRequest({
    required this.operationId,
    required this.botId,
    required this.expectedConfigRevision,
    required this.enabled,
  });

  final String operationId;
  final String botId;
  final int expectedConfigRevision;
  final bool enabled;
}

class RetryBotConnectionRequest {
  const RetryBotConnectionRequest({
    required this.operationId,
    required this.botId,
  });

  final String operationId;
  final String botId;
}

class SetBotTrustedUserRequest {
  const SetBotTrustedUserRequest({
    required this.operationId,
    required this.botId,
    required this.expectedConfigRevision,
    required this.openId,
    required this.trusted,
  });

  final String operationId;
  final String botId;
  final int expectedConfigRevision;
  final String openId;
  final bool trusted;
}

class SetBotTrustedChatRequest {
  const SetBotTrustedChatRequest({
    required this.operationId,
    required this.botId,
    required this.expectedConfigRevision,
    required this.chatId,
    required this.trusted,
  });

  final String operationId;
  final String botId;
  final int expectedConfigRevision;
  final String chatId;
  final bool trusted;
}

class BotsCommandReply {
  const BotsCommandReply({
    required this.snapshot,
    required this.receipt,
    this.stamp,
  });

  final BotsStateSnapshot snapshot;
  final StudioCommandReceipt receipt;
  final ResourceStamp? stamp;
}

enum BotConversationSource { remoteGroup, observedDirect }

enum BotConversationKind { group, direct }

enum BotConversationThreadState { creating, bound, needsAttention }

class BotConversationThreadBinding {
  const BotConversationThreadBinding({
    required this.botId,
    required this.chatId,
    required this.projectId,
    this.threadId,
    required this.revision,
    required this.state,
    this.diagnostic,
  });

  final String botId;
  final String chatId;
  final String projectId;
  final String? threadId;
  final int revision;
  final BotConversationThreadState state;
  final BotDiagnostic? diagnostic;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BotConversationThreadBinding &&
          botId == other.botId &&
          chatId == other.chatId &&
          projectId == other.projectId &&
          threadId == other.threadId &&
          revision == other.revision &&
          state == other.state &&
          diagnostic == other.diagnostic;

  @override
  int get hashCode => Object.hash(
    botId,
    chatId,
    projectId,
    threadId,
    revision,
    state,
    diagnostic,
  );
}

class BotConversation {
  const BotConversation({
    required this.chatId,
    required this.kind,
    required this.source,
    this.name,
    this.lastObservedAt,
    this.threadBinding,
  });

  final String chatId;
  final BotConversationKind kind;
  final BotConversationSource source;
  final String? name;
  final int? lastObservedAt;
  final BotConversationThreadBinding? threadBinding;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BotConversation &&
          chatId == other.chatId &&
          kind == other.kind &&
          source == other.source &&
          name == other.name &&
          lastObservedAt == other.lastObservedAt &&
          threadBinding == other.threadBinding;

  @override
  int get hashCode =>
      Object.hash(chatId, kind, source, name, lastObservedAt, threadBinding);
}

class CreateBotConversationThreadRequest {
  const CreateBotConversationThreadRequest({
    required this.operationId,
    required this.botId,
    required this.chatId,
    required this.expectedConfigRevision,
    required this.expectedBindingRevision,
  });

  final String operationId;
  final String botId;
  final String chatId;
  final int expectedConfigRevision;
  final int expectedBindingRevision;
}

class BotConversationThreadReply {
  const BotConversationThreadReply({
    required this.binding,
    required this.receipt,
  });

  final BotConversationThreadBinding binding;
  final StudioCommandReceipt receipt;
}

class ListBotConversationsRequest {
  const ListBotConversationsRequest({
    required this.botId,
    this.cursor,
    this.limit,
  });

  final String botId;
  final String? cursor;
  final int? limit;
}

class BotConversationPage {
  const BotConversationPage({
    required this.botId,
    required this.conversations,
    this.nextCursor,
  });

  final String botId;
  final List<BotConversation> conversations;
  final String? nextCursor;
}

class ReadBotMessagesRequest {
  const ReadBotMessagesRequest({
    required this.botId,
    required this.chatId,
    this.startTime,
    this.endTime,
    this.cursor,
    this.limit,
  });

  final String botId;
  final String chatId;
  final int? startTime;
  final int? endTime;
  final String? cursor;
  final int? limit;
}

sealed class BotMessageBody {
  const BotMessageBody();
}

final class BotTextMessageBody extends BotMessageBody {
  const BotTextMessageBody(this.text);

  final String text;

  @override
  bool operator ==(Object other) =>
      other is BotTextMessageBody && text == other.text;

  @override
  int get hashCode => Object.hash(0x6240, text);
}

final class BotPostMessageBody extends BotMessageBody {
  const BotPostMessageBody(this.text);

  final String text;

  @override
  bool operator ==(Object other) =>
      other is BotPostMessageBody && text == other.text;

  @override
  int get hashCode => Object.hash(0x6241, text);
}

final class BotUnsupportedMessageBody extends BotMessageBody {
  const BotUnsupportedMessageBody({
    required this.msgType,
    required this.notice,
  });

  final String msgType;
  final String notice;

  @override
  bool operator ==(Object other) =>
      other is BotUnsupportedMessageBody &&
      msgType == other.msgType &&
      notice == other.notice;

  @override
  int get hashCode => Object.hash(0x6242, msgType, notice);
}

class BotMessage {
  const BotMessage({
    required this.messageId,
    required this.chatId,
    this.senderOpenId,
    required this.createdAt,
    required this.body,
  });

  final String messageId;
  final String chatId;
  final String? senderOpenId;
  final int createdAt;
  final BotMessageBody body;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BotMessage &&
          messageId == other.messageId &&
          chatId == other.chatId &&
          senderOpenId == other.senderOpenId &&
          createdAt == other.createdAt &&
          body == other.body;

  @override
  int get hashCode =>
      Object.hash(messageId, chatId, senderOpenId, createdAt, body);
}

class BotMessagePage {
  const BotMessagePage({
    required this.botId,
    required this.chatId,
    required this.messages,
    this.nextCursor,
  });

  final String botId;
  final String chatId;
  final List<BotMessage> messages;
  final String? nextCursor;
}

enum BotSendStatus { succeeded, partial, rejected, unknown }

class SendBotMessageRequest {
  const SendBotMessageRequest({
    required this.operationId,
    required this.botId,
    required this.chatId,
    required this.text,
  });

  final String operationId;
  final String botId;
  final String chatId;
  final String text;
}

class BotSendSegment {
  const BotSendSegment({
    required this.index,
    required this.status,
    this.platformMessageId,
    this.diagnostic,
  });

  final int index;
  final BotSendStatus status;
  final String? platformMessageId;
  final BotDiagnostic? diagnostic;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BotSendSegment &&
          index == other.index &&
          status == other.status &&
          platformMessageId == other.platformMessageId &&
          diagnostic == other.diagnostic;

  @override
  int get hashCode => Object.hash(index, status, platformMessageId, diagnostic);
}

class BotSendResult {
  const BotSendResult({
    required this.operationId,
    required this.botId,
    required this.chatId,
    required this.status,
    required this.segments,
    required this.receipt,
  });

  final String operationId;
  final String botId;
  final String chatId;
  final BotSendStatus status;
  final List<BotSendSegment> segments;
  final StudioCommandReceipt receipt;
}

/// 首配非敏感草稿。Secret 不得进入此结构。
class BotSetupDraft {
  const BotSetupDraft({
    this.name = '',
    this.projectId = '',
    this.appId = '',
    this.enabled = false,
    this.toolsEnabled = false,
    this.riskAcknowledged = false,
  });

  final String name;
  final String projectId;
  final String appId;
  final bool enabled;
  final bool toolsEnabled;
  final bool riskAcknowledged;

  BotSetupDraft copyWith({
    String? name,
    String? projectId,
    String? appId,
    bool? enabled,
    bool? toolsEnabled,
    bool? riskAcknowledged,
  }) {
    return BotSetupDraft(
      name: name ?? this.name,
      projectId: projectId ?? this.projectId,
      appId: appId ?? this.appId,
      enabled: enabled ?? this.enabled,
      toolsEnabled: toolsEnabled ?? this.toolsEnabled,
      riskAcknowledged: riskAcknowledged ?? this.riskAcknowledged,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BotSetupDraft &&
          name == other.name &&
          projectId == other.projectId &&
          appId == other.appId &&
          enabled == other.enabled &&
          toolsEnabled == other.toolsEnabled &&
          riskAcknowledged == other.riskAcknowledged;

  @override
  int get hashCode => Object.hash(
    name,
    projectId,
    appId,
    enabled,
    toolsEnabled,
    riskAcknowledged,
  );
}
