import 'dart:convert';

import 'package:anywork/src/features/conversation/timeline/state/timeline_display_diagnostics.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_member_atom.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_display_unit_view.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finds the current title inside one exact header without resolving the header
/// again for every candidate. A clock may replace a custom label during a pump.
Finder timelineGroupTitleFinder(
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
        value.id,
        reason: 'one canonical Main card owns one Message',
      );
      expect(value.historyPos, greaterThan(0));
      if (value.body case WorkDisplayBlock(:final summary, :final members)) {
        expect(summary.total, greaterThan(0));
        expect(members.blockId, value.id);
      } else {
        expect(value.body, isA<SingleDisplayBlock>());
      }
      yield value;
    }
  }

  Iterable<TimelineDisplayUnit> get singleBlocks =>
      main.where((unit) => unit.body is SingleDisplayBlock);
  Iterable<ChatAtom> get mountedMembers =>
      lease.groupDisplays.expand((display) => display.atoms);
  Iterable<LiveDisplayBlock> get liveBlocks =>
      lease.live.value?.blocks ?? const [];
  Iterable<TimelineDisplayUnit> get liveWork => liveBlocks
      .where((block) => block.body is WorkDisplayBlock)
      .map(
        (block) => lease.liveUnit(block, lease.live.value!.executionPresent),
      );
  Iterable<ChatAtom> get liveAtoms sync* {
    final workIds = liveWork.map((block) => block.id).toSet();
    for (final block in liveBlocks) {
      if (block.body case SingleDisplayBlock(:final atom)) yield atom;
    }
    for (final display in lease.groupDisplays) {
      if (workIds.contains(display.unitId)) yield* display.atoms;
    }
  }

  Iterable<TimelineDisplayUnit> get workBlocks =>
      main.where((unit) => unit.body is WorkDisplayBlock);
  Iterable<TimelineDisplayUnit> get allWork sync* {
    yield* workBlocks;
    yield* liveWork;
  }

  /// Explicit bounded provenance evidence, not an atom-history scan or a cache.
  Future<DisplayMemberPage> readMemberPage(
    DisplayBlockRef reference, {
    DisplayMemberWindow window = const LatestDisplayMembers(),
    ReadDemand demand = const ReadDemand(maxItems: 1, maxBytes: 16384),
  }) async {
    final original = lease;
    final handle = await original.openDisplayMembers(
      reference: reference,
      window: window,
      demand: demand,
    );
    try {
      final page = await handle.next();
      expect(lease, same(original));
      expect(page, isNotNull);
      expect(page!.block, reference);
      return page;
    } finally {
      handle.requestClose();
      await handle.close();
    }
  }

  Future<List<TimelineDisplayUnit>> workForSource(ChatSourceId source) async {
    final matched = <TimelineDisplayUnit>[];
    for (final block in allWork.toList()) {
      final page = await readMemberPage(block.memberReference!);
      expect(page.entries, isNotEmpty);
      if (page.entries.single.atom.source == source) matched.add(block);
    }
    return matched;
  }

  /// Explicit finite fixture inventory. UI still owns just its selected page.
  Future<List<DisplayMemberHead>> readMemberInventory(
    TimelineDisplayUnit block, {
    required int expectedCount,
  }) async {
    expect(block.summary!.total, expectedCount);
    final result = <DisplayMemberHead>[];
    DisplayMemberWindow window = const LatestDisplayMembers();
    int? revision;
    while (true) {
      final page = await readMemberPage(
        block.memberReference!,
        window: window,
        demand: const ReadDemand(maxItems: 12, maxBytes: 64 * 1024),
      );
      revision ??= page.revision;
      expect(
        page.revision,
        revision,
        reason: 'A mutable fixture inventory must stay at one structural cut',
      );
      result.insertAll(0, page.entries);
      expect(result.length, lessThanOrEqualTo(expectedCount));
      final before = page.before;
      if (before == null) break;
      window = BeforeDisplayMembers(memberOrder: before);
    }
    expect(result, hasLength(expectedCount));
    expect(
      result.map((head) => head.memberKey).toSet(),
      hasLength(expectedCount),
    );
    var previous = 0;
    for (final head in result) {
      expect(head.memberOrder, greaterThan(previous));
      previous = head.memberOrder;
    }
    return List.unmodifiable(result);
  }

  Future<List<ChatAtom>> readFixtureAtoms(
    TimelineDisplayUnit block, {
    required int expectedCount,
  }) async {
    final heads = await readMemberInventory(
      block,
      expectedCount: expectedCount,
    );
    final scope = lease.content.openScope(generation: lease.generation);
    try {
      final atoms = <ChatAtom>[];
      for (final head in heads) {
        if (head.completionId == null) {
          atoms.add(head.atom);
        } else {
          final original = await scope.readCompleted(
            recordId: head.completionId!,
            demand: const ReadDemand(maxItems: 1, maxBytes: 64 * 1024),
          );
          expect(original.atom.id, head.atom.id);
          expect(original.atom.source, head.atom.source);
          expect(original.recordId, head.completionId);
          expect(original.completionSeq, head.atom.completionSeq);
          atoms.add(original.atom);
        }
      }
      return List.unmodifiable(atoms);
    } finally {
      scope.retire();
      expect((await scope.close()).complete, isTrue);
    }
  }

  TimelineDisplayUnit unitForMember(String id) => unit(
    lease.groupDisplays
        .singleWhere((display) => display.atoms.any((atom) => atom.id == id))
        .unitId,
  );
  Future<void> openSourceWork(ChatSourceId source) async {
    for (final block in await workForSource(source)) {
      await openWork(block.id);
    }
  }

  TimelineDisplayUnit unit(String id) {
    final historical = main.where((unit) => unit.id == id).singleOrNull;
    if (historical != null) return historical;
    final block = liveBlocks.singleWhere((block) => block.id == id);
    return lease.liveUnit(block, lease.live.value!.executionPresent);
  }

  TimelineDisplayUnit unitForBlock(DisplayBlockRef reference) =>
      allWork.singleWhere((unit) => unit.memberReference == reference);

  Finder groupRow(String id, {bool skipOffstage = true}) =>
      find.byWidgetPredicate(
        (widget) => widget is TimelineDisplayUnitView && widget.unit.id == id,
        skipOffstage: skipOffstage,
      );
  Finder itemRow(String id) => find.byWidgetPredicate(
    (widget) => widget is ChatItemView && widget.item.id == id,
  );
  Finder memberRow(String id) => find.byWidgetPredicate(
    (widget) => widget is ChatItemView && widget.item.atom?.id == id,
  );
  Finder groupHeader(String id, {bool skipOffstage = true}) => find.descendant(
    of: groupRow(id, skipOffstage: skipOffstage),
    matching: find.byKey(
      ValueKey('completion-run-header:$id'),
      skipOffstage: skipOffstage,
    ),
    skipOffstage: skipOffstage,
  );

  Finder _groupTitle(String id, {bool skipOffstage = true}) {
    final header = groupHeader(id, skipOffstage: skipOffstage);
    expect(header, findsOneWidget);
    final originalLease = lease;
    final originalController = originalLease.controller;
    final originalGeneration = originalLease.generation;
    // The header's Align/Row can have its centre in a Spacer, outside its
    // children's hit path. Target the real title inside this exact unit, not
    // the disclosure's body or another group's identically labelled header.
    final title = timelineGroupTitleFinder(
      tester,
      header,
      skipOffstage: skipOffstage,
      validateOwner: () {
        final current = lease;
        if (!identical(current, originalLease) ||
            originalLease.isRetired ||
            originalLease.isReleased ||
            !originalLease.isMounted ||
            !identical(current.controller, originalController) ||
            current.generation != originalGeneration) {
          fail('Timeline owner changed while resolving Work title $id');
        }
      },
    );
    expect(title, findsOneWidget);
    return title;
  }

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
    double scrollAlignment = 0,
    bool Function()? isActive,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (timeout <= Duration.zero) {
      fail('Tapping a production control requires a positive deadline');
    }
    if (isActive?.call() == false) return;
    expect(target, findsOneWidget);
    final clock = Stopwatch()..start();
    while (true) {
      if (isActive?.call() == false) return;
      if (clock.elapsed >= timeout) {
        fail('Timed out waiting for hittable production control');
      }
      if (target.hitTestable().evaluate().length == 1) break;
      // A nested scroll can change the outer viewport's target geometry on the
      // next layout. Reveal the same control again, never tap a surrogate.
      await Scrollable.ensureVisible(
        tester.element(target),
        alignment: scrollAlignment,
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      if (isActive?.call() == false) return;
      if (clock.elapsed >= timeout) {
        fail('Timed out waiting for hittable production control');
      }
      if (target.hitTestable().evaluate().length == 1) break;
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    }
    if (clock.elapsed >= timeout) {
      fail('Timed out waiting for hittable production control');
    }
    await tester.tap(target);
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  Future<void> reveal(
    Finder target,
    String unitId, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final deadline = timeout < const Duration(seconds: 60)
        ? timeout
        : const Duration(seconds: 60);
    if (deadline <= Duration.zero) {
      fail('Main reveal requires a positive deadline');
    }
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
    var interactionIsHeader = false;
    var phase = 'capture';
    final demands = <Map<String, Object?>>[];

    bool matchesCanonical(Element element) {
      final widget = element.widget;
      final unit = originalUnit;
      return unit != null &&
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
        'interactionRole': interactionIsHeader
            ? 'groupHeaderTitle'
            : 'originalFragment',
        'interactionTitle': !interactionIsHeader
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
      if (metadata is! TimelineDisplayUnit || metadata.id != unitId) {
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

    bool borrowInteraction() {
      // Elements are frame-local borrows. Only the original Main owner,
      // metadata and scroll qualification survive a layout boundary.
      final rows = canonical.evaluate().toList();
      final fragments = target.evaluate().toList();
      if (rows.isEmpty || fragments.isEmpty) return false;
      final fragment = requireTarget();
      interaction = target;
      interactionIsHeader = false;
      if (originalUnit!.body is SingleDisplayBlock) return true;
      final headers = groupHeader(unitId).evaluate().toList();
      if (headers.length > 1) {
        stop('Main reveal group header is not unique');
      }
      if (headers.isEmpty || !identical(fragment, headers.single)) return true;
      final header = headers.single;
      interactionIsHeader = true;
      interaction = _groupTitle(unitId);
      final titles = interaction.evaluate().toList();
      if (titles.length > 1) {
        stop('Main reveal group header title is not unique');
      }
      if (titles.isEmpty) return false;
      if (!belongsTo(titles.single, header) ||
          !identical(Scrollable.maybeOf(titles.single), originalScrollable)) {
        stop('Main reveal requires the exact header title in its Main domain');
      }
      return true;
    }

    bool fragmentVisible() {
      final fragment = requireTarget().findRenderObject();
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
      if (!rect.isFinite) {
        stop('Main original fragment has nonfinite geometry');
      }
      final visible = rect.intersect(Offset.zero & viewport.size);
      return visible.width > 0 && visible.height > 0;
    }

    Future<void> demand(
      String kind,
      Future<void> Function() operation, {
      Map<String, Object?>? pointer,
    }) async {
      requireOriginal();
      if (clock.elapsed >= deadline) {
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
      if (clock.elapsed >= deadline) {
        stop('Main reveal exceeded its original deadline');
      }
    }

    while (true) {
      requireOriginal();
      if (clock.elapsed >= deadline) {
        stop('Main did not reveal the requested canonical row');
      }
      if (canonical.evaluate().isNotEmpty) {
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
          // A cached row can move again while the reversed list measures it.
          continue;
        }
        if (!borrowInteraction()) {
          await demand('wait for same Main fragment layout', () async {});
          continue;
        }
        // The canonical demand may already have exposed the exact title. Do
        // not move a ready fragment back to the reversed viewport's edge.
        if (fragmentVisible() &&
            interaction.hitTestable().evaluate().length == 1) {
          return;
        }
        await demand(
          interactionIsHeader
              ? 'ensure original group title visible'
              : 'ensure original fragment visible',
          () => tester.ensureVisible(interaction),
        );
        requireOriginal();
        // ensureVisible and its next layout may rebuild the header or move the
        // whole row back into cache. Resume the same state machine, not a new
        // reveal/reader and not an expired Element qualification.
        if (!_mainRevealIndices(
              originalController,
              originalScrollable!,
              visibleOnly: true,
            ).contains(
              originalController.messages.indexWhere(
                (message) => message.id == unitId,
              ),
            ) ||
            !borrowInteraction()) {
          continue;
        }
        if (fragmentVisible() &&
            interaction.hitTestable().evaluate().length == 1) {
          return;
        }
        continue;
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
  }

  Map<String, Object?>? _mainRevealUnitInfo(TimelineDisplayUnit? unit) {
    if (unit == null) return null;
    final ref = unit.memberReference;
    return {
      'identity': identityHashCode(unit),
      'id': unit.id,
      'kind': unit.body is WorkDisplayBlock ? 'work' : 'single',
      'historyPos': unit.historyPos,
      'blockReference': ref == null
          ? null
          : {'databaseId': ref.databaseId, 'blockId': ref.blockId},
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
      if (unit == null) {
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

  Future<TimelineGroupDisplay> openWork(
    String id, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final originalLease = lease;
    final value = unit(id);
    final reference = value.memberReference;
    expect(reference, isNotNull);
    final controller = lease.controller;
    final sets = lease.appliedSets;
    final header = groupHeader(id);
    if (value.historyPos != null) {
      await reveal(header, id, timeout: timeout);
    } else {
      await until(
        () => header.evaluate().length == 1,
        'live Work header $id',
        timeout: timeout,
      );
    }
    if (!tester.widget<TimelineActivityRow>(header).expanded) {
      await tap(_groupTitle(id), timeout: timeout);
    }
    TimelineGroupDisplay? display;
    await until(
      () {
        display = lease.groupDisplays
            .where((display) => display.unitId == id)
            .singleOrNull;
        if (display?.error case final error?) throw StateError('$error');
        return display?.isCurrent == true &&
            display?.expanded == true &&
            display?.loading == false &&
            display!.atoms.isNotEmpty;
      },
      'bounded member page for Work $id',
      timeout: timeout,
    );
    expect(display!.blockReference, reference);
    expect(display!.atoms.length, lessThanOrEqualTo(unit(id).summary!.total));
    expect(
      display!.atoms.map((atom) => atom.id).toSet(),
      hasLength(display!.atoms.length),
    );
    expect(lease, same(originalLease));
    expect(lease.controller, same(controller));
    expect(
      lease.appliedSets,
      sets,
      reason: 'Member demand cannot replace Main',
    );
    return display!;
  }

  /// Demand one older page through the exact mounted Work's production control.
  /// The caller owns the total budget across opening, paging and qualification.
  Future<void> loadOlderMemberPage(
    TimelineGroupDisplay display, {
    required Duration timeout,
  }) async {
    if (timeout <= Duration.zero) {
      fail('Loading a member page requires a positive deadline');
    }
    final clock = Stopwatch()..start();
    Duration remaining() {
      final value = timeout - clock.elapsed;
      if (value <= Duration.zero) {
        fail('Timed out loading original member page ${display.unitId}');
      }
      return value;
    }

    final originalLease = lease;
    final reference = unit(display.unitId).memberReference!;
    final before = display.before;
    expect(before, isNotNull);
    void requireOriginal() {
      expect(lease, same(originalLease));
      expect(display.isCurrent, isTrue);
      expect(display.expanded, isTrue);
      expect(display.blockReference, reference);
      expect(
        lease.groupDisplays.singleWhere(
          (value) => value.unitId == display.unitId,
        ),
        same(display),
      );
      if (display.error case final error?) throw StateError('$error');
    }

    final older = find.descendant(
      of: groupRow(display.unitId),
      matching: find.widgetWithText(TextButton, '更早成员'),
    );
    await until(
      () {
        requireOriginal();
        expect(display.before, before);
        final matches = older.evaluate().length;
        expect(matches, lessThanOrEqualTo(1));
        return matches == 1 &&
            tester.widget<TextButton>(older).onPressed != null;
      },
      'enabled original member pagination control',
      timeout: remaining(),
    );
    await tap(older, timeout: remaining());
    await until(
      () {
        requireOriginal();
        return !display.loading && display.before != before;
      },
      'explicit original member page advanced',
      timeout: remaining(),
    );
    remaining();
  }

  Future<void> selectLatestMembers(
    TimelineGroupDisplay display, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final original = lease;
    if (unit(display.unitId).expansion.members!.window
        is LatestDisplayMembers) {
      return;
    }
    final latest = find.descendant(
      of: groupRow(display.unitId),
      matching: find.widgetWithText(TextButton, '最新成员'),
    );
    await tap(latest, timeout: timeout);
    await until(
      () {
        expect(lease, same(original));
        expect(display.isCurrent, isTrue);
        if (display.error case final error?) throw StateError('$error');
        return !display.loading &&
            unit(display.unitId).expansion.members!.window
                is LatestDisplayMembers;
      },
      'latest bounded member page',
      timeout: timeout,
    );
  }

  Future<void> revealSingle(
    TimelineDisplayUnit block, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    expect(block.body, isA<SingleDisplayBlock>());
    await reveal(itemRow(block.id), block.id, timeout: timeout);
  }

  Future<TimelineGroupDisplay> revealMember(
    ChatAtom atom, {
    required DisplayBlockRef reference,
  }) async {
    final value = unitForBlock(reference);
    final display = await openWork(value.id);
    if (!display.atoms.any((member) => member.id == atom.id)) {
      await selectLatestMembers(display);
    }
    final clock = Stopwatch()..start();
    while (!display.atoms.any((member) => member.id == atom.id)) {
      if (clock.elapsed >= const Duration(seconds: 60)) {
        fail('Member ${atom.id} not found in $reference');
      }
      expect(
        display.before,
        isNotNull,
        reason: 'The producer-defined member must be in this block',
      );
      await loadOlderMemberPage(
        display,
        timeout: const Duration(seconds: 60) - clock.elapsed,
      );
    }
    final row = find.byWidgetPredicate(
      (widget) => widget is TimelineMemberAtom && widget.atom.id == atom.id,
    );
    await until(() => row.evaluate().length == 1, 'mounted member ${atom.id}');
    await tester.ensureVisible(row);
    await tester.pump();
    final rendered = tester.widget<TimelineMemberAtom>(row).atom;
    expect(rendered.id, atom.id);
    expect(rendered.source, atom.source);
    expect(rendered.tool?.callId, atom.tool?.callId);
    if (atom.kind == ChatAtomKind.reasoning ||
        atom.kind == ChatAtomKind.toolCall) {
      final header = find
          .descendant(
            of: row,
            matching: find.byWidgetPredicate(
              (widget) => widget is TimelineActivityRow && widget.expandable,
            ),
          )
          .first;
      await until(
        () => header.evaluate().isNotEmpty,
        'readable member disclosure ${atom.id}',
      );
      if (!tester.widget<TimelineActivityRow>(header).expanded) {
        await tap(timelineGroupTitleFinder(tester, header));
      }
    }
    return display;
  }

  Future<void> closeWork(TimelineGroupDisplay display) async {
    if (display.isCurrent && display.expanded) {
      // This original owner is mounted in current or the Main cache. Reveal
      // its exact title directly, without navigating to a replacement row.
      if (display.isCurrent && display.expanded) {
        final title = tester.element(
          _groupTitle(display.unitId, skipOffstage: false),
        );
        await tap(
          find.byElementPredicate(
            (element) => identical(element, title),
            skipOffstage: false,
          ),
          isActive: () => display.isCurrent && display.expanded,
        );
      }
    }
    await until(
      () =>
          !display.expanded &&
          display.atoms.isEmpty &&
          !display.isCurrent &&
          display.before == null &&
          !display.loading,
      'collapsed member window revoked',
    );
    expect(display.error, isNull);
  }

  Future<void> closeSourceWork(
    ChatSourceId source, {
    Map<String, Object?>? diagnostics,
  }) async {
    final owner = lease;
    final controller = owner.controller;
    final generation = owner.generation;
    final ids = (await workForSource(source)).map((unit) => unit.id).toList();
    expect(ids, isNotEmpty);
    expect(ids.toSet(), hasLength(ids.length));
    final evidence = diagnostics ?? <String, Object?>{};
    final samples = <Map<String, Object?>>[];
    final tracked = <TimelineGroupDisplay>{};
    final clicked = <String>{};
    final clock = Stopwatch()..start();
    Map<String, Object?> displayState(TimelineGroupDisplay display) => {
      'identity': identityHashCode(display),
      'unitId': display.unitId,
      'expanded': display.expanded,
      'isCurrent': display.isCurrent,
      'atomCount': display.atoms.length,
      'windowCount': display.windows.length,
      'before': display.before,
      'loading': display.loading,
      'errorType': display.error?.runtimeType.toString(),
    };
    void sample(String stage, {String? id}) {
      final current = owner.groupDisplays
          .where((display) => ids.contains(display.unitId))
          .toList();
      tracked.addAll(current);
      final value = <String, Object?>{
        'stage': stage,
        'unitId': id,
        'elapsedMillis': clock.elapsedMilliseconds,
        'displays': current.take(32).map(displayState).toList(),
        'tracked': tracked.take(32).map(displayState).toList(),
        'clickedUnitIds': clicked.toList(),
      };
      evidence['last'] = value;
      if (samples.length < 64) samples.add(value);
    }

    Duration remaining() {
      final value = const Duration(seconds: 60) - clock.elapsed;
      if (value <= Duration.zero) {
        sample('timeout');
        fail('Timed out closing the original source Main cards');
      }
      return value;
    }

    void requireOwnerAndCollapsedCards() {
      expect(lease, same(owner));
      expect(owner.controller, same(controller));
      expect(owner.generation, generation);
      expect(owner.isRetired, isFalse);
      for (final id in clicked) {
        expect(
          unit(id).expansion.expanded,
          isFalse,
          reason: 'A real collapsed Main card must not reopen on remount: $id',
        );
      }
    }

    evidence.addAll({
      'generation': generation,
      'targetUnitIds': ids,
      'samples': samples,
      'complete': false,
    });
    sample('initial');
    try {
      for (final id in ids) {
        requireOwnerAndCollapsedCards();
        sample('before-reveal', id: id);
        if (unit(id).historyPos != null) {
          await reveal(groupHeader(id), id, timeout: remaining());
        } else {
          await until(
            () => groupHeader(id).evaluate().length == 1,
            'live Work header before collapse',
            timeout: remaining(),
          );
        }
        sample('after-reveal', id: id);
        requireOwnerAndCollapsedCards();
        final header = groupHeader(id);
        expect(header, findsOneWidget);
        if (tester.widget<TimelineActivityRow>(header).expanded) {
          TimelineGroupDisplay? current;
          await until(
            () {
              current = owner.groupDisplays
                  .where((display) => display.unitId == id)
                  .singleOrNull;
              if (current?.error case final error?) throw StateError('$error');
              return current?.isCurrent == true && current?.expanded == true;
            },
            'current display after revealing exact Main header $id',
            timeout: remaining(),
          );
          final original = current!;
          tracked.add(original);
          expect(original.blockReference, unit(id).memberReference!);
          sample('before-click', id: id);
          // Borrow after navigation. This dynamic exact-card title remains the
          // target if layout replaces its Element; retirement is not a click.
          await tap(_groupTitle(id), timeout: remaining());
          clicked.add(id);
          sample('after-click', id: id);
          requireOwnerAndCollapsedCards();
          await until(
            () =>
                !original.expanded &&
                !original.isCurrent &&
                original.atoms.isEmpty &&
                original.windows.isEmpty &&
                original.before == null &&
                !original.loading,
            'clicked original source member scope revoked',
            timeout: remaining(),
          );
          expect(original.error, isNull);
        } else {
          expect(unit(id).expansion.expanded, isFalse);
        }
        sample('card-collapsed', id: id);
      }
      requireOwnerAndCollapsedCards();
      expect(
        owner.groupDisplays.where(
          (display) => ids.contains(display.unitId) && display.expanded,
        ),
        isEmpty,
      );
      for (final id in ids) {
        expect(unit(id).expansion.expanded, isFalse);
      }
      await until(
        () => tracked.every(
          (display) =>
              !display.expanded &&
              !display.isCurrent &&
              display.atoms.isEmpty &&
              display.windows.isEmpty &&
              display.before == null &&
              !display.loading,
        ),
        'all borrowed source display resources revoked',
        timeout: remaining(),
      );
      for (final display in tracked) {
        expect(display.error, isNull);
      }
      evidence['complete'] = true;
    } finally {
      sample('final');
    }
  }
}
