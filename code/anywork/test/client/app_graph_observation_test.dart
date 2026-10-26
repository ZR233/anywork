import 'dart:async';

import 'package:anywork/src/app/composition/application_container.dart';
import 'package:anywork/src/features/conversation/state/editor_keys.dart';
import 'package:anywork/src/features/conversation/view_models/composer_view_model.dart';
import 'package:anywork/src/features/conversation/view_models/thread_context_view_model.dart';
import 'package:anywork/src/features/conversation/view_models/thread_status_view_model.dart';
import 'package:anywork/src/features/settings/skills/view_models/skills_view_model.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/timeline_transport.dart';
import 'support/application_environment.dart';
import 'support/recording_demo_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('observing missing resources never admits an application owner', () async {
    final environment = ApplicationTestEnvironment()..installHost();
    addTearDown(environment.close);
    final graph = environment.graph;
    final readModels = graph.budget.used(ResourceKind.readModel);
    final drafts = graph.budget.used(ResourceKind.draft);
    final observers = graph.budget.used(ResourceKind.observer);
    final container = createApplicationContainer(graph);
    final session = container.listen(
      threadStatusViewModelProvider('unselected-thread'),
      (_, _) {},
    );
    final composer = container.listen(
      composerViewModelProvider(
        const ComposerKey.thread(threadId: 'unselected-thread'),
      ),
      (_, _) {},
    );
    final skills = container.listen(
      skillsViewModelProvider('unselected-project'),
      (_, _) {},
    );
    final costs = container.listen(
      threadContextViewModelProvider('unselected-thread'),
      (_, _) {},
    );
    try {
      await container.pump();
      expect(graph.conversation.existingSession('unselected-thread'), isNull);
      expect(
        graph.budget.used(ResourceKind.draft),
        drafts,
        reason: 'a missing composer cannot admit a Drafts owner',
      );
      expect(
        environment.skillsPort.openedProjects,
        isEmpty,
        reason:
            'hidden, unselected Skills observation cannot open a native feed',
      );
      expect(costs.read().requireValue.source, isNull);
      expect(session.read().requireValue.execution?.value, isNull);
      expect(session.read().requireValue.execution, isNull);
      expect(
        composer.read().error,
        isA<StudioFailure>().having(
          (error) => error.code,
          'code',
          StudioFailureCode.unavailable,
        ),
      );
      expect(
        skills.read().value?.source.projection.sync.phase ==
            ResourceSyncPhase.ready,
        isFalse,
      );
      expect(costs.read().requireValue.header, isNull);
      expect(graph.budget.used(ResourceKind.readModel), readModels);
      expect(graph.budget.used(ResourceKind.draft), drafts);
      // The generated VMs observe 3 status facets, the composer active source,
      // and 2 Context sources. The retired store->store bridges no longer exist.
      expect(graph.budget.used(ResourceKind.observer), observers + 6);
      expect(environment.domains.conversationPort.facets.execution, isEmpty);
      expect(environment.domains.timeline.requests, isEmpty);
    } finally {
      session.close();
      composer.close();
      skills.close();
      costs.close();
      await container.pump();
      container.dispose();
    }
    expect(graph.budget.used(ResourceKind.observer), observers);
  });

  test(
    'account cancellation, disposal and rebuilding preserve app resources',
    () async {
      final environment = await _openApplication();
      addTearDown(environment.close);
      final graph = environment.graph;
      final domains = environment.domains;
      final connection = await _select(environment, 'thread-main');
      final session = graph.conversation.existingSession('thread-main')!;
      await connection.nextEntered.future;
      final attemptId = session.timeline.state.value.attemptId;
      const projectId = 'project';
      final startOwner = graph.drafts.start(projectId);
      final composerOwner = graph.drafts.composer('thread-main');
      // Skills/costs are domain read demands now, not eagerly admitted Client
      // owners. Opening a Session alone must not create unrelated native reads.
      expect(environment.skillsPort.openedProjects, isEmpty);
      expect(session.context.value, isNotNull);
      final observerBudgetBefore = graph.budget.used(ResourceKind.observer);
      final first = createApplicationContainer(graph);
      final sessionObserver = first.listen(
        threadStatusViewModelProvider('thread-main'),
        (_, _) {},
      );
      final startObserver = first.listen(
        composerViewModelProvider(
          const ComposerKey.start(projectId: projectId),
        ),
        (_, _) {},
      );
      final composerObserver = first.listen(
        composerViewModelProvider(
          const ComposerKey.thread(threadId: 'thread-main'),
        ),
        (_, _) {},
      );
      final timelineObserver = graph.timeline.changes.listen((_) {});
      await first.pump();
      startOwner.setText('new session survives Settings');
      composerOwner.setText('existing session survives observation disposal');

      sessionObserver.close();
      startObserver.close();
      composerObserver.close();
      await timelineObserver.cancel();
      await first.pump();
      first.dispose();
      expect(
        graph.budget.used(ResourceKind.observer),
        observerBudgetBefore,
        reason:
            'a disposed ProviderScope must release all its observer permits',
      );
      expect(connection.requestCloseCalls, 0);
      expect(connection.closeCalls, 0);
      expect(session.timeline.state.value.attemptId, attemptId);
      expect(session.timeline.state.value.lastStamp, isNotNull);
      expect(graph.drafts.start(projectId), same(startOwner));
      expect(graph.drafts.composer('thread-main'), same(composerOwner));
      expect(startOwner.state.value.text, 'new session survives Settings');
      expect(
        composerOwner.state.value.text,
        'existing session survives observation disposal',
      );

      final rebuilt = createApplicationContainer(graph);
      final rebuiltSession = rebuilt.listen(
        threadStatusViewModelProvider('thread-main'),
        (_, _) {},
      );
      final rebuiltStart = rebuilt.listen(
        composerViewModelProvider(
          const ComposerKey.start(projectId: projectId),
        ),
        (_, _) {},
      );
      final rebuiltComposer = rebuilt.listen(
        composerViewModelProvider(
          const ComposerKey.thread(threadId: 'thread-main'),
        ),
        (_, _) {},
      );
      await rebuilt.pump();
      expect(
        graph.conversation
            .existingSession('thread-main')!
            .timeline
            .state
            .value
            .attemptId,
        attemptId,
      );
      expect(
        rebuiltStart.read().requireValue.startDraft!.text,
        'new session survives Settings',
      );
      expect(
        rebuiltComposer.read().requireValue.draft!.text,
        'existing session survives observation disposal',
      );
      expect(domains.timeline.requests, hasLength(1));
      expect(connection.initialCalls, 1);
      rebuiltSession.close();
      rebuiltStart.close();
      rebuiltComposer.close();
      await rebuilt.pump();
      rebuilt.dispose();
      final report = await graph.exitCoordinator.exit(ExitIntent.exit);
      expect(report.shutdown.issues, isEmpty);
      expect(connection.requestCloseCalls, greaterThanOrEqualTo(1));
      expect(connection.closeCalls, 1);
      expect(connection.joined.isCompleted, isTrue);
    },
  );

  test('two injected AppGraphs have independent sessions and drafts', () async {
    final first = await _openApplication();
    final second = await _openApplication();
    addTearDown(first.close);
    addTearDown(second.close);
    final firstConnection = await _select(first, 'thread-main');
    final secondConnection = await _select(second, 'thread-main');
    final firstContainer = createApplicationContainer(first.graph);
    final secondContainer = createApplicationContainer(second.graph);
    addTearDown(firstContainer.dispose);
    addTearDown(secondContainer.dispose);
    const target = ComposerKey.thread(threadId: 'thread-main');
    final firstObserver = firstContainer.listen(
      composerViewModelProvider(target),
      (_, _) {},
    );
    final secondObserver = secondContainer.listen(
      composerViewModelProvider(target),
      (_, _) {},
    );
    addTearDown(firstObserver.close);
    addTearDown(secondObserver.close);
    first.graph.drafts.composer('thread-main').setText('first app');
    second.graph.drafts.composer('thread-main').setText('second app');
    first.graph.drafts.start('project').setText('first start draft');
    await Future.wait([firstContainer.pump(), secondContainer.pump()]);
    expect(
      first.graph.conversation.existingSession('thread-main'),
      isNot(same(second.graph.conversation.existingSession('thread-main'))),
    );
    expect(firstConnection, isNot(same(secondConnection)));
    expect(first.graph.timeline, isNot(same(second.graph.timeline)));
    expect(second.graph.drafts.start('project').state.value.text, isEmpty);
    expect(firstObserver.read().requireValue.draft!.text, 'first app');
    expect(secondObserver.read().requireValue.draft!.text, 'second app');
    expect(
      (await first.graph.exitCoordinator.exit(ExitIntent.exit))
          .shutdown
          .outcome,
      ShutdownOutcome.clean,
    );
    expect(firstConnection.joined.isCompleted, isTrue);
    expect(secondConnection.requestCloseCalls, 0);
    expect(second.graph.workspace.state.value.sealed, isFalse);
    expect(
      second.graph.conversation
          .existingSession('thread-main')!
          .timeline
          .state
          .value
          .lastStamp,
      isNotNull,
    );
    expect(secondObserver.read().requireValue.draft!.text, 'second app');
  });

  test(
    'late open after selecting B is reclaimed without clearing current B',
    () async {
      final environment = await _openApplication();
      addTearDown(environment.close);
      final domains = environment.domains;
      await domains.selectThread('thread-main', bind: false);
      final pending = await domains.timeline.opened(0);
      final late = RecordingTimelineConnection(
        threadId: 'thread-main',
        inner: TestTimelineConnection(
          initial: baseline(
            1,
            items: [timelineItem(1, threadId: 'thread-main')],
          ),
        ),
      );
      final current = await _select(environment, 'thread-alt');
      final selected = environment.graph.conversation.existingSession(
        'thread-alt',
      )!;
      final currentAttempt = selected.timeline.state.value.attemptId;
      expect(current, isNot(same(late)));
      pending.result.complete(late);
      await late.joined.future;
      expect(
        late.wasSubscribed,
        isFalse,
        reason: 'retired open never becomes a baseline',
      );
      expect(late.requestCloseCalls, greaterThanOrEqualTo(1));
      expect(late.closeCalls, 1);
      expect(current.requestCloseCalls, 0);
      expect(selected.timeline.state.value.attemptId, currentAttempt);
      expect(selected.timeline.state.value.lastStamp, isNotNull);
      final display = environment.graph.timeline.display('thread-alt')!;
      expect(display.canvas.chatController.messages, isNotEmpty);
    },
  );
}

