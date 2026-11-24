import 'package:flutter/widget_previews.dart';
import 'package:material_ui/material_ui.dart';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/app/theme/studio_tokens.dart';
import 'package:anywork/src/domain/models/studio_models.dart'
    hide PlanConfirmationView;
import 'package:anywork/src/features/conversation/acp/acp_views.dart';
import 'package:anywork/src/features/conversation/composer/views/composer_dock_view.dart';
import 'package:anywork/src/features/conversation/interactions/views/plan_confirmation_view.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/file_reading_panel.dart';
import 'package:anywork/src/features/conversation/timeline/views/plan_detail_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/plan_summary_card.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_markdown.dart';
import 'package:anywork/src/features/conversation/workspace/conversation_workspace.dart';
import 'package:anywork/src/features/status/context_usage_readout.dart';
import 'package:anywork/src/features/status/status_bar_item.dart';
import 'package:anywork/src/features/status/thread_status_bar.dart';
import 'package:anywork/src/features/status/workflow_graph_panel.dart';
import 'package:anywork/src/features/todo/todo_panel.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/composer_action_button.dart';
import 'package:anywork/src/shared/conversation_composer.dart';
import 'package:anywork/src/shared/studio_chrome.dart';

const _planMarkdown = '''
# 统一会话工作区与右侧可收缩边栏方案

将工作流图、实施计划、Markdown 文档阅读、Todo 与 ACP 执行步骤收拢到同一右侧可收缩边栏组件，底部状态栏横贯全宽。

## 关键布局规则

- 底部 `38px` 状态栏横贯工作区全宽，不受边栏展开影响。
- 并排模式（`>= 701px`）右侧边栏向下延伸至状态栏顶部，把时间线、实时状态与输入区／确认栏一并压缩到左列。
- **待确认 Plan** 默认采用全展开 + 下方确认栏（`expanded` + `keepFooterBelow`），其余面板默认右侧并排（`split` + `coverAll`）。
- 清理重复面板标题与二级说明段落，用单行页签、状态徽章与进度图标直接传达状态。

## 验证清单

1. 宽屏并排、全宽切换与分隔条拖动／双击复位。
2. 窄窗（`< 701px`）半透明遮罩浮层停靠在状态栏上方。
3. Native 与 ACP 会话共用同一壳层与开关入口。
''';

const _docMarkdown = '''
# architecture-notes.md

## 组件边界

`ConversationWorkspaceShell` 只管理空间划分与状态保留，不拥有业务领域状态：

| 插槽 | 行为说明 | 默认布局 |
| :--- | :--- | :--- |
| Workflow | 纵向拓扑图，右下角自适应居中 | Split |
| Plan (待确认) | 保留确认反馈栏于正文下方 | Expanded |
| Markdown File | 独立文件页签，关闭恢复原页签 | Split |
| Todo / Steps | 顶部 2px 进度条 + 图标状态 | Split |

> 所有几何与面板偏好均以参数驱动，无硬编码面板特例。
''';

final _workflowGraph = WorkflowRuntimeGraphSnapshotView(
  modeId: 'mode.auto',
  modeDisplayName: '自动工作流',
  modeDeleted: false,
  initialStateId: 'triage',
  states: const [
    WorkflowRuntimeGraphStateView(
      id: 'triage',
      title: '需求分流',
      kind: WorkflowStateKind.atomic,
    ),
    WorkflowRuntimeGraphStateView(
      id: 'planning',
      title: '方案规划',
      kind: WorkflowStateKind.atomic,
    ),
    WorkflowRuntimeGraphStateView(
      id: 'implement',
      title: '代码重构',
      kind: WorkflowStateKind.atomic,
    ),
    WorkflowRuntimeGraphStateView(
      id: 'verify',
      title: '测试验收',
      kind: WorkflowStateKind.finalState,
    ),
  ],
  edges: const [
    WorkflowRuntimeGraphEdgeView(
      id: 'triage->planning',
      sourceStateId: 'triage',
      targetStateId: 'planning',
      guard: '架构重塑需要方案确认',
    ),
    WorkflowRuntimeGraphEdgeView(
      id: 'planning->implement',
      sourceStateId: 'planning',
      targetStateId: 'implement',
      guard: 'Plan 批准后执行',
    ),
    WorkflowRuntimeGraphEdgeView(
      id: 'implement->verify',
      sourceStateId: 'implement',
      targetStateId: 'verify',
      guard: '测试与截图通过',
    ),
  ],
);

