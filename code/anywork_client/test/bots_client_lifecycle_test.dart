import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

final class _BotsTransport implements StudioTransport {
  BotsStateSnapshot snapshot = const BotsStateSnapshot.empty();
  final conversationCalls = <ListBotConversationsRequest>[];
  final messageCalls = <ReadBotMessagesRequest>[];
  final sendCalls = <SendBotMessageRequest>[];
  Completer<BotConversationPage>? conversationsGate;
  Completer<BotMessagePage>? messagesGate;
  Completer<BotSendResult>? sendGate;
  BotSendStatus sendStatus = BotSendStatus.succeeded;

  @override
  Stream<ProductTopicFrame> subscribeProductTopic(ProductTopic topic) {
    return const Stream.empty();
  }

  @override
  Future<BotsStateSnapshot> readBots() async => snapshot;

  @override
  Future<BotsCommandReply> saveBot(SaveBotRequest request) async {
    snapshot = BotsStateSnapshot(
      revision: snapshot.revision + 1,
      updatedAt: 1,
      bots: [
        BotSnapshot(
          id: request.botId ?? 'bot-1',
          name: request.name,
          projectId: request.projectId,
          appId: request.appId,
          platform: BotPlatform.feishuChina,
          enabled: request.enabled,
          toolsEnabled: request.toolsEnabled,
          configRevision: request.expectedConfigRevision + 1,
          trustedOpenIds: const [],
          trustedChatIds: const [],
          connection: const BotConnectionDisabled(),
          credential: request.secret is BotSecretReplace
              ? BotCredentialAvailability.stored
              : BotCredentialAvailability.missing,
          pairing: const [],
          canChangeProject: true,
          canChangeAppId: true,
          createdAt: 0,
          updatedAt: 1,
        ),
      ],
    );
    return _reply(request.operationId);
  }

  @override
  Future<BotsCommandReply> startBotRegistration(
    StartBotRegistrationRequest request,
  ) async {
    snapshot = BotsStateSnapshot(
      revision: snapshot.revision + 1,
      updatedAt: 1,
      bots: snapshot.bots,
      registration: BotRegistrationAttempt(
        attemptId: 'attempt-1',
        name: request.name,
        projectId: request.projectId,
        status: const BotRegistrationWaiting(
          attemptId: 'attempt-1',
          verificationUrl: 'https://accounts.feishu.cn/wait',
          expiresAt: 9,
          intervalSeconds: 5,
        ),
      ),
    );
    return _reply(request.operationId);
  }

  @override
  Future<BotsCommandReply> cancelBotRegistration(
    CancelBotRegistrationRequest request,
  ) async {
    snapshot = BotsStateSnapshot(
      revision: snapshot.revision + 1,
      updatedAt: 2,
      bots: snapshot.bots,
      registration: BotRegistrationAttempt(
        attemptId: request.attemptId,
        name: snapshot.registration?.name ?? '',
        projectId: snapshot.registration?.projectId ?? '',
        status: BotRegistrationCancelled(attemptId: request.attemptId),
      ),
    );
    return _reply(request.operationId);
  }

  @override
  Future<BotsCommandReply> setBotEnabled(SetBotEnabledRequest request) async {
    final bot = snapshot.bot(request.botId)!;
    if (bot.configRevision != request.expectedConfigRevision) {
      throw const StudioFailure(
        code: StudioFailureCode.staleRevision,
        message: 'stale',
        retryable: true,
        correlationId: 'stale',
      );
    }
    snapshot = BotsStateSnapshot(
      revision: snapshot.revision + 1,
      updatedAt: 3,
      bots: [
        BotSnapshot(
          id: bot.id,
          name: bot.name,
          projectId: bot.projectId,
          appId: bot.appId,
          platform: bot.platform,
          enabled: request.enabled,
          toolsEnabled: bot.toolsEnabled,
          configRevision: bot.configRevision + 1,
          trustedOpenIds: bot.trustedOpenIds,
          trustedChatIds: bot.trustedChatIds,
          connection: request.enabled
              ? const BotConnectionConnected()
              : const BotConnectionDisabled(),
          credential: bot.credential,
          pairing: bot.pairing,
          canChangeProject: bot.canChangeProject,
          canChangeAppId: bot.canChangeAppId,
          createdAt: bot.createdAt,
          updatedAt: bot.updatedAt + 1,
        ),
      ],
      registration: snapshot.registration,
    );
    return _reply(request.operationId);
  }

