import '../../../resources.dart';
import 'bot_conversation_values.dart';
import 'bots_state.dart';

/// A borrowed, bot-bound read. Closing this scope never disables a bot, closes
/// its Repository, or cancels a previously dispatched mutation.
abstract interface class BotConversationReadScope {
  String get botId;
  ReadonlyLatestValue<BotConversationsState> get state;
  Future<BotConversationPage> page({String? cursor, int? limit});
  void requestClose();
  Future<CloseReport> close({DateTime? deadline});
  Future<CloseReport> retryCleanup({DateTime? deadline});
}
