import 'support/mapped_conversation_feed.dart';
import 'support/chat_fixtures.dart';

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
import 'package:anywork/src/features/conversation/composer/view_models/composer_view_model.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_diagnostics.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_image_resources.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_message_controller.dart';
import 'package:anywork/src/features/shell/shell_view.dart';
import 'package:anywork/src/features/status/status_view.dart';
import 'package:anywork/src/shared/studio_driver_projection.dart';
import 'package:anywork/src/shared/studio_driver_state.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_demo_transport.dart';
import '../../../anywork_client/test/support/directory_feed.dart';

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

final class _ColdDirectoryTransport extends _UnusedTransport
    with DirectoryFeedFixture {
  // Restoring navigation may observe product topics, but must not open a child.
  @override
  Stream<ProductTopicFrame> subscribeProductTopic(ProductTopic topic) =>
      const Stream.empty();
}

final class _DirectoryRecordingDemoTransport extends RecordingDemoTransport
    with DirectoryFeedFixture {}

Future<DirectoryObservation<ThreadDirectoryFrame>> _observeDirectory(
  AnyworkClient client,
  String workspaceId,
) async {
  final demand = client.threadDirectory.observeThreads(
    DirectoryQuery(workspaceId: workspaceId),
    DirectoryWindow(),
  );
  try {
    await demand.state
        .waitFor((state) => state.frame != null)
        .timeout(const Duration(seconds: 5));
    return demand;
  } catch (error, stackTrace) {
    await demand.release();
    Error.throwWithStackTrace(error, stackTrace);
  }
}

Future<DirectoryObservation<ThreadMetadataFrame>> _observeThreadMetadata(
  AnyworkClient client,
  String threadId,
) async {
  final demand = client.threadDirectory.observeThread(threadId);
  try {
    await demand.state
        .waitFor((state) => state.frame?.thread != null)
        .timeout(const Duration(seconds: 5));
    return demand;
  } catch (error, stackTrace) {
    await demand.release();
    Error.throwWithStackTrace(error, stackTrace);
  }
}

