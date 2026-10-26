import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';

part 'bot_message_requests.freezed.dart';

/// Strings and the operation identity freeze before any lane wait.
@Freezed(toStringOverride: false)
final class SendBotMessageRequest with _$SendBotMessageRequest {
  const SendBotMessageRequest({
    required this.operationId,
    required this.botId,
    required this.chatId,
    required this.text,
  });

  final OperationId operationId;
  final String botId;
  final String chatId;
  final String text;
}
