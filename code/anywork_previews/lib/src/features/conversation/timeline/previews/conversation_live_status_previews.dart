import 'dart:convert';

import 'package:anywork_client/models.dart' hide LiveStatusIdle;
import 'package:anywork_client/models.dart' as feed show LiveStatusIdle;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/widget_previews.dart';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/app/theme/studio_tokens.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/timeline_views.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_display_unit_view.dart';
import 'package:anywork/src/features/conversation/timeline/work_group/work_group_member_view.dart';

import 'timeline_preview_fixtures.dart';

import 'package:anywork/src/features/conversation/timeline/widgets/timeline_resting_cat.dart';

/// 官方预览只装配生产组件，不装配 Client、原生桥或第二套状态投影。
Widget liveStatusPreviewHost(Widget child, {double scale = 1}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('zh'),
  theme: pureStudioTheme(locale: const Locale('zh')),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, appChild) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: ListTileTheme(
      data: Theme.of(context).listTileTheme,
      child: appChild!,
    ),
  ),
  home: Scaffold(body: Center(child: child)),
);

const liveStatusResponseText =
    '已经把会话界面收敛为同一套共享模块：**起始页与运行期会话共用外壳、顶栏与输入框，Work 在主时间线连续阅读，状态栏只承载独立正文、通知与交互**。\n\n'
    '### 运行期配置可配性分层\n'
    '- **创建期一次性冻结**：工作区模式与子智能体分发在会话创建后上移至顶栏只读徽标。\n'
    '- **运行期条件锁定**：轮次运行或等待期间锁定模式、主模型与思考强度。\n'
    '- **子智能体只读**：详情展示历史、进展与工作区，主会话保持独立草稿。\n\n'
    '长正文达到可用高度后在区内滚动，向上阅读或选择文字暂停跟随，点击“跟随输出”回到底部。\n\n'
    '前序工作组已在流式正文开始时结算入主时间线，当前状态栏仅承载正在输出的正文与必要控制提示。';

Widget liveStatusGroupPreview({
  bool history = false,
  bool thinkingOnly = false,
}) {
  if (history) {
    return CompletionRunView(
      id: 'preview-history',
      timing: TimelinePreviewFixtures.workTiming(),
      initiallyExpanded: false,
      location: WorkDisplayLocation.history,
      childBuilder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChatItemView(item: TimelinePreviewFixtures.reasoning),
          ChatItemView(item: TimelinePreviewFixtures.tool),
        ],
      ),
    );
  }
  return _ActivityPreview(
    activity: thinkingOnly
        ? const ConversationActivityView(
            identity: 'preview-thinking-only',
            kind: ConversationActivityKind.thinking,
          )
        : const ConversationActivityView(
            identity: 'preview-exec-work',
            kind: ConversationActivityKind.runningTool,
            activeTools: [
              ThreadActivityToolEntry(
                callId: 'preview-command',
                name: 'exec',
                summary: 'cargo flutter analyze',
                arguments: ThreadActivityArgumentsKind.commandLine,
                state: ThreadActivityToolState.running,
                startedAt: 100,
              ),
            ],
          ),
    timing: WorkTiming(startedAtMillis: 100_000),
    childBuilder: (_) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TimelineReasoningView(
          summary: '梳理 **会话共享组件** 与 `LiveStatusBar` 锁定边界',
          running: true,
          body: ConversationCurrentWindowView(
            id: 'preview-reasoning',
            text: '核对现有调用链和组件边界，随后检查布局和状态。',
          ),
        ),
        if (!thinkingOnly)
          const TimelineToolItemView(
            item: TimelineToolPresentation(
              id: 'preview-command',
              toolCallId: 'preview-command',
              name: 'exec',
              presentationContract: 'builtin.exec@2',
              statusString: 'running',
              arguments: '{"command":"cargo flutter analyze"}',
              output: '',
            ),
          ),
      ],
    ),
  );
}

@Preview(name: '趴卧猫 · 尾巴摆动', group: '实时状态栏', size: Size(760, 340))
Widget conversationRestingCatPreview() => liveStatusPreviewHost(
  Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 168,
            child: Center(
              child: TimelineActivityIndicator(
                icon: null,
                color: Color(0xFF55798C),
                active: true,
                catSize: 152,
              ),
            ),
          ),
          SizedBox(width: 24),
          TimelineRestingCat(
            progress: AlwaysStoppedAnimation(0.23),
            color: Color(0xFF55798C),
            size: 84,
          ),
          SizedBox(width: 12),
          TimelineRestingCat(
            progress: AlwaysStoppedAnimation(0.50),
            color: Color(0xFF55798C),
            size: 84,
          ),
          SizedBox(width: 12),
          TimelineRestingCat(
            progress: AlwaysStoppedAnimation(0.75),
            color: Color(0xFF55798C),
            size: 84,
          ),
        ],
      ),
      _liveMachineSurface(
        snapshot: LiveStatusSnapshot(
          revision: 1,
          phase: LiveStatusWorking(items: []),
          attentions: [],
          suppressedByInteraction: false,
        ),
      ),
    ],
  ),
);

@Preview(name: '压缩图标 · 动态拉链关键帧', group: '实时状态栏', size: Size(760, 340))
Widget conversationCompactingZipPreview() => liveStatusPreviewHost(
  Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 168,
            child: Center(
              child: TimelineActivityIndicator(
                icon: null,
                color: Color(0xFF55798C),
                active: true,
                style: TimelineActivityIndicatorStyle.compactingZip,
                zipSize: 136,
              ),
            ),
          ),
          SizedBox(width: 20),
          TimelineCompactingZipIcon(
            progress: AlwaysStoppedAnimation(0.00),
            color: Color(0xFF55798C),
            size: 80,
          ),
          SizedBox(width: 12),
          TimelineCompactingZipIcon(
            progress: AlwaysStoppedAnimation(0.28),
            color: Color(0xFF55798C),
            size: 80,
          ),
          SizedBox(width: 12),
          TimelineCompactingZipIcon(
            progress: AlwaysStoppedAnimation(0.50),
            color: Color(0xFF55798C),
            size: 80,
          ),
          SizedBox(width: 12),
          TimelineCompactingZipIcon(
            progress: AlwaysStoppedAnimation(0.76),
            color: Color(0xFF55798C),
            size: 80,
          ),
        ],
      ),
      _liveMachineSurface(
        snapshot: LiveStatusSnapshot(
          revision: 1,
          phase: const LiveStatusCompacting(manual: false),
          attentions: [],
          suppressedByInteraction: false,
        ),
      ),
    ],
  ),
);

Widget _previewScenario(String label, Widget child) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          return Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          );
        },
      ),
    ),
    child,
  ],
);

