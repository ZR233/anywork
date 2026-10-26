import 'support/test_statistics_feed.dart';
import 'support/unused_account_ports.dart';

import 'package:anywork_client/accounts_ports.dart';
import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/model_directory.dart';
import 'package:anywork_client/account_usage.dart';

import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/domain/models/agent_workspace_view.dart';
import 'package:anywork/src/domain/models/plan_confirmation_ownership.dart';
import 'package:anywork/src/features/interaction/composer_view.dart';
import 'package:anywork/src/features/shell/shell_view.dart';
import 'package:anywork/src/features/status/status_view.dart';
import 'package:anywork/src/shared/studio_driver_projection.dart';
import 'package:anywork/src/shared/studio_driver_state.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_demo_transport.dart';

final class _UnusedTransport extends UnusedAccountPorts
    implements StudioTransport {
  var calls = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    throw UnsupportedError(
      'Driver query attempted transport: ${invocation.memberName}',
    );
  }
}

final class _ColdDirectoryTransport extends _UnusedTransport {
  // Restoring navigation may observe product topics, but must not open a child.
  @override
  Stream<ProductTopicFrame> subscribeProductTopic(ProductTopic topic) =>
      const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('canonical cold and closed members survive a root-only Thread page and cold selection', () async {
    final transport = _ColdDirectoryTransport();
    final graph = AppGraph(
      statisticsFeed: const TestStatisticsFeedPort(),
      transport: transport,
      clientId: 'canonical-agent-members',
    );
    addTearDown(
      () =>
          graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
    );
    final client = graph.client;
    final root = _factsThread();
    final other = StudioThread(
      id: 'other-root',
      projectId: 'other-project',
      title: 'Other project',
      mode: ThreadModeId.simple,
      delegationMode: DelegationMode.profile,
      delegationPreference: DelegationPreference.balanced,
      workspacePath: '/other',
      updatedAt: root.updatedAt,
    );
    StudioAgentView agent(
      String id, {
      String? rootId,
      String? parent,
      StudioAgentState state = const IdleStudioAgent(),
      int depth = 0,
    }) => StudioAgentView(
      id: id,
      threadId: id,
      path: 'path-$id',
      parentPath: parent,
      rootThreadId: rootId,
      depth: depth,
      role: parent == null ? 'planner' : 'reviewer',
      task: 'Task $id',
      state: state,
      updatedAt: root.updatedAt,
      delegationMode: DelegationMode.automatic,
      delegationPreference: DelegationPreference.economy,
      frozenModel: parent == null
          ? null
          : const NewThreadModelRoute(
              accountId: 'saved-account',
              modelId: 'saved-model',
              effort: 'high',
            ),
    );
    final members = [
      agent(root.id, rootId: root.id),
      agent(
        'cold-executor',
        rootId: root.id,
        parent: 'path-${root.id}',
        depth: 1,
        state: const RunningStudioAgent('executor-turn'),
      ),
      agent(
        'cold-closed',
        rootId: root.id,
        parent: 'path-${root.id}',
        depth: 1,
        state: const ClosedStudioAgent(),
      ),
      // The exact parent link resolves this member, not a parsed path prefix.
      agent(
        'nested',
        parent: 'path-cold-closed',
        depth: 2,
        state: const RunningStudioAgent('nested-turn'),
      ),
      agent(
        'faulted',
        rootId: root.id,
        parent: 'path-${root.id}',
        depth: 1,
        state: const FaultedStudioAgent(
          failure: AgentStateError(
            code: 'saved-failure',
            message: 'Saved failure',
            retryable: false,
          ),
        ),
      ),
      agent(
        'cold-closed',
        rootId: root.id,
        parent: 'path-${root.id}',
        depth: 1,
        state: const ClosedStudioAgent(),
      ),
      agent(other.id, rootId: other.id),
      agent(
        'other-child',
        rootId: other.id,
        parent: 'path-${other.id}',
        depth: 1,
      ),
    ];
    client.project.applyProjectDirectory(
      ProjectDirectoryState(
        revision: 1,
        values: const [
          StudioProject(id: 'project', name: 'Project', path: '/project'),
          StudioProject(id: 'other-project', name: 'Other', path: '/other'),
        ],
      ),
    );
    client.project.applyAgentDirectory(
      AgentDirectoryState(revision: 1, values: members),
    );
    client.threadDirectory.applyWindow(
      ThreadDirectoryWindow(threads: [root, other], revision: 1),
    );
    client.selection.restoreStartup(
      projectId: root.projectId,
      threadId: root.id,
      needsOpen: true,
    );
    final container = ProviderContainer(
      overrides: [appGraphProvider.overrideWithValue(graph)],
    );
    addTearDown(container.dispose);
    final header = container.listen(headerViewProvider, (_, _) {});
    final sidebar = container.listen(sidebarViewProvider, (_, _) {});
    addTearDown(sidebar.close);
    expect(header.read().agents.map((a) => a.threadId), [
      root.id,
      'cold-executor',
      'cold-closed',
      'nested',
      'faulted',
    ]);
    expect(header.read().workspaceThreads.map((thread) => thread.id), [
      root.id,
    ], reason: 'Member enumeration never fabricates missing Thread metadata');
    expect(header.read().agents.first.frozenModel, isNull);
    expect(header.read().agents[1].frozenModel?.modelId, 'saved-model');
    expect(
      AgentDirectoryQueries.menuOrder(header.read().agents)
          .map((a) => a.threadId),
      ['cold-executor', 'nested', 'faulted', root.id, 'cold-closed'],
      reason: 'Status grouping keeps stable canonical order inside each group',
    );
    final timeline = graph.timeline;
    expect(
      queryStudioDriverFacts(
        client,
        accountsRepository: graph.accounts,
        modelsRepository: graph.models,
        usageRepository: graph.accountUsage,
        acpService: graph.acp,
        timeline: timeline,
      ).workspace?.agents.map((a) => a.threadId),
      [root.id, 'cold-executor', 'cold-closed', 'nested', 'faulted'],
    );
    client.selection.restoreStartup(
      projectId: root.projectId,
      threadId: 'cold-closed',
      needsOpen: true,
    );
    expect(
      header.read().selectedRootThread?.id,
      root.id,
      reason: 'Typed agent root identity is sufficient even before child Thread metadata arrives',
    );
    expect(header.read().selectedThreadId, 'cold-closed');
    expect(sidebar.read().selectedRootThreadId, root.id);
    expect(header.read().agents.map((a) => a.threadId), [
      root.id,
      'cold-executor',
      'cold-closed',
      'nested',
      'faulted',
    ]);
    expect(client.sessionStates, isEmpty);
    expect(
      transport.calls,
      0,
      reason:
          'Enumeration and cold navigation restore cannot load child sessions',
    );
    client.selection.restoreStartup(
      projectId: other.projectId,
      threadId: other.id,
      needsOpen: true,
    );
    expect(header.read().agents.map((a) => a.threadId), [
      other.id,
      'other-child',
    ]);
    client.selection.restoreStartup(
      projectId: root.projectId,
      threadId: 'cold-closed',
      needsOpen: true,
    );
    client.threadDirectory.applyDelta(
      revision: 2,
      upserted: const [],
      removed: [root.id],
    );
    expect(header.read().selectedRootThread, isNull);
    expect(header.read().workspaceThreads, isEmpty);
    expect(header.read().agents.map((a) => a.threadId), [
      root.id,
      'cold-executor',
      'cold-closed',
      'nested',
      'faulted',
    ], reason: 'Even root metadata availability is not a membership condition');
    expect(sidebar.read().selectedRootThreadId, root.id);
    expect(client.sessionStates, isEmpty);
    expect(transport.calls, 0);
    header.close();
  });