final _workflowRun = WorkflowRunView(
  lineageId: 'lin-preview',
  runId: 'run-preview',
  modeId: 'mode.auto',
  graphRevision: 1,
  graphHash: 'preview-hash',
  currentStateId: 'implement',
  currentStateTitle: '代码重构',
  modeDisplayName: '自动工作流',
  visitedStateIds: const ['triage', 'planning'],
  lastTransitionForced: false,
  terminal: false,
  startedAt: DateTime.utc(2026, 11, 24),
  updatedAt: DateTime.utc(2026, 11, 24),
);

const _nativeTodo = TimelineTodoListUpdate(
  callId: 'todo-preview',
  items: [
    TimelineTodoItem(
      step: '抽离 ConversationWorkspaceShell 与公共状态',
      status: 'completed',
    ),
    TimelineTodoItem(step: '清理二级标题与重复说明，统一顶栏与画布控制', status: 'completed'),
    TimelineTodoItem(step: '接入 Native 与 ACP 工作区及全宽底栏开关', status: 'inProgress'),
    TimelineTodoItem(step: '运行全量 UI 测试与多工况可视化截图验证', status: 'pending'),
  ],
);

const _acpSteps = AcpPlanCardViewState(
  completedCount: 2,
  entries: [
    AcpPlanEntryPresentation(
      content: '对齐 Host MCP 计划与嵌入式 Markdown 阅读链路',
      priority: AcpPlanPriorityKind.high,
      status: AcpPlanStatusKind.completed,
    ),
    AcpPlanEntryPresentation(
      content: '将执行步骤卡片迁移至统一右侧边栏「执行步骤」页签',
      priority: AcpPlanPriorityKind.high,
      status: AcpPlanStatusKind.completed,
    ),
    AcpPlanEntryPresentation(
      content: '在 AcpStatusBarView 补充 steps/plan 药丸与右侧展开开关',
      priority: AcpPlanPriorityKind.medium,
      status: AcpPlanStatusKind.inProgress,
    ),
    AcpPlanEntryPresentation(
      content: '执行 ACP + Native 集成验证并交付截图证据',
      priority: AcpPlanPriorityKind.low,
      status: AcpPlanStatusKind.pending,
    ),
  ],
);

final _nativeStatus = StatusBarView(
  row: SessionDirectoryRow(
    sessionId: 'preview-native',
    agentId: 'root',
    threadId: 'preview-native-thread',
    workspaceId: 'ws-pure-lang',
    title: '统一右侧边栏与会话布局重构',
    mode: null,
    delegationMode: DelegationMode.profile,
    delegationPreference: DelegationPreference.balanced,
    workspacePath: '/workspace/pure-lang',
    backend: const NativeAgentBackendView(
      config: NativeAgentConfigView(),
      status: ThreadStatusView.running,
    ),
    updatedAt: DateTime.utc(2026, 11, 24),
  ),
  accounts: const [],
  roles: const [],
  isBusy: true,
);

const _contextProjection = StudioContextProjection(
  threadId: 'preview-native-thread',
  modelId: 'claude-sonnet-4',
  contextTokens: 38400,
  contextWindow: 200000,
  maxContextWindow: 200000,
  autoCompactLimit: 160000,
  totalTokens: 52100,
  costLabel: '',
  promptTokens: 32000,
  completionTokens: 20100,
  cachedPromptTokens: 0,
  cacheWriteTokens: 0,
  reasoningTokens: 0,
  inferenceCount: 4,
  cacheUsage: CacheUsageView(),
  estimatedCosts: [],
  estimatedCacheSavings: [],
  hasUnpricedUsage: false,
  hasIncompleteUsage: false,
);

Widget _host(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('zh'),
  theme: pureStudioTheme(locale: const Locale('zh')),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, inner) =>
      ListTileTheme(data: Theme.of(context).listTileTheme, child: inner!),
  home: Scaffold(body: child),
);

Widget _compactSessionHeader(
  BuildContext context, {
  required String subtitle,
}) => DecoratedBox(
  decoration: BoxDecoration(
    color: context.colors.surface,
    border: Border(bottom: BorderSide(color: context.colors.outlineVariant)),
  ),
  child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '统一右侧边栏与会话布局重构',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        const StudioPill(label: '3 agents', tone: StudioTone.neutral),
      ],
    ),
  ),
);