Widget _liveMachineSurface({
  required LiveStatusSnapshot snapshot,
  ThreadStorageStateView? storageState,
  bool liveWorkInitiallyExpanded = false,
  DateTime Function()? now,
}) {
  final previewNow = now ?? () => DateTime.fromMillisecondsSinceEpoch(225_000);
  final projected = LiveStatusMachine.project(
    'preview-thread',
    snapshot,
    receivedAt: previewNow(),
    storageState: storageState,
  );
  return LiveStatusSurfaceView(
    state: projected.state,
    liveWorkInitiallyExpanded: liveWorkInitiallyExpanded,
    now: previewNow,
  );
}

@Preview(name: '四态顶栏指示器零抖动对比', group: '实时状态栏', size: Size(760, 560))
Widget conversationFourStatesComparisonPreview() => liveStatusPreviewHost(
  SingleChildScrollView(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _previewScenario(
          '工况 1 · 思考中（趴卧摇尾猫）',
          _liveMachineSurface(
            snapshot: LiveStatusSnapshot(
              revision: 1,
              phase: LiveStatusWorking(items: []),
              attentions: [],
              suppressedByInteraction: false,
            ),
          ),
        ),
        _previewScenario(
          '工况 2 · 前台命令执行（圆形进度 + 命令摘要）',
          _liveMachineSurface(
            snapshot: LiveStatusSnapshot(
              revision: 1,
              phase: LiveStatusWorking(
                items: [
                  WorkGroupToolCall(
                    id: 'preview-exec-call',
                    seq: 1,
                    callId: 'preview-exec-call',
                    toolName: 'exec',
                    status: 'running',
                    summary: 'cargo flutter test --no-pub test/ui',
                    payloadJson: '{}',
                    bodies: const [],
                    startedAtMs: (100) * 1000,
                  ),
                ],
              ),
              attentions: [],
              suppressedByInteraction: false,
            ),
          ),
        ),
        _previewScenario(
          '工况 3 · 流式正文输出（书写笔触）',
          _liveMachineSurface(
            snapshot: LiveStatusSnapshot(
              revision: 1,
              phase: LiveStatusStreamingText(
                attemptId: 'preview-attempt',
                itemId: 'preview-response',
                text: '四态顶栏共享同一 32×32 引导槽位与 15px 标题字号，切换零位移。',
                startedAtMs: (100) * 1000,
              ),
              attentions: [],
              suppressedByInteraction: false,
            ),
            now: () => DateTime.fromMillisecondsSinceEpoch(117_000),
          ),
        ),
        _previewScenario(
          '工况 4 · 上下文压缩（拉链图标）',
          _liveMachineSurface(
            snapshot: LiveStatusSnapshot(
              revision: 1,
              phase: const LiveStatusCompacting(manual: false),
              attentions: [],
              suppressedByInteraction: false,
            ),
          ),
        ),
      ],
    ),
  ),
);

@Preview(name: '思考中 · 无内容', group: '实时状态栏', size: Size(760, 110))
Widget conversationLiveStatusWaitingPreview() => liveStatusPreviewHost(
  _liveMachineSurface(
    snapshot: LiveStatusSnapshot(
      revision: 1,
      phase: LiveStatusWorking(items: []),
      attentions: [],
      suppressedByInteraction: false,
    ),
  ),
);

@Preview(name: '正在压缩上下文', group: '实时状态栏', size: Size(760, 110))
Widget conversationLiveStatusCompactingPreview() => liveStatusPreviewHost(
  _liveMachineSurface(
    snapshot: LiveStatusSnapshot(
      revision: 1,
      phase: const LiveStatusCompacting(manual: false),
      attentions: [],
      suppressedByInteraction: false,
    ),
  ),
);

@Preview(name: '工作组 · 进行中', group: '实时状态栏', size: Size(760, 300))
Widget conversationLiveStatusToolsPreview() => liveStatusPreviewHost(
  _liveMachineSurface(
    snapshot: LiveStatusSnapshot(
      revision: 1,
      phase: LiveStatusWorking(
        items: [
          const WorkGroupReasoning(
            id: 'preview-reasoning',
            seq: 1,
            text: '梳理会话共享组件与状态机迁移边界',
            summary: '梳理会话共享组件与状态机迁移边界',
            outcome: 'completed',
            startedAtMs: 100_000,
            finishedAtMs: 104_000,
          ),
          WorkGroupToolCall(
            id: 'preview-command',
            seq: 2,
            callId: 'preview-command',
            toolName: 'exec',
            status: 'completed',
            summary: 'cargo flutter analyze',
            payloadJson: '{}',
            bodies: const [],
            startedAtMs: 104_000,
            finishedAtMs: 112_000,
          ),
          WorkGroupToolCall(
            id: 'preview-read',
            seq: 3,
            callId: 'preview-read',
            toolName: 'read_file',
            status: 'running',
            summary: 'design/26-timeline-content.md',
            payloadJson: '{}',
            bodies: const [],
            startedAtMs: 112_000,
          ),
        ],
        reasoningPreview: '梳理 **会话共享组件** 与状态机迁移边界',
        startedAtMs: 100_000,
      ),
      attentions: [],
      suppressedByInteraction: false,
    ),
    liveWorkInitiallyExpanded: true,
    now: () => DateTime.fromMillisecondsSinceEpoch(225_000),
  ),
);

@Preview(name: '重连中 · 独立状态', group: '实时状态栏', size: Size(760, 140))
Widget conversationLiveStatusReconnectingPreview() => liveStatusPreviewHost(
  _liveMachineSurface(
    snapshot: LiveStatusSnapshot(
      revision: 1,
      phase: const LiveStatusReconnecting(
        attemptId: 'preview-reconnect',
        message: '正在重新连接',
        attempt: 1,
        maxAttempts: 3,
      ),
      attentions: [],
      suppressedByInteraction: false,
    ),
  ),
);

@Preview(name: '工作组 · 调用失败后继续思考（折叠单行）', group: '实时状态栏', size: Size(1067, 140))
Widget conversationLiveStatusFailedCallPreview() => liveStatusPreviewHost(
  _liveMachineSurface(
    snapshot: LiveStatusSnapshot(
      revision: 1,
      phase: LiveStatusWorking(
        items: [
          WorkGroupToolCall(
            id: 'preview-failed-call',
            seq: 1,
            callId: 'preview-failed-call',
            toolName: 'exec',
            status: 'failed',
            summary: 'cargo flutter analyze',
            payloadJson: '{}',
            bodies: const [],
            startedAtMs: 154_000,
            finishedAtMs: 162_000,
          ),
        ],
        reasoningPreview: '静态分析检查失败，正在定位问题。',
        startedAtMs: 154_000,
      ),
      attentions: [],
      suppressedByInteraction: false,
    ),
    liveWorkInitiallyExpanded: true,
    now: () => DateTime.fromMillisecondsSinceEpoch(225_000),
  ),
);

