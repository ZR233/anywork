import 'package:anywork_client/bots_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources.dart';

import '../../../../rust/api/studio/types/bots.dart' as native;
import '../../shared/adapter_failure.dart';
import '../../shared/exact_numbers.dart';
import '../../shared/receipt_converters.dart';
import 'bot_values.dart';
import 'command_results.dart';

BotMessagePage botMessagePageFromBridge(
  native.BridgeBotMessagePage value,
  BotMessageQuery query,
) {
  if (value.botId != query.botId ||
      value.chatId != query.chatId ||
      query.cursor != null && value.nextCursor == query.cursor ||
      value.messages.any((message) => message.chatId != query.chatId)) {
    throw adapterProtocol('bots-message-query-target');
  }
  return BotMessagePage(
    botId: value.botId,
    chatId: value.chatId,
    messages: [
      for (final message in value.messages)
        BotMessage(
          messageId: message.messageId,
          chatId: message.chatId,
          senderOpenId: message.senderOpenId,
          createdAt: exactI64(
            BigInt.from(message.createdAt),
            'bot message created Unix seconds',
          ),
          body: switch (message.body) {
            native.BridgeBotMessageBody_Text(:final text) =>
              BotMessageBody.text(text),
            native.BridgeBotMessageBody_Post(:final text) =>
              BotMessageBody.post(text),
            native.BridgeBotMessageBody_Unsupported(
              :final msgType,
              :final notice,
            ) =>
              BotMessageBody.unsupported(msgType: msgType, notice: notice),
          },
        ),
    ],
    nextCursor: value.nextCursor,
  );
}

BotSendStatus _sendStatus(native.BridgeBotSendStatus value) => switch (value) {
  native.BridgeBotSendStatus.succeeded => BotSendStatus.succeeded,
  native.BridgeBotSendStatus.partial => BotSendStatus.partial,
  native.BridgeBotSendStatus.rejected => BotSendStatus.rejected,
  native.BridgeBotSendStatus.unknown => BotSendStatus.unknown,
};

// Like Thread commands, retain the original typed successful DTO if conversion
// fails. The evidence belongs to the failure, not a second command/retry path.
final _unusableSendReplies = Expando<_UnusableSendReply>(
  'native-bot-send-evidence',
);

BotSendResult botSendResultFromBridge(
  native.BridgeBotSendResult value,
  SendBotMessageRequest request,
) {
  CommitReceipt? receipt;
  try {
    receipt = commitReceiptFromBridge(value.receipt);
    if (receipt.operationId != request.operationId) {
      throw adapterProtocol('bots-send-receipt-operation');
    }
    if (receipt.targets.length != 1 ||
        receipt.requiresIdentityObservation ||
        receipt.targets.single is! ResourceStamp) {
      throw adapterProtocol('bots-send-receipt');
    }
    final target = receipt.targets.single as ResourceStamp;
    if (target.resourceKey != 'bot:${request.botId}' ||
        target.ownerEpoch.isEmpty) {
      throw adapterProtocol('bots-send-receipt-target');
    }
    if (value.operationId != request.operationId.value ||
        value.botId != request.botId ||
        value.chatId != request.chatId) {
      throw adapterProtocol('bots-send-target');
    }
    return BotSendResult(
      operationId: OperationId(value.operationId),
      botId: value.botId,
      chatId: value.chatId,
      status: _sendStatus(value.status),
      segments: [
        for (final segment in value.segments)
          BotSendSegment(
            index: _segmentIndex(segment.index),
            status: _sendStatus(segment.status),
            platformMessageId: segment.platformMessageId,
            diagnostic: segment.diagnostic == null
                ? null
                : botDiagnosticFromBridge(segment.diagnostic!),
          ),
      ],
      receipt: receipt,
    );
  } on Object catch (error, stack) {
    final failure = botsCallFailure(error);
    _unusableSendReplies[failure] = _UnusableSendReply(value, error, stack);
    Error.throwWithStackTrace(
      receipt != null && receipt.operationId == request.operationId
          ? CommandDispatchFailure.committedButUnobserved(
              receipt: receipt,
              failure: failure,
            )
          : CommandDispatchFailure.confirmedWithoutUsableReceipt(
              failure: failure,
            ),
      stack,
    );
  }
}

int _segmentIndex(int value) {
  if (value < 0 || value > 0xffffffff) {
    throw adapterProtocol('bots-send-segment-index');
  }
  return exactU64(BigInt.from(value), 'bot send segment index');
}

final class _UnusableSendReply {
  _UnusableSendReply(this.reply, this.cause, this.stack);
  final native.BridgeBotSendResult reply;
  final Object cause;
  final StackTrace stack;
}
