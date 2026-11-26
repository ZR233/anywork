import 'dart:convert';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_reasoning_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';

import '../support/chat_fixtures.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _target = ValueKey('target-member');
const _unrelated = ValueKey('unrelated-member');

ChatItemPresentation _presentation(
  String type,
  String key, {
  String text = 'accepted member body',
}) => chatPresentation(
  'member',
  type: type,
  data: type == 'thinking'
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
  bodies: [
    {
      'key': key,
      'byteLength': utf8.encode(text).length,
      'inline': utf8.encode(text),
    },
  ],
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

void main() {
  for (final type in ['thinking', 'tool']) {
    testWidgets('disclosing a $type member leaves adjacent rows collapsed', (
      tester,
    ) async {
      final current = ValueNotifier<ChatItemPresentation?>(null);
      addTearDown(current.dispose);
      await tester.pumpWidget(_host(current));
      expect(_headers(_target), findsNothing);
      current.value = _presentation(
        type,
        type == 'thinking' ? 'part.reasoningText.0' : 'tool.result',
      );
      await tester.pumpAndSettle();
      final target = _headers(_target);
      expect(target, findsOneWidget);
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(tester.widget<TimelineActivityRow>(target).expanded, isTrue);
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

  testWidgets('a reasoning summary can be read without opening a body', (
    tester,
  ) async {
    const summary = '梳理会话共享组件与锁定边界';
    final current = ValueNotifier<ChatItemPresentation?>(
      _presentation('thinking', 'part.summaryText.0', text: summary),
    );
    addTearDown(current.dispose);
    await tester.pumpWidget(_host(current));
    final row = find.byKey(_target);
    final reasoning = find.descendant(
      of: row,
      matching: find.byType(TimelineReasoningView),
    );
    expect(reasoning, findsOneWidget);
    expect(tester.widget<TimelineReasoningView>(reasoning).body, isNull);
    expect(_headers(_target), findsNothing);
    expect(
      find
          .descendant(of: row, matching: find.text(summary, findRichText: true))
          .hitTestable(),
      findsOneWidget,
    );
    expect(
      tester.widget<TimelineActivityRow>(_headers(_unrelated)).expanded,
      isFalse,
    );
  });
}