Widget _nativeConversationFeed({
  bool pendingPlan = false,
  bool planOpen = false,
}) {
  return SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: StudioLayout.conversationWidth,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AcpTimelineEntryView(
              item: AcpTimelineUserMessage(
                id: 'u1',
                blocks: [
                  AcpTextBlockPresentation(
                    text:
                        '基于最新主线，重构 Native 与 ACP 的会话右侧可收缩边栏，状态栏延伸全宽并压缩左列输入与确认区。',
                  ),
                ],
              ),
            ),
            AcpTimelineEntryView(
              item: AcpTimelineAssistantMessage(
                id: 'a1',
                blocks: [
                  const AcpTextBlockPresentation(
                    text:
                        '已完成工作区壳层分析与组件收敛规划：\n\n'
                        '1. 抽离共用 `ConversationWorkspaceShell` 与 `ConversationRightSidebar`。\n'
                        '2. 底部 `38px` 状态栏横贯全宽，右侧边栏下缘贴齐状态栏顶缘。\n'
                        '3. 待确认 Plan 默认保持全展开（保留下方确认框），工作流、Markdown、Todo 与 ACP 步骤默认并排。\n\n'
                        '参考文档已附加在右侧，可随时切换页签或拖动分隔条调整宽度。',
                  ),
                ],
              ),
            ),
            if (pendingPlan)
              PlanSummaryCard(
                title: '统一会话工作区与右侧可收缩边栏方案',
                expanded: planOpen,
                onToggle: () {},
              ),
          ],
        ),
      ),
    ),
  );
}

Widget _nativeComposer(BuildContext context, bool compact) => ComposerDockView(
  compact: compact,
  additionalDiagnostics: const [],
  childInteractions: null,
  content: ConversationComposer(
    identity: 'preview-composer',
    text: '继续优化窄窗口覆盖抽屉动效与键盘 Esc 关闭交互',
    inputKey: const ValueKey('preview-composer-input'),
    onTextChanged: (_) {},
    compact: compact,
    primaryAction: ComposerActionPresentation(
      state: ComposerActionButtonState.send,
      tooltip: '发送',
      onPressed: () {},
    ),
    canAttach: true,
    configuration: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_awesome_outlined,
            size: 14,
            color: context.colors.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            '自动工作流 · Claude Sonnet 4',
            style: context.text.labelMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  ),
);

Widget _nativeStatusBar({
  bool workflowExpanded = false,
  bool planExpanded = false,
  bool showPlanEntry = true,
  bool todoExpanded = false,
  bool sidebarOpen = false,
}) => ThreadStatusBar(
  status: _nativeStatus,
  contextReadout: const ContextUsageReadout(projection: _contextProjection),
  throughputReadout: const TokenThroughputReadout(tokensPerSecond: 48),
  startedItemsEntry: const StatusBarItem(
    icon: Icons.tune_outlined,
    label: '技能 6 · MCP 2',
  ),
  workflowReadout: WorkflowStatusReadout(
    stateTitle: '代码重构',
    modeName: '自动工作流',
    expanded: workflowExpanded,
    onTap: () {},
  ),
  showTodo: true,
  todoExpanded: todoExpanded,
  onToggleTodo: () {},
  showPlanEntry: showPlanEntry,
  planExpanded: planExpanded,
  onOpenPlan: () {},
  hasSidebarPanels: true,
  sidebarOpen: sidebarOpen,
  onToggleSidebar: () {},
);

