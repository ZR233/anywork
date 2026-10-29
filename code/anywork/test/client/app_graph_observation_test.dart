import 'support/test_statistics_feed.dart';

import 'dart:async';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/presentation/providers/thread_session_store.dart';
import 'package:anywork/src/presentation/providers/composer_draft_controller.dart';
import 'package:anywork/src/presentation/providers/start_session_controller.dart';
import 'package:anywork/src/presentation/providers/skills_store.dart';
import 'package:anywork/src/presentation/providers/session_costs_store.dart';
import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork_client/studio_client.dart'
    show DomainSyncPhase, FailedComposerThreadState, ResourceKind;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_demo_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('observing missing resources never admits a Client owner', () async {
    final transport = RecordingDemoTransport();
    final graph = AppGraph(
      statisticsFeed: const TestStatisticsFeedPort(),
      transport: transport,
      clientId: 'missing-owner',
    );
    addTearDown(() => graph.close(deadline: _deadline()));
    final client = graph.client;
    final readModels = client.budget.used(ResourceKind.readModel);
    final drafts = client.budget.used(ResourceKind.draft);
    final observers = client.budget.used(ResourceKind.observer);
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
      expect(client.budget.used(ResourceKind.readModel), readModels);
      expect(client.budget.used(ResourceKind.draft), drafts);
      // 未加载会话只观察 visibleThreadId；其他三个缺失 owner 各观察 selection 与 failure。
      expect(
        client.budget.used(ResourceKind.observer),
        observers + 1 + 2 + 2 + 2,
      );
      expect(client.channels.activeTopicRefCountViews(), isEmpty);
      expect(transport.feeds, isEmpty);
    } finally {
      session.close();
      composer.close();
      skills.close();
      costs.close();
      container.dispose();
    }
    expect(client.budget.used(ResourceKind.observer), observers);
  });

  test(
    'account cancellation, disposal and rebuilding preserve app resources',
    () async {
      final transport = RecordingDemoTransport();
      final graph = AppGraph(
        statisticsFeed: const TestStatisticsFeedPort(),
        transport: transport,
        clientId: 'observer-owner',
      );
      addTearDown(() => graph.close(deadline: _deadline()));
      await graph.client.bootstrap();
      await (graph..setConversationPageVisible(true)).client.directoryCommands
          .selectThread('thread-main');
      final session = graph.client.conversations.existingSession(
        'thread-main',
      )!;
      await session.content.state.waitFor(
        (state) => state.snapshot is ConversationBaselineFrame,
      );
      final connection = transport.feeds.single;
      await connection.nextEntered.future;
      final attemptId = session.content.currentAttemptId?.value;
      final projectId = graph.client.selection.state.selectedProjectId!;
      final startOwner = graph.client.drafts.startDraft;
      final composerOwner = graph.client.drafts.existingComposer(
        'thread-main',
      )!;
      expect(graph.client.existingSkills(projectId), isNotNull);
      expect(graph.client.existingSessionCosts('thread-main'), isNotNull);
      final observerBudgetBefore = graph.client.budget.used(
        ResourceKind.observer,
      );

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
        projectId,
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

      expect(
        graph.client.budget.used(ResourceKind.observer),
        observerBudgetBefore,
        reason:
            'a disposed ProviderScope must release all its observer permits',
      );
      expect(connection.requestCloseCalls, 0);
      expect(connection.closeCalls, 0);
      expect(session.content.currentAttemptId?.value, attemptId);
      expect(session.content.lastDeliveredFrame, isNotNull);
      expect(graph.client.drafts.startDraft, same(startOwner));
      expect(graph.client.drafts.composer('thread-main'), same(composerOwner));
      expect(
        startOwner.state.forProject(projectId).text,
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
        graph.client.conversations
            .session('thread-main')
            .content
            .currentAttemptId
            ?.value,
        attemptId,
      );
      expect(
        rebuilt.read(startSessionControllerProvider).forProject(projectId).text,
        'new session survives Settings',
      );
      expect(
        rebuilt.read(composerDraftControllerProvider('thread-main')).draft,
        'existing session survives observation disposal',
      );
      expect(transport.feeds, hasLength(1));
      expect(connection.initialCalls, 1);

      final report = await graph.close(deadline: _deadline());
      expect(report.unresolved, isEmpty);
      expect(connection.requestCloseCalls, greaterThanOrEqualTo(1));
      expect(connection.closeCalls, 1);
      expect(connection.joined.isCompleted, isTrue);
    },
  );

  test('two injected AppGraphs have independent sessions and drafts', () async {
    final firstTransport = RecordingDemoTransport();
    final secondTransport = RecordingDemoTransport();
    final first = AppGraph(
      statisticsFeed: const TestStatisticsFeedPort(),
      transport: firstTransport,
      clientId: 'first-app',
    );
    final second = AppGraph(
      statisticsFeed: const TestStatisticsFeedPort(),
      transport: secondTransport,
      clientId: 'second-app',
    );
    addTearDown(() => first.close(deadline: _deadline()));
    addTearDown(() => second.close(deadline: _deadline()));
    await Future.wait([first.client.bootstrap(), second.client.bootstrap()]);
    first.setConversationPageVisible(true);
    second.setConversationPageVisible(true);
    await Future.wait([
      first.client.directoryCommands.selectThread('thread-main'),
      second.client.directoryCommands.selectThread('thread-main'),
    ]);
    await Future.wait([
      first.client.conversations
          .session('thread-main')
          .content
          .state
          .waitFor((state) => state.snapshot is ConversationBaselineFrame),
      second.client.conversations
          .session('thread-main')
          .content
          .state
          .waitFor((state) => state.snapshot is ConversationBaselineFrame),
    ]);
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
    final projectId = first.client.selection.state.selectedProjectId!;
    first.client.drafts.startDraft.updateDraft(projectId, 'first start draft');

    expect(
      first.client.conversations.session('thread-main'),
      isNot(same(second.client.conversations.session('thread-main'))),
    );
    expect(
      firstTransport.feeds.single,
      isNot(same(secondTransport.feeds.single)),
    );
    expect(first.timeline, isNot(same(second.timeline)));
    expect(
      second.client.drafts.startDraft.state.forProject(projectId).text,
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

    expect((await first.close(deadline: _deadline())).complete, isTrue);
    expect(firstTransport.feeds.single.joined.isCompleted, isTrue);
    expect(secondTransport.feeds.single.requestCloseCalls, 0);
    expect(second.client.isClosed, isFalse);
    expect(
      second.client.conversations
          .session('thread-main')
          .content
          .lastDeliveredFrame,
      isNotNull,
    );
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
      final transport = DemoStudioTransport(lspActivityLoop: false);
      final firstOpen = Completer<RecordingConversationFeed>();
      final releaseFirst = Completer<void>();
      var mainOpens = 0;
      final connections = <RecordingConversationFeed>[];
      transport.conversationFeedFactory = (threadId, inner) async {
        final window = RecordingConversationFeed(inner: inner);
        connections.add(window);
        if (threadId == 'thread-main' && ++mainOpens == 1) {
          firstOpen.complete(window);
          await releaseFirst.future;
        }
        return window;
      };
      final graph = AppGraph(
        statisticsFeed: const TestStatisticsFeedPort(),
        transport: transport,
        clientId: 'late-demo-attempt',
      );
      addTearDown(() async {
        if (!releaseFirst.isCompleted) releaseFirst.complete();
        await graph.close(deadline: _deadline());
      });
      await graph.client.bootstrap();
      await (graph..setConversationPageVisible(true)).client.directoryCommands
          .selectThread('thread-main');
      final late = await firstOpen.future;
      await (graph..setConversationPageVisible(true)).client.directoryCommands
          .selectThread('thread-alt');
      await graph.client.conversations
          .session('thread-alt')
          .content
          .state
          .waitFor((state) => state.snapshot is ConversationBaselineFrame);
      final selected = graph.client.conversations.session('thread-alt');
      final currentAttempt = selected.content.currentAttemptId?.value;
      final current = connections.lastWhere(
        (value) => value.threadId == 'thread-alt',
      );
      expect(current, isNot(same(late)));

      releaseFirst.complete();
      await late.joined.future;

      expect(
        late.initialCalls,
        0,
        reason: 'retired open never becomes a baseline',
      );
      expect(late.requestCloseCalls, greaterThanOrEqualTo(1));
      expect(late.closeCalls, 1);
      expect(current.requestCloseCalls, 0);
      expect(selected.content.currentAttemptId?.value, currentAttempt);
      expect(selected.content.lastDeliveredFrame, isNotNull);
      final display = graph.timeline.lease('thread-alt')!;
      expect(display.controller.messages, isNotEmpty);
      // This is the Client attempt contract over Demo connections, not native FRB.
    },
  );
}

ProviderContainer _container(AppGraph graph) =>
    ProviderContainer(overrides: [appGraphProvider.overrideWithValue(graph)]);

DateTime _deadline() => DateTime.now().add(const Duration(seconds: 5));
