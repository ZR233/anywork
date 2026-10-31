import 'dart:convert';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_entry_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_markdown.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ConversationItem item({
    required String id,
    required ConversationDescriptor descriptor,
    Map<ThreadContentFieldView, String> fields = const {},
  }) {
    return ConversationItem(
      header: ConversationItemHeader(
        id: id,
        threadId: 'thread',
        turnId: 'turn',
        appendSeq: 1,
        sealedAt: 1_700_000_001,
      ),
      descriptor: descriptor,
      source: const ConversationContentSource(),
      fields: [
        for (final entry in fields.entries)
          ConversationFieldPreview(
            field: entry.key,
            text: entry.value,
            totalBytes: utf8.encode(entry.value).length,
          ),
      ],
    );
  }

  Future<void> pumpReceipt(
    WidgetTester tester, {
    required ConversationItem value,
    ConversationUserInputDescriptor? input,
    bool plan = false,
    Locale locale = const Locale('en'),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: pureStudioTheme(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: SelectionArea(
              child: TimelineQuestionReceipt(
                item: value,
                input: input,
                plan: plan,
                bodyBuilder: (item, text) => TimelineMarkdown(
                  id: 'receipt-${item.id}',
                  text: text,
                  onLink: (_) {},
                  isSafeLink: (_) => false,
                  imageBuilder: (_, _) => const SizedBox.shrink(),
                ),
                onDetail: (_, _) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('选项按答案文本标出选中，敏感回答永不渲染原文', (tester) async {
    const secret = 'hunter2-secret-token';
    final input = ConversationUserInputDescriptor(
      interactionId: 'ask-1',
      questions: const [
        ConversationQuestionDescriptor(
          id: 'q1',
          isOther: false,
          isSecret: false,
          optionCount: 2,
        ),
        ConversationQuestionDescriptor(
          id: 'q2',
          isOther: true,
          isSecret: true,
          optionCount: 0,
        ),
      ],
      state: ConversationUserInputResolved(
        answers: [
          ConversationAnswerDescriptor(
            questionId: 'q1',
            answerCount: 1,
            redacted: false,
          ),
          ConversationAnswerDescriptor(
            questionId: 'q2',
            answerCount: 1,
            redacted: false,
          ),
        ],
      ),
    );
    await pumpReceipt(
      tester,
      value: item(
        id: 'qa',
        descriptor: ConversationToolDescriptor(
          invocation: const ConversationToolInvocation(
            toolCallId: 'call',
            name: 'ask_user',
          ),
          state: ConversationToolSucceeded(
            completedAt: DateTime.utc(2026, 1, 2),
            output: ConversationToolOutputDescriptor(attachments: []),
          ),
          userInput: input,
        ),
        fields: {
          const ThreadToolUserInputFieldView(
            questionIndex: 0,
            part: ThreadUserInputHeaderFieldPartView(),
          ): 'Pick one',
          const ThreadToolUserInputFieldView(
            questionIndex: 0,
            part: ThreadUserInputQuestionFieldPartView(),
          ): 'Which option?',
          const ThreadToolUserInputFieldView(
            questionIndex: 0,
            part: ThreadUserInputOptionLabelFieldPartView(0),
          ): 'A',
          const ThreadToolUserInputFieldView(
            questionIndex: 0,
            part: ThreadUserInputOptionLabelFieldPartView(1),
          ): 'B',
          const ThreadToolUserInputFieldView(
            questionIndex: 0,
            part: ThreadUserInputAnswerFieldPartView(0),
          ): 'A',
          const ThreadToolUserInputFieldView(
            questionIndex: 1,
            part: ThreadUserInputHeaderFieldPartView(),
          ): 'Secret',
          const ThreadToolUserInputFieldView(
            questionIndex: 1,
            part: ThreadUserInputQuestionFieldPartView(),
          ): 'Provide the token',
          const ThreadToolUserInputFieldView(
            questionIndex: 1,
            part: ThreadUserInputAnswerFieldPartView(0),
          ): secret,
        },
      ),
      input: input,
    );

    await tester.tap(find.byKey(StudioDriverKeys.timelineUserInput('qa')));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.byIcon(Icons.remove), findsOneWidget);
    expect(find.text('A'), findsWidgets);
    expect(find.text(secret), findsNothing);
    expect(find.text('Sensitive answer hidden'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('只读选项不从未答、单个或多个答案猜单选多选约束', (tester) async {
    for (final count in [0, 1, 2]) {
      final input = ConversationUserInputDescriptor(
        interactionId: 'answers-$count',
        questions: const [
          ConversationQuestionDescriptor(
            id: 'choice',
            isOther: true,
            isSecret: false,
            optionCount: 2,
          ),
          ConversationQuestionDescriptor(
            id: 'free',
            isOther: true,
            isSecret: false,
            optionCount: 0,
          ),
        ],
        state: ConversationUserInputResolved(
          answers: [
            if (count > 0)
              ConversationAnswerDescriptor(
                questionId: 'choice',
                answerCount: count,
                redacted: false,
              ),
            const ConversationAnswerDescriptor(
              questionId: 'free',
              answerCount: 2,
              redacted: false,
            ),
          ],
        ),
      );
      final value = item(
        id: 'qa-$count',
        descriptor: ConversationToolDescriptor(
          invocation: const ConversationToolInvocation(
            toolCallId: 'call',
            name: 'ask_user',
          ),
          state: ConversationToolSucceeded(
            completedAt: DateTime.utc(2026),
            output: ConversationToolOutputDescriptor(attachments: []),
          ),
          userInput: input,
        ),
        fields: {
          for (var option = 0; option < 2; option++)
            ThreadToolUserInputFieldView(
              questionIndex: 0,
              part: ThreadUserInputOptionLabelFieldPartView(option),
            ): [
              'A',
              'B',
            ][option],
          for (var answer = 0; answer < count; answer++)
            ThreadToolUserInputFieldView(
              questionIndex: 0,
              part: ThreadUserInputAnswerFieldPartView(answer),
            ): [
              'A',
              'B',
            ][answer],
          for (var answer = 0; answer < 2; answer++)
            ThreadToolUserInputFieldView(
              questionIndex: 1,
              part: ThreadUserInputAnswerFieldPartView(answer),
            ): [
              'free first',
              'free second',
            ][answer],
        },
      );
      await pumpReceipt(tester, value: value, input: input);
      await tester.tap(
        find.byKey(StudioDriverKeys.timelineUserInput('qa-$count')),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check), findsNWidgets(count));
      expect(find.byIcon(Icons.remove), findsNWidgets(2 - count));
      expect(find.byIcon(Icons.radio_button_checked), findsNothing);
      expect(find.byIcon(Icons.radio_button_unchecked), findsNothing);
      expect(find.byIcon(Icons.check_box), findsNothing);
      expect(find.byIcon(Icons.check_box_outline_blank), findsNothing);
      expect(find.text('free first'), findsOneWidget);
      expect(find.text('free second'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('历史 Plan 反馈保留缩进和尾随换行并原样复制', (tester) async {
    const feedback = '    keep the first indentation\n\nlast line  \n';
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await pumpReceipt(
      tester,
      plan: true,
      value: item(
        id: 'plan-raw-feedback',
        descriptor: const ConversationPlanDescriptor(
          interactionId: 'plan-feedback',
          decision: ConversationPlanDecision.revisionRequested,
          documentVersion: 3,
        ),
        fields: {const ThreadPlanFeedbackFieldView(): feedback},
      ),
    );
    await tester.tap(
      find.byKey(StudioDriverKeys.timelinePlanReceipt('plan-raw-feedback')),
    );
    await tester.pumpAndSettle();
    final body = find.byKey(
      const ValueKey('plain-text-plan-raw-feedback-plan-feedback-0'),
    );
    expect(tester.widget<Text>(body).data, feedback);
    final selection = tester.state<SelectableRegionState>(
      find.byType(SelectableRegion),
    );
    selection.selectAll(SelectionChangedCause.keyboard);
    await tester.pump();
    final copy = selection.contextMenuButtonItems
        .firstWhere((item) => item.type == ContextMenuButtonType.copy)
        .onPressed;
    expect(copy, isNotNull);
    copy!();
    await tester.pump();
    expect(copied, feedback);
    expect(tester.takeException(), isNull);
  });

  testWidgets('历史 Plan 卡按当时 descriptor 映射修订，不渲染内部标记', (tester) async {
    await pumpReceipt(
      tester,
      locale: const Locale('zh'),
      plan: true,
      value: item(
        id: 'plan-revise',
        descriptor: const ConversationPlanDescriptor(
          interactionId: 'plan-1',
          decision: ConversationPlanDecision.revisionRequested,
          documentVersion: 3,
        ),
        fields: {
          const ThreadPlanDocumentFieldView(): '# Plan title\n\n- step one',
          const ThreadPlanFeedbackFieldView(): '请补充回滚步骤',
        },
      ),
    );

    expect(find.text('已请求修改计划'), findsOneWidget);
    expect(find.text('计划已批准'), findsNothing);
    await tester.tap(
      find.byKey(StudioDriverKeys.timelinePlanReceipt('plan-revise')),
    );
    await tester.pumpAndSettle();
    expect(find.text('请补充回滚步骤'), findsOneWidget);
    expect(find.text(agentSessionPlanReviseAnswer), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未知回答不猜批准，且不渲染内部标记', (tester) async {
    await pumpReceipt(
      tester,
      plan: true,
      value: item(
        id: 'plan-resolved',
        descriptor: const ConversationPlanDescriptor(
          interactionId: 'plan-1',
          decision: ConversationPlanDecision.resolved,
        ),
        fields: {
          const ThreadPlanDocumentFieldView(): '# Plan title\n\n- step one',
        },
      ),
    );

    expect(find.text('Plan confirmation answered'), findsOneWidget);
    expect(find.text('Plan approved'), findsNothing);
    await tester.tap(
      find.byKey(StudioDriverKeys.timelinePlanReceipt('plan-resolved')),
    );
    await tester.pumpAndSettle();
    expect(find.text('maybe-later'), findsNothing);
    expect(find.text(agentSessionPlanApproveAnswer), findsNothing);
  });

  testWidgets('ConversationPlanDescriptor 使用当时文档字段，不渲染机器标记', (tester) async {
    await pumpReceipt(
      tester,
      locale: const Locale('zh'),
      plan: true,
      value: item(
        id: 'plan-item',
        descriptor: const ConversationPlanDescriptor(
          interactionId: 'plan-1',
          decision: ConversationPlanDecision.revisionRequested,
          documentVersion: 7,
        ),
        fields: {
          const ThreadPlanDocumentFieldView():
              '# Delivery Blueprint\n\nKeep the current draft readable.',
          const ThreadPlanFeedbackFieldView(): '请补充回滚步骤',
        },
      ),
    );

    expect(
      find.byKey(StudioDriverKeys.timelinePlanReceipt('plan-item')),
      findsOneWidget,
    );
    expect(find.text('已请求修改计划'), findsOneWidget);
    expect(find.text('计划已批准'), findsNothing);
    await tester.tap(
      find.byKey(StudioDriverKeys.timelinePlanReceipt('plan-item')),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Keep the current draft readable.'),
      findsOneWidget,
    );
    expect(find.text('请补充回滚步骤'), findsOneWidget);
    expect(find.text(agentSessionPlanReviseAnswer), findsNothing);
  });
}
