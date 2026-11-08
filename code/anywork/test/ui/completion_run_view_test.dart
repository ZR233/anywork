import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_message_controller.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork_client/conversation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/completion_fixtures.dart';

void main() {
  testWidgets(
    'one work member is a folded card; same Run growth preserves the open body',
    (tester) async {
      final controller = InMemoryChatController();
      final adapter = TimelineMessageController(controller, generation: 1);
      var built = 0;
      var retired = 0;
      Widget display() {
        final message = controller.messages.single;
        return MaterialApp(
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

      await adapter.applyBatch(completedBatch([completionEntry('first', 1)]));
      await tester.pumpWidget(display());
      expect(find.text('工作记录 · 1 项'), findsOneWidget);
      expect(built, 0);
      expect(find.byType(_Body), findsNothing);
      await tester.tap(find.text('工作记录 · 1 项'));
      await tester.pumpAndSettle();
      expect(find.text('成员正文'), findsOneWidget);
      final first = tester.element(find.byType(_Body));
      final unit =
          controller.messages.single.metadata![timelineDisplayUnitKey]
              as TimelineDisplayUnit;
      final token = unit.expansion.bodyGeneration;
      await adapter.applyBatch(
        completedBatch(
          [completionEntry('second', 2, start: 1, ordinal: 2)],
          placement: ChatPlacement.append,
          from: 1,
        ),
      );
      await tester.pumpWidget(display());
      expect(find.text('工作记录 · 2 项'), findsOneWidget);
      expect(tester.element(find.byType(_Body)), same(first));
      expect(unit.expansion.bodyGeneration, same(token));
      expect(retired, 0);
      await tester.tap(find.text('工作记录 · 2 项'));
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
    'background title uses explicit class; zero unrequested member reads',
    (tester) async {
      final controller = InMemoryChatController();
      final adapter = TimelineMessageController(controller, generation: 1);
      await adapter.applyBatch(
        completedBatch([
          completionEntry(
            'background',
            100000,
            start: 1,
            ordinal: 100000,
            presentation: MainPresentation.backgroundResults,
          ),
        ]),
      );
      var reads = 0;
      await tester.pumpWidget(
        MaterialApp(
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
      expect(find.text('后台结果 · 100000 项'), findsOneWidget);
      expect(reads, 0);
      expect(find.textContaining('失败'), findsNothing);
      expect(find.textContaining('思考'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      adapter.dispose();
      controller.dispose();
    },
  );
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