  test(
    'canonical saved agent routes retain selection without activating children',
    () async {
      final transport = _ColdDirectoryTransport();
      final graph = AppGraph(
        transport: transport,
        statisticsFeed: const TestStatisticsFeedPort(),
        clientId: 'cold-frozen',
      );
      final client = graph.client;
      addTearDown(
        () => graph.close(
          deadline: DateTime.now().add(const Duration(seconds: 5)),
        ),
      );
      const frozen = NewThreadModelRoute(
        accountId: 'account-b',
        modelId: 'shared',
        effort: 'high',
      );
      final root = _factsThread();
      final child = StudioThread(
        id: 'child',
        projectId: 'project',
        title: 'Review final changes',
        mode: ThreadModeId.task,
        delegationMode: DelegationMode.automatic,
        delegationPreference: DelegationPreference.economy,
        frozenModel: frozen,
        parentThreadId: root.id,
        rootThreadId: root.id,
        role: 'reviewer',
        workspacePath: '/project',
        updatedAt: DateTime.utc(2026),
      );
      client.threadDirectory.applyWindow(
        ThreadDirectoryWindow(threads: [root, child], revision: 1),
      );
      StudioAgentView saved(StudioAgentState state) => StudioAgentView(
        id: child.id,
        threadId: child.id,
        path: child.id,
        parentPath: root.id,
        rootThreadId: root.id,
        role: child.role,
        task: child.title,
        depth: 1,
        delegationMode: child.delegationMode,
        delegationPreference: child.delegationPreference,
        frozenModel: frozen,
        state: state,
        updatedAt: child.updatedAt,
      );
      final savedRoot = StudioAgentView(
        id: root.id,
        threadId: root.id,
        path: root.id,
        rootThreadId: root.id,
        role: root.role,
        task: root.title,
        delegationMode: root.delegationMode,
        delegationPreference: root.delegationPreference,
        state: const IdleStudioAgent(),
        updatedAt: root.updatedAt,
      );
      client.project.applyAgentDirectory(
        AgentDirectoryState(
          revision: 1,
          values: [savedRoot, saved(const IdleStudioAgent())],
        ),
      );
      client.selection.restoreStartup(
        projectId: 'project',
        threadId: child.id,
        needsOpen: true,
      );
      final timeline = graph.timeline;
      final facts = queryStudioDriverFacts(
        client,
        accountsRepository: graph.accounts,
        modelsRepository: graph.models,
        usageRepository: graph.accountUsage,
        acpService: graph.acp,
        timeline: timeline,
      );
      expect(
        facts.workspace?.agents
            .where((a) => a.threadId == child.id)
            .single
            .frozenModel,
        frozen,
      );
      expect(client.existingSession(child.id), isNull);
      final cold = AgentDirectoryQueries.forRoot(
        rootThreadId: root.id,
        agents: [saved(const IdleStudioAgent())],
      ).single;
      final active = StudioAgentView(
        id: child.id,
        threadId: child.id,
        path: child.id,
        parentPath: root.id,
        rootThreadId: root.id,
        depth: 1,
        role: child.role,
        task: child.title,
        delegationMode: child.delegationMode,
        delegationPreference: child.delegationPreference,
        frozenModel: frozen,
        state: const RunningStudioAgent('turn'),
        updatedAt: child.updatedAt,
      );
      expect(
        AgentDirectoryQueries.forRoot(
          rootThreadId: root.id,
          agents: [active],
          threads: [child],
        ).single.frozenModel,
        frozen,
      );
      final closed = AgentDirectoryQueries.forRoot(
        rootThreadId: root.id,
        agents: [saved(const ClosedStudioAgent())],
      ).single;
      expect(cold.frozenModel, frozen);
      expect(closed.frozenModel, frozen);
      expect(closed.delegationPreference, DelegationPreference.economy);
      expect(client.selection.state.selectedThreadId, child.id);
      expect(
        transport.calls,
        0,
        reason: 'Fallback/Driver reads cannot fetch or activate a cold child',
      );
      expect(
        AgentDirectoryQueries.forRoot(
          rootThreadId: root.id,
          agents: [savedRoot],
        ).single.frozenModel,
        isNull,
        reason: 'No saved model remains genuinely unknown, never filled from a current Profile',
      );
    },
  );

