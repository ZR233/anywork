import 'package:anywork/src/app/routing/app_route.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/domain/models/studio_models.dart';
import 'package:anywork/src/features/conversation/acp/connectors/acp_composer_connector.dart';
import 'package:anywork/src/features/conversation/acp/connectors/acp_start_composer_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/tool_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/tools/items/plan/plan_transition_tool_item.dart';
import 'package:anywork/src/features/conversation/timeline/tools/support/tool_detail_values.dart';
import 'package:anywork/src/features/conversation/timeline/tools/tool_item_adapter.dart';
import 'package:anywork/src/features/conversation/workspace/conversation_workspace.dart';
import 'package:anywork/src/features/status/session_selectors.dart';
import 'package:anywork/src/features/status/workflow_graph_panel.dart';
import 'package:anywork/src/features/todo/todo_panel.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/l10n/app_localizations_zh.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/acp_sessions.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'acp_components_support.dart';

WorkflowRuntimeGraphSnapshotView _autoGraph() =>
    const WorkflowRuntimeGraphSnapshotView(
      modeId: 'mode.auto',
      modeDisplayName: '自动',
      modeDeleted: false,
      initialStateId: 'triage',
      states: [
        WorkflowRuntimeGraphStateView(
          id: 'triage',
          title: '评估分流',
          kind: WorkflowStateKind.atomic,
        ),
        WorkflowRuntimeGraphStateView(
          id: 'simple',
          title: '简单处理',
          kind: WorkflowStateKind.atomic,
        ),
        WorkflowRuntimeGraphStateView(
          id: 'planning',
          title: '规划',
          kind: WorkflowStateKind.atomic,
        ),
        WorkflowRuntimeGraphStateView(
          id: 'working',
          title: '实施',
          kind: WorkflowStateKind.atomic,
        ),
        WorkflowRuntimeGraphStateView(
          id: 'completed',
          title: '已完成',
          kind: WorkflowStateKind.finalState,
        ),
      ],
      edges: [
        WorkflowRuntimeGraphEdgeView(
          id: 'triage->simple',
          sourceStateId: 'triage',
          targetStateId: 'simple',
          guard: '简单需求直接处理',
        ),
        WorkflowRuntimeGraphEdgeView(
          id: 'triage->planning',
          sourceStateId: 'triage',
          targetStateId: 'planning',
          guard: '复杂需求正式规划',
        ),
        WorkflowRuntimeGraphEdgeView(
          id: 'simple->planning',
          sourceStateId: 'simple',
          targetStateId: 'planning',
          guard: '复杂度升级转入规划',
        ),
        WorkflowRuntimeGraphEdgeView(
          id: 'simple->completed',
          sourceStateId: 'simple',
          targetStateId: 'completed',
          guard: '直接完成',
        ),
        WorkflowRuntimeGraphEdgeView(
          id: 'planning->working',
          sourceStateId: 'planning',
          targetStateId: 'working',
          guard: '规划完成开始实施',
        ),
        WorkflowRuntimeGraphEdgeView(
          id: 'working->completed',
          sourceStateId: 'working',
          targetStateId: 'completed',
          guard: '实施完成',
        ),
      ],
    );