Future<ApplicationTestEnvironment> _openApplication() async {
  final environment = ApplicationTestEnvironment()..installHost();
  await environment.domains.establish(catalog: false);
  await environment.graph.bootstrap.start();
  return environment;
}

Future<RecordingTimelineConnection> _select(
  ApplicationTestEnvironment environment,
  String id,
) async {
  final domains = environment.domains;
  final index = domains.timeline.requests.length;
  await domains.selectThread(id, bind: false);
  final opening = await domains.timeline.opened(index);
  final connection = RecordingTimelineConnection(
    threadId: id,
    inner: TestTimelineConnection(
      initial: baseline(1, items: [timelineItem(1, threadId: id)]),
    ),
  );
  opening.result.complete(connection);
  await environment.graph.conversation.existingSession(id)!.timeline.ready;
  await waitLatestTimeline(
    environment,
    () => environment.graph.timeline.value?.ready == true,
  );
  return connection;
}

Future<void> waitLatestTimeline(
  ApplicationTestEnvironment environment,
  bool Function() matches,
) async {
  if (matches()) return;
  final ready = Completer<void>();
  final watch = environment.graph.timeline.changes.listen((_) {
    if (!ready.isCompleted && matches()) ready.complete();
  });
  try {
    if (!matches()) await ready.future;
  } finally {
    await watch.cancel();
  }
}
