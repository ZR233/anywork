import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_feed_projection.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_fixtures.dart';

void main() {
  Widget app(Widget child) => MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  testWidgets(
    'runtimeControl is a localized nonexpandable notice, not raw user history',
    (tester) async {
      final item = chatPresentation(
        'notice',
        type: 'raw',
        data: const {
          'origin': 'runtimeControl',
          'notice': 'This session continued after it was stopped.',
          'payloads': [],
          'recordedAt': 1700000000,
        },
      );
      await tester.pumpWidget(app(ChatItemView(item: item)));
      expect(find.text('运行时说明'), findsOneWidget);
      expect(
        find.text('This session continued after it was stopped.'),
        findsNothing,
      );
      expect(
        find.byType(ExpansionTile),
        findsNothing,
        reason: 'runtime control never held user content to expand',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'stored raw payload remains expandable and verbatim, including absent default origin',
    (tester) async {
      final item = chatPresentation(
        'payload',
        type: 'raw',
        data: const {
          'notice': 'Unsupported saved response encoding',
          'payloads': [
            {'format': 'pl.model.receipt', 'version': 1, 'content': ''},
          ],
          'recordedAt': 1700000000,
        },
        bodies: [inlineBody('raw.payload.0', '{"ok":false}')],
      );
      await tester.pumpWidget(app(ChatItemView(item: item)));
      expect(find.text('Unsupported saved response encoding'), findsOneWidget);
      expect(find.text('{"ok":false}'), findsNothing);
      await tester.tap(find.text('Unsupported saved response encoding'));
      await tester.pumpAndSettle();
      expect(find.text('{"ok":false}'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'typed model and SSH notices retain their display scope and retry detail',
    (tester) async {
      final notices = [
        const TimelineConnectionNotice(
          id: 'model',
          seq: 10,
          scope: 'model',
          state: 'disconnected',
          transport: 'websocket',
          attempt: 1,
          maxAttempts: 5,
          recoverable: true,
          reason: 'peer reset',
        ),
        const TimelineConnectionNotice(
          id: 'ssh',
          seq: 11,
          scope: 'ssh',
          state: 'reconnected',
          transport: 'ssh',
          attempt: 1,
          maxAttempts: 2,
          recoverable: true,
        ),
      ];
      await tester.pumpWidget(
        app(
          Column(
            children: [
              for (final notice in notices)
                ChatItemView(
                  item: chatItemPresentationOf(timelineFeedMessage(notice))!,
                ),
            ],
          ),
        ),
      );
      expect(find.text('模型连接已断开'), findsOneWidget);
      expect(
        find.textContaining('websocket · 1/5 · peer reset'),
        findsOneWidget,
      );
      expect(find.text('SSH 连接已恢复'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