Widget _buildNativeScenario({
  required ConversationSidebarPanelKind? activeKind,
  required bool pendingPlan,
  bool expandedFull = false,
  bool includeFile = false,
}) => Builder(
  builder: (context) {
    final entries = <ConversationSidebarPanelEntry>[
      ConversationSidebarPanelEntry(
        kind: ConversationSidebarPanelKind.workflow,
        icon: Icons.account_tree_outlined,
        label: '工作流',
        defaultWidthBuilder: (w) => (w * 0.36).clamp(360.0, 440.0),
        builder: (_) =>
            WorkflowGraphPanel(graph: _workflowGraph, run: _workflowRun),
      ),
      ConversationSidebarPanelEntry(
        kind: ConversationSidebarPanelKind.plan,
        icon: Icons.description_outlined,
        label: '计划',
        badge: PlanDetailStatusBadge(
          status: pendingPlan
              ? PlanDetailStatus.awaitingConfirmation
              : PlanDetailStatus.approved,
        ),
        defaultLayoutMode: pendingPlan
            ? ConversationSidebarLayoutMode.expanded
            : ConversationSidebarLayoutMode.split,
        expandedDockBehavior: pendingPlan
            ? ConversationExpandedDockBehavior.keepFooterBelow
            : ConversationExpandedDockBehavior.coverAll,
        defaultWidthBuilder: (w) => (w * 0.48).clamp(360.0, 620.0),
        builder: (_) => PlanDetailView(
          identity: 'preview-plan',
          body: TimelineMarkdown(
            id: 'preview-plan-md',
            text: _planMarkdown,
            onLink: (_) {},
            isSafeLink: (_) => false,
            imageBuilder: (_, _) => const SizedBox.shrink(),
          ),
        ),
      ),
      if (includeFile)
        ConversationSidebarPanelEntry(
          kind: ConversationSidebarPanelKind.file,
          icon: Icons.article_outlined,
          label: 'architecture-notes.md',
          onDismiss: () {},
          defaultWidthBuilder: (w) => (w * 0.48).clamp(360.0, 620.0),
          builder: (_) => FileDocumentView(
            identity: 'preview-doc',
            body: TimelineMarkdown(
              id: 'preview-doc-md',
              text: _docMarkdown,
              onLink: (_) {},
              isSafeLink: (_) => false,
              imageBuilder: (_, _) => const SizedBox.shrink(),
            ),
          ),
        ),
      ConversationSidebarPanelEntry(
        kind: ConversationSidebarPanelKind.todo,
        icon: Icons.checklist_outlined,
        label: '待办',
        badge: const StudioPill(label: '2/4', tone: StudioTone.brand),
        defaultWidthBuilder: (w) => (w * 0.34).clamp(340.0, 420.0),
        builder: (_) => const TodoPanel(todo: _nativeTodo),
      ),
    ];

    final activeEntry = activeKind == null
        ? null
        : entries.firstWhere((entry) => entry.kind == activeKind);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _compactSessionHeader(context, subtitle: 'pure-lang · 本地工作区 · 固定配置模板'),
        Expanded(
          child: ConversationWorkspaceShell(
            readingArea: _nativeConversationFeed(
              pendingPlan: pendingPlan,
              planOpen: activeKind == ConversationSidebarPanelKind.plan,
            ),
            scrollFooter: pendingPlan,
            footerDockBuilder: (context, compact) => pendingPlan
                ? ComposerDockView(
                    compact: compact,
                    additionalDiagnostics: const [],
                    childInteractions: null,
                    content: PlanConfirmationView(
                      interactionId: 'preview-pending-plan',
                      available: true,
                      enabled: true,
                      initialFeedback: '请保留宽屏并排时的分栏宽度记忆。',
                      error: null,
                      onSubmitRevision: (_) {},
                      onApprove: () {},
                    ),
                  )
                : _nativeComposer(context, compact),
            sidebarBuilder: activeEntry == null
                ? null
                : (_, presentation) => ConversationRightSidebar(
                    entries: entries,
                    activeKind: activeEntry.kind,
                    presentation: presentation,
                    onSelectKind: (_) {},
                    onToggleLayoutMode: () {},
                    onCollapse: () {},
                  ),
            sidebarExpanded: expandedFull,
            expandedDockBehavior: pendingPlan
                ? ConversationExpandedDockBehavior.keepFooterBelow
                : ConversationExpandedDockBehavior.coverAll,
            sidebarDefaultWidthBuilder: activeEntry?.defaultWidthBuilder,
            onCollapseSidebar: () {},
            statusBar: _nativeStatusBar(
              workflowExpanded:
                  activeKind == ConversationSidebarPanelKind.workflow,
              planExpanded: activeKind == ConversationSidebarPanelKind.plan,
              showPlanEntry: !pendingPlan,
              todoExpanded: activeKind == ConversationSidebarPanelKind.todo,
              sidebarOpen: activeEntry != null,
            ),
          ),
        ),
      ],
    );
  },
);

@Preview(
  name: '01-native-collapsed',
  group: 'UnifiedSidebar',
  size: Size(1280, 800),
)
Widget unifiedSidebar01NativeCollapsed() =>
    _host(_buildNativeScenario(activeKind: null, pendingPlan: false));

@Preview(
  name: '02-native-workflow-split',
  group: 'UnifiedSidebar',
  size: Size(1280, 800),
)
Widget unifiedSidebar02NativeWorkflowSplit() => _host(
  _buildNativeScenario(
    activeKind: ConversationSidebarPanelKind.workflow,
    pendingPlan: false,
  ),
);

