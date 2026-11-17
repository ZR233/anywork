import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_reasoning_view.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Finder timelineGroupTitleFinder(
  WidgetTester tester,
  Finder header, {
  bool skipOffstage = true,
  VoidCallback? validateOwner,
}) => find.descendant(
  of: header,
  matching: find.byElementPredicate((element) {
    final widget = element.widget;
    if (widget.key == const ValueKey('work-header-title')) {
      validateOwner?.call();
      return true;
    }
    return widget is TimelineReasoningSummary;
  }, skipOffstage: skipOffstage),
  skipOffstage: skipOffstage,
);

RenderParagraph timelineGroupTitleParagraph(
  WidgetTester tester,
  Finder title,
) => tester.renderObject<RenderParagraph>(title);

String timelineGroupTitleText(WidgetTester tester, Finder title) =>
    timelineGroupTitleParagraph(tester, title).text.toPlainText();

bool timelineWorkHeaderExpanded(
  WidgetTester tester,
  Finder header,
  String id,
) => find
    .descendant(
      of: header,
      matching: find.byKey(ValueKey('work-header-details:$id')),
    )
    .evaluate()
    .isNotEmpty;

/// Synchronous observation of the one production Main controller. It does not
/// reconstruct grouping, Current atoms, or a second timeline collection.
final class TimelineObservation {
  TimelineObservation(this.tester, this.borrowLease);

  final WidgetTester tester;
  final TimelineDisplayLease Function() borrowLease;
  TimelineDisplayLease get lease => borrowLease();

  Iterable<TimelineDisplayUnit> get main sync* {
    for (final message in lease.controller.messages) {
      final unit = message.metadata?[timelineDisplayUnitKey];
      expect(unit, isA<TimelineDisplayUnit>());
      final value = unit as TimelineDisplayUnit;
      expect(message.id, value.id);
      expect(value.blockOrder, greaterThan(0));
      yield value;
    }
  }

  Iterable<TimelineDisplayUnit> get singleBlocks =>
      main.where((unit) => unit.body is SingleDisplayBlock);

  Iterable<ChatAtom> get mountedMembers =>
      lease.groupDisplays.expand((display) => display.atoms);

  TimelineDisplayUnit unit(String id) =>
      main.singleWhere((unit) => unit.id == id);

  Finder itemRow(String id) => find.byWidgetPredicate(
    (widget) => widget is ChatItemView && widget.item.id == id,
  );

  Future<void> reveal(
    Finder fragment,
    String unitId, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final matches = fragment.evaluate();
      if (matches.isNotEmpty) {
        await Scrollable.ensureVisible(matches.first, alignment: 0.5);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(fragment.hitTestable(), findsWidgets);
        return;
      }
      await tester.pump(const Duration(milliseconds: 16));
    }
    fail('Timed out revealing Main row $unitId');
  }

  Future<void> revealSingle(TimelineDisplayUnit block) =>
      reveal(itemRow(block.id), block.id);
}
