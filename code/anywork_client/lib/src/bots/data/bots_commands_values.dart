import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../operations.dart';
import '../../../resources.dart';
import '../domain/bot_edit.dart';
import '../domain/bot_values.dart';
import '../domain/bot_conversation_values.dart';

part 'bots_commands_values.freezed.dart';

@Freezed(toStringOverride: false)
abstract class SaveBotRequest with _$SaveBotRequest {
  const factory SaveBotRequest({
    required OperationId operationId,
    required String? botId,
    required int expectedConfigRevision,
    required String name,
    required String projectId,
    required String appId,
    required BotSecretUpdate secret,
    required bool enabled,
    required bool toolsEnabled,
    required BotModelRoute? modelRoute,
  }) = _SaveBotRequest;
}

@Freezed(toStringOverride: false)
abstract class StartBotRegistrationRequest with _$StartBotRegistrationRequest {
  const factory StartBotRegistrationRequest({
    required OperationId operationId,
    required String name,
    required String projectId,
  }) = _StartBotRegistrationRequest;
}

@freezed
abstract class CancelBotRegistrationRequest
    with _$CancelBotRegistrationRequest {
  const factory CancelBotRegistrationRequest({
    required OperationId operationId,
    required String attemptId,
  }) = _CancelBotRegistrationRequest;
}

@freezed
abstract class SetBotEnabledRequest with _$SetBotEnabledRequest {
  const factory SetBotEnabledRequest({
    required OperationId operationId,
    required String botId,
    required int expectedConfigRevision,
    required bool enabled,
  }) = _SetBotEnabledRequest;
}

@freezed
abstract class RetryBotConnectionRequest with _$RetryBotConnectionRequest {
  const factory RetryBotConnectionRequest({
    required OperationId operationId,
    required String botId,
  }) = _RetryBotConnectionRequest;
}

@freezed
abstract class SetBotTrustedUserRequest with _$SetBotTrustedUserRequest {
  const factory SetBotTrustedUserRequest({
    required OperationId operationId,
    required String botId,
    required int expectedConfigRevision,
    required String openId,
    required bool trusted,
  }) = _SetBotTrustedUserRequest;
}

@freezed
abstract class SetBotTrustedChatRequest with _$SetBotTrustedChatRequest {
  const factory SetBotTrustedChatRequest({
    required OperationId operationId,
    required String botId,
    required int expectedConfigRevision,
    required String chatId,
    required bool trusted,
  }) = _SetBotTrustedChatRequest;
}

/// The adapter extracts only the original action's bot/attempt from the native
/// reply. It must validate that identity before discarding the native aggregate;
/// this is not permission to read latest or echo the request as success proof.
/// Neither value is applied to the Repository's canonical feed mirror.
@Freezed(toStringOverride: false)
abstract class BotsCommandReply with _$BotsCommandReply {
  const factory BotsCommandReply({
    required CommitReceipt receipt,
    required ResourceStamp? stamp,
    required BotSnapshot? bot,
    required BotRegistrationAttempt? registration,
  }) = _BotsCommandReply;
}

@freezed
abstract class CreateBotConversationThreadRequest
    with _$CreateBotConversationThreadRequest {
  const factory CreateBotConversationThreadRequest({
    required OperationId operationId,
    required String botId,
    required String chatId,
    required int expectedConfigRevision,
    required int expectedBindingRevision,
  }) = _CreateBotConversationThreadRequest;
}

@Freezed(toStringOverride: false)
abstract class BotConversationThreadReply with _$BotConversationThreadReply {
  const factory BotConversationThreadReply({
    required BotConversationThreadBinding binding,
    required CommitReceipt receipt,
  }) = _BotConversationThreadReply;
}

@Freezed(toStringOverride: false)
abstract class ListBotConversationsRequest with _$ListBotConversationsRequest {
  const factory ListBotConversationsRequest({
    required String botId,
    required String? cursor,
    required int? limit,
  }) = _ListBotConversationsRequest;
}
