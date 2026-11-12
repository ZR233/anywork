import 'dart:convert';

import 'package:anywork/src/domain/models/composer_primary_action.dart';
import 'package:anywork/src/features/conversation/composer/views/prompt_composer_view.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_diagnostics.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_member_atom.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/conversation_current_connector.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_display_unit_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_reasoning_view.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_content_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_canonical_payload_connector.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _sourceCut(ChatSourceId source) => switch (source) {
  ForegroundTurnChatSource(:final turnId) => {
    'kind': 'foregroundTurn',
    'turnId': turnId,
  },
  InputChatSource(:final inputId) => {'kind': 'input', 'inputId': inputId},
  InboxMessageChatSource(:final sourceId, :final messageId) => {
    'kind': 'inboxMessage',
    'sourceId': sourceId,
    'messageId': messageId,
  },
  BackgroundResultChatSource(:final messageId) => {
    'kind': 'backgroundResult',
    'messageId': messageId,
  },
  OperationChatSource(:final operationId) => {
    'kind': 'operation',
    'operationId': operationId,
  },
  ReceiptChatSource(:final receiptId) => {
    'kind': 'receipt',
    'receiptId': receiptId,
  },
};

Map<String, Object?> _atomCut(ChatAtom atom) => {
  'atomId': atom.id,
  'kind': atom.kind.name,
  'source': _sourceCut(atom.source),
  'turnId': atom.turnId,
  'lifecycle': atom.lifecycle.runtimeType.toString(),
  'completionItemId': atom.completionItemId,
  'completionSeq': atom.completionSeq,
};

// One synchronous failure cut of public identities, never body/payload/draft
// text, a query, or a new Session. Work headers deliberately have no source.
Map<String, Object?> timelineWaitFailureSnapshot({
  required WidgetTester tester,
  required String? selectedThreadId,
  required String? submittedThreadId,
  required String? submittedTurnId,
  required String? previousTurnId,
  required TimelineDisplayLease? lease,
  required ThreadSessionState? session,
  String? afterTurnId,
  String? targetTurnId,
  required String expectedOutcome,
}) {
  Map<String, Object?>? turn(StudioTurnView? value) => value == null
      ? null
      : {
          'threadId': value.threadId,
          'turnId': value.turnId,
          'status': value.state.status.name,
          'isBusy': value.state.isBusy,
          'isTerminal': value.state.isTerminal,
        };
  Map<String, Object?> body(DisplayBlockBody value, String id) =>
      switch (value) {
        SingleDisplayBlock(:final record) => {
          'bodyKind': 'single',
          ..._atomCut(record.atom),
        },
        WorkDisplayBlock(:final members, :final summary) => {
          'bodyKind': 'work',
          'source': null,
          'sourceEvidence':
              'bounded member heads, not a source on the Work header',
          'memberBlockId': members.blockId,
          'total': summary.total,
          'terminal': summary.terminal,
          'mountedMembers': [
            for (final display
                in lease?.groupDisplays ?? const <TimelineGroupDisplay>[])
              if (display.unitId == id && display.isCurrent)
                for (final atom in display.atoms) _atomCut(atom),
          ],
        },
      };
  final main = lease == null || lease.isReleased
      ? const <TimelineDisplayUnit>[]
      : TimelineObservation(tester, () => lease).main.toList();
  final live = lease?.isReleased == false ? lease?.live.value : null;
  final execution = session?.runtime?.execution;
  final composers = tester
      .widgetList<PromptComposerView>(find.byType(PromptComposerView))
      .toList();
  return {
    'selectedThreadId': selectedThreadId,
    'submittedThreadId': submittedThreadId,
    'submittedTurnId': submittedTurnId,
    'previousTurnId': previousTurnId,
    'afterTurnId': afterTurnId,
    'targetTurnId': targetTurnId,
    'expectedOutcome': expectedOutcome,
    'candidateTurn': turn(session?.lastTurn),
    'activeTurn': turn(session?.activeTurn),
    'execution': execution == null
        ? null
        : {
            'id': execution.id,
            'turnId': execution.turnId,
            'phase': execution.phase.name,
          },
    'activity': session?.activity == null
        ? null
        : {
            'kind': session!.activity!.kind.name,
            'count': session.activity!.tools.count,
            'background': session.activity!.tools.background,
          },
    'lease': lease == null
        ? null
        : {
            'threadId': lease.threadId,
            'generation': lease.generation,
            'selectionId': lease.selectionId,
            'mounted': lease.isMounted,
            'retired': lease.isRetired,
            'released': lease.isReleased,
            'appliedSets': lease.appliedSets,
          },
    'historyBlockCount': main.length,
    'historyTailLimit': 64,
    'historyTruncated': main.length > 64,
    'history': [
      for (final unit in main.skip(main.length > 64 ? main.length - 64 : 0))
        {
          'blockId': unit.id,
          'historyPos': unit.historyPos,
          ...body(unit.body, unit.id),
        },
    ],
    'live': live == null
        ? null
        : {
            'revision': live.revision,
            'historyThrough': live.historyThrough,
            'executionPresent': live.executionPresent,
            'blocks': [
              for (final block in live.blocks)
                {
                  'blockId': block.id,
                  'blockOrder': block.blockOrder,
                  ...body(block.body, block.id),
                  'source': block.source == null
                      ? null
                      : _sourceCut(block.source!),
                  'state': block.state.name,
                },
            ],
          },
    'mainScrollableCount': lease == null || lease.isReleased
        ? 0
        : find
              .byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    identical(widget.controller, lease.scrollController),
              )
              .evaluate()
              .length,
    'composer': [
      for (final composer in composers)
        {
          'enabled': composer.state.enabled,
          'submissionLocked': composer.state.submissionLocked,
          'blockerKind': composer.state.blocker?.runtimeType.toString(),
          'failureKind': composer.state.failure?.runtimeType.toString(),
          'failureReason': switch (composer.state.failure) {
            ComposerFailureBlocker(:final reason) => reason?.name,
            _ => null,
          },
        },
    ],
  };
}