  @override
  Future<BotsCommandReply> retryBotConnection(
    RetryBotConnectionRequest request,
  ) async {
    return _reply(request.operationId);
  }

  @override
  Future<BotsCommandReply> setBotTrustedUser(
    SetBotTrustedUserRequest request,
  ) async {
    return _reply(request.operationId);
  }

  @override
  Future<BotsCommandReply> setBotTrustedChat(
    SetBotTrustedChatRequest request,
  ) async {
    return _reply(request.operationId);
  }

  @override
  Future<BotConversationPage> listBotConversations(
    ListBotConversationsRequest request,
  ) async {
    conversationCalls.add(request);
    if (conversationsGate != null) return conversationsGate!.future;
    return BotConversationPage(
      botId: request.botId,
      conversations: [
        BotConversation(
          chatId: 'chat-${request.botId}',
          kind: BotConversationKind.direct,
          source: BotConversationSource.observedDirect,
        ),
      ],
    );
  }

  @override
  Future<BotMessagePage> readBotMessages(ReadBotMessagesRequest request) async {
    messageCalls.add(request);
    if (messagesGate != null) return messagesGate!.future;
    return BotMessagePage(
      botId: request.botId,
      chatId: request.chatId,
      messages: [
        BotMessage(
          messageId: 'm1',
          chatId: request.chatId,
          createdAt: 1,
          body: const BotTextMessageBody('hello'),
        ),
      ],
    );
  }

  @override
  Future<BotSendResult> sendBotMessage(SendBotMessageRequest request) async {
    sendCalls.add(request);
    final result = BotSendResult(
      operationId: request.operationId,
      botId: request.botId,
      chatId: request.chatId,
      status: sendStatus,
      segments: [BotSendSegment(index: 0, status: sendStatus)],
      receipt: StudioCommandReceipt(
        operationId: OperationId(request.operationId),
        disposition: CommitDisposition.applied,
        targets: const [],
        effect: EffectPoint.immediate,
        effective: true,
        durable: false,
      ),
    );
    if (sendGate != null) return sendGate!.future;
    return result;
  }

  @override
  Future<BotConversationThreadReply> createBotConversationThread(
    CreateBotConversationThreadRequest request,
  ) async {
    return BotConversationThreadReply(
      binding: BotConversationThreadBinding(
        botId: request.botId,
        chatId: request.chatId,
        projectId: 'project',
        threadId: 'thread-1',
        revision: request.expectedBindingRevision + 1,
        state: BotConversationThreadState.bound,
      ),
      receipt: StudioCommandReceipt(
        operationId: OperationId(request.operationId),
        disposition: CommitDisposition.applied,
        targets: const [],
        effect: EffectPoint.immediate,
        effective: true,
        durable: false,
      ),
    );
  }

