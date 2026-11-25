import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/acp/acp_views.dart';
import 'package:anywork/src/features/conversation/timeline/state/patch_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/tool_presentation.dart';
import 'package:anywork/src/features/conversation/workspace/conversation_workspace.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:flutter/widget_previews.dart';
import 'package:material_ui/material_ui.dart';

Widget _shell(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: pureStudioTheme(),
  locale: const Locale('zh'),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

const _sampleSlashCommands = [
  AcpSlashCommandPresentation(
    name: 'review',
    description: '审查当前改动并总结潜在风险',
    inputHint: 'target',
  ),
  AcpSlashCommandPresentation(name: 'compact', description: '整理并压缩当前会话上下文窗口'),
  AcpSlashCommandPresentation(
    name: 'plan',
    description: '为复杂任务拆解可追踪步骤清单',
    inputHint: 'goal',
  ),
  AcpSlashCommandPresentation(name: 'clear', description: '开启一轮新的轻量上下文讨论'),
];

const _samplePlanState = AcpPlanCardViewState(
  completedCount: 1,
  entries: [
    AcpPlanEntryPresentation(
      content: '重构 ACP 过程分组与工具行，统一复用工作组外壳',
      priority: AcpPlanPriorityKind.low,
      status: AcpPlanStatusKind.completed,
    ),
    AcpPlanEntryPresentation(
      content: '上线 Myers 行级 Diff、变更统计与斜杠命令自动补全',
      priority: AcpPlanPriorityKind.high,
      status: AcpPlanStatusKind.inProgress,
    ),
    AcpPlanEntryPresentation(
      content: '运行客户端边界守卫与全量 UI 回归验证',
      priority: AcpPlanPriorityKind.medium,
      status: AcpPlanStatusKind.pending,
    ),
  ],
);

AcpTimelineProcessRow _sampleDiffProcessRow() {
  const multiHunkDoc = TimelinePatchDocument(
    files: [
      TimelinePatchFile(
        op: TimelinePatchFileOp.update,
        path: 'lib/src/features/conversation/acp/acp_session_view.dart',
        chunks: [
          TimelinePatchChunk(
            context: '@@ -3,6 +3,8 @@ class AcpSessionView',
            lines: [
              TimelinePatchLine(
                kind: TimelinePatchLineKind.context,
                text: 'class AcpSessionView {',
              ),
              TimelinePatchLine(
                kind: TimelinePatchLineKind.deletion,
                text: '  AcpSessionView({required this.id});',
              ),
              TimelinePatchLine(
                kind: TimelinePatchLineKind.addition,
                text: '  AcpSessionView({required this.id, this.title});',
              ),
              TimelinePatchLine(
                kind: TimelinePatchLineKind.context,
                text: '  final String id;',
              ),
              TimelinePatchLine(
                kind: TimelinePatchLineKind.addition,
                text: '  final String? title;',
              ),
              TimelinePatchLine(
                kind: TimelinePatchLineKind.context,
                text: '  String label() {',
              ),
              TimelinePatchLine(
                kind: TimelinePatchLineKind.deletion,
                text: '    return id;',
              ),
              TimelinePatchLine(
                kind: TimelinePatchLineKind.addition,
                text: '    return title ?? id;',
              ),
              TimelinePatchLine(
                kind: TimelinePatchLineKind.context,
                text: '  }',
              ),
            ],
          ),
          TimelinePatchChunk(
            context: '@@ -14,5 +16,5 @@ Future<void> refresh()',
            lines: [
              TimelinePatchLine(
                kind: TimelinePatchLineKind.context,
                text: '  Future<void> refresh() async {',
              ),
              TimelinePatchLine(
                kind: TimelinePatchLineKind.deletion,
                text: '    // TODO: implement refresh',
              ),
              TimelinePatchLine(
                kind: TimelinePatchLineKind.addition,
                text: '    await Future<void>.value();',
              ),
              TimelinePatchLine(
                kind: TimelinePatchLineKind.context,
                text: '  }',
              ),
            ],
          ),
        ],
      ),
    ],
  );
  return AcpTimelineProcessRow(
    id: 'ux-diff-process',
    items: [
      AcpTimelineToolCallItem(
        id: 'ux-diff-edit',
        toolCallId: 'call-diff-edit',
        status: AcpToolStatusKind.completed,
        kindLabel: 'edit',
        locations: [
          'lib/src/features/conversation/acp/acp_session_view.dart:4',
        ],
        diffs: [multiHunkDoc],
        tool: const TimelineToolPresentation(
          id: 'ux-diff-edit',
          toolCallId: 'call-diff-edit',
          name: '更新会话标题与刷新逻辑',
          presentationContract: 'acp.tool.edit',
          statusString: 'succeeded',
          arguments: '',
          output: '已更新 2 处片段。',
        ),
      ),
      const AcpTimelineToolCallItem(
        id: 'ux-diff-fail',
        toolCallId: 'call-diff-fail',
        status: AcpToolStatusKind.failed,
        kindLabel: 'execute',
        tool: TimelineToolPresentation(
          id: 'ux-diff-fail',
          toolCallId: 'call-diff-fail',
          name: 'flutter test test/ui/acp_ux_interactions_test.dart',
          presentationContract: 'acp.tool.execute',
          statusString: 'failed',
          arguments: '',
          output: '退出码 1：请先运行 generate-gui',
        ),
      ),
    ],
  );
}

@Preview(
  name: 'UX 1 · 多片段行级 Diff 与 +N -M 统计',
  group: 'ACP UX',
  size: Size(780, 620),
)
Widget acpUxMultiHunkDiffPreview() => _shell(
  SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: AcpTimelineProcessGroupView(
      row: _sampleDiffProcessRow(),
      initiallyExpanded: true,
    ),
  ),
);

