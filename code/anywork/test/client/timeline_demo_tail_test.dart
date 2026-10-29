import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/conversation_fixtures.dart';

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
    final feed = await value.openConversationFeed('thread-main');
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
    final feed = await transport.openConversationFeed('thread-main');
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

  Future<List<ConversationItem>> historyItems(
    DemoStudioTransport transport,
  ) async {
    final reader = await transport.openHistoryReader('thread-main');
    try {
      return (await reader.page(limit: 100)).items;
    } finally {
      await reader.close();
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

  Future<ConversationItem> planHistoryItem(
    DemoStudioTransport transport,
    String interactionId,
  ) async {
    final id = 'demo-plan:$interactionId';
    return (await historyItems(transport)).singleWhere((item) => item.id == id);
  }

  Future<String> planHistoryField(
    DemoStudioTransport transport,
    String interactionId,
    ThreadContentFieldView field,
  ) async {
    final reader = await transport.openHistoryReader('thread-main');
    try {
      return (await reader.readDetail(
        itemId: 'demo-plan:$interactionId',
        query: ConversationDetailQuery(
          timelineEpoch: reader.timelineEpoch,
          field: field,
        ),
      )).text;
    } finally {
      await reader.close();
    }
  }

  test('同 epoch 完成游标连续恢复；feed 两个未 ACK 数据帧后停发', () async {
    final transport = await demo();
    transport.seedConversationItems('thread-main', [
      conversationFixture(id: 'first', appendSeq: 1),
    ]);
    final first = await transport.openConversationFeed('thread-main');
    final iterator = StreamIterator(first.events);
    // State + baseline fill both initially available data credits.
    final state = await nextFrame(iterator);
    final baselineFrame = await nextFrame(iterator);
    var thirdSettled = false;
    final thirdFuture = nextFrame(iterator);
    unawaited(thirdFuture.then((_) => thirdSettled = true));
    await Future<void>.delayed(Duration.zero);
    expect(thirdSettled, isFalse, reason: '两个 credit 均未 ACK 时不得投递第三帧');
    await first.acknowledge(state.deliverySequence);
    await first.acknowledge(baselineFrame.deliverySequence);
    final baseline =
        (baselineFrame.event as ConversationBaselineEvent).baseline;
    expect(baseline.items.last.id, 'first');
    final cursor = baseline.completedCursor;
    final thirdFrame = await thirdFuture;
    await first.acknowledge(thirdFrame.deliverySequence);
    await first.close();
    await iterator.cancel();

    transport.seedConversationItems('thread-main', [
      conversationFixture(id: 'second', appendSeq: 2),
      conversationFixture(id: 'third', appendSeq: 3),
    ]);
    final resumed = await transport.openConversationFeed(
      'thread-main',
      resumeAfter: cursor,
    );
    final resumedIterator = StreamIterator(resumed.events);
    final resumedState = await nextFrame(resumedIterator);
    await resumed.acknowledge(resumedState.deliverySequence);
    var resumedCompletion = false;
    while (!resumedCompletion) {
      final frame = await nextFrame(resumedIterator);
      await resumed.acknowledge(frame.deliverySequence);
      if (frame.event case ConversationActivityContentEvent(
        frame: ActivityCommit(),
        completed: final ConversationBatch batch?,
      )) {
        expect(batch.timelineEpoch, baseline.timelineEpoch);
        expect(batch.fromSeq, cursor.appendSeq);
        expect(batch.items.map((item) => item.id), ['second', 'third']);
        resumedCompletion = true;
      }
    }
    await resumed.close();
    await resumedIterator.cancel();
  });

  test('成员完成先于 Turn，且完成 batch 与 Activity Commit 同帧交付', () async {
    final transport = await demo();
    final feed = await transport.openConversationFeed('thread-main');
    final iterator = StreamIterator(feed.events);
    final initialState = await nextFrame(iterator);
    final initialBaseline = await nextFrame(iterator);
    await feed.acknowledge(initialState.deliverySequence);
    await feed.acknowledge(initialBaseline.deliverySequence);
    transport.seedConversationItems('thread-main', [
      conversationFixture(id: 'member', appendSeq: 1, turnId: 'turn-A'),
      conversationFixture(
        id: 'turn-complete',
        appendSeq: 2,
        turnId: 'turn-A',
        descriptor: ConversationTurnDescriptor(
          outcome: ConversationTurnCompleted(
            const CompletedStudioTurnState(
              startedAt: 1700000000,
              completedAt: 1700000002,
              completion: StudioTurnCompletion.normal,
            ),
          ),
        ),
      ),
    ]);
    var found = false;
    while (!found) {
      final frame = await nextFrame(iterator);
      await feed.acknowledge(frame.deliverySequence);
      if (frame.event case ConversationActivityContentEvent(
        frame: ActivityCommit(),
        completed: final ConversationBatch batch?,
      )) {
        expect(batch.items.map((item) => item.id), ['member', 'turn-complete']);
        expect(
          batch.items.first.header.appendSeq,
          lessThan(batch.items.last.header.appendSeq),
        );
        found = true;
      }
    }
    expect(found, isTrue);
    await feed.close();
    await iterator.cancel();
  });

  test('history reader 同 epoch 独立于 feed 生命周期，并按 UTF-8 字节预算分页详情', () async {
    final transport = await demo();
    final text = '🐱中文';
    transport.seedConversationItems('thread-main', [
      conversationFixture(
        id: 'long',
        appendSeq: 1,
        fields: {const ThreadTextFieldView(): text},
        totalBytes: {const ThreadTextFieldView(): utf8.encode(text).length},
      ),
    ]);
    final reader = await transport.openHistoryReader('thread-main');
    final feed = await transport.openConversationFeed('thread-main');
    final iterator = StreamIterator(feed.events);
    await nextFrame(iterator);
    final baselineFrame = await nextFrame(iterator);
    final epoch = (baselineFrame.event as ConversationBaselineEvent)
        .baseline
        .timelineEpoch;
    expect(reader.timelineEpoch, epoch);
    await feed.close();
    await iterator.cancel();

    final page = await reader.page(limit: 10);
    expect(page.timelineEpoch, epoch);
    expect(page.items.singleWhere((item) => item.id == 'long').id, 'long');
    final first = await reader.readDetail(
      itemId: 'long',
      query: ConversationDetailQuery(
        timelineEpoch: epoch,
        field: const ThreadTextFieldView(),
        maxBytes: 4,
      ),
    );
    expect(first.text, '🐱');
    expect(utf8.encode(first.text), hasLength(4));
    final second = await reader.readDetail(
      itemId: 'long',
      query: ConversationDetailQuery(
        timelineEpoch: epoch,
        field: const ThreadTextFieldView(),
        continuation: first.continuation,
        maxBytes: 4,
      ),
    );
    final third = await reader.readDetail(
      itemId: 'long',
      query: ConversationDetailQuery(
        timelineEpoch: epoch,
        field: const ThreadTextFieldView(),
        continuation: second.continuation,
        maxBytes: 4,
      ),
    );
    expect(first.text + second.text + third.text, text);
    await reader.close();
  });

  test('同一完成身份幂等，冲突内容拒绝；无效跨 epoch reader 查询不串读', () async {
    final transport = await demo();
    final item = conversationFixture(id: 'fixed', appendSeq: 1);
    transport.seedConversationItems('thread-main', [item]);
    transport.seedConversationItems('thread-main', [
      conversationCopyFixture(item),
    ]);
    expect(
      () => transport.seedConversationItems('thread-main', [
        conversationCopyFixture(
          item,
          fields: {const ThreadTextFieldView(): 'changed'},
          totalBytes: {
            const ThreadTextFieldView(): utf8.encode('changed').length,
          },
        ),
      ]),
      throwsA(
        isA<StudioFailure>().having(
          (failure) => failure.code,
          'code',
          StudioFailureCode.conflict,
        ),
      ),
    );
    final reader = await transport.openHistoryReader('thread-main');
    await expectLater(
      reader.readDetail(
        itemId: 'fixed',
        query: const ConversationDetailQuery(
          timelineEpoch: 'another-epoch',
          field: ThreadTextFieldView(),
        ),
      ),
      throwsA(isA<StudioFailure>()),
    );
    await reader.close();
  });

  test('问答 secret 不暴露答案字段，短预算拒绝且详情仅包含允许的非 secret 正文', () async {
    final transport = await demo();
    final question = UserQuestionView(
      id: 'secret-q',
      header: 'Credentials',
      question: 'Enter token',
      options: const [],
      isOther: false,
      isSecret: true,
    );
    final input = conversationInputFixture(
      interactionId: 'interaction',
      questions: [question],
      state: ConversationUserInputResolved(
        answers: const [
          ConversationAnswerDescriptor(
            questionId: 'secret-q',
            answerCount: 1,
            redacted: true,
          ),
        ],
      ),
      answers: const {
        'secret-q': ['do-not-leak'],
      },
    );
    final item = conversationFixture(
      id: 'secret-item',
      appendSeq: 1,
      descriptor: ConversationToolDescriptor(
        invocation: const ConversationToolInvocation(
          toolCallId: 'call',
          name: 'ask',
        ),
        state: ConversationToolCancelled(
          cancelledAt: DateTime.fromMillisecondsSinceEpoch(1700000001),
          reason: 'test',
        ),
        userInput: input.descriptor,
      ),
      fields: input.fields,
    );
    transport.seedConversationItems('thread-main', [item]);
    final reader = await transport.openHistoryReader('thread-main');
    final page = await reader.page();
    final delivered = page.items.singleWhere(
      (item) => item.id == 'secret-item',
    );
    expect(delivered.descriptor, isA<ConversationToolDescriptor>());
    expect(
      delivered.fieldFor(
        const ThreadToolUserInputFieldView(
          questionIndex: 0,
          part: ThreadUserInputAnswerFieldPartView(0),
        ),
      ),
      isNull,
    );
    expect(
      delivered.fields.where(
        (field) => field.field is ThreadToolUserInputFieldView,
      ),
      isEmpty,
      reason: 'secret 问题的所有字段，包括 header、question 与答案，都不得暴露',
    );
    await expectLater(
      reader.readDetail(
        itemId: 'secret-item',
        query: ConversationDetailQuery(
          timelineEpoch: reader.timelineEpoch,
          field: const ThreadToolUserInputFieldView(
            questionIndex: 0,
            part: ThreadUserInputHeaderFieldPartView(),
          ),
          maxBytes: 4,
        ),
      ),
      throwsA(
        isA<StudioFailure>().having(
          (failure) => failure.code,
          'code',
          StudioFailureCode.notFound,
        ),
      ),
    );
    await expectLater(
      reader.readDetail(
        itemId: 'secret-item',
        query: ConversationDetailQuery(
          timelineEpoch: reader.timelineEpoch,
          field: const ThreadToolUserInputFieldView(
            questionIndex: 0,
            part: ThreadUserInputHeaderFieldPartView(),
          ),
          maxBytes: 3,
        ),
      ),
      throwsA(isA<StudioFailure>()),
    );
    await reader.close();
  });

  test('Driver Plan 公开决议按冻结请求完成、回放同一回执且保留自身文档', () async {
    final scenarios = [
      (
        name: 'approve',
        answers: [agentSessionPlanApproveAnswer],
        decision: ConversationPlanDecision.approved,
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
        decision: ConversationPlanDecision.revisionRequested,
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
          ThreadRuntimeUpdate(runtime: changedRuntime, todo: workspace.todo),
        );
        workspace = await latestWorkspace(transport);
        expect(workspace.runtime.plan!.document, changedDocument);
      }

      final item = await planHistoryItem(transport, interaction.id);
      final descriptor = item.descriptor as ConversationPlanDescriptor;
      expect(descriptor.interactionId, interaction.id);
      expect(descriptor.decision, scenario.decision);
      expect(descriptor.documentVersion, 1);
      expect(
        descriptor.contentHash,
        'sha256:30205da061addd1c07201c28d92cd9533f77cb5740c452a478425751f3685f0d',
      );
      expect(
        await planHistoryField(
          transport,
          interaction.id,
          const ThreadPlanDocumentFieldView(),
        ),
        document.markdown,
      );
      if (scenario.feedback == null) {
        expect(item.fieldFor(const ThreadPlanFeedbackFieldView()), isNull);
      } else {
        expect(
          item.fieldFor(const ThreadPlanFeedbackFieldView())?.text,
          scenario.feedback,
        );
        expect(
          await planHistoryField(
            transport,
            interaction.id,
            const ThreadPlanFeedbackFieldView(),
          ),
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
        final descriptor = receipt.descriptor as ConversationPlanDescriptor;
        expect(descriptor.interactionId, interaction.id);
        expect(descriptor.decision, ConversationPlanDecision.approved);
        expect(descriptor.documentVersion, isNull);
        expect(descriptor.contentHash, isNull);
        expect(
          receipt.fieldFor(const ThreadPlanDocumentFieldView()),
          isNotNull,
        );
      } else {
        final genericReceipt = (await historyItems(demoTransport)).singleWhere(
          (item) => item.id == 'demo-user-input:${interaction.id}',
        );
        expect(genericReceipt.descriptor, isA<ConversationToolDescriptor>());
        expect(
          genericReceipt.descriptor,
          isNot(isA<ConversationPlanDescriptor>()),
        );
        expect(
          (await historyItems(demoTransport))
              .where((item) => item.id == 'demo-plan:${interaction.id}'),
          isEmpty,
        );
      }
    }
  });
}