  test('workspace and Driver join current directory identity after a Turn', () async {
    final graph = AppGraph(
      statisticsFeed: const TestStatisticsFeedPort(),
      transport: RecordingDemoTransport(),
      clientId: 'directory-identity',
    );
    addTearDown(
      () =>
          graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
    );
    final client = graph.client;
    await client.bootstrap();
    await client.directoryCommands.selectThread('thread-main');
    final session = client.existingSession('thread-main')!;
    await session.timeline.state.waitFor(
      (state) => state.snapshot is StudioTimelineBaselineFrame,
    );
    final initial = session.state.workspace!;
    // A runtime baseline may predate the directory's terminal/title/mode frame.
    session.applySnapshot(
      initial.copyWith(
        thread: initial.thread.copyWith(status: ThreadStatusView.running),
      ),
    );
    final container = ProviderContainer(
      overrides: [appGraphProvider.overrideWithValue(graph)],
    );
    addTearDown(container.dispose);
    final workspace = container.listen(
      shellComposerWorkspaceProvider,
      (_, _) {},
    );
    final status = container.listen(
      statusBarViewProvider('thread-main'),
      (_, _) {},
    );
    final composer = container.listen(
      composerDockViewProvider('thread-main'),
      (_, _) {},
    );
    addTearDown(workspace.close);
    addTearDown(status.close);
    addTearDown(composer.close);
    final canonical = initial.thread.copyWith(
      title: 'Completed canonical title',
      mode: ThreadModeId.task,
      status: ThreadStatusView.idle,
      updatedAt: initial.thread.updatedAt,
    );
    client.threadDirectory.applyDelta(
      revision: client.threadDirectory.state.revision + 1,
      upserted: [canonical],
      removed: const [],
    );
    // The directory frame can arrive before an already captured runtime
    // baseline. Unix-second timestamps cannot order these resource domains.
    session.applySnapshot(
      initial.copyWith(
        thread: initial.thread.copyWith(status: ThreadStatusView.running),
      ),
    );
    expect(client.findThread('thread-main'), same(canonical));
    final timeline = graph.timeline;
    final facts = queryStudioDriverFacts(
      client,
      accountsRepository: graph.accounts,
      modelsRepository: graph.models,
      usageRepository: graph.accountUsage,
      acpService: graph.acp,
      timeline: timeline,
    );
    final json =
        jsonDecode(StudioDriverState.snapshotJson(observed: facts)) as Map;
    expect((json['workspace'] as Map)['threadStatus'], 'idle');
    // 展示事实来自当前展示代次的真实消息集合，不从状态流猜测。
    expect(facts.timeline, isNotNull);
    expect(facts.timeline!.threadId, 'thread-main');
    expect(
      (json['timeline'] as Map)['itemCount'],
      facts.timeline!.items.length,
    );
    // 只读滚动几何：诊断请求现场读取，本测试没有挂载 Timeline 子树，因此几何是
    // nullable 空值而不是猜数或上一代快照。
    expect(facts.timeline!.ready, isTrue);
    expect(facts.timelineScroll, isNotNull);
    expect(facts.timelineScroll!.threadId, 'thread-main');
    expect(facts.timelineScroll!.generation, facts.timeline!.generation);
    expect(facts.timelineScroll!.pixels, isNull);
    expect(facts.timelineScroll!.maxScrollExtent, isNull);
    expect(facts.timelineScroll!.atLiveEdge, isFalse);
    expect(facts.timelineScroll!.isScrolling, isFalse);
    expect((json['timelineScroll'] as Map)['isScrolling'], isFalse);
    final generation = facts.timeline!.generation;
    await timeline.returnToLive('thread-main');
    final switched = queryStudioDriverFacts(
      client,
      accountsRepository: graph.accounts,
      modelsRepository: graph.models,
      usageRepository: graph.accountUsage,
      acpService: graph.acp,
      timeline: timeline,
    );
    expect(switched.timeline!.generation, greaterThan(generation));
    expect(switched.timeline!.threadId, 'thread-main');
    // 切代次后诊断仍读当前 lease 的真实身份，不残留上一代几何。
    expect(switched.timelineScroll, isNotNull);
    expect(switched.timelineScroll!.generation, switched.timeline!.generation);
    expect(switched.timelineScroll!.threadId, 'thread-main');
    expect(facts.workspace!.thread, same(canonical));
    expect(workspace.read()!.thread, same(canonical));
    expect(status.read()!.thread, same(canonical));
    expect(composer.read().thread, same(canonical));
  });

  test(
    'Driver reads current Client facts without creating any owner or lease',
    () async {
      final transport = _UnusedTransport();
      final graph = AppGraph(
        statisticsFeed: const TestStatisticsFeedPort(),
        transport: transport,
        clientId: 'driver-query',
      );
      final client = graph.client;
      addTearDown(
        () => graph.close(
          deadline: DateTime.now().add(const Duration(seconds: 5)),
        ),
      );
      final thread = StudioThread(
        id: 'thread',
        projectId: 'project',
        title: 'Original title',
        mode: ThreadModeId.simple,
        delegationMode: DelegationMode.profile,
        delegationPreference: DelegationPreference.balanced,
        updatedAt: DateTime.utc(2026),
        workspacePath: '/tmp/thread',
      );
      client.threadDirectory.applyWindow(
        ThreadDirectoryWindow(threads: [thread], revision: 1),
      );
      final timeline = graph.timeline;
      bindStudioDriver(
        client,
        accountsRepository: graph.accounts,
        modelsRepository: graph.models,
        usageRepository: graph.accountUsage,
        acpService: graph.acp,
        timeline: timeline,
      );
      final usageBefore = client.budget.usage.length;
      final original = StudioDriverState.readFacts();
      expect(original.rootThreads.single.title, 'Original title');
      // 读诊断不建立展示 lease，也不打开会话。
      expect(original.timeline, isNull);
      expect(
        original.timelineScroll,
        isNull,
        reason: '没有展示 lease 就没有几何，也不回放上一代',
      );
      expect(timeline.lease('thread'), isNull);
      expect(client.sessionStates, isEmpty);
      expect(client.composerState('thread'), isNull);
      expect(client.ownedSkills, isEmpty);
      expect(client.ownedSessionCosts, isEmpty);
      expect(transport.calls, 0);

      client.threadDirectory.applyDelta(
        revision: 2,
        upserted: [thread.copyWith(title: 'Updated canonical title')],
        removed: const [],
      );
      final current = StudioDriverState.readFacts();
      expect(current.rootThreads.single.title, 'Updated canonical title');
      expect(original.rootThreads.single.title, 'Original title');
      expect(() => current.rootThreads.add(thread), throwsUnsupportedError);
      final json =
          jsonDecode(StudioDriverState.snapshotJson()) as Map<String, dynamic>;
      expect(json.containsKey('timelineScroll'), isTrue);
      expect(json['timelineScroll'], isNull);
      final settingsJson = json['settings'] as Map;
      expect(settingsJson.containsKey('modelCatalogRevision'), isFalse);
      final domains = settingsJson['accountDomains'] as Map;
      expect(domains['schemaVersion'], 2);
      expect(domains['templates'], {
        'loaded': false,
        'revision': null,
        'usable': null,
      });
      expect(settingsJson['nativeTemplates'], isNull);
      expect(current.accountDetails, isEmpty);
      expect((domains['usage'] as Map)['stamp'], isNull);
      final directory = json['sidebarDirectory'] as Map<String, dynamic>;
      expect(directory['titles'], {'thread': 'Updated canonical title'});
      studioDriverTopicDiagnostics(
        client,
        accountsRepository: graph.accounts,
        modelsRepository: graph.models,
        usageRepository: graph.accountUsage,
        acpService: graph.acp,
      );
      expect(client.sessionStates, isEmpty);
      expect(client.composerState('thread'), isNull);
      expect(client.budget.usage.length, usageBefore);
      expect(
        transport.calls,
        0,
        reason: 'snapshot queries never create transport demand',
      );
      expect((await client.close()).complete, isTrue);
    },
  );