@Preview(
  name: 'UX 2 · 右侧边栏步骤、空态速览与斜杠补全',
  group: 'ACP UX',
  size: Size(1040, 680),
)
Widget acpUxStickyPlanAndSlashPreview() => _shell(
  AcpWorkspaceView(
    readingArea: AcpConversationContentView(
      threadId: 'preview-slash',
      header: const AcpTimelineHeaderViewState(
        ready: true,
        loading: false,
        capabilities: [
          AcpCapabilityKind.image,
          AcpCapabilityKind.embeddedContext,
          AcpCapabilityKind.listSessions,
        ],
        availableCommands: _sampleSlashCommands,
      ),
      rows: const [],
      onInsertSlashCommand: (_) {},
      itemBuilder: (_, _) => const SizedBox.shrink(),
    ),
    sidebarBuilder: (_, presentation) => ConversationRightSidebar(
      entries: [
        ConversationSidebarPanelEntry(
          kind: ConversationSidebarPanelKind.todo,
          icon: Icons.checklist_outlined,
          label: '执行步骤',
          builder: (_) => const AcpPlanPanel(state: _samplePlanState),
        ),
      ],
      activeKind: ConversationSidebarPanelKind.todo,
      presentation: presentation,
      onSelectKind: (_) {},
      onCollapse: () {},
    ),
    composerBuilder: (_, compact) => AcpConversationComposerView(
      state: const AcpComposerViewState(
        threadId: 'preview-slash',
        draftText: '/re',
        canSend: true,
        canAttach: true,
        availableCommands: _sampleSlashCommands,
      ),
      compact: compact,
      onDraftChanged: (_) {},
      onSubmit: () {},
      onInterrupt: () {},
      onPickLocalAttachments: (_) async {},
      onAddRemoteAttachment: (_) async {},
      onRemoveAttachment: (_) {},
    ),
    statusBar: const AcpStatusBarView(
      status: AcpConnectionStatusView(
        state: AcpStatusBarViewState(phase: AcpSessionStatusPhase.ready),
      ),
      contextUsage: SizedBox.shrink(),
      cost: SizedBox.shrink(),
      externalHistory: SizedBox.shrink(),
    ),
  ),
);

