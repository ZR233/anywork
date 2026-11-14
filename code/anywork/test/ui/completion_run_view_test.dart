import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_message_controller.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_resting_cat.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_writing_indicator.dart';
import 'package:anywork_client/conversation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/display_fixtures.dart';

void main() {
  for (final language in ['zh', 'en']) {
    testWidgets(
      'a later frozen block cannot grow or reset the open historical card ($language)',
      (tester) async {
        final controller = InMemoryChatController();
        final adapter = TimelineMessageController(controller, generation: 1);
        var built = 0;
        var retired = 0;
        Widget display() {
          final message = controller.messages.first;
          return MaterialApp(
            locale: Locale(language),
            localizationsDelegates: [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ChatItemView(
                key: ValueKey(message.id),
                item: chatItemPresentationOf(message)!,
                groupMembersBuilder: (_) {
                  built++;
                  return _Body(onDispose: () => retired++);
                },
              ),
            ),
          );
        }

        await adapter.applyFixtureUpdate(
          displayBatch([displayWork('first', 1)]),
        );
        await tester.pumpWidget(display());
        expect(find.text(_runTitle(tester, 1)), findsOneWidget);
        expect(find.byType(TimelineActivityIndicator), findsNothing);
        expect(find.byType(TimelineRestingCat), findsNothing);
        expect(find.byType(TimelineWritingIndicator), findsNothing);
        expect(built, 0);
        expect(find.byType(_Body), findsNothing);
        await tester.tap(find.text(_runTitle(tester, 1)));
        await tester.pumpAndSettle();
        expect(find.text('成员正文'), findsOneWidget);
        final first = tester.element(find.byType(_Body));
        final unit =
            controller.messages.first.metadata![timelineDisplayUnitKey]
                as TimelineDisplayUnit;
        final token = unit.expansion.bodyGeneration;
        await adapter.applyFixtureUpdate(
          displayBatch(
            [displayWork('second', 2)],
            placement: ChatPlacement.append,
            from: 1,
          ),
        );
        await tester.pumpWidget(display());
        expect(controller.messages, hasLength(2));
        expect(find.text(_runTitle(tester, 1)), findsOneWidget);
        expect(find.byType(TimelineActivityIndicator), findsNothing);
        expect(tester.element(find.byType(_Body)), same(first));
        expect(unit.expansion.bodyGeneration, same(token));
        expect(retired, 0);
        await tester.tap(find.text(_runTitle(tester, 1)));
        // Eligibility is revoked in the tap callback, before the closing animation.
        expect(unit.expansion.retirement.value, isTrue);
        expect(unit.expansion.bodyActive, isFalse);
        await tester.pumpAndSettle();
        expect(find.byType(_Body), findsNothing);
        expect(retired, 1);
        await tester.pumpWidget(const SizedBox());
        adapter.dispose();
        controller.dispose();
      },
    );

    testWidgets(
      'collapsed Work timing requires zero unrequested member reads ($language)',
      (tester) async {
        final controller = InMemoryChatController();
        final adapter = TimelineMessageController(controller, generation: 1);
        await adapter.applyFixtureUpdate(
          displayBatch([displayWork('large', 1)]),
        );
        var reads = 0;
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            localizationsDelegates: [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ChatItemView(
                item: chatItemPresentationOf(controller.messages.single)!,
                groupMembersBuilder: (_) {
                  reads++;
                  return const Text('仅在展开后读取');
                },
              ),
            ),
          ),
        );
        expect(find.text(_runTitle(tester, 100000)), findsOneWidget);
        expect(reads, 0);
        expect(find.textContaining('失败'), findsNothing);
        expect(find.textContaining('思考'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        adapter.dispose();
        controller.dispose();
      },
    );
  }
}

String _runTitle(WidgetTester tester, int count) {
  final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)));
  return l10n.timelineGroupWorkedSeconds(1);
}

class _Body extends StatefulWidget {
  const _Body({required this.onDispose});
  final VoidCallback onDispose;
  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  @override
  Widget build(BuildContext context) => const Text('成员正文');
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }
}