  test('Driver domain snapshot keeps target clocks, unknown details and exact last-good usage', () {
    const native = NativeAccountIdentity('shared-id');
    const acp = AcpAccountIdentity('shared-id');
    const summariesStamp = ResourceStamp(
      resourceKey: 'account-summaries',
      ownerEpoch: 'owner-a',
      revision: 17,
    );
    const usageStamp = ResourceStamp(
      resourceKey: 'account-usage',
      ownerEpoch: 'owner-b',
      revision: 0,
    );
    const capabilities = AccountCapabilities(
      setDefault: true,
      edit: true,
      remove: true,
      queryUsage: true,
      syncModels: true,
      editModels: true,
      acpAuth: false,
    );
    final summaries = [
      const AccountSummary(
        identity: native,
        name: 'Native',
        isDefault: true,
        capabilities: capabilities,
      ),
      const AccountSummary(
        identity: acp,
        name: 'ACP',
        isDefault: false,
        acpConnectionRevision: 9,
        capabilities: capabilities,
      ),
    ];
    Map snapshot({
      required AccountsState accounts,
      AccountUsagePhase phase = AccountUsagePhase.querying,
    }) =>
        (jsonDecode(
              StudioDriverState.snapshotJson(
                observed: StudioDriverFacts(
                  acpAuthLoaded: false,
                  accountSummaries: accounts,
                  accounts: modelSelectionAccounts(
                    accounts,
                    ModelDirectoryState(),
                  ),
                  accountUsage: AccountResource(
                    stamp: usageStamp,
                    stale: true,
                    value: {
                      native: AccountUsageObservation(
                        identity: native,
                        queryRevision: 4,
                        revision: 2,
                        phase: phase,
                        operationId: 'query-4',
                        checkedAt: 100,
                        lastGood: AccountUsageSuccess(
                          checkedAt: 90,
                          value: AccountBalance(
                            available: true,
                            balances: const [
                              AccountMoneyBalance(
                                currency: 'CNY',
                                total: '88.000000000000000001',
                                granted: '0.00',
                                toppedUp: '88.000000000000000001',
                              ),
                              AccountMoneyBalance(
                                currency: 'USD',
                                total: '0.01',
                                granted: '0.01',
                                toppedUp: '0.00',
                              ),
                            ],
                          ),
                        ),
                      ),
                    },
                  ),
                  accountUsageQueryFailures: {
                    native: const StudioFailure(
                      code: StudioFailureCode.unavailable,
                      message: 'DO_NOT_EXPOSE_TOKEN',
                      retryable: true,
                      correlationId: 'query-transport',
                      detailsJson: 'DO_NOT_EXPOSE_DETAILS',
                    ),
                  },
                ),
              ),
            ) as Map)['settings']
            as Map;
    final settings = snapshot(
      accounts: AccountsState(stamp: summariesStamp, accounts: summaries),
    );
    final domains = settings['accountDomains'] as Map;
    expect(
      domains['summaries']['stamp'],
      studioDriverStampJson(summariesStamp),
    );
    expect(domains['usage']['stamp'], studioDriverStampJson(usageStamp));
    expect(domains['usage']['stale'], isTrue);
    expect(domains['templates'], {
      'loaded': false,
      'revision': null,
      'usable': null,
    }, reason: 'A loaded summary is not a loaded static template catalog');
    final identities = (domains['accounts'] as List).cast<Map>();
    expect(
      identities.map(
        (entry) => [entry['kind'], entry['id'], entry['acpConnectionRevision']],
      ),
      [
        ['native', 'shared-id', null],
        ['acp', 'shared-id', 9],
      ],
    );
    for (final entry in identities) {
      expect(entry['details']['loaded'], isFalse);
      expect(entry['details']['stamp'], isNull);
    }
    final nativeJson = (settings['accounts'] as List).single as Map;
    expect(nativeJson.containsKey('defaultModelId'), isFalse);
    expect(nativeJson.containsKey('status'), isFalse);
    expect(nativeJson['hasBearerToken'], isNull);
    expect(nativeJson['templateId'], isNull);
    expect(domains['usage']['queryFailures'], [
      {
        'accountId': 'shared-id',
        'code': 'unavailable',
        'retryable': true,
        'correlationId': 'query-transport',
      },
    ]);
    expect(jsonEncode(settings), isNot(contains('DO_NOT_EXPOSE')));
    for (final phase in AccountUsagePhase.values) {
      final current = snapshot(
        accounts: AccountsState(stamp: summariesStamp, accounts: summaries),
        phase: phase,
      );
      final observation =
          (current['accountDomains']['usage']['accounts'] as List).single;
      expect(
        observation['phase'],
        phase.name,
        reason: 'Transport failure never fabricates a canonical failed phase',
      );
      expect(observation['lastGood'], {
        'checkedAt': 90,
        'value': {
          'kind': 'balance',
          'available': true,
          'balances': [
            {
              'currency': 'CNY',
              'total': '88.000000000000000001',
              'granted': '0.00',
              'toppedUp': '88.000000000000000001',
            },
            {
              'currency': 'USD',
              'total': '0.01',
              'granted': '0.01',
              'toppedUp': '0.00',
            },
          ],
        },
      });
    }
    final observedEmpty = snapshot(
      accounts: AccountsState(
        accounts: summaries,
        templates: const AccountCatalogView(
          schemaVersion: 1,
          revision: 'templates-only',
          templates: [],
          modelCatalogs: {},
        ),
      ),
    );
    expect(observedEmpty['accountDomains']['summaries']['loaded'], isFalse);
    expect(observedEmpty['accountDomains']['templates'], {
      'loaded': true,
      'revision': 'templates-only',
      'usable': false,
    });
    expect(observedEmpty['nativeTemplates'], isEmpty);
  });

