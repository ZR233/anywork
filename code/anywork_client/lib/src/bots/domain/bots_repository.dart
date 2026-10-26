import '../../../operations.dart';
import '../../../resources.dart';
import 'bot_edit.dart';
import 'bot_values.dart';
import 'bot_conversation_values.dart';
import 'bot_conversation_read_scope.dart';
import 'bot_message_values.dart';
import 'bots_state.dart';

/// Sole Dart canonical writer for Bots. Observation disposal never cancels
/// accepted business work; all action inputs and versions freeze synchronously.
abstract interface class BotsRepository {
  ReadonlyLatestValue<BotsState> get state;
  Future<void> synchronize();
  Future<void> retrySync();
  Future<void> loadSourceStatus();
  OperationTicket<BotSnapshot> saveBot(BotEdit intent);
  OperationTicket<BotSnapshot> setEnabled({
    required String botId,
    required int expectedConfigRevision,
    required bool enabled,
  });
  OperationTicket<BotSnapshot> retryConnection({required String botId});
  OperationTicket<BotRegistrationAttempt> startRegistration({
    required String name,
    required String projectId,
  });
  OperationTicket<BotRegistrationAttempt> cancelRegistration({
    required String attemptId,
  });
  OperationTicket<BotSnapshot> setTrustedUser({
    required String botId,
    required int expectedConfigRevision,
    required String openId,
    required bool trusted,
  });
  OperationTicket<BotSnapshot> setTrustedChat({
    required String botId,
    required int expectedConfigRevision,
    required String chatId,
    required bool trusted,
  });
  OperationTicket<BotConversationThreadBinding> createConversationThread({
    required String botId,
    required String chatId,
    required int expectedConfigRevision,
    required int expectedBindingRevision,
  });
  BotConversationReadScope conversations(String botId);

  /// Latest selected query only. A late read still completes for its caller,
  /// but cannot replace the page/error of a newer selection.
  ReadonlyLatestValue<BotMessagesState> get messages;

  /// Identical full queries share exactly one in-flight Future, not a cache.
  Future<BotMessagePage> readMessages(
    String botId,
    String chatId, {
    int? startTime,
    int? endTime,
    String? cursor,
    int? limit,
  });
  String messageDraft(String botId, String chatId);
  void updateMessageDraft(String botId, String chatId, String text);

  /// Original typed results, including Unknown/Partial and their receipts.
  /// This bounded display mirror does not replace Rust's persistent ledger.
  ReadonlyLatestValue<BotSendsState> get sends;

  /// Freezes target/text/operation before waiting on this bot/chat's lane.
  /// Unknown/Partial settles as unknownOutcome; inspect sends for the retained
  /// native result. Observation and cleanup never replay the external write.
  OperationTicket<BotSendResult> sendMessage({
    required String botId,
    required String chatId,
    required String text,
  });
  void seal();
  Future<CloseReport> close({DateTime? deadline});
  Future<CloseReport> retryCleanup({DateTime? deadline});
}
