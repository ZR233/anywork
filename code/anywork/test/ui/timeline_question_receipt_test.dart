import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> pumpReceipt(
    WidgetTester tester,
    ChatItemPresentation item, {
    double width = 600,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: pureStudioTheme(),
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: width,
            child: ChatItemView(
              item: item,
              bodyBuilder: (id, text) =>
                  SelectionArea(child: Text(text, key: ValueKey(id))),
            ),
          ),
        ),
      ),
    ),
  );
  ChatItemPresentation receipt({
    bool cancelled = false,
    bool reverseAnswers = false,
  }) => ChatItemPresentation.decode(
    chatEnvelope(
      'qa',
      type: 'tool',
      data: {
        'invocation': {
          'toolCallId': 'call',
          'name': 'request_user_input',
          'presentationContract': 'generic@1',
        },
        'state': {
          'kind': 'succeeded',
          'completedAt': 0,
          'output': {'attachments': []},
        },
        'userInput': {
          'interactionId': 'interaction',
          'questions': [
            {
              'id': 'public-q',
              'isSecret': false,
              'isOther': true,
              'optionCount': 2,
            },
            {
              'id': 'secret-q',
              'isSecret': true,
              'isOther': true,
              'optionCount': 0,
            },
          ],
          'state': {
            'kind': cancelled ? 'cancelled' : 'resolved',
            'answers': [
              if (reverseAnswers)
                {'questionId': 'secret-q', 'answerCount': 1, 'redacted': true},
              {'questionId': 'public-q', 'answerCount': 2, 'redacted': false},
              if (!reverseAnswers)
                {'questionId': 'secret-q', 'answerCount': 1, 'redacted': true},
            ],
          },
        },
      },
      bodies: [
        inlineBody('tool.arguments', '{}'),
        inlineBody('tool.user-input.question.0.header', '公开问题'),
        inlineBody('tool.user-input.question.0.question', 'Which option?'),
        inlineBody('tool.user-input.question.0.option.0.label', 'Option A'),
        inlineBody('tool.user-input.question.0.option.1.label', 'Option B'),
        inlineBody('tool.user-input.answer.0.0', 'Option A'),
        inlineBody('tool.user-input.answer.0.1', 'free second'),
        inlineBody('tool.user-input.question.1.header', 'PRIVATE HEADER'),
        inlineBody('tool.user-input.question.1.question', 'PRIVATE QUESTION'),
        inlineBody(
          'tool.user-input.answer.1.0',
          'secret-token-must-not-render',
        ),
      ],
    ),
  );

  for (final reversed in [false, true]) {
    testWidgets(
      'questionId links answers with redaction even when answer order reversed=$reversed',
      (tester) async {
        await pumpReceipt(tester, receipt(reverseAnswers: reversed));
        expect(find.text('公开问题'), findsOneWidget);
        expect(find.text('free second'), findsOneWidget);
        expect(find.text('敏感内容已隐藏'), findsOneWidget);
        expect(find.text('PRIVATE HEADER'), findsNothing);
        expect(find.text('PRIVATE QUESTION'), findsNothing);
        expect(find.text('secret-token-must-not-render'), findsNothing);
        // A public raw disclosure must not turn into a side channel for secret
        // manifests or the unfiltered envelope, including an unknown tool marker.
        await tester.tap(find.text('公开原始记录').first);
        await tester.pumpAndSettle();
        expect(
          find.textContaining('secret-token-must-not-render'),
          findsNothing,
        );
        expect(find.textContaining('PRIVATE HEADER'), findsNothing);
        expect(find.byType(TextField), findsNothing);
        expect(find.byType(Checkbox), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'cancelled receipt stays read-only and narrow long answers do not overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpReceipt(tester, receipt(cancelled: true), width: 280);
      expect(find.text('问答已取消'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ordinary question titled Plan is not reclassified into a plan decision',
    (tester) async {
      final ordinary = ChatItemPresentation.decode(
        chatEnvelope(
          'ordinary',
          type: 'tool',
          data: {
            'invocation': {
              'toolCallId': 'call',
              'name': 'plan',
              'presentationContract': 'generic@1',
            },
            'state': {
              'kind': 'succeeded',
              'output': {'attachments': []},
            },
            'userInput': {
              'questions': [
                {'id': 'ordinary-q', 'isSecret': false},
              ],
              'state': {'kind': 'resolved', 'answers': []},
            },
          },
          bodies: [
            inlineBody('tool.arguments', '{}'),
            inlineBody(
              'tool.user-input.question.0.header',
              'Plan approval question',
            ),
          ],
        ),
      );
      await pumpReceipt(tester, ordinary);
      expect(find.text('Plan approval question'), findsOneWidget);
      expect(find.text('计划已批准'), findsNothing);
      expect(find.text('已请求修改计划'), findsNothing);
    },
  );

  for (final (decision, label) in [
    ('revisionRequested', '已请求修改计划'),
    ('resolved', '计划确认已回答'),
  ]) {
    testWidgets(
      'frozen $decision displays its own document and feedback without machine markers',
      (tester) async {
        final item = ChatItemPresentation.decode(
          chatEnvelope(
            'plan',
            type: 'plan',
            data: {
              'interactionId': 'old-plan',
              'decision': decision,
              'documentVersion': 7,
            },
            bodies: [
              inlineBody(
                'plan.document',
                '# Delivery Blueprint\n\nKeep the current draft readable.',
              ),
              inlineBody('plan.feedback', '请补充回滚步骤'),
            ],
          ),
        );
        await pumpReceipt(tester, item);
        expect(find.text(label), findsOneWidget);
        expect(find.text('计划已批准'), findsNothing);
        expect(
          find.textContaining('Keep the current draft readable.'),
          findsOneWidget,
        );
        expect(find.text('请补充回滚步骤'), findsOneWidget);
        expect(find.text(agentSessionPlanReviseAnswer), findsNothing);
        expect(find.text(agentSessionPlanApproveAnswer), findsNothing);
      },
    );
  }

  testWidgets(
    'plan feedback preserves whitespace and clipboard contents verbatim',
    (tester) async {
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
        ChatItemPresentation.decode(
          chatEnvelope(
            'plan-feedback',
            type: 'plan',
            data: const {'decision': 'revisionRequested'},
            bodies: [inlineBody('plan.feedback', feedback)],
          ),
        ),
      );
      final rich = find.descendant(
        of: find.text(feedback),
        matching: find.byType(RichText),
      );
      final selection = tester.state<SelectableRegionState>(
        find.byType(SelectableRegion),
      );
      selection.selectAll(SelectionChangedCause.keyboard);
      await tester.pump();
      selection.contextMenuButtonItems
          .firstWhere((item) => item.type == ContextMenuButtonType.copy)
          .onPressed!();
      await tester.pump();
      expect(rich, findsOneWidget);
      expect(copied, feedback);
      expect(tester.takeException(), isNull);
    },
  );
}