@Preview(
  name: '03-native-plan-pending-expanded',
  group: 'UnifiedSidebar',
  size: Size(1280, 800),
)
Widget unifiedSidebar03NativePlanPendingExpanded() => _host(
  _buildNativeScenario(
    activeKind: ConversationSidebarPanelKind.plan,
    pendingPlan: true,
    expandedFull: true,
  ),
);

@Preview(
  name: '04-native-plan-pending-split',
  group: 'UnifiedSidebar',
  size: Size(1280, 800),
)
Widget unifiedSidebar04NativePlanPendingSplit() => _host(
  _buildNativeScenario(
    activeKind: ConversationSidebarPanelKind.plan,
    pendingPlan: true,
    expandedFull: false,
  ),
);

@Preview(
  name: '05-native-markdown-tabs',
  group: 'UnifiedSidebar',
  size: Size(1280, 800),
)
Widget unifiedSidebar05NativeMarkdownTabs() => _host(
  _buildNativeScenario(
    activeKind: ConversationSidebarPanelKind.file,
    pendingPlan: false,
    includeFile: true,
  ),
);

@Preview(
  name: '06-native-todo-split',
  group: 'UnifiedSidebar',
  size: Size(1280, 800),
)
Widget unifiedSidebar06NativeTodoSplit() => _host(
  _buildNativeScenario(
    activeKind: ConversationSidebarPanelKind.todo,
    pendingPlan: false,
  ),
);

@Preview(
  name: '07-native-workflow-full',
  group: 'UnifiedSidebar',
  size: Size(1280, 800),
)
Widget unifiedSidebar07NativeWorkflowFull() => _host(
  _buildNativeScenario(
    activeKind: ConversationSidebarPanelKind.workflow,
    pendingPlan: false,
    expandedFull: true,
  ),
);

