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
    final graph = AppGraph(transport: transport, clientId: 'missing-owner');
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
      expect(client.existingSession('unselected-thread'), isNull);
      expect(client.existingComposer('unselected-thread'), isNull);
      expect(client.existingSkills('unselected-project'), isNull);
      expect(client.existingSessionCosts('unselected-thread'), isNull);
      expect(session.read().hasSnapshot, isFalse);
      expect(session.read().sync.phase, DomainSyncPhase.idle);
      expect(composer.read(), isA<FailedComposerThreadState>());
      expect(skills.read().loaded, isFalse);
      expect(costs.read().loaded, isFalse);
      expect(client.budget.used(ResourceKind.readModel), readModels);
      expect(client.budget.used(ResourceKind.draft), drafts);
      expect(client.budget.used(ResourceKind.observer), observers + 8);
      expect(client.channels.activeTopicRefCountViews(), isEmpty);
      expect(transport.timelines, isEmpty);
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
    'provider cancellation, disposal and rebuilding preserve app resources',
    () async {
      final transport = RecordingDemoTransport();
      final graph = AppGraph(transport: transport, clientId: 'observer-owner');
      addTearDown(() => graph.close(deadline: _deadline()));
      await graph.client.bootstrap();
      await graph.client.directoryCommands.selectThread('thread-main');
      final session = graph.client.existingSession('thread-main')!;
      await session.timeline.state.waitFor(
        (state) => state.snapshot is StudioTimelineBaselineFrame,
      );
      final connection = transport.timelines.single;
      await connection.nextEntered.future;
      final attemptId = session.timeline.currentAttemptId?.value;
      final projectId = graph.client.selection.state.selectedProjectId!;
      final startOwner = graph.client.startDraft;
      final composerOwner = graph.client.existingComposer('thread-main')!;
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
      graph.client.startDraft.updateDraft(
        projectId,
        'new session survives Settings',
      );
      graph.client
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
      expect(session.timeline.currentAttemptId?.value, attemptId);
      expect(session.timeline.lastDeliveredFrame, isNotNull);
      expect(graph.client.startDraft, same(startOwner));
      expect(graph.client.composer('thread-main'), same(composerOwner));
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
        graph.client.session('thread-main').timeline.currentAttemptId?.value,
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
      expect(transport.timelines, hasLength(1));
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
    final first = AppGraph(transport: firstTransport, clientId: 'first-app');
    final second = AppGraph(transport: secondTransport, clientId: 'second-app');
    addTearDown(() => first.close(deadline: _deadline()));
    addTearDown(() => second.close(deadline: _deadline()));
    await Future.wait([first.client.bootstrap(), second.client.bootstrap()]);
    await Future.wait([
      first.client.directoryCommands.selectThread('thread-main'),
      second.client.directoryCommands.selectThread('thread-main'),
    ]);
    await Future.wait([
      first.client
          .session('thread-main')
          .timeline
          .state
          .waitFor((state) => state.snapshot is StudioTimelineBaselineFrame),
      second.client
          .session('thread-main')
          .timeline
          .state
          .waitFor((state) => state.snapshot is StudioTimelineBaselineFrame),
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
    first.client.composer('thread-main').updateDraft('first app');
    second.client.composer('thread-main').updateDraft('second app');
    final projectId = first.client.selection.state.selectedProjectId!;
    first.client.startDraft.updateDraft(projectId, 'first start draft');

    expect(
      first.client.session('thread-main'),
      isNot(same(second.client.session('thread-main'))),
    );
    expect(
      firstTransport.timelines.single,
      isNot(same(secondTransport.timelines.single)),
    );
    expect(first.timeline, isNot(same(second.timeline)));
    expect(second.client.startDraft.state.forProject(projectId).text, isEmpty);
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
    expect(firstTransport.timelines.single.joined.isCompleted, isTrue);
    expect(secondTransport.timelines.single.requestCloseCalls, 0);
    expect(second.client.isClosed, isFalse);
    expect(
      second.client.session('thread-main').timeline.lastDeliveredFrame,
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
      final firstOpen = Completer<RecordingTimelineConnection>();
      final releaseFirst = Completer<void>();
      var mainOpens = 0;
      final connections = <RecordingTimelineConnection>[];
      transport.timelineFactory = (threadId, inner) async {
        final window = RecordingTimelineConnection(
          threadId: threadId,
          inner: inner,
        );
        connections.add(window);
        if (threadId == 'thread-main' && ++mainOpens == 1) {
          firstOpen.complete(window);
          await releaseFirst.future;
        }
        return window;
      };
      final graph = AppGraph(
        transport: transport,
        clientId: 'late-demo-attempt',
      );
      addTearDown(() async {
        if (!releaseFirst.isCompleted) releaseFirst.complete();
        await graph.close(deadline: _deadline());
      });
      await graph.client.bootstrap();
      await graph.client.directoryCommands.selectThread('thread-main');
      final late = await firstOpen.future;
      await graph.client.directoryCommands.selectThread('thread-alt');
      await graph.client
          .session('thread-alt')
          .timeline
          .state
          .waitFor((state) => state.snapshot is StudioTimelineBaselineFrame);
      final selected = graph.client.session('thread-alt');
      final currentAttempt = selected.timeline.currentAttemptId?.value;
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
      expect(selected.timeline.currentAttemptId?.value, currentAttempt);
      expect(selected.timeline.lastDeliveredFrame, isNotNull);
      final display = graph.timeline.lease('thread-alt')!;
      expect(display.controller.messages, isNotEmpty);
      // This is the Client attempt contract over Demo connections, not native FRB.
    },
  );
}

ProviderContainer _container(AppGraph graph) =>
    ProviderContainer(overrides: [appGraphProvider.overrideWithValue(graph)]);

DateTime _deadline() => DateTime.now().add(const Duration(seconds: 5));
