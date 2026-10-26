import '../../../resources.dart';
import '../../../resources_ports.dart'
    show FeedConnection, ProductSourceStatusReadConnection;
import '../domain/bot_conversation_values.dart';
import '../domain/bot_message_values.dart';
import 'bot_message_requests.dart';
import 'bots_commands_values.dart';
import 'bots_frames.dart';

/// Composition-only native capabilities. Feeds have at most two unacknowledged
/// Data deliveries, including the baseline. No adapter synthesizes source
/// Ready, receipt stages or empty business values from transport success.
///
/// Dispatch failures use CommandDispatchFailure evidence. An ordinary
/// StudioFailure, error code or message after invoking a command never proves
/// rejection. A successful native reply that cannot be converted retains its
/// real receipt via committedButUnobserved, or confirmedWithoutUsableReceipt.
abstract interface class BotsPort {
  Future<FeedConnection<BotsFrame>> openBots();
  Future<ProductSourceStatusReadConnection> openSourceStatus(
    ProductSourceStatusRef reference, {
    required ProductReadOrigin origin,
  });
  Future<BotsCommandReply> saveBot(SaveBotRequest request);
  Future<BotsCommandReply> setBotEnabled(SetBotEnabledRequest request);
  Future<BotsCommandReply> retryBotConnection(
    RetryBotConnectionRequest request,
  );
  Future<BotsCommandReply> startBotRegistration(
    StartBotRegistrationRequest request,
  );
  Future<BotsCommandReply> cancelBotRegistration(
    CancelBotRegistrationRequest request,
  );
  Future<BotsCommandReply> setBotTrustedUser(SetBotTrustedUserRequest request);
  Future<BotsCommandReply> setBotTrustedChat(SetBotTrustedChatRequest request);
  Future<BotConversationThreadReply> createBotConversationThread(
    CreateBotConversationThreadRequest request,
  );
  Future<BotConversationReadConnection> openConversations(String botId);
  Future<BotMessagePage> readMessages(BotMessageQuery query);
  Future<BotSendResult> sendMessage(SendBotMessageRequest request);
}

/// A concrete bot-bound read owner. page forwards the original native cursor;
/// close joins opening and all admitted queries, including late results. It is
/// not a business command cancellation and never disables the bot.
abstract interface class BotConversationReadConnection {
  String get botId;
  Future<BotConversationPage> page(ListBotConversationsRequest request);
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}