Widget _conversationWithFoldAndPermission({required bool narrow}) {
  final longUserText = List.generate(
    18,
    (index) => '${index + 1}. 请排查日志片段：Stream chunk #$index 在滚动后仍保留展开状态与复制能力。',
  ).join('\n');
  final items = [
    AcpTimelineMessageRow(
      AcpTimelineUserMessage(
        id: 'u1',
        blocks: [AcpTextBlockPresentation(text: longUserText)],
      ),
    ),
    const AcpTimelineMessageRow(
      AcpTimelineAssistantMessage(
        id: 'a1',
        blocks: [
          AcpTextBlockPresentation(
            text: '已完成检查：\n- 超长用户消息默认折叠并可展开\n- 每条消息底部附带轻量复制图标\n- 下方停靠栏展示本地化类别标签与行级补丁统计',
          ),
        ],
      ),
    ),
  ];
  const dockDiff = TimelinePatchDocument(
    files: [
      TimelinePatchFile(
        op: TimelinePatchFileOp.update,
        path: 'code/anywork/lib/src/features/conversation/acp/acp_views.dart',
        chunks: [
          TimelinePatchChunk(
            context: null,
            lines: [
              TimelinePatchLine(
                kind: TimelinePatchLineKind.addition,
                text: "export 'widgets/acp_message_actions.dart';",
              ),
              TimelinePatchLine(
                kind: TimelinePatchLineKind.context,
                text: "export 'widgets/acp_plan_card.dart';",
              ),
              TimelinePatchLine(
                kind: TimelinePatchLineKind.addition,
                text: "export 'widgets/acp_slash_command_menu.dart';",
              ),
              TimelinePatchLine(
                kind: TimelinePatchLineKind.context,
                text: "export 'widgets/acp_tool_card.dart';",
              ),
            ],
          ),
        ],
      ),
    ],
  );
  return AcpWorkspaceView(
    readingArea: AcpConversationContentView(
      threadId: narrow ? 'preview-narrow' : 'preview-wide',
      header: const AcpTimelineHeaderViewState(
        ready: true,
        loading: false,
        hasConversationalContent: true,
      ),
      rows: items,
      itemBuilder: (context, row) =>
          AcpTimelineEntryView(item: (row as AcpTimelineMessageRow).item),
    ),
    sidebarBuilder: narrow
        ? null
        : (_, presentation) => ConversationRightSidebar(
            entries: [
              ConversationSidebarPanelEntry(
                kind: ConversationSidebarPanelKind.todo,
                icon: Icons.checklist_outlined,
                label: '执行步骤',
                builder: (_) => const AcpPlanPanel(state: _samplePlanState),
              ),
            ],
            activeKind: ConversationSidebarPanelKind.todo,
            presentation: presentation,
            onSelectKind: (_) {},
            onCollapse: () {},
          ),
    permissionDock: AcpPermissionDock(
      state: AcpPermissionDockViewState(
        pendingCount: 2,
        activeRequest: AcpPermissionRequestPresentation(
          id: 'perm-1',
          title: '应用代码修改到 acp_views.dart',
          kindLabel: 'edit',
          locations: [
            'code/anywork/lib/src/features/conversation/acp/acp_views.dart:11',
          ],
          diffs: [dockDiff],
          options: const [
            AcpPermissionOptionPresentation(
              optionId: 'allow-once',
              name: '仅此次允许',
              tone: AcpPermissionOptionTone.allowOnce,
            ),
            AcpPermissionOptionPresentation(
              optionId: 'allow-always',
              name: '本会话总是允许',
              tone: AcpPermissionOptionTone.allowAlways,
            ),
            AcpPermissionOptionPresentation(
              optionId: 'reject-once',
              name: '拒绝',
              tone: AcpPermissionOptionTone.rejectOnce,
            ),
          ],
        ),
      ),
      onSelectOption: (_, _) {},
      onCancel: (_) {},
    ),
    composerBuilder: (_, compact) => AcpConversationComposerView(
      state: const AcpComposerViewState(
        threadId: 'preview-ux',
        canSend: true,
        isRunning: true,
        canInterrupt: true,
      ),
      compact: compact,
      onDraftChanged: (_) {},
      onSubmit: () {},
      onInterrupt: () {},
      onPickLocalAttachments: (_) async {},
      onAddRemoteAttachment: (_) async {},
      onRemoveAttachment: (_) {},
    ),
    statusBar: const AcpStatusBarView(
      status: AcpConnectionStatusView(
        state: AcpStatusBarViewState(phase: AcpSessionStatusPhase.running),
      ),
      contextUsage: SizedBox.shrink(),
      cost: SizedBox.shrink(),
      externalHistory: SizedBox.shrink(),
    ),
  );
}

@Preview(name: 'UX 3 · 展开计划、长消息折叠与本地化审批', group: 'ACP UX', size: Size(880, 980))
Widget acpUxConversationAndPermissionPreview() =>
    _shell(_conversationWithFoldAndPermission(narrow: false));

@Preview(
  name: 'UX 4 · 窄窗大字适配',
  group: 'ACP UX',
  size: Size(360, 760),
  textScaleFactor: 1.6,
)
Widget acpUxNarrowAccessibilityPreview() =>
    _shell(_conversationWithFoldAndPermission(narrow: true));

@Preview(name: 'UX 5 · 外部历史会话搜索与过滤', group: 'ACP UX', size: Size(760, 560))
Widget acpUxExternalHistorySearchPreview() => _shell(
  AcpExternalHistoryDialog(
    state: const AcpExternalHistoryDialogState(
      availability: AcpExternalHistoryAvailability.available,
      canLoad: true,
      canResume: true,
      nextCursor: 'cursor-2',
      sessions: [
        AcpExternalSessionRowPresentation(
          sessionId: 'sess-diff-01',
          title: '重构 ACP Myers 行级 Diff 与变更统计',
          cwd: '/home/zhourui/worktrees/anywork',
          updatedAt: '2026-11-24 13:10',
        ),
        AcpExternalSessionRowPresentation(
          sessionId: 'sess-slash-02',
          title: '实现输入框 / 斜杠命令补全菜单',
          cwd: '/home/zhourui/worktrees/anywork',
          updatedAt: '2026-11-24 12:45',
        ),
        AcpExternalSessionRowPresentation(
          sessionId: 'sess-plan-03',
          title: '吸顶执行计划条与权限审批本地化',
          cwd: '/home/zhourui/worktrees/anywork_docs',
          updatedAt: '2026-11-23 19:20',
        ),
      ],
    ),
    onRefresh: () {},
    onLoadMore: () {},
    onLoadSession: (_) {},
    onResumeSession: (_) {},
    onClose: () {},
  ),
);
