import 'package:anywork_client/bots_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../../../../rust/api/studio/handlers/bots.dart' as native;
import '../../shared/adapter_failure.dart';
import '../../shared/bridge_failure.dart';
import 'bots_feed.dart';
import 'command_inputs.dart';
import 'command_results.dart';
import 'conversations_connection.dart';
import 'message_values.dart';
import 'source_status_connection.dart';

/// Production transport leaf. Construction and open methods start no registration, credential
/// resolution or connection task. Repository assembly remains the App composition root's job.
BotsPort createBotsPort() => const FrbBotsPort();

final class FrbBotsPort implements BotsPort {
  const FrbBotsPort();

  @override
  Future<FeedConnection<BotsFrame>> openBots() async {
    final connection = FrbBotsConnection();
    await connection.opened;
    return connection;
  }

  @override
  Future<ProductSourceStatusReadConnection> openSourceStatus(
    ProductSourceStatusRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final connection = FrbBotsSourceStatusConnection(reference, origin);
    await connection.opened;
    return connection;
  }

  @override
  Future<BotConversationReadConnection> openConversations(String botId) async {
    final connection = FrbBotConversationsConnection(botId);
    await connection.opened;
    return connection;
  }

  @override
  Future<BotMessagePage> readMessages(BotMessageQuery query) =>
      bridgeQuery(() async {
        final input = readBotMessagesToBridge(query);
        return botMessagePageFromBridge(
          await native.readBotMessages(request: input),
          query,
        );
      });

  @override
  Future<BotSendResult> sendMessage(SendBotMessageRequest request) async {
    final input = prepareBotsCommand(() => sendBotMessageToBridge(request));
    return invokeBotsCommand(
      () => native.sendBotMessage(request: input),
      (value) => botSendResultFromBridge(value, request),
    );
  }

  @override
  Future<BotsCommandReply> saveBot(SaveBotRequest request) async {
    final input = prepareBotsCommand(() => saveBotToBridge(request));
    return invokeBotsCommand(
      () => native.saveBot(request: input),
      (value) => botsReplyFromBridge(value, request.operationId, (reply) {
        requireBotResult(
          reply,
          request.botId,
          expectedRevision: request.expectedConfigRevision,
        );
        final bot = reply.bot!;
        if (bot.appId != request.appId ||
            request.projectId.isNotEmpty &&
                bot.projectId != request.projectId) {
          throw adapterProtocol('bots-save-target');
        }
      }),
    );
  }

  @override
  Future<BotsCommandReply> setBotEnabled(SetBotEnabledRequest request) async {
    final input = prepareBotsCommand(() => setBotEnabledToBridge(request));
    return invokeBotsCommand(
      () => native.setBotEnabled(request: input),
      (value) => botsReplyFromBridge(value, request.operationId, (reply) {
        requireBotResult(
          reply,
          request.botId,
          expectedRevision: request.expectedConfigRevision,
        );
        if (reply.bot!.enabled != request.enabled) {
          throw adapterProtocol('bots-enable-target');
        }
      }),
    );
  }

  @override
  Future<BotsCommandReply> retryBotConnection(
    RetryBotConnectionRequest request,
  ) async {
    final input = prepareBotsCommand(() => retryBotConnectionToBridge(request));
    return invokeBotsCommand(
      () => native.retryBotConnection(request: input),
      (value) => botsReplyFromBridge(
        value,
        request.operationId,
        (reply) => requireBotResult(reply, request.botId),
      ),
    );
  }

  @override
  Future<BotsCommandReply> startBotRegistration(
    StartBotRegistrationRequest request,
  ) async {
    final input = prepareBotsCommand(
      () => startBotRegistrationToBridge(request),
    );
    return invokeBotsCommand(
      () => native.startBotRegistration(request: input),
      (value) => botsReplyFromBridge(
        value,
        request.operationId,
        (reply) => requireRegistrationResult(
          reply,
          name: request.name,
          projectId: request.projectId,
        ),
      ),
    );
  }

  @override
  Future<BotsCommandReply> cancelBotRegistration(
    CancelBotRegistrationRequest request,
  ) async {
    final input = prepareBotsCommand(
      () => cancelBotRegistrationToBridge(request),
    );
    return invokeBotsCommand(
      () => native.cancelBotRegistration(request: input),
      (value) => botsReplyFromBridge(
        value,
        request.operationId,
        (reply) =>
            requireRegistrationResult(reply, attemptId: request.attemptId),
      ),
    );
  }

  @override
  Future<BotsCommandReply> setBotTrustedUser(
    SetBotTrustedUserRequest request,
  ) async {
    final input = prepareBotsCommand(() => setBotTrustedUserToBridge(request));
    return invokeBotsCommand(
      () => native.setBotTrustedUser(request: input),
      (value) => botsReplyFromBridge(value, request.operationId, (reply) {
        requireBotResult(
          reply,
          request.botId,
          expectedRevision: request.expectedConfigRevision,
        );
        if (reply.bot!.trustedOpenIds.contains(request.openId) !=
            request.trusted) {
          throw adapterProtocol('bots-trusted-user-target');
        }
      }),
    );
  }

  @override
  Future<BotsCommandReply> setBotTrustedChat(
    SetBotTrustedChatRequest request,
  ) async {
    final input = prepareBotsCommand(() => setBotTrustedChatToBridge(request));
    return invokeBotsCommand(
      () => native.setBotTrustedChat(request: input),
      (value) => botsReplyFromBridge(value, request.operationId, (reply) {
        requireBotResult(
          reply,
          request.botId,
          expectedRevision: request.expectedConfigRevision,
        );
        if (reply.bot!.trustedChatIds.contains(request.chatId) !=
            request.trusted) {
          throw adapterProtocol('bots-trusted-chat-target');
        }
      }),
    );
  }

  @override
  Future<BotConversationThreadReply> createBotConversationThread(
    CreateBotConversationThreadRequest request,
  ) async {
    final input = prepareBotsCommand(() => createBotThreadToBridge(request));
    return invokeBotsCommand(
      () => native.createBotConversationThread(request: input),
      (value) => botThreadReplyFromBridge(value, request),
    );
  }
}
