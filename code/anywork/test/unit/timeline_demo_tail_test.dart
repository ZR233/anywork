import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_fixtures.dart';

import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<DemoStudioTransport> demo() async {
    final transport = DemoStudioTransport();
    await transport.readBootstrap();
    return transport;
  }

  Future<ConversationFrame> nextFrame(
    StreamIterator<ConversationFrame> iterator,
  ) async {
    expect(await iterator.moveNext(), isTrue);
    return iterator.current;
  }

  Future<
    ({
      DriverDemoStudioTransport transport,
      ThreadWorkspace workspace,
      PendingInteraction interaction,
    })
  >
  driverPlan({
    DriverDemoStudioTransport? transport,
    bool prepare = true,
  }) async {
    final value = transport ?? DriverDemoStudioTransport();
    if (prepare) value.prepareThemeScenario(plan: true);
    await value.readBootstrap();
    final feed = await value.openConversationFeed(
      'thread-main',
      scope: const MainChatScope(),
      demand: const ReadDemand(maxItems: 1000, maxBytes: 262144),
    );
    final iterator = StreamIterator(feed.events);
    try {
      final frame = await nextFrame(iterator);
      await feed.acknowledge(frame.deliverySequence);
      expect(frame.event, isA<ConversationStateEvent>());
      final state = (frame.event as ConversationStateEvent).frame;
      expect(state, isA<ThreadSnapshotFrame>());
      final workspace = (state as ThreadSnapshotFrame).workspace;
      final interaction = workspace.interactions.singleWhere(
        (candidate) => candidate.isPlanConfirmation,
      );
      expect(interaction.id, isNotEmpty);
      expect(interaction.revision, 1);
      expect(workspace.runtime.plan?.revision, 1);
      expect(
        workspace.runtime.plan?.state,
        PlanRuntimePhase.awaitingConfirmation,
      );
      return (transport: value, workspace: workspace, interaction: interaction);
    } finally {
      await feed.close();
      await iterator.cancel();
    }
  }

  Future<ThreadWorkspace> latestWorkspace(DemoStudioTransport transport) async {
    final feed = await transport.openConversationFeed(
      'thread-main',
      scope: const MainChatScope(),
      demand: const ReadDemand(maxItems: 1000, maxBytes: 262144),
    );
    final iterator = StreamIterator(feed.events);
    try {
      final frame = await nextFrame(iterator);
      expect(frame.event, isA<ConversationStateEvent>());
      final state = (frame.event as ConversationStateEvent).frame;
      expect(state, isA<ThreadSnapshotFrame>());
      return (state as ThreadSnapshotFrame).workspace;
    } finally {
      await feed.close();
      await iterator.cancel();
    }
  }

  Future<ChatBatch> nextChat(
    ConversationFeed feed,
    StreamIterator<ConversationFrame> iterator,
  ) async {
    while (true) {
      final frame = await nextFrame(iterator);
      switch (frame.event) {
        case ConversationChatEvent(:final batch):
          await feed.acknowledge(frame.deliverySequence);
          return batch;
        case ConversationStateEvent():
          await feed.acknowledge(frame.deliverySequence);
        case ConversationFailureEvent(:final failure):
          throw failure;
        case ConversationClosedEvent():
          throw StateError('Closed before Chat');
      }
    }
  }

  Future<List<ChatItemPresentation>> historyItems(
    DemoStudioTransport transport,
  ) async {
    final feed = await transport.openConversationFeed(
      'thread-main',
      scope: const MainChatScope(),
      demand: const ReadDemand(maxItems: 1000, maxBytes: 262144),
    );
    final iterator = StreamIterator(feed.events);
    try {
      return (await nextChat(
        feed,
        iterator,
      )).messages.map(ChatItemPresentation.decode).toList();
    } finally {
      await feed.close();
      await iterator.cancel();
    }
  }

  String planQuestionId(PendingInteraction interaction) {
    final payload = interaction.payload as UserInputInteractionPayload;
    expect(payload.questions, hasLength(1));
    expect(payload.questions.single.isSecret, isFalse);
    expect(payload.questions.single.id, agentSessionPlanConfirmationQuestionId);
    return payload.questions.single.id;
  }

  UserInputResolutionCommand planAnswer(
    PendingInteraction interaction,
    List<String> answers,
  ) => UserInputResolutionCommand(
    answers: [
      UserInputAnswerCommand(
        questionId: planQuestionId(interaction),
        answers: answers,
      ),
    ],
  );

  Future<InteractionCommandReply> resolvePlan(
    DriverDemoStudioTransport transport,
    PendingInteraction interaction,
    List<String> answers, {
    required OperationId operationId,
  }) => transport.respondInteraction(
    'thread-main',
    interaction.id,
    interaction.revision,
    planAnswer(interaction, answers),
    operationId: operationId,
  );

  Future<ChatItemPresentation> planHistoryItem(
    DemoStudioTransport transport,
    String interactionId,
  ) async {
    final id = 'demo-plan:$interactionId';
    return (await historyItems(transport)).singleWhere((item) => item.id == id);
  }

  Future<String> planHistoryField(
    DemoStudioTransport transport,
    String interactionId,
    String key,
  ) async {
    final feed = await transport.openConversationFeed(
      'thread-main',
      scope: const MainChatScope(),
      demand: const ReadDemand(maxItems: 1000, maxBytes: 262144),
    );
    final iterator = StreamIterator(feed.events);
    try {
      final batch = await nextChat(feed, iterator);
      final item = ChatItemPresentation.decode(
        batch.messages.singleWhere(
          (message) => message.id == 'demo-plan:$interactionId',
        ),
      );
      final body = item.body(key)!;
      if (body.inline != null) return item.inlineText(key)!;
      return utf8.decode(
        (await feed.reader.readContent(
          reference: body.reference!,
          range: const ContentRange(offset: 0, maxBytes: 65536),
        )).bytes,
      );
    } finally {
      await feed.close();
      await iterator.cancel();
    }
  }

  test('single credit gates Set after State; reopen starts with a new Set rather than resume cursor', () async {
    final transport = await demo();
    transport.seedChatMessages('thread-main', [chatMessage('first')]);
    final feed = await transport.openConversationFeed(
      'thread-main',
      scope: const MainChatScope(),
      demand: chatDemand,
    );
    final iterator = StreamIterator(feed.events);
    final state = await nextFrame(iterator);
    expect(state.event, isA<ConversationStateEvent>());
    var secondDelivered = false;
    final second = iterator.moveNext().then((value) {
      secondDelivered = true;
      return value;
    });
    await Future<void>.delayed(Duration.zero);
    expect(
      secondDelivered,
      isFalse,
      reason: 'one unacknowledged ordinary batch owns the only credit',
    );
    await feed.acknowledge(state.deliverySequence);
    expect(await second, isTrue);
    final set = (iterator.current.event as ConversationChatEvent).batch;
    expect(set.placement, ChatPlacement.set);
    expect(set.messages.last.id, 'first');
    await feed.acknowledge(iterator.current.deliverySequence);
    transport.seedChatMessages('thread-main', [
      chatMessage('second'),
      chatMessage('third'),
    ]);
    final append = await nextChat(feed, iterator);
    expect(append.placement, ChatPlacement.append);
    expect(append.messages.map((message) => message.id), ['second', 'third']);
    await feed.close();
    await iterator.cancel();
    final reopened = await transport.openConversationFeed(
      'thread-main',
      scope: const MainChatScope(),
      demand: chatDemand,
    );
    final reopenedIterator = StreamIterator(reopened.events);
    final fresh = await nextChat(reopened, reopenedIterator);
    expect(fresh.placement, ChatPlacement.set);
    expect(
      fresh.messages.map((message) => message.id),
      containsAllInOrder(['first', 'second', 'third']),
    );
    await reopened.close();
    await reopenedIterator.cancel();
  });

  test('producer member and Turn messages remain ordered in one Append without Activity staging', () async {
    final transport = await demo();
    final feed = await transport.openConversationFeed(
      'thread-main',
      scope: const MainChatScope(),
      demand: chatDemand,
    );
    final iterator = StreamIterator(feed.events);
    await nextChat(feed, iterator);
    transport.seedChatMessages('thread-main', [
      chatMessage('member'),
      chatEnvelope(
        'turn-complete',
        type: 'turn',
        data: const {
          'outcome': {
            'kind': 'completed',
            'data': {'completedAt': 3},
          },
        },
      ),
    ]);
    final append = await nextChat(feed, iterator);
    expect(append.placement, ChatPlacement.append);
    expect(append.messages.map((message) => message.id), [
      'member',
      'turn-complete',
    ]);
    await feed.close();
    await iterator.cancel();
  });

  test('original reader pages opaque payload byte windows and is cancelled with its feed', () async {
    final transport = await demo();
    final message = chatMessage('long', body: '中文🐱' * 3000);
    transport.seedChatMessages('thread-main', [message]);
    final feed = await transport.openConversationFeed(
      'thread-main',
      scope: const MainChatScope(),
      demand: const ReadDemand(maxItems: 1, maxBytes: 4096),
    );
    final iterator = StreamIterator(feed.events);
    final set = await nextChat(feed, iterator);
    final deferred = set.messages.single.payload as DeferredPayload;
    final first = await feed.reader.readContent(
      reference: deferred.reference,
      range: const ContentRange(offset: 0, maxBytes: 17),
    );
    final second = await feed.reader.readContent(
      reference: deferred.reference,
      range: ContentRange(offset: first.bytes.length, maxBytes: 19),
    );
    expect([
      ...first.bytes,
      ...second.bytes,
    ], (message.payload as InlinePayload).bytes.take(36));
    expect(first.offset, 0);
    expect(second.offset, 17);
    expect(first.availableThrough, deferred.byteLength);
    expect(first.sealed, isTrue);
    await feed.close();
    await expectLater(
      feed.reader.readContent(
        reference: deferred.reference,
        range: const ContentRange(offset: 0, maxBytes: 17),
      ),
      throwsA(isA<StudioFailure>()),
    );
    await iterator.cancel();
  });

  test('duplicate producer identity is idempotent but conflicting payload is rejected', () async {
    final transport = await demo();
    transport.seedChatMessages('thread-main', [
      chatMessage('same', body: 'same'),
    ]);
    transport.seedChatMessages('thread-main', [
      chatMessage('same', body: 'same'),
    ]);
    expect(
      () => transport.seedChatMessages('thread-main', [
        chatMessage('same', body: 'different'),
      ]),
      throwsA(
        isA<StudioFailure>()
            .having(
              (failure) => failure.code,
              'code',
              StudioFailureCode.conflict,
            )
            .having(
              (failure) => failure.correlationId,
              'correlationId',
              'demo-completion-conflict',
            ),
      ),
    );
    expect(
      (await historyItems(transport)).where((item) => item.id == 'same'),
      hasLength(1),
    );
  });

  test('Demo secret answer is absent from both the message and original reader manifest', () async {
    final transport = await demo();
    const secret = 'secret-token-never-public';
    const interaction = PendingInteraction(
      id: 'secret-input',
      threadId: 'thread-main',
      turnId: 'secret-turn',
      revision: 1,
      kind: InteractionKind.userInput,
      title: 'Input',
      body: '',
      payload: UserInputInteractionPayload(
        questions: [
          UserQuestionView(
            id: 'secret-q',
            header: 'Private header',
            question: 'Private question',
            isOther: true,
            isSecret: true,
            options: [],
          ),
        ],
      ),
    );
    transport.seedConversationState(
      'thread-main',
      const ThreadInteractionUpdate(interaction: interaction, pending: true),
    );
    await transport.respondInteraction(
      'thread-main',
      interaction.id,
      interaction.revision,
      const UserInputResolutionCommand(
        answers: [
          UserInputAnswerCommand(questionId: 'secret-q', answers: [secret]),
        ],
      ),
      operationId: const OperationId('answer-secret'),
    );
    final feed = await transport.openConversationFeed(
      'thread-main',
      scope: const MainChatScope(),
      demand: chatDemand,
    );
    final iterator = StreamIterator(feed.events);
    try {
      final batch = await nextChat(feed, iterator);
      final message = batch.messages.singleWhere(
        (message) => message.id == 'demo-user-input:secret-input',
      );
      final item = ChatItemPresentation.decode(message);
      expect(item.raw, isNot(contains(secret)));
      expect(item.raw, isNot(contains('Private header')));
      expect(item.raw, isNot(contains('Private question')));
      final manifest = await feed.reader.listContents(
        itemId: message.id,
        demand: chatDemand,
      );
      expect(
        manifest.entries.where(
          (entry) => entry.key.startsWith('tool.user-input.'),
        ),
        isEmpty,
      );
      final publicManifest = await feed.reader.listContents(
        itemId: 'turn-demo:final',
        demand: chatDemand,
      );
      expect(publicManifest.entries, isNotEmpty);
      await expectLater(
        feed.reader.readContent(
          reference: ContentRef(
            databaseId: publicManifest.entries.first.reference.databaseId,
            target: BodyContentTarget(
              owner: ItemContentOwner(itemId: message.id),
              key: 'tool.user-input.answer.0.0',
            ),
          ),
          range: const ContentRange(offset: 0, maxBytes: 32),
        ),
        throwsA(isA<StudioFailure>()),
      );
    } finally {
      await feed.close();
      await iterator.cancel();
    }
  });

  test('Driver Plan 公开决议按冻结请求完成、回放同一回执且保留自身文档', () async {
    final scenarios = [
      (
        name: 'approve',
        answers: [agentSessionPlanApproveAnswer],
        decision: 'approved',
        phase: PlanRuntimePhase.approved,
        feedback: null,
        mutateCurrentPlanAfterDecision: true,
      ),
      (
        name: 'revision',
        answers: [
          agentSessionPlanReviseAnswer,
          '  Palette should remain legible.  ',
          '\n',
          '  Keep keyboard focus visible.\t',
        ],
        decision: 'revisionRequested',
        phase: PlanRuntimePhase.revisionRequested,
        feedback:
            'Palette should remain legible.\nKeep keyboard focus visible.',
        mutateCurrentPlanAfterDecision: false,
      ),
    ];

    for (final scenario in scenarios) {
      final fixture = await driverPlan();
      final transport = fixture.transport;
      final interaction = fixture.interaction;
      final document = fixture.workspace.runtime.plan!.document!;
      expect(document.version, 1);
      expect(
        document.contentHash,
        'sha256:30205da061addd1c07201c28d92cd9533f77cb5740c452a478425751f3685f0d',
      );
      expect(interaction.body, document.markdown);
      final operationId = OperationId('driver-plan-${scenario.name}');
      final reply = await resolvePlan(
        transport,
        interaction,
        scenario.answers,
        operationId: operationId,
      );
      expect(reply.receipt.operationId, operationId);
      expect(reply.receipt.effective, isTrue);
      expect(reply.receipt.requiresIdentityObservation, isTrue);

      var workspace = await latestWorkspace(transport);
      expect(workspace.runtime.plan!.state, scenario.phase);
      expect(workspace.runtime.plan!.revision, 2);

      if (scenario.mutateCurrentPlanAfterDecision) {
        final changedDocument = document.copyWith(
          version: 99,
          markdown: '# Later current Plan\n\nNot the frozen request.',
          contentHash: 'sha256:later-current-plan',
        );
        final changedRuntime = workspace.runtime.copyWith(
          plan: workspace.runtime.plan!.copyWith(
            revision: 99,
            state: PlanRuntimePhase.drafting,
            document: changedDocument,
          ),
        );
        transport.seedConversationState(
          'thread-main',
          ThreadRuntimeUpdate(
            runtime: changedRuntime,
            todo: workspace.todo,
            modelRoute: workspace.modelRoute,
          ),
        );
        workspace = await latestWorkspace(transport);
        expect(workspace.runtime.plan!.document, changedDocument);
      }

      final item = await planHistoryItem(transport, interaction.id);
      final descriptor = item.data;
      expect(descriptor['interactionId'], interaction.id);
      expect(descriptor['decision'], scenario.decision);
      expect(descriptor['documentVersion'], 1);
      expect(
        descriptor['contentHash'],
        'sha256:30205da061addd1c07201c28d92cd9533f77cb5740c452a478425751f3685f0d',
      );
      expect(
        await planHistoryField(transport, interaction.id, 'plan.document'),
        document.markdown,
      );
      if (scenario.feedback == null) {
        expect(item.body('plan.feedback'), isNull);
      } else {
        expect(item.inlineText('plan.feedback'), scenario.feedback);
        expect(
          await planHistoryField(transport, interaction.id, 'plan.feedback'),
          scenario.feedback,
        );
      }

      final replay = await resolvePlan(
        transport,
        interaction,
        scenario.answers,
        operationId: OperationId('driver-plan-replay-${scenario.name}'),
      );
      expect(identical(replay.receipt, reply.receipt), isTrue);
      expect(
        (await historyItems(
          transport,
        )).where((candidate) => candidate.id == 'demo-plan:${interaction.id}'),
        hasLength(1),
        reason: '同一原始 receipt 的重放不得再次追加完成原子',
      );
      if (scenario.mutateCurrentPlanAfterDecision) {
        expect(
          (await latestWorkspace(transport))
              .runtime
              .plan!
              .document!
              .contentHash,
          'sha256:later-current-plan',
        );
      }
    }
  });

  test('Driver Plan 拒绝输入无状态/历史/回执副作用且同 operation 可重试', () async {
    const invalidKinds = ['missing', 'duplicate', 'contradictory', 'blank'];
    for (final kind in invalidKinds) {
      final fixture = await driverPlan();
      final interaction = fixture.interaction;
      final questionId = planQuestionId(interaction);
      final invalidAnswers = switch (kind) {
        'missing' => const <UserInputAnswerCommand>[],
        'duplicate' => [
          UserInputAnswerCommand(
            questionId: questionId,
            answers: const [agentSessionPlanApproveAnswer],
          ),
          UserInputAnswerCommand(
            questionId: questionId,
            answers: const [agentSessionPlanApproveAnswer],
          ),
        ],
        'contradictory' => [
          UserInputAnswerCommand(
            questionId: questionId,
            answers: const [
              agentSessionPlanApproveAnswer,
              agentSessionPlanReviseAnswer,
            ],
          ),
        ],
        'blank' => [
          UserInputAnswerCommand(
            questionId: questionId,
            answers: const [' \n\t '],
          ),
        ],
        _ => throw StateError('Unknown invalid Plan case: $kind'),
      };
      final operationId = OperationId('driver-plan-invalid-$kind');
      final originalPlan = fixture.workspace.runtime.plan!;
      await expectLater(
        fixture.transport.respondInteraction(
          'thread-main',
          interaction.id,
          interaction.revision,
          UserInputResolutionCommand(answers: invalidAnswers),
          operationId: operationId,
        ),
        throwsA(
          isA<StudioFailure>().having(
            (failure) => failure.code,
            'code',
            StudioFailureCode.invalidArgument,
          ),
        ),
      );
      expect(
        (await latestWorkspace(fixture.transport)).runtime.plan,
        originalPlan,
        reason: '$kind rejection must leave the current Plan untouched',
      );
      expect(
        (await historyItems(fixture.transport))
            .where((item) => item.id == 'demo-plan:${interaction.id}'),
        isEmpty,
        reason: '$kind rejection must not append history',
      );

      final accepted = await resolvePlan(fixture.transport, interaction, [
        agentSessionPlanApproveAnswer,
      ], operationId: operationId);
      expect(accepted.receipt.operationId, operationId);
      expect(accepted.receipt.effective, isTrue);
      expect(
        (await historyItems(fixture.transport))
            .where((item) => item.id == 'demo-plan:${interaction.id}'),
        hasLength(1),
        reason: '拒绝不得占用 operation receipt 或重复 append',
      );
    }
  });

  test('Driver Plan 换场景后旧交互不能决议；未知文档不借用当前 Plan，普通问答保持普通', () async {
    final old = await driverPlan();
    final transport = old.transport;
    transport.prepareThemeScenario(plan: true);
    final current = await driverPlan(transport: transport, prepare: false);
    expect(current.interaction.id, isNot(old.interaction.id));
    await expectLater(
      resolvePlan(transport, old.interaction, [
        agentSessionPlanApproveAnswer,
      ], operationId: const OperationId('retired-driver-plan')),
      throwsA(
        isA<StudioFailure>().having(
          (failure) => failure.code,
          'code',
          StudioFailureCode.notFound,
        ),
      ),
    );
    expect(
      (await historyItems(transport))
          .where((item) => item.id == 'demo-plan:${old.interaction.id}'),
      isEmpty,
    );
    expect(
      (await latestWorkspace(transport)).runtime.plan!.state,
      PlanRuntimePhase.awaitingConfirmation,
    );

    final seededCases = [
      (
        id: 'unfrozen-reserved-question',
        questionId: agentSessionPlanConfirmationQuestionId,
        frozenPlan: true,
      ),
      (
        id: 'ordinary-user-input',
        questionId: 'ordinary-question',
        frozenPlan: false,
      ),
    ];
    for (final seededCase in seededCases) {
      final demoTransport = await demo();
      final interaction = PendingInteraction(
        id: seededCase.id,
        threadId: 'thread-main',
        turnId: 'seeded-turn',
        revision: 1,
        kind: InteractionKind.userInput,
        title: 'Plan approval question',
        body: 'Approve this Plan?',
        payload: UserInputInteractionPayload(
          questions: [
            UserQuestionView(
              id: seededCase.questionId,
              header: 'Plan',
              question: 'Approve this Plan?',
              isOther: true,
              isSecret: false,
              options: const [],
            ),
          ],
        ),
      );
      final seeded = demoTransport.seedConversationState(
        'thread-main',
        ThreadInteractionUpdate(interaction: interaction, pending: true),
      );
      expect(seeded.runtime.plan, isNull);
      await demoTransport.respondInteraction(
        'thread-main',
        interaction.id,
        interaction.revision,
        UserInputResolutionCommand(
          answers: [
            UserInputAnswerCommand(
              questionId: seededCase.questionId,
              answers: const [agentSessionPlanApproveAnswer],
            ),
          ],
        ),
        operationId: OperationId('seeded-${seededCase.id}'),
      );
      expect((await latestWorkspace(demoTransport)).runtime.plan, isNull);
      if (seededCase.frozenPlan) {
        final receipt = await planHistoryItem(demoTransport, interaction.id);
        final descriptor = receipt.data;
        expect(descriptor['interactionId'], interaction.id);
        expect(descriptor['decision'], 'approved');
        expect(descriptor['documentVersion'], isNull);
        expect(descriptor['contentHash'], isNull);
        expect(receipt.body('plan.document'), isNotNull);
      } else {
        final genericReceipt = (await historyItems(demoTransport)).singleWhere(
          (item) => item.id == 'demo-user-input:${interaction.id}',
        );
        expect(genericReceipt.type, 'tool');
        expect(genericReceipt.type, isNot('plan'));
        expect(
          (await historyItems(demoTransport))
              .where((item) => item.id == 'demo-plan:${interaction.id}'),
          isEmpty,
        );
      }
    }
  });
}