// Work uses a dedicated single-line header, not TimelineActivityRow. Borrow its
// actual title widget (plain Text or single-line Markdown TimelineReasoningSummary)
// without the separate elapsed Text or any private widget API.
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
    if (widget is! TimelineReasoningSummary &&
        (widget is! Text ||
            widget.key == const ValueKey('work-header-elapsed') ||
            widget.key == const ValueKey('work-header-member-count'))) {
      return false;
    }
    var insideSummaryOrTitle = false;
    element.visitAncestorElements((ancestor) {
      if (ancestor.widget.key == const ValueKey('work-header-title') ||
          ancestor.widget is TimelineReasoningSummary) {
        insideSummaryOrTitle = true;
        return false;
      }
      return true;
    });
    if (!insideSummaryOrTitle) validateOwner?.call();
    return !insideSummaryOrTitle;
  }, skipOffstage: skipOffstage),
  skipOffstage: skipOffstage,
);

RenderParagraph timelineGroupTitleParagraph(WidgetTester tester, Finder title) {
  expect(title, findsOneWidget);
  final richTexts = find
      .descendant(
        of: title,
        matching: find.byWidgetPredicate((widget) => widget is RichText),
        matchRoot: true,
      )
      .evaluate()
      .toList();
  expect(richTexts, isNotEmpty);
  final target = richTexts.lastWhere((element) {
    final renderObject = element.renderObject;
    return renderObject is RenderParagraph &&
        renderObject.text
            .toPlainText(includePlaceholders: false)
            .trim()
            .isNotEmpty;
  }, orElse: () => richTexts.last);
  return target.renderObject! as RenderParagraph;
}

String timelineGroupTitleText(WidgetTester tester, Finder title) =>
    timelineGroupTitleParagraph(
      tester,
      title,
    ).text.toPlainText(includePlaceholders: false);