@Preview(name: '工作组 · 推理详情', group: '实时状态栏', size: Size(760, 200))
Widget conversationLiveStatusThinkingPreview() => liveStatusPreviewHost(
  _liveMachineSurface(
    snapshot: LiveStatusSnapshot(
      revision: 1,
      phase: LiveStatusWorking(
        items: [
          const WorkGroupReasoning(
            id: 'preview-thinking-detail',
            seq: 1,
            text: '核对现有调用链和组件边界',
            summary: '核对现有调用链和组件边界',
            outcome: 'running',
            startedAtMs: 100_000,
          ),
        ],
        reasoningPreview: '梳理 **会话共享组件** 与状态机转换条件',
        startedAtMs: 100_000,
      ),
      attentions: [],
      suppressedByInteraction: false,
    ),
    liveWorkInitiallyExpanded: true,
    now: () => DateTime.fromMillisecondsSinceEpoch(225_000),
  ),
);

@Preview(name: '正文 · 长文与跟随', group: '实时状态栏', size: Size(760, 300))
Widget conversationLiveStatusRespondingPreview() => liveStatusPreviewHost(
  _liveMachineSurface(
    snapshot: LiveStatusSnapshot(
      revision: 1,
      phase: LiveStatusStreamingText(
        attemptId: 'preview-attempt',
        itemId: 'preview-response',
        text: liveStatusResponseText,
        startedAtMs: (100) * 1000,
      ),
      attentions: [],
      suppressedByInteraction: false,
    ),
    now: () => DateTime.fromMillisecondsSinceEpoch(125_000),
  ),
);

@Preview(name: '正文 · 短文自然高度', group: '实时状态栏', size: Size(760, 180))
Widget conversationLiveStatusShortResponsePreview() => liveStatusPreviewHost(
  _liveMachineSurface(
    snapshot: LiveStatusSnapshot(
      revision: 1,
      phase: LiveStatusStreamingText(
        attemptId: 'preview-attempt',
        itemId: 'preview-response',
        text: '已完成组件布局调整，正在核对各工况。',
        startedAtMs: (100) * 1000,
      ),
      attentions: [],
      suppressedByInteraction: false,
    ),
    now: () => DateTime.fromMillisecondsSinceEpoch(108_000),
  ),
);

@Preview(name: '等待成员', group: '实时状态栏', size: Size(760, 300))
Widget conversationLiveStatusWaitPreview() => liveStatusPreviewHost(
  _liveMachineSurface(
    snapshot: LiveStatusSnapshot(
      revision: 1,
      phase: LiveStatusWorking(
        items: [
          WorkGroupToolCall(
            id: 'preview-wait-member',
            seq: 1,
            callId: 'preview-wait-member',
            toolName: 'wait',
            status: 'running',
            summary: '等待成员汇报结果',
            payloadJson: '{}',
            bodies: const [],
            startedAtMs: 100_000,
          ),
        ],
        startedAtMs: 100_000,
      ),
      attentions: [],
      suppressedByInteraction: false,
    ),
    liveWorkInitiallyExpanded: true,
    now: () => DateTime.fromMillisecondsSinceEpoch(225_000),
  ),
);

@Preview(name: '宽窗 · 正文', group: '实时状态栏', size: Size(1040, 300))
Widget conversationLiveStatusWidePreview() => liveStatusPreviewHost(
  _liveMachineSurface(
    snapshot: LiveStatusSnapshot(
      revision: 1,
      phase: LiveStatusStreamingText(
        attemptId: 'preview-attempt',
        itemId: 'preview-response',
        text: liveStatusResponseText,
        startedAtMs: (100) * 1000,
      ),
      attentions: [],
      suppressedByInteraction: false,
    ),
    now: () => DateTime.fromMillisecondsSinceEpoch(125_000),
  ),
);

@Preview(name: '停止中', group: '实时状态栏', size: Size(760, 110))
Widget conversationLiveStatusStoppingPreview() => liveStatusPreviewHost(
  _liveMachineSurface(
    snapshot: LiveStatusSnapshot(
      revision: 1,
      phase: LiveStatusWorking(items: []),
      attentions: [
        LiveAttention(id: 'preview-stopping', kind: 'stopping', summary: ''),
      ],
      suppressedByInteraction: false,
    ),
  ),
);

@Preview(name: '存储状态五态对比', group: '实时状态栏', size: Size(760, 580))
Widget conversationLiveStatusStorageFailurePreview() => liveStatusPreviewHost(
  SingleChildScrollView(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _previewScenario(
          '工况 1 · 已恢复可继续',
          _liveMachineSurface(
            snapshot: LiveStatusSnapshot(
              revision: 1,
              phase: const feed.LiveStatusIdle(),
              attentions: [],
              suppressedByInteraction: false,
            ),
            storageState: const ThreadStorageStateView(
              fault: ThreadHistoryFault.writeFailed,
              faultGeneration: 1,
              execution: ThreadStorageExecution.paused,
              resumeRequired: true,
              canResume: true,
              lastError: '保存暂时失败，当前内容已保留。',
            ),
          ),
        ),
        _previewScenario(
          '工况 2 · 写入故障',
          _liveMachineSurface(
            snapshot: LiveStatusSnapshot(
              revision: 1,
              phase: const feed.LiveStatusIdle(),
              attentions: [],
              suppressedByInteraction: false,
            ),
            storageState: const ThreadStorageStateView(
              fault: ThreadHistoryFault.writeFailed,
              faultGeneration: 2,
              execution: ThreadStorageExecution.paused,
              resumeRequired: true,
              canResume: false,
              lastError: '保存暂时失败，当前内容已保留。',
            ),
          ),
        ),
        _previewScenario(
          '工况 3 · 存储受限',
          _liveMachineSurface(
            snapshot: LiveStatusSnapshot(
              revision: 1,
              phase: const feed.LiveStatusIdle(),
              attentions: [],
              suppressedByInteraction: false,
            ),
            storageState: const ThreadStorageStateView(
              pressurePaused: true,
              execution: ThreadStorageExecution.running,
            ),
          ),
        ),
        _previewScenario(
          '工况 4 · 等待保存恢复',
          _liveMachineSurface(
            snapshot: LiveStatusSnapshot(
              revision: 1,
              phase: const feed.LiveStatusIdle(),
              attentions: [],
              suppressedByInteraction: false,
            ),
            storageState: const ThreadStorageStateView(
              resumeRequired: true,
              canResume: false,
              execution: ThreadStorageExecution.paused,
            ),
          ),
        ),
        _previewScenario(
          '工况 5 · 保存已暂停',
          _liveMachineSurface(
            snapshot: LiveStatusSnapshot(
              revision: 1,
              phase: const feed.LiveStatusIdle(),
              attentions: [],
              suppressedByInteraction: false,
            ),
            storageState: const ThreadStorageStateView(
              execution: ThreadStorageExecution.paused,
            ),
          ),
        ),
      ],
    ),
  ),
);