  test(
    'Driver facts map typed acp install failures without dynamic dispatch',
    () async {
      final transport = _UnusedTransport();
      final graph = AppGraph(
        statisticsFeed: const TestStatisticsFeedPort(),
        transport: transport,
        clientId: 'acp-install-facts',
      );
      final client = graph.client;
      addTearDown(
        () => graph.close(
          deadline: DateTime.now().add(const Duration(seconds: 5)),
        ),
      );
      addTearDown(
        () => client.close(
          deadline: DateTime.now().add(const Duration(seconds: 5)),
        ),
      );
      final timeline = graph.timeline;

      // Failed 是终态：状态层没有阶段，阶段事实由失败类别自己携带。
      _applyInstall(
        graph,
        const AcpInstallSnapshotView(
          revision: 7,
          updatedAt: 1760000000,
          installations: [
            AcpInstallEntryView(
              provider: AcpProviderView.antigravity,
              state: AcpInstallFailedState(
                operationId: 'op-failed',
                failure: AcpInstallFailureView(
                  code: AcpInstallFailureCodeView.checksumMismatch,
                  stage: AcpInstallStageView.verify,
                  message: 'checksum mismatch',
                  retryable: true,
                ),
              ),
            ),
          ],
        ),
      );
      final failed = queryStudioDriverFacts(
        client,
        accountsRepository: graph.accounts,
        modelsRepository: graph.models,
        usageRepository: graph.accountUsage,
        acpService: graph.acp,
        timeline: timeline,
      );
      final failedInstall = failed.acpInstall!;
      expect(failedInstall.loaded, isTrue);
      expect(failedInstall.revision, 7);
      final failedEntry = failedInstall.installations.single;
      expect(failedEntry.provider, 'antigravity');
      expect(failedEntry.phase, 'failed');
      expect(failedEntry.operationId, 'op-failed');
      expect(failedEntry.stage, isNull);
      // 失败类别是 typed enum：投影必须静态解析，不能靠 dynamic 调扩展成员。
      expect(failedEntry.failureCode, 'checksumMismatch');
      expect(failedEntry.failureRetryable, isTrue);

      // Closing 是收束阶段：带 cancelled 失败，阶段为 close，不能被 Ready 吞掉。
      _applyInstall(
        graph,
        const AcpInstallSnapshotView(
          revision: 8,
          updatedAt: 1760000010,
          installations: [
            AcpInstallEntryView(
              provider: AcpProviderView.antigravity,
              state: AcpInstallClosingState(
                operationId: 'op-closing',
                failure: AcpInstallFailureView(
                  code: AcpInstallFailureCodeView.cancelled,
                  stage: AcpInstallStageView.download,
                  message: 'cancelled by user',
                  retryable: true,
                ),
              ),
            ),
          ],
        ),
      );
      final closing = queryStudioDriverFacts(
        client,
        accountsRepository: graph.accounts,
        modelsRepository: graph.models,
        usageRepository: graph.accountUsage,
        acpService: graph.acp,
        timeline: timeline,
      );
      final closingInstall = closing.acpInstall!;
      expect(closingInstall.revision, 8);
      final closingEntry = closingInstall.installations.single;
      expect(closingEntry.phase, 'closing');
      expect(closingEntry.stage, 'close');
      expect(closingEntry.operationId, 'op-closing');
      expect(closingEntry.failureCode, 'cancelled');
      expect(closingEntry.failureRetryable, isTrue);

      // 序列化后再核对一次：Driver 消费的是 JSON 里的真实 failure 事实。
      final json =
          jsonDecode(StudioDriverState.snapshotJson(observed: closing)) as Map;
      final install = (json['settings'] as Map)['acpInstall'] as Map;
      expect(install['loaded'], isTrue);
      expect(install['revision'], 8);
      final entry = (install['installations'] as List).single as Map;
      expect(entry['phase'], 'closing');
      expect(entry['stage'], 'close');
      expect((entry['failure'] as Map)['code'], 'cancelled');
      expect((entry['failure'] as Map)['retryable'], isTrue);
      expect(transport.calls, 0, reason: '投影只读现有镜像，不建立业务 demand');
    },
  );

  test('timeline facts expose authoritative text channel and plan-confirmation bool', () async {
    final transport = _ScriptedTimelineTransport();
    final graph = AppGraph(
      statisticsFeed: const TestStatisticsFeedPort(),
      transport: transport,
      clientId: 'facts',
    );
    final client = graph.client;
    addTearDown(
      () =>
          graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
    );
    addTearDown(
      () => client.close(
        deadline: DateTime.now().add(const Duration(seconds: 5)),
      ),
    );
    client.selection.markOpened();
    client.threadDirectory.applyBaseline(
      ThreadDirectoryPage(threads: [_factsThread()], revision: 1),
      revision: 1,
    );
    final timeline = graph.timeline;
    client.workspace.selectThread('thread', projectId: 'project');
    await timeline.source.waitFor((state) => state?.generation != 0);

    bindStudioDriver(
      client,
      accountsRepository: graph.accounts,
      modelsRepository: graph.models,
      usageRepository: graph.accountUsage,
      acpService: graph.acp,
      timeline: timeline,
    );
    final json =
        jsonDecode(StudioDriverState.snapshotJson()) as Map<String, dynamic>;
    final items = (json['timeline'] as Map<String, dynamic>)['items'] as List;
    Map<String, dynamic> itemOf(String id) => items
        .cast<Map<String, dynamic>>()
        .firstWhere((item) => item['id'] == id);
    Map<String, dynamic>? userInputOf(String id) =>
        itemOf(id)['userInput'] as Map<String, dynamic>?;

    // 文本频道是权威判别事实：commentary 与 finalAnswer 不混，非文本为 null。
    expect(itemOf('cm')['channel'], 'commentary');
    expect(itemOf('fa')['channel'], 'finalAnswer');
    expect(itemOf('cm')['channel'], isNot(itemOf('fa')['channel']));
    expect(itemOf('tool')['channel'], isNull);
    // 两个文本条目的 kind 相同也必须靠 channel 区分，不能从 kind/文本推测。
    expect(itemOf('cm')['kind'], itemOf('fa')['kind']);

    // 普通问答：false + 无决定。
    expect(userInputOf('qa-normal')!['isPlanConfirmation'], isFalse);
    expect(userInputOf('qa-normal')!['planDecision'], isNull);
    // 待确认的计划同样是计划确认，且决定来自权威 getter。
    expect(userInputOf('qa-plan-pending')!['isPlanConfirmation'], isTrue);
    expect(userInputOf('qa-plan-pending')!['planDecision'], 'pending');
    // cancelled / approved 按权威 getter 直出。
    expect(userInputOf('qa-plan-cancelled')!['isPlanConfirmation'], isTrue);
    expect(userInputOf('qa-plan-cancelled')!['planDecision'], 'cancelled');
    expect(userInputOf('qa-plan-approved')!['isPlanConfirmation'], isTrue);
    expect(userInputOf('qa-plan-approved')!['planDecision'], 'approved');
    // 旧普通问答复用保留 ID：归属只看工具名，仍是普通问答。
    expect(userInputOf('qa-plan-legacy')!['isPlanConfirmation'], isFalse);
    expect(userInputOf('qa-plan-legacy')!['planDecision'], isNull);
    // 每个问答条目都始终输出该键（固定 schema）。
    for (final id in const [
      'qa-normal',
      'qa-plan-pending',
      'qa-plan-cancelled',
      'qa-plan-approved',
      'qa-plan-legacy',
    ]) {
      expect(userInputOf(id)!.containsKey('isPlanConfirmation'), isTrue);
      expect(userInputOf(id)!.containsKey('planDecision'), isTrue);
    }

    await timeline.close(
      deadline: DateTime.now().add(const Duration(seconds: 5)),
    );
    await client.close(
      deadline: DateTime.now().add(const Duration(seconds: 5)),
    );
  });

