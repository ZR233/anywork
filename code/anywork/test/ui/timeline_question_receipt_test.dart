import 'dart:convert';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_feed_body_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_feed_projection.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> pumpReceipt(
    WidgetTester tester,
    ChatItemPresentation item, {
    double width = 600,
    Widget Function(Widget)? wrap,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: pureStudioTheme(),
      locale: const Locale('zh'),
      localizationsDelegates: [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: width,
            child: (wrap ?? (child) => child)(
              ChatItemView(
                item: item,
                bodyBuilder: (id, text) =>
                    SelectionArea(child: Text(text, key: ValueKey(id))),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  ChatItemPresentation receipt({
    bool cancelled = false,
    bool reverseAnswers = false,
    int optionCount = 2,
    int answerCount = 2,
  }) => chatPresentation(
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
          {'id': 'public-q', 'isSecret': false, 'optionCount': optionCount},
          {'id': 'secret-q', 'isSecret': true, 'optionCount': 0},
        ],
        'state': {
          'kind': cancelled ? 'cancelled' : 'resolved',
          'answers': [
            if (reverseAnswers)
              {'questionId': 'secret-q', 'answerCount': 1, 'redacted': true},
            {
              'questionId': 'public-q',
              'answerCount': answerCount,
              'redacted': false,
            },
            if (!reverseAnswers)
              {'questionId': 'secret-q', 'answerCount': 1, 'redacted': true},
          ],
        },
      },
    },
    bodies: [
      inlineBody('tool.arguments', '{}'),
      inlineBody('tool.user-input.question.0.header', '公开问题'),
      inlineBody('tool.user-input.question.0.body', 'Which option?'),
      inlineBody('tool.user-input.question.0.option.0.label', 'Option A'),
      inlineBody('tool.user-input.question.0.option.1.label', 'Option B'),
      inlineBody('tool.user-input.answer.0.0', 'Option A'),
      inlineBody('tool.user-input.answer.0.1', 'free second'),
      inlineBody('tool.user-input.question.1.header', 'PRIVATE HEADER'),
      inlineBody('tool.user-input.question.1.body', 'PRIVATE QUESTION'),
      inlineBody('tool.user-input.answer.1.0', 'secret-token-must-not-render'),
    ],
  );

  testWidgets(
    'expanding a historical receipt reads public fields and never secret bodies',
    (tester) async {
      final inline = receipt();
      final bodies = {for (final body in inline.bodies) body.key: body.inline!};
      final refs = [
        for (final entry in bodies.entries)
          BodyRef(
            databaseId: 'db',
            ownerEventId: 'event',
            bodyKey: entry.key,
            bodyId: 'body-${entry.key}',
            role: 'body',
            byteLength: entry.value.length,
          ),
      ];
      final item = chatItemPresentationOf(
        timelineFeedMessage(
          TimelineStandaloneTool(
            id: 'qa',
            seq: 1,
            callId: 'call',
            toolName: 'request_user_input',
            state: 'succeeded',
            summary: 'Question receipt',
            presentationContract: 'generic@1',
            bodies: refs,
            payloadJson: jsonEncode({
              'contract': 'anywork.event/1',
              'type': inline.type,
              'data': inline.data,
            }),
          ),
        ),
      )!;
      final reads = <String>[];
      final identity = Object();
      await pumpReceipt(
        tester,
        item,
        wrap: (child) => TimelineFeedContent(
          identity: identity,
          isActive: () => true,
          readBodyWindow:
              (reference, {required offset, required maxBytes}) async {
                expect(reference.ownerEventId, 'event');
                expect(offset, 0);
                reads.add(reference.bodyKey);
                final bytes = bodies[reference.bodyKey]!;
                return BodyWindow(
                  offset: 0,
                  text: utf8.decode(bytes),
                  totalBytes: bytes.length,
                  eof: true,
                );
              },
          child: child,
        ),
      );
      await tester.pumpAndSettle();
      expect(reads, isEmpty);
      await tester.tap(find.byKey(StudioDriverKeys.timelineUserInput('qa')));
      await tester.pumpAndSettle();
      expect(find.text('公开问题'), findsOneWidget);
      expect(find.text('Which option?'), findsOneWidget);
      expect(find.text('Option A'), findsNWidgets(2));
      expect(find.text('Option B'), findsOneWidget);
      expect(find.text('free second'), findsOneWidget);
      expect(find.text('敏感内容已隐藏'), findsOneWidget);
      expect(
        reads,
        unorderedEquals([
          'tool.user-input.question.0.header',
          'tool.user-input.question.0.body',
          'tool.user-input.question.0.option.0.label',
          'tool.user-input.question.0.option.1.label',
          'tool.user-input.answer.0.0',
          'tool.user-input.answer.0.1',
        ]),
      );
      expect(find.textContaining('PRIVATE'), findsNothing);
      expect(find.textContaining('secret-token'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  for (final reversed in [false, true]) {
    testWidgets(
      'questionId links answers with redaction even when answer order reversed=$reversed',
      (tester) async {
        await pumpReceipt(tester, receipt(reverseAnswers: reversed));
        final receiptHeader = find.byKey(
          StudioDriverKeys.timelineUserInput('qa'),
        );
        expect(receiptHeader, findsOneWidget);
        expect(find.text('公开问题'), findsNothing);
        await tester.tap(receiptHeader);
        await tester.pumpAndSettle();
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
    'cancelled receipt stays read-only without overflow in a narrow viewport',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpReceipt(tester, receipt(cancelled: true), width: 280);
      expect(
        find.descendant(
          of: find.byKey(StudioDriverKeys.timelineUserInput('qa')),
          matching: find.textContaining('问答已取消'),
        ),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (options, answers) in [
    (-1, 2),
    (1 << 30, 2),
    (2, -1),
    (2, 1 << 30),
  ]) {
    testWidgets(
      'invalid counts ($options options, $answers answers) report malformed content before building',
      (tester) async {
        await pumpReceipt(
          tester,
          receipt(optionCount: options, answerCount: answers),
        );
        expect(find.text('内容格式错误'), findsOneWidget);
        expect(
          find.byKey(StudioDriverKeys.timelineUserInput('qa')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final optionCount in <int?>[null, 0]) {
    testWidgets(
      'ordinary question titled Plan with optionCount=$optionCount is not a plan decision',
      (tester) async {
        final ordinary = chatPresentation(
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
                {
                  'id': 'ordinary-q',
                  'isSecret': false,
                  'optionCount': optionCount,
                },
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
            inlineBody('tool.user-input.question.0.body', 'An ordinary prompt'),
          ],
        );
        await pumpReceipt(tester, ordinary);
        expect(find.text('Plan approval question'), findsNothing);
        await tester.tap(
          find.byKey(StudioDriverKeys.timelineUserInput('ordinary')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Plan approval question'), findsOneWidget);
        expect(find.text('An ordinary prompt'), findsOneWidget);
        expect(find.text('可选项'), findsNothing);
        expect(find.text('计划已批准'), findsNothing);
        expect(find.text('已请求修改计划'), findsNothing);
      },
    );
  }

  for (final (decision, label) in [
    ('revisionRequested', '已请求修改计划'),
    ('resolved', '计划确认已回答'),
  ]) {
    testWidgets(
      'frozen $decision displays its own document and feedback without machine markers',
      (tester) async {
        final item = chatPresentation(
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
        );
        await pumpReceipt(tester, item);
        expect(find.textContaining(label), findsOneWidget);
        expect(
          find.textContaining('Keep the current draft readable.'),
          findsNothing,
        );
        await tester.tap(find.textContaining(label));
        await tester.pumpAndSettle();
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
        chatPresentation(
          'plan-feedback',
          type: 'plan',
          data: const {'decision': 'revisionRequested'},
          bodies: [inlineBody('plan.feedback', feedback)],
        ),
      );
      await tester.tap(find.text('已请求修改计划'));
      await tester.pumpAndSettle();
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
