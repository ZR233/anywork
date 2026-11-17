import 'package:anywork/src/features/conversation/timeline/connectors/timeline_content_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_diagnostics.dart';
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
      await tester.pump(const Duration(milliseconds: 16));
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
      await Scrollable.ensureVisible(tester.element(target));
      await tester.pump();
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

  Future<void> ensureMemberReadable(
    Finder row,
    ChatAtom atom, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (atom.kind == ChatAtomKind.toolCall) {
      await expandMemberDisclosure(row, atom.id, timeout: timeout);
      return;
    }
    expect(atom.kind, ChatAtomKind.reasoning);
    expect(atom.contents, isNotEmpty);
    expect(
      atom.contents.every(
        (content) =>
            content.role == ChatContentRole.body ||
            content.role == ChatContentRole.reasoningSummary,
      ),
      isTrue,
    );
    if (atom.contents.any((content) => content.role == ChatContentRole.body)) {
      await expandMemberDisclosure(row, atom.id, timeout: timeout);
      return;
    }

    final reasoning = find.descendant(
      of: row,
      matching: find.byType(TimelineReasoningView),
    );
    await until(
      () {
        if (reasoning.evaluate().isEmpty) return false;
        expect(reasoning, findsOneWidget);
        expect(tester.widget<TimelineReasoningView>(reasoning).body, isNull);
        final header = find.descendant(
          of: reasoning,
          matching: find.byType(TimelineActivityRow),
        );
        expect(header, findsOneWidget);
        expect(tester.widget<TimelineActivityRow>(header).expandable, isFalse);
        expect(tester.widget<TimelineActivityRow>(header).expanded, isFalse);
        final observations = <TimelineCurrentWindowDisplay>[
          for (final element in row.evaluate())
            if (element is StatefulElement &&
                element.state is TimelineMemberDisplay)
              ...(element.state as TimelineMemberDisplay).windows,
          for (final element
              in find
                  .descendant(
                    of: reasoning,
                    matching: find.byType(TimelineContentRangeConnector),
                  )
                  .evaluate())
            (element as StatefulElement).state as TimelineCurrentWindowDisplay,
        ];
        for (final observation in observations) {
          expect(
            atom.contents.any(
              (content) => content.reference == observation.reference,
            ),
            isTrue,
          );
          expect(observation.error, isNull);
          if (observation.window == null || observation.window!.bytes.isEmpty) {
            return false;
          }
        }
        final summaries = find.descendant(
          of: reasoning,
          matching: find.byType(TimelineReasoningSummary),
        );
        if (summaries.evaluate().isEmpty ||
            tester
                .widgetList<TimelineReasoningSummary>(summaries)
                .any((summary) => summary.text.trim().isEmpty)) {
          return false;
        }
        return find
            .descendant(
              of: summaries,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is RichText &&
                    widget.text.toPlainText().trim().isNotEmpty,
              ),
            )
            .hitTestable()
            .evaluate()
            .isNotEmpty;
      },
      'visible summary-only reasoning ${atom.id}',
      timeout: timeout,
    );
  }

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
