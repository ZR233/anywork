import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_feed_projection.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

ChatItemPresentation _message(String id, String channel) =>
    chatItemPresentationOf(
      timelineFeedMessage(
        TimelineUserMessage(
          id: id,
          seq: 1,
          channel: channel,
          text: '家长消息',
          attachments: const [],
        ),
      ),
    )!;

Widget _host(
  ChatItemPresentation item, {
  required Widget Function(String, String) bodyBuilder,
}) => MaterialApp(
  theme: pureStudioTheme(),
  locale: const Locale('zh'),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: ChatItemView(item: item, bodyBuilder: bodyBuilder),
  ),
);

void main() {
  testWidgets(
    'parent channel renders a parent badge and user channel has none',
    (tester) async {
      final trustedItem = _message('trusted-parent', 'parentAgent');
      expect(trustedItem.authorId, 'parentAgent');
      await tester.pumpWidget(
        _host(
          trustedItem,
          bodyBuilder: (id, text) {
            expect(text, '家长消息');
            return Text('$id:$text');
          },
        ),
      );
      expect(
        find.byKey(StudioDriverKeys.parentAgentLabel('trusted-parent')),
        findsOneWidget,
      );
      expect(find.textContaining('家长消息'), findsOneWidget);

      final untrustedItem = _message('untrusted-parent', 'user');
      expect(untrustedItem.authorId, 'user');
      await tester.pumpWidget(
        _host(untrustedItem, bodyBuilder: (_, text) => Text(text)),
      );
      expect(
        find.byKey(StudioDriverKeys.parentAgentLabel('untrusted-parent')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
