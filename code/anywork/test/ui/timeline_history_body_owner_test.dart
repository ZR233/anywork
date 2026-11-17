import 'dart:convert';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final source in <ChatSourceId>[
    const ForegroundTurnChatSource(turnId: 'turn'),
    const InputChatSource(inputId: 'input'),
  ]) {
    testWidgets(
      'resolved historical ${source.runtimeType} keeps its body read owner',
      (tester) async {
        const text = '独立历史正文🙂';
        final bytes = utf8.encode(text);
        final unit = TimelineDisplayUnit(
          block: DisplayBlock(
            id: 'row',
            blockOrder: 1,
            body: SingleDisplayBlock(
              visibility: HistorySingleVisibility.content,
              record: DisplayRecord(
                historyEventId: 'event',
                contentSource: const CompletedOriginal(completionId: 'event'),
                atom: ChatAtom(
                  id: 'entity',
                  sourceOrder: null,
                  source: source,
                  kind: source is InputChatSource
                      ? ChatAtomKind.input
                      : ChatAtomKind.text,
                  delivery: ChatDeliveryKind.independent,
                  lifecycle: const TerminalChatAtom(
                    started: null,
                    ended: null,
                    outcome: ChatTerminalOutcome.completed,
                  ),
                  contentPresent: true,
                  contents: const [],
                ),
              ),
            ),
          ),
        );
        unit.expansion.current = unit;
        var reads = 0;
        unit.expansion.readHistoryBody = (generation, reference, range) async {
          expect(identical(generation, unit.expansion.bodyGeneration), isTrue);
          expect(reference.ownerEventId, 'event');
          expect(range.offset, 0);
          reads++;
          return ContentWindow(
            offset: 0,
            bytes: bytes,
            generation: reference.bodyId,
            availableThrough: bytes.length,
            sealed: true,
          );
        };
        final item = ChatItemPresentation.forUnit(unit).resolvePayload(
          InlinePayload(
            bytes: utf8.encode(
              jsonEncode({
                'contract': 'anywork.chat/1',
                'type': 'text',
                'data': {
                  'channel': source is InputChatSource ? 'user' : 'final',
                  'attachments': <Object?>[],
                },
                'bodies': [
                  {
                    'key': 'body',
                    'byteLength': bytes.length,
                    'reference': {
                      'databaseId': 'db',
                      'ownerEventId': 'event',
                      'bodyKey': 'body',
                      'bodyId': 'body-id',
                      'byteStart': 0,
                      'byteLength': bytes.length,
                    },
                  },
                ],
              }),
            ),
          ),
        );
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
              body: ChatItemView(
                item: item,
                bodyBuilder: (_, text) => Text(text),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(text), findsOneWidget);
        expect(reads, 1);
        await tester.pumpWidget(const SizedBox());
        expect(unit.expansion.bodyActive, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
