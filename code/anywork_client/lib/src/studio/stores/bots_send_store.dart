import '../../../models.dart';
import '../../../anywork_client.dart' show ReadModel;

/// 发送结果按 operation 身份保留。未知/部分结果不得被 Widget 重建自动覆盖。
class BotsSendStore extends ReadModel<BotsSendState> {
  BotsSendStore() : super(const BotsSendState());

  void record(BotSendResult result) {
    final next = Map<String, BotSendResult>.from(state.byOperationId);
    next[result.operationId] = result;
    // This is a bounded display mirror, not the durable Rust operation ledger.
    while (next.length > 256) {
      next.remove(next.keys.first);
    }
    state = BotsSendState(byOperationId: Map.unmodifiable(next));
  }

  BotSendResult? latestFor(String botId, String chatId) {
    return state.latestFor(botId, chatId);
  }
}

class BotsSendState {
  const BotsSendState({this.byOperationId = const {}});

  final Map<String, BotSendResult> byOperationId;

  BotSendResult? latestFor(String botId, String chatId) {
    BotSendResult? latest;
    for (final result in byOperationId.values) {
      if (result.botId != botId || result.chatId != chatId) continue;
      latest = result;
    }
    return latest;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BotsSendState && identical(byOperationId, other.byOperationId);

  @override
  int get hashCode => identityHashCode(byOperationId);
}