@Preview(
  name: '08-acp-unified-sidebar',
  group: 'UnifiedSidebar',
  size: Size(1280, 800),
)
Widget unifiedSidebar08AcpUnifiedSidebar() => _host(
  Builder(
    builder: (context) {
      final acpEntries = <ConversationSidebarPanelEntry>[
        ConversationSidebarPanelEntry(
          kind: ConversationSidebarPanelKind.workflow,
          icon: Icons.account_tree_outlined,
          label: '工作流',
          defaultWidthBuilder: (w) => (w * 0.36).clamp(360.0, 440.0),
          builder: (_) =>
              WorkflowGraphPanel(graph: _workflowGraph, run: _workflowRun),
        ),
        ConversationSidebarPanelEntry(
          kind: ConversationSidebarPanelKind.plan,
          icon: Icons.description_outlined,
          label: '计划',
          badge: const PlanDetailStatusBadge(status: PlanDetailStatus.approved),
          defaultWidthBuilder: (w) => (w * 0.48).clamp(360.0, 620.0),
          builder: (_) => PlanDetailView(
            identity: 'acp-host-plan',
            body: TimelineMarkdown(
              id: 'acp-host-plan-md',
              text: _planMarkdown,
              onLink: (_) {},
              isSafeLink: (_) => false,
              imageBuilder: (_, _) => const SizedBox.shrink(),
            ),
          ),
        ),
        ConversationSidebarPanelEntry(
          kind: ConversationSidebarPanelKind.todo,
          icon: Icons.checklist_outlined,
          label: '执行步骤',
          badge: const StudioPill(label: '2/4', tone: StudioTone.brand),
          defaultWidthBuilder: (w) => (w * 0.34).clamp(340.0, 420.0),
          builder: (_) => const AcpPlanPanel(state: _acpSteps),
        ),
      ];

      final items = const [
        AcpTimelineMessageRow(
          AcpTimelineUserMessage(
            id: 'acp-u1',
            blocks: [
              AcpTextBlockPresentation(
                text: '把 ACP 执行步骤也并入统一右侧边栏，状态栏保持全宽并补充步骤与 Host MCP 计划入口。',
              ),
            ],
          ),
        ),
        AcpTimelineMessageRow(
          AcpTimelineAssistantMessage(
            id: 'acp-a1',
            blocks: [
              AcpTextBlockPresentation(
                text:
                    '已将 ACP 会话切换为复用 `ConversationWorkspaceShell` 与 `ConversationRightSidebar`：\n\n'
                    '- 原时间线顶部的吸顶 `AcpPlanCard` 改为右侧「执行步骤」面板（`AcpPlanPanel`），状态栏显示 `2/4` 药丸开关。\n'
                    '- Host MCP 初始化后的只读 `Plan` 与嵌入式 `.md` 资源均可在同一边栏页签内切换查看。',
              ),
              AcpTextResourceBlockPresentation(
                uri: 'file:///workspace/pure-lang/docs/sidebar-spec.md',
                text: '# Sidebar Spec\n\nUnified Native & ACP layout spec.',
                mimeType: 'text/markdown',
              ),
            ],
          ),
        ),
      ];

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _compactSessionHeader(context, subtitle: 'pure-lang'),
          Expanded(
            child: AcpWorkspaceView(
              readingArea: AcpConversationContentView(
                threadId: 'acp-preview',
                header: AcpTimelineHeaderViewState(
                  ready: true,
                  loading: false,
                  hasPlan: true,
                  hasConversationalContent: true,
                  itemCount: items.length,
                ),
                itemBuilder: (_, index) => AcpTimelineEntryView(
                  key: ValueKey(items[index].id),
                  item: items[index].item,
                  onOpenMarkdownResource: (_, _) {},
                ),
              ),
              composerBuilder: (_, compact) => AcpConversationComposerView(
                state: const AcpComposerViewState(
                  threadId: 'acp-preview',
                  draftText: '运行完整静态检查与 Widget 验收测试',
                  canSend: true,
                  canAttach: true,
                ),
                compact: compact,
                onDraftChanged: (_) {},
                onSubmit: () {},
                onInterrupt: () {},
                onPickLocalAttachments: (_) async {},
                onAddRemoteAttachment: (_) async {},
                onRemoveAttachment: (_) {},
              ),
              sidebarBuilder: (_, presentation) => ConversationRightSidebar(
                entries: acpEntries,
                activeKind: ConversationSidebarPanelKind.todo,
                presentation: presentation,
                onSelectKind: (_) {},
                onToggleLayoutMode: () {},
                onCollapse: () {},
              ),
              sidebarDefaultWidthBuilder: (w) => (w * 0.34).clamp(340.0, 420.0),
              onCollapseSidebar: () {},
              statusBar: AcpStatusBarView(
                status: const AcpConnectionStatusView(
                  state: AcpStatusBarViewState(
                    phase: AcpSessionStatusPhase.running,
                  ),
                ),
                workflow: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: WorkflowStatusPill(
                    stateTitle: '代码重构',
                    modeName: '自动工作流',
                    expanded: false,
                    onTap: () {},
                  ),
                ),
                plan: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(StudioRadii.sm),
                      border: Border.all(
                        color: context.colors.outlineVariant.withValues(
                          alpha: 0.65,
                        ),
                      ),
                    ),
                    child: SizedBox(
                      height: 26,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.description_outlined,
                              size: 14,
                              color: context.colors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '计划',
                              style: context.text.labelSmall?.copyWith(
                                color: context.colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                steps: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: context.colors.primaryContainer.withValues(
                        alpha: 0.45,
                      ),
                      borderRadius: BorderRadius.circular(StudioRadii.sm),
                      border: Border.all(
                        color: context.colors.primary.withValues(alpha: 0.55),
                      ),
                    ),
                    child: SizedBox(
                      height: 26,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.checklist_outlined,
                              size: 14,
                              color: context.colors.primary,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '2/4',
                              style: context.text.labelSmall?.copyWith(
                                color: context.colors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                contextUsage: AcpContextUsageView(
                  state: (
                    used: BigInt.from(54200),
                    size: BigInt.from(200000),
                    isLive: true,
                  ),
                ),
                throughput: const TokenThroughputReadout(
                  estimated: true,
                  tokensPerSecond: 64.0,
                ),
                cost: const AcpCostReadoutView(
                  state: (amount: 0.18, currency: 'USD'),
                ),
                externalHistory: const SizedBox.shrink(),
                sidebarToggle: ConversationSidebarToggleButton(
                  available: true,
                  expanded: true,
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ],
      );
    },
  ),
);

@Preview(
  name: '09-narrow-overlay',
  group: 'UnifiedSidebar',
  size: Size(640, 800),
)
Widget unifiedSidebar09NarrowOverlay() => _host(
  _buildNativeScenario(
    activeKind: ConversationSidebarPanelKind.todo,
    pendingPlan: false,
  ),
);
