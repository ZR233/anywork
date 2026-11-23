import 'package:flutter/widget_previews.dart';
import 'package:anywork/src/shared/composer_configuration_bar.dart';

import 'agy_configuration_fixture.dart';

import 'package:material_ui/material_ui.dart';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/features/conversation/timeline/state/patch_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/tool_presentation.dart';
import 'package:anywork/src/features/conversation/acp/acp_views.dart';
import 'package:anywork/src/features/conversation/composer/state/start_backend_view_state.dart';
import 'package:anywork/src/features/conversation/composer/views/start_model_selector_view.dart';

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

const _sampleAcpService = StartBackendServiceItem(
  id: 'preview-agent',
  name: '代码助手',
  enabled: true,
);

StartBackendViewState _startBackendState({bool enabled = true}) =>
    StartBackendViewState(
      services: const [_sampleAcpService],
      accountId: _sampleAcpService.id,
      modelAccountId: null,
      modelId: null,
      nativeEnabled: false,
      enabled: enabled,
      loading: false,
    );

StartModelSelectorView _startModelSelector({
  bool enabled = true,
  bool inMenu = false,
}) => StartModelSelectorView(
  inMenu: inMenu,
  state: _startBackendState(enabled: enabled),
  onSelectModel: (_, _) {},
  onSelectService: (_) {},
  onManageServices: () {},
);

@Preview(name: 'ACP 新会话输入 · 合成 agy', group: 'ACP', size: Size(760, 260))
@Preview(name: 'ACP 新会话输入 · 中窗合成 agy', group: 'ACP', size: Size(520, 260))
@Preview(name: 'ACP 新会话输入 · 窄窗合成 agy', group: 'ACP', size: Size(380, 260))
Widget acpStartComposerPreview() => _acpPreviewShell(
  AcpStartComposerView(
    state: const AcpStartComposerViewState(
      workspaceId: 'preview-workspace',
      text: '梳理当前仓库的 ACP 会话状态流转，并检查组件边界。',
      accountId: 'preview-agent',
      serviceEnabled: true,
      ready: true,
    ),
    key: const ValueKey('acp-start-ready'),
    configurationBar: _acpConfigurationBar(enabled: true, withService: true),
    onDraftChanged: (_) {},
    onSubmit: () {},
  ),
);

@Preview(
  name: 'ACP 压力场景 / 创建忙碌 · 1.3×字号',
  group: 'ACP',
  size: Size(380, 300),
  textScaleFactor: 1.3,
)
Widget acpStartComposerLockedPreview() => _acpPreviewShell(
  AcpStartComposerView(
    state: const AcpStartComposerViewState(
      workspaceId: 'preview-workspace-locked',
      text: '补充检查失败重试路径。',
      accountId: 'preview-agent',
      serviceEnabled: true,
      ready: true,
      submitting: true,
    ),
    key: const ValueKey('acp-start-locked'),
    configurationBar: _acpConfigurationBar(enabled: false, withService: true),
    onDraftChanged: (_) {},
    onSubmit: () {},
  ),
);

@Preview(name: 'ACP 运行期输入与服务配置 · 合成 agy', group: 'ACP', size: Size(760, 240))
@Preview(name: 'ACP 运行期输入 · 窄窗合成 agy', group: 'ACP', size: Size(380, 240))
Widget acpConversationComposerPreview() => _acpPreviewShell(
  AcpConversationComposerView(
    key: const ValueKey('acp-session-ready'),
    state: const AcpComposerViewState(
      threadId: 'preview-thread',
      draftText: '继续检查这些配置选项在运行期的呈现。',
      canSend: true,
      isRunning: false,
      canInterrupt: false,
    ),
    onDraftChanged: (_) {},
    onSubmit: () {},
    onInterrupt: () {},
    onPickLocalAttachments: (_) async {},
    onAddRemoteAttachment: (_) async {},
    onRemoveAttachment: (_) {},
    configurationBar: _acpConfigurationBar(enabled: true),
  ),
);

@Preview(
  name: 'ACP 压力场景 / 中断忙碌 · 1.3×字号',
  group: 'ACP',
  size: Size(380, 280),
  textScaleFactor: 1.3,
)
Widget acpConversationComposerLockedPreview() => _acpPreviewShell(
  AcpConversationComposerView(
    key: const ValueKey('acp-session-locked'),
    state: const AcpComposerViewState(
      threadId: 'preview-thread-locked',
      draftText: '正在等待中断操作完成',
      canSend: false,
      isRunning: true,
      canInterrupt: false,
      interrupting: true,
    ),
    onDraftChanged: (_) {},
    onSubmit: () {},
    onInterrupt: () {},
    onPickLocalAttachments: (_) async {},
    onAddRemoteAttachment: (_) async {},
    onRemoveAttachment: (_) {},
    configurationBar: _acpConfigurationBar(enabled: false),
  ),
);

Widget _acpConfigurationBar({
  required bool enabled,
  bool withService = false,
  bool flash = false,
}) => AcpConfigurationBar(
  leadingEntries: [
    if (withService)
      ComposerConfigurationEntry(
        id: 'preview-service',
        inline: _startModelSelector(enabled: enabled),
        measureInlineWidth: _startModelSelector(enabled: enabled)
            .measureInlineWidth,
        menuItem: _startModelSelector(enabled: enabled, inMenu: true),
      ),
  ],
  state: AcpConfigurationViewState(
    controls: agyConfigurationFixture(flash: flash),
    enabled: enabled,
  ),
  onSelectValue: (_, _) {},
  onBooleanChanged: (_, _) {},
  onSelectLegacyMode: (_) {},
);

@Preview(name: 'ACP 合成 agy 配置栏 · 宽窗', group: 'ACP', size: Size(760, 140))
Widget acpConfigurationWidePreview() =>
    _acpPreviewShell(_acpConfigurationBar(enabled: true));

@Preview(name: 'ACP 合成 agy 配置栏 · 窄窗收纳', group: 'ACP', size: Size(340, 260))
Widget acpConfigurationNarrowPreview() =>
    _acpPreviewShell(_acpConfigurationBar(enabled: true));

@Preview(
  name: 'ACP 合成 agy Flash · 2×字号压力',
  group: 'ACP',
  size: Size(380, 180),
  textScaleFactor: 2,
)
Widget acpConfigurationFlashPreview() =>
    _acpPreviewShell(_acpConfigurationBar(enabled: true, flash: true));

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

@Preview(name: 'ACP 权限审批停靠面板', group: 'ACP', size: Size(720, 360))
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
    status: const AcpConnectionStatusView(
      state: AcpStatusBarViewState(
        phase: AcpSessionStatusPhase.completed,
        stopReason: AcpStopReasonKind.endTurn,
        provenance: AcpHistoryOriginKind.loadReplay,
      ),
    ),
    contextUsage: AcpContextUsageView(
      state: (
        used: BigInt.from(18400),
        size: BigInt.from(200000),
        isLive: true,
      ),
    ),
    cost: const AcpCostReadoutView(state: (amount: 0.04, currency: 'USD')),
    externalHistory: AcpExternalHistoryButtonView(
      threadId: 'preview-thread',
      state: const AcpExternalHistoryButtonState(
        status: AcpExternalHistoryAvailability.available,
        canLoad: true,
        canResume: true,
      ),
      onOpen: () {},
    ),
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
