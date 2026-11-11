import 'package:flutter/widget_previews.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/material3_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../timeline/state/patch_presentation.dart';
import '../../timeline/state/tool_presentation.dart';
import '../acp_views.dart';

Widget _acpPreviewShell(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: pureStudioTheme(),
  locale: const Locale('zh'),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
);

const List<AcpConfigControlPresentation> _sampleControls = [
  AcpConfigControlPresentation.select(
    id: 'server-quality',
    name: '回答方式',
    description: '来自智能体服务的配置说明，不依赖固定的模型或 effort',
    category: AcpConfigCategoryKind.mode,
    currentValue: 'careful',
    currentLabel: '仔细分析',
    groups: [
      AcpSelectGroupPresentation(
        id: 'quality',
        name: '质量',
        options: [
          AcpSelectChoicePresentation(
            value: 'careful',
            name: '仔细分析',
            description: '适合架构规划与复杂代码调整',
          ),
          AcpSelectChoicePresentation(
            value: 'quick',
            name: '快速回答',
            description: '适合简短问答与命令确认',
          ),
        ],
      ),
    ],
  ),
  AcpConfigControlPresentation.select(
    id: 'model-tier',
    name: '推理档位',
    category: AcpConfigCategoryKind.thoughtLevel,
    currentValue: 'deep',
    currentLabel: '深度思考',
    flatOptions: [
      AcpSelectChoicePresentation(value: 'standard', name: '标准'),
      AcpSelectChoicePresentation(value: 'deep', name: '深度思考'),
    ],
  ),
  AcpConfigControlPresentation.boolean(
    id: 'citations',
    name: '引用来源',
    description: '回复中附带代码与文档引用定位',
    category: AcpConfigCategoryKind.other,
    currentValue: true,
  ),
  AcpConfigControlPresentation.boolean(
    id: 'auto-verify',
    name: '自动自检',
    category: AcpConfigCategoryKind.other,
    currentValue: false,
  ),
];

@Preview(name: 'ACP 启动页创建卡片', group: 'ACP', size: Size(720, 260))
Widget acpStartComposerPreview() => _acpPreviewShell(
  AcpStartComposerView(
    state: const AcpStartComposerViewState(
      workspaceId: 'preview-workspace',
      text: '梳理当前仓库的 ACP 会话状态流转，并检查组件边界。',
      accountId: 'agy-local',
      serviceName: 'Antigravity CLI',
      brandKey: 'google',
      serviceEnabled: true,
    ),
    onDraftChanged: (_) {},
    onSubmit: () {},
  ),
);

@Preview(name: 'ACP 服务端配置栏 · 宽窗', group: 'ACP', size: Size(760, 140))
Widget acpConfigurationWidePreview() => _acpPreviewShell(
  AcpConfigurationBar(
    state: const AcpConfigurationViewState(
      controls: _sampleControls,
      enabled: true,
    ),
    onSelectValue: (_, _) {},
    onBooleanChanged: (_, _) {},
    onSelectLegacyMode: (_) {},
  ),
);

@Preview(name: 'ACP 服务端配置栏 · 窄窗收纳', group: 'ACP', size: Size(340, 160))
Widget acpConfigurationNarrowPreview() => _acpPreviewShell(
  AcpConfigurationBar(
    state: const AcpConfigurationViewState(
      controls: _sampleControls,
      enabled: true,
    ),
    onSelectValue: (_, _) {},
    onBooleanChanged: (_, _) {},
    onSelectLegacyMode: (_) {},
  ),
);

@Preview(name: 'ACP 执行计划卡片', group: 'ACP', size: Size(680, 240))
Widget acpPlanCardPreview() => _acpPreviewShell(
  const AcpPlanCard(
    state: AcpPlanCardViewState(
      completedCount: 1,
      entries: [
        AcpPlanEntryPresentation(
          content: '建立纯展示 State 与独立组件 ViewModel',
          priority: AcpPlanPriorityKind.high,
          status: AcpPlanStatusKind.completed,
        ),
        AcpPlanEntryPresentation(
          content: '接入权限停靠面板与内联配置工具栏',
          priority: AcpPlanPriorityKind.high,
          status: AcpPlanStatusKind.inProgress,
        ),
        AcpPlanEntryPresentation(
          content: '运行客户端边界静态检查与桌面集成验收',
          priority: AcpPlanPriorityKind.medium,
          status: AcpPlanStatusKind.pending,
        ),
      ],
    ),
  ),
);

