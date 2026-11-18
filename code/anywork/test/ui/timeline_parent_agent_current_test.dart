import 'dart:convert';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

ChatAtom _parentAtom({
  required String id,
  required ThreadTextChannel channel,
}) => ChatAtom(
  id: id,
  source: const InboxMessageChatSource(
    sourceId: 'agent:direct-parent',
    messageId: 'message',
  ),
  sourceOrder: null,
  kind: ChatAtomKind.text,
  delivery: ChatDeliveryKind.independent,
  textChannel: channel,
  lifecycle: const TerminalChatAtom(
    started: null,
    ended: null,
    outcome: ChatTerminalOutcome.completed,
  ),
  contents: const [],
  payload: InlinePayload(
    bytes: utf8.encode(
      jsonEncode({
        'contract': 'anywork.chat/1',
        'type': 'text',
        'data': {'channel': 'parentAgent', 'attachments': []},
        'bodies': [
          {
            'key': 'body',
            'byteLength': utf8.encode('家长消息').length,
            'inline': utf8.encode('家长消息'),
          },
        ],
      }),
    ),
  ),
);

DisplayRecord _record(ChatAtom atom) => DisplayRecord(
  atom: atom,
  contentSource: const CurrentAtomSource(),
  currentContents: const [
    CurrentAtomContent(
      role: ChatContentRole.body,
      reference: CurrentContentRef(
        ownerId: 'owner',
        domain: 'thread',
        entityId: 'parent',
        contentKey: 'body',
        generation: '1',
      ),
    ),
  ],
);

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
    'typed parent channel grants identity while inbox source does not',
    (tester) async {
      final trusted = _parentAtom(
        id: 'trusted-parent',
        channel: ThreadTextChannel.parentAgent,
      );
      final trustedItem = ChatItemPresentation.decode(
        trusted,
        record: _record(trusted),
      );
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

      final untrusted = _parentAtom(
        id: 'untrusted-parent',
        channel: ThreadTextChannel.user,
      );
      final untrustedItem = ChatItemPresentation.decode(
        untrusted,
        record: _record(untrusted),
      );
      expect(untrustedItem.authorId, 'inbox:agent:direct-parent');
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