void main() {
  testWidgets('SessionModeSelector 菜单包含分割线与「添加模式」并跳转到设置工作模式页', (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Center(
              child: SessionModeSelector(
                catalog: const ThreadModeCatalogView(
                  modes: [
                    ThreadModeDescriptorView(
                      id: 'mode.auto',
                      displayName: '自动',
                      description: '自动工作流',
                      order: 0,
                      hasWorkflow: true,
                    ),
                  ],
                ),
                mode: ThreadModeId.auto,
                onSelected: (_) {},
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/settings',
          name: SettingsRoute.name,
          builder: (context, state) => Scaffold(
            key: const ValueKey('settings-destination'),
            body: Text('section:${state.uri.queryParameters['section']}'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        locale: const Locale('zh'),
        theme: pureStudioTheme(),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(StudioDriverKeys.sessionMode));
    await tester.pumpAndSettle();

    expect(find.byType(Divider), findsOneWidget);
    final addItem = find.byKey(const ValueKey('session-mode-add'));
    expect(addItem, findsOneWidget);
    expect(find.text('添加模式'), findsOneWidget);

    await tester.tap(addItem);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('settings-destination')), findsOneWidget);
    expect(find.text('section:work-modes'), findsOneWidget);
  });

  testWidgets('WorkflowStatusPill 展开纵向工作流图面板并与 TodoPanel 互斥', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final graph = _autoGraph();
    final run = WorkflowRunView(
      lineageId: 'lin-1',
      runId: 'run-1',
      modeId: 'mode.auto',
      graphRevision: 1,
      graphHash: 'hash',
      currentStateId: 'planning',
      currentStateTitle: '规划',
      modeDisplayName: '自动',
      visitedStateIds: const ['triage', 'simple'],
      lastTransitionForced: true,
      terminal: false,
      startedAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    const todo = TimelineTodoListUpdate(
      callId: 'todo-1',
      items: [TimelineTodoItem(step: '验证状态恢复', status: 'inProgress')],
    );

    var showWorkflow = false;
    var showTodo = true;

    await tester.pumpWidget(
      acpTestApp(
        StatefulBuilder(
          builder: (context, setState) {
            final entries = <ConversationSidebarPanelEntry>[
              ConversationSidebarPanelEntry(
                kind: ConversationSidebarPanelKind.workflow,
                icon: Icons.account_tree_outlined,
                label: '工作流',
                builder: (_) => WorkflowGraphPanel(graph: graph, run: run),
              ),
              ConversationSidebarPanelEntry(
                kind: ConversationSidebarPanelKind.todo,
                icon: Icons.checklist_outlined,
                label: '待办',
                builder: (_) => TodoPanel(todo: todo),
              ),
            ];
            final activeKind = showWorkflow
                ? ConversationSidebarPanelKind.workflow
                : ConversationSidebarPanelKind.todo;
            final showSidebar = showWorkflow || showTodo;
            return ConversationWorkspaceShell(
              readingArea: const SizedBox.expand(),
              footerDockBuilder: (_, _) => const SizedBox.shrink(),
              statusBar: SizedBox(
                height: 44,
                child: Row(
                  children: [
                    WorkflowStatusPill(
                      stateTitle: '规划',
                      modeName: '自动',
                      expanded: showWorkflow,
                      onTap: () => setState(() {
                        showWorkflow = !showWorkflow;
                        if (showWorkflow) showTodo = false;
                      }),
                    ),
                  ],
                ),
              ),
              sidebarBuilder: !showSidebar
                  ? null
                  : (_, presentation) => ConversationRightSidebar(
                      entries: entries,
                      activeKind: activeKind,
                      presentation: presentation,
                      onSelectKind: (kind) => setState(() {
                        showWorkflow =
                            kind == ConversationSidebarPanelKind.workflow;
                        showTodo = kind == ConversationSidebarPanelKind.todo;
                      }),
                      onCollapse: () => setState(() {
                        showWorkflow = false;
                        showTodo = false;
                      }),
                    ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('todo-side-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('workflow-graph-panel')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('workflow-status-pill')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('todo-side-panel')), findsNothing);
    expect(find.byKey(const ValueKey('workflow-graph-panel')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('workflow-graph-node-triage')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workflow-graph-node-planning')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workflow-graph-current-planning')),
      findsOneWidget,
    );
    expect(find.text('强制切换'), findsOneWidget);
    expect(find.text('已走过'), findsNWidgets(2));
    // Verify triage is rendered vertically above planning.
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('workflow-graph-node-triage')))
          .dy,
      lessThan(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('workflow-graph-node-planning')),
            )
            .dy,
      ),
    );

    await tester.tap(find.byKey(StudioDriverKeys.rightSidebarCollapse));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workflow-graph-panel')), findsNothing);
  });

  testWidgets('ACP 起始页与对话 Composer 底栏首项展示模式选择器', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final harness = await AcpComponentHarness.create();
    addTearDown(() => harness.close(tester));

    harness.emit(
      AcpWorkflowStateUpdatedEventView(
        AcpWorkflowStateView(
          modeId: 'mode.auto',
          modeDisplayName: '自动',
          graph: _autoGraph(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      harness.scope(
        Column(
          children: const [
            Expanded(
              child: AcpStartComposerConnector(workspaceId: 'workspace'),
            ),
            Expanded(child: AcpComposerConnector(threadId: 'thread')),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(StudioDriverKeys.sessionMode), findsNWidgets(2));
    expect(find.text('自动'), findsWidgets);

    final startModeLeft = tester
        .getTopLeft(find.byKey(StudioDriverKeys.sessionMode).first)
        .dx;
    final startServiceLeft = tester
        .getTopLeft(find.byKey(StudioDriverKeys.model).first)
        .dx;
    expect(startModeLeft, lessThan(startServiceLeft));
  });

  test('PlanTransitionToolItem 映射 builtin.plan_transition@1 与 force 字段', () {
    final l10n = AppLocalizationsZh();
    const adapter = PlanTransitionToolItem();
    const presentation = TimelineToolPresentation(
      id: 'plan-1',
      toolCallId: 'call-1',
      name: 'plan_transition',
      presentationContract: 'builtin.plan_transition@1',
      statusString: 'succeeded',
      arguments: '{"targetState":"awaitingConfirmation","force":true,"reason":"按计划推进","content":"# Plan"}',
      output: '{"state":"awaitingConfirmation","forced":true}',
    );

    expect(
      adapter.matcher.matches(
        TimelineToolMatchContext.fromPresentation(presentation),
      ),
      isTrue,
    );
    expect(
      adapter.displayName(l10n, presentation),
      l10n.timelineToolNamePlanTransition,
    );
    final inputs = adapter.input(l10n, presentation.arguments);
    expect(
      inputs.whereType<ToolDetailText>().any(
        (detail) => detail.title == l10n.timelineToolDetailTargetPhase,
      ),
      isTrue,
    );
    expect(
      inputs.whereType<ToolDetailText>().any(
        (detail) =>
            detail.title == l10n.timelineToolDetailForceTransition &&
            detail.text == 'true',
      ),
      isTrue,
    );
    final outputs = adapter.output(l10n, {
      'state': 'awaitingConfirmation',
      'forced': true,
    });
    expect(
      outputs.whereType<ToolDetailText>().any(
        (detail) => detail.title == l10n.timelineToolDetailForceTransition,
      ),
      isTrue,
    );
  });
}
