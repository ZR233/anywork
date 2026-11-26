import 'package:anywork/src/features/conversation/timeline/state/timeline_feed_projection.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
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

Finder timelineActivityTitleFinder(
  WidgetTester tester,
  Finder header, {
  bool skipOffstage = true,
  VoidCallback? validateOwner,
}) => find.descendant(
  of: header,
  matching: find.byElementPredicate((element) {
    TimelineActivityRow? row;
    element.visitAncestorElements((ancestor) {
      if (ancestor.widget case final TimelineActivityRow value) {
        row = value;
        return false;
      }
      return true;
    });
    final current = row;
    if (current == null) return false;
    final widget = element.widget;
    final labelWidget = current.labelWidget;
    final matches = labelWidget == null
        ? widget is Text && widget.data == current.label
        : identical(widget, labelWidget);
    if (matches) validateOwner?.call();
    return matches;
  }, skipOffstage: skipOffstage),
  skipOffstage: skipOffstage,
);

/// Synchronous observation of the one production Main controller. It does not
/// reconstruct grouping or a second timeline collection.
final class TimelineObservation {
  TimelineObservation(this.tester, this.borrowLease);

  final WidgetTester tester;
  final TimelineDisplayLease Function() borrowLease;
  TimelineDisplayLease get lease => borrowLease();

  Iterable<TimelineItem> get main sync* {
    for (final message in lease.controller.messages) {
      final item = timelineFeedItemOf(message);
      expect(
        item,
        isNotNull,
        reason: 'Every Main row retains its typed feed item',
      );
      expect(message.id, item!.id);
      expect(item.seq, greaterThan(0));
      yield item;
    }
  }

  Iterable<WorkGroupMember> get mountedMembers =>
      lease.groupDisplays.expand((display) => display.members);

  TimelineItem unit(String id) => main.singleWhere((item) => item.id == id);

  Finder itemRow(String id) => find.byWidgetPredicate(
    (widget) => widget is ChatItemView && widget.item.id == id,
  );

  Future<void> until(
    bool Function() ready,
    String description, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (timeout <= Duration.zero) {
      fail('Waiting for $description requires a positive deadline');
    }
    final clock = Stopwatch()..start();
    while (true) {
      if (clock.elapsed >= timeout) {
        fail('Timed out waiting for $description');
      }
      if (ready()) return;
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    }
  }

  Future<void> tap(
    Finder target, {
    bool Function()? isActive,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (timeout <= Duration.zero) {
      fail('Tapping a production control requires a positive deadline');
    }
    if (isActive?.call() == false) return;
    expect(target, findsOneWidget);
    final clock = Stopwatch()..start();
    while (target.hitTestable().evaluate().length != 1) {
      if (isActive?.call() == false) return;
      if (clock.elapsed >= timeout) {
        fail('Timed out waiting for hittable production control');
      }
      final elements = target.evaluate();
      if (elements.isNotEmpty) {
        expect(elements, hasLength(1));
        await Scrollable.ensureVisible(elements.single);
      }
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    }
    await tester.tap(target);
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  Future<void> expandMemberDisclosure(
    Finder row,
    String memberId, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final clock = Stopwatch()..start();
    Duration remaining() => timeout - clock.elapsed;
    final candidates = find.descendant(
      of: row,
      matching: find.byWidgetPredicate(
        (widget) => widget is TimelineActivityRow && widget.expandable,
      ),
    );
    await until(
      () => candidates.evaluate().isNotEmpty,
      'readable member disclosure $memberId',
      timeout: remaining(),
    );
    final header = candidates.first;
    if (!tester.widget<TimelineActivityRow>(header).expanded) {
      await tap(
        timelineActivityTitleFinder(tester, header),
        timeout: remaining(),
      );
    }
    expect(tester.widget<TimelineActivityRow>(header).expanded, isTrue);
  }

  Future<void> reveal(
    Finder fragment,
    String unitId, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (fragment.evaluate().isNotEmpty) {
        await tester.ensureVisible(fragment);
        await tester.pump();
        expect(tester.takeException(), isNull);
        // Head replacement can remount the row during the frame. Re-query the
        // finder; callers verify their actual content/control is visible.
        if (fragment.evaluate().isNotEmpty) return;
      }
      await tester.pump(const Duration(milliseconds: 50));
    }
    fail('Timed out revealing Main row $unitId');
  }

  Future<void> revealSingle(TimelineItem block) =>
      reveal(itemRow(block.id), block.id);
}
