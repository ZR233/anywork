import 'dart:async';

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

import '../support/conversation_feed_fixtures.dart';
import '../support/pump_client_future.dart';
import '../support/recording_demo_transport.dart';
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
  RecordingDemoTransport transport,
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
    final transport = _timelineTransport();
    final graph = await _mountNative(tester, transport);
    final feed = transport.feedFor(_threadId);
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

    feed.emit(ConversationTimeline(patch: TimelineAppend(items: [_row(11)])));
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
    expect(feed.resetRequests, isEmpty);
    expect(owner.source.value!.hasNewOutput, isFalse);
    expect(controller.offset, closeTo(controller.position.minScrollExtent, .5));

    await _wheel(tester, scroll, -170);
    await _layout(tester);
    expect(lease.mode, TimelineDisplayMode.history);
    feed.emit(ConversationTimeline(patch: TimelineAppend(items: [_row(12)])));
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
    expect(feed.resetRequests, isEmpty);
    expect(controller.offset, closeTo(controller.position.minScrollExtent, .5));
    expect(tester.takeException(), isNull);
  });

  for (final count in [64, 65]) {
    testWidgets(
      'Native history buffers $count new rows within the fixed limit',
      (tester) async {
        final transport = _timelineTransport();
        final graph = await _mountNative(tester, transport);
        final owner = graph.timeline;
        final lease = owner.lease(_threadId)!;
        final feed = transport.feedFor(_threadId);
        final original = lease.controller.messages
            .map((row) => row.id)
            .toList();
        final incoming = [
          for (var seq = 11; seq < 11 + count; seq++) _row(seq),
        ];
        feed.onReset = (limit) async => TimelineReset(
          items: incoming.skip(count - 5),
          hasMoreOlder: true,
          olderCursor: 'latest-older',
          revision: 2,
        );

        await _wheel(tester, _timelineScroll(lease.scrollController), -170);
        await _layout(tester);
        expect(lease.mode, TimelineDisplayMode.history);
        feed.emit(
          ConversationTimeline(patch: TimelineAppend(items: incoming.take(32))),
        );
        feed.emit(
          ConversationTimeline(patch: TimelineAppend(items: incoming.skip(32))),
        );
        feed.emit(
          ConversationLiveStatus(
            snapshot: LiveStatusSnapshot(
              revision: 99,
              phase: const LiveStatusIdle(),
              attentions: const [],
              suppressedByInteraction: false,
            ),
          ),
        );
        await pumpClientUntil(
          tester,
          () => owner.liveStatus.value?.snapshot.revision == 99,
          'both append patches reached the paused timeline',
        );
        expect(lease.hasNewOutput, isTrue);
        expect(lease.controller.messages.map((row) => row.id), original);
        expect(
          find.byKey(StudioDriverKeys.timelineReturnLatest),
          findsOneWidget,
        );
        await tester.tap(_returnLatest);
        await pumpClientUntil(
          tester,
          () => lease.mode == TimelineDisplayMode.live,
          'return to latest',
        );

        expect(
          lease.controller.messages.map((row) => row.id),
          count == 64
              ? [...original, ...incoming.map((row) => row.id)]
              : incoming.skip(count - 5).map((row) => row.id),
        );
        expect(feed.resetRequests, count == 64 ? isEmpty : hasLength(1));
        expect(lease.appliedSets, count == 64 ? 1 : 2);
        expect(lease.hasNewOutput, isFalse);
      },
    );
  }

  testWidgets('Native older paging keeps its cursor and prepends in order', (
    tester,
  ) async {
    final transport = _timelineTransport();
    final graph = await _mountNative(tester, transport);
    final owner = graph.timeline;
    final lease = owner.lease(_threadId)!;
    final feed = transport.feedFor(_threadId);
    final firstPage = Completer<TimelinePatch>();
    addTearDown(() {
      if (!firstPage.isCompleted) {
        firstPage.complete(
          TimelinePrependOlder(items: const [], hasMoreOlder: false),
        );
      }
    });
    feed.onLoadOlder = (cursor, _) => firstPage.future;
    final older = owner.loadOlder(_threadId, generation: lease.generation);
    await pumpClientUntil(
      tester,
      () => feed.olderRequests.isNotEmpty,
      'older query entered',
    );
    expect(feed.olderRequests.single.cursor, 'older:2');
    final samePage = owner.loadOlder(_threadId, generation: lease.generation);
    feed.emit(ConversationTimeline(patch: TimelineAppend(items: [_row(11)])));
    await pumpClientUntil(
      tester,
      () => lease.controller.messages.last.id == 'row:11',
      'live append during paging',
    );
    firstPage.complete(
      TimelinePrependOlder(items: [_row(1), _row(2)], hasMoreOlder: false),
    );
    await pumpClientFuture(
      tester,
      Future.wait([older, samePage]),
      'older page applied',
    );
    expect(lease.controller.messages.map((row) => row.id), [
      for (var seq = 1; seq <= 11; seq++) 'row:$seq',
    ]);
    expect(feed.olderRequests, hasLength(1));
    expect(lease.appliedSets, 1);
    expect(lease.appliedPrepends, 1);
    expect(lease.hasOlder, isFalse);
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

  // Both model locations are rows in TimelineView. Bounded live work scrolling
  // is covered by live_status_surface_view_test.dart, including its fixed header.
  for (final location in WorkDisplayLocation.values) {
    testWidgets(
      'TimelineView $location model reaches first middle last of 120 mixed members',
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

    testWidgets(
      'TimelineView $location model follows additions and async height',
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
      },
    );

    testWidgets(
      'TimelineView $location model drag enters history and later growth does not force bottom',
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

RecordingDemoTransport _timelineTransport() =>
    RecordingDemoTransport()
      ..onFeedOpened = (feed) {
        feed.mapReset = (reset) => TimelineReset(
          items: [for (var seq = 3; seq <= 10; seq++) _row(seq)],
          hasMoreOlder: true,
          olderCursor: 'older:2',
          revision: reset.revision,
        );
      };

TimelineUserMessage _row(int seq) => feedUser(
  'row:$seq',
  seq,
  List.generate(6, (line) => 'Prompt $seq, paragraph $line').join('\n\n'),
  inputId: 'input-$seq',
);
