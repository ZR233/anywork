import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter_test/flutter_test.dart';

// Observe the production renderer, not the lightweight Message/Single head.
// This helper neither reads an original nor resolves/caches a payload itself.
Future<ChatItemPresentation> waitForTimelineConceptSingle(
  WidgetTester tester,
  TimelineDisplayUnit unit, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  expect(unit.body, isA<SingleDisplayBlock>());
  final body = unit.body as SingleDisplayBlock;
  expect(body.completionId, isNotNull);
  expect(body.atom.lifecycle, isA<TerminalChatAtom>());
  final row = find.byWidgetPredicate(
    (widget) => widget is ChatItemView && widget.item.id == unit.id,
  );
  final deadline = tester.binding.clock.fromNowBy(timeout);
  while (true) {
    final rows = tester.widgetList<ChatItemView>(row).toList();
    expect(rows.length, lessThanOrEqualTo(1));
    if (rows.isNotEmpty) {
      final item = rows.single.item;
      expect(item.displayUnit, same(unit));
      expect(item.atom?.id, body.atom.id);
      expect(item.atom?.source, body.atom.source);
      expect(item.atom?.kind, body.atom.kind);
      if (item.atom?.completionItemId case final recordId?) {
        expect(recordId, body.completionId);
      }
      expect(item.atom?.completionSeq, body.atom.completionSeq);
      expect(item.atom?.lifecycle, body.atom.lifecycle);
      // Public Input Body may mount before its independent canonical metadata
      // finishes. It is valid visible content, but not evidence of completed
      // metadata/attachment recovery. Keep the original bounded wait.
      if (item.compatibility != ChatItemCompatibility.deferred) {
        expect(
          item.compatibility,
          ChatItemCompatibility.current,
          reason: 'Only the canonical mounted business renderer is evidence',
        );
        return item;
      }
    }
    if (!tester.binding.clock.now().isBefore(deadline)) {
      fail('Canonical Single renderer did not resolve for ${unit.id}');
    }
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
  }
}