  test(
    'attachment facts keep canonical modality for user and tool items',
    () async {
      final transport = _ScriptedTimelineTransport(
        baseline: _attachmentBaseline,
      );
      final graph = AppGraph(
        statisticsFeed: const TestStatisticsFeedPort(),
        transport: transport,
        clientId: 'attachments',
      );
      final client = graph.client;
      addTearDown(
        () => graph.close(
          deadline: DateTime.now().add(const Duration(seconds: 5)),
        ),
      );
      addTearDown(
        () => client.close(
          deadline: DateTime.now().add(const Duration(seconds: 5)),
        ),
      );
      client.selection.markOpened();
      client.threadDirectory.applyBaseline(
        ThreadDirectoryPage(threads: [_factsThread()], revision: 1),
        revision: 1,
      );
      final timeline = graph.timeline;
      client.workspace.selectThread('thread', projectId: 'project');
      await timeline.source.waitFor((state) => state?.generation != 0);

      bindStudioDriver(
        client,
        accountsRepository: graph.accounts,
        modelsRepository: graph.models,
        usageRepository: graph.accountUsage,
        acpService: graph.acp,
        timeline: timeline,
      );
      final opensBefore = transport.opens;
      final facts = StudioDriverState.readFacts();
      expect(facts.timeline, isNotNull);
      final items = facts.timeline!.items;
      TimelineItemFacts itemOf(String id) =>
          items.firstWhere((item) => item.id == id);

      // 用户文本条目的附件：canonical enum 名、真实文件名与字节数，且不冒充工具产出。
      final userItem = itemOf('user');
      expect(userItem.tool, isNull);
      expect(userItem.attachments.map((attachment) => attachment.id), [
        'user-image',
        'user-file',
      ]);
      expect(userItem.attachments.map((attachment) => attachment.modality), [
        'image',
        'file',
      ]);
      expect(userItem.attachments.map((attachment) => attachment.filename), [
        'chart.png',
        'notes.txt',
      ]);
      expect(userItem.attachments.map((attachment) => attachment.byteSize), [
        2048,
        15,
      ]);
      expect(userItem.attachments.map((attachment) => attachment.source), [
        null,
        null,
      ]);

      // 工具条目的顶层附件行带工具来源标记；nested 工具诊断给同一批附件的原始事实。
      final toolItem = itemOf('tool-output');
      expect(toolItem.attachments.map((attachment) => attachment.id), [
        'tool-image',
        'tool-video',
      ]);
      expect(toolItem.attachments.map((attachment) => attachment.modality), [
        'image',
        'video',
      ]);
      expect(toolItem.attachments.map((attachment) => attachment.filename), [
        'shot.png',
        'clip.mp4',
      ]);
      expect(toolItem.attachments.map((attachment) => attachment.byteSize), [
        4096,
        8192,
      ]);
      expect(toolItem.attachments.map((attachment) => attachment.source), [
        'tool',
        'tool',
      ]);
      final tool = toolItem.tool!;
      expect(tool.name, 'bash');
      expect(tool.attachments.map((attachment) => attachment.id), [
        'tool-image',
        'tool-video',
      ]);
      expect(tool.attachments.map((attachment) => attachment.modality), [
        'image',
        'video',
      ]);
      expect(tool.attachments.map((attachment) => attachment.filename), [
        'shot.png',
        'clip.mp4',
      ]);
      expect(tool.attachments.map((attachment) => attachment.byteSize), [
        4096,
        8192,
      ]);
      expect(tool.attachments.map((attachment) => attachment.source), [
        null,
        null,
      ]);
      // 用户与工具附件身份不串：两侧 id 无交集。
      expect(
        toolItem.attachments
            .map((attachment) => attachment.id)
            .toSet()
            .intersection(
              userItem.attachments.map((attachment) => attachment.id).toSet(),
            ),
        isEmpty,
      );

      // 序列化诊断给同一批 canonical 值，键名保持不变。
      final json =
          jsonDecode(StudioDriverState.snapshotJson()) as Map<String, dynamic>;
      final jsonItems =
          ((json['timeline'] as Map<String, dynamic>)['items'] as List)
              .cast<Map<String, dynamic>>();
      Map<String, dynamic> jsonItemOf(String id) =>
          jsonItems.firstWhere((item) => item['id'] == id);
      expect(jsonItemOf('user')['attachments'], [
        {
          'id': 'user-image',
          'modality': 'image',
          'filename': 'chart.png',
          'byteSize': 2048,
        },
        {
          'id': 'user-file',
          'modality': 'file',
          'filename': 'notes.txt',
          'byteSize': 15,
        },
      ]);
      final jsonTool =
          jsonItemOf('tool-output')['tool'] as Map<String, dynamic>;
      expect(jsonItemOf('tool-output')['attachments'], [
        {
          'id': 'tool-image',
          'modality': 'image',
          'filename': 'shot.png',
          'byteSize': 4096,
          'source': 'tool',
        },
        {
          'id': 'tool-video',
          'modality': 'video',
          'filename': 'clip.mp4',
          'byteSize': 8192,
          'source': 'tool',
        },
      ]);
      expect(jsonTool['attachments'], [
        {
          'id': 'tool-image',
          'modality': 'image',
          'filename': 'shot.png',
          'byteSize': 4096,
        },
        {
          'id': 'tool-video',
          'modality': 'video',
          'filename': 'clip.mp4',
          'byteSize': 8192,
        },
      ]);
      final history =
          ((json['workspace'] as Map<String, dynamic>)['historyAttachments']
                  as List)
              .cast<Map<String, dynamic>>();
      expect(history.map((attachment) => attachment['id']), [
        'user-image',
        'user-file',
        'tool-image',
        'tool-video',
      ]);
      // 读诊断不制造新的内容订阅或 transport demand。
      expect(transport.opens, opensBefore);

      // 释放展示后诊断读不到上一代附件。
      await timeline.close(
        deadline: DateTime.now().add(const Duration(seconds: 5)),
      );
      expect(timeline.lease('thread'), isNull);
      final retired = StudioDriverState.readFacts();
      expect(retired.timeline, isNull);
      final retiredJson =
          jsonDecode(StudioDriverState.snapshotJson()) as Map<String, dynamic>;
      expect(retiredJson['timeline'], isNull);
      expect(
        ((retiredJson['workspace']
                    as Map<String, dynamic>)['historyAttachments']
                as List)
            .isEmpty,
        isTrue,
      );
      expect(transport.opens, opensBefore);
    },
  );