  BotsCommandReply _reply(String operationId) {
    return BotsCommandReply(
      snapshot: snapshot,
      receipt: StudioCommandReceipt(
        operationId: OperationId(operationId),
        disposition: CommitDisposition.applied,
        targets: [
          ResourceStamp(
            resourceKey: 'bots',
            ownerEpoch: 'epoch',
            revision: snapshot.revision,
          ),
        ],
        effect: EffectPoint.immediate,
        effective: true,
        durable: false,
      ),
      stamp: ResourceStamp(
        resourceKey: 'bots',
        ownerEpoch: 'epoch',
        revision: snapshot.revision,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unused transport: ${invocation.memberName}');
}

void main() {
  test(
    'canonical bots snapshot rejects older revisions and late owner frames',
    () {
      final store = BotsStore();
      store.apply(const BotsStateSnapshot(revision: 2, updatedAt: 2, bots: []));
      store.apply(const BotsStateSnapshot(revision: 1, updatedAt: 9, bots: []));
      expect(store.state.revision, 2);
      store.apply(const BotsStateSnapshot(revision: 2, updatedAt: 3, bots: []));
      expect(store.state.revision, 2);
    },
  );

  test('registration debug text redacts verification URLs', () {
    const status = BotRegistrationWaiting(
      attemptId: 'attempt-1',
      verificationUrl: 'https://accounts.feishu.cn/secret-ticket',
      expiresAt: 1,
      intervalSeconds: 5,
    );
    expect(status.toString(), isNot(contains('secret-ticket')));
    expect(status.toString(), contains('<redacted>'));
  });

  test('secret never enters setup draft and is released after save', () async {
    final transport = _BotsTransport();
    final client = AnyworkClient(transport: transport, clientId: 'bots');
    addTearDown(() => client.close());
    client.botsCommands.updateSetupDraft(
      const BotSetupDraft(name: 'Feishu', projectId: 'p1', appId: 'cli_1'),
    );
    client.botsCommands.holdSecret('app-secret-value');
    expect(
      client.botsCommands.setupDraft.toString(),
      isNot(contains('app-secret')),
    );
    await client.botsCommands.saveBot(
      expectedConfigRevision: 0,
      name: 'Feishu',
      projectId: 'p1',
      appId: 'cli_1',
      secret: client.botsCommands.consumeSecretUpdate(clear: false),
    );
    expect(
      client.bots.state.value?.bots.single.credential,
      BotCredentialAvailability.stored,
    );
    expect(client.botsCommands.setupDraft.appId, 'cli_1');
    final again = client.botsCommands.consumeSecretUpdate(clear: false);
    expect(again, isA<BotSecretPreserve>());
  });

  test('conversation and message queries drop stale results after selection change', () async {
    final transport = _BotsTransport();
    final client = AnyworkClient(transport: transport, clientId: 'bots-query');
    addTearDown(() => client.close());
    transport.conversationsGate = Completer();
    final first = client.botsQueries.listConversations('bot-a');
    await Future<void>.delayed(Duration.zero);
    expect(client.botsQueries.state.conversationsLoading, isTrue);
    final oldGate = transport.conversationsGate!;
    transport.conversationsGate = null;
    final second = client.botsQueries.listConversations('bot-b');
    await second;
    oldGate.complete(
      const BotConversationPage(
        botId: 'bot-a',
        conversations: [
          BotConversation(
            chatId: 'stale',
            kind: BotConversationKind.direct,
            source: BotConversationSource.observedDirect,
          ),
        ],
      ),
    );
    await first;
    expect(client.botsQueries.state.selectedConversationBotId, 'bot-b');
    expect(client.botsQueries.state.conversationPage?.botId, 'bot-b');
    expect(
      client.botsQueries.state.conversationPage?.conversations.single.chatId,
      isNot('stale'),
    );
    final messagesGate = Completer<BotMessagePage>();
    transport.messagesGate = messagesGate;
    final oldMessages = client.botsQueries.readMessages(
      'bot-b',
      'chat-old',
      limit: 10,
    );
    final coalesced = client.botsQueries.readMessages(
      'bot-b',
      'chat-old',
      limit: 10,
    );
    expect(identical(oldMessages, coalesced), isTrue);
    transport.messagesGate = null;
    await client.botsQueries.readMessages('bot-b', 'chat-old', limit: 20);
    await client.botsQueries.readMessages('bot-b', 'chat-new', limit: 20);
    messagesGate.complete(
      const BotMessagePage(botId: 'bot-b', chatId: 'chat-old', messages: []),
    );
    await oldMessages;
    expect(client.botsQueries.state.messagePage?.chatId, 'chat-new');
    expect(transport.messageCalls.map((call) => call.limit), [10, 20, 20]);
  });

  test('send freezes target before await and unknown results are retained without replay', () async {
    final transport = _BotsTransport();
    final client = AnyworkClient(transport: transport, clientId: 'bots-send');
    addTearDown(() => client.close());
    transport.sendStatus = BotSendStatus.unknown;
    transport.sendGate = Completer();
    client.botsCommands.updateMessageDraft('bot-1', 'chat-1', 'first');
    client.botsCommands.updateMessageDraft('bot-2', 'chat-2', 'other chat');
    final pending = client.botsCommands.sendMessage(
      botId: 'bot-1',
      chatId: 'chat-1',
      text: client.botsCommands.messageDraft('bot-1', 'chat-1'),
    );
    client.botsCommands.updateMessageDraft(
      'bot-1',
      'chat-1',
      'edited after submit',
    );
    await Future<void>.delayed(Duration.zero);
    expect(transport.sendCalls, hasLength(1));
    expect(transport.sendCalls.single.botId, 'bot-1');
    expect(transport.sendCalls.single.chatId, 'chat-1');
    expect(transport.sendCalls.single.text, 'first');
    expect(
      client.botsCommands.messageDraft('bot-1', 'chat-1'),
      'edited after submit',
    );
    expect(client.botsCommands.messageDraft('bot-2', 'chat-2'), 'other chat');
    transport.sendGate!.complete(
      BotSendResult(
        operationId: client.mutations
            .latest('bots:send:bot-1:chat-1')!
            .id
            .value,
        botId: 'bot-1',
        chatId: 'chat-1',
        status: BotSendStatus.unknown,
        segments: const [
          BotSendSegment(index: 0, status: BotSendStatus.unknown),
        ],
        receipt: StudioCommandReceipt(
          operationId: client.mutations.latest('bots:send:bot-1:chat-1')!.id,
          disposition: CommitDisposition.applied,
          targets: const [],
          effect: EffectPoint.immediate,
          effective: true,
          durable: false,
        ),
      ),
    );
    final result = await pending;
    expect(result.status, BotSendStatus.unknown);
    expect(
      client.botsSends.latestFor('bot-1', 'chat-1')?.status,
      BotSendStatus.unknown,
    );
    expect(transport.sendCalls, hasLength(1));
    expect(transport.sendCalls.single.text, 'first');
  });

  test('client close joins bot commands and queries', () async {
    final transport = _BotsTransport();
    final client = AnyworkClient(transport: transport, clientId: 'bots-close');
    transport.conversationsGate = Completer();
    unawaited(client.botsQueries.listConversations('bot-1'));
    final closed = client.close();
    transport.conversationsGate!.complete(
      const BotConversationPage(botId: 'bot-1', conversations: []),
    );
    final report = await closed;
    expect(report.complete, isTrue);
  });

  test(
    'replaced queries retain real ownership and budget through close',
    () async {
      final transport = _BotsTransport();
      final client = AnyworkClient(
        transport: transport,
        clientId: 'bots-retired',
      );
      final gate = Completer<BotConversationPage>();
      transport.conversationsGate = gate;
      try {
        final first = client.botsQueries.listConversations('bot-a');
        transport.conversationsGate = null;
        await client.botsQueries.listConversations('bot-b');
        await first; // Display cancellation is not transport completion.
        expect(client.budget.used(ResourceKind.pendingOperation), 1);
        final report = await client.close(deadline: DateTime.now());
        expect(report.complete, isFalse);
        expect(client.budget.used(ResourceKind.pendingOperation), 1);
        var queryOwnerClosed = false;
        final queryOwnerClose = client.botsQueries.close().then((_) {
          queryOwnerClosed = true;
        });
        await Future<void>.delayed(Duration.zero);
        expect(queryOwnerClosed, isFalse);
        gate.complete(
          const BotConversationPage(botId: 'bot-a', conversations: []),
        );
        await queryOwnerClose;
        expect(client.budget.used(ResourceKind.pendingOperation), 0);
        expect(client.botsQueries.state.conversationPage?.botId, 'bot-b');
      } finally {
        if (!gate.isCompleted) {
          gate.complete(
            const BotConversationPage(botId: 'bot-a', conversations: []),
          );
        }
        await client.close();
      }
    },
  );

  test(
    'foreign conversation responses fail without publishing another bot',
    () async {
      final transport = _BotsTransport();
      final client = AnyworkClient(
        transport: transport,
        clientId: 'bots-foreign',
      );
      addTearDown(client.close);
      transport.conversationsGate = Completer<BotConversationPage>();
      final query = client.botsQueries.listConversations('bot-b');
      final rejected = expectLater(
        query,
        throwsA(
          isA<StudioFailure>().having(
            (failure) => failure.code,
            'code',
            StudioFailureCode.protocol,
          ),
        ),
      );
      transport.conversationsGate!.complete(
        const BotConversationPage(botId: 'bot-a', conversations: []),
      );
      await rejected;
      expect(client.botsQueries.state.conversationPage, isNull);
      expect(
        client.botsQueries.state.conversationError?.code,
        StudioFailureCode.protocol,
      );
    },
  );
}
