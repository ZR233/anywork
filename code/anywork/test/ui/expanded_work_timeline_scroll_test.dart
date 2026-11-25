import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_view_state.dart';
import 'package:anywork/src/features/conversation/timeline/views/timeline_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/completion_run_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/shared/latest_scroll.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:anywork_previews/src/features/conversation/timeline/previews/expanded_work_timeline_fixture.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../../anywork_client/test/support/timeline_transport.dart'
    show TestHistoryReader;
import '../support/pump_client_future.dart';
import '../support/recording_demo_transport.dart'
    show RecordingHistoryReader, timelineReady;
import '../support/test_app_lifecycle.dart';
import '../support/test_statistics_feed.dart';

const _threadId = 'thread-main';

Finder _timelineScroll(ScrollController controller) => find.byWidgetPredicate(
  (widget) => widget is Scrollable && identical(widget.controller, controller),
);

Finder get _returnLatest => find.byKey(StudioDriverKeys.timelineReturnLatest);

Future<void> _wheel(WidgetTester tester, Finder scroll, double dy) async {
  await tester.sendEventToBinding(
    PointerScrollEvent(
      position: tester.getCenter(scroll),
      scrollDelta: Offset(0, dy),
    ),
  );
}

Future<AppGraph> _mountNative(
  WidgetTester tester,
  _NativeHistoryTransport transport,
) async {
  await tester.binding.setSurfaceSize(const Size(820, 580));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final graph = testAppGraph(
    statisticsFeed: const TestStatisticsFeedPort(),
    transport: transport,
    clientId: 'native-timeline-follow',
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    final report = await pumpClientFuture(
      tester,
      graph.close(budget: testCloseBudget()),
      'close native timeline',
    );
    expect(report.complete, isTrue);
  });
  await pumpClientFuture(tester, graph.client.bootstrap(), 'bootstrap');
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appGraphProvider.overrideWithValue(graph)],
      child: MaterialApp(
        theme: pureStudioTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: LatestScrollScope(
            child: Column(
              children: [
                Expanded(child: TimelineConnector(threadId: _threadId)),
                ReturnToLatestButton(),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  graph.setConversationPageVisible(true);
  await pumpClientFuture(
    tester,
    graph.client.directoryCommands.selectThread(_threadId),
    'select thread',
  );
  await pumpClientFuture(
    tester,
    timelineReady(graph.timeline, _threadId),
    'initial history',
  );
  await pumpClientUntil(tester, () {
    final scroll = graph.timeline.lease(_threadId)?.scrollController;
    return scroll != null &&
        scroll.hasClients &&
        scroll.position.hasContentDimensions;
  }, 'initial timeline layout');
  return graph;
}

Future<void> _layout(WidgetTester tester) async {
  await tester.pump();
  await tester.pumpAndSettle();
}

Finder _marker(int number) => find.byKey(
  ValueKey('expanded-marker-${number.toString().padLeft(3, '0')}'),
);
Finder _groupVerticalScrolls() => find.descendant(
  of: find.byType(CompletionRunView),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Scrollable &&
        (widget.axisDirection == AxisDirection.down ||
            widget.axisDirection == AxisDirection.up),
  ),
);

void main() {
  testWidgets('native history stays frozen until explicit or manual return', (
    tester,
  ) async {
    final transport = _NativeHistoryTransport();
    final graph = await _mountNative(tester, transport);
    final owner = graph.timeline;
    final lease = owner.lease(_threadId)!;
    final controller = lease.scrollController;
    final scroll = _timelineScroll(controller);
    List<String> rowIds() =>
        lease.controller.messages.map((row) => row.id).toList();
    final frozenRows = rowIds();
    final frozenCursor = lease.olderCursor;
    expect(frozenRows.last, 'row:10');
    expect(_returnLatest, findsNothing);

    await tester.drag(scroll, const Offset(0, 170));
    await _layout(tester);
    expect(lease.mode, TimelineDisplayMode.history);
    final readingOffset = controller.offset;
    expect(readingOffset, greaterThan(100));
    expect(_returnLatest.hitTestable(), findsOneWidget);

    transport.publishHead(11);
    await pumpClientUntil(
      tester,
      () => owner.source.value!.hasNewOutput,
      'new output while reading',
    );
    await _layout(tester);
    expect(rowIds(), frozenRows);
    expect(lease.olderCursor, frozenCursor);
    expect(controller.offset, closeTo(readingOffset, .5));
    expect(_returnLatest, findsOneWidget);

    final readsBeforeButton = transport.latestReads;
    await tester.tap(_returnLatest);
    await pumpClientUntil(
      tester,
      () =>
          lease.mode == TimelineDisplayMode.live &&
          _returnLatest.evaluate().isEmpty,
      'explicit return committed',
    );
    expect(owner.lease(_threadId), same(lease));
    expect(rowIds().last, 'row:11');
    expect(transport.latestReads, readsBeforeButton + 1);
    expect(owner.source.value!.hasNewOutput, isFalse);
    expect(controller.offset, closeTo(controller.position.minScrollExtent, .5));

    await _wheel(tester, scroll, -170);
    await _layout(tester);
    expect(lease.mode, TimelineDisplayMode.history);
    transport.publishHead(12);
    await pumpClientUntil(
      tester,
      () => owner.source.value!.hasNewOutput,
      'new output before manual return',
    );
    expect(rowIds().last, 'row:11');
    await _wheel(tester, scroll, 350);
    await pumpClientUntil(
      tester,
      () =>
          lease.mode == TimelineDisplayMode.live &&
          _returnLatest.evaluate().isEmpty,
      'manual return committed',
    );
    expect(rowIds().last, 'row:12');
    expect(controller.offset, closeTo(controller.position.minScrollExtent, .5));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed latest read preserves Native history and can be retried',
    (tester) async {
      final transport = _NativeHistoryTransport();
      final graph = await _mountNative(tester, transport);
      final owner = graph.timeline;
      final lease = owner.lease(_threadId)!;
      final controller = lease.scrollController;
      await _wheel(tester, _timelineScroll(controller), -170);
      await _layout(tester);
      expect(lease.mode, TimelineDisplayMode.history);
      final readingOffset = controller.offset;
      final failure = StateError('latest page unavailable');
      transport.latestError = failure;

      await tester.tap(_returnLatest);
      await pumpClientUntil(
        tester,
        () => owner.source.value?.connectionError == failure,
        'failed latest-page read',
      );
      await _layout(tester);
      expect(owner.lease(_threadId), same(lease));
      expect(lease.mode, TimelineDisplayMode.history);
      expect(controller.offset, closeTo(readingOffset, .5));
      expect(owner.source.value!.hasNewOutput, isFalse);
      expect(_returnLatest.hitTestable(), findsOneWidget);

      transport.latestError = null;
      await tester.tap(_returnLatest);
      await pumpClientUntil(
        tester,
        () =>
            lease.mode == TimelineDisplayMode.live &&
            _returnLatest.evaluate().isEmpty,
        'retry latest page from the same lease',
      );
      expect(owner.lease(_threadId), same(lease));
      expect(controller.position.extentBefore, 0);
    },
  );

  testWidgets('scrolling older cancels a return queued behind Native paging', (
    tester,
  ) async {
    final transport = _NativeHistoryTransport();
    final graph = await _mountNative(tester, transport);
    final owner = graph.timeline;
    final lease = owner.lease(_threadId)!;
    final controller = lease.scrollController;
    final scroll = _timelineScroll(controller);
    transport.olderRelease = Completer<void>();
    addTearDown(() {
      if (!transport.olderRelease!.isCompleted) {
        transport.olderRelease!.complete();
      }
    });

    expect(controller.position.maxScrollExtent, greaterThan(300));
    await _wheel(tester, scroll, -(controller.position.maxScrollExtent - 140));
    await pumpClientUntil(
      tester,
      () =>
          transport.olderReads.isNotEmpty &&
          _returnLatest.evaluate().isNotEmpty,
      'fixed-cut older query',
    );
    expect(lease.mode, TimelineDisplayMode.history);
    expect(transport.olderReads, [(const HistoryCut('head-10'), 'older:2')]);

    transport.publishHead(11);
    await pumpClientUntil(
      tester,
      () => owner.source.value!.hasNewOutput,
      'new output while older query waits',
    );
    final readsBeforeReturn = transport.latestReads;
    await tester.tap(_returnLatest);
    await tester.pump();
    expect(transport.latestReads, readsBeforeReturn);

    await _wheel(tester, scroll, -70);
    transport.olderRelease!.complete();
    await pumpClientUntil(
      tester,
      () => !owner.source.value!.isLoadingOlder,
      'older page applied',
    );
    await _layout(tester);
    expect(transport.latestReads, readsBeforeReturn);
    expect(transport.olderReads, [(const HistoryCut('head-10'), 'older:2')]);
    expect(lease.mode, TimelineDisplayMode.history);
    expect(lease.controller.messages.first.id, 'row:1');
    expect(lease.controller.messages.last.id, 'row:10');
    expect(controller.offset, greaterThan(100));
    expect(_returnLatest.hitTestable(), findsOneWidget);

    await tester.tap(_returnLatest);
    await pumpClientUntil(
      tester,
      () =>
          lease.mode == TimelineDisplayMode.live &&
          _returnLatest.evaluate().isEmpty,
      'new return committed',
    );
    expect(transport.latestReads, readsBeforeReturn + 1);
    expect(lease.controller.messages.last.id, 'row:11');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'preview fixture isolates activity rows from an inherited dark ListTileTheme',
    (tester) async {
      const inheritedTileColor = Color(0xff111111);
      await tester.pumpWidget(
        Theme(
          data: ThemeData.dark(),
          child: const ListTileTheme(
            data: ListTileThemeData(tileColor: inheritedTileColor),
            child: ExpandedWorkTimelineFixture(initialCount: 2),
          ),
        ),
      );
      await _layout(tester);
      final row = find.byType(TimelineActivityRow).first;
      expect(row, findsOneWidget);
      final context = tester.element(row);
      final ownTheme = pureStudioTheme(locale: const Locale('zh'));
      expect(Theme.of(context).brightness, ownTheme.brightness);
      expect(
        ListTileTheme.of(context).tileColor,
        ownTheme.listTileTheme.tileColor,
      );
      expect(ListTileTheme.of(context).tileColor, isNot(inheritedTileColor));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('automatic fill follows a new cut with the same older cursor', (
    tester,
  ) async {
    final release = Completer<void>();
    final transport = _NativeHistoryTransport(headRows: 1)
      ..olderRelease = release;
    final graph = await _mountNative(tester, transport);
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    final owner = graph.timeline;
    final lease = owner.lease(_threadId)!;
    await pumpClientUntil(
      tester,
      () => transport.olderReads.isNotEmpty,
      'short viewport fill',
    );
    expect(transport.olderReads, [(const HistoryCut('head-10'), 'older')]);
    expect(lease.mode, TimelineDisplayMode.live);
    expect(_returnLatest, findsNothing);

    transport.publishHead(11);
    await pumpClientUntil(
      tester,
      () => lease.controller.messages.singleOrNull?.id == 'row:11',
      'new live window while prefill waits',
    );
    expect(lease.olderCursor, 'older');
    expect(owner.source.value!.hasNewOutput, isFalse);
    release.complete();
    await pumpClientUntil(
      tester,
      () => lease.appliedPrepends == 1,
      'current cut fills the viewport',
    );
    await _layout(tester);
    expect(transport.olderReads, [
      (const HistoryCut('head-10'), 'older'),
      (const HistoryCut('head-11'), 'older'),
    ]);
    expect(lease.mode, TimelineDisplayMode.live);
    expect(lease.controller.messages.last.id, 'row:11');
    expect(lease.appliedPrepends, 1);
    expect(owner.source.value!.olderError, isNull);
    expect(_returnLatest, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Native submission echo mounts at the latest edge and follows new input',
    (tester) async {
      final controls = ExpandedWorkPreviewControls();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        controls.dispose();
      });
      var returns = 0;
      ComposerSubmission echo(String id) => ComposerSubmission(
        inputId: id,
        text: 'Submitted prompt $id',
        attachments: const [],
        phase: ComposerSubmissionPhase.sending,
      );
      Future<void> show(List<ComposerSubmission> submissions) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: pureStudioTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: TimelineView(
                threadId: _threadId,
                view: const TimelineSessionViewState(
                  threadId: _threadId,
                  generation: 1,
                  mode: TimelineDisplayMode.live,
                  connection: TimelineConnectionPhase.ready,
                ),
                controls: controls,
                submissions: submissions,
                onLoadOlder: () async {},
                onRetryOlder: () async {},
                onReturnLive: () async {
                  returns++;
                  return true;
                },
                onEnterHistory: () {},
                onRetryConnection: () {},
                onLink: (_) {},
                isSafeLink: (_) => false,
                remoteImageBuilder: (_, _) => const SizedBox.shrink(),
              ),
            ),
          ),
        );
        await _layout(tester);
      }

      final first = echo('first');
      await show([first]);
      final firstCard = find.byKey(const ValueKey('composer-submission:first'));
      expect(firstCard.hitTestable(), findsOneWidget);
      final l10n = AppLocalizations.of(tester.element(firstCard));
      expect(find.text(l10n.timelineEmptyMessage), findsNothing);
      expect(returns, 0);

      await show([first, echo('second')]);
      expect(
        find.byKey(const ValueKey('composer-submission:second')).hitTestable(),
        findsOneWidget,
      );
      expect(returns, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final location in WorkDisplayLocation.values) {
    testWidgets(
      '$location production main timeline reaches first middle last of 120 mixed members',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(820, 720));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final key = GlobalKey<ExpandedWorkTimelineFixtureState>();
        await tester.pumpWidget(
          ExpandedWorkTimelineFixture(key: key, location: location),
        );
        await _layout(tester);
        expect(find.byType(CompletionRunView), findsOneWidget);
        expect(
          tester.getSize(find.byType(CompletionRunView)).height,
          greaterThan(420),
        );
        expect(_groupVerticalScrolls(), findsNothing);
        final scroll = key.currentState!.controls.scrollController;
        expect(scroll.hasClients, isTrue);
        expect(scroll.position.maxScrollExtent, greaterThan(2000));
        for (final number in [1, 60, 120]) {
          final row = _marker(number);
          expect(row, findsOneWidget);
          await Scrollable.ensureVisible(tester.element(row), alignment: .5);
          await _layout(tester);
          expect(
            row.hitTestable(),
            findsOneWidget,
            reason:
                'Member $number is reachable through the production main scroll',
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('$location bottom follows additions and async height', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(820, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final key = GlobalKey<ExpandedWorkTimelineFixtureState>();
      await tester.pumpWidget(
        ExpandedWorkTimelineFixture(
          key: key,
          location: location,
          initialCount: 30,
        ),
      );
      await _layout(tester);
      final state = key.currentState!;
      final scroll = state.controls.scrollController;
      scroll.jumpTo(scroll.position.minScrollExtent);
      await _layout(tester);
      state.appendMember();
      await _layout(tester);
      expect(
        scroll.position.pixels,
        closeTo(scroll.position.minScrollExtent, 1),
      );
      await state.growMiddle();
      await _layout(tester);
      expect(
        scroll.position.pixels,
        closeTo(scroll.position.minScrollExtent, 1),
      );
      expect(
        find.text(
          '完整 31 项 · ${location == WorkDisplayLocation.history ? '历史消息行' : '当前消息行'}',
        ),
        findsOneWidget,
      );
      expect(_groupVerticalScrolls(), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      '$location actual main drag enters history and later growth does not force bottom',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(820, 720));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final key = GlobalKey<ExpandedWorkTimelineFixtureState>();
        await tester.pumpWidget(
          ExpandedWorkTimelineFixture(
            key: key,
            location: location,
            initialCount: 30,
          ),
        );
        await _layout(tester);
        final state = key.currentState!;
        final scroll = state.controls.scrollController;
        await Scrollable.ensureVisible(
          tester.element(_marker(15)),
          alignment: .5,
        );
        await _layout(tester);
        expect(
          state.mode,
          TimelineDisplayMode.live,
          reason: 'Programmatic reveal alone is not user intent',
        );
        final main = _timelineScroll(scroll);
        expect(main, findsOneWidget);
        await tester.drag(main, const Offset(0, 120));
        await _layout(tester);
        expect(state.mode, TimelineDisplayMode.history);
        final reading = scroll.position.pixels;
        expect(reading, greaterThan(100));
        state.appendMember();
        await _layout(tester);
        expect(
          scroll.position.pixels,
          greaterThan(100),
          reason:
              'Appending must not return an upward-reading user to the bottom',
        );
        expect(_marker(15).hitTestable(), findsOneWidget);
        await state.growMiddle();
        await _layout(tester);
        expect(state.mode, TimelineDisplayMode.history);
        expect(
          scroll.position.pixels,
          greaterThan(100),
          reason: 'Async details must not steal the upward-reading intent',
        );
        expect(_groupVerticalScrolls(), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}

class _NativeHistoryTransport extends TestDemoStudioTransport {
  _NativeHistoryTransport({this.headRows = 8});

  final int headRows;
  int _head = 10;
  HistoryCut get _headCut => HistoryCut('head-$_head');
  Completer<HistoryCut>? _changed;
  int latestReads = 0;
  Object? latestError;
  final olderReads = <(HistoryCut?, String)>[];
  Completer<void>? olderRelease;

  void publishHead(int head) {
    _head = head;
    final changed = _changed;
    _changed = null;
    changed?.complete(_headCut);
  }

  @override
  Future<HistoryReader> openHistoryReader(
    String threadId, {
    required int historyProtocolVersion,
  }) async =>
      RecordingHistoryReader(
          inner:
              TestHistoryReader(
                  threadId: threadId,
                  protocolVersion: historyProtocolVersion,
                  cut: _headCut,
                )
                ..onWaitChanged = (after) => after == _headCut
                    ? (_changed ??= Completer<HistoryCut>()).future
                    : Future.value(_headCut),
        )
        ..onTimelinePage = (cut, cursor, demand) async {
          final requestedCut = cut ?? _headCut;
          final head = int.parse(requestedCut.token.substring('head-'.length));
          if (cursor != null) {
            olderReads.add((cut, cursor));
            await olderRelease?.future;
            final newest = cursor == 'older'
                ? head - headRows
                : int.parse(cursor.substring('older:'.length));
            final count = min(newest, demand.maxRows);
            return _page(
              requestedCut,
              newest: newest,
              count: count,
              next: newest > count ? 'older:${newest - count}' : null,
            );
          }
          if (cut == null) {
            latestReads++;
            if (latestError case final error?) throw error;
          }
          return _page(
            requestedCut,
            newest: head,
            count: headRows,
            next: headRows == 1 ? 'older' : 'older:${head - headRows}',
          );
        };

  HistoryTimelinePage _page(
    HistoryCut cut, {
    required int newest,
    required int count,
    String? next,
  }) => HistoryTimelinePage(
    cut: cut,
    next: next,
    items: [
      for (var seq = newest; seq > newest - count; seq--)
        BoundaryTimelineItem(_row(seq)),
    ],
  );

  HistoryEventRecord _row(int seq) {
    final id = 'input-$seq';
    final text = List.generate(
      6,
      (line) => 'Prompt $seq, paragraph $line',
    ).join('\n\n');
    return HistoryEventRecord(
      seq: seq,
      eventId: 'event:$id',
      kind: 'input_accepted',
      timelineRole: HistoryTimelineRole.boundary,
      recordedAt: seq * 1000,
      entityId: id,
      rowKey: 'row:$seq',
      source: InputChatSource(inputId: id),
      payloadSchema: 'anywork.event/1',
      payloadJson: jsonEncode({
        'contract': 'anywork.event/1',
        'type': 'text',
        'meta': {
          'entityId': id,
          'entityKind': 'input',
          'delivery': 'foreground',
          'state': {'kind': 'knownTerminal', 'outcome': 'completed'},
          'contentPresent': true,
        },
        'data': {'channel': 'user'},
        'bodies': [
          {
            'key': 'body',
            'byteLength': utf8.encode(text).length,
            'inlineText': text,
          },
        ],
      }),
    );
  }
}