  test('workspace 模型诊断按已解析 route 的 accountId 与 modelId 选账号，不按裸 model id 猜', () {
    Map<String, dynamic> workspaceJsonFor(ThreadModelRouteView? route) {
      final json = jsonDecode(
        StudioDriverState.snapshotJson(
          observed: StudioDriverFacts(
            acpAuthLoaded: false,
            workspace: _identityWorkspace(route: route),
            accountSummaries: _identitySummaries(),
            accountDetails: _identityDetails(),
          ),
        ),
      ) as Map<String, dynamic>;
      return json['workspace'] as Map<String, dynamic>;
    }

    // 两个账号共用同一 modelId；只有 route 能说明当前模型属于哪个账号。
    final routed = workspaceJsonFor(_sharedModelRoute(accountId: 'acct-b'));
    expect(routed['modelAccount'], {
      'id': 'acct-b',
      'hasBearerToken': true,
      'credentialReady': true,
      'credentialEnv': null,
    });
    expect(routed['modelCapabilities'], ['text', 'image']);

    // 路由暂不可用仍保留身份：可用性不是身份选择依据。
    final unavailable = workspaceJsonFor(
      _sharedModelRoute(accountId: 'acct-b', available: false),
    );
    expect(
      (unavailable['modelAccount'] as Map<String, dynamic>)['id'],
      'acct-b',
    );
    expect(unavailable['modelCapabilities'], ['text', 'image']);

    // 路由缺失：保持 unknown，不按裸 model id 猜任意账号。
    final unrouted = workspaceJsonFor(null);
    expect(unrouted['modelAccount'], isNull);
    expect(unrouted['modelCapabilities'], isEmpty);

    // 未知账号：保持 unknown。
    final unknownAccount = workspaceJsonFor(
      _sharedModelRoute(accountId: 'acct-missing'),
    );
    expect(unknownAccount['modelAccount'], isNull);
    expect(unknownAccount['modelCapabilities'], isEmpty);

    // 路由指向的账号不含该模型：保持 unknown，不借用另一账号的同名模型。
    final crossAccount = workspaceJsonFor(
      _sharedModelRoute(accountId: 'acct-a'),
    );
    expect(crossAccount['modelAccount'], isNull);
    expect(crossAccount['modelCapabilities'], isEmpty);
  });
}

StudioThread _factsThread() => StudioThread(
  id: 'thread',
  projectId: 'project',
  title: 'Thread',
  mode: ThreadModeId.simple,
  delegationMode: DelegationMode.profile,
  delegationPreference: DelegationPreference.balanced,
  updatedAt: DateTime.utc(2026),
  workspacePath: '/tmp/thread',
);

ThreadModelRouteView _sharedModelRoute({
  required String accountId,
  bool available = true,
}) => ThreadModelRouteView(
  accountId: accountId,
  modelId: 'shared-model',
  effort: 'high',
  revision: 3,
  available: available,
);

/// 同名模型同时存在于两个账号：能力与凭据环境不同，展示诊断只能按已解析的
/// `(accountId, modelId)` 路由取账号，不能按裸 model id 取第一个命中。
AgentWorkspaceView _identityWorkspace({required ThreadModelRouteView? route}) {
  final thread = _factsThread();
  return AgentWorkspaceView(
    thread: thread,
    rootThread: thread,
    syncState: AgentWorkspaceSyncState.ready,
    loadError: null,
    todo: null,
    runtime: ThreadRuntimeView(
      modelId: 'shared-model',
      contextTokens: 0,
      contextWindow: 128000,
      totalTokens: 0,
      costLabel: '',
      activeSkills: const [],
      activeMcpServers: const [],
      activeLspServers: const [],
      modelRoute: route,
    ),
    turn: null,
    lastTurn: null,
    activeInteraction: null,
    composer: const ComposerThreadState.idle(),
    composerMode: AgentComposerMode.editable,
    accounts: [
      ModelSelectionAccount(
        id: 'acct-a',
        name: 'Account A',
        billingKind: BillingKind.unknown,
        models: [
          AccountModelView(
            modelId: 'a-only',
            displayName: 'A Only',
            reasoningEfforts: ['medium'],
            inputCapabilities: [
              ModelInputCapabilityView(
                modality: ModelModalityView.text,
                sources: [ModelInputSourceView.local],
              ),
            ],
          ),
        ],
      ),
      ModelSelectionAccount(
        id: 'acct-b',
        name: 'Account B',
        billingKind: BillingKind.unknown,
        models: [
          AccountModelView(
            modelId: 'shared-model',
            displayName: 'Shared Model',
            reasoningEfforts: ['high'],
            inputCapabilities: [
              ModelInputCapabilityView(
                modality: ModelModalityView.text,
                sources: [ModelInputSourceView.local],
              ),
              ModelInputCapabilityView(
                modality: ModelModalityView.image,
                sources: [ModelInputSourceView.local],
              ),
            ],
          ),
        ],
      ),
    ],
    roles: const [],
    agents: const [],
  );
}

/// 受控最小 content connection：只交付一份首帧基线，尾部保持静默。
final class _FactsConnection implements StudioTimelineConnection {
  _FactsConnection(this._baseline);

  final StudioTimelineBaseline Function() _baseline;
  final Completer<StudioTimelineUpdate?> _pending = Completer();
  int closeCalls = 0;
  bool closed = false;

  @override
  Future<StudioTimelineBaseline> initial() async => _baseline();

  @override
  Future<StudioTimelineUpdate?> next() => _pending.future;

  @override
  Future<StudioTimelinePage> page({String? before, int? limit}) async =>
      const StudioTimelinePage(items: [], before: null, hasOlder: false);

  @override
  Future<StudioTimelineDetailChunk> readDetail({
    required String itemId,
    required StudioTimelineDetailQuery query,
  }) async => StudioTimelineDetailChunk(
    itemId: itemId,
    field: query.field,
    revision: query.revision,
    text: '',
    totalBytes: 0,
    continuation: null,
  );

  @override
  void requestClose() {
    closed = true;
    if (!_pending.isCompleted) _pending.complete(null);
  }

  @override
  Future<void> close() async {
    closeCalls++;
    requestClose();
  }
}

final class _ScriptedTimelineTransport extends UnusedAccountPorts
    implements StudioTransport {
  _ScriptedTimelineTransport({StudioTimelineBaseline Function()? baseline})
    : _baseline = baseline ?? _factsBaseline;

  final StudioTimelineBaseline Function() _baseline;
  int opens = 0;

  @override
  Future<StudioTimelineConnection> openTimeline(String threadId) async {
    opens++;
    return _FactsConnection(_baseline);
  }

  @override
  Stream<ThreadStreamFrame> subscribeThread(String threadId) =>
      const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unused transport capability: ${invocation.memberName}',
  );
}

UserQuestionView _factsQuestion({required String id, String text = 'Q'}) =>
    UserQuestionView(
      id: id,
      header: 'Header',
      question: text,
      isOther: false,
      isSecret: false,
      options: const [],
    );

StudioTimelineItem _textItem(
  String id,
  int ordinal,
  ThreadTextChannel channel, {
  List<ThreadAttachmentView> attachments = const [],
}) => StudioTimelineItem(
  item: ThreadItemView(
    id: id,
    threadId: 'thread',
    turnId: 'turn',
    ordinal: ordinal,
    revision: 1,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    saved: true,
    executionTerminal: true,
    state: ThreadTextItemStateView(
      channel: channel,
      text: 'body-$id',
      attachments: attachments,
      lifecycle: CompletedThreadContentView(DateTime.utc(2026)),
    ),
  ),
  saved: true,
  lifecycle: StudioTimelineLifecycle.terminal,
  omittedBytes: 0,
  details: const [],
);