Future<void> _closeDirectoryDemand<T>(DirectoryObservation<T> demand) =>
    demand.release();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('canonical cold and closed members survive a root-only Thread page and cold selection', () async {
    final transport = _ScriptedTimelineTransport(
      workspace: _factsWorkspace(_factsThread()),
    );
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
      workspaceId: 'other-project',
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
    transport.seedThread(root);
    final directoryDemand = await _observeDirectory(client, root.workspaceId);
    addTearDown(() => _closeDirectoryDemand(directoryDemand));
    expect(
      directoryDemand.state.value.frame!.threads.map((thread) => thread.id),
      [root.id],
      reason: 'The test demand is the root-only complete directory window',
    );
    final rootMetadata = await _observeThreadMetadata(client, root.id);
    addTearDown(() => _closeDirectoryDemand(rootMetadata));
    client.selection.restoreStartup(
      workspaceId: root.workspaceId,
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
    await container.pump();
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
    graph.timeline.updateReadDemand(chatDemand);
    graph.setConversationPageVisible(true);
    await client.directoryCommands.selectThread(root.id);
    final rootSession = client.conversations.session(root.id);
    await rootSession.source
        .waitFor((state) => state.workspace != null)
        .timeout(const Duration(seconds: 5));
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
    transport.emitThread(
      StudioThread(
        id: 'cold-closed',
        workspaceId: root.workspaceId,
        title: 'Closed child',
        workspacePath: root.workspacePath,
        mode: ThreadModeId.simple,
        delegationMode: DelegationMode.profile,
        delegationPreference: DelegationPreference.balanced,
        parentThreadId: root.id,
        rootThreadId: root.id,
        updatedAt: root.updatedAt,
      ),
      'cold-closed',
      revision: transport.directoryRevision + 1,
    );
    final closedMetadata = await _observeThreadMetadata(client, 'cold-closed');
    addTearDown(() => _closeDirectoryDemand(closedMetadata));
    client.selection.restoreStartup(
      workspaceId: root.workspaceId,
      threadId: 'cold-closed',
      needsOpen: true,
    );
    expect(
      header.read().selectedRootThread?.id,
      root.id,
      reason: 'Independent exact-ID child metadata identifies its root without opening a child Conversation',
    );
    expect(header.read().selectedThreadId, 'cold-closed');
    expect(sidebar.read().selectedProjectId, root.workspaceId);
    expect(header.read().agents.map((a) => a.threadId), [
      root.id,
      'cold-executor',
      'cold-closed',
      'nested',
      'faulted',
    ]);
    expect(client.conversations.sessionStates.map((state) => state.threadId), [
      root.id,
    ]);
    expect(transport.feeds.map((feed) => feed.threadId), [
      root.id,
    ], reason: 'Cold selection does not open a child Conversation feed');
    transport.seedThread(other);
    final otherMetadata = await _observeThreadMetadata(client, other.id);
    addTearDown(() => _closeDirectoryDemand(otherMetadata));
    client.selection.restoreStartup(
      workspaceId: other.workspaceId,
      threadId: other.id,
      needsOpen: true,
    );
    expect(header.read().agents.map((a) => a.threadId), [
      other.id,
      'other-child',
    ]);
    client.selection.restoreStartup(
      workspaceId: root.workspaceId,
      threadId: 'cold-closed',
      needsOpen: true,
    );
    final rootMetadataDemand = client.threadDirectory.observeThread(root.id);
    addTearDown(() => _closeDirectoryDemand(rootMetadataDemand));
    await rootMetadataDemand.state
        .waitFor((state) => state.frame != null)
        .timeout(const Duration(seconds: 5));
    transport.emitThread(
      null,
      root.id,
      revision: transport.directoryRevision + 1,
    );
    await rootMetadataDemand.state
        .waitFor((state) => state.frame?.thread == null)
        .timeout(const Duration(seconds: 5));
    expect(header.read().selectedRootThread, isNull);
    expect(
      header.read().workspaceThreads.map((thread) => thread.id),
      ['cold-closed'],
      reason: 'Missing root metadata cannot remove independently observed child metadata',
    );
    expect(header.read().agents.map((a) => a.threadId), [
      root.id,
      'cold-executor',
      'cold-closed',
      'nested',
      'faulted',
    ], reason: 'Even root metadata availability is not a membership condition');
    expect(sidebar.read().selectedProjectId, root.workspaceId);
    expect(
      client.conversations.sessionStates.map((state) => state.threadId),
      [root.id],
      reason: 'Only the previously opened root Conversation remains; metadata cannot activate a cold child',
    );
    expect(transport.feeds.map((feed) => feed.threadId), [
      root.id,
    ], reason: 'The cold child does not open a Conversation feed');
    header.close();
  });

  test(
    'canonical saved agent routes retain selection without activating children',
    () async {
      final transport = _ScriptedTimelineTransport(
        workspace: _factsWorkspace(_factsThread()),
      );
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
        workspaceId: 'project',
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
      transport.seedThread(root);
      final directoryDemand = await _observeDirectory(client, root.workspaceId);
      addTearDown(() => _closeDirectoryDemand(directoryDemand));
      expect(
        directoryDemand.state.value.frame!.threads.map((thread) => thread.id),
        [root.id],
      );
      transport.seedThread(child);
      final rootMetadata = await _observeThreadMetadata(client, root.id);
      addTearDown(() => _closeDirectoryDemand(rootMetadata));
      // This independent fixture exercises saved-route fallback below; it is
      // deliberately not published into the live AgentDirectory.
      StudioAgentView savedWithFrozenRoute(StudioAgentState state) =>
          StudioAgentView(
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
      client.project.applyProjectDirectory(
        ProjectDirectoryState(
          revision: 1,
          values: [
            StudioProject(
              id: root.workspaceId,
              name: 'Saved project',
              path: root.workspacePath,
            ),
          ],
        ),
      );
      client.project.applyAgentDirectory(
        AgentDirectoryState(
          revision: 1,
          values: [
            savedRoot,
            StudioAgentView(
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
              state: const IdleStudioAgent(),
              updatedAt: child.updatedAt,
            ),
          ],
        ),
      );
      graph.timeline.updateReadDemand(chatDemand);
      graph.setConversationPageVisible(true);
      client.selection.restoreStartup(
        workspaceId: root.workspaceId,
        threadId: root.id,
        needsOpen: true,
      );
      await client.directoryCommands.selectThread(root.id);
      final rootSession = client.conversations.session(root.id);
      await rootSession.source
          .waitFor((state) => state.workspace != null)
          .timeout(const Duration(seconds: 5));
      await rootSession.content.ready;
      // Keep the real root presentation independent of the cold selection.
      graph.setConversationPageVisible(true, threadId: root.id);
      client.selection.restoreStartup(
        workspaceId: root.workspaceId,
        threadId: child.id,
        needsOpen: true,
      );
      final childMetadata = await _observeThreadMetadata(client, child.id);
      addTearDown(() => _closeDirectoryDemand(childMetadata));
      expect(childMetadata.state.value.frame!.thread, same(child));
      final container = ProviderContainer(
        overrides: [appGraphProvider.overrideWithValue(graph)],
      );
      addTearDown(container.dispose);
      final header = container.listen(headerViewProvider, (_, _) {});
      addTearDown(header.close);
      await container.pump();
      expect(
        header
            .read()
            .workspaceThreads
            .singleWhere((thread) => thread.id == child.id)
            .frozenModel,
        frozen,
        reason:
            'Header owns exact-ID metadata including the complete frozen route',
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
      expect(facts.workspace, isNotNull);
      final workspace = facts.workspace!;
      expect(workspace.thread.id, root.id);
      expect(workspace.agents.map((a) => a.threadId), contains(child.id));
      final driverChild = workspace.agents.singleWhere(
        (a) => a.threadId == child.id,
      );
      expect(
        driverChild.frozenModel,
        isNull,
        reason: 'Driver has no child Conversation or child row in its root-only window; it must not union independent metadata demands',
      );
      expect(client.conversations.existingSession(child.id), isNull);
      final cold = AgentDirectoryQueries.forRoot(
        rootThreadId: root.id,
        agents: [savedWithFrozenRoute(const IdleStudioAgent())],
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
        agents: [savedWithFrozenRoute(const ClosedStudioAgent())],
      ).single;
      expect(cold.frozenModel, frozen);
      expect(closed.frozenModel, frozen);
      expect(closed.delegationPreference, DelegationPreference.economy);
      expect(client.selection.state.selectedThreadId, child.id);
      expect(transport.feeds.map((feed) => feed.threadId), [
        root.id,
      ], reason: 'Fallback/Driver reads cannot fetch or activate a cold child');
      expect(
        AgentDirectoryQueries.forRoot(
          rootThreadId: root.id,
          agents: [savedRoot],
        ).single.frozenModel,
        isNull,
        reason: 'No saved model remains genuinely unknown, never filled from a current Profile',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test('workspace and Driver join current directory identity after a Turn', () async {
    final graph = AppGraph(
      statisticsFeed: const TestStatisticsFeedPort(),
      transport: _DirectoryRecordingDemoTransport(),
      clientId: 'directory-identity',
    );
    addTearDown(
      () =>
          graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
    );
    final client = graph.client;
    final transport =
        graph.client.transport as _DirectoryRecordingDemoTransport;
    final bootstrap = await transport.readBootstrap();
    transport.seedThread(
      bootstrap.threadDirectory.threads.singleWhere(
        (thread) => thread.id == 'thread-main',
      ),
    );
    await client.bootstrap();
    final metadataDemand = client.threadDirectory.observeThread('thread-main');
    addTearDown(() => _closeDirectoryDemand(metadataDemand));
    await metadataDemand.state
        .waitFor((state) => state.frame?.thread != null)
        .timeout(const Duration(seconds: 5));
    await (graph
          ..timeline.updateReadDemand(chatDemand)
          ..setConversationPageVisible(true))
        .client
        .directoryCommands
        .selectThread('thread-main');
    final session = client.conversations.existingSession('thread-main')!;
    await session.content.state.waitFor((state) => state.snapshot == true);
    final initial = session.state.workspace!;
    // A runtime baseline may predate the directory's terminal/title/mode frame.
    await transport.publishWorkspace(
      initial.copyWith(
        thread: initial.thread.copyWith(status: ThreadStatusView.running),
      ),
    );
    final container = ProviderContainer(
      overrides: [appGraphProvider.overrideWithValue(graph)],
    );
    addTearDown(container.dispose);
    final workspace = container.listen(
      conversationWorkspaceProvider('thread-main'),
      (_, _) {},
    );
    final status = container.listen(
      statusBarViewProvider('thread-main'),
      (_, _) {},
    );
    final composer = container.listen(
      composerDockViewModelProvider('thread-main'),
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
    transport.emitThread(
      canonical,
      canonical.id,
      revision: transport.directoryRevision + 1,
    );
    await metadataDemand.state
        .waitFor((state) => identical(state.frame?.thread, canonical))
        .timeout(const Duration(seconds: 5));
    // The directory frame can arrive before an already captured runtime
    // baseline. Unix-second timestamps cannot order these resource domains.
    await transport.publishWorkspace(
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
    final display = timeline.lease('thread-main');
    await timeline.returnToLive('thread-main');
    final switched = queryStudioDriverFacts(
      client,
      accountsRepository: graph.accounts,
      modelsRepository: graph.models,
      usageRepository: graph.accountUsage,
      acpService: graph.acp,
      timeline: timeline,
    );
    expect(switched.timeline!.generation, generation);
    expect(timeline.lease('thread-main'), same(display));
    expect(switched.timeline!.threadId, 'thread-main');
    // 阅读模式不切代次；诊断仍从同一真实 lease 读取几何。
    expect(switched.timelineScroll, isNotNull);
    expect(switched.timelineScroll!.generation, switched.timeline!.generation);
    expect(switched.timelineScroll!.threadId, 'thread-main');
    expect(facts.workspace!.thread, same(canonical));
    expect(workspace.read()!.thread, same(canonical));
    expect(status.read()!.thread, same(canonical));
    expect(composer.read().requireValue.thread, same(canonical));
  });

  test('Driver reads a test-owned directory demand without creating another owner or lease', () async {
    final transport = _ColdDirectoryTransport();
    final graph = AppGraph(
      statisticsFeed: const TestStatisticsFeedPort(),
      transport: transport,
      clientId: 'driver-query',
    );
    final client = graph.client;
    addTearDown(
      () =>
          graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
    );
    final thread = StudioThread(
      id: 'thread',
      workspaceId: 'project',
      title: 'Original title',
      mode: ThreadModeId.simple,
      delegationMode: DelegationMode.profile,
      delegationPreference: DelegationPreference.balanced,
      updatedAt: DateTime.utc(2026),
      workspacePath: '/tmp/thread',
    );
    transport.seedThread(thread);
    final directoryDemand = await _observeDirectory(client, thread.workspaceId);
    addTearDown(() => _closeDirectoryDemand(directoryDemand));
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
    expect(original.timelineScroll, isNull, reason: '没有展示 lease 就没有几何，也不回放上一代');
    expect(timeline.lease('thread'), isNull);
    expect(client.conversations.sessionStates, isEmpty);
    expect(client.drafts.existingComposer('thread')?.state, isNull);
    expect(client.ownedSkills, isEmpty);
    expect(client.ownedSessionCosts, isEmpty);
    expect(transport.calls, 0);

    transport.directoryRevision++;
    transport.directoryThreads[thread.id] = thread.copyWith(
      title: 'Updated canonical title',
    );
    await directoryDemand.refresh();
    await directoryDemand.state
        .waitFor(
          (state) =>
              state.frame?.threads.single.title == 'Updated canonical title',
        )
        .timeout(const Duration(seconds: 5));
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
      timeline: timeline,
      accountsRepository: graph.accounts,
      modelsRepository: graph.models,
      usageRepository: graph.accountUsage,
      acpService: graph.acp,
    );
    expect(client.conversations.sessionStates, isEmpty);
    expect(client.drafts.existingComposer('thread')?.state, isNull);
    expect(client.budget.usage.length, usageBefore);
    expect(
      transport.calls,
      0,
      reason: 'snapshot queries never create transport demand',
    );
    expect((await client.close()).complete, isTrue);
  });

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
    'Driver new-thread projection retains the raw composer failure object',
    () {
      final transport = _UnusedTransport();
      final graph = AppGraph(
        statisticsFeed: const TestStatisticsFeedPort(),
        transport: transport,
        clientId: 'driver-failure-projection',
      );
      addTearDown(() async {
        expect(
          (await graph.close(
            deadline: DateTime.now().add(const Duration(seconds: 5)),
          )).complete,
          isTrue,
        );
      });
      final client = graph.client;
      const project = StudioProject(
        id: 'project',
        name: 'Project',
        path: '/project',
      );
      client.project.applyProjectDirectory(
        ProjectDirectoryState(revision: 1, values: [project]),
      );
      client.selection.selectProject(project.id);
      const failure = StudioFailure(
        code: StudioFailureCode.permissionDenied,
        message: 'Typed recovery failure from attachment admission',
        retryable: false,
        correlationId: 'driver-recovery-failure',
      );
      client.drafts.attachments.reportNewThreadFailure(project.id, failure);

      final facts = queryStudioDriverFacts(
        client,
        timeline: graph.timeline,
        accountsRepository: graph.accounts,
        modelsRepository: graph.models,
        usageRepository: graph.accountUsage,
        acpService: graph.acp,
      );
      expect(facts.newThreadComposer.failure, same(failure));
      expect(facts.newThreadComposer.error, failure.toString());
      expect(transport.calls, 0);
    },
  );

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

  test('timeline facts expose completed clocks, text channels and typed Plan decisions', () async {
    final diagnosticReaders = <_DiagnosticReader>[];
    final transport = _ScriptedTimelineTransport(
      readerFactory: (threadId) {
        final reader = _DiagnosticReader(threadId);
        diagnosticReaders.add(reader);
        return reader;
      },
    );
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
    transport.seedThread(_factsThread());
    final metadataDemand = await _observeThreadMetadata(client, 'thread');
    addTearDown(() => _closeDirectoryDemand(metadataDemand));
    final timeline = graph.timeline;
    (graph
          ..timeline.updateReadDemand(chatDemand)
          ..setConversationPageVisible(true))
        .client
        .selection
        .selectThread(threadId: 'thread', workspaceId: 'project');
    await timeline.source.waitFor(
      (state) => state != null && state.generation > 0,
    );

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
    expect(itemOf('fa')['channel'], 'final');
    expect(itemOf('cm')['channel'], isNot(itemOf('fa')['channel']));
    expect(itemOf('tool')['channel'], isNull);
    // 两个文本条目的 kind 相同也必须靠 channel 区分，不能从 kind/文本推测。
    expect(itemOf('cm')['kind'], itemOf('fa')['kind']);

    // 普通问答：false + 无决定。
    expect(userInputOf('qa-normal')!['isPlanConfirmation'], isFalse);
    expect(userInputOf('qa-normal')!['planDecision'], isNull);
    // Plan completion is its own typed atom. A pending Plan has no historical atom.
    expect(
      items.cast<Map<String, dynamic>>().map((item) => item['id']),
      isNot(contains('qa-plan-pending')),
    );
    expect(itemOf('plan-cancelled')['kind'], 'plan');
    expect(itemOf('plan-cancelled')['status'], 'cancelled');
    expect(itemOf('plan-cancelled')['plan']['decision'], 'cancelled');
    expect(itemOf('plan-approved')['kind'], 'plan');
    expect(itemOf('plan-approved')['status'], 'approved');
    expect(itemOf('plan-approved')['plan']['decision'], 'approved');
    expect(userInputOf('plan-approved'), isNull);
    final approved = itemOf('plan-approved')['plan'];
    expect(approved, {
      'interactionId': 'approved',
      'decision': 'approved',
      'documentVersion': 7,
      'contentHash': 'recorded-approved-hash',
      'document': '# Approved plan',
      'feedback': '  historical feedback\n',
    });
    final lease = timeline.lease('thread')!;
    final timelineJson = json['timeline'] as Map<String, dynamic>;
    expect(items.length, lease.controller.messages.length);
    expect(
      items.cast<Map<String, dynamic>>().map((item) => item['id']),
      lease.controller.messages.map((message) => message.id),
    );
    expect(
      itemOf('turn-completed')['kind'],
      'turn',
      reason: 'one producer Turn is a real Message, no hidden local owner',
    );
    expect(itemOf('cm')['sealedAt'], isNull);
    expect(itemOf('fa')['sealedAt'], 1767225600);
    for (final oldField in [
      'timelineEpoch',
      'completedThrough',
      'presentationItems',
    ]) {
      expect(timelineJson.containsKey(oldField), isFalse);
    }
    for (final oldField in [
      'appendSeq',
      'sourceEffectSeq',
      'revision',
      'ordinal',
    ]) {
      expect(itemOf('cm').containsKey(oldField), isFalse);
    }
    // 旧普通问答复用保留 ID：归属只看工具名，仍是普通问答。
    expect(userInputOf('qa-plan-legacy')!['isPlanConfirmation'], isFalse);
    expect(userInputOf('qa-plan-legacy')!['planDecision'], isNull);
    // 每个问答条目都始终输出该键（固定 schema）。
    for (final id in const ['qa-normal', 'qa-plan-legacy']) {
      expect(userInputOf(id)!.containsKey('isPlanConfirmation'), isTrue);
      expect(userInputOf(id)!.containsKey('planDecision'), isTrue);
    }

    expect(timelineJson['appliedSets'], 1);
    expect(timelineJson['appliedPrepends'], 0);
    expect(timelineJson['appliedAppends'], 0);
    expect(timelineJson['firstContentLayout'], isNull);
    expect(lease.selectionId, isNotNull);
    expect(lease.selectionStartedMicros, isNotNull);

    // Only the read-only display resource is supplied by this test. Its messages
    // and metadata come from the actual Flyer controller and production adapter.
    // This proves Driver borrowing, not the UI Children's own apply counters.
    final childController = InMemoryChatController();
    final childImages = TimelineImageResources(threadId: 'thread');
    final childAdapter = TimelineMessageController(
      childController,
      generation: 71,
      imageResources: childImages,
    );
    addTearDown(() {
      childAdapter.dispose();
      childImages.release();
      childController.dispose();
    });
    await childAdapter.applyBatch(
      chatBatch([
        _toolItem('child-tool', name: 'child_tool', result: 'child-result'),
        chatMessage('child-text'),
      ]),
    );
    var childIsCurrent = true;
    final borrowed = _BorrowedChildrenDisplay(
      controller: childController,
      isEligible: () => childIsCurrent,
    );
    final usageBeforeQuery = {
      for (final kind in ResourceKind.values) kind: client.budget.used(kind),
    };
    final opensBeforeQuery = transport.opens;
    final unregister = lease.registerChildrenDisplay(borrowed);
    Map<String, dynamic> currentTimelineJson() =>
        (jsonDecode(StudioDriverState.snapshotJson())
                as Map<String, dynamic>)['timeline']
            as Map<String, dynamic>;
    expect(
      currentTimelineJson()['current'],
      isNull,
      reason:
          'Main facts or Chat.current cannot replace a mounted current borrow',
    );
    const waitJson =
        '{ "contract":"anywork.chat/1","type":"tool","data":'
        '{"invocation":{"name":"opaque-producer-name","presentationContract":'
        '"builtin.wait@1"},"wait":{"state":"completed","messagesReady":true,'
        '"intent":{"kind":"events","data":{"timeoutMs":4500,'
        '"targets":[{"kind":"task","id":"task:区别"}]}}}} }\n';
    const payloadRef = ContentRef(
      databaseId: 'current-db',
      target: ItemPayloadTarget(itemId: 'large-current-entry'),
    );
    const currentBodyRef = ContentRef(
      databaseId: 'current-db',
      target: BodyContentTarget(
        owner: CurrentContentOwner(
          domain: 'tool',
          id: 'current-call',
          revision: 83,
        ),
        key: 'tool.output',
      ),
    );
    const itemBodyRef = ContentRef(
      databaseId: 'current-db',
      target: BodyContentTarget(
        owner: ItemContentOwner(itemId: 'completed-tool'),
        key: 'tool.arguments',
      ),
    );
    final tools = _BorrowedCurrentCollection(
      reference: const CurrentCollectionRef(
        databaseId: 'current-db',
        collection: 'tools',
        revision: 83,
      ),
      generation: 19,
      page: CurrentCollectionPage(
        revision: 83,
        continuation: 'opaque-tools-next',
        entries: [
          CurrentCollectionEntry(
            id: 'wait-entry',
            position: 42,
            payload: InlinePayload(bytes: utf8.encode(waitJson)),
          ),
          const CurrentCollectionEntry(
            id: 'deferred-entry',
            position: 77,
            payload: DeferredPayload(reference: payloadRef, byteLength: 123456),
          ),
        ],
      ),
    );
    final notReady = _BorrowedCurrentCollection(
      reference: const CurrentCollectionRef(
        databaseId: 'current-db',
        collection: 'backgroundTools',
        revision: 91,
      ),
      generation: 20,
      error: StateError('page unavailable'),
    );
    var currentEligible = true;
    final currentBorrow = _BorrowedCurrentDisplay(
      isEligible: () => currentEligible,
      turnId: 'borrowed-turn',
      activityId: 'borrowed-activity',
      collections: [tools, notReady],
      windows: [
        _BorrowedCurrentWindow(
          id: 'tool-output',
          reference: currentBodyRef,
          offset: 128,
          window: ContentWindow(
            offset: 128,
            bytes: [0, 255, 65, 10],
            generation: 'body-generation-7',
            availableThrough: 900,
            sealed: false,
          ),
        ),
        const _BorrowedCurrentWindow(
          id: 'pending-arguments',
          reference: itemBodyRef,
          offset: 64,
        ),
        _BorrowedCurrentWindow(
          id: 'failed-payload',
          reference: payloadRef,
          offset: 256,
          error: StateError('window unavailable'),
        ),
      ],
    );
    final unregisterCurrent = lease.registerCurrentDisplay(currentBorrow);
    final projectedCurrent = currentTimelineJson()['current'] as Map;
    expect(projectedCurrent['turnId'], 'borrowed-turn');
    expect(projectedCurrent.containsKey('childrenParentId'), isFalse);
    expect(projectedCurrent['activityId'], 'borrowed-activity');
    expect(projectedCurrent['expanded'], isTrue);
    final projectedTools =
        (projectedCurrent['collections'] as List).first as Map;
    expect(projectedTools, {
      'databaseId': 'current-db',
      'collection': 'tools',
      'revision': 83,
      'generation': 19,
      'expanded': true,
      'loading': false,
      'error': null,
      'ready': true,
      'continuation': 'opaque-tools-next',
      'entries': [
        {
          'id': 'wait-entry',
          'position': 42,
          'payload': {
            'kind': 'inline',
            'byteLength': utf8.encode(waitJson).length,
            'base64': base64Encode(utf8.encode(waitJson)),
          },
        },
        {
          'id': 'deferred-entry',
          'position': 77,
          'payload': {
            'kind': 'deferred',
            'byteLength': 123456,
            'reference': {
              'databaseId': 'current-db',
              'target': {
                'kind': 'itemPayload',
                'itemId': 'large-current-entry',
              },
            },
          },
        },
      ],
    });
    final waitPayload =
        ((projectedTools['entries'] as List).first as Map)['payload'] as Map;
    expect(
      utf8.decode(base64Decode(waitPayload['base64'] as String)),
      waitJson,
      reason:
          'keep producer wait JSON opaque, including its name and whitespace',
    );
    expect((projectedCurrent['collections'] as List).last, {
      'databaseId': 'current-db',
      'collection': 'backgroundTools',
      'revision': 91,
      'generation': 20,
      'expanded': true,
      'loading': false,
      'error': 'Bad state: page unavailable',
      'ready': false,
      'continuation': null,
      'entries': [],
    });
    expect(projectedCurrent['windows'], [
      {
        'id': 'tool-output',
        'offset': 128,
        'error': null,
        'reference': {
          'databaseId': 'current-db',
          'target': {
            'kind': 'body',
            'key': 'tool.output',
            'owner': {
              'kind': 'current',
              'domain': 'tool',
              'id': 'current-call',
              'revision': 83,
            },
          },
        },
        'window': {
          'offset': 128,
          'byteLength': 4,
          'base64': base64Encode([0, 255, 65, 10]),
          'generation': 'body-generation-7',
          'availableThrough': 900,
          'sealed': false,
        },
      },
      {
        'id': 'pending-arguments',
        'offset': 64,
        'error': null,
        'window': null,
        'reference': {
          'databaseId': 'current-db',
          'target': {
            'kind': 'body',
            'key': 'tool.arguments',
            'owner': {'kind': 'item', 'itemId': 'completed-tool'},
          },
        },
      },
      {
        'id': 'failed-payload',
        'offset': 256,
        'error': 'Bad state: window unavailable',
        'window': null,
        'reference': {
          'databaseId': 'current-db',
          'target': {'kind': 'itemPayload', 'itemId': 'large-current-entry'},
        },
      },
    ]);
    expect(
      base64Decode(
        ((projectedCurrent['windows'] as List).first as Map)['window']['base64']
            as String,
      ),
      [0, 255, 65, 10],
    );
    for (var snapshot = 0; snapshot < 3; snapshot++) {
      expect(currentTimelineJson()['current'], projectedCurrent);
    }
    tools.page = CurrentCollectionPage(
      revision: 83,
      entries: [
        CurrentCollectionEntry(
          id: 'updated-page',
          position: 98,
          payload: InlinePayload(bytes: utf8.encode('new admitted page')),
        ),
      ],
    );
    final updatedCurrent = currentTimelineJson()['current'] as Map;
    final updatedTools = (updatedCurrent['collections'] as List).first as Map;
    expect(updatedTools['continuation'], isNull);
    expect((updatedTools['entries'] as List).single['id'], 'updated-page');
    expect(
      (projectedTools['entries'] as List).first['id'],
      'wait-entry',
      reason:
          'new query reads the current borrowed page, not a cached JSON copy',
    );
    tools.isCurrent = false;
    expect(
      ((currentTimelineJson()['current'] as Map)['collections'] as List),
      hasLength(1),
    );
    tools.isCurrent = true;
    currentEligible = false;
    expect(currentTimelineJson()['current'], isNull);
    currentEligible = true;
    unregisterCurrent();
    unregisterCurrent();
    expect(currentTimelineJson()['current'], isNull);
    final unregisterA = lease.registerCurrentDisplay(currentBorrow);
    final currentB = _BorrowedCurrentDisplay(
      isEligible: () => true,
      turnId: 'replacement-turn',
      activityId: null,
      collections: const [],
      windows: const [],
    );
    final unregisterB = lease.registerCurrentDisplay(currentB);
    unregisterA();
    expect(
      (currentTimelineJson()['current'] as Map)['turnId'],
      'replacement-turn',
    );
    unregisterB();
    expect(currentTimelineJson()['current'], isNull);
    final unregisterRetiredCurrent = lease.registerCurrentDisplay(
      currentBorrow,
    );
    final firstBorrow = currentTimelineJson();
    final childJson = (firstBorrow['children'] as List).single as Map;
    expect(childJson['parentId'], 'turn-parent');
    expect(childJson['generation'], 71);
    expect(childJson['ready'], isTrue);
    expect(childJson['loadedCount'], childController.messages.length);
    expect(childJson['itemIds'], ['child-tool', 'child-text']);
    expect(childJson['olderCursor'], 'opaque-child-before');
    expect(childJson['loadingOlder'], isFalse);
    expect(childJson['error'], isNull);
    expect(
      (
        childJson['appliedSets'],
        childJson['appliedPrepends'],
        childJson['appliedAppends'],
      ),
      (7, 3, 5),
      reason: 'forward borrowed facts, do not infer them from length',
    );
    final childItems = (childJson['items'] as List).cast<Map>();
    expect(childItems.first['kind'], 'tool');
    expect(childItems.first['presentationContract'], 'generic@1');
    expect((childItems.first['tool'] as Map)['result'], 'child-result');
    expect(
      (childItems.first['details'] as List).cast<Map>().map(
        (detail) => detail['field'],
      ),
      ['tool.arguments', 'tool.result'],
    );
    expect(
      (firstBorrow['items'] as List).cast<Map>().map((item) => item['id']),
      lease.controller.messages.map((message) => message.id),
    );
    expect(
      (firstBorrow['items'] as List).cast<Map>().map((item) => item['id']),
      isNot(contains('child-tool')),
    );
    await childAdapter.applyBatch(
      chatBatch([chatMessage('child-later')], placement: ChatPlacement.append),
    );
    final laterBorrow = currentTimelineJson();
    expect(((laterBorrow['children'] as List).single as Map)['itemIds'], [
      'child-tool',
      'child-text',
      'child-later',
    ]);
    expect(
      childJson['itemIds'],
      ['child-tool', 'child-text'],
      reason: 'each query snapshots the borrowed controller, not a live mirror',
    );
    expect(
      laterBorrow['firstContentLayout'],
      isNull,
      reason: 'ready, messages and Driver queries are not layout witnesses',
    );
    expect(transport.opens, opensBeforeQuery);
    expect(
      diagnosticReaders.single.queryCalls,
      0,
      reason: 'snapshots never page/read/watch, including Deferred payloads',
    );
    expect(
      {for (final kind in ResourceKind.values) kind: client.budget.used(kind)},
      usageBeforeQuery,
      reason: 'borrowing/querying never opens a scope or IO',
    );

    unregister();
    unregister();
    expect(currentTimelineJson()['children'], isEmpty);
    final unregisterRetiring = lease.registerChildrenDisplay(borrowed);
    childIsCurrent = false;
    expect(currentTimelineJson()['children'], isEmpty);
    childIsCurrent = true;
    expect(currentTimelineJson()['children'], hasLength(1));

    lease.bind();
    addTearDown(() async {
      graph.setConversationPageVisible(false);
      await lease.unbind();
    });
    graph.setConversationPageVisible(false);
    expect(lease.isRetired, isTrue);
    expect(lease.childrenDisplays, isEmpty);
    expect(lease.currentDisplay, isNull);
    // A late old registration remains scoped to the retired Main lease.
    lease.registerChildrenDisplay(borrowed)();
    expect(lease.childrenDisplays, isEmpty);
    graph.setConversationPageVisible(true);
    await client.conversations.session('thread').content.ready;
    final replacement = timeline.lease('thread')!;
    expect(replacement.generation, greaterThan(lease.generation));
    expect(replacement.selectionId, isNot(lease.selectionId));
    replacement.bind();
    addTearDown(() async {
      graph.setConversationPageVisible(false);
      await replacement.unbind();
    });
    expect(currentTimelineJson()['children'], isEmpty);
    expect(currentTimelineJson()['current'], isNull);
    final unregisterNewCurrent = replacement.registerCurrentDisplay(currentB);
    unregisterRetiredCurrent();
    lease.registerCurrentDisplay(currentBorrow)();
    expect(lease.currentDisplay, isNull);
    expect(
      (currentTimelineJson()['current'] as Map)['turnId'],
      'replacement-turn',
      reason: 'old lease registrations/unregisters cannot affect the new lease',
    );
    final unregisterReplacement = replacement.registerChildrenDisplay(borrowed);
    unregisterRetiring();
    expect(
      currentTimelineJson()['children'],
      hasLength(1),
      reason: 'old unregister cannot remove a new lease registration',
    );
    timeline.recordContentLayout(lease, 'cm', timeline.monotonicMicros);
    expect(lease.firstContentLayout, isNull);
    expect(replacement.firstContentLayout, isNull);
    expect(
      currentTimelineJson()['firstContentLayout'],
      isNull,
      reason: 'old lease callback cannot write the current generation',
    );
    unregisterReplacement();
    unregisterNewCurrent();
    expect(currentTimelineJson()['current'], isNull);
    expect(diagnosticReaders.every((reader) => reader.queryCalls == 0), isTrue);
    graph.setConversationPageVisible(false);
    await replacement.unbind();
    await lease.unbind();

    client.conversations.setVisibleThread(null);
    await timeline.close(
      deadline: DateTime.now().add(const Duration(seconds: 5)),
    );
    await client.close(
      deadline: DateTime.now().add(const Duration(seconds: 5)),
    );
  });

  test('Driver counts admitted Main placements, not loaded message lengths', () async {
    final readers = <_DiagnosticReader>[];
    final transport = _ScriptedTimelineTransport(
      initial: () => chatBatch([chatMessage('main')], before: 'opaque-main'),
      readerFactory: (threadId) {
        final reader = _DiagnosticReader(threadId);
        readers.add(reader);
        return reader;
      },
    );
    final graph = AppGraph(
      statisticsFeed: const TestStatisticsFeedPort(),
      transport: transport,
      clientId: 'driver-placement-counts',
    );
    addTearDown(() async {
      graph.setConversationPageVisible(false);
      for (final reader in readers) {
        if (!reader.reply.isCompleted) {
          reader.reply.complete(
            chatBatch([], placement: ChatPlacement.prepend),
          );
        }
      }
      await graph.close(
        deadline: DateTime.now().add(const Duration(seconds: 5)),
      );
    });
    final client = graph.client;
    client.selection.markOpened();
    transport.seedThread(_factsThread());
    final metadataDemand = await _observeThreadMetadata(client, 'thread');
    addTearDown(() => _closeDirectoryDemand(metadataDemand));
    graph.timeline.updateReadDemand(chatDemand);
    graph.setConversationPageVisible(true);
    client.selection.selectThread(threadId: 'thread', workspaceId: 'project');
    final session = client.conversations.session('thread');
    await session.content.ready;
    final feed = transport.feeds.single;
    await feed.accepted(1);
    final lease = graph.timeline.lease('thread')!;
    TimelineDisplayFacts query() => queryStudioDriverFacts(
      client,
      accountsRepository: graph.accounts,
      modelsRepository: graph.models,
      usageRepository: graph.accountUsage,
      acpService: graph.acp,
      timeline: graph.timeline,
    ).timeline!;
    void expectCounts(int sets, int prepends, int appends, int messages) {
      final facts = query();
      expect(
        (facts.appliedSets, facts.appliedPrepends, facts.appliedAppends),
        (sets, prepends, appends),
      );
      expect(facts.items.length, messages);
      expect(facts.firstContentLayout, isNull);
    }

    expectCounts(1, 0, 0, 1);
    feed.emit(chatBatch([], placement: ChatPlacement.append));
    await feed.accepted(2);
    expectCounts(1, 0, 1, 1);
    final appendCountsAtComponentOperation = <int>[];
    final operations = lease.controller.operationsStream.listen((_) {
      appendCountsAtComponentOperation.add(lease.appliedAppends);
    });
    addTearDown(operations.cancel);
    feed.emit(
      chatBatch([
        chatMessage('append-a'),
        chatMessage('append-b'),
      ], placement: ChatPlacement.append),
    );
    await feed.accepted(3);
    expect(appendCountsAtComponentOperation, [
      1,
    ], reason: 'counter updates only after the actual controller await');
    expectCounts(1, 0, 2, 3);

    final reader = readers.single;
    final loading = graph.timeline.loadOlder(
      'thread',
      generation: lease.generation,
    );
    await reader.entered.future;
    expectCounts(1, 0, 2, 3);
    reader.reply.complete(
      chatBatch(
        [chatMessage('older-a'), chatMessage('older-b')],
        placement: ChatPlacement.prepend,
        before: 'opaque-next',
      ),
    );
    await loading;
    expectCounts(1, 1, 2, 5);
    reader.reply = Completer<ChatBatch>()
      ..complete(chatBatch([], placement: ChatPlacement.prepend));
    await graph.timeline.loadOlder('thread', generation: lease.generation);
    expectCounts(1, 2, 2, 5);
    expect(reader.boundaries, ['opaque-main', 'opaque-next']);
    final usage = {
      for (final kind in ResourceKind.values) kind: client.budget.used(kind),
    };
    for (var queryIndex = 0; queryIndex < 3; queryIndex++) {
      expectCounts(1, 2, 2, 5);
    }
    expect(transport.opens, 1);
    expect(reader.queryCalls, 2, reason: 'Driver adds no content/history IO');
    expect(reader.closeCalls, 0);
    expect(reader.requestCloseCalls, 0);
    expect({
      for (final kind in ResourceKind.values) kind: client.budget.used(kind),
    }, usage);

    // Re-enter a selection from the real component operation stream. Although
    // the old controller accepted the Message, that lease must not count it as
    // a qualified admission or contaminate the replacement generation.
    await operations.cancel();
    lease.bind();
    addTearDown(() async {
      graph.setConversationPageVisible(false);
      await lease.unbind();
    });
    final interrupted = Completer<void>();
    final reentrant = lease.controller.operationsStream.listen((_) {
      if (interrupted.isCompleted) return;
      expect(lease.appliedAppends, 2);
      graph.setConversationPageVisible(false);
      graph.setConversationPageVisible(true);
      interrupted.complete();
    });
    addTearDown(reentrant.cancel);
    feed.emit(
      chatBatch([
        chatMessage('retired-append'),
      ], placement: ChatPlacement.append),
    );
    await interrupted.future;
    await session.content.ready;
    await transport.feeds.last.accepted(1);
    await lease.unbind();
    expect(lease.appliedAppends, 2);
    expectCounts(1, 0, 0, 1);
    expect(query().items.single.id, 'main');
    expect(
      readers.fold<int>(0, (count, reader) => count + reader.queryCalls),
      2,
    );
  });

  test(
    'attachment facts keep canonical modality for user and tool items',
    () async {
      final transport = _ScriptedTimelineTransport(
        initial: _attachmentSet,
        workspace: _factsWorkspace(_factsThread()),
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
      transport.seedThread(_factsThread());
      final metadataDemand = await _observeThreadMetadata(client, 'thread');
      addTearDown(() => _closeDirectoryDemand(metadataDemand));
      final timeline = graph.timeline;
      (graph
            ..timeline.updateReadDemand(chatDemand)
            ..setConversationPageVisible(true))
          .client
          .selection
          .selectThread(threadId: 'thread', workspaceId: 'project');
      await timeline.source.waitFor(
        (state) => state != null && state.generation > 0,
      );

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
        'tool',
        'tool',
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
      client.conversations.setVisibleThread(null);
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
  workspaceId: 'project',
  title: 'Thread',
  mode: ThreadModeId.simple,
  delegationMode: DelegationMode.profile,
  delegationPreference: DelegationPreference.balanced,
  updatedAt: DateTime.utc(2026),
  workspacePath: '/tmp/thread',
);

ThreadWorkspace _factsWorkspace(StudioThread thread) => ThreadWorkspace(
  thread: thread,
  revision: 1,
  interactions: const [],
  runtime: const ThreadRuntimeView(
    modelId: 'model',
    contextTokens: 0,
    contextWindow: 128000,
    totalTokens: 0,
    costLabel: '',
    activeSkills: [],
    activeMcpServers: [],
    activeLspServers: [],
  ),
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
    ),
    modelRoute: route,
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

// Only the external source is scripted; SDK admission and Driver queries remain real.
final class _ScriptedTimelineTransport extends _UnusedTransport
    with DirectoryFeedFixture {
  _ScriptedTimelineTransport({
    ChatBatch Function()? initial,
    this.readerFactory,
    this.workspace,
  }) : _initial = initial ?? _factsSet;
  final ChatBatch Function() _initial;
  final ThreadWorkspace? workspace;
  final ConversationReader Function(String threadId)? readerFactory;
  final feeds = <ScriptedConversationFeed>[];
  int opens = 0;
  @override
  Future<ConversationFeed> openConversationFeed(
    String threadId, {
    required ChatScope scope,
    required ReadDemand demand,
  }) async {
    opens++;
    final feed = ScriptedConversationFeed(
      threadId: threadId,
      subscriptionId: 'facts-$opens',
      initial: _initial,
      reader: readerFactory?.call(threadId),
      state: workspace == null
          ? null
          : () => ThreadSnapshotFrame(workspace: workspace!),
    );
    feeds.add(feed);
    return feed;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unused transport capability: ${invocation.memberName}',
  );
}

/// The only supplied Children seam is a synchronous read-only resource borrow.
/// Counter values are fixture facts for mechanical Driver projection; no real
/// Children State's admission, lifecycle or layout behavior is claimed here.
final class _BorrowedChildrenDisplay implements TimelineChildrenDisplay {
  _BorrowedChildrenDisplay({
    required this.controller,
    required this.isEligible,
  });

  final ChatController controller;
  final bool Function() isEligible;

  @override
  String get parentId => 'turn-parent';
  @override
  int get generation => 71;
  @override
  bool get isCurrent => isEligible();
  @override
  bool get ready => true;
  @override
  String? get olderCursor => 'opaque-child-before';
  @override
  bool get loadingOlder => false;
  @override
  Object? get error => null;
  @override
  Iterable<Message> get messages => controller.messages;
  @override
  int get appliedSets => 7;
  @override
  int get appliedPrepends => 3;
  @override
  int get appliedAppends => 5;
}

/// Supplies only already admitted immutable values through the read-only borrow.
/// Changing these inputs tests snapshot projection, not production current
/// State's paging, revision transitions, attempts or cancellation.
final class _BorrowedCurrentDisplay implements TimelineCurrentDisplay {
  const _BorrowedCurrentDisplay({
    required this.isEligible,
    required this.turnId,
    required this.activityId,
    required this.collections,
    required this.windows,
  });
  final bool Function() isEligible;
  @override
  bool get isCurrent => isEligible();
  @override
  final String? turnId;
  @override
  final String? activityId;
  @override
  bool get expanded => true;
  @override
  final Iterable<TimelineCurrentCollectionDisplay> collections;
  @override
  final Iterable<TimelineCurrentWindowDisplay> windows;
}

final class _BorrowedCurrentCollection
    implements TimelineCurrentCollectionDisplay {
  _BorrowedCurrentCollection({
    required this.reference,
    required this.generation,
    this.page,
    this.error,
  });
  @override
  bool isCurrent = true;
  @override
  final CurrentCollectionRef reference;
  @override
  final int generation;
  @override
  bool get expanded => true;
  @override
  bool get loading => false;
  @override
  final Object? error;
  @override
  CurrentCollectionPage? page;
}

final class _BorrowedCurrentWindow implements TimelineCurrentWindowDisplay {
  const _BorrowedCurrentWindow({
    required this.id,
    required this.reference,
    required this.offset,
    this.window,
    this.error,
  });
  @override
  final String id;
  @override
  final ContentRef reference;
  @override
  final int offset;
  @override
  final ContentWindow? window;
  @override
  final Object? error;
}

/// Script only the original reader's IO result. The SDK and Main owner still
/// perform the real serialized Prepend admission and operation accounting.
final class _DiagnosticReader extends Fake implements ConversationReader {
  _DiagnosticReader(this.threadId);
  @override
  final String threadId;
  final entered = Completer<void>();
  Completer<ChatBatch> reply = Completer<ChatBatch>();
  final boundaries = <String>[];
  int queryCalls = 0;
  int closeCalls = 0;
  int requestCloseCalls = 0;

  @override
  Future<ChatBatch> loadOlder({
    required String before,
    required ReadDemand demand,
  }) {
    queryCalls++;
    boundaries.add(before);
    if (!entered.isCompleted) entered.complete();
    return reply.future;
  }

  @override
  void requestClose() => requestCloseCalls++;
  @override
  Future<void> close() async {
    closeCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    queryCalls++;
    throw UnsupportedError(
      'Unexpected diagnostic IO: ${invocation.memberName}',
    );
  }
}

Map<String, Object?> _attachment(ThreadAttachmentView value) => {
  'id': value.id,
  'modality': value.modality.name,
  'mediaType': value.mediaType,
  'byteSize': value.byteSize,
  'filename': value.filename,
};
ChatAtom _textItem(
  String id,
  String channel, {
  int? sealedAt,
  List<ThreadAttachmentView> attachments = const [],
}) => chatEnvelope(
  id,
  type: 'text',
  sealedAt: sealedAt,
  data: {
    'channel': channel,
    'attachments': attachments.map(_attachment).toList(),
    'outcome': {
      'kind': 'completed',
      'data': {'completedAt': 1767225600},
    },
  },
  bodies: [inlineBody('body', 'body-$id')],
);
ChatAtom _toolItem(
  String id, {
  String name = 'ask_user',
  String result = '',
  Map<String, Object?>? userInput,
  List<Map<String, Object?>> bodies = const [],
  List<ThreadAttachmentView> attachments = const [],
}) => chatEnvelope(
  id,
  type: 'tool',
  data: {
    'invocation': {
      'toolCallId': id,
      'callId': id,
      'name': name,
      'presentationContract': 'generic@1',
    },
    'state': {
      'kind': 'succeeded',
      'completedAt': 1767225600,
      'output': {'attachments': attachments.map(_attachment).toList()},
    },
    'userInput': ?userInput,
  },
  bodies: [
    inlineBody('tool.arguments', '{}'),
    inlineBody('tool.result', result),
    ...bodies,
  ],
);
Map<String, Object?> _input(String interactionId, String questionId) => {
  'interactionId': interactionId,
  'questions': [
    {'id': questionId, 'isSecret': false, 'optionCount': 0},
  ],
  'state': {
    'kind': 'resolved',
    'answers': [
      {'questionId': questionId, 'answerCount': 1, 'redacted': false},
    ],
  },
};
ChatBatch _factsSet() => chatBatch([
  _textItem('cm', 'commentary'),
  _textItem('fa', 'final', sealedAt: 1767225600),
  _toolItem('tool'),
  _toolItem(
    'qa-normal',
    userInput: _input('normal', 'q1'),
    bodies: [inlineBody('tool.user-input.answer.0.0', 'A')],
  ),
  chatEnvelope(
    'plan-cancelled',
    type: 'plan',
    data: const {'interactionId': 'cancelled', 'decision': 'cancelled'},
    bodies: [inlineBody('plan.document', '# Cancelled plan')],
  ),
  chatEnvelope(
    'plan-approved',
    type: 'plan',
    data: const {
      'interactionId': 'approved',
      'decision': 'approved',
      'documentVersion': 7,
      'contentHash': 'recorded-approved-hash',
    },
    bodies: [
      inlineBody('plan.document', '# Approved plan'),
      inlineBody('plan.feedback', '  historical feedback\n'),
    ],
  ),
  _toolItem(
    'qa-plan-legacy',
    userInput: _input('plan-legacy', agentSessionPlanConfirmationQuestionId),
    bodies: [
      inlineBody('tool.user-input.answer.0.0', agentSessionPlanApproveAnswer),
    ],
  ),
  chatEnvelope(
    'turn-completed',
    type: 'turn',
    data: const {
      'outcome': {
        'kind': 'completed',
        'data': {'startedAt': null, 'completedAt': 1, 'completion': 'normal'},
      },
    },
  ),
], current: chatCurrent());

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
ChatBatch _attachmentSet() => chatBatch([
  _textItem('user', 'user', attachments: const [_userImage, _userFile]),
  _toolItem(
    'tool-output',
    name: 'bash',
    result: 'ok',
    attachments: const [_toolImage, _toolVideo],
  ),
], current: chatCurrent());

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
