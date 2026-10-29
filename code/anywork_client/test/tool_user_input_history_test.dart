import 'dart:convert';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/timeline_transport.dart';

void main() {
  ConversationItem questionItem({
    ConversationUserInputState state = const ConversationUserInputPending(),
    List<ConversationFieldPreview> fields = const [],
    int revision = 1,
  }) => ConversationItem(
    header: timelineItem(1).header,
    revision: revision,
    descriptor: ConversationToolDescriptor(
      invocation: const ConversationToolInvocation(
        toolCallId: 'call',
        name: 'request_user_input',
      ),
      state: const ConversationToolRunning(),
      userInput: ConversationUserInputDescriptor(
        interactionId: 'interaction',
        questions: const [
          ConversationQuestionDescriptor(
            id: 'account',
            isOther: true,
            isSecret: false,
            optionCount: 1,
          ),
          ConversationQuestionDescriptor(
            id: 'token',
            isOther: true,
            isSecret: true,
            optionCount: 0,
          ),
        ],
        state: state,
      ),
    ),
    saved: false,
    lifecycle: ConversationLifecycle.streaming,
    fields: fields,
  );
  const question = ThreadToolUserInputFieldView(
    questionIndex: 0,
    part: ThreadUserInputQuestionFieldPartView(),
  );
  const answer = ThreadToolUserInputFieldView(
    questionIndex: 0,
    part: ThreadUserInputAnswerFieldPartView(0),
  );

  test('typed question order, pending/cancelled and None versus zero options remain distinct', () {
    final pending =
        (questionItem().descriptor as ConversationToolDescriptor).userInput!;
    expect(pending.questions.map((q) => q.id), ['account', 'token']);
    expect(pending.state, isA<ConversationUserInputPending>());
    expect(pending.questions.last.isSecret, isTrue);
    expect(pending.questions.last.optionCount, 0);
    expect(
      const ConversationQuestionDescriptor(
        id: 'free',
        isOther: true,
        isSecret: false,
      ).optionCount,
      isNull,
    );
    expect(
      (questionItem(state: const ConversationUserInputCancelled()).descriptor
              as ConversationToolDescriptor)
          .userInput!
          .state,
      isA<ConversationUserInputCancelled>(),
    );
  });

  test('question, option and answer values are field-addressable and an atomic descriptor update carries redaction', () async {
    final fixture = ConversationFixture();
    final content = fixture.session().content;
    final initial = questionItem(
      fields: const [
        ConversationFieldPreview(
          field: question,
          text: 'Which?',
          totalBytes: 6,
        ),
      ],
    );
    final resolved = questionItem(
      revision: 2,
      state: const ConversationUserInputResolved(
        answers: [
          ConversationAnswerDescriptor(
            questionId: 'account',
            answerCount: 1,
            redacted: false,
          ),
          ConversationAnswerDescriptor(
            questionId: 'token',
            answerCount: 0,
            redacted: true,
          ),
        ],
      ),
    );
    final next = content.reduceItem(
      initial,
      ConversationUpdateItem(
        itemId: 'item',
        expectedRevision: 1,
        revision: 2,
        saved: true,
        lifecycle: ConversationLifecycle.terminal,
        descriptor: resolved.descriptor,
        fields: const [
          ConversationFieldUpdate(
            field: question,
            change: ReplaceThreadFieldChangeView('Which?\n'),
            totalBytes: 7,
            previewBytes: 7,
          ),
          ConversationFieldUpdate(
            field: answer,
            change: ReplaceThreadFieldChangeView('provider'),
            totalBytes: 8,
            previewBytes: 8,
          ),
          ConversationFieldUpdate(
            field: ThreadToolUserInputFieldView(
              questionIndex: 0,
              part: ThreadUserInputOptionLabelFieldPartView(0),
            ),
            change: ReplaceThreadFieldChangeView('Keep'),
            totalBytes: 4,
            previewBytes: 4,
          ),
        ],
      ),
    );
    expect(next.fieldFor(question)!.text, 'Which?\n');
    expect(
      next
          .fieldFor(
            const ThreadToolUserInputFieldView(
              questionIndex: 0,
              part: ThreadUserInputAnswerFieldPartView(0),
            ),
          )!
          .text,
      'provider',
    );
    final descriptors =
        ((next.descriptor as ConversationToolDescriptor).userInput!.state
                as ConversationUserInputResolved)
            .answers;
    expect(descriptors.last.redacted, isTrue);
    expect(descriptors.last.answerCount, 0);
    expect(next.saved, isTrue);
    expect(next.omittedBytes, 0);
    await fixture.close();
  });

  test('plan decisions preserve feedback, hide secret answers and ignore tool output artifacts', () async {
    final fixture = ConversationFixture();
    final content = fixture.session().content;
    const label = ThreadToolUserInputFieldView(
      questionIndex: 0,
      part: ThreadUserInputOptionLabelFieldPartView(0),
    );
    ConversationItem planItem(
      String decision, {
      bool redacted = false,
      bool secret = false,
      String toolName = 'plan_submit',
      ConversationUserInputState? inputState,
    }) {
      ConversationFieldPreview field(
        ThreadContentFieldView identity,
        String text,
      ) => ConversationFieldPreview(
        field: identity,
        text: text,
        totalBytes: utf8.encode(text).length,
      );
      return ConversationItem(
        header: timelineItem(1).header,
        revision: 1,
        descriptor: ConversationToolDescriptor(
          invocation: ConversationToolInvocation(
            toolCallId: 'plan',
            name: toolName,
          ),
          state: const ConversationToolRunning(),
          userInput: ConversationUserInputDescriptor(
            interactionId: 'plan-confirmation',
            questions: [
              ConversationQuestionDescriptor(
                id: agentSessionPlanConfirmationQuestionId,
                isOther: true,
                isSecret: secret,
                optionCount: 1,
              ),
            ],
            state:
                inputState ??
                ConversationUserInputResolved(
                  answers: [
                    ConversationAnswerDescriptor(
                      questionId: agentSessionPlanConfirmationQuestionId,
                      answerCount: 2,
                      redacted: redacted,
                    ),
                  ],
                ),
          ),
        ),
        saved: true,
        lifecycle: ConversationLifecycle.terminal,
        fields: [
          field(question, '# Plan title\n\n原始正文\n'),
          field(label, decision),
          field(answer, decision),
          field(
            const ThreadToolUserInputFieldView(
              questionIndex: 0,
              part: ThreadUserInputAnswerFieldPartView(1),
            ),
            '  保留原反馈\n',
          ),
          field(
            const ThreadToolOutputArtifactsFieldView(),
            '{not a ThreadItem}',
          ),
        ],
      );
    }

    final value = planItem(agentSessionPlanReviseAnswer);
    final merged = content.mergeItem(value, value);
    expect(merged.fieldFor(label)!.text, agentSessionPlanReviseAnswer);
    expect(merged.fieldFor(answer)!.text, agentSessionPlanReviseAnswer);
    expect(merged.planReceipt!.title, 'Plan title');
    expect(
      merged.planReceipt!.decision,
      PlanConfirmationDecisionView.revisionRequested,
    );
    expect(merged.planReceipt!.feedback, ['  保留原反馈\n']);
    expect(
      planItem(
        agentSessionPlanApproveAnswer,
        inputState: const ConversationUserInputPending(),
      ).planReceipt!.decision,
      PlanConfirmationDecisionView.pending,
    );
    expect(
      planItem(
        agentSessionPlanApproveAnswer,
        inputState: const ConversationUserInputCancelled(),
      ).planReceipt!.decision,
      PlanConfirmationDecisionView.cancelled,
    );
    expect(
      planItem(agentSessionPlanApproveAnswer).planReceipt!.decision,
      PlanConfirmationDecisionView.approved,
    );
    expect(
      planItem(agentSessionPlanApproveAnswer).planReceipt!.feedback,
      isEmpty,
    );
    for (final hidden in [
      planItem(agentSessionPlanReviseAnswer, redacted: true),
      planItem(agentSessionPlanReviseAnswer, secret: true),
    ]) {
      expect(
        hidden.planReceipt!.decision,
        PlanConfirmationDecisionView.resolved,
      );
      expect(hidden.planReceipt!.feedback, isEmpty);
    }
    for (final toolName in ['ask_user', 'request_user_input']) {
      for (final inputState in [
        const ConversationUserInputPending(),
        const ConversationUserInputResolved(
          answers: [
            ConversationAnswerDescriptor(
              questionId: agentSessionPlanConfirmationQuestionId,
              answerCount: 2,
              redacted: false,
            ),
          ],
        ),
      ]) {
        final ordinary = planItem(
          agentSessionPlanReviseAnswer,
          toolName: toolName,
          inputState: inputState,
        );
        expect(
          ordinary.planReceipt,
          isNull,
          reason: 'A reserved question ID does not give an ordinary tool plan ownership',
        );
        expect(ordinary.userInput, isNotNull);
        expect(
          ordinary.userInputText(
            0,
            const ThreadUserInputQuestionFieldPartView(),
          ),
          '# Plan title\n\n原始正文\n',
        );
        expect(ordinary.fieldFor(answer)!.text, agentSessionPlanReviseAnswer);
      }
    }
    expect(questionItem().planReceipt, isNull);
    expect(
      merged.fieldFor(const ThreadToolOutputArtifactsFieldView())!.text,
      '{not a ThreadItem}',
    );
    await fixture.close();
  });

  test(
    'known tool display strings require complete current arguments previews',
    () {
      ConversationItem toolItem(
        String tool,
        String arguments, {
        int omittedBytes = 0,
      }) => ConversationItem(
        header: timelineItem(1).header,
        revision: 1,
        descriptor: ConversationToolDescriptor(
          invocation: ConversationToolInvocation(
            toolCallId: 'image',
            name: tool,
          ),
          state: const ConversationToolRunning(),
        ),
        saved: false,
        lifecycle: ConversationLifecycle.streaming,
        fields: [
          ConversationFieldPreview(
            field: const ThreadToolArgumentsFieldView(),
            text: arguments,
            totalBytes: utf8.encode(arguments).length + omittedBytes,
          ),
        ],
      );

      expect(
        toolItem(
          'show_image',
          jsonEncode({'caption': '  说明 😀  '}),
        ).imageCardCaption,
        '说明 😀',
      );
      final long = '😀' * 241;
      final bounded = toolItem(
        'show_image',
        jsonEncode({'caption': long}),
      ).imageCardCaption!;
      expect(bounded.runes.length, 240);
      expect(bounded, '😀' * 240);
      for (final item in [
        toolItem('other_tool', jsonEncode({'caption': 'hidden'})),
        toolItem('show_image', '{"caption":"truncated'),
        toolItem('show_image', jsonEncode(['not', 'object'])),
        toolItem('show_image', jsonEncode({'caption': 7})),
        toolItem('show_image', jsonEncode({'caption': '  '})),
        toolItem(
          'show_image',
          jsonEncode({'caption': 'visible'}),
          omittedBytes: 1,
        ),
      ]) {
        expect(item.imageCardCaption, isNull);
      }
    },
  );
}