@Preview(
  name: '控制与连接 · 停止 / 审批 / 重连 / 断开',
  group: '实时状态栏',
  size: Size(760, 620),
)
Widget conversationLiveStatusControlAndConnectionPreview() =>
    liveStatusPreviewHost(
      SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _previewScenario(
              '工况 1 · 停止中',
              _liveMachineSurface(
                snapshot: LiveStatusSnapshot(
                  revision: 1,
                  phase: LiveStatusWorking(items: []),
                  attentions: [
                    LiveAttention(
                      id: 'preview-ctrl-stopping',
                      kind: 'stopping',
                      summary: '',
                    ),
                  ],
                  suppressedByInteraction: false,
                ),
              ),
            ),
            _previewScenario(
              '工况 2 · 等待工具授权',
              _liveMachineSurface(
                snapshot: LiveStatusSnapshot(
                  revision: 1,
                  phase: LiveStatusWorking(items: []),
                  attentions: [
                    LiveAttention(
                      id: 'preview-ctrl-approval',
                      kind: 'approval',
                      summary: 'exec: cargo test',
                    ),
                  ],
                  suppressedByInteraction: false,
                ),
              ),
            ),
            _previewScenario(
              '工况 3 · 流式输出与停止并发',
              _liveMachineSurface(
                snapshot: LiveStatusSnapshot(
                  revision: 1,
                  phase: LiveStatusStreamingText(
                    attemptId: 'preview-attempt',
                    itemId: 'preview-response',
                    text: '正在终止当前输出并回收在途工具调用。',
                    startedAtMs: (100) * 1000,
                  ),
                  attentions: [
                    LiveAttention(
                      id: 'preview-ctrl-resp-stopping',
                      kind: 'stopping',
                      summary: '',
                    ),
                  ],
                  suppressedByInteraction: false,
                ),
                now: () => DateTime.fromMillisecondsSinceEpoch(112_000),
              ),
            ),
            _previewScenario(
              '工况 4 · 实时同步重连中',
              _liveMachineSurface(
                snapshot: LiveStatusSnapshot(
                  revision: 1,
                  phase: const LiveStatusReconnecting(
                    attemptId: 'preview-reconnect',
                    message: '正在重新连接',
                    attempt: 1,
                  ),
                  attentions: [],
                  suppressedByInteraction: false,
                ),
              ),
            ),
            _previewScenario(
              '工况 5 · 实时同步已断开',
              _liveMachineSurface(
                snapshot: LiveStatusSnapshot(
                  revision: 1,
                  phase: const feed.LiveStatusIdle(),
                  attentions: [
                    LiveAttention(
                      id: 'preview-disconnected',
                      kind: 'disconnected',
                      summary: '实时同步连接已断开',
                    ),
                  ],
                  suppressedByInteraction: false,
                ),
              ),
            ),
          ],
        ),
      ),
    );

@Preview(name: '主阶段 · 流式正文输出', group: '实时状态栏', size: Size(760, 420))
Widget conversationLiveStatusStreamingResponsePreview() =>
    liveStatusPreviewHost(
      _liveMachineSurface(
        snapshot: LiveStatusSnapshot(
          revision: 1,
          phase: LiveStatusStreamingText(
            attemptId: 'preview-attempt',
            itemId: 'preview-response',
            text:
                '### 流式输出期间状态栏收敛\n'
                '- **前序工作组已结算**：流式正文开始即进入主时间线不可变历史。\n'
                '- **单一核心区**：状态栏只承载正在输出的正文与必要控制提示。\n\n'
                '当前正在连续生成最终答复内容，状态由状态机统一投影。',
            startedAtMs: (112) * 1000,
          ),
          attentions: [],
          suppressedByInteraction: false,
        ),
        now: () => DateTime.fromMillisecondsSinceEpoch(225_000),
      ),
    );

@Preview(name: '长耗时与工作组展开 · 小时 / 日', group: '实时状态栏', size: Size(760, 640))
Widget conversationLiveStatusDeferredToolsAndDurationsPreview() =>
    liveStatusPreviewHost(
      SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _previewScenario(
              '工况 1 · 命令执行与工作组展开（> 60 分钟进位小时）',
              _liveMachineSurface(
                snapshot: LiveStatusSnapshot(
                  revision: 1,
                  phase: LiveStatusWorking(
                    items: [
                      WorkGroupToolCall(
                        id: 'hourly-exec',
                        seq: 1,
                        callId: 'hourly-exec',
                        toolName: 'exec',
                        status: 'running',
                        summary: 'cargo flutter test --no-pub test/ui',
                        payloadJson: '{}',
                        bodies: const [],
                        startedAtMs: (100) * 1000,
                      ),
                      WorkGroupToolCall(
                        id: 'hourly-write',
                        seq: 2,
                        callId: 'hourly-write',
                        toolName: 'write_file',
                        status: 'completed',
                        summary: 'design/19-studio-ui.md',
                        payloadJson: '{}',
                        bodies: const [],
                        startedAtMs: (100) * 1000,
                        finishedAtMs: (105) * 1000,
                      ),
                    ],
                    startedAtMs: 100_000,
                  ),
                  attentions: [],
                  suppressedByInteraction: false,
                ),
                liveWorkInitiallyExpanded: true,
                now: () => DateTime.fromMillisecondsSinceEpoch(
                  100_000 + (3600 + 15 * 60 + 8) * 1000,
                ),
              ),
            ),
            _previewScenario(
              '工况 2 · 非命令工具运行（保留猫图标 + 工具摘要）',
              _liveMachineSurface(
                snapshot: LiveStatusSnapshot(
                  revision: 1,
                  phase: LiveStatusWorking(
                    items: [
                      WorkGroupToolCall(
                        id: 'write-tool',
                        seq: 1,
                        callId: 'write-tool',
                        toolName: 'write_file',
                        status: 'running',
                        summary: '写入 design/19-studio-ui.md',
                        payloadJson: '{}',
                        bodies: const [],
                        startedAtMs: (100) * 1000,
                      ),
                    ],
                    startedAtMs: 100_000,
                  ),
                  attentions: [],
                  suppressedByInteraction: false,
                ),
                now: () => DateTime.fromMillisecondsSinceEpoch(142_000),
              ),
            ),
            _previewScenario(
              '工况 3 · 长时间思考（> 24 小时进位日）',
              _liveMachineSurface(
                snapshot: LiveStatusSnapshot(
                  revision: 1,
                  phase: LiveStatusWorking(items: [], startedAtMs: 100_000),
                  attentions: [],
                  suppressedByInteraction: false,
                ),
                now: () => DateTime.fromMillisecondsSinceEpoch(
                  100_000 + (86400 + 3 * 3600 + 120) * 1000,
                ),
              ),
            ),
          ],
        ),
      ),
    );

