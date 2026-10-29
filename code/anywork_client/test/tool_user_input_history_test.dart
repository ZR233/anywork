import 'dart:convert';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/timeline_transport.dart';

void main() {
  test(
    'completed questions retain ordering, identity, answers and redaction',
    () async {
      final fixture = ConversationFixture();
      final feed = await fixture.open();
      const question = ThreadToolUserInputFieldView(
        questionIndex: 0,
        part: ThreadUserInputQuestionFieldPartView(),
      );
      const answer = ThreadToolUserInputFieldView(
        questionIndex: 0,
        part: ThreadUserInputAnswerFieldPartView(0),
      );
      final item = ConversationItem(
        header: const ConversationItemHeader(
          id: 'question',
          threadId: 'thread',
          appendSeq: 2,
        ),
        source: const ConversationContentSource(),
        descriptor: ConversationToolDescriptor(
          invocation: const ConversationToolInvocation(
            toolCallId: 'call',
            name: 'request_user_input',
          ),
          state: ConversationToolSucceeded(
            completedAt: DateTime.utc(2026),
            output: ConversationToolOutputDescriptor(attachments: const []),
          ),
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
              ConversationQuestionDescriptor(
                id: 'free',
                isOther: true,
                isSecret: false,
              ),
            ],
            state: ConversationUserInputResolved(
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
          ),
        ),
        fields: const [
          ConversationFieldPreview(
            field: question,
            text: 'Which?\n',
            totalBytes: 7,
          ),
          ConversationFieldPreview(
            field: answer,
            text: 'provider',
            totalBytes: 8,
          ),
          ConversationFieldPreview(
            field: ThreadToolUserInputFieldView(
              questionIndex: 0,
              part: ThreadUserInputOptionLabelFieldPartView(0),
            ),
            text: 'Keep',
            totalBytes: 4,
          ),
        ],
      );
      await feed.deliver(
        ConversationUpdateEvent(
          update: ConversationBatch(
            subscriptionId: 'sub',
            timelineEpoch: 'epoch',
            fromSeq: 1,
            throughSeq: 2,
            items: [item],
          ),
        ),
      );
      final delivered =
          (fixture.consumers['thread']!.frames.last
                  as ConversationCompletedBatchFrame)
              .batch
              .items
              .single;
      final input =
          (delivered.descriptor as ConversationToolDescriptor).userInput!;
      expect(input.interactionId, 'interaction');
      expect(input.questions.map((q) => q.id), ['account', 'token', 'free']);
      expect(input.questions[1].isSecret, isTrue);
      expect(input.questions[1].optionCount, 0);
      expect(input.questions[2].optionCount, isNull);
      final answers = (input.state as ConversationUserInputResolved).answers;
      expect(answers.map((a) => a.questionId), ['account', 'token']);
      expect(answers.last.redacted, isTrue);
      expect(answers.last.answerCount, 0);
      expect(delivered.fieldFor(question)!.text, 'Which?\n');
      expect(delivered.fieldFor(answer)!.text, 'provider');
      expect(
        delivered.fieldFor(
          const ThreadToolUserInputFieldView(
            questionIndex: 1,
            part: ThreadUserInputAnswerFieldPartView(0),
          ),
        ),
        isNull,
      );
      expect(delivered.planReceipt, isNull);
      expect((await fixture.close()).complete, isTrue);
    },
  );

  test('typed Plan decision uses its own document and feedback, not tool artifacts', () {
    ConversationItem plan(
      ConversationPlanDecision decision, {
      String? feedback,
    }) => ConversationItem(
      header: timelineItem(1).header,
      source: const ConversationContentSource(),
      descriptor: ConversationPlanDescriptor(
        interactionId: 'plan-confirmation',
        decision: decision,
      ),
      fields: [
        const ConversationFieldPreview(
          field: ThreadPlanDocumentFieldView(),
          text: '# Plan title\n',
          totalBytes: 13,
        ),
        if (feedback != null)
          ConversationFieldPreview(
            field: const ThreadPlanFeedbackFieldView(),
            text: feedback,
            totalBytes: utf8.encode(feedback).length,
          ),
        const ConversationFieldPreview(
          field: ThreadToolOutputArtifactsFieldView(),
          text: 'ignored',
          totalBytes: 7,
        ),
      ],
    );
    final revised = plan(
      ConversationPlanDecision.revisionRequested,
      feedback: '  保留原反馈\n',
    ).planReceipt!;
    expect(revised.interactionId, 'plan-confirmation');
    expect(revised.title, 'Plan title');
    expect(revised.decision, PlanConfirmationDecisionView.revisionRequested);
    expect(revised.feedback, ['  保留原反馈\n']);
    expect(
      plan(ConversationPlanDecision.approved).planReceipt!.decision,
      PlanConfirmationDecisionView.approved,
    );
    expect(
      plan(ConversationPlanDecision.cancelled).planReceipt!.decision,
      PlanConfirmationDecisionView.cancelled,
    );
    expect(
      plan(ConversationPlanDecision.resolved).planReceipt!.decision,
      PlanConfirmationDecisionView.resolved,
    );
    expect(
      plan(ConversationPlanDecision.approved).planReceipt!.feedback,
      isEmpty,
    );
  });

  test('known tool display strings require complete arguments previews', () {
    ConversationItem tool(String name, String arguments, {int omitted = 0}) =>
        ConversationItem(
          header: timelineItem(1).header,
          source: const ConversationContentSource(),
          descriptor: ConversationToolDescriptor(
            invocation: ConversationToolInvocation(
              toolCallId: 'image',
              name: name,
            ),
            state: ConversationToolSucceeded(
              completedAt: DateTime.utc(2026),
              output: ConversationToolOutputDescriptor(attachments: const []),
            ),
          ),
          fields: [
            ConversationFieldPreview(
              field: const ThreadToolArgumentsFieldView(),
              text: arguments,
              totalBytes: utf8.encode(arguments).length + omitted,
            ),
          ],
        );
    expect(
      tool('show_image', jsonEncode({'caption': '  说明 😀  '})).imageCardCaption,
      '说明 😀',
    );
    expect(
      tool('show_image', jsonEncode({'caption': '😀' * 241})).imageCardCaption,
      '😀' * 240,
    );
    for (final item in [
      tool('other', jsonEncode({'caption': 'hidden'})),
      tool('show_image', '{"caption":"truncated'),
      tool('show_image', jsonEncode(['bad'])),
      tool('show_image', jsonEncode({'caption': 7})),
      tool('show_image', jsonEncode({'caption': '  '})),
      tool('show_image', jsonEncode({'caption': 'visible'}), omitted: 1),
    ]) {
      expect(item.imageCardCaption, isNull);
    }
  });
}
