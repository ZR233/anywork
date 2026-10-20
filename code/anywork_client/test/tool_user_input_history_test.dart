import 'package:test/test.dart';

import 'package:anywork_client/studio_client.dart';

/// 普通问答历史必须在 Client 契约层就是 typed 的：问题按原顺序、只有权威 resolved 才算已回答、
/// 敏感回答不携带原值，而且一次工具条目更新后仍能按字段身份拿到完整正文。
void main() {
  final created = DateTime.fromMillisecondsSinceEpoch(1000);

  ThreadItemView toolItem({
    required ThreadToolUserInputView? userInput,
    int revision = 1,
    int omittedUnits = 0,
    bool terminal = false,
  }) {
    return ThreadItemView(
      id: 'tool:call-1',
      threadId: 'thread-1',
      turnId: 'turn-1',
      ordinal: 4,
      revision: revision,
      createdAt: created,
      updatedAt: created,
      bodyOmittedUnits: omittedUnits,
      executionTerminal: terminal,
      state: ThreadToolItemStateView(
        invocation: const ThreadToolInvocationView(
          toolCallId: 'call-1',
          name: 'request_user_input',
          arguments: '{"questions":[]}',
        ),
        lifecycle: const RunningThreadToolView(''),
        userInput: userInput,
      ),
    );
  }

  ThreadToolUserInputView userInput({
    required ThreadToolUserInputStateView state,
    String firstQuestion = 'Which account should the release use?',
    String secretQuestion = '',
    String firstHeader = 'Provider',
  }) {
    return ThreadToolUserInputView(
      interactionId: 'tool-interaction:call-1',
      questions: [
        UserQuestionView(
          id: 'account',
          header: firstHeader,
          question: firstQuestion,
          isOther: true,
          isSecret: false,
          options: const [
            UserQuestionOptionView(
              label: 'anthropic',
              description: 'Verify the Claude route',
            ),
          ],
        ),
        UserQuestionView(
          id: 'token',
          header: 'Token',
          question: secretQuestion,
          isOther: true,
          isSecret: true,
          options: const [],
        ),
      ],
      state: state,
    );
  }

  test('待回答投影不冒充已回答，并按原顺序保留问题', () {
    final part = toolItem(
      userInput: userInput(
        state: const PendingThreadToolUserInputView(),
        firstQuestion: 'Which account?',
        secretQuestion: 'Paste the token',
      ),
    ).tool;

    final projected = part?.userInput;
    expect(projected, isNotNull);
    expect(projected!.isResolved, isFalse);
    expect(projected.answers, isEmpty);
    expect(projected.questions.map((question) => question.id), [
      'account',
      'token',
    ]);
    expect(projected.questions.first.question, 'Which account?');
    expect(projected.questions.last.isSecret, isTrue);
  });

  test('取消的问答只表达取消事实', () {
    final projected = toolItem(
      userInput: userInput(state: const CancelledThreadToolUserInputView()),
    ).tool?.userInput;

    expect(projected?.isResolved, isFalse);
    expect(projected?.state, isA<CancelledThreadToolUserInputView>());
    expect(projected?.answers, isEmpty);
  });

  test('权威更新按字段身份恢复完整问题与答案正文', () {
    // 窗口本体只携带结构（正文清空），正文由字段域交付。
    final shell = toolItem(
      userInput: userInput(
        state: ResolvedThreadToolUserInputView([
          ThreadUserInputAnswerView(questionId: 'account', answers: ['']),
        ]),
        firstQuestion: '',
        secretQuestion: '',
      ),
      revision: 2,
      terminal: true,
    );
    final current = toolItem(
      userInput: userInput(
        state: const PendingThreadToolUserInputView(),
        firstQuestion: 'Which account?',
        secretQuestion: 'Paste the token',
      ),
      terminal: false,
    );

    final updated = current.applyFieldUpdates(
      fields: const [
        ThreadFieldUpdateView(
          field: ThreadToolUserInputFieldView(
            questionIndex: 0,
            part: ThreadUserInputHeaderFieldPartView(),
          ),
          change: ReplaceThreadFieldChangeView('Provider'),
        ),
        ThreadFieldUpdateView(
          field: ThreadToolUserInputFieldView(
            questionIndex: 0,
            part: ThreadUserInputQuestionFieldPartView(),
          ),
          change: ReplaceThreadFieldChangeView('Which account?'),
        ),
        ThreadFieldUpdateView(
          field: ThreadToolUserInputFieldView(
            questionIndex: 0,
            part: ThreadUserInputAnswerFieldPartView(0),
          ),
          change: ReplaceThreadFieldChangeView('anthropic'),
        ),
        ThreadFieldUpdateView(
          field: ThreadToolUserInputFieldView(
            questionIndex: 0,
            part: ThreadUserInputOptionLabelFieldPartView(0),
          ),
          change: ReplaceThreadFieldChangeView('anthropic'),
        ),
        ThreadFieldUpdateView(
          field: ThreadToolUserInputFieldView(
            questionIndex: 0,
            part: ThreadUserInputOptionDescriptionFieldPartView(0),
          ),
          change: ReplaceThreadFieldChangeView('Verify the Claude route'),
        ),
      ],
      expectedRevision: 1,
      revision: 2,
      omittedUnits: 0,
      saved: true,
      terminal: true,
      itemShell: shell,
    );

    final projected = updated?.tool?.userInput;
    expect(projected, isNotNull);
    expect(projected!.isResolved, isTrue);
    expect(projected.headerText(0), 'Provider');
    expect(projected.questionText(0), 'Which account?');
    expect(projected.answerText(0, 0), 'anthropic');
    expect(projected.optionLabel(0, 0), 'anthropic');
    expect(projected.optionDescription(0, 0), 'Verify the Claude route');
    expect(updated?.revision, 2);
    expect(updated?.state, isA<ThreadToolItemStateView>());
  });

  test('第二段正文变化只替换对应字段并保留其它正文', () {
    final current = toolItem(
      userInput: userInput(
        state: ResolvedThreadToolUserInputView([
          ThreadUserInputAnswerView(
            questionId: 'account',
            answers: ['anthropic'],
          ),
        ]),
        firstQuestion: 'Which account?',
      ),
      revision: 3,
    );

    final updated = current.applyFieldUpdates(
      fields: const [
        ThreadFieldUpdateView(
          field: ThreadToolUserInputFieldView(
            questionIndex: 0,
            part: ThreadUserInputAnswerFieldPartView(0),
          ),
          change: ReplaceThreadFieldChangeView('openai\nand a second line'),
        ),
      ],
      expectedRevision: 3,
      revision: 4,
      omittedUnits: 0,
      saved: false,
      terminal: false,
    );

    final projected = updated?.tool?.userInput;
    expect(projected?.answerText(0, 0), 'openai\nand a second line');
    // 未被这次更新点名的正文保持原样，问答结构也不因字段变化重建。
    expect(projected?.questionText(0), 'Which account?');
    expect(projected?.headerText(0), 'Provider');
    expect(projected?.optionLabel(0, 0), 'anthropic');
    expect(projected?.questions.map((question) => question.id), [
      'account',
      'token',
    ]);
  });

  test('答案正文不能把待回答或取消的问答变成已回答', () {
    for (final pending in [
      const PendingThreadToolUserInputView(),
      const CancelledThreadToolUserInputView(),
    ]) {
      final item = toolItem(
        userInput: userInput(state: pending, firstQuestion: 'Which account?'),
      );
      final updated = item.applyFieldUpdates(
        fields: const [
          ThreadFieldUpdateView(
            field: ThreadToolUserInputFieldView(
              questionIndex: 0,
              part: ThreadUserInputAnswerFieldPartView(0),
            ),
            change: ReplaceThreadFieldChangeView('anthropic'),
          ),
        ],
        expectedRevision: 1,
        revision: 2,
        omittedUnits: 0,
        saved: true,
        terminal: false,
      );

      final projected = updated?.tool?.userInput;
      // 状态是权威事实：一段答案正文不得改写它。
      expect(projected?.isResolved, isFalse);
      expect(projected?.state.runtimeType, pending.runtimeType);
      expect(projected?.answers, isEmpty);
      expect(projected?.answerText(0, 0), '');
    }
  });

  test('敏感回答只暴露已回答/已隐藏状态', () {
    final projected = toolItem(
      userInput: userInput(
        state: const ResolvedThreadToolUserInputView([
          ThreadUserInputAnswerView(
            questionId: 'account',
            answers: ['anthropic'],
          ),
          ThreadUserInputAnswerView(questionId: 'token', redacted: true),
        ]),
      ),
    ).tool?.userInput;

    final secret = projected!.answers.firstWhere(
      (answer) => answer.questionId == 'token',
    );
    expect(secret.redacted, isTrue);
    expect(secret.answers, isEmpty);
    expect(projected.answerText(1, 0), '');
  });

  test('问答正文随条目省略量一起交付，省略提示不被丢弃', () {
    final item = toolItem(
      userInput: userInput(
        state: ResolvedThreadToolUserInputView([
          ThreadUserInputAnswerView(questionId: 'account', answers: ['a']),
        ]),
      ),
      omittedUnits: 2048,
    );

    expect(item.bodyPreviewed, isTrue);
    expect(item.tool?.userInput?.isResolved, isTrue);
  });

  /// 计划确认复用同一条 typed 问答通道：唯一 `plan_confirmation` 问题标识计划语义，
  /// 回执的决定只来自该交互自己的答案，普通问答与它互不影响。
  group('计划确认历史回执', () {
    UserQuestionView planQuestion(String markdown) => UserQuestionView(
      id: agentSessionPlanConfirmationQuestionId,
      header: 'Plan',
      question: markdown,
      isOther: false,
      isSecret: false,
      options: const [],
    );

    ThreadToolUserInputView planInput({
      required ThreadToolUserInputStateView state,
    }) {
      return ThreadToolUserInputView(
        interactionId: 'tool-interaction:call-1',
        questions: [
          planQuestion(
            '# Delivery Blueprint\n\n## Steps\n\n1. Ship the split view.',
          ),
        ],
        state: state,
      );
    }

    test('待确认只表达等待，批准后同一条目投影为已批准且不产生反馈', () {
      final pending = toolItem(
        userInput: planInput(state: const PendingThreadToolUserInputView()),
      ).tool!.userInput!;

      final waiting = pending.planReceipt;
      expect(waiting, isNotNull);
      expect(waiting!.decision, PlanConfirmationDecisionView.pending);
      expect(waiting.title, 'Delivery Blueprint');
      expect(waiting.isResolved, isFalse);

      // 同一条目身份刷新为权威 resolved：身份不变，决定随答案改变。
      final resolved = planInput(
        state: const ResolvedThreadToolUserInputView([
          ThreadUserInputAnswerView(
            questionId: 'plan_confirmation',
            answers: [agentSessionPlanApproveAnswer],
          ),
        ]),
      );
      final approved = resolved.planReceipt;
      expect(resolved.interactionId, pending.interactionId);
      expect(approved!.decision, PlanConfirmationDecisionView.approved);
      expect(approved.feedback, isEmpty);
      expect(approved.isResolved, isTrue);
    });

    test('请求修改保留原始完整反馈，内部决定标记不进入正文', () {
      final receipt = planInput(
        state: const ResolvedThreadToolUserInputView([
          ThreadUserInputAnswerView(
            questionId: 'plan_confirmation',
            answers: [
              agentSessionPlanReviseAnswer,
              'Tighten step 2.\nKeep the delivery scope unchanged.',
            ],
          ),
        ]),
      ).planReceipt;

      expect(receipt!.decision, PlanConfirmationDecisionView.revisionRequested);
      expect(receipt.feedback, [
        'Tighten step 2.\nKeep the delivery scope unchanged.',
      ]);
    });

    test('取消与未知决定标记都不伪造批准或修改', () {
      final cancelled = planInput(
        state: const CancelledThreadToolUserInputView(),
      ).planReceipt;
      expect(cancelled!.decision, PlanConfirmationDecisionView.cancelled);
      expect(cancelled.feedback, isEmpty);

      final unknown = planInput(
        state: const ResolvedThreadToolUserInputView([
          ThreadUserInputAnswerView(
            questionId: 'plan_confirmation',
            answers: ['Unrecognized'],
          ),
        ]),
      ).planReceipt;
      expect(unknown!.decision, PlanConfirmationDecisionView.resolved);
      expect(unknown.feedback, isEmpty);
    });

    test('普通问答与不完整问题结构不构成计划回执', () {
      expect(
        toolItem(
          userInput: userInput(
            state: const ResolvedThreadToolUserInputView([
              ThreadUserInputAnswerView(questionId: 'account', answers: ['a']),
            ]),
          ),
        ).tool!.userInput!.planReceipt,
        isNull,
      );
      expect(
        ThreadToolUserInputView(
          interactionId: 'tool-interaction:call-1',
          questions: [
            planQuestion('# Only Plan'),
            const UserQuestionView(
              id: 'extra',
              header: 'Extra',
              question: 'An extra question',
              isOther: false,
              isSecret: false,
              options: [],
            ),
          ],
          state: const PendingThreadToolUserInputView(),
        ).planReceipt,
        isNull,
      );
    });
  });
}