@Preview(name: 'ACP 权限审批停靠面板', group: 'ACP', size: Size(720, 320))
Widget acpPermissionDockPreview() => _acpPreviewShell(
  AcpPermissionDock(
    state: const AcpPermissionDockViewState(
      pendingCount: 2,
      activeRequest: AcpPermissionRequestPresentation(
        id: '1:42',
        title: '写入 lib/src/features/conversation/acp/acp_views.dart',
        kindLabel: 'edit',
        locations: ['lib/src/features/conversation/acp/acp_views.dart:1'],
        diffs: [
          TimelinePatchDocument(
            files: [
              TimelinePatchFile(
                op: TimelinePatchFileOp.update,
                path: 'lib/src/features/conversation/acp/acp_views.dart',
                chunks: [
                  TimelinePatchChunk(
                    context: null,
                    lines: [
                      TimelinePatchLine(
                        kind: TimelinePatchLineKind.deletion,
                        text: "export 'views/acp_conversation_content.dart';",
                      ),
                      TimelinePatchLine(
                        kind: TimelinePatchLineKind.addition,
                        text: "export 'state/acp_view_state.dart';",
                      ),
                      TimelinePatchLine(
                        kind: TimelinePatchLineKind.addition,
                        text: "export 'views/acp_conversation_content_view.dart';",
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
        options: [
          AcpPermissionOptionPresentation(
            optionId: 'allow-once',
            name: '允许本次修改',
            tone: AcpPermissionOptionTone.allowOnce,
          ),
          AcpPermissionOptionPresentation(
            optionId: 'allow-always',
            name: '本会话始终允许编辑',
            tone: AcpPermissionOptionTone.allowAlways,
          ),
          AcpPermissionOptionPresentation(
            optionId: 'reject-once',
            name: '拒绝修改',
            tone: AcpPermissionOptionTone.rejectOnce,
          ),
        ],
      ),
    ),
    onSelectOption: (_, _) {},
    onCancel: (_) {},
  ),
);

@Preview(name: 'ACP 工具调用与补丁行', group: 'ACP', size: Size(680, 260))
Widget acpToolCardPreview() => _acpPreviewShell(
  const AcpToolCard(
    initiallyExpanded: true,
    item: AcpTimelineToolCallItem(
      id: 'tool-1',
      toolCallId: 'call-edit-1',
      status: AcpToolStatusKind.completed,
      kindLabel: 'edit',
      locations: ['code/anywork/lib/src/features/shell/studio_shell.dart:42'],
      tool: TimelineToolPresentation(
        id: 'call-edit-1',
        toolCallId: 'call-edit-1',
        name: '更新 ACP 工作区装配',
        presentationContract: 'acp.tool',
        statusString: 'succeeded',
        arguments: '',
        output: '',
      ),
      diffs: [
        TimelinePatchDocument(
          files: [
            TimelinePatchFile(
              op: TimelinePatchFileOp.update,
              path: 'code/anywork/lib/src/features/shell/studio_shell.dart',
              chunks: [
                TimelinePatchChunk(
                  context: null,
                  lines: [
                    TimelinePatchLine(
                      kind: TimelinePatchLineKind.deletion,
                      text:
                          'return AcpConversationContent(threadId: threadId);',
                    ),
                    TimelinePatchLine(
                      kind: TimelinePatchLineKind.addition,
                      text: 'return AcpWorkspaceConnector(threadId: threadId);',
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ),
);

@Preview(name: 'ACP 底部状态栏', group: 'ACP', size: Size(760, 80))
Widget acpStatusBarPreview() => _acpPreviewShell(
  AcpStatusBarView(
    threadId: 'preview-thread',
    state: const AcpStatusBarViewState(
      phase: AcpSessionStatusPhase.completed,
      stopReason: AcpStopReasonKind.endTurn,
      provenance: AcpHistoryOriginKind.loadReplay,
      usage: AcpUsagePresentation(
        usedFormatted: '18.4k',
        sizeFormatted: '200k',
        ratio: 0.092,
        costLabel: '\$0.04',
      ),
    ),
    externalHistoryButton: const AcpExternalHistoryButtonState(
      status: AcpExternalHistoryAvailability.available,
      canLoad: true,
      canResume: true,
    ),
    onOpenExternalHistory: () {},
  ),
);

@Preview(name: 'ACP 外部会话对话框', group: 'ACP', size: Size(760, 520))
Widget acpExternalHistoryDialogPreview() => _acpPreviewShell(
  AcpExternalHistoryDialog(
    state: const AcpExternalHistoryDialogState(
      availability: AcpExternalHistoryAvailability.available,
      canLoad: true,
      canResume: true,
      nextCursor: 'page-2',
      sessions: [
        AcpExternalSessionRowPresentation(
          sessionId: 'sess-9f31a2',
          title: '重构 Studio 会话状态栏与动态配置交互',
          cwd: '/workspace/anywork',
          updatedAt: '2026-11-11 16:40',
        ),
        AcpExternalSessionRowPresentation(
          sessionId: 'sess-4c08b7',
          title: '排查 JSON-RPC stdio 连接与权限回执',
          cwd: '/workspace/anywork',
          updatedAt: '2026-11-10 21:15',
          outcome: AcpExternalOpenOutcome.unknown,
          errorMessage: '打开超时，对端可能已受理该请求',
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
