import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/timeline_transport.dart';

const _demand = ReadDemand(maxItems: 20, maxBytes: 65536);

ThreadWorkspace _workspace({int revision = 1}) =>
    emptyCurrentWorkspace('thread').copyWith(revision: revision);

ThreadModelRouteView _route(int revision) => ThreadModelRouteView(
  accountId: 'account',
  modelId: 'model',
  effort: 'medium',
  revision: revision,
  available: true,
);

ThreadRuntimeView _runtime(int completionTokens) => ThreadRuntimeView(
  modelId: 'model',
  contextTokens: 1,
  contextWindow: 100000,
  totalTokens: completionTokens + 1,
  completionTokens: completionTokens,
  inferenceCount: 1,
  costLabel: '',
  activeSkills: const [],
  activeMcpServers: const [],
  activeLspServers: const [],
);

ThreadNotificationFrame _runtimeUpdate(
  int revision, {
  required ThreadRuntimeView runtime,
  ThreadModelRouteView? modelRoute,
  int epoch = 7,
}) => ThreadNotificationFrame(
  threadId: 'thread',
  revision: revision,
  baseRevision: revision - 1,
  epoch: epoch,
  update: ThreadRuntimeUpdate(
    runtime: runtime,
    todo: null,
    modelRoute: modelRoute,
  ),
);

void main() {
  test(
    'model route follows Current and an old epoch cannot resurrect it',
    () async {
      final fixture = ConversationFixture();
      addTearDown(fixture.close);
      final current = await fixture.open(demand: _demand);
      final session = fixture.session();
      await current.deliver(
        ResetCurrentFrame(
          currentViewForWorkspace(
            _workspace().copyWith(revision: 1, modelRoute: _route(4)),
          ),
        ),
      );
      expect(session.state.modelRoute, _route(4));

      await current.deliver(
        NotificationCurrentFrame(
          revision: const CurrentRevision(ownerId: 'owner', revision: 2),
          notification: _runtimeUpdate(
            2,
            runtime: _runtime(1),
            modelRoute: _route(5),
          ),
        ),
      );
      expect(session.state.modelRoute, _route(5));

      await current.deliver(
        NotificationCurrentFrame(
          revision: const CurrentRevision(ownerId: 'owner', revision: 3),
          notification: _runtimeUpdate(
            3,
            runtime: _runtime(2),
            modelRoute: null,
          ),
        ),
      );
      expect(session.state.modelRoute, isNull);

      current.send(
        NotificationCurrentFrame(
          revision: const CurrentRevision(ownerId: 'owner', revision: 3),
          notification: _runtimeUpdate(
            3,
            runtime: _runtime(99),
            modelRoute: _route(99),
            epoch: 6,
          ),
        ),
      );
      await current.requestCloseStarted.future;
      await current.closeCompleted.future;
      expect(session.state.modelRoute, isNull);
      expect(session.state.runtime!.completionTokens, 2);
    },
  );

  test('Current break admits a lower replacement baseline', () async {
    final fixture = ConversationFixture();
    addTearDown(fixture.close);
    var current = await fixture.open(demand: _demand);
    final session = fixture.session();
    await current.deliver(
      ResetCurrentFrame(currentViewForWorkspace(_workspace(revision: 4))),
    );
    current.sendError(ConversationContinuityError('current broke'));
    await current.closeCompleted.future;
    expect(session.state.sync.phase, DomainSyncPhase.reconnecting);

    await fixture.transport.currentOpened(1);
    current = fixture.currentReader();
    await current.deliver(
      ResetCurrentFrame(currentViewForWorkspace(_workspace(revision: 2))),
    );
    expect(session.state.revision, 2, reason: '新订阅代次允许状态水位回退');
    expect(session.state.sync.phase, DomainSyncPhase.ready);
  });

  test(
    'late old Current reader cannot mutate the replacement generation',
    () async {
      final fixture = ConversationFixture();
      addTearDown(fixture.close);
      final old = await fixture.open(demand: _demand);
      await old.deliver(
        ResetCurrentFrame(currentViewForWorkspace(_workspace(revision: 1))),
      );
      old.sendError(ConversationContinuityError('old current broke'));
      await old.requestCloseStarted.future;

      await fixture.transport.currentOpened(1);
      final replacement = fixture.currentReader();
      await replacement.deliver(
        ResetCurrentFrame(currentViewForWorkspace(_workspace(revision: 2))),
      );
      old.send(
        NotificationCurrentFrame(
          revision: const CurrentRevision(ownerId: 'owner', revision: 99),
          notification: _runtimeUpdate(99, runtime: _runtime(99)),
        ),
      );
      expect(fixture.session().state.revision, 2);
    },
  );

  test('a late Current open is closed by its original owner', () async {
    final fixture = ConversationFixture();
    addTearDown(fixture.close);
    fixture.transport.currentReaderFactory = null;
    fixture.repository.setVisibleThread('thread');
    await fixture.transport.currentOpened(0);
    fixture.repository.setVisibleThread(null);
    final late = TestCurrentReader();
    fixture.transport.currentOpens.single.result.complete(late);
    await late.closeCompleted.future;
    expect(late.requestCloseCalls, greaterThan(0));
    expect(late.closeCalls, 1);
    expect(fixture.transport.currentOpens, hasLength(1));
  });

  test(
    'visibility retirement closes the Current owner without leftovers',
    () async {
      final fixture = ConversationFixture();
      addTearDown(fixture.close);
      final current = await fixture.open(demand: _demand);
      final session = fixture.session();
      await current.deliver(
        ResetCurrentFrame(currentViewForWorkspace(_workspace(revision: 3))),
      );
      fixture.repository.setVisibleThread(null);
      await current.closeCompleted.future;
      expect(session.isActive, isFalse);
      expect(current.closeCalls, 1);
      final report = await fixture.close();
      expect(report.complete, isTrue);
      expect(report.unresolved, isEmpty);
    },
  );

  test('the retired agent role has one trimmed judgement', () {
    expect(isRetiredAgentRole('planner'), isTrue);
    expect(isRetiredAgentRole(' planner '), isTrue);
    expect(isRetiredAgentRole('executor'), isFalse);
    expect(isRetiredAgentRole(''), isFalse);
    StudioThread agent({
      String role = 'planner',
      String? parentThreadId = 'root',
    }) => StudioThread(
      id: 'member',
      workspaceId: 'project',
      title: 'Member',
      mode: ThreadModeId.simple,
      delegationMode: DelegationMode.profile,
      delegationPreference: DelegationPreference.balanced,
      parentThreadId: parentThreadId,
      rootThreadId: 'root',
      agentPath: 'root/member',
      role: role,
      updatedAt: DateTime.utc(2026),
      workspacePath: '/tmp/member',
    );
    expect(agent().isRetiredAgent, isTrue);
    expect(agent(role: ' planner ').isRetiredAgent, isTrue);
    expect(agent(role: 'executor').isRetiredAgent, isFalse);
    expect(agent(parentThreadId: null).isRetiredAgent, isFalse);
  });
}
