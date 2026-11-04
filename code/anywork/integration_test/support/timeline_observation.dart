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
    TimelineDisplayUnit? originalUnit;
    Finder interaction = target;
    Element? interactionHeader;
    var phase = 'capture';
    final demands = <Map<String, Object?>>[];

    bool matchesCanonical(Element element) {
      final widget = element.widget;
      final unit = originalUnit;
      return unit != null &&
          !unit.live &&
          widget is ChatItemView &&
          widget.item.id == unitId &&
          identical(widget.item.displayUnit, unit) &&
          identical(Scrollable.maybeOf(element), originalScrollable);
    }

    final canonical = find.byElementPredicate(
      matchesCanonical,
      description: 'original canonical Main row $unitId (including cache)',
      skipOffstage: false,
    );
    final onstageCanonical = find.byElementPredicate(matchesCanonical);

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
      final canonicalElements = canonical.evaluate().toList();
      final targetElements = target.evaluate().toList();
      Object? currentMetadata;
      if (wanted != null && wanted >= 0) {
        currentMetadata = originalController
            .messages[wanted]
            .metadata?[timelineDisplayUnitKey];
      }
      final diagnostic = {
        'phase': phase,
        'targetId': unitId,
        'mainIndex': wanted,
        'elapsedMillis': clock.elapsedMilliseconds,
        'original': {
          'lease': identityHashCode(originalLease),
          'controller': identityHashCode(originalController),
          'scrollController': identityHashCode(originalScrollController),
          'generation': originalGeneration,
          'mounted': originalLease.isMounted,
          'retired': originalLease.isRetired,
          'released': originalLease.isReleased,
        },
        'current': {
          'lease': currentLease == null ? null : identityHashCode(currentLease),
          'controller':
              currentLease == null ||
                  currentLease.isRetired ||
                  currentLease.isReleased
              ? null
              : identityHashCode(currentLease.controller),
          'generation': currentLease?.generation,
          'borrowError': borrowError,
        },
        'scrollableCount': matches.length,
        'originalScrollable': originalScrollable == null
            ? null
            : identityHashCode(originalScrollable),
        'sameScrollable': state != null && identical(state, originalScrollable),
        'pixels': position?.hasPixels == true ? position!.pixels : null,
        'min': position?.hasContentDimensions == true
            ? position!.minScrollExtent
            : null,
        'max': position?.hasContentDimensions == true
            ? position!.maxScrollExtent
            : null,
        'viewport': position?.hasViewportDimension == true
            ? position!.viewportDimension
            : null,
        'axisDirection': position?.axisDirection.name,
        'visibleMainIndices': visible.take(40).toList(),
        'visibleMainCount': visible.length,
        'mountedMainIndices': mounted.take(40).toList(),
        'mountedMainCount': mounted.length,
        'cachedMainIndices': mounted
            .where((index) => !visible.contains(index))
            .take(40)
            .toList(),
        'cachedMainCount': mounted.length - visible.length,
        'targetMainRowMounted': mounted.contains(wanted),
        'originalMetadata': _mainRevealUnitInfo(originalUnit),
        'currentMetadataType': currentMetadata.runtimeType.toString(),
        'sameMetadata':
            originalUnit != null && identical(originalUnit, currentMetadata),
        'currentMetadata': currentMetadata is TimelineDisplayUnit
            ? _mainRevealUnitInfo(currentMetadata)
            : null,
        'canonicalFinderCount': canonicalElements.length,
        'canonicalOnstageFinderCount': onstageCanonical.evaluate().length,
        'canonical': canonicalElements
            .take(3)
            .map((element) => _mainRevealElementInfo(element, state))
            .toList(),
        'canonicalRenderBranches': _mainRevealBranches(canonical),
        'targetFinder': target.describeMatch(Plurality.many),
        'targetSkipOffstage': target.skipOffstage,
        'targetFinderCount': targetElements.length,
        'targetHitTestableCount': target.hitTestable().evaluate().length,
        'target': targetElements
            .take(3)
            .map((element) => _mainRevealElementInfo(element, state))
            .toList(),
        'interactionRole': interactionHeader == null
            ? 'originalFragment'
            : 'groupHeaderTitle',
        'interactionTitle': interactionHeader == null
            ? null
            : {
                'finderCount': interaction.evaluate().length,
                'hitTestableCount': interaction.hitTestable().evaluate().length,
                'elements': interaction
                    .evaluate()
                    .take(3)
                    .map((element) => _mainRevealElementInfo(element, state))
                    .toList(),
              },
        'scrollDemands': demands,
        'pointerEvidenceLimit': 'Read-only hit test at exact dragFrom start; actual dispatch cache and gesture-arena winning receiver are not exposed by WidgetTester.',
      };
      fail('$reason: ${jsonEncode(diagnostic)}');
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
      final messages = originalController.messages
          .where((message) => message.id == unitId)
          .toList();
      if (messages.length != 1) {
        stop('Main reveal requires one original controller item');
      }
      final metadata = messages.single.metadata?[timelineDisplayUnitKey];
      if (metadata is! TimelineDisplayUnit ||
          metadata.live ||
          metadata.id != unitId) {
        stop('Main reveal requires the original Main metadata');
      }
      if (originalUnit == null) {
        originalUnit = metadata;
      } else if (!identical(metadata, originalUnit)) {
        stop('Main reveal lost its original metadata identity');
      }
      if (canonical.evaluate().length > 1) {
        stop('Main reveal canonical row is not unique');
      }
      final fragments = target.evaluate().toList();
      if (fragments.length > 1) {
        stop('Main reveal fragment is not unique');
      }
      if (fragments.length == 1 &&
          !identical(Scrollable.maybeOf(fragments.single), state)) {
        stop('Main reveal fragment belongs to another Scrollable');
      }
    }

    bool belongsTo(Element element, Element ancestor) {
      var belongs = identical(element, ancestor);
      element.visitAncestorElements((candidate) {
        if (identical(candidate, ancestor)) {
          belongs = true;
          return false;
        }
        return true;
      });
      return belongs;
    }

    Element requireTarget() {
      final matches = target.evaluate().toList();
      if (matches.length != 1) {
        stop(
          'Main canonical row is visible but the original fragment is absent',
        );
      }
      final row = canonical.evaluate().toList();
      if (row.length != 1 ||
          !identical(Scrollable.maybeOf(matches.single), originalScrollable)) {
        stop('Main reveal fragment lost its original Main domain');
      }
      if (!belongsTo(matches.single, row.single)) {
        stop('Main reveal fragment belongs to another canonical row');
      }
      return matches.single;
    }

    void requireInteraction() {
      final fragment = requireTarget();
      final header = interactionHeader;
      if (header == null) return;
      final headers = groupHeader(unitId).evaluate().toList();
      if (originalUnit!.item.kind != TimelineItemKind.workGroup ||
          headers.length != 1 ||
          !identical(headers.single, header) ||
          !identical(fragment, header)) {
        stop('Main reveal lost its exact original group header');
      }
      final titles = interaction.evaluate().toList();
      if (titles.length != 1 ||
          !belongsTo(titles.single, header) ||
          !identical(Scrollable.maybeOf(titles.single), originalScrollable)) {
        stop('Main reveal requires the exact header title in its Main domain');
      }
    }

    Future<void> demand(
      String kind,
      Future<void> Function() operation, {
      Map<String, Object?>? pointer,
    }) async {
      requireOriginal();
      if (clock.elapsed > const Duration(seconds: 60)) {
        stop('Main reveal exceeded its original deadline');
      }
      phase = kind;
      final record = <String, Object?>{
        'kind': kind,
        'beforePixels': originalScrollable!.position.pixels,
        'afterPixels': null,
        'afterLayoutPixels': null,
        'pointer': pointer,
      };
      if (demands.length == 6) demands.removeAt(0);
      demands.add(record);
      try {
        await operation();
      } catch (error) {
        final description = error.toString();
        record['operationError'] = description.length > 500
            ? description.substring(0, 500)
            : description;
        requireOriginal();
        stop('Main reveal scroll demand failed');
      }
      requireOriginal();
      record['afterPixels'] = originalScrollable!.position.pixels;
      await tester.pump(const Duration(milliseconds: 16));
      requireOriginal();
      record['afterLayoutPixels'] = originalScrollable!.position.pixels;
      final error = tester.takeException();
      if (error != null) {
        final description = error.toString();
        record['layoutError'] = description.length > 500
            ? description.substring(0, 500)
            : description;
        stop('Main reveal encountered a layout/framework error');
      }
      if (clock.elapsed > const Duration(seconds: 60)) {
        stop('Main reveal exceeded its original deadline');
      }
    }

    while (true) {
      requireOriginal();
      if (clock.elapsed > const Duration(seconds: 60)) {
        stop('Main did not mount the requested canonical row');
      }
      if (canonical.evaluate().isNotEmpty) break;
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
        stop('Main canonical row is absent inside the visible Main range');
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
      final start = tester.getCenter(scrollable);
      final view = View.of(tester.element(scrollable));
      final pointer = _mainRevealPointer(start, delta, view.viewId);
      await demand(
        'drag to mount canonical',
        () => tester.dragFrom(start, delta, view: view),
        pointer: pointer,
      );
      requireOriginal();
    }
    await demand(
      'ensure canonical visible',
      () => tester.ensureVisible(canonical),
    );
    requireOriginal();
    final wanted = originalController.messages.indexWhere(
      (message) => message.id == unitId,
    );
    if (!_mainRevealIndices(
      originalController,
      originalScrollable!,
      visibleOnly: true,
    ).contains(wanted)) {
      stop('Main canonical row did not become visible after ensureVisible');
    }
    final fragmentElement = requireTarget();
    if (originalUnit!.item.kind == TimelineItemKind.workGroup) {
      final headers = groupHeader(unitId).evaluate().toList();
      if (headers.length > 1) {
        stop('Main reveal group header is not unique');
      }
      if (headers.length == 1 && identical(fragmentElement, headers.single)) {
        // This is the same title used by openGroup, selected by exact header
        // identity before any fragment demand, not a failed-hit fallback.
        interactionHeader = fragmentElement;
        interaction = _groupTitle(unitId);
      }
    }
    requireInteraction();
    await demand(
      interactionHeader == null
          ? 'ensure original fragment visible'
          : 'ensure original group title visible',
      () => tester.ensureVisible(interaction),
    );
    requireOriginal();
    requireInteraction();
    final fragment = target.evaluate().single.findRenderObject();
    if (fragment is! RenderBox || !fragment.attached || !fragment.hasSize) {
      stop('Main original fragment has no attached sized RenderBox');
    }
    final viewport = RenderAbstractViewport.maybeOf(fragment);
    if (viewport is! RenderViewport ||
        !identical(viewport.offset, originalScrollable!.position) ||
        !viewport.attached ||
        !viewport.hasSize) {
      stop('Main original fragment lost its original sized viewport');
    }
    final rect = MatrixUtils.transformRect(
      fragment.getTransformTo(viewport),
      Offset.zero & fragment.size,
    );
    final visible = rect.intersect(Offset.zero & viewport.size);
    if (!rect.isFinite || visible.width <= 0 || visible.height <= 0) {
      stop('Main original fragment is not geometrically visible');
    }
    if (interaction.hitTestable().evaluate().length != 1) {
      stop('Main interaction target is not hit-testable after ensureVisible');
    }
  }

  Map<String, Object?>? _mainRevealUnitInfo(TimelineDisplayUnit? unit) {
    if (unit == null) return null;
    final ref = unit.item.members;
    return {
      'identity': identityHashCode(unit),
      'id': unit.id,
      'kind': unit.item.kind.name,
      'live': unit.live,
      'membersRef': ref == null
          ? null
          : {
              'itemId': ref.itemId,
              'databaseId': ref.databaseId,
              'projectionVersion': ref.projectionVersion,
              'projectionGeneration': ref.projectionGeneration,
            },
    };
  }

  Map<String, Object?> _mainRevealElementInfo(
    Element element,
    ScrollableState? main,
  ) {
    final widget = element.widget;
    ChatItemView? row = widget is ChatItemView ? widget : null;
    if (row == null) {
      element.visitAncestorElements((ancestor) {
        final widget = ancestor.widget;
        if (widget is ChatItemView) {
          row = widget;
          return false;
        }
        return true;
      });
    }
    final render = element.findRenderObject();
    final viewport = RenderAbstractViewport.maybeOf(render);
    final box = render is RenderBox ? render : null;
    Rect? rect;
    if (box != null &&
        box.attached &&
        box.hasSize &&
        viewport is RenderViewport &&
        viewport.attached &&
        viewport.hasSize) {
      rect = MatrixUtils.transformRect(
        box.getTransformTo(viewport),
        Offset.zero & box.size,
      );
    }
    final nearest = Scrollable.maybeOf(element);
    return {
      'widget': widget.runtimeType.toString(),
      'key': widget.key?.toString(),
      'presentationType': row?.item.type,
      'compatibility': row?.item.compatibility.name,
      'metadata': _mainRevealUnitInfo(row?.item.displayUnit),
      'scrollable': nearest == null ? null : identityHashCode(nearest),
      'sameMainScrollable': identical(nearest, main),
      'renderType': render.runtimeType.toString(),
      'attached': render?.attached,
      'hasSize': box?.hasSize,
      'size': box != null && box.hasSize
          ? [box.size.width, box.size.height]
          : null,
      'rectInViewport': _mainRevealRect(rect),
      'viewportRect': viewport is RenderViewport && viewport.hasSize
          ? _mainRevealRect(Offset.zero & viewport.size)
          : null,
      'sameMainViewport':
          viewport is RenderViewport &&
          main != null &&
          identical(viewport.offset, main.position),
    };
  }

  List<double>? _mainRevealRect(Rect? rect) {
    if (rect == null) return null;
    final values = [rect.left, rect.top, rect.right, rect.bottom];
    return values.every((value) => value.isFinite) ? values : null;
  }

  List<Map<String, Object?>> _mainRevealBranches(Finder canonical) {
    final branches = find.descendant(
      of: canonical,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is TimelineDisplayUnitView ||
            widget is TimelineActivityRow ||
            widget is Text,
        skipOffstage: false,
      ),
      skipOffstage: false,
    );
    return [
      for (final element in branches.evaluate().take(16))
        {
          'widget': element.widget.runtimeType.toString(),
          'key': element.widget.key?.toString(),
        },
    ];
  }

  Map<String, Object?> _mainRevealPointer(
    Offset start,
    Offset delta,
    int viewId,
  ) {
    final hit = tester.hitTestOnBinding(start, viewId: viewId);
    return {
      'start': [start.dx, start.dy],
      'delta': [delta.dx, delta.dy],
      'viewId': viewId,
      'hitPathCount': hit.path.length,
      'hitPathAtExactStart': hit.path.take(10).map((entry) {
        final target = entry.target;
        final creator = target is RenderObject ? target.debugCreator : null;
        final element = creator is DebugCreator ? creator.element : null;
        final scrollable = element == null ? null : Scrollable.maybeOf(element);
        return {
          'target': target.runtimeType.toString(),
          'creatorWidget': element?.widget.runtimeType.toString(),
          'creatorScrollable': scrollable == null
              ? null
              : identityHashCode(scrollable),
        };
      }).toList(),
      'dispatchReceiver': null,
      'receiverUnavailableReason': 'WidgetTester exposes a read-only hit test, not the delivered hit-test cache or gesture-arena winner.',
    };
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
