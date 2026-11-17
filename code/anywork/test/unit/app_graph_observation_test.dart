import '../support/test_app_lifecycle.dart';
import '../support/chat_fixtures.dart';
import '../support/test_statistics_feed.dart';

import 'dart:async';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/presentation/providers/thread_session_store.dart';
import 'package:anywork/src/presentation/providers/composer_draft_controller.dart';
import 'package:anywork/src/presentation/providers/start_session_controller.dart';
import 'package:anywork/src/presentation/providers/skills_store.dart';
import 'package:anywork/src/presentation/providers/session_costs_store.dart';
import 'package:anywork_client/studio_client.dart'
    show CloseReport, DomainSyncPhase, FailedComposerThreadState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/recording_demo_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'reentrant graph close keeps the first future and mounted display report',
    () async {
      final transport = RecordingDemoTransport();
      final graph = testAppGraph(
        statisticsFeed: const TestStatisticsFeedPort(),
        transport: transport,
        clientId: 'reentrant-graph-close',
      );
      await graph.client.bootstrap();
      graph.timeline.updateReadDemand(chatDemand);
      graph.setConversationPageVisible(true);
      await graph.client.directoryCommands.selectThread('thread-main');
      await timelineReady(graph.timeline, 'thread-main');
      final lease = graph.timeline.lease('thread-main')!..bind();
      Future<CloseReport>? nested;
      final observation = graph.timeline.source.watch((state) {
        if (state == null) {
          nested = graph.close(budget: testBudgetUntil(_deadline()));
        }
      });
      try {
        final closing = graph.close(budget: ClientCloseBudget(Duration.zero));
        expect(nested, same(closing));
        final report = await closing;
        expect(report.complete, isFalse);
        expect(
          report.unresolved.any(
            (entry) => entry.owner == 'timeline-display:thread-main',
          ),
          isTrue,
        );
        expect(lease.isReleased, isFalse);
        await lease.unbind();
        expect(
          graph.close(budget: testBudgetUntil(_deadline())),
          same(closing),
        );
      } finally {
        observation.cancel();
        if (!lease.isReleased) await lease.unbind();
        await graph.close(budget: testBudgetUntil(_deadline()));
        await graph.client.retryCleanup(budget: testBudgetUntil(_deadline()));
      }
    },
  );

  test('observing missing resources never admits a Client owner', () async {
    final transport = RecordingDemoTransport();
    final graph = testAppGraph(
      statisticsFeed: const TestStatisticsFeedPort(),
      transport: transport,
      clientId: 'missing-owner',
    );
    addTearDown(() => graph.close(budget: testBudgetUntil(_deadline())));
    final client = graph.client;
    final container = _container(graph);
    final session = container.listen(
      threadSessionStoreProvider('unselected-thread'),
      (_, _) {},
    );
    final composer = container.listen(
      composerDraftControllerProvider('unselected-thread'),
      (_, _) {},
    );
    final skills = container.listen(
      skillsStoreProvider('unselected-project'),
      (_, _) {},
    );
    final costs = container.listen(
      sessionCostsStoreProvider('unselected-thread'),
      (_, _) {},
    );
    try {
      expect(client.conversations.existingSession('unselected-thread'), isNull);
      expect(client.drafts.existingComposer('unselected-thread'), isNull);
      expect(client.existingSkills('unselected-project'), isNull);
      expect(client.existingSessionCosts('unselected-thread'), isNull);
      expect(session.read().hasSnapshot, isFalse);
      expect(session.read().sync.phase, DomainSyncPhase.idle);
      expect(composer.read(), isA<FailedComposerThreadState>());
      expect(skills.read().loaded, isFalse);
      expect(costs.read().loaded, isFalse);
      // 未加载会话只观察 visibleThreadId；其他三个缺失 owner 各观察 selection 与 failure。
      expect(client.channels.activeTopicRefCountViews(), isEmpty);
      expect(transport.currentReaders, isEmpty);
    } finally {
      session.close();
      composer.close();
      skills.close();
      costs.close();
      container.dispose();
    }
  });

  test(
    'account cancellation, disposal and rebuilding preserve app resources',
    () async {
      final transport = RecordingDemoTransport();
      final graph = testAppGraph(
        statisticsFeed: const TestStatisticsFeedPort(),
        transport: transport,
        clientId: 'observer-owner',
      );
      addTearDown(() => graph.close(budget: testBudgetUntil(_deadline())));
      await graph.client.bootstrap();
      await (graph
            ..timeline.updateReadDemand(chatDemand)
            ..setConversationPageVisible(true))
          .client
          .directoryCommands
          .selectThread('thread-main');
      await graph.client.conversations.visibleThreadId.waitFor(
        (id) => id == 'thread-main',
      );
      await timelineReady(graph.timeline, 'thread-main');
      final connection = _timelineCurrentReader(transport, 'thread-main');
      await connection.watchEntered.future;
      final attemptId = graph.timeline
          .lease('thread-main')!
          .current
          .metadata
          .readerId;
      final workspaceId = graph.client.selection.state.selectedProjectId!;
      final startOwner = graph.client.drafts.startDraft;
      final composerOwner = graph.client.drafts.existingComposer(
        'thread-main',
      )!;
      expect(graph.client.existingSkills(workspaceId), isNotNull);
      expect(graph.client.existingSessionCosts('thread-main'), isNotNull);

      final first = _container(graph);
      final sessionObserver = first.listen(
        threadSessionStoreProvider('thread-main'),
        (_, _) {},
      );
      final startObserver = first.listen(
        startSessionControllerProvider,
        (_, _) {},
      );
      final composerObserver = first.listen(
        composerDraftControllerProvider('thread-main'),
        (_, _) {},
      );
      final timelineObserver = graph.timeline.source.watch((_) {});
      graph.client.drafts.startDraft.updateDraft(
        workspaceId,
        'new session survives Settings',
      );
      graph.client.drafts
          .composer('thread-main')
          .updateDraft('existing session survives observation disposal');

      sessionObserver.close();
      startObserver.close();
      composerObserver.close();
      timelineObserver.cancel();
      await first.pump();
      first.dispose();

      expect(connection.requestCloseCalls, 0);
      expect(connection.closeCalls, 0);
      expect(
        graph.timeline.lease('thread-main')!.current.metadata.readerId,
        attemptId,
      );
      expect(graph.timeline.lease('thread-main'), isNotNull);
      expect(graph.client.drafts.startDraft, same(startOwner));
      expect(graph.client.drafts.composer('thread-main'), same(composerOwner));
      expect(
        startOwner.state.forProject(workspaceId).text,
        'new session survives Settings',
      );
      expect(
        composerOwner.state.draft,
        'existing session survives observation disposal',
      );

      final rebuilt = _container(graph);
      addTearDown(rebuilt.dispose);
      final rebuiltSession = rebuilt.listen(
        threadSessionStoreProvider('thread-main'),
        (_, _) {},
      );
      final rebuiltStart = rebuilt.listen(
        startSessionControllerProvider,
        (_, _) {},
      );
      final rebuiltComposer = rebuilt.listen(
        composerDraftControllerProvider('thread-main'),
        (_, _) {},
      );
      addTearDown(rebuiltSession.close);
      addTearDown(rebuiltStart.close);
      addTearDown(rebuiltComposer.close);

      expect(
        graph.timeline.lease('thread-main')!.current.metadata.readerId,
        attemptId,
      );
      expect(
        rebuilt
            .read(startSessionControllerProvider)
            .forProject(workspaceId)
            .text,
        'new session survives Settings',
      );
      expect(
        rebuilt.read(composerDraftControllerProvider('thread-main')).draft,
        'existing session survives observation disposal',
      );
      expect(
        _activeTimelineCurrentReaders(transport, 'thread-main'),
        hasLength(1),
      );
      expect(connection.initialViewReads, 1);

      final report = await graph.close(budget: testBudgetUntil(_deadline()));
      expect(report.unresolved, isEmpty);
      expect(connection.requestCloseCalls, greaterThanOrEqualTo(1));
      expect(connection.closeCalls, 1);
      expect(connection.joined.isCompleted, isTrue);
    },
  );

  test('two injected AppGraphs have independent sessions and drafts', () async {
    final firstTransport = RecordingDemoTransport();
    final secondTransport = RecordingDemoTransport();
    final first = testAppGraph(
      statisticsFeed: const TestStatisticsFeedPort(),
      transport: firstTransport,
      clientId: 'first-app',
    );
    final second = testAppGraph(
      statisticsFeed: const TestStatisticsFeedPort(),
      transport: secondTransport,
      clientId: 'second-app',
    );
    addTearDown(() => first.close(budget: testBudgetUntil(_deadline())));
    addTearDown(() => second.close(budget: testBudgetUntil(_deadline())));
    await Future.wait([first.client.bootstrap(), second.client.bootstrap()]);
    final beforeVisibleSelection = first.timeline.monotonicMicros;
    first.setConversationPageVisible(true);
    second.setConversationPageVisible(true);
    await Future.wait([
      first.client.directoryCommands.selectThread('thread-main'),
      second.client.directoryCommands.selectThread('thread-main'),
    ]);
    final afterVisibleSelection = first.timeline.monotonicMicros;
    expect(
      _activeTimelineCurrentReaders(firstTransport, 'thread-main'),
      isEmpty,
    );
    expect(
      _activeTimelineCurrentReaders(secondTransport, 'thread-main'),
      isEmpty,
      reason: 'canonical visible selection does not fabricate viewport demand',
    );
    first.timeline.updateReadDemand(chatDemand);
    second.timeline.updateReadDemand(chatDemand);
    await Future.wait([
      timelineReady(first.timeline, 'thread-main'),
      timelineReady(second.timeline, 'thread-main'),
    ]);
    final display = first.timeline.lease('thread-main')!;
    expect(display.selectionId, isNotNull);
    expect(
      display.selectionStartedMicros,
      inInclusiveRange(beforeVisibleSelection, afterVisibleSelection),
      reason: 'AppGraph records selection before demand and successful Set',
    );
    expect(
      display.firstContentLayout,
      isNull,
      reason: 'a headless ready display has no real content layout witness',
    );
    final firstContainer = _container(first);
    final secondContainer = _container(second);
    addTearDown(firstContainer.dispose);
    addTearDown(secondContainer.dispose);
    final firstObserver = firstContainer.listen(
      composerDraftControllerProvider('thread-main'),
      (_, _) {},
    );
    final secondObserver = secondContainer.listen(
      composerDraftControllerProvider('thread-main'),
      (_, _) {},
    );
    addTearDown(firstObserver.close);
    addTearDown(secondObserver.close);
    first.client.drafts.composer('thread-main').updateDraft('first app');
    second.client.drafts.composer('thread-main').updateDraft('second app');
    final workspaceId = first.client.selection.state.selectedProjectId!;
    first.client.drafts.startDraft.updateDraft(
      workspaceId,
      'first start draft',
    );

    expect(
      first.client.conversations.session('thread-main'),
      isNot(same(second.client.conversations.session('thread-main'))),
    );
    expect(
      _timelineCurrentReader(firstTransport, 'thread-main'),
      isNot(same(_timelineCurrentReader(secondTransport, 'thread-main'))),
    );
    expect(first.timeline, isNot(same(second.timeline)));
    expect(
      second.client.drafts.startDraft.state.forProject(workspaceId).text,
      isEmpty,
    );
    expect(
      firstContainer.read(composerDraftControllerProvider('thread-main')).draft,
      'first app',
    );
    expect(
      secondContainer
          .read(composerDraftControllerProvider('thread-main'))
          .draft,
      'second app',
    );

    expect(
      (await first.close(budget: testBudgetUntil(_deadline()))).complete,
      isTrue,
    );
    expect(
      firstTransport.currentReaders.every(
        (reader) => reader.joined.isCompleted,
      ),
      isTrue,
    );
    expect(
      secondTransport.currentReaders.every(
        (reader) => reader.requestCloseCalls == 0,
      ),
      isTrue,
    );
    expect(second.client.isClosed, isFalse);
    expect(second.timeline.lease('thread-main'), isNotNull);
    expect(
      secondContainer
          .read(composerDraftControllerProvider('thread-main'))
          .draft,
      'second app',
    );
  });

  test(
    'late open after selecting B is reclaimed without clearing current B',
    () async {
      final transport = RecordingDemoTransport();
      final firstOpenEntered = Completer<void>();
      final releaseFirst = Completer<void>();
      var mainOpens = 0;
      transport
        ..nextCurrentOpenGate = releaseFirst
        ..testCurrentOpenEntered = (threadId) {
          if (threadId == 'thread-main' && ++mainOpens == 1) {
            firstOpenEntered.complete();
          }
        };
      final graph = testAppGraph(
        statisticsFeed: const TestStatisticsFeedPort(),
        transport: transport,
        clientId: 'late-demo-attempt',
      );
      addTearDown(() async {
        if (!releaseFirst.isCompleted) releaseFirst.complete();
        await graph.close(budget: testBudgetUntil(_deadline()));
      });
      await graph.client.bootstrap();
      final lateSelection =
          (graph
                ..timeline.updateReadDemand(chatDemand)
                ..setConversationPageVisible(true))
              .client
              .directoryCommands
              .selectThread('thread-main');
      await firstOpenEntered.future;
      final late = transport.currentReaders.lastWhere(
        (reader) =>
            reader.threadId == 'thread-main' &&
            reader.demand.maxItems != chatDemand.maxItems,
      );
      await (graph
            ..timeline.updateReadDemand(chatDemand)
            ..setConversationPageVisible(true))
          .client
          .directoryCommands
          .selectThread('thread-alt');
      await timelineReady(graph.timeline, 'thread-alt');
      final currentAttempt = graph.timeline
          .lease('thread-alt')!
          .current
          .metadata
          .readerId;
      final current = transport.currentReaders.lastWhere(
        (value) => value.threadId == 'thread-alt',
      );
      expect(current, isNot(same(late)));

      releaseFirst.complete();
      await lateSelection;
      await late.joined.future;

      expect(
        late.initialViewReads,
        0,
        reason: 'retired open never becomes a baseline',
      );
      expect(late.requestCloseCalls, greaterThanOrEqualTo(1));
      expect(late.closeCalls, 1);
      expect(current.requestCloseCalls, 0);
      expect(
        graph.timeline.lease('thread-alt')!.current.metadata.readerId,
        currentAttempt,
      );
      expect(graph.timeline.lease('thread-alt'), isNotNull);
      final display = graph.timeline.lease('thread-alt')!;
      expect(display.controller.messages, isNotEmpty);
      // This is the Client attempt contract over Demo connections, not native FRB.
    },
  );
}

ProviderContainer _container(AppGraph graph) =>
    ProviderContainer(overrides: [appGraphProvider.overrideWithValue(graph)]);

DateTime _deadline() => DateTime.now().add(const Duration(seconds: 5));

RecordingCurrentReader _timelineCurrentReader(
  RecordingDemoTransport transport,
  String threadId,
) => transport.currentReaders.lastWhere(
  (reader) =>
      reader.threadId == threadId &&
      reader.demand.maxItems == chatDemand.maxItems,
);

Iterable<RecordingCurrentReader> _activeTimelineCurrentReaders(
  RecordingDemoTransport transport,
  String threadId,
) => transport.currentReaders.where(
  (reader) =>
      reader.threadId == threadId &&
      reader.demand.maxItems == chatDemand.maxItems &&
      !reader.requested,
);
