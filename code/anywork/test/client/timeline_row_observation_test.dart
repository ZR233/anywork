import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/features/timeline/timeline_session_view.dart';
import 'package:anywork/src/features/timeline/timeline_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork/src/shared/studio_driver_state.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_demo_transport.dart';
import 'support/pump_client_future.dart';

void main() {
  testWidgets('initial long streaming body follows the real layout bottom', (
    tester,
  ) async {
    final harness = await _mountObservedTimeline(
      tester,
      secondText: _streamingParagraphs(80),
    );

    final position = _timelinePosition(tester);
    expect(position.maxScrollExtent, greaterThan(position.viewportDimension));
    expect(
      position.extentAfter,
      lessThanOrEqualTo(2),
      reason:
          'followLatest must reach the actual bottom before any user scroll',
    );
    expect(harness.listBuilds, 1);
    await _closeObservedTimeline(tester, harness);
    expect(tester.takeException(), isNull);
  });

  testWidgets('row-only body growth follows the real layout bottom', (
    tester,
  ) async {
    final harness = await _mountObservedTimeline(tester);
    final structure = harness.graph.timeline.source.value!;
    final row = structure.rowQuery.row('second');
    final listBuilds = harness.listBuilds;
    expect(_timelinePosition(tester).extentAfter, lessThanOrEqualTo(2));

    for (var version = 2; version <= 3; version++) {
      harness.window.appendSecond(
        from: version - 1,
        to: version,
        expectedRevision: version - 1,
        text: '\n\n${_streamingParagraphs(80)}',
      );
      await _pumpVersion(tester, harness.session, harness.window, version);
      await tester.pumpAndSettle(const Duration(milliseconds: 16));

      expect(harness.graph.timeline.source.value, same(structure));
      expect(structure.rowQuery.row('second'), same(row));
      expect(
        harness.listBuilds,
        listBuilds,
        reason: 'the follow correction must work without rebuilding the list',
      );
      final position = _timelinePosition(tester);
      expect(position.maxScrollExtent, greaterThan(position.viewportDimension));
      expect(
        position.extentAfter,
        lessThanOrEqualTo(2),
        reason:
            'row revision $version left followLatest above the actual bottom',
      );
    }
    await _closeObservedTimeline(tester, harness);
    expect(tester.takeException(), isNull);
  });

  testWidgets('body growth after an upward drag preserves the reading anchor', (
    tester,
  ) async {
    final harness = await _mountObservedTimeline(
      tester,
      secondText: _streamingParagraphs(80),
    );
    expect(_timelinePosition(tester).extentAfter, lessThanOrEqualTo(2));

    await tester.drag(
      find.byKey(StudioDriverKeys.timeline),
      const Offset(0, 120),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    final before = _lastPublishedAnchor(harness.commands);
    expect(before.readingIntent, TimelineReadingIntent.browseHistory);
    expect(before.itemId, 'second');
    expect(_timelinePosition(tester).extentAfter, greaterThan(80));
    final rowOffset = _rowViewportOffset(tester, before.itemId);
    expect(before.offset, closeTo(rowOffset, 2));
    final listBuilds = harness.listBuilds;
    final structure = harness.graph.timeline.source.value;

    harness.window.appendSecond(
      from: 1,
      to: 2,
      expectedRevision: 1,
      text: '\n\n${_streamingParagraphs(80)}',
    );
    await _pumpVersion(tester, harness.session, harness.window, 2);
    await tester.pumpAndSettle(const Duration(milliseconds: 16));

    final after = _lastPublishedAnchor(harness.commands);
    expect(harness.graph.timeline.source.value, same(structure));
    expect(harness.listBuilds, listBuilds);
    expect(after.readingIntent, TimelineReadingIntent.browseHistory);
    expect(after.itemId, before.itemId);
    expect(after.offset, closeTo(before.offset, 2));
    expect(
      _rowViewportOffset(tester, before.itemId),
      closeTo(rowOffset, 2),
      reason: 'continued streaming must preserve the painted item and offset',
    );
    expect(_timelinePosition(tester).extentAfter, greaterThan(80));
    await _closeObservedTimeline(tester, harness);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'row layout cannot cancel a drag before its first scroll update',
    (tester) async {
      var dragStarts = 0;
      var dragUpdates = 0;
      final harness = await _mountObservedTimeline(
        tester,
        secondText: _streamingParagraphs(80),
        onScrollNotification: (notification) {
          if (notification.depth != 0) return;
          if (notification is ScrollStartNotification &&
              notification.dragDetails != null) {
            dragStarts++;
          }
          if (notification is ScrollUpdateNotification &&
              notification.dragDetails != null) {
            dragUpdates++;
          }
        },
      );
      final position = _timelinePosition(tester);
      expect(position.extentAfter, lessThanOrEqualTo(2));
      final originalMaxExtent = position.maxScrollExtent;
      final listBuilds = harness.listBuilds;
      final originalQuery = harness.graph.timeline.source.value!.rowQuery;
      final originalUserDragUpdates = _publishedUserDragUpdates();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(StudioDriverKeys.timeline)),
      );
      var released = false;
      try {
        // DragStartBehavior.start consumes the slop-crossing move as onStart.
        // The next pointer event has not yet called applyUserOffset. This is an
        // actual DragScrollActivity, rather than the earlier pointer-down hold.
        await gesture.moveBy(const Offset(0, kTouchSlop + 1));
        expect(dragStarts, 1);
        expect(dragUpdates, 0);
        expect(position.isScrollingNotifier.value, isTrue);

        // Keep the same pointer down while a genuine row-only frame changes the
        // laid-out max extent. No list replacement or synthetic scroll is used.
        harness.window.appendSecond(
          from: 1,
          to: 2,
          expectedRevision: 1,
          text: '\n\n${_streamingParagraphs(80)}',
        );
        await _pumpVersion(tester, harness.session, harness.window, 2);
        await tester.pumpAndSettle(const Duration(milliseconds: 16));
        expect(_timelinePosition(tester), same(position));
        expect(harness.listBuilds, listBuilds);
        expect(
          harness.graph.timeline.source.value!.rowQuery,
          same(originalQuery),
        );
        expect(position.maxScrollExtent, greaterThan(originalMaxExtent));
        expect(dragUpdates, 0);
        expect(_publishedScrollDiagnostic()['isScrolling'], isTrue);
        final beforeContinuedMove = position.pixels;

        await gesture.moveBy(const Offset(0, 120));
        await tester.pump();

        expect(
          dragUpdates,
          greaterThan(0),
          reason:
              'row layout must retain the established drag until the next move',
        );
        expect(
          _publishedUserDragUpdates(),
          greaterThan(originalUserDragUpdates),
        );
        expect(position.pixels, lessThan(beforeContinuedMove - 80));
        expect(position.extentAfter, greaterThan(80));
        await gesture.up();
        released = true;
        await tester.pumpAndSettle(const Duration(milliseconds: 16));
        expect(_publishedScrollDiagnostic()['isScrolling'], isFalse);
        expect(
          _lastPublishedAnchor(harness.commands).readingIntent,
          TimelineReadingIntent.browseHistory,
        );
      } finally {
        if (!released) await gesture.up();
        await tester.pumpAndSettle(const Duration(milliseconds: 16));
        await _closeObservedTimeline(tester, harness);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('every held drag step publishes its current geometry', (
    tester,
  ) async {
    final harness = await _mountObservedTimeline(
      tester,
      secondText: _streamingParagraphs(80),
    );
    final position = _timelinePosition(tester);
    final initialUpdates = _publishedUserDragUpdates();
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(StudioDriverKeys.timeline)),
    );
    try {
      await gesture.moveBy(const Offset(0, kTouchSlop + 1));
      await tester.pump();
      for (var step = 1; step <= 4; step++) {
        final before = position.pixels;
        await gesture.moveBy(const Offset(0, 32));
        await tester.pump();
        expect(position.pixels, lessThan(before - 20));
        final diagnostic = _publishedScrollDiagnostic();
        expect(
          diagnostic['pixels'],
          closeTo(position.pixels, 0.5),
          reason: 'held drag step $step must publish before pointer up',
        );
        expect(diagnostic['userDragUpdates'], initialUpdates + step);
        expect(diagnostic['isScrolling'], isTrue);
      }
    } finally {
      await gesture.up();
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      await _closeObservedTimeline(tester, harness);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a downward wheel at the clamped bottom resumes following', (
    tester,
  ) async {
    final harness = await _mountObservedTimeline(
      tester,
      secondText: _streamingParagraphs(80),
    );
    try {
      await tester.drag(
        find.byKey(StudioDriverKeys.timeline),
        const Offset(0, 120),
      );
      await tester.pumpAndSettle();
      expect(_publishedScrollDiagnostic()['followingBottom'], isFalse);
      harness.window.emit(
        StudioChatPatch(
          from: 1,
          to: 2,
          changes: [
            StudioViewItemUpdate(
              itemId: 'second',
              expectedRevision: 1,
              revision: 2,
              omittedUnits: 0,
              saved: false,
              fields: const [
                StudioFieldUpdateView(
                  field: ThreadTextFieldView(),
                  change: ReplaceThreadFieldChangeView('short replacement'),
                ),
              ],
            ),
          ],
          hasNewer: false,
        ),
      );
      await _pumpVersion(tester, harness.session, harness.window, 2);
      await tester.pumpAndSettle();
      final position = _timelinePosition(tester);
      expect(position.extentAfter, closeTo(0, .5));
      expect(_publishedScrollDiagnostic()['followingBottom'], isFalse);
      final beforePixels = position.pixels;
      harness.commands.clear();

      await tester.sendEventToBinding(
        PointerScrollEvent(
          kind: PointerDeviceKind.mouse,
          position: tester.getCenter(find.byKey(StudioDriverKeys.timeline)),
          scrollDelta: const Offset(0, 200),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        position.pixels,
        beforePixels,
        reason: 'the edge consumes no displacement',
      );
      expect(_publishedScrollDiagnostic()['followingBottom'], isTrue);
      expect(harness.commands.whereType<TimelineJumpToLatest>(), hasLength(1));
    } finally {
      await _closeObservedTimeline(tester, harness);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unchanged plain body keeps its layout under inherited height behavior',
    (tester) async {
      final text = List.generate(
        3000,
        (index) => 'body-${index.toString().padLeft(5, '0')} ${'W' * 20} ',
      ).join();
      final harness = await _mountObservedTimeline(
        tester,
        secondText: text,
        textHeightBehavior: const TextHeightBehavior(
          applyHeightToFirstAscent: false,
          applyHeightToLastDescent: false,
        ),
      );
      final body = find.byKey(const ValueKey('plain-second'));
      final before = tester.getSize(body).height;
      try {
        for (var version = 2; version <= 4; version++) {
          harness.window.appendSecond(
            from: version - 1,
            to: version,
            expectedRevision: version - 1,
            text: '',
          );
          await _pumpVersion(tester, harness.session, harness.window, version);
          await tester.pumpAndSettle();
          expect(harness.session.state.items[1].text, text);
          expect(
            tester.getSize(body).height,
            closeTo(before, .5),
            reason: 'unchanged text moved on row revision $version',
          );
        }
      } finally {
        await _closeObservedTimeline(tester, harness);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('streamed and replaced plain bodies match a fresh layout', (
    tester,
  ) async {
    final text = List.generate(
      1800,
      (index) => 'body-${index.toString().padLeft(5, '0')} ${'W' * 20} ',
    ).join();
    const heightBehavior = TextHeightBehavior(
      applyHeightToFirstAscent: false,
      applyHeightToLastDescent: false,
    );
    final harness = await _mountObservedTimeline(
      tester,
      secondText: text.substring(0, 5200),
      textHeightBehavior: heightBehavior,
    );
    final body = find.byKey(const ValueKey('plain-second'));
    late final double streamedHeight;
    late final double replacedHeight;
    final replacement = text.substring(0, 5100) + 'updated ' * 1100;
    try {
      var start = 5200;
      var version = 1;
      for (final end in [11700, text.length]) {
        harness.window.appendSecond(
          from: version,
          to: version + 1,
          expectedRevision: version,
          text: text.substring(start, end),
        );
        version++;
        start = end;
        await _pumpVersion(tester, harness.session, harness.window, version);
        await tester.pumpAndSettle();
      }
      expect(harness.session.state.items[1].text, text);
      streamedHeight = tester.getSize(body).height;
      harness.window.emit(
        StudioChatPatch(
          from: version,
          to: version + 1,
          changes: [
            StudioViewItemUpdate(
              itemId: 'second',
              expectedRevision: version,
              revision: version + 1,
              omittedUnits: 0,
              saved: false,
              fields: [
                StudioFieldUpdateView(
                  field: const ThreadTextFieldView(),
                  change: ReplaceThreadFieldChangeView(replacement),
                ),
              ],
            ),
          ],
          hasNewer: false,
        ),
      );
      await _pumpVersion(tester, harness.session, harness.window, version + 1);
      await tester.pumpAndSettle();
      expect(harness.session.state.items[1].text, replacement);
      replacedHeight = tester.getSize(body).height;
    } finally {
      await _closeObservedTimeline(tester, harness);
    }

    for (final (canonical, expectedHeight) in [
      (text, streamedHeight),
      (replacement, replacedHeight),
    ]) {
      final fresh = await _mountObservedTimeline(
        tester,
        secondText: canonical,
        textHeightBehavior: heightBehavior,
      );
      try {
        expect(tester.getSize(body).height, closeTo(expectedHeight, .5));
        final rendered = tester
            .widgetList<Text>(
              find.descendant(of: body, matching: find.byType(Text)),
            )
            .map((chunk) => chunk.data ?? chunk.textSpan!.toPlainText())
            .join();
        expect(rendered, canonical, reason: 'partitioning must preserve bytes');
      } finally {
        await _closeObservedTimeline(tester, fresh);
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'body updates rebuild only their row and eviction closes its query',
    (tester) async {
      final transport = RecordingDemoTransport();
      final window = _ControlledWindow();
      transport.chatWindowFactory = (threadId, demoWindow) async {
        demoWindow.requestClose();
        await demoWindow.close();
        return window;
      };
      final graph = AppGraph(transport: transport, clientId: 'row-observation');
      addTearDown(
        () => pumpClientFuture(
          tester,
          graph.close(deadline: _deadline()),
          'row teardown close',
        ),
      );
      await pumpClientFuture(tester, graph.client.bootstrap(), 'row bootstrap');
      await pumpClientFuture(
        tester,
        graph.client.directoryCommands.selectThread('thread-main'),
        'row select',
      );
      final session = graph.client.existingSession('thread-main')!;
      await _pumpVersion(tester, session, window, 1);
      final structure = graph.timeline.source.value!;
      final firstQuery = structure.rowQuery.row('first')!;
      final secondQuery = structure.rowQuery.row('second')!;
      final thirdQuery = structure.rowQuery.row('third')!;
      final firstChanges = <TimelineRowSnapshot?>[];
      final secondChanges = <TimelineRowSnapshot?>[];
      final thirdChanges = <TimelineRowSnapshot?>[];
      final firstWatch = firstQuery.watchLatest(firstChanges.add);
      final secondWatch = secondQuery.watchLatest(secondChanges.add);
      final thirdWatch = thirdQuery.watchLatest(thirdChanges.add);
      addTearDown(firstWatch.observation.cancel);
      addTearDown(secondWatch.observation.cancel);
      addTearDown(thirdWatch.observation.cancel);
      int rowObservers() => graph.client.budget.usage
          .where(
            (entry) =>
                entry.kind == ResourceKind.observer &&
                entry.owner.startsWith('timeline:thread-main:'),
          )
          .length;
      expect(rowObservers(), 3);
      var listBuilds = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appGraphProvider.overrideWithValue(graph)],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  final latest = ref.watch(timelineSessionWindowProvider)!;
                  listBuilds++;
                  return TimelineView.observed(
                    threadId: latest.threadId,
                    viewId: latest.viewId,
                    rows: latest.rowQuery,
                    turn: latest.turn,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(rowObservers(), 6, reason: 'three mounted rows own three permits');
      final buildsBeforePatch = listBuilds;
      final originalFirst = firstQuery.value!.row;
      final originalThird = thirdQuery.value!.row;

      window.appendSecond(
        from: 1,
        to: 2,
        expectedRevision: 1,
        text: ' updated',
      );
      await _pumpVersion(tester, session, window, 2);

      expect(find.text('second updated', findRichText: true), findsWidgets);
      expect(
        listBuilds,
        buildsBeforePatch,
        reason: 'body revisions must not invalidate the list observer',
      );
      expect(firstChanges, isEmpty);
      expect(thirdChanges, isEmpty);
      expect(firstQuery.value!.row, same(originalFirst));
      expect(thirdQuery.value!.row, same(originalThird));
      expect(secondChanges, hasLength(1));
      expect(graph.timeline.source.value, same(structure));

      secondWatch.observation.pause();
      expect(
        rowObservers(),
        6,
        reason: 'a paused latest buffer retains its permit',
      );
      window.appendSecond(from: 2, to: 3, expectedRevision: 2, text: ' once');
      await _pumpVersion(tester, session, window, 3);
      window.appendSecond(from: 3, to: 4, expectedRevision: 3, text: ' twice');
      await _pumpVersion(tester, session, window, 4);
      secondWatch.observation.resume();
      expect(
        secondChanges,
        hasLength(2),
        reason: 'paused display observation retains one latest row snapshot',
      );
      expect(secondChanges.last!.row.part!.text, 'second updated once twice');
      expect(rowObservers(), 6);

      window.emit(
        const StudioChatPatch(
          from: 4,
          to: 5,
          changes: [StudioViewSplice(index: 0, remove: 1, items: [])],
          hasNewer: false,
        ),
      );
      await _pumpVersion(tester, session, window, 5);
      expect(graph.timeline.source.value!.orderedIds, ['second', 'third']);
      expect(graph.timeline.source.value!.rowQuery.row('first'), isNull);
      expect(firstQuery.value, isNull);
      expect(firstChanges, [null]);
      expect(firstWatch.observation.isCancelled, isTrue);
      expect(rowObservers(), 4, reason: 'eviction releases both row observers');
      expect(() => firstQuery.watchLatest((_) {}), throwsStateError);
      expect(
        graph.timeline.source.value!.rowQuery.row('second'),
        same(secondQuery),
      );
      expect(find.text('first', findRichText: true), findsNothing);
      expect(
        find.text('second updated once twice', findRichText: true),
        findsWidgets,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await pumpClientFuture(
        tester,
        graph.close(deadline: _deadline()),
        'row close',
      );
      expect(secondQuery.value, isNull);
      expect(thirdQuery.value, isNull);
      expect(secondWatch.observation.isCancelled, isTrue);
      expect(thirdWatch.observation.isCancelled, isTrue);
      expect(rowObservers(), 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'row observation budget failure is visible and explicitly retryable',
    (tester) async {
      final budget = ResourceBudget(capacities: {ResourceKind.observer: 1});
      final rows = TimelineRowProjector().project([_item('first').item]);
      final query = TimelineRowsQuery.snapshot(rows, budget: budget);
      final held = query.row('first')!.watchLatest((_) {});
      addTearDown(held.observation.cancel);
      expect(budget.used(ResourceKind.observer), 1);
      expect(
        () => query.row('first')!.watchLatest((_) {}),
        throwsA(isA<ResourceBudgetExceeded>()),
      );
      expect(
        budget.used(ResourceKind.observer),
        1,
        reason: 'failed registration cannot leak another permit',
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: TimelineView.observed(
                threadId: 'thread-main',
                rows: query,
                turn: null,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('Resource budget exhausted:'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('timeline-row-observation-retry')),
        findsOneWidget,
      );
      held.observation.cancel();
      expect(budget.used(ResourceKind.observer), 0);
      await tester.tap(
        find.byKey(const ValueKey('timeline-row-observation-retry')),
      );
      await tester.pump();
      expect(find.text('first', findRichText: true), findsWidgets);
      expect(find.textContaining('Resource budget exhausted:'), findsNothing);
      expect(budget.used(ResourceKind.observer), 1);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(budget.used(ResourceKind.observer), 0);
      expect(tester.takeException(), isNull);
    },
  );
}

class _ControlledWindow implements StudioChatWindow {
  _ControlledWindow({this.secondText = 'second'});

  final String secondText;
  Completer<StudioChatFrame?>? _next;
  Completer<void> nextRequested = Completer<void>();
  bool _closed = false;

  @override
  Future<StudioChatSnapshot> initial() async => StudioChatSnapshot(
    focusedItemId: null,
    version: 1,
    items: [
      for (final id in ['first', 'second', 'third'])
        _item(id, text: id == 'second' ? secondText : null),
    ],
    hasOlder: false,
    hasNewer: false,
    canExtendLatest: false,
  );

  @override
  Future<StudioChatFrame?> next() {
    if (_closed) return Future.value(null);
    if (_next != null) throw StateError('Two unfinished next calls');
    _next = Completer<StudioChatFrame?>();
    nextRequested.complete();
    return _next!.future;
  }

  void emit(StudioChatFrame frame) {
    final pending = _next!;
    _next = null;
    nextRequested = Completer<void>();
    pending.complete(frame);
  }

  void appendSecond({
    required int from,
    required int to,
    required int expectedRevision,
    required String text,
  }) => emit(
    StudioChatPatch(
      from: from,
      to: to,
      changes: [
        StudioViewItemUpdate(
          itemId: 'second',
          expectedRevision: expectedRevision,
          revision: expectedRevision + 1,
          omittedUnits: 0,
          saved: false,
          fields: [
            StudioFieldUpdateView(
              field: const ThreadTextFieldView(),
              change: AppendThreadFieldChangeView(text),
            ),
          ],
        ),
      ],
      hasNewer: false,
    ),
  );

  @override
  void requestClose() {
    _closed = true;
    _next?.complete(null);
    _next = null;
  }

  @override
  Future<void> close() async => requestClose();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('No control commands are used in this row test');
}

StudioChatItem _item(String id, {String? text}) {
  final now = DateTime.utc(2026);
  final streaming = id == 'second';
  return StudioChatItem(
    ThreadItemView(
      id: id,
      threadId: 'thread-main',
      turnId: 'turn',
      ordinal: ['first', 'second', 'third'].indexOf(id),
      revision: 1,
      createdAt: now,
      updatedAt: now,
      state: ThreadTextItemStateView(
        channel: streaming
            ? ThreadTextChannel.finalAnswer
            : ThreadTextChannel.user,
        text: text ?? id,
        attachments: const [],
        lifecycle: streaming
            ? const StreamingThreadContentView()
            : CompletedThreadContentView(now),
      ),
    ),
    saved: !streaming,
    lifecycle: streaming
        ? StudioChatLifecycle.streaming
        : StudioChatLifecycle.terminal,
  );
}

final class _ObservedTimelineHarness {
  _ObservedTimelineHarness({
    required this.graph,
    required this.window,
    required this.session,
  });

  final AppGraph graph;
  final _ControlledWindow window;
  final StudioThreadSession session;
  final List<TimelineCommand> commands = [];
  int listBuilds = 0;
}

Future<_ObservedTimelineHarness> _mountObservedTimeline(
  WidgetTester tester, {
  String secondText = 'second',
  ValueChanged<ScrollNotification>? onScrollNotification,
  TextHeightBehavior textHeightBehavior = const TextHeightBehavior(),
}) async {
  final transport = RecordingDemoTransport();
  final window = _ControlledWindow(secondText: secondText);
  transport.chatWindowFactory = (threadId, demoWindow) async {
    demoWindow.requestClose();
    await demoWindow.close();
    return window;
  };
  final graph = AppGraph(transport: transport, clientId: 'follow-layout');
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpClientFuture(
      tester,
      graph.close(deadline: _deadline()),
      'follow-layout teardown close',
    );
  });
  await pumpClientFuture(tester, graph.client.bootstrap(), 'follow bootstrap');
  await pumpClientFuture(
    tester,
    graph.client.directoryCommands.selectThread('thread-main'),
    'follow select',
  );
  final session = graph.client.existingSession('thread-main')!;
  await _pumpVersion(tester, session, window, 1);
  final harness = _ObservedTimelineHarness(
    graph: graph,
    window: window,
    session: session,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appGraphProvider.overrideWithValue(graph)],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 640,
              height: 320,
              child: DefaultTextHeightBehavior(
                textHeightBehavior: textHeightBehavior,
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    onScrollNotification?.call(notification);
                    return false;
                  },
                  child: Consumer(
                    builder: (context, ref, _) {
                      final latest = ref.watch(timelineSessionWindowProvider)!;
                      harness.listBuilds++;
                      return TimelineView.observed(
                        threadId: latest.threadId,
                        viewId: latest.viewId,
                        windowEpoch: latest.history.epoch,
                        rows: latest.rowQuery,
                        turn: null,
                        onCommand: harness.commands.add,
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 16));
  return harness;
}

Future<void> _closeObservedTimeline(
  WidgetTester tester,
  _ObservedTimelineHarness harness,
) async {
  // testWidgets checks its pending timers before addTearDown runs. Successful
  // journeys must finish their owner here; teardown remains a failure fallback.
  await tester.pumpWidget(const SizedBox.shrink());
  await pumpClientFuture(
    tester,
    harness.graph.close(deadline: _deadline()),
    'follow-layout close',
  );
}

ScrollPosition _timelinePosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byKey(StudioDriverKeys.timeline),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

Map<String, dynamic> _publishedScrollDiagnostic() {
  final snapshot = jsonDecode(
    StudioDriverState.snapshotJson(observed: StudioDriverFacts()),
  ) as Map<String, dynamic>;
  return snapshot['timelineScroll'] as Map<String, dynamic>;
}

int _publishedUserDragUpdates() =>
    _publishedScrollDiagnostic()['userDragUpdates'] as int;

TimelineAnchor _lastPublishedAnchor(List<TimelineCommand> commands) {
  final anchors = commands.whereType<TimelineAnchorChanged>().toList();
  expect(anchors, isNotEmpty, reason: 'a settled drag must publish its anchor');
  return anchors.last.anchor;
}

double _rowViewportOffset(WidgetTester tester, String itemId) =>
    tester.getTopLeft(find.byKey(StudioDriverKeys.timelineBlock(itemId))).dy -
    tester.getTopLeft(find.byKey(StudioDriverKeys.timeline)).dy;

String _streamingParagraphs(int count) => List.generate(
  count,
  (index) => 'Streaming paragraph $index keeps a visible reading anchor.',
).join('\n\n');

Future<void> _pumpVersion(
  WidgetTester tester,
  StudioThreadSession session,
  _ControlledWindow window,
  int version,
) async {
  // Every frame is released by emit, so processing needs microtasks and widget
  // frames, never wall-clock time. A rejected frame must fail with its owner
  // error instead of waiting forever while FakeAsync holds a retry timer.
  for (var frame = 0; frame < 64; frame++) {
    await tester.runAsync(() async {});
    await tester.pump();
    final chat = session.chat.state.value;
    final Object? error = switch (chat) {
      ChatReconnecting<StudioChatSnapshot>(:final error) => error,
      ChatFailed<StudioChatSnapshot>(:final error) => error,
      _ => null,
    };
    if (error != null) {
      fail('ChatView rejected version $version: $error');
    }
    if (session.state.chatVersion == version &&
        window.nextRequested.isCompleted) {
      return;
    }
  }
  fail(
    'ChatView did not deliver version $version; '
    'observed=${session.state.chatVersion}, '
    'sync=${session.state.sync.phase}, '
    'error=${session.state.sync.errorMessage}',
  );
}

DateTime _deadline() => DateTime.now().add(const Duration(seconds: 5));