@Preview(name: '窄窗 360px · 160% 缩放与工作组审批', group: '实时状态栏', size: Size(360, 440))
Widget conversationLiveStatusNarrowMachinePreview() => liveStatusPreviewHost(
  _liveMachineSurface(
    snapshot: LiveStatusSnapshot(
      revision: 1,
      phase: const feed.LiveStatusIdle(),
      attentions: [
        LiveAttention(
          id: 'preview-narrow-approval',
          kind: 'approval',
          summary: 'exec: cargo flutter test --no-pub test/ui',
        ),
      ],
      suppressedByInteraction: false,
    ),
    storageState: const ThreadStorageStateView(
      fault: ThreadHistoryFault.writeFailed,
      faultGeneration: 1,
      execution: ThreadStorageExecution.paused,
      resumeRequired: true,
      canResume: true,
    ),
    now: () => DateTime.fromMillisecondsSinceEpoch(
      100_000 + (3600 + 15 * 60 + 8) * 1000,
    ),
  ),
  scale: 1.6,
);

@Preview(name: '正文窗口 · 分页与诊断', group: '实时状态栏', size: Size(760, 300))
Widget conversationLiveStatusWindowPreview() => liveStatusPreviewHost(
  ConversationActivityBar(
    children: [
      ConversationResponseView(
        child: ConversationCurrentWindowView(
          id: 'preview-window',
          text: liveStatusResponseText,
          offset: 32768,
          end: 65536,
          availableThrough: 98304,
          onFirst: () {},
          onNext: () {},
        ),
      ),
    ],
  ),
);

@Preview(name: '思考成员 · 概要与正文组合', group: '实时状态栏', size: Size(760, 300))
Widget conversationReasoningVariantsPreview() => liveStatusPreviewHost(
  _liveMachineSurface(
    snapshot: LiveStatusSnapshot(
      revision: 1,
      phase: LiveStatusWorking(
        items: [
          const WorkGroupReasoning(
            id: 'reasoning-1',
            seq: 1,
            text: '梳理会话共享组件与锁定边界',
            summary: '梳理会话共享组件与锁定边界',
            outcome: 'completed',
            startedAtMs: 100_000,
            finishedAtMs: 108_000,
          ),
          const WorkGroupReasoning(
            id: 'reasoning-2',
            seq: 2,
            text: '核对运行期选择器锁定规则',
            summary: '核对运行期选择器锁定规则',
            outcome: 'running',
            startedAtMs: 108_000,
          ),
        ],
        reasoningPreview: '核对运行期选择器锁定规则',
        startedAtMs: 100_000,
      ),
      attentions: [],
      suppressedByInteraction: false,
    ),
    liveWorkInitiallyExpanded: true,
    now: () => DateTime.fromMillisecondsSinceEpoch(225_000),
  ),
);

@Preview(name: '工作组 · 长工具输出', group: '实时状态栏', size: Size(760, 220))
Widget conversationLiveStatusLongToolPreview() => liveStatusPreviewHost(
  _liveMachineSurface(
    snapshot: LiveStatusSnapshot(
      revision: 1,
      phase: LiveStatusWorking(
        items: [
          WorkGroupToolCall(
            id: 'long-tool-output',
            seq: 1,
            callId: 'long-tool-output',
            toolName: 'exec',
            status: 'running',
            summary: 'cargo flutter analyze --fatal-infos',
            payloadJson: '{}',
            bodies: const [],
            startedAtMs: (100) * 1000,
          ),
        ],
        startedAtMs: 100_000,
      ),
      attentions: [],
      suppressedByInteraction: false,
    ),
    liveWorkInitiallyExpanded: true,
    now: () => DateTime.fromMillisecondsSinceEpoch(225_000),
  ),
);

class _ActivityPreview extends StatelessWidget {
  const _ActivityPreview({
    required this.childBuilder,
    this.activity,
    this.timing = const WorkTiming(startedAtMillis: 100_000),
  });
  final WidgetBuilder childBuilder;
  final ConversationActivityView? activity;
  final WorkTiming timing;
  @override
  Widget build(BuildContext context) => CompletionRunView(
    id: 'preview-live-work',
    timing: timing,
    activity: activity,
    location: WorkDisplayLocation.live,
    executionPresent: true,
    initiallyExpanded: false,
    // A fixed synthetic observation cut, not a reconstructed production clock.
    now: () => DateTime.fromMillisecondsSinceEpoch(225000),
    childBuilder: childBuilder,
  );
}

@Preview(name: '已封存工作组 / 折叠', group: 'Timeline · 原子工作组', size: Size(1067, 420))
Widget sealedToolWorkGroupCollapsedPreview() =>
    liveStatusPreviewHost(const _SealedToolWorkGroupPreview());

@Preview(name: '已封存工作组 / 展开', group: 'Timeline · 原子工作组', size: Size(1067, 420))
Widget sealedToolWorkGroupExpandedPreview() =>
    liveStatusPreviewHost(const _SealedToolWorkGroupPreview(expanded: true));

/// Static chronological fixtures mounted through production disclosure and
/// item widgets. No grouping reducer or app graph is reconstructed here.
class _SealedToolWorkGroupPreview extends StatefulWidget {
  const _SealedToolWorkGroupPreview({this.expanded = false});

  final bool expanded;

  @override
  State<_SealedToolWorkGroupPreview> createState() =>
      _SealedToolWorkGroupPreviewState();
}

