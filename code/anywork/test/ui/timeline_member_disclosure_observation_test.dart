import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_reasoning_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/timeline_observation.dart';

const _target = ValueKey('target-member');
const _unrelated = ValueKey('unrelated-member');

ChatItemPresentation _presentation(
  String type,
  String key, {
  String text = 'accepted member body',
}) => ChatItemPresentation.decode(
  ChatAtom(
    id: 'member',
    completionItemId: 'completion',
    completionSeq: 1,
    source: const ForegroundTurnChatSource(turnId: 'turn'),
    sourceOrder: 1,
    kind: type == 'thinking' ? ChatAtomKind.reasoning : ChatAtomKind.toolCall,
    delivery: ChatDeliveryKind.foreground,
    lifecycle: const TerminalChatAtom(
      started: null,
      ended: null,
      outcome: ChatTerminalOutcome.completed,
    ),
    contents: [
      ChatAtomContent(
        role: type == 'tool'
            ? ChatContentRole.toolOutput
            : key == 'part.summaryText.0'
            ? ChatContentRole.reasoningSummary
            : ChatContentRole.body,
        reference: ContentRef(
          databaseId: 'db',
          target: BodyContentTarget(
            owner: const ItemContentOwner(itemId: 'member'),
            key: key,
          ),
        ),
      ),
    ],
    payload: InlinePayload(
      bytes: utf8.encode(
        jsonEncode({
          'contract': 'anywork.chat/1',
          'type': type,
          'data': type == 'thinking'
              ? {
                  'outcome': {
                    'kind': 'completed',
                    'data': {'completedAt': 12},
                  },
                }
              : {
                  'invocation': {
                    'toolCallId': 'call',
                    'name': 'canonical-exec',
                    'presentationContract': 'generic@1',
                  },
                  'state': {
                    'kind': 'succeeded',
                    'completedAt': 12,
                    'output': {'exitCode': 0, 'attachments': []},
                  },
                },
          'bodies': [
            {
              'key': key,
              'byteLength': utf8.encode(text).length,
              'inline': utf8.encode(text),
            },
          ],
        }),
      ),
    ),
  ),
);

Widget _host(
  ValueNotifier<ChatItemPresentation?> current, {
  String pendingText = '正在读取完成内容…',
}) => MaterialApp(
  theme: pureStudioTheme(),
  locale: const Locale('zh'),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Column(
      children: [
        ValueListenableBuilder(
          valueListenable: current,
          builder: (_, item, _) => SizedBox(
            key: _target,
            child: item == null ? Text(pendingText) : ChatItemView(item: item),
          ),
        ),
        SizedBox(
          key: _unrelated,
          child: ChatItemView(item: _presentation('tool', 'tool.result')),
        ),
      ],
    ),
  ),
);

Finder _headers(Key key) => find.descendant(
  of: find.byKey(key),
  matching: find.byWidgetPredicate(
    (widget) => widget is TimelineActivityRow && widget.expandable,
  ),
);

Future<void> _expectReadabilityFailure(Future<void> action) async {
  Object? failure;
  try {
    await action;
  } catch (error) {
    failure = error;
  }
  expect(failure, isA<TestFailure>());
}

