import 'dart:convert';

import 'package:anywork/src/features/conversation/timeline/state/timeline_display_diagnostics.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_children_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_display_unit_view.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
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
      final value = unit as TimelineDisplayUnit;
      expect(
        message.id,
        value.item.id,
        reason: 'one Main item owns one Message',
      );
      expect(value.live, isFalse);
      expect(value.item.position, isNotNull);
      if (value.item.kind == TimelineItemKind.workGroup) {
        expect(value.item.summary, isNotNull);
        expect(value.item.members?.itemId, value.item.id);
        expect(value.item.payload, isNull);
        expect(value.item.contents, isEmpty);
        expect(value.item.contentItemId, isNull);
      } else {
        expect(value.item.atomKind, isNotNull);
        expect(value.item.members, isNull);
      }
      yield value;
    }
  }

  Iterable<TimelineItem> get items => main.map((unit) => unit.item);
  // Only already mounted member scopes are borrowed. This never expands a
  // folded group, reads a page, or claims the bounded window is full inventory.
  Iterable<ChatAtom> get mountedMembers =>
      lease.groupDisplays.expand((display) => display.atoms);
  Iterable<TimelineDisplayUnit> get live => lease.liveUnits.value;
  Iterable<TimelineDisplayUnit> workFor(ChatSourceId source) =>
      [...main, ...live].where(
        (unit) =>
            unit.item.source == source &&
            unit.item.kind == TimelineItemKind.workGroup,
      );

  TimelineDisplayUnit unitForMember(String id) => unit(
    lease.groupDisplays
        .singleWhere((display) => display.atoms.any((atom) => atom.id == id))
        .unitId,
  );

  Future<void> openSourceGroups(ChatSourceId source) async {
    for (final group in workFor(source).toList()) {
      await openGroup(group.id);
    }
  }

  Future<void> openLiveGroups() async {
    for (final group
        in live
            .where((unit) => unit.item.kind == TimelineItemKind.workGroup)
            .toList()) {
      await openGroup(group.id);
    }
  }

  TimelineDisplayUnit unit(String id) =>
      [...main, ...live].singleWhere((unit) => unit.id == id);

  Finder groupRow(String id) => find.byWidgetPredicate(
    (widget) => widget is TimelineDisplayUnitView && widget.unit.id == id,
  );
  Finder itemRow(String id) => find.byWidgetPredicate(
    (widget) => widget is ChatItemView && widget.item.id == id,
  );
  Finder memberRow(String id) => find.byWidgetPredicate(
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
    final originalLease = lease;
    final originalController = originalLease.controller;
    final originalScrollController = originalLease.scrollController;
    final originalGeneration = originalLease.generation;
    final scrollable = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable &&
          identical(widget.controller, originalScrollController),
    );
    ScrollableState? originalScrollable;
    final clock = Stopwatch()..start();

    Never stop(String reason) {
      TimelineDisplayLease? currentLease;
      String? borrowError;
      try {
        currentLease = lease;
      } catch (error) {
        borrowError = error.runtimeType.toString();
      }
      final matches = scrollable.evaluate().toList();
      final state = matches.length == 1
          ? tester.state<ScrollableState>(scrollable)
          : null;
      final position = state?.position;
      final available = !originalLease.isReleased;
      final mounted = available && state != null
          ? _mainRevealIndices(originalController, state, visibleOnly: false)
          : <int>[];
      final visible = available && state != null
          ? _mainRevealIndices(originalController, state, visibleOnly: true)
          : <int>[];
      final wanted = available
          ? originalController.messages.indexWhere((item) => item.id == unitId)
          : null;
      fail(
        '$reason: ${jsonEncode({
          'targetId': unitId,
          'mainIndex': wanted,
          'elapsedMillis': clock.elapsedMilliseconds,
          'original': {'lease': identityHashCode(originalLease), 'controller': identityHashCode(originalController), 'scrollController': identityHashCode(originalScrollController), 'generation': originalGeneration, 'mounted': originalLease.isMounted, 'retired': originalLease.isRetired, 'released': originalLease.isReleased},
          'current': {'lease': currentLease == null ? null : identityHashCode(currentLease), 'controller': currentLease == null || currentLease.isRetired || currentLease.isReleased ? null : identityHashCode(currentLease.controller), 'generation': currentLease?.generation, 'borrowError': borrowError},
          'scrollableCount': matches.length,
          'originalScrollable': originalScrollable == null ? null : identityHashCode(originalScrollable),
          'sameScrollable': state != null && identical(state, originalScrollable),
          'pixels': position?.hasPixels == true ? position!.pixels : null,
          'min': position?.hasContentDimensions == true ? position!.minScrollExtent : null,
          'max': position?.hasContentDimensions == true ? position!.maxScrollExtent : null,
          'viewport': position?.hasViewportDimension == true ? position!.viewportDimension : null,
          'axisDirection': position?.axisDirection.name,
          'visibleMainIndices': visible.take(40).toList(),
          'visibleMainCount': visible.length,
          'mountedMainIndices': mounted.take(40).toList(),
          'mountedMainCount': mounted.length,
          'cachedMainIndices': mounted.where((index) => !visible.contains(index)).take(40).toList(),
          'cachedMainCount': mounted.length - visible.length,
          'targetMainRowMounted': mounted.contains(wanted),
          'targetFinderCount': target.evaluate().length,
          'targetHitTestableCount': target.hitTestable().evaluate().length,
        })}',
      );
    }

    void requireOriginal() {
      TimelineDisplayLease currentLease;
      try {
        currentLease = lease;
      } catch (_) {
        stop('Main reveal lost its original lease');
      }
      if (!identical(currentLease, originalLease) ||
          originalLease.isRetired ||
          originalLease.isReleased ||
          !originalLease.isMounted ||
          originalLease.generation != originalGeneration ||
          !identical(originalLease.controller, originalController)) {
        stop('Main reveal lost its original lease/controller/generation');
      }
      if (scrollable.evaluate().length != 1 ||
          originalScrollController.positions.length != 1) {
        stop('Main reveal requires one original Main Scrollable');
      }
      final state = tester.state<ScrollableState>(scrollable);
      if ((originalScrollable != null &&
              !identical(state, originalScrollable)) ||
          !identical(state.position, originalScrollController.position)) {
        stop('Main reveal lost its original Scrollable');
      }
      originalScrollable ??= state;
    }

    while (true) {
      requireOriginal();
      if (clock.elapsed > const Duration(seconds: 60)) {
        stop('Main did not mount requested unit');
      }
      final targetCount = target.evaluate().length;
      if (targetCount > 1) stop('Main reveal target is not unique');
      if (targetCount == 1) {
        if (!identical(
          Scrollable.maybeOf(target.evaluate().single),
          originalScrollable,
        )) {
          stop('Main reveal target belongs to another Scrollable');
        }
        break;
      }
      final wanted = originalController.messages.indexWhere(
        (item) => item.id == unitId,
      );
      final visible = _mainRevealIndices(
        originalController,
        originalScrollable!,
        visibleOnly: true,
      );
      if (wanted < 0 || visible.isEmpty) {
        stop('Main reveal has no target index or visible Main anchor');
      }
      if (wanted >= visible.first && wanted <= visible.last) {
        stop('Main reveal target is absent inside the visible Main range');
      }
      final axisDirection = originalScrollable!.axisDirection;
      // Flyer reverses both the viewport axis and the controller-to-sliver
      // index mapping. Increasing pixels therefore approaches older Main items
      // on a reversed list, and newer ones on a non-reversed list.
      final forward =
          (wanted < visible.first) == axisDirectionIsReversed(axisDirection);
      final delta = switch (axisDirection) {
        AxisDirection.up => Offset(0, forward ? 240 : -240),
        AxisDirection.down => Offset(0, forward ? -240 : 240),
        AxisDirection.left || AxisDirection.right => stop(
          'Main reveal expected the production vertical Main list',
        ),
      };
      await tester.drag(scrollable, delta);
      requireOriginal();
      await tester.pump(const Duration(milliseconds: 16));
      requireOriginal();
      expect(tester.takeException(), isNull);
    }
    await tester.ensureVisible(target);
    requireOriginal();
    await tester.pump();
    requireOriginal();
    if (target.evaluate().length != 1) {
      stop('Main reveal lost its unique mounted target');
    }
  }

  List<int> _mainRevealIndices(
    ChatController controller,
    ScrollableState main, {
    required bool visibleOnly,
  }) {
    final indices = <int>{};
    // ChatItemView is the canonical Main container, including typed payloads
    // and groups. Its inner TimelineDisplayUnitView must not be counted twice.
    final rows = find.byType(ChatItemView, skipOffstage: visibleOnly);
    for (final element in rows.evaluate()) {
      if (!identical(Scrollable.maybeOf(element), main)) continue;
      final unit = (element.widget as ChatItemView).item.displayUnit;
      if (unit == null || unit.live) {
        continue; // Not a Main item (e.g. an Atom).
      }
      final index = controller.messages.indexWhere(
        (message) =>
            message.id == unit.id &&
            identical(message.metadata?[timelineDisplayUnitKey], unit),
      );
      if (index < 0) continue;
      if (visibleOnly) {
        final box = element.findRenderObject();
        if (box is! RenderBox || !box.attached || !box.hasSize) continue;
        final viewport = RenderAbstractViewport.maybeOf(box);
        if (viewport is! RenderViewport ||
            !identical(viewport.offset, main.position) ||
            !viewport.attached ||
            !viewport.hasSize) {
          continue;
        }
        final rect = MatrixUtils.transformRect(
          box.getTransformTo(viewport),
          Offset.zero & box.size,
        );
        final intersection = rect.intersect(Offset.zero & viewport.size);
        if (intersection.width <= 0 || intersection.height <= 0) continue;
      }
      indices.add(index);
    }
    return indices.toList()..sort();
  }

  Future<TimelineGroupDisplay> openGroup(String id) async {
    final originalLease = lease;
    final value = unit(id);
    final originalController = lease.controller;
    final originalGeneration = lease.generation;
    final mainSets = lease.appliedSets;
    expect(value.item.kind, TimelineItemKind.workGroup);
    expect(value.item.members, isNotNull);
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
      // Main and GroupMembers are delivered independently. Keep the bound,
      // but qualify both observed views before accepting this open.
      return display?.isCurrent == true &&
          display?.expanded == true &&
          display!.atoms.isNotEmpty &&
          display!.atoms.length <= unit(id).item.summary!.memberCount;
    }, 'mounted original ordinary group $id');
    expect(display!.atoms, isNotEmpty);
    expect(display!.membersRef, value.item.members);
    expect(display!.atoms.map((atom) => atom.source).toSet(), {
      value.item.source,
    });
    expect(
      display!.atoms.length,
      lessThanOrEqualTo(unit(id).item.summary!.memberCount),
    );
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

  Future<void> revealItem(TimelineItem item) async {
    expect(item.kind, isNot(TimelineItemKind.workGroup));
    await reveal(itemRow(item.id), item.id);
  }

  Future<TimelineGroupDisplay> revealMember(
    ChatAtom atom, {
    required TimelineMembersRef reference,
  }) async {
    final value = unit(reference.itemId);
    expect(value.item.members, reference);
    final display = await openGroup(value.id);
    expect(display.atoms.where((entry) => entry.id == atom.id), hasLength(1));
    final children = find.descendant(
      of: groupRow(value.id),
      matching: find.byType(TimelineChildrenView),
    );
    await until(
      () => children.evaluate().length == 1,
      'original member viewport ${value.id}',
    );
    final view = tester.widget<TimelineChildrenView>(children);
    final list = find.descendant(
      of: children,
      matching: find.byKey(
        ValueKey(('timeline-children-list', view.generation)),
      ),
    );
    expect(list, findsOneWidget);
    // The list's own Scrollable precedes any text-internal scrollables.
    final scrollable = find
        .descendant(of: list, matching: find.byType(Scrollable))
        .first;
    expect(scrollable, findsOneWidget);
    await tester.ensureVisible(children);
    await tester.pump();
    // Members have their own bounded viewport and controller order. Main's
    // parent index cannot locate a lazily mounted member inside that viewport.
    final clock = Stopwatch()..start();
    while (memberRow(atom.id).evaluate().isEmpty) {
      if (clock.elapsed > const Duration(seconds: 60)) {
        fail('Group ${value.id} did not mount original member ${atom.id}');
      }
      expect(display.isCurrent, isTrue);
      expect(display.error, isNull);
      final ordered = view.controller.messages
          .map((message) => message.id)
          .toList();
      final wanted = ordered.indexOf(atom.id);
      expect(wanted, greaterThanOrEqualTo(0));
      final mounted =
          tester
              .widgetList<ChatItemView>(
                find.descendant(
                  of: children,
                  matching: find.byType(ChatItemView),
                ),
              )
              .map((widget) => ordered.indexOf(widget.item.id))
              .where((index) => index >= 0)
              .toList()
            ..sort();
      if (mounted.isNotEmpty) {
        if (wanted > mounted.last) {
          await tester.drag(scrollable, const Offset(0, -240));
        } else if (wanted < mounted.first) {
          await tester.drag(scrollable, const Offset(0, 240));
        }
      }
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    }
    await tester.ensureVisible(memberRow(atom.id));
    await tester.pump();
    expect(memberRow(atom.id), findsOneWidget);
    final rendered = tester.widget<ChatItemView>(memberRow(atom.id)).item.atom!;
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
          !display.isCurrent &&
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
