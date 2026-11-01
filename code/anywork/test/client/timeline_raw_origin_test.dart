import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_fixtures.dart';

void main() {
  Widget app(Widget child) => MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  testWidgets(
    'runtimeControl is a localized nonexpandable notice, not raw user history',
    (tester) async {
      final item = ChatItemPresentation.decode(
        chatEnvelope(
          'notice',
          type: 'raw',
          data: const {
            'origin': 'runtimeControl',
            'notice': 'This session continued after it was stopped.',
            'payloads': [],
            'recordedAt': 1700000000,
          },
        ),
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
      final item = ChatItemPresentation.decode(
        chatEnvelope(
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
        ),
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
}