class _SealedToolWorkGroupPreviewState
    extends State<_SealedToolWorkGroupPreview> {
  late final group = TimelineDisplayUnit(
    block: DisplayBlock(
      id: 'sealed-tool-preview-group',
      blockOrder: 2,
      body: WorkDisplayBlock(
        timing: const WorkTiming(
          startedAtMillis: 1_735_689_600_000,
          finishedAtMillis: 1_735_689_725_000,
        ),
        feedGroup: const TimelineWorkGroup(
          id: 'sealed-tool-preview-group',
          firstSeq: 2,
          lastSeq: 2,
          memberCount: 1,
          summary: '',
          status: WorkGroupStatus.completed,
          startedAtMs: 1_735_689_600_000,
          finishedAtMs: 1_735_689_725_000,
        ),
        executionPresent: false,
        memberCount: 1,
        unfinishedCount: 0,
        groupClosed: true,
      ),
    ),
  );

  @override
  void initState() {
    super.initState();
    group.expansion.expanded = widget.expanded;
  }

  @override
  void dispose() {
    group.expansion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChatItemView(item: TimelinePreviewFixtures.assistant),
        TimelineDisplayUnitView(
          key: const ValueKey('sealed-tool-preview-group'),
          unit: group,
          childBuilder: (_) => const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TimelineToolItemView(
                item: TimelineToolPresentation(
                  id: 'sealed-tool-preview-exec',
                  toolCallId: 'sealed-tool-preview-exec-call',
                  name: 'exec',
                  presentationContract: 'builtin.exec@2',
                  statusString: 'succeeded',
                  arguments: '{"command":"cargo flutter test test/ui"}',
                  output: r'{"stdout":{"content":"exec 执行完成：测试命令成功退出。"},"stderr":{"content":""},"exitCode":0}',
                ),
                initiallyExpanded: true,
              ),
              TimelineToolItemView(
                item: TimelineToolPresentation(
                  id: 'sealed-tool-preview-search',
                  toolCallId: 'sealed-tool-preview-search-call',
                  name: 'web_search',
                  presentationContract: 'builtin.web_search@1',
                  statusString: 'failed',
                  arguments: '{"search_query":[{"q":"时间线工作组"}]}',
                  output: '',
                  error: '搜索服务暂时不可用',
                ),
                initiallyExpanded: true,
              ),
            ],
          ),
        ),
        ChatItemView(
          item: TimelinePreviewFixtures.item(
            'sealed-tool-preview-answer',
            'text',
            const {'channel': 'final', 'attachments': []},
            sealedAt: 1735689602,
            bodies: [
              TimelinePreviewFixtures.body(
                'part.text.0',
                '搜索未成功，但已封存工作组仍保留在两段正文之间。',
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

List<WorkGroupMember> _buildMixedWorkGroupMembers() => [
  const WorkGroupReasoning(
    id: 'matrix-reasoning-1',
    seq: 1,
    text: '- 收敛 `WorkGroupMemberRegistry` 匹配分派表\n- 确认 **实时与历史工作组** 共用 `WorkGroupMemberView`',
    summary: '**梳理** `WorkGroupMemberRegistry` 分派边界',
    outcome: 'completed',
    startedAtMs: 100_000,
    finishedAtMs: 104_000,
  ),
  const WorkGroupReasoning(
    id: 'matrix-reasoning-2',
    seq: 2,
    text: '',
    summary: 'Designing **ToolResult** views 与 `WorkGroupMemberView` 单行排版',
    outcome: 'running',
    startedAtMs: 104_000,
  ),
  WorkGroupToolCall(
    id: 'matrix-exec-running',
    seq: 3,
    callId: 'call-exec-running',
    toolName: 'exec',
    presentationContract: 'builtin.exec@2',
    status: 'running',
    summary: 'exec',
    arguments: '{"command":"cargo flutter test --no-pub test/ui"}',
    payloadJson: '{}',
    bodies: const [],
    startedAtMs: 106_000,
  ),
  WorkGroupToolCall(
    id: 'matrix-exec-succeeded',
    seq: 4,
    callId: 'call-exec-succeeded',
    toolName: 'exec',
    presentationContract: 'builtin.exec@2',
    status: 'succeeded',
    summary: 'exec',
    arguments: '{"command":"cargo test -p pl-studio-runtime timeline::"}',
    resultPreview: '{"stdout":{"content":"test result: ok. 42 passed"},"stderr":{"content":""},"exitCode":0}',
    payloadJson: '{}',
    bodies: const [],
    startedAtMs: 106_000,
    finishedAtMs: 111_000,
  ),
  WorkGroupToolCall(
    id: 'matrix-exec-failed',
    seq: 5,
    callId: 'call-exec-failed',
    toolName: 'exec',
    presentationContract: 'builtin.exec@2',
    status: 'failed',
    summary: 'exec',
    payloadJson: jsonEncode({
      'contract': 'anywork.event/1',
      'type': 'tool',
      'meta': {'presentationContract': 'builtin.exec@2'},
      'data': {
        'invocation': {
          'toolCallId': 'call-exec-failed',
          'name': 'exec',
          'presentationContract': 'builtin.exec@2',
          'workingDirectory': '/workspace/sample-project',
        },
        'state': {
          'kind': 'failed',
          'completedAt': 119,
          'output': {'exitCode': 101, 'attachments': []},
        },
      },
      'bodies': [
        TimelinePreviewFixtures.body(
          'tool.arguments',
          '{"command":"cargo flutter analyze"}',
        ),
        TimelinePreviewFixtures.body(
          'tool.result',
          jsonEncode({
            'stdout': {'content': 'Analyzing code/anywork...'},
            'stderr': {
              'content': '[stderr] error: The named parameter "member" is required (work_group_member_view.dart:18:5)',
            },
            'exitCode': 101,
          }),
        ),
      ],
    }),
    bodies: const [],
    startedAtMs: 111_000,
    finishedAtMs: 119_000,
  ),
  WorkGroupToolCall(
    id: 'matrix-exec-backgrounded',
    seq: 6,
    callId: 'call-exec-bg',
    toolName: 'exec',
    presentationContract: 'builtin.exec@2',
    status: 'backgrounded',
    summary: 'exec',
    arguments: '{"command":"cargo xtask preview-gui --headless"}',
    payloadJson: '{}',
    bodies: const [],
    startedAtMs: 119_000,
  ),
  WorkGroupAgent(
    id: 'matrix-agent-1',
    seq: 7,
    agentId: 'thread-66137d7bee82c-14',
    name: 'thread-66137d7bee82c-14',
    status: 'running',
    summary: '审查工作组成员注册分派与单行排版',
    payloadJson: jsonEncode({
      'contract': 'anywork.event/1',
      'type': 'agent',
      'data': {
        'identity': {'role': 'reviewer', 'taskSummary': '审查工作组成员注册分派与单行排版'},
        'outcome': {'kind': 'active'},
      },
    }),
    startedAtMs: 120_000,
  ),
  WorkGroupToolCall(
    id: 'matrix-read-agent-session',
    seq: 8,
    callId: 'call-read-agent-session',
    toolName: 'read_agent_session',
    presentationContract: 'builtin.read_agent_session@1',
    status: 'succeeded',
    summary: 'read_agent_session',
    arguments: '{"target":"thread-66137cebcce11-a","limit":20}',
    resultPreview: jsonEncode({
      'items': [
        {'summary': '已核对历史工作组与实时工作组接口一致', 'status': 'completed'},
      ],
      'nextCursor': 'cursor-2',
    }),
    payloadJson: '{}',
    bodies: const [],
    startedAtMs: 121_000,
    finishedAtMs: 122_000,
  ),
  WorkGroupToolCall(
    id: 'matrix-spawn-agent',
    seq: 9,
    callId: 'call-spawn-agent',
    toolName: 'spawn_agent',
    presentationContract: 'builtin.spawn_agent@1',
    status: 'succeeded',
    summary: 'spawn_agent',
    arguments: jsonEncode({
      'profileId': 'executor',
      'taskSummary': '核对 360px 窄窗与大字号排版',
      'message': '验证工作组折叠行和展开详情在大字号下无溢出。',
    }),
    resultPreview: jsonEncode({
      'agentId': 'thread-66137cebcce11-b',
      'messageAccepted': true,
    }),
    payloadJson: '{}',
    bodies: const [],
    startedAtMs: 122_000,
    finishedAtMs: 123_000,
  ),
  WorkGroupToolCall(
    id: 'matrix-send-message',
    seq: 10,
    callId: 'call-send-message',
    toolName: 'send_message',
    presentationContract: 'builtin.send_message@1',
    status: 'succeeded',
    summary: 'send_message',
    arguments: jsonEncode({
      'target': 'thread-66137cebcce11-c',
      'targetName': 'builder',
      'message': '请补充实时工作组对照预览并验证分析检查。',
    }),
    resultPreview: jsonEncode({'messageAccepted': true}),
    payloadJson: '{}',
    bodies: const [],
    startedAtMs: 123_000,
    finishedAtMs: 124_000,
  ),
  WorkGroupFileChange(
    id: 'matrix-file-change',
    seq: 11,
    summary: 'work_group/work_group_member_view.dart',
    payloadJson: jsonEncode({
      'contract': 'anywork.event/1',
      'type': 'fileChange',
      'data': {
        'path': 'work_group/work_group_member_view.dart',
        'action': 'modified',
      },
    }),
    bodies: const [],
    occurredAtMs: 124_000,
  ),
  const WorkGroupSkill(
    id: 'matrix-skill',
    seq: 12,
    name: 'flutter-studio-build',
    summary: 'flutter-studio-build',
    payloadJson: '{"name":"flutter-studio-build","summary":"无头预览与分析规范"}',
    occurredAtMs: 125_000,
  ),
];

@Preview(name: '工作组 / 顶行思考摘要（折叠态）', group: '实时状态栏', size: Size(760, 260))
Widget conversationLiveStatusReasoningHeaderCollapsedPreview() =>
    liveStatusPreviewHost(
      SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _previewScenario(
              '工况 1 · 仅展示最新单条思考摘要（含行内加粗，折叠态）',
              _liveMachineSurface(
                snapshot: LiveStatusSnapshot(
                  revision: 1,
                  phase: LiveStatusWorking(
                    items: [
                      const WorkGroupReasoning(
                        id: 'collapsed-r1',
                        seq: 1,
                        text: '先梳理旧状态机字段',
                        summary: '**梳理**旧状态机字段',
                        outcome: 'completed',
                        startedAtMs: 100_000,
                        finishedAtMs: 104_000,
                      ),
                      const WorkGroupReasoning(
                        id: 'collapsed-r2',
                        seq: 2,
                        text: 'Designing **ToolResult** views for work group rows',
                        summary: 'Designing **ToolResult** views',
                        outcome: 'running',
                        startedAtMs: 104_000,
                      ),
                      WorkGroupToolCall(
                        id: 'collapsed-exec',
                        seq: 3,
                        callId: 'collapsed-exec',
                        toolName: 'exec',
                        presentationContract: 'builtin.exec@2',
                        status: 'running',
                        summary: 'exec',
                        arguments: '{"command":"cargo test -p pl-studio-runtime timeline::"}',
                        payloadJson: '{}',
                        bodies: const [],
                        startedAtMs: 106_000,
                      ),
                    ],
                    reasoningPreview: 'Designing **ToolResult** views',
                    startedAtMs: 100_000,
                  ),
                  attentions: const [],
                  suppressedByInteraction: false,
                ),
                liveWorkInitiallyExpanded: false,
                now: () => DateTime.fromMillisecondsSinceEpoch(138_000),
              ),
            ),
            _previewScenario(
              '工况 2 · 多段无换行强调安全分隔（无星号乱码）',
              _liveMachineSurface(
                snapshot: LiveStatusSnapshot(
                  revision: 2,
                  phase: LiveStatusWorking(
                    items: const [
                      WorkGroupReasoning(
                        id: 'collapsed-r3',
                        seq: 1,
                        text: '详细分析行内代码与加粗边界',
                        summary:
                            '**Phase A****Designing `WorkGroupMemberView`**',
                        outcome: 'completed',
                        startedAtMs: 100_000,
                        finishedAtMs: 108_000,
                      ),
                    ],
                    reasoningPreview:
                        '**Phase A****Designing `WorkGroupMemberView`**',
                    startedAtMs: 100_000,
                  ),
                  attentions: const [],
                  suppressedByInteraction: false,
                ),
                liveWorkInitiallyExpanded: false,
                now: () => DateTime.fromMillisecondsSinceEpoch(116_000),
              ),
            ),
          ],
        ),
      ),
    );

@Preview(name: '工作组 / 实时展开混合条目矩阵', group: '实时状态栏', size: Size(820, 1080))
Widget conversationLiveStatusMixedMatrixPreview() => liveStatusPreviewHost(
  _liveMachineSurface(
    snapshot: LiveStatusSnapshot(
      revision: 1,
      phase: LiveStatusWorking(
        items: _buildMixedWorkGroupMembers(),
        reasoningPreview:
            'Designing **ToolResult** views 与 `WorkGroupMemberView`',
        startedAtMs: 100_000,
      ),
      attentions: const [],
      suppressedByInteraction: false,
    ),
    liveWorkInitiallyExpanded: true,
    now: () => DateTime.fromMillisecondsSinceEpoch(138_000),
  ),
);

@Preview(name: '工作组 / 实时成员展开详情态', group: '实时状态栏', size: Size(820, 1060))
Widget conversationLiveStatusMemberDetailsExpandedPreview() {
  DateTime previewNow() => DateTime.fromMillisecondsSinceEpoch(138_000);
  final members = _buildMixedWorkGroupMembers();
  final selected = [
    members[0], // 带 Markdown 正文的思考
    members[4], // 失败 exec（含命令与 stderr 分组）
    members[6], // WorkGroupAgent
    members[11], // WorkGroupSkill
  ];
  return liveStatusPreviewHost(
    ConversationActivityBar(
      children: [
        Builder(
          builder: (context) => TimelineWorkGroupShell(
            scrollBody: true,
            railInset: 15.5,
            railContentInset: 25.5,
            initiallyExpanded: true,
            disclosureKey: const ValueKey('preview-live-details-disclosure'),
            headerBuilder: (context, expanded) {
              const titleText =
                  'Designing **ToolResult** views 与 `WorkGroupMemberView`';
              final titleStyle = context.text.bodySmall!.copyWith(
                color: context.colors.onSurface,
                fontSize: TimelineActivityRow.headerFontSize,
                fontWeight: FontWeight.w500,
                height: 1.36,
              );
              return TimelineActivityRow(
                label: timelineMarkdownPlainText(titleText),
                labelWidget: TimelineReasoningSummary(
                  id: 'preview-live-details-summary',
                  text: titleText,
                  style: titleStyle,
                  strutStyle: TimelineActivityRow.headerStrutStyle,
                  inlineCodeBackgroundColor: context.colors.surfaceContainerHigh
                      .withValues(alpha: .75),
                ),
                labelColor: titleStyle.color,
                icon: Icons.psychology_outlined,
                iconColor: StudioTone.active.indicator(context),
                indicatorStyle: TimelineActivityIndicatorStyle.restingCat,
                active: true,
                emphasized: true,
                header: true,
                expandable: true,
                expanded: expanded,
                meta: '执行了 38 秒',
                tooltip: null,
              );
            },
            bodyBuilder: (context) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < selected.length; i++) ...[
                  if (i > 0) const SizedBox(height: 2),
                  WorkGroupMemberView(
                    key: ValueKey('details-${selected[i].id}'),
                    member: selected[i],
                    isLive: true,
                    now: previewNow,
                    initiallyExpanded: i < 2,
                    bodyBuilder: (id, text) => TimelineMarkdown(
                      id: id,
                      text: text,
                      onLink: (_) {},
                      isSafeLink: (_) => false,
                      imageBuilder: (_, url) => Text(url),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

@Preview(name: '工作组对照 / 实时 vs 历史工作组', group: '实时状态栏', size: Size(820, 820))
Widget conversationLiveVsHistoryWorkGroupPreview() {
  DateTime previewNow() => DateTime.fromMillisecondsSinceEpoch(138_000);
  final mixed = _buildMixedWorkGroupMembers();
  final historyAgent = WorkGroupAgent(
    id: 'history-agent-1',
    seq: 7,
    agentId: 'thread-66137d7bee82c-14',
    name: 'thread-66137d7bee82c-14',
    status: 'completed',
    summary: '审查工作组成员注册分派与单行排版',
    payloadJson: jsonEncode({
      'contract': 'anywork.event/1',
      'type': 'agent',
      'data': {
        'identity': {'role': 'reviewer', 'taskSummary': '审查工作组成员注册分派与单行排版'},
        'outcome': {'kind': 'completed'},
      },
    }),
    startedAtMs: 120_000,
    finishedAtMs: 132_000,
  );
  final sharedMembers = [
    mixed[0],
    mixed[3],
    mixed[4],
    historyAgent,
    mixed[10],
    mixed[11],
  ];
  return liveStatusPreviewHost(
    SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _previewScenario(
            '工况 1 · 实时工作组（顶行最新思考摘要 + 状态猫 + 共用 WorkGroupMemberView）',
            _liveMachineSurface(
              snapshot: LiveStatusSnapshot(
                revision: 1,
                phase: LiveStatusWorking(
                  items: [
                    sharedMembers[0],
                    mixed[2],
                    sharedMembers[1],
                    mixed[6],
                  ],
                  reasoningPreview: 'Designing **ToolResult** views',
                  startedAtMs: 100_000,
                ),
                attentions: const [],
                suppressedByInteraction: false,
              ),
              liveWorkInitiallyExpanded: true,
              now: previewNow,
            ),
          ),
          _previewScenario(
            '工况 2 · 历史已封存工作组（顶行纯文本工作时长 + 共用 WorkGroupMemberView）',
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: CompletionRunView(
                id: 'preview-history-vs-live',
                timing: const WorkTiming(
                  startedAtMillis: 100_000,
                  finishedAtMillis: 138_000,
                ),
                initiallyExpanded: true,
                location: WorkDisplayLocation.history,
                childBuilder: (_) => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final member in sharedMembers.take(5))
                      WorkGroupMemberView(
                        key: ValueKey('history-${member.id}'),
                        member: member,
                        isLive: false,
                        now: previewNow,
                        bodyBuilder: (id, text) => TimelineMarkdown(
                          id: id,
                          text: text,
                          onLink: (_) {},
                          isSafeLink: (_) => false,
                          imageBuilder: (_, url) => Text(url),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

@Preview(
  name: '工作组 / 360px 窄窗 150% 大字排版',
  group: '实时状态栏',
  size: Size(360, 1020),
)
Widget conversationLiveStatusWorkGroupNarrowScaledPreview() {
  DateTime previewNow() => DateTime.fromMillisecondsSinceEpoch(138_000);
  final mixed = _buildMixedWorkGroupMembers();
  return liveStatusPreviewHost(
    SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _previewScenario(
            '折叠态顶行（360px / 1.5x）',
            _liveMachineSurface(
              snapshot: LiveStatusSnapshot(
                revision: 1,
                phase: LiveStatusWorking(
                  items: mixed,
                  reasoningPreview: 'Designing **ToolResult** views for `WorkGroupMemberView` in narrow panes',
                  startedAtMs: 100_000,
                ),
                attentions: const [],
                suppressedByInteraction: false,
              ),
              liveWorkInitiallyExpanded: false,
              now: previewNow,
            ),
          ),
          _previewScenario(
            '展开态混合成员（360px / 1.5x）',
            _liveMachineSurface(
              snapshot: LiveStatusSnapshot(
                revision: 2,
                phase: LiveStatusWorking(
                  items: [
                    mixed[0],
                    mixed[2],
                    mixed[4],
                    mixed[6],
                    mixed[7],
                    mixed[8],
                    mixed[9],
                    mixed[10],
                    mixed[11],
                  ],
                  reasoningPreview: 'Designing **ToolResult** views',
                  startedAtMs: 100_000,
                ),
                attentions: const [],
                suppressedByInteraction: false,
              ),
              liveWorkInitiallyExpanded: true,
              now: previewNow,
            ),
          ),
        ],
      ),
    ),
    scale: 1.5,
  );
}