void main() {
  for (final type in ['thinking', 'tool']) {
    testWidgets('member disclosure waits for the real delayed $type control', (
      tester,
    ) async {
      final current = ValueNotifier<ChatItemPresentation?>(null);
      addTearDown(current.dispose);
      await tester.pumpWidget(_host(current));
      expect(_headers(_target), findsNothing);
      final observation = TimelineObservation(
        tester,
        () => throw StateError('The helper must not open another owner'),
      );
      final original = _presentation(
        type,
        type == 'thinking' ? 'part.reasoningText.0' : 'tool.result',
      );
      final timer = Timer(
        const Duration(milliseconds: 32),
        () => current.value = original,
      );
      addTearDown(timer.cancel);
      await observation.ensureMemberReadable(
        find.byKey(_target),
        original.atom!,
      );
      await tester.pumpAndSettle();
      expect(_headers(_target), findsOneWidget);
      expect(
        tester.widget<TimelineActivityRow>(_headers(_target)).expanded,
        isTrue,
      );
      expect(
        tester.widget<TimelineActivityRow>(_headers(_unrelated)).expanded,
        isFalse,
      );
      expect(
        find.descendant(
          of: find.byKey(_target),
          matching: find.text('accepted member body', findRichText: true),
        ),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'summary-only reasoning waits for visible canonical summary without a disclosure',
    (tester) async {
      const summary = '梳理会话共享组件与锁定边界';
      final original = _presentation(
        'thinking',
        'part.summaryText.0',
        text: summary,
      );
      final current = ValueNotifier<ChatItemPresentation?>(null);
      addTearDown(current.dispose);
      await tester.pumpWidget(_host(current));
      final observation = TimelineObservation(
        tester,
        () => throw StateError('No additional query or owner is allowed'),
      );
      final timer = Timer(
        const Duration(milliseconds: 32),
        () => current.value = original,
      );
      addTearDown(timer.cancel);
      await observation.ensureMemberReadable(
        find.byKey(_target),
        original.atom!,
      );
      final row = find.byKey(_target);
      final reasoning = find.descendant(
        of: row,
        matching: find.byType(TimelineReasoningView),
      );
      expect(reasoning, findsOneWidget);
      expect(tester.widget<TimelineReasoningView>(reasoning).body, isNull);
      expect(_headers(_target), findsNothing);
      expect(
        find.descendant(
          of: row,
          matching: find.byType(TimelineActivityDisclosure),
        ),
        findsNothing,
      );
      expect(
        find
            .descendant(
              of: row,
              matching: find.text(summary, findRichText: true),
            )
            .hitTestable(),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ChatItemView>(
              find.descendant(of: row, matching: find.byType(ChatItemView)),
            )
            .item
            .atom,
        same(original.atom),
      );
      expect(
        tester.widget<TimelineActivityRow>(_headers(_unrelated)).expanded,
        isFalse,
      );
    },
  );

  for (final placeholder in ['正在读取完成内容…', '完成内容读取失败']) {
    testWidgets(
      'summary-only reasoning rejects unresolved canonical state: $placeholder',
      (tester) async {
        final current = ValueNotifier<ChatItemPresentation?>(null);
        addTearDown(current.dispose);
        await tester.pumpWidget(_host(current, pendingText: placeholder));
        final observation = TimelineObservation(
          tester,
          () => throw StateError('No additional query is allowed'),
        );
        await _expectReadabilityFailure(
          observation.ensureMemberReadable(
            find.byKey(_target),
            _presentation('thinking', 'part.summaryText.0').atom!,
            timeout: const Duration(milliseconds: 100),
          ),
        );
      },
    );
  }

  testWidgets(
    'summary-only reasoning does not accept the empty-summary fallback',
    (tester) async {
      final original = _presentation(
        'thinking',
        'part.summaryText.0',
        text: '',
      );
      final current = ValueNotifier<ChatItemPresentation?>(original);
      addTearDown(current.dispose);
      await tester.pumpWidget(_host(current));
      final observation = TimelineObservation(
        tester,
        () => throw StateError('No additional query is allowed'),
      );
      await _expectReadabilityFailure(
        observation.ensureMemberReadable(
          find.byKey(_target),
          original.atom!,
          timeout: const Duration(milliseconds: 100),
        ),
      );
    },
  );

  testWidgets(
    'a declared reasoning Body cannot use the summary-only shortcut',
    (tester) async {
      final current = ValueNotifier<ChatItemPresentation?>(
        _presentation('thinking', 'part.summaryText.0'),
      );
      addTearDown(current.dispose);
      await tester.pumpWidget(_host(current));
      final observation = TimelineObservation(
        tester,
        () => throw StateError('No additional query is allowed'),
      );
      await _expectReadabilityFailure(
        observation.ensureMemberReadable(
          find.byKey(_target),
          _presentation('thinking', 'part.reasoningText.0').atom!,
          timeout: const Duration(milliseconds: 100),
        ),
      );
    },
  );

  for (final role in [null, ChatContentRole.toolOutput]) {
    testWidgets(
      'reasoning rejects ${role == null ? 'missing' : 'unknown'} content declarations',
      (tester) async {
        final current = ValueNotifier<ChatItemPresentation?>(
          _presentation('thinking', 'part.summaryText.0'),
        );
        addTearDown(current.dispose);
        await tester.pumpWidget(_host(current));
        final atom = ChatAtom(
          id: 'member',
          source: const ForegroundTurnChatSource(turnId: 'turn'),
          sourceOrder: 1,
          kind: ChatAtomKind.reasoning,
          delivery: ChatDeliveryKind.foreground,
          lifecycle: const TerminalChatAtom(
            started: null,
            ended: null,
            outcome: ChatTerminalOutcome.completed,
          ),
          contents: [
            if (role != null)
              ChatAtomContent(
                role: role,
                reference: const ContentRef(
                  databaseId: 'db',
                  target: ItemPayloadTarget(itemId: 'member'),
                ),
              ),
          ],
        );
        final observation = TimelineObservation(
          tester,
          () => throw StateError('No additional query is allowed'),
        );
        await _expectReadabilityFailure(
          observation.ensureMemberReadable(find.byKey(_target), atom),
        );
      },
    );
  }

  testWidgets(
    'member disclosure cannot pass if its canonical control never mounts',
    (tester) async {
      final current = ValueNotifier<ChatItemPresentation?>(null);
      addTearDown(current.dispose);
      await tester.pumpWidget(_host(current));
      expect(_headers(_target), findsNothing);
      final observation = TimelineObservation(
        tester,
        () => throw StateError('The helper must not open another owner'),
      );
      Object? failure;
      try {
        await observation.expandMemberDisclosure(
          find.byKey(_target),
          'member',
          timeout: const Duration(milliseconds: 100),
        );
      } catch (error) {
        failure = error;
      }
      expect(
        failure,
        isA<TestFailure>().having(
          (error) => error.message,
          'message',
          contains('Timed out waiting for readable member disclosure member'),
        ),
      );
      expect(
        tester.widget<TimelineActivityRow>(_headers(_unrelated)).expanded,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
