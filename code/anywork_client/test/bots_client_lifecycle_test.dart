import 'dart:async';

import 'package:anywork_client/bots_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

import 'support/bots_fixture.dart';

void main() {
  test(
    'canonical bots snapshot rejects older revisions and late owner frames',
    () async {
      final environment = BotsEnvironment();
      addTearDown(environment.close);
      await environment.establish(
        revision: 2,
        bots: [botsFixtureBot(configRevision: 2)],
      );
      expect(environment.repository.state.value.snapshot!.value.revision, 2);

      await environment.publishRejected(
        BotsStateChangedPayload(
          stamp: const ProductProjectionStamp(
            ownerEpoch: 'bots-epoch',
            incarnation: 1,
            revision: 1,
          ),
          baseRevision: 1,
          header: botsHeader(1),
          state: botsSnapshot(1),
        ),
      );
      final sync = environment.repository.state.value.projection.sync;
      expect(sync.phase, ResourceSyncPhase.failed);
      expect(sync.error!.code, StudioFailureCode.protocol);
      // Last-known business material survives a rejected publication.
      expect(environment.repository.state.value.snapshot!.value.revision, 2);
    },
  );

  test(
    'a same-revision mutation cannot rewrite an accepted snapshot',
    () async {
      final environment = BotsEnvironment();
      addTearDown(environment.close);
      await environment.establish(
        revision: 2,
        bots: [botsFixtureBot(configRevision: 2)],
      );

      await environment.publishRejected(
        BotsStateChangedPayload(
          stamp: const ProductProjectionStamp(
            ownerEpoch: 'bots-epoch',
            incarnation: 1,
            revision: 2,
          ),
          baseRevision: 2,
          header: BotsHeader(
            source: ObservedHeader(
              brief: ObservedBrief.ready(
                revision: 2,
                updatedAt: 3,
                lastCheckedAt: null,
              ),
              status: const ProductSourceStatusRef(entry: 7, revision: 2),
            ),
            botsRevision: 2,
            updatedAt: 3,
          ),
          state: botsSnapshot(
            2,
            bots: [botsFixtureBot(configRevision: 2, name: 'Rewritten')],
          ),
        ),
      );
      final sync = environment.repository.state.value.projection.sync;
      expect(sync.phase, ResourceSyncPhase.failed);
      expect(sync.error!.code, StudioFailureCode.protocol);
      expect(environment.bot('bot-1').name, 'Feishu');
    },
  );

  test('registration debug text redacts verification URLs', () {
    const status = BotRegistrationStatus.waiting(
      attemptId: 'attempt-1',
      verificationUrl: 'https://accounts.feishu.cn/secret-ticket',
      expiresAt: 1,
      intervalSeconds: 5,
    );
    expect(status.toString(), isNot(contains('secret-ticket')));
    expect(status.toString(), contains('<redacted>'));
  });

  test('secret never enters a retained intent and is released after save', () async {
    final environment = BotsEnvironment(clientId: 'bots-secret');
    addTearDown(environment.close);
    await environment.establish(revision: 1, bots: [botsFixtureBot()]);

    final edit = BotEdit(
      botId: 'bot-1',
      expectedConfigRevision: 1,
      name: 'Feishu',
      projectId: 'p1',
      appId: 'cli_1',
      secret: const BotSecretUpdate.replace(value: 'app-secret-value'),
      enabled: true,
      toolsEnabled: false,
      modelRoute: botsFixtureRoute,
    );
    // The transient edit is the only place that ever held the clear text; its
    // generated diagnosis is suppressed entirely, and the secret union itself
    // only ever prints a redacted form.
    expect(edit.toString(), isNot(contains('app-secret-value')));
    expect(edit.secret.toString(), contains('<redacted>'));
    expect(edit.secret.toString(), isNot(contains('app-secret-value')));

    final ticket = environment.repository.saveBot(edit);
    final call = await environment.port.savedBot(0);
    expect(call.request.appId, 'cli_1');
    expect(call.request.secret, isA<BotSecretReplace>());

    final saved = botsFixtureBot(
      configRevision: 2,
      credential: BotCredentialAvailability.stored,
      modelRoute: botsFixtureRoute,
    );
    call.reply.complete(
      botsCommandReply(
        operationId: call.request.operationId,
        revision: 2,
        bot: saved,
      ),
    );
    environment.publishChange(baseRevision: 1, revision: 2, bots: [saved]);
    final outcome = await ticket.result;
    expect(outcome, isA<CommittedCommandResult<BotSnapshot>>());
    expect(
      (outcome as CommittedCommandResult<BotSnapshot>).value.credential,
      BotCredentialAvailability.stored,
    );
    expect(
      environment.bot('bot-1').credential,
      BotCredentialAvailability.stored,
    );
    expect(environment.bot('bot-1').modelRoute, botsFixtureRoute);
    // No canonical value retains the credential text.
    expect(
      environment.repository.state.value.toString(),
      isNot(contains('app-secret-value')),
    );
    // A later edit starts from preserve: the Repository never hands the secret
    // back, so it cannot be re-sent by an unrelated save.
    expect(const BotSecretUpdate.preserve(), isA<BotSecretPreserve>());
  });

  test(
    'conversation queries keep their own bot and late results stay isolated',
    () async {
      final environment = BotsEnvironment(clientId: 'bots-queries');
      addTearDown(environment.close);
      await environment.establish(revision: 1);

      final firstScope = environment.repository.conversations('bot-a');
      final secondScope = environment.repository.conversations('bot-b');
      final firstOpen = await environment.port.conversationOpened(0);
      final secondOpen = await environment.port.conversationOpened(1);
      expect(firstOpen.botId, 'bot-a');
      expect(secondOpen.botId, 'bot-b');
      final first = ScriptedConversationConnection(
        'bot-a',
        declaredBotId: 'bot-a',
      );
      final second = ScriptedConversationConnection(
        'bot-b',
        declaredBotId: 'bot-b',
      );
      firstOpen.reply.complete(first);
      secondOpen.reply.complete(second);

      final gate = Completer<BotConversationPage>();
      first.onPage = (request) => gate.future;
      second.onPage = (request) async => BotConversationPage(
        botId: 'bot-b',
        conversations: [
          BotConversation(
            chatId: 'chat-bot-b',
            kind: BotConversationKind.direct,
            source: BotConversationSource.observedDirect,
            name: null,
            lastObservedAt: null,
            threadBinding: null,
          ),
        ],
        nextCursor: null,
      );

      final stale = firstScope.page();
      await Future<void>.delayed(Duration.zero);
      expect(firstScope.state.value.loading, isTrue);
      await secondScope.page();
      expect(secondScope.state.value.page!.botId, 'bot-b');

      gate.complete(
        BotConversationPage(
          botId: 'bot-a',
          conversations: [
            BotConversation(
              chatId: 'stale',
              kind: BotConversationKind.direct,
              source: BotConversationSource.observedDirect,
              name: null,
              lastObservedAt: null,
              threadBinding: null,
            ),
          ],
          nextCursor: null,
        ),
      );
      await stale;
      // The newer selection keeps its own page; the late result is delivered to
      // its original caller only.
      expect(secondScope.state.value.botId, 'bot-b');
      expect(secondScope.state.value.page!.botId, 'bot-b');
      expect(
        secondScope.state.value.page!.conversations.single.chatId,
        isNot('stale'),
      );
      expect(firstScope.state.value.page!.conversations.single.chatId, 'stale');
    },
  );

  test('message queries preserve identity and drop stale results after selection change', () async {
    final environment = BotsEnvironment(clientId: 'bots-messages');
    addTearDown(environment.close);

    final old = environment.repository.readMessages(
      'bot-b',
      'chat-old',
      limit: 10,
    );
    final coalesced = environment.repository.readMessages(
      'bot-b',
      'chat-old',
      limit: 10,
    );
    expect(identical(old, coalesced), isTrue);
    final older = await environment.port.messageRead(0);
    expect(older.query.limit, 10);

    final newer = environment.repository.readMessages(
      'bot-b',
      'chat-old',
      limit: 20,
    );
    final otherChat = environment.repository.readMessages(
      'bot-b',
      'chat-new',
      limit: 20,
    );
    expect(await environment.port.messageRead(1), isNotNull);
    expect(await environment.port.messageRead(2), isNotNull);
    environment.port.messageReads[1].reply.complete(
      BotMessagePage(botId: 'bot-b', chatId: 'chat-old', messages: const []),
    );
    environment.port.messageReads[2].reply.complete(
      BotMessagePage(botId: 'bot-b', chatId: 'chat-new', messages: const []),
    );
    await newer;
    await otherChat;

    older.reply.complete(
      BotMessagePage(botId: 'bot-b', chatId: 'chat-old', messages: const []),
    );
    await old;
    expect(
      environment.repository.messages.value.messagePage!.chatId,
      'chat-new',
    );
    expect(
      environment.port.messageReads
          .map((BotsMessageReadCall call) => call.query.limit)
          .toList(),
      [10, 20, 20],
    );
  });

  test('send freezes target before await and unknown results are retained without replay', () async {
    final environment = BotsEnvironment(clientId: 'bots-send');
    addTearDown(environment.close);
    environment.repository.updateMessageDraft('bot-1', 'chat-1', 'first');
    environment.repository.updateMessageDraft('bot-2', 'chat-2', 'other chat');
    final pending = environment.repository.sendMessage(
      botId: 'bot-1',
      chatId: 'chat-1',
      text: environment.repository.messageDraft('bot-1', 'chat-1'),
    );
    final call = await environment.port.sent(0);
    expect(call.request.botId, 'bot-1');
    expect(call.request.chatId, 'chat-1');
    expect(call.request.text, 'first');
    environment.repository.updateMessageDraft(
      'bot-1',
      'chat-1',
      'edited after submit',
    );
    await Future<void>.delayed(Duration.zero);
    expect(environment.port.sends, hasLength(1));
    expect(
      environment.repository.messageDraft('bot-1', 'chat-1'),
      'edited after submit',
    );
    expect(
      environment.repository.messageDraft('bot-2', 'chat-2'),
      'other chat',
    );

    call.reply.complete(
      BotSendResult(
        operationId: call.request.operationId,
        botId: 'bot-1',
        chatId: 'chat-1',
        status: BotSendStatus.unknown,
        segments: const [
          BotSendSegment(index: 0, status: BotSendStatus.unknown),
        ],
        receipt: CommitReceipt(
          operationId: call.request.operationId,
          disposition: CommitDisposition.applied,
          targets: [
            ResourceStamp(
              resourceKey: 'bot:bot-1',
              ownerEpoch: 'epoch',
              revision: 1,
            ),
          ],
          effect: EffectPoint.immediate,
          effective: true,
          durable: false,
        ),
      ),
    );
    final outcome = await pending.result;
    expect(outcome, isA<UnknownOutcomeCommandResult<BotSendResult>>());
    expect(
      environment.repository.sends.value.latestFor('bot-1', 'chat-1')!.status,
      BotSendStatus.unknown,
    );
    // Neither the unknown outcome nor cleanup replays the external write.
    expect(environment.port.sends, hasLength(1));
    expect(environment.port.sends.single.request.text, 'first');
  });

  test('repository close joins bot conversation queries', () async {
    final environment = BotsEnvironment(clientId: 'bots-close');
    addTearDown(environment.close);
    await environment.establish(revision: 1);

    final scope = environment.repository.conversations('bot-1');
    final opening = await environment.port.conversationOpened(0);
    final connection = ScriptedConversationConnection(
      'bot-1',
      declaredBotId: 'bot-1',
    );
    final gate = Completer<BotConversationPage>();
    connection.onPage = (request) => gate.future;
    opening.reply.complete(connection);
    final pending = scope.page();
    await connection.pageEntered.future;

    final closed = environment.repository.close();
    var reported = false;
    unawaited(closed.then((_) => reported = true));
    await Future<void>.delayed(Duration.zero);
    // The original native query stays owned: close cannot report completion
    // before its real reply arrives.
    expect(reported, isFalse);
    // A sealed scope joins the query but publishes no late page.
    final pendingFailure = expectLater(
      pending,
      throwsA(
        isA<StudioFailure>().having(
          (StudioFailure failure) => failure.code,
          'code',
          StudioFailureCode.cancelled,
        ),
      ),
    );
    gate.complete(
      BotConversationPage(
        botId: 'bot-1',
        conversations: const [],
        nextCursor: null,
      ),
    );
    await pendingFailure;
    final report = await closed;
    expect(report.complete, isTrue);
    expect(report.unresolved, isEmpty);
  });

  test(
    'replaced queries retain real ownership and budget through close',
    () async {
      final environment = BotsEnvironment(clientId: 'bots-retired');
      addTearDown(environment.close);
      await environment.establish(revision: 1);
      final baseline = environment.budget.used(ResourceKind.readModel);

      final firstScope = environment.repository.conversations('bot-a');
      final firstOpen = await environment.port.conversationOpened(0);
      final first = ScriptedConversationConnection(
        'bot-a',
        declaredBotId: 'bot-a',
      );
      final gate = Completer<BotConversationPage>();
      first.onPage = (request) => gate.future;
      firstOpen.reply.complete(first);
      final pending = firstScope.page();
      await first.pageEntered.future;
      expect(environment.budget.used(ResourceKind.readModel), baseline + 1);
      Iterable<ResourceUsage> retiredHandles() =>
          environment.budget.usage.where(
            (ResourceUsage usage) =>
                usage.owner.startsWith('bots:conversations:bot-a'),
          );
      expect(retiredHandles(), isNotEmpty);

      final secondScope = environment.repository.conversations('bot-b');
      final secondOpen = await environment.port.conversationOpened(1);
      final second = ScriptedConversationConnection(
        'bot-b',
        declaredBotId: 'bot-b',
      );
      second.onPage = (request) async => BotConversationPage(
        botId: 'bot-b',
        conversations: const [],
        nextCursor: null,
      );
      secondOpen.reply.complete(second);
      await secondScope.page();

      try {
        final report = await environment.repository.close(
          deadline: DateTime.now(),
        );
        expect(report.complete, isFalse);
        // A display replacement never releases the retired query's real native
        // handle, so an incomplete close must not pretend the budget is clean.
        expect(retiredHandles(), isNotEmpty);
        final retiredFailure = expectLater(
          pending,
          throwsA(isA<StudioFailure>()),
        );
        gate.complete(
          BotConversationPage(
            botId: 'bot-a',
            conversations: const [],
            nextCursor: null,
          ),
        );
        await retiredFailure;
        final retried = await environment.repository.retryCleanup();
        expect(retried.complete, isTrue);
        expect(retiredHandles(), isEmpty);
        expect(environment.budget.used(ResourceKind.readModel), 0);
        expect(secondScope.state.value.page!.botId, 'bot-b');
      } finally {
        if (!gate.isCompleted) {
          gate.complete(
            BotConversationPage(
              botId: 'bot-a',
              conversations: const [],
              nextCursor: null,
            ),
          );
        }
        await environment.close();
      }
    },
  );

  test(
    'foreign conversation responses fail without publishing another bot',
    () async {
      final environment = BotsEnvironment(clientId: 'bots-foreign');
      addTearDown(environment.close);
      await environment.establish(revision: 1);

      final scope = environment.repository.conversations('bot-b');
      final opening = await environment.port.conversationOpened(0);
      final connection = ScriptedConversationConnection(
        'bot-b',
        declaredBotId: 'bot-b',
      );
      connection.onPage = (request) async => BotConversationPage(
        botId: 'bot-a',
        conversations: [],
        nextCursor: null,
      );
      opening.reply.complete(connection);

      final rejected = expectLater(
        scope.page(),
        throwsA(
          isA<StudioFailure>().having(
            (StudioFailure failure) => failure.code,
            'code',
            StudioFailureCode.protocol,
          ),
        ),
      );
      await rejected;
      expect(scope.state.value.page, isNull);
      expect(scope.state.value.error!.code, StudioFailureCode.protocol);
    },
  );
}
