import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../operations.dart';
import '../../../resources.dart';
import 'bot_values.dart';

part 'bot_message_values.freezed.dart';

/// All query parameters, including an opaque cursor and the native page size,
/// identify one read. Times are Unix seconds, not platform milliseconds.
@Freezed(toStringOverride: false)
final class BotMessageQuery with _$BotMessageQuery {
  const BotMessageQuery({
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

@Freezed(toStringOverride: false)
sealed class BotMessageBody with _$BotMessageBody {
  const factory BotMessageBody.text(String text) = BotTextMessageBody;
  const factory BotMessageBody.post(String text) = BotPostMessageBody;
  const factory BotMessageBody.unsupported({
    required String msgType,
    required String notice,
  }) = BotUnsupportedMessageBody;
}

@Freezed(toStringOverride: false)
final class BotMessage with _$BotMessage {
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
}

/// Native order and continuation are preserved; no local sorting or cursor
/// reconstruction is performed.
@Freezed(toStringOverride: false)
final class BotMessagePage with _$BotMessagePage {
  BotMessagePage({
    required this.botId,
    required this.chatId,
    required List<BotMessage> messages,
    this.nextCursor,
  }) : messages = List.unmodifiable(messages);

  final String botId;
  final String chatId;
  final List<BotMessage> messages;
  final String? nextCursor;
}

enum BotSendStatus { succeeded, partial, rejected, unknown }

@Freezed(toStringOverride: false)
final class BotSendSegment with _$BotSendSegment {
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
}

/// A send result is evidence for its original operation, not permission to
/// replay a partial or unknown external write.
@Freezed(toStringOverride: false)
final class BotSendResult with _$BotSendResult {
  BotSendResult({
    required this.operationId,
    required this.botId,
    required this.chatId,
    required this.status,
    required List<BotSendSegment> segments,
    required this.receipt,
  }) : segments = List.unmodifiable(segments);

  final OperationId operationId;
  final String botId;
  final String chatId;
  final BotSendStatus status;
  final List<BotSendSegment> segments;
  final CommitReceipt receipt;
}

@Freezed(toStringOverride: false)
final class BotMessagesState with _$BotMessagesState {
  const BotMessagesState({
    this.query,
    this.messagePage,
    this.loading = false,
    this.error,
    this.closed = false,
  });

  final BotMessageQuery? query;
  final BotMessagePage? messagePage;
  final bool loading;
  final StudioFailure? error;
  final bool closed;
}

/// Bounded display evidence only. Rust owns the persistent send ledger.
@Freezed(toStringOverride: false)
final class BotSendsState with _$BotSendsState {
  BotSendsState({required Map<OperationId, BotSendResult> byOperationId})
    : byOperationId = Map.unmodifiable(byOperationId);

  final Map<OperationId, BotSendResult> byOperationId;

  BotSendResult? latestFor(String botId, String chatId) {
    BotSendResult? latest;
    for (final result in byOperationId.values) {
      if (result.botId == botId && result.chatId == chatId) latest = result;
    }
    return latest;
  }
}
