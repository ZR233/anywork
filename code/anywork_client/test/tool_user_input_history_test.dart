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
    String firstQuestion = 'Which provider should the release use?',
    String secretQuestion = '',
    String firstHeader = 'Provider',
  }) {
    return ThreadToolUserInputView(
      interactionId: 'tool-interaction:call-1',
      questions: [
        UserQuestionView(
          id: 'provider',
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
        firstQuestion: 'Which provider?',
        secretQuestion: 'Paste the token',
      ),
    ).tool;

    final projected = part?.userInput;
    expect(projected, isNotNull);
    expect(projected!.isResolved, isFalse);
    expect(projected.answers, isEmpty);
    expect(projected.questions.map((question) => question.id), [
      'provider',
      'token',
    ]);
    expect(projected.questions.first.question, 'Which provider?');
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
          ThreadUserInputAnswerView(questionId: 'provider', answers: ['']),
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
        firstQuestion: 'Which provider?',
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
          change: ReplaceThreadFieldChangeView('Which provider?'),
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
    expect(projected.questionText(0), 'Which provider?');
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
            questionId: 'provider',
            answers: ['anthropic'],
          ),
        ]),
        firstQuestion: 'Which provider?',
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
    expect(projected?.questionText(0), 'Which provider?');
    expect(projected?.headerText(0), 'Provider');
    expect(projected?.optionLabel(0, 0), 'anthropic');
    expect(projected?.questions.map((question) => question.id), [
      'provider',
      'token',
    ]);
  });

  test('答案正文不能把待回答或取消的问答变成已回答', () {
    for (final pending in [
      const PendingThreadToolUserInputView(),
      const CancelledThreadToolUserInputView(),
    ]) {
      final item = toolItem(
        userInput: userInput(state: pending, firstQuestion: 'Which provider?'),
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
            questionId: 'provider',
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
          ThreadUserInputAnswerView(questionId: 'provider', answers: ['a']),
        ]),
      ),
      omittedUnits: 2048,
    );

    expect(item.bodyPreviewed, isTrue);
    expect(item.tool?.userInput?.isResolved, isTrue);
  });
}
