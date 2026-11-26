import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/domain/models/studio_models.dart';
import 'package:anywork/src/features/conversation/acp/connectors/acp_workspace_connector.dart';
import 'package:anywork/src/features/shell/studio_shell.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/platform/host_app_icons.dart';
import 'package:anywork/src/platform/terminal_launcher.dart';
import 'package:anywork/src/platform/vscode_launcher.dart';
import 'package:anywork/src/platform/zed_launcher.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/acp_sessions.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/chat_fixtures.dart';
import '../support/pump_client_future.dart';
import '../support/recording_demo_transport.dart';
import '../support/test_app_lifecycle.dart';
import '../support/test_statistics_feed.dart';
import 'acp_components_support.dart';

void main() {
  testWidgets('workspace menu restores focus and opens the selected path', (
    tester,
  ) async {
    final graph = testAppGraph(
      transport: RecordingDemoTransport(),
      clientId: 'workspace-menu-shell',
      statisticsFeed: const TestStatisticsFeedPort(),
    );
    addTearDown(() => _closeGraph(tester, graph));
    const project = StudioProject(id: 'project', name: 'Demo', path: '/root');
    final row = SessionDirectoryRow(
      sessionId: 'session',
      agentId: 'root-agent',
      threadId: 'root-thread',
      workspaceId: project.id,
      title: 'Demo session',
      mode: null,
      delegationMode: DelegationMode.automatic,
      delegationPreference: DelegationPreference.fast,
      workspacePath: '/work/session',
      backend: const NativeAgentBackendView(
        config: NativeAgentConfigView(),
        status: ThreadStatusView.idle,
      ),
      updatedAt: DateTime.utc(2025),
    );
    final openedUris = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appGraphProvider.overrideWithValue(graph),
          vsCodeAvailabilityProvider.overrideWith((ref) async => true),
          zedAvailabilityProvider.overrideWith((ref) async => false),
          terminalAvailabilityProvider.overrideWith((ref) async => false),
          hostAppIconProvider.overrideWith((ref, app) async => null),
          vsCodeLauncherProvider.overrideWith(
            (ref) =>
                (uri) async => openedUris.add(uri),
          ),
        ],
        child: MaterialApp(
          theme: pureStudioTheme(),
          localizationsDelegates: [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SessionHeader(
              state: HeaderView(
                selectedRootRow: row,
                selectedProject: project,
                selectedProjectId: project.id,
                workspaceRows: [row],
                agents: const [],
                selectedThreadId: row.threadId,
                runtime: const ThreadRuntimeView(
                  modelId: '',
                  contextTokens: 0,
                  contextWindow: 0,
                  totalTokens: 0,
                  costLabel: '',
                  activeSkills: [],
                  activeMcpServers: [],
                  activeLspServers: [],
                ),
                sessionCost: null,
                pendingInteractions: const [],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final trigger = find.byKey(StudioDriverKeys.sessionOpenWorkspaceMenu);
    final vsCode = find.byKey(StudioDriverKeys.sessionOpenWorkspaceVsCode);
    final zed = find.byKey(StudioDriverKeys.sessionOpenWorkspaceZed);
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    expect(vsCode, findsOneWidget);
    expect(tester.widget<MenuItemButton>(zed).onPressed, isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(vsCode, findsNothing);
    expect(openedUris, isEmpty);
    expect(tester.widget<TextButton>(trigger).focusNode?.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.tap(vsCode);
    await tester.pumpAndSettle();
    expect(openedUris, [Uri.directory('/work/session').toString()]);
    expect(vsCode, findsNothing);
  });

  testWidgets('Native workspace opens Todo and retries its workflow graph', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const threadId = 'thread-main';
    const stageId = 'native-workflow-stage';
    final transport = _NativeGraphTransport(_graphSnapshot(stageId));
    final graph = testAppGraph(
      transport: transport,
      clientId: 'workflow-workspace-shell',
      statisticsFeed: const TestStatisticsFeedPort(),
    );
    addTearDown(() => _closeGraph(tester, graph));
    await pumpClientFuture(tester, graph.client.bootstrap(), 'bootstrap');
    graph.timeline.updateReadDemand(chatDemand);
    graph.setConversationPageVisible(true);
    await pumpClientFuture(
      tester,
      graph.client.directoryCommands.selectThread(threadId),
      'select Native workflow thread',
    );
    await pumpClientFuture(
      tester,
      graph.client.conversations.visibleThreadId.waitFor(
        (id) => id == threadId,
      ),
      'admit the selected Native thread',
    );
    final session = graph.client.conversations.existingSession(threadId)!;
    await pumpClientFuture(
      tester,
      session.source.waitFor((state) => state.hasSnapshot),
      'initial Current State',
    );
    final revision = session.state.revision + 1;
    transport.seedConversationState(
      threadId,
      (current) => current.copyWith(
        runtime: current.runtime.copyWith(
          deferred: [],
          workflow: WorkflowRuntimeView(
            revision: revision,
            currentRun: WorkflowRunView(
              lineageId: 'graph-lineage',
              runId: 'graph-run',
              modeId: 'mode.auto',
              graphRevision: 1,
              graphHash: 'frozen-graph',
              currentStateId: stageId,
              currentStateTitle: 'Native workflow stage',
              terminal: false,
              startedAt: DateTime.utc(2025),
              updatedAt: DateTime.utc(2025),
            ),
          ),
        ),
        todo: const TimelineTodoListUpdate(
          callId: 'native-todo',
          items: [
            TimelineTodoItem(step: 'Native workspace todo', status: 'pending'),
          ],
        ),
      ),
    );
    await pumpClientFuture(
      tester,
      session.source.waitFor(
        (state) =>
            state.workflow?.currentRun?.currentStateId == stageId &&
            state.workspace?.todo?.callId == 'native-todo',
      ),
      'workflow enters SessionMeta',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appGraphProvider.overrideWithValue(graph)],
        child: MaterialApp(
          locale: const Locale('en'),
          theme: pureStudioTheme(),
          localizationsDelegates: [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: AgentWorkspacePane(threadId: threadId)),
        ),
      ),
    );
    final todo = find.byKey(const ValueKey('todo-open-button'));
    await pumpClientUntil(
      tester,
      () => todo.evaluate().isNotEmpty,
      'workspace Todo entry',
    );
    await tester.tap(todo);
    await pumpClientUntil(
      tester,
      () => find.text('Native workspace todo').evaluate().isNotEmpty,
      'workspace Todo panel',
    );

    expect(transport.graphRequests, isEmpty);
    await tester.tap(find.byKey(const ValueKey('workflow-status-pill')));
    final failure = find.text('Failed to load workflow graph');
    await pumpClientUntil(
      tester,
      () => failure.evaluate().isNotEmpty,
      'workflow graph failure',
    );
    expect(find.byKey(const ValueKey('todo-side-panel')), findsNothing);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Retry'));
    final active = find.byKey(
      const ValueKey('workflow-graph-current-$stageId'),
    );
    await pumpClientUntil(
      tester,
      () => active.evaluate().isNotEmpty,
      'recovered workflow graph active node',
    );
    expect(transport.graphRequests, [threadId, threadId]);
    expect(failure, findsNothing);
  });

  testWidgets('ACP workspace opens its observed workflow graph', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final harness = await AcpComponentHarness.create();
    addTearDown(() => harness.close(tester));
    const stageId = 'acp-workflow-stage';
    harness.emit(
      AcpWorkflowStateUpdatedEventView(
        AcpWorkflowStateView(
          modeId: 'mode.auto',
          graph: _graphSnapshot(stageId),
        ),
      ),
    );
    await tester.pumpWidget(
      harness.scope(const AcpWorkspaceConnector(threadId: 'thread')),
    );
    final pill = find.byKey(const ValueKey('workflow-status-pill'));
    await pumpClientUntil(
      tester,
      () => pill.evaluate().isNotEmpty,
      'ACP workflow entry',
    );
    expect(find.byKey(const ValueKey('workflow-graph-panel')), findsNothing);
    await tester.tap(pill);
    final node = find.byKey(const ValueKey('workflow-graph-node-$stageId'));
    await pumpClientUntil(
      tester,
      () => node.evaluate().isNotEmpty,
      'ACP canonical workflow graph node',
    );
    expect(tester.takeException(), isNull);
  });
}

WorkflowRuntimeGraphSnapshotView _graphSnapshot(String stateId) =>
    WorkflowRuntimeGraphSnapshotView(
      modeId: 'mode.auto',
      modeDisplayName: 'Auto',
      modeDeleted: false,
      initialStateId: stateId,
      states: [
        WorkflowRuntimeGraphStateView(
          id: stateId,
          title: 'Workflow stage',
          kind: WorkflowStateKind.atomic,
        ),
      ],
      edges: const [],
    );

Future<void> _closeGraph(WidgetTester tester, AppGraph graph) async {
  await tester.pumpWidget(const SizedBox.shrink());
  final report = await pumpClientFuture(
    tester,
    graph.close(budget: testCloseBudget()),
    'close shell test graph',
  );
  expect(report.complete, isTrue, reason: describeTestCloseReport(report));
}

final class _NativeGraphTransport extends RecordingDemoTransport {
  _NativeGraphTransport(this.graph);

  final WorkflowRuntimeGraphSnapshotView graph;
  final graphRequests = <String>[];

  @override
  Future<WorkflowRuntimeGraphSnapshotView?> getThreadWorkflowGraph(
    String threadId,
  ) async {
    graphRequests.add(threadId);
    if (graphRequests.length == 1) {
      throw StateError('Scripted workflow graph failure');
    }
    return graph;
  }
}