StudioTimelineItem _toolItem(
  String id,
  int ordinal, {
  ThreadToolUserInputView? userInput,
  ThreadToolLifecycleView lifecycle = const RunningThreadToolView(''),
  StudioTimelineLifecycle itemLifecycle = StudioTimelineLifecycle.streaming,
  String name = 'ask_user',
}) => StudioTimelineItem(
  item: ThreadItemView(
    id: id,
    threadId: 'thread',
    turnId: 'turn',
    ordinal: ordinal,
    revision: 1,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    saved: true,
    executionTerminal: true,
    state: ThreadToolItemStateView(
      invocation: ThreadToolInvocationView(
        toolCallId: id,
        callId: id,
        name: name,
        arguments: '{}',
      ),
      lifecycle: lifecycle,
      userInput: userInput,
    ),
  ),
  saved: true,
  lifecycle: itemLifecycle,
  omittedBytes: 0,
  details: const [],
);

StudioTimelineBaseline _factsBaseline() => StudioTimelineBaseline(
  subscriptionId: 'facts',
  version: 1,
  before: null,
  hasOlder: false,
  items: [
    _textItem('cm', 1, ThreadTextChannel.commentary),
    _textItem('fa', 2, ThreadTextChannel.finalAnswer),
    _toolItem('tool', 3),
    _toolItem(
      'qa-normal',
      4,
      userInput: ThreadToolUserInputView(
        interactionId: 'normal',
        questions: [_factsQuestion(id: 'q1')],
        state: const ResolvedThreadToolUserInputView([
          ThreadUserInputAnswerView(questionId: 'q1', answers: ['A']),
        ]),
      ),
    ),
    _toolItem(
      'qa-plan-pending',
      5,
      name: planSubmitToolName,
      userInput: ThreadToolUserInputView(
        interactionId: 'plan-pending',
        questions: [
          _factsQuestion(
            id: agentSessionPlanConfirmationQuestionId,
            text: '# Plan',
          ),
        ],
        state: const PendingThreadToolUserInputView(),
      ),
    ),
    _toolItem(
      'qa-plan-cancelled',
      6,
      name: planSubmitToolName,
      userInput: ThreadToolUserInputView(
        interactionId: 'plan-cancelled',
        questions: [
          _factsQuestion(
            id: agentSessionPlanConfirmationQuestionId,
            text: '# Plan',
          ),
        ],
        state: const CancelledThreadToolUserInputView(),
      ),
    ),
    _toolItem(
      'qa-plan-approved',
      7,
      name: planSubmitToolName,
      userInput: ThreadToolUserInputView(
        interactionId: 'plan-approved',
        questions: [
          _factsQuestion(
            id: agentSessionPlanConfirmationQuestionId,
            text: '# Plan',
          ),
        ],
        state: const ResolvedThreadToolUserInputView([
          ThreadUserInputAnswerView(
            questionId: agentSessionPlanConfirmationQuestionId,
            answers: [agentSessionPlanApproveAnswer],
          ),
        ]),
      ),
    ),
    // 旧历史的普通问答工具复用过保留的问题 ID：它仍必须报告为普通问答。
    _toolItem(
      'qa-plan-legacy',
      8,
      userInput: ThreadToolUserInputView(
        interactionId: 'plan-legacy',
        questions: [
          _factsQuestion(
            id: agentSessionPlanConfirmationQuestionId,
            text: '# Plan',
          ),
        ],
        state: const ResolvedThreadToolUserInputView([
          ThreadUserInputAnswerView(
            questionId: agentSessionPlanConfirmationQuestionId,
            answers: [agentSessionPlanApproveAnswer],
          ),
        ]),
      ),
    ),
  ],
);

/// 用户输入附件与工具输出附件都用 SDK 的 typed DTO 准备，不做 dynamic 替身。
const _userImage = ThreadAttachmentView(
  id: 'user-image',
  modality: AttachmentModalityView.image,
  mediaType: 'image/png',
  byteSize: 2048,
  filename: 'chart.png',
);

const _userFile = ThreadAttachmentView(
  id: 'user-file',
  modality: AttachmentModalityView.file,
  mediaType: 'text/plain',
  byteSize: 15,
  filename: 'notes.txt',
);

const _toolImage = ThreadAttachmentView(
  id: 'tool-image',
  modality: AttachmentModalityView.image,
  mediaType: 'image/png',
  byteSize: 4096,
  filename: 'shot.png',
);

const _toolVideo = ThreadAttachmentView(
  id: 'tool-video',
  modality: AttachmentModalityView.video,
  mediaType: 'video/mp4',
  byteSize: 8192,
  filename: 'clip.mp4',
);

/// 用户条目带图片/文件附件，工具条目带真实成功输出附件：投影必须同时保留
/// 顶层附件行与 nested 工具附件，且 modality 是 canonical enum 名。
StudioTimelineBaseline _attachmentBaseline() => StudioTimelineBaseline(
  subscriptionId: 'attachments',
  version: 1,
  before: null,
  hasOlder: false,
  items: [
    _textItem(
      'user',
      1,
      ThreadTextChannel.user,
      attachments: const [_userImage, _userFile],
    ),
    _toolItem(
      'tool-output',
      2,
      name: 'bash',
      itemLifecycle: StudioTimelineLifecycle.terminal,
      lifecycle: SucceededThreadToolView(
        DateTime.utc(2026),
        const ThreadToolOutputView(
          result: 'ok',
          attachments: [_toolImage, _toolVideo],
          outputArtifacts: [],
        ),
      ),
    ),
  ],
);

void _applyInstall(AppGraph graph, AcpInstallSnapshotView snapshot) =>
    graph.accountDomains.acceptFrame(
      AcpInstallFrame(
        ResourceStamp(
          resourceKey: 'acp-install',
          ownerEpoch: 'driver-owner',
          revision: snapshot.revision,
        ),
        snapshot,
      ),
    );

AccountsState _identitySummaries() => AccountsState(
  accounts: const [
    AccountSummary(
      identity: NativeAccountIdentity('acct-b'),
      name: 'Account B',
      isDefault: false,
      credentialReady: true,
      capabilities: AccountCapabilities(
        setDefault: false,
        edit: true,
        remove: true,
        queryUsage: false,
        syncModels: false,
        editModels: true,
        acpAuth: false,
      ),
    ),
  ],
);
Map<AccountIdentity, AccountResource<AccountDetails>> _identityDetails() => {
  const NativeAccountIdentity('acct-b'): AccountResource(
    stamp: const ResourceStamp(
      resourceKey: 'settings',
      ownerEpoch: 'identity',
      revision: 1,
    ),
    value: NativeAccountDetails(
      identity: const NativeAccountIdentity('acct-b'),
      name: 'Account B',
      protocol: 'open_ai_compatible',
      baseUrl: 'http://b.invalid',
      hasBearerToken: true,
      credentialRequired: true,
      usageQueryRevision: 1,
      customModels: const [],
    ),
  ),
};
