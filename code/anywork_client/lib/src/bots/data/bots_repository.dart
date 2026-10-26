import 'dart:async';

import '../../../operations.dart';
import '../../../operations_ports.dart' show OperationRecorder;
import '../../../resources_ports.dart';
import '../domain/bot_edit.dart';
import '../domain/bot_values.dart';
import '../domain/bot_conversation_read_scope.dart';
import '../domain/bot_conversation_values.dart';
import '../domain/bot_message_values.dart';
import '../domain/bots_repository.dart';
import '../domain/bots_state.dart';
import 'bot_conversation_scope_owner.dart';
import 'bot_message_reads.dart';
import 'bot_message_sends.dart';
import 'bots_actions.dart';
import 'bots_mirror.dart';
import 'bots_port.dart';

/// Pure assembly only. No feed or native read opens until explicit domain
/// demand after RuntimeReady. Publishers and settlement owners stay private.
BotsRepository createBotsRepository({
  required BotsPort port,
  required ResourceBudget budget,
  required OperationRecorder operations,
}) => _BotsRepository(port, budget, operations);

final class _BotsRepository implements BotsRepository {
  _BotsRepository(
    this.port,
    ResourceBudget budget,
    OperationRecorder operations,
  ) : lifetime = ResourceLifetime(budget) {
    mirror = BotsMirror(port, lifetime, operations);
    actions = BotsActions(port, mirror, lifetime, operations);
    messageReads = BotMessageReads(port, lifetime);
    messageSends = BotMessageSends(port, lifetime, operations);
  }

  final BotsPort port;
  final ResourceLifetime lifetime;
  late final BotsMirror mirror;
  late final BotsActions actions;
  late final BotMessageReads messageReads;
  late final BotMessageSends messageSends;
  bool _sourcesClosed = false;

  @override
  ReadonlyLatestValue<BotsState> get state => mirror.source.readonly;
  @override
  Future<void> synchronize() => mirror.synchronize();
  @override
  Future<void> retrySync() => mirror.retrySync();
  @override
  Future<void> loadSourceStatus() => mirror.loadSourceStatus();
  @override
  OperationTicket<BotSnapshot> saveBot(BotEdit intent) =>
      actions.saveBot(intent);
  @override
  OperationTicket<BotSnapshot> setEnabled({
    required String botId,
    required int expectedConfigRevision,
    required bool enabled,
  }) => actions.setEnabled(
    botId: botId,
    expectedConfigRevision: expectedConfigRevision,
    enabled: enabled,
  );
  @override
  OperationTicket<BotSnapshot> retryConnection({required String botId}) =>
      actions.retryConnection(botId: botId);
  @override
  OperationTicket<BotRegistrationAttempt> startRegistration({
    required String name,
    required String projectId,
  }) => actions.startRegistration(name: name, projectId: projectId);
  @override
  OperationTicket<BotRegistrationAttempt> cancelRegistration({
    required String attemptId,
  }) => actions.cancelRegistration(attemptId: attemptId);
  @override
  OperationTicket<BotSnapshot> setTrustedUser({
    required String botId,
    required int expectedConfigRevision,
    required String openId,
    required bool trusted,
  }) => actions.setTrustedUser(
    botId: botId,
    expectedConfigRevision: expectedConfigRevision,
    openId: openId,
    trusted: trusted,
  );
  @override
  OperationTicket<BotSnapshot> setTrustedChat({
    required String botId,
    required int expectedConfigRevision,
    required String chatId,
    required bool trusted,
  }) => actions.setTrustedChat(
    botId: botId,
    expectedConfigRevision: expectedConfigRevision,
    chatId: chatId,
    trusted: trusted,
  );
  @override
  OperationTicket<BotConversationThreadBinding> createConversationThread({
    required String botId,
    required String chatId,
    required int expectedConfigRevision,
    required int expectedBindingRevision,
  }) => actions.createConversationThread(
    botId: botId,
    chatId: chatId,
    expectedConfigRevision: expectedConfigRevision,
    expectedBindingRevision: expectedBindingRevision,
  );

  @override
  BotConversationReadScope conversations(String botId) {
    lifetime.admit();
    final scope = BotConversationScopeOwner(port, lifetime, botId);
    lifetime.register(scope);
    try {
      scope.start();
    } catch (error, stack) {
      lifetime.lastCause = error;
      lifetime.lastStack = stack;
      scope.requestClose();
      unawaited(scope.cleanup(retry: false));
      Error.throwWithStackTrace(resourceFailure(error), stack);
    }
    return scope;
  }

  @override
  ReadonlyLatestValue<BotMessagesState> get messages =>
      messageReads.source.readonly;
  @override
  Future<BotMessagePage> readMessages(
    String botId,
    String chatId, {
    int? startTime,
    int? endTime,
    String? cursor,
    int? limit,
  }) => messageReads.read(
    BotMessageQuery(
      botId: botId,
      chatId: chatId,
      startTime: startTime,
      endTime: endTime,
      cursor: cursor,
      limit: limit,
    ),
  );
  @override
  String messageDraft(String botId, String chatId) =>
      messageSends.messageDraft(botId, chatId);
  @override
  void updateMessageDraft(String botId, String chatId, String text) =>
      messageSends.updateMessageDraft(botId, chatId, text);
  @override
  ReadonlyLatestValue<BotSendsState> get sends => messageSends.source.readonly;
  @override
  OperationTicket<BotSendResult> sendMessage({
    required String botId,
    required String chatId,
    required String text,
  }) => messageSends.send(botId: botId, chatId: chatId, text: text);

  @override
  void seal() => lifetime.seal();
  @override
  Future<CloseReport> close({DateTime? deadline}) => _close(deadline, false);
  @override
  Future<CloseReport> retryCleanup({DateTime? deadline}) =>
      _close(deadline, true);

  Future<CloseReport> _close(DateTime? deadline, bool retry) async {
    final report = await lifetime.close(deadline: deadline, retry: retry);
    if (report.complete && !_sourcesClosed) {
      _sourcesClosed = true;
      final current = mirror.source.value;
      mirror.source.publish(
        current.copyWith(
          projection: current.projection.copyWith(
            sync: const ResourceSyncState(
              phase: ResourceSyncPhase.closed,
              error: null,
              retryExhausted: false,
            ),
          ),
        ),
      );
      mirror.source.close();
      messageReads.closeSource();
      messageSends.closeSource();
    }
    return report;
  }
}
