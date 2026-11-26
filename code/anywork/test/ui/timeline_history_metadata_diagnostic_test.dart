import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_feed_projection.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/conversation_feed_fixtures.dart';

void main() {
  for (final grouped in [false, true]) {
    testWidgets(
      'a Feed fallback preserves its diagnostic and following row (grouped=$grouped)',
      (tester) async {
        const diagnostic = 'Unsupported saved observation';
        final damaged = grouped
            ? timelineFeedMember(
                const WorkGroupFallback(
                  id: 'member:1',
                  seq: 1,
                  eventId: 'event:1',
                  eventKind: 'legacy_observed',
                  reason: diagnostic,
                ),
              )
            : chatItemPresentationOf(
                timelineFeedMessage(
                  const TimelineFallback(
                    id: 'msg:1',
                    seq: 1,
                    eventId: 'event:1',
                    eventKind: 'legacy_observed',
                    reason: diagnostic,
                  ),
                ),
              )!;
        final following = chatItemPresentationOf(
          timelineFeedMessage(feedAssistant('msg:2', 2, '正常后续行')),
        )!;
        await tester.pumpWidget(
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
                child: Column(
                  children: [
                    ChatItemView(item: damaged),
                    ChatItemView(item: following),
                  ],
                ),
              ),
            ),
          ),
        );
        expect(find.text('内容格式错误'), findsOneWidget);
        await tester.tap(find.text('内容格式错误'));
        await tester.pumpAndSettle();
        expect(find.text(diagnostic), findsOneWidget);
        expect(find.text('正常后续行'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
