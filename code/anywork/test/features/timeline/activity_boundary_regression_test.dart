import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/previews/timeline_preview_fixtures.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_children_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  theme: pureStudioTheme(),
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: 500, child: child),
    ),
  ),
);

Message _skill(String id) => Message.custom(
  id: id,
  authorId: 'assistant',
  metadata: {
    chatItemPresentationKey: TimelinePreviewFixtures.item(id, 'skill', {
      'activation': {'name': id},
    }),
  },
);

void main() {
  testWidgets(
    'Children prepend and final-page offset retain expanded member State',
    (tester) async {
      final original = _skill('existing-skill');
      final controller = InMemoryChatController(messages: [original]);
      addTearDown(controller.dispose);
      var hasOlder = true;
      var pages = 0;
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, rebuild) {
              return TimelineChildrenView(
                controller: controller,
                generation: 1,
                isDisplayActive: () => true,
                contentRangeBuilder: (_, _, label, _, _) => Text(label),
                onLoadOlder: hasOlder
                    ? () async {
                        pages++;
                        await controller.insertAllMessages(
                          [_skill('older-$pages')],
                          index: 0,
                          animated: false,
                        );
                        if (pages == 2) rebuild(() => hasOlder = false);
                      }
                    : null,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      Finder disclosure() => find
          .descendant(
            of: find.byKey(const ValueKey('chat-item:existing-skill')),
            matching: find.byType(ExpansionTile),
          )
          .first;
      await tester.tap(find.text('existing-skill'));
      await tester.pumpAndSettle();
      final state = tester.state(disclosure());
      for (var page = 1; page <= 2; page++) {
        await tester.tap(
          find.byKey(const ValueKey('timeline-children-load-older')),
        );
        await tester.pumpAndSettle();
        expect(controller.messages[page], same(original));
        expect(tester.state(disclosure()), same(state));
        final tile = tester.widget<ExpansionTile>(disclosure());
        expect(
          ExpansibleController.of(tester.element(find.byWidget(tile.title)))
              .isExpanded,
          isTrue,
        );
      }
      expect(
        find.byKey(const ValueKey('timeline-children-load-older')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final state in ['failed', 'cancelled']) {
    testWidgets('$state reason belongs to Turn receipt, not accepted text', (
      tester,
    ) async {
      final outcome = {
        'kind': state,
        'data': {'message': '$state-terminal-proof'},
      };
      await tester.pumpWidget(
        _host(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ChatItemView(
                item: TimelinePreviewFixtures.item(
                  'partial',
                  'text',
                  {'channel': 'final', 'attachments': [], 'outcome': outcome},
                  bodies: [
                    TimelinePreviewFixtures.body(
                      'part.text.0',
                      'accepted partial text',
                    ),
                  ],
                ),
              ),
              ChatItemView(
                item: TimelinePreviewFixtures.item('terminal', 'turn', {
                  'outcome': outcome,
                }),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('accepted partial text'), findsOneWidget);
      expect(find.textContaining('$state-terminal-proof'), findsNothing);
      await tester.tap(
        find
            .descendant(
              of: find.byKey(const ValueKey('chat-item:terminal')),
              matching: find.byType(InkWell),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('$state-terminal-proof'), findsOneWidget);
      expect(find.text('accepted partial text'), findsOneWidget);
    });

    testWidgets('empty $state thinking keeps outcome and semantic icon', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          ChatItemView(
            item: TimelinePreviewFixtures.item('empty-thinking', 'thinking', {
              'outcome': {
                'kind': state,
                'data': {'message': '$state-thinking-proof'},
              },
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('$state-thinking-proof'), findsOneWidget);
      final row = tester.widget<TimelineActivityRow>(
        find.byType(TimelineActivityRow),
      );
      expect(row.isIssue, state == 'failed');
      if (state == 'cancelled') {
        expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
      }
      expect(row.expandable, isFalse);
    });
  }
}
