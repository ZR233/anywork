import 'package:anywork/src/features/conversation/timeline/state/timeline_display_diagnostics.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_display_unit_view.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// UI operations and synchronous borrows of the production presentation owner.
/// No copied group/current list, payload fallback, query, or test-owned reducer.
final class TimelineObservation {
  TimelineObservation(this.tester, this.borrowLease);
  final WidgetTester tester;
  final TimelineDisplayLease Function() borrowLease;
  TimelineDisplayLease get lease => borrowLease();

  Iterable<TimelineDisplayUnit> get main sync* {
    for (final message in lease.controller.messages) {
      final unit = message.metadata?[timelineDisplayUnitKey];
      expect(unit, isA<TimelineDisplayUnit>());
      yield unit as TimelineDisplayUnit;
    }
  }

  Iterable<ChatAtom> get atoms => main.expand((unit) => unit.members);
  Iterable<TimelineDisplayUnit> get live => lease.liveUnits.value;
  Iterable<TimelineDisplayUnit> workFor(ChatSourceId source) => main.where(
    (unit) => unit.source == source && unit.kind == TimelineUnitKind.work,
  );

  TimelineDisplayUnit unitForAtom(String id) =>
      main.singleWhere((unit) => unit.members.any((atom) => atom.id == id));

  TimelineDisplayUnit unit(String id) =>
      [...main, ...live].singleWhere((unit) => unit.id == id);

  Finder groupRow(String id) => find.byWidgetPredicate(
    (widget) => widget is TimelineDisplayUnitView && widget.unit.id == id,
  );
  Finder atomRow(String id) => find.byWidgetPredicate(
    (widget) => widget is ChatItemView && widget.item.atom?.id == id,
  );
  Finder groupHeader(String id) => find.descendant(
    of: groupRow(id),
    matching: find.byKey(ValueKey('source-unit-header:$id')),
  );

  Finder _groupTitle(String id) {
    final header = groupHeader(id);
    expect(header, findsOneWidget);
    // The header's Align/Row can have its centre in a Spacer, outside its
    // children's hit path. Target the real title inside this exact unit, not
    // the disclosure's body or another group's identically labelled header.
    return find.descendant(
      of: header,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data == tester.widget<TimelineActivityRow>(header).label,
      ),
    );
  }

  Future<void> until(bool Function() ready, String description) async {
    final clock = Stopwatch()..start();
    while (!ready()) {
      if (clock.elapsed > const Duration(seconds: 60)) {
        fail('Timed out waiting for $description');
      }
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    }
  }

  Future<void> tap(Finder target) async {
    expect(target, findsOneWidget);
    await tester.ensureVisible(target);
    await tester.pump();
    await until(
      () => target.hitTestable().evaluate().length == 1,
      'hittable production control',
    );
    await tester.tap(target);
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  Future<void> reveal(Finder target, String unitId) async {
    final scrollable = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable &&
          identical(widget.controller, lease.scrollController),
    );
    final clock = Stopwatch()..start();
    while (target.evaluate().isEmpty) {
      if (clock.elapsed > const Duration(seconds: 60)) {
        fail('Main did not mount requested unit $unitId');
      }
      final ordered = main.toList();
      final wanted = ordered.indexWhere((unit) => unit.id == unitId);
      final mounted =
          tester
              .widgetList<TimelineDisplayUnitView>(
                find.byType(TimelineDisplayUnitView),
              )
              .where((view) => !view.unit.live)
              .map(
                (view) => ordered.indexWhere((unit) => unit.id == view.unit.id),
              )
              .where((index) => index >= 0)
              .toList()
            ..sort();
      final newer = mounted.isNotEmpty && wanted > mounted.last;
      await tester.drag(scrollable, Offset(0, newer ? -240 : 240));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    }
    await tester.ensureVisible(target);
    await tester.pump();
  }

  Future<TimelineGroupDisplay> openGroup(String id) async {
    final originalLease = lease;
    final value = unit(id);
    final originalController = lease.controller;
    final originalGeneration = lease.generation;
    final mainSets = lease.appliedSets;
    expect(value.kind, TimelineUnitKind.work);
    final header = groupHeader(id);
    if (value.live) {
      await until(() => header.evaluate().isNotEmpty, 'live group $id');
    } else {
      await reveal(header, id);
    }
    expect(header, findsOneWidget);
    if (!tester.widget<TimelineActivityRow>(header).expanded) {
      await tap(_groupTitle(id));
    }
    TimelineGroupDisplay? display;
    await until(() {
      display = lease.groupDisplays
          .where((display) => display.unitId == id)
          .singleOrNull;
      if (display?.error case final error?) throw StateError('$error');
      return display?.isCurrent == true && display?.expanded == true;
    }, 'mounted original ordinary group $id');
    expect(display!.atoms, isNotEmpty);
    expect(display!.atoms.map((atom) => atom.source).toSet(), {value.source});
    expect(lease, same(originalLease));
    expect(lease.controller, same(originalController));
    expect(lease.generation, originalGeneration);
    expect(
      lease.appliedSets,
      mainSets,
      reason: 'group expansion must not replace the original Main Set',
    );
    return display!;
  }

  Future<TimelineGroupDisplay?> revealAtom(ChatAtom atom) async {
    final value = unitForAtom(atom.id);
    TimelineGroupDisplay? display;
    if (value.kind == TimelineUnitKind.work) {
      display = await openGroup(value.id);
      expect(display.atoms.where((entry) => entry.id == atom.id), hasLength(1));
    }
    await reveal(atomRow(atom.id), value.id);
    expect(atomRow(atom.id), findsOneWidget);
    final rendered = tester.widget<ChatItemView>(atomRow(atom.id)).item.atom!;
    expect(rendered.id, atom.id);
    expect(rendered.source, atom.source);
    expect(rendered.tool?.callId, atom.tool?.callId);
    return display;
  }

  Future<void> closeGroup(TimelineGroupDisplay display) async {
    if (display.isCurrent && display.expanded) {
      await reveal(groupHeader(display.unitId), display.unitId);
      await tap(_groupTitle(display.unitId));
    }
    await until(
      () =>
          !display.expanded &&
          display.atoms.isEmpty &&
          display.completionAnchor == null &&
          display.before == null &&
          !display.loading,
      'collapsed ordinary window revoked',
    );
    expect(display.error, isNull);
  }

  Future<void> closeSource(ChatSourceId source) async {
    final ids = workFor(source).map((unit) => unit.id).toSet();
    expect(ids, isNotEmpty);
    for (final display
        in lease.groupDisplays
            .where(
              (display) => ids.contains(display.unitId) && display.expanded,
            )
            .toList()) {
      await closeGroup(display);
    }
    expect(
      lease.groupDisplays.where(
        (display) => ids.contains(display.unitId) && display.expanded,
      ),
      isEmpty,
    );
  }
}