bool timelineWorkHeaderExpanded(WidgetTester tester, Finder header, String id) {
  expect(header, findsOneWidget);
  final disclosure = find.ancestor(
    of: header,
    matching: find.byKey(
      ValueKey('completion-run-disclosure:$id'),
      skipOffstage: false,
    ),
  );
  expect(disclosure, findsOneWidget);
  return tester.widget<Expansible>(disclosure).controller.isExpanded;
}

// Members and Single disclosures still use TimelineActivityRow. Their label may
// be a custom widget; keep the original row-specific observation separate.
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

typedef ObservedLiveDisplayRecord = ({
  String blockId,
  String displayId,
  DisplayRecord record,
});

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
      if (block.body case SingleDisplayBlock(:final record)) yield record.atom;
    }
    for (final display in lease.groupDisplays) {
      if (workIds.contains(display.unitId)) yield* display.atoms;
    }
  }

  // Resolve display identity only from the admitted block or its mounted page.
  // No query, ID decoding, or parallel member inventory is involved.
  Iterable<ObservedLiveDisplayRecord> liveDisplayRecords(
    LiveDisplayBlock block,
  ) sync* {
    switch (block.body) {
      case SingleDisplayBlock(:final record):
        yield (blockId: block.id, displayId: block.id, record: record);
      case WorkDisplayBlock(:final members):
        final group = lease.groupDisplays
            .where(
              (display) =>
                  display.unitId == block.id &&
                  display.blockReference == members &&
                  display.expanded &&
                  !display.loading,
            )
            .singleOrNull;
        if (group == null) return;
        expect(group.error, isNull);
        final page = unit(block.id).expansion.members?.page;
        if (page == null) return;
        expect(page.block, members);
        for (final entry in page.entries) {
          yield (
            blockId: block.id,
            displayId: entry.memberKey,
            record: entry.record,
          );
        }
    }
  }

  Finder liveRenderer(ObservedLiveDisplayRecord head) {
    final row = find.byWidgetPredicate(
      (widget) =>
          widget is TimelineMemberAtom &&
          widget.displayId == head.displayId &&
          widget.record == head.record &&
          identical(widget.content, lease.content) &&
          widget.isActive(),
    );
    final block = liveBlocks.singleWhere((block) => block.id == head.blockId);
    return block.body is WorkDisplayBlock
        ? find.descendant(of: groupRow(block.id), matching: row)
        : row;
  }

  TimelineCurrentDisplay currentDisplayForWork(String blockId) {
    final parent = find.ancestor(
      of: groupRow(blockId),
      matching: find.byType(ConversationCurrentConnector),
    );
    expect(parent, findsOneWidget);
    final current = tester.state(parent) as TimelineCurrentDisplay;
    expect(
      lease.currentDisplays.where((display) => identical(display, current)),
      hasLength(1),
    );
    expect(current.isCurrent, isTrue);
    return current;
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

  Future<bool> _workContainsSource(
    TimelineDisplayUnit block,
    ChatSourceId source,
  ) async {
    DisplayMemberWindow window = const LatestDisplayMembers();
    while (true) {
      final page = await readMemberPage(block.memberReference!, window: window);
      if (page.entries.any((head) => head.record.atom.source == source)) {
        return true;
      }
      final before = page.before;
      if (before == null) return false;
      window = BeforeDisplayMembers(memberOrder: before);
    }
  }

  Future<List<TimelineDisplayUnit>> workForSource(ChatSourceId source) async =>
      [
        for (final block in allWork.toList())
          if (await _workContainsSource(block, source)) block,
      ];

  Future<bool> hasDisplayedSource(ChatSourceId source) async =>
      singleBlocks.any((unit) => unit.atom!.source == source) ||
      (await workForSource(source)).isNotEmpty;

  Future<bool> hasHistoricalSource(ChatSourceId source) async {
    final original = lease;
    if (singleBlocks.any((unit) => unit.atom!.source == source)) return true;
    for (final block in workBlocks.toList()) {
      final contains = await _workContainsSource(block, source);
      expect(lease, same(original));
      final admitted = main.where((unit) => unit.id == block.id).single;
      expect(admitted.historyPos, block.historyPos);
      expect(admitted.memberReference, block.memberReference);
      if (contains) return true;
    }
    return false;
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
        final record = head.record;
        switch (record.contentSource) {
          case CurrentAtom() || FrozenObservation():
            atoms.add(record.atom);
          case CompletedOriginal(:final completionId):
            final original = await scope.readCompleted(
              recordId: completionId,
              demand: const ReadDemand(maxItems: 1, maxBytes: 64 * 1024),
            );
            expect(original.atom.id, record.atom.id);
            expect(original.atom.source, record.atom.source);
            expect(original.recordId, completionId);
            expect(original.completionSeq, record.atom.completionSeq);
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

  bool groupExpanded(String id) =>
      timelineWorkHeaderExpanded(tester, groupHeader(id), id);

  Future<void> tapGroupHeader(
    String id, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final original = lease;
    final controller = original.controller;
    final generation = original.generation;
    await tap(
      groupHeader(id),
      timeout: timeout,
      isActive: () {
        expect(lease, same(original));
        expect(original.isRetired, isFalse);
        expect(original.isReleased, isFalse);
        expect(original.isMounted, isTrue);
        expect(original.controller, same(controller));
        expect(original.generation, generation);
        return true;
      },
    );
  }

  Finder _groupTitle(String id, {bool skipOffstage = true}) {
    final header = groupHeader(id, skipOffstage: skipOffstage);
    expect(header, findsOneWidget);
    final originalLease = lease;
    final originalController = originalLease.controller;
    final originalGeneration = originalLease.generation;
    // Navigation reveals the actual title in this exact Work header, not a
    // member or another group's label. Toggle gestures use tapGroupHeader.
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
      final unit = originalUnit;
      return unit != null &&
          originalScrollable != null &&
          identical(
            _mainRevealRowUnit(
              originalController,
              originalScrollable!,
              element,
            ),
            unit,
          );
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
        'canonicalAnchor': 'ChatMessage canonical key/id and controller unit',
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

    bool rendererReady() {
      final rows = canonical.evaluate().toList();
      if (rows.length != 1) return false;
      final renderers = find
          .descendant(
            of: canonical,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is ChatItemView &&
                  identical(widget.item.displayUnit, originalUnit),
            ),
          )
          .evaluate()
          .toList();
      if (renderers.length > 1) {
        stop('Main canonical row has multiple payload renderers');
      }
      if (renderers.isEmpty) {
        // Observe the connector's actual UI branch, never open/refresh its
        // reader or infer a tool/business outcome from an error message.
        final connectors = find.descendant(
          of: canonical,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is TimelineCanonicalPayloadConnector &&
                identical(widget.item.displayUnit, originalUnit),
          ),
        );
        for (final element in connectors.evaluate()) {
          element.visitChildren((child) {
            final widget = child.widget;
            if (widget is Text && widget.data != '正在读取完成内容…') {
              stop('Main canonical metadata connector displays an error');
            }
          });
        }
        return false;
      }
      final element = renderers.single;
      final item = (element.widget as ChatItemView).item;
      if (item.id != unitId ||
          !identical(Scrollable.maybeOf(element), originalScrollable) ||
          !belongsTo(element, rows.single)) {
        stop('Main payload renderer lost its canonical row/domain');
      }
      if (item.compatibility == ChatItemCompatibility.deferred) return false;
      if (item.compatibility != ChatItemCompatibility.current) {
        stop('Main payload renderer has unavailable canonical metadata');
      }
      final body = originalUnit!.body;
      if (body is SingleDisplayBlock) {
        final atom = item.atom;
        final record = body.record;
        final head = record.atom;
        final completionId = switch (record.contentSource) {
          CompletedOriginal(:final completionId) => completionId,
          CurrentAtom() || FrozenObservation() => null,
        };
        if (atom == null ||
            atom.id != head.id ||
            atom.source != head.source ||
            atom.kind != head.kind ||
            atom.turnId != head.turnId ||
            atom.delivery != head.delivery ||
            atom.lifecycle != head.lifecycle ||
            atom.tool?.callId != head.tool?.callId ||
            atom.tool?.name != head.tool?.name ||
            atom.completionItemId != head.completionItemId ||
            atom.completionSeq != head.completionSeq ||
            (completionId != null && atom.completionItemId != completionId)) {
          stop(
            'Main payload renderer completion identity differs from its unit',
          );
        }
      }
      return true;
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
        final wanted = originalController.messages.indexWhere(
          (message) => message.id == unitId,
        );
        if (!_mainRevealIndices(
          originalController,
          originalScrollable!,
          visibleOnly: true,
        ).contains(wanted)) {
          await demand(
            'ensure canonical visible',
            () => tester.ensureVisible(canonical),
          );
          requireOriginal();
          if (!_mainRevealIndices(
            originalController,
            originalScrollable!,
            visibleOnly: true,
          ).contains(wanted)) {
            // A cached shell can move while the reversed list measures it.
            continue;
          }
        }
        if (!rendererReady()) {
          await demand('wait for original Main payload renderer', () async {});
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
            !rendererReady() ||
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
    ChatMessage? outer = widget is ChatMessage ? widget : null;
    ChatItemView? row = widget is ChatItemView ? widget : null;
    element.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (widget is ChatItemView) row ??= widget;
      if (widget is ChatMessage) outer ??= widget;
      return outer == null;
    });
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
      'outerMessageId': outer?.message.id,
      'outerUnitIdentity':
          outer?.message.metadata?[timelineDisplayUnitKey] == null
          ? null
          : identityHashCode(outer!.message.metadata![timelineDisplayUnitKey]),
      'presentationType': row?.item.type,
      'compatibility': row?.item.compatibility.name,
      'metadata': _mainRevealUnitInfo(
        outer?.message.metadata?[timelineDisplayUnitKey] is TimelineDisplayUnit
            ? outer!.message.metadata![timelineDisplayUnitKey]
                  as TimelineDisplayUnit
            : row?.item.displayUnit,
      ),
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
            widget is TimelineCanonicalPayloadConnector ||
            widget is ChatItemView ||
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
          if (element.widget case Text(:final data, :final textSpan))
            'text': data ?? textSpan?.toPlainText(),
          if (element.widget case TimelineCanonicalPayloadConnector(
            :final item,
          ))
            'connectorItem': _mainRevealPresentationInfo(item),
          if (element.widget case ChatItemView(:final item))
            'rendererItem': _mainRevealPresentationInfo(item),
        },
    ];
  }

  Map<String, Object?> _mainRevealPresentationInfo(ChatItemPresentation item) =>
      {
        'id': item.id,
        'type': item.type,
        'compatibility': item.compatibility.name,
        'unitIdentity': item.displayUnit == null
            ? null
            : identityHashCode(item.displayUnit),
        'atomId': item.atom?.id,
        if (item.atom case final atom?) 'source': _sourceCut(atom.source),
        'completionItemId': item.atom?.completionItemId,
        'completionSeq': item.atom?.completionSeq,
        'diagnostic': item.diagnostic,
      };

  TimelineDisplayUnit? _mainRevealRowUnit(
    ChatController controller,
    ScrollableState main,
    Element element,
  ) {
    final widget = element.widget;
    if (widget is! ChatMessage ||
        widget.key != StudioDriverKeys.timelineRow(widget.message.id) ||
        !identical(Scrollable.maybeOf(element), main)) {
      return null;
    }
    final unit = widget.message.metadata?[timelineDisplayUnitKey];
    if (unit is! TimelineDisplayUnit || unit.id != widget.message.id) {
      return null;
    }
    final messages = controller.messages.where(
      (message) => message.id == unit.id,
    );
    if (messages.length != 1 ||
        !identical(messages.single.metadata?[timelineDisplayUnitKey], unit)) {
      return null;
    }
    return unit;
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
    // Use the same production shell as the canonical finder. Deferred metadata
    // can legitimately leave this shell without a ChatItemView child.
    final rows = find.byType(ChatMessage, skipOffstage: visibleOnly);
    for (final element in rows.evaluate()) {
      final unit = _mainRevealRowUnit(controller, main, element);
      if (unit == null) continue;
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
    if (!groupExpanded(id)) {
      await tapGroupHeader(id, timeout: timeout);
    }
    expect(groupExpanded(id), isTrue);
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
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final clock = Stopwatch()..start();
    Duration remaining() {
      final value = timeout - clock.elapsed;
      if (value <= Duration.zero) fail('Timed out revealing member ${atom.id}');
      return value;
    }

    final value = unitForBlock(reference);
    final display = await openWork(value.id, timeout: remaining());
    if (!display.atoms.any((member) => member.id == atom.id)) {
      await selectLatestMembers(display);
    }
    while (!display.atoms.any((member) => member.id == atom.id)) {
      remaining();
      expect(
        display.before,
        isNotNull,
        reason: 'The producer-defined member must be in this block',
      );
      await loadOlderMemberPage(display, timeout: remaining());
    }
    final row = find.descendant(
      of: groupRow(value.id),
      matching: find.byWidgetPredicate(
        (widget) => widget is TimelineMemberAtom && widget.atom.id == atom.id,
      ),
    );
    await until(
      () => row.evaluate().length == 1,
      'mounted member ${atom.id}',
      timeout: remaining(),
    );
    await tester.ensureVisible(row);
    await tester.pump();
    final rendered = tester.widget<TimelineMemberAtom>(row).atom;
    expect(rendered.id, atom.id);
    expect(rendered.source, atom.source);
    expect(rendered.tool?.callId, atom.tool?.callId);
    if (atom.kind == ChatAtomKind.reasoning ||
        atom.kind == ChatAtomKind.toolCall) {
      await ensureMemberReadable(row, rendered, timeout: remaining());
    }
    return display;
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
    expect(
      atom.contents,
      isNotEmpty,
      reason: 'Reasoning readability requires producer-declared content',
    );
    expect(
      atom.contents.every(
        (content) =>
            content.role == ChatContentRole.body ||
            content.role == ChatContentRole.reasoningSummary,
      ),
      isTrue,
      reason: 'Unsupported reasoning content roles must not guess a renderer',
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
        // A summary read error may itself be displayed as summary text. Borrow
        // existing window diagnostics so it cannot satisfy the visibility gate.
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

  Future<void> expandMemberDisclosure(
    Finder row,
    String memberId, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final clock = Stopwatch()..start();
    Duration remaining() => timeout - clock.elapsed;
    // A Deferred member is mounted before its canonical renderer is ready.
    // Evaluate the candidates, not .first, while there may be no header yet.
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

  Future<void> closeWork(
    TimelineGroupDisplay display, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final clock = Stopwatch()..start();
    Duration remaining() {
      final value = timeout - clock.elapsed;
      if (value <= Duration.zero) fail('Timed out closing ${display.unitId}');
      return value;
    }

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
          timeout: remaining(),
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
      timeout: remaining(),
    );
    expect(display.error, isNull);
  }

  Future<void> closeSourceWork(
    ChatSourceId source, {
    Map<String, Object?>? diagnostics,
  }) async {
    final owner = lease;
    final groups = await workForSource(source);
    expect(groups, isNotEmpty);
    diagnostics?.addAll({
      'targetUnitIds': groups.map((unit) => unit.id).toList(),
      'complete': false,
    });
    for (final group in groups) {
      if (group.expansion.expanded != true) continue;
      if (group.historyPos != null) {
        await reveal(groupHeader(group.id), group.id);
      }
      await until(
        () => owner.groupDisplays.any(
          (display) => display.unitId == group.id && display.expanded,
        ),
        'mounted expanded Work before closing',
      );
      final display = owner.groupDisplays.singleWhere(
        (display) => display.unitId == group.id,
      );
      await closeWork(display);
      expect(lease, same(owner));
      expect(group.expansion.expanded, isFalse);
    }
    diagnostics?['complete'] = true;
  }
}
