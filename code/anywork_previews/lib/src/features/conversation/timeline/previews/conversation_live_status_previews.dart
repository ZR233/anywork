import 'dart:convert';

import 'package:anywork_client/models.dart' hide LiveStatusIdle;
import 'package:anywork_client/models.dart' as feed show LiveStatusIdle;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/widget_previews.dart';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/timeline_views.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_display_unit_view.dart';

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
  List<LiveStatusAttention> presentationAttentions = const [],
  WidgetBuilder? liveWorkChildBuilder,
  bool liveWorkInitiallyExpanded = false,
  DateTime Function()? now,
}) {
  final previewNow = now ?? () => DateTime.fromMillisecondsSinceEpoch(225_000);
  final projected = LiveStatusMachine.project(
    'preview-thread',
    snapshot,
    receivedAt: previewNow(),
  );
  final presentation = switch (projected.gate) {
    LiveStatusPresenting(:final presentation) => presentation,
    _ => null,
  };
  final gate = presentationAttentions.isEmpty
      ? projected.gate
      : LiveStatusPresenting(
          presentation: LiveStatusPresentation(
            primary: presentation?.primary,
            attentions: [
              ...?presentation?.attentions,
              ...presentationAttentions,
            ],
          ),
        );
  return LiveStatusSurfaceView(
    gate: gate,
    liveWorkChildBuilder: liveWorkChildBuilder,
    liveWorkInitiallyExpanded: liveWorkInitiallyExpanded,
    now: previewNow,
  );
}

// Storage variants are explicit pure-view fixtures. They do not reconstruct
// runtime activity or manufacture another feed projection.
LiveStorageAttention _storageAttention(ThreadStorageStateView storage) =>
    LiveStorageAttention(
      activity: const ConversationActivityView(
        identity: 'preview-storage',
        kind: ConversationActivityKind.storageBlocked,
      ),
      storage: storage,
      severity: LiveStorageSeverity.fromStorage(storage),
    );

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
                  LiveWorkItem(
                    id: 'preview-exec-call',
                    callId: 'preview-exec-call',
                    kind: 'tool',
                    toolName: 'exec',
                    status: 'running',
                    summary: 'cargo flutter test --no-pub test/ui',
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
          LiveWorkItem(
            id: 'preview-command',
            callId: 'preview-command',
            kind: 'tool',
            toolName: 'read_file',
            status: 'running',
            summary: '读取 design/26-timeline-content.md',
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
    liveWorkChildBuilder: (_) => const Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TimelineReasoningView(
          summary: '梳理 **会话共享组件** 与状态机迁移边界',
          running: true,
          body: ConversationCurrentWindowView(
            id: 'preview-reasoning',
            text: '核对现有调用链和组件边界，随后检查布局和状态。',
          ),
        ),
        TimelineToolItemView(
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
        TimelineToolItemView(
          workGroupMember: true,
          item: TimelineToolPresentation(
            id: 'preview-read',
            toolCallId: 'preview-read',
            name: 'read_file',
            presentationContract: 'builtin.read_file@1',
            statusString: 'running',
            arguments: '{"path":"design/26-timeline-content.md"}',
            output: '',
          ),
        ),
      ],
    ),
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
      ),
      attentions: [],
      suppressedByInteraction: false,
    ),
  ),
);

@Preview(name: '工作组 · 调用失败后继续思考（折叠单行）', group: '实时状态栏', size: Size(1067, 110))
Widget conversationLiveStatusFailedCallPreview() => liveStatusPreviewHost(
  _liveMachineSurface(
    snapshot: LiveStatusSnapshot(
      revision: 1,
      phase: LiveStatusWorking(items: [], startedAtMs: 154_000),
      attentions: [],
      suppressedByInteraction: false,
    ),
    now: () => DateTime.fromMillisecondsSinceEpoch(225_000),
    liveWorkChildBuilder: (_) => const TimelineToolItemView(
      item: TimelineToolPresentation(
        id: 'preview-failed-call',
        toolCallId: 'preview-failed-call',
        name: 'exec',
        presentationContract: 'builtin.exec@2',
        statusString: 'failed',
        arguments: '{"command":"cargo flutter analyze"}',
        output: r'{"stdout":{"content":""},"stderr":{"content":"静态分析检查失败。"},"exitCode":1}',
        error: '命令退出码 1',
        exitCode: 1,
      ),
    ),
  ),
);

@Preview(name: '工作组 · 推理详情', group: '实时状态栏', size: Size(760, 260))
Widget conversationLiveStatusThinkingPreview() => liveStatusPreviewHost(
  _liveMachineSurface(
    snapshot: LiveStatusSnapshot(
      revision: 1,
      phase: LiveStatusWorking(
        items: [],
        reasoningPreview: '梳理 **会话共享组件** 与状态机转换条件',
        startedAtMs: 100_000,
      ),
      attentions: [],
      suppressedByInteraction: false,
    ),
    liveWorkInitiallyExpanded: true,
    now: () => DateTime.fromMillisecondsSinceEpoch(225_000),
    liveWorkChildBuilder: (_) => const TimelineReasoningView(
      summary: '梳理 **会话共享组件** 与状态机转换条件',
      running: true,
      body: ConversationCurrentWindowView(
        id: 'preview-thinking-detail',
        text: '核对现有调用链和组件边界，确认流式正文开始时前序工作组已封存。',
      ),
    ),
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
          LiveWorkItem(
            id: 'preview-wait-member',
            callId: 'preview-wait-member',
            kind: 'tool',
            toolName: 'wait',
            status: 'running',
            summary: '等待成员汇报结果',
          ),
        ],
        startedAtMs: 100_000,
      ),
      attentions: [],
      suppressedByInteraction: false,
    ),
    liveWorkInitiallyExpanded: true,
    now: () => DateTime.fromMillisecondsSinceEpoch(225_000),
    liveWorkChildBuilder: (_) => TimelineWaitDetails(
      identity: 'preview-wait-member',
      presentation: ThreadWaitPresentationView(
        intent: ThreadWaitEventsIntentView(
          targets: [
            ThreadWaitTargetView(
              taskId: 'explorer',
              toolName: 'delegation',
              summary: '梳理组件边界',
              status: ThreadWaitTargetStatusView.succeeded,
            ),
            ThreadWaitTargetView(
              taskId: 'reviewer',
              toolName: 'delegation',
              summary: '复核布局与状态文案',
              status: ThreadWaitTargetStatusView.running,
            ),
          ],
          timeoutMs: 300000,
        ),
        state: ThreadWaitStateView.waiting,
        messagesReady: false,
      ),
    ),
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
            presentationAttentions: [
              _storageAttention(
                const ThreadStorageStateView(
                  fault: ThreadHistoryFault.writeFailed,
                  faultGeneration: 1,
                  execution: ThreadStorageExecution.paused,
                  resumeRequired: true,
                  canResume: true,
                  lastError: '保存暂时失败，当前内容已保留。',
                ),
              ),
            ],
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
            presentationAttentions: [
              _storageAttention(
                const ThreadStorageStateView(
                  fault: ThreadHistoryFault.writeFailed,
                  faultGeneration: 2,
                  execution: ThreadStorageExecution.paused,
                  resumeRequired: true,
                  canResume: false,
                  lastError: '保存暂时失败，当前内容已保留。',
                ),
              ),
            ],
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
            presentationAttentions: [
              _storageAttention(
                const ThreadStorageStateView(
                  pressurePaused: true,
                  execution: ThreadStorageExecution.running,
                ),
              ),
            ],
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
            presentationAttentions: [
              _storageAttention(
                const ThreadStorageStateView(
                  resumeRequired: true,
                  canResume: false,
                  execution: ThreadStorageExecution.paused,
                ),
              ),
            ],
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
            presentationAttentions: [
              _storageAttention(
                const ThreadStorageStateView(
                  execution: ThreadStorageExecution.paused,
                ),
              ),
            ],
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
              '工况 1 · 命令执行与工作组展开（> 60 分钟进位小时 + 错误提示）',
              _liveMachineSurface(
                snapshot: LiveStatusSnapshot(
                  revision: 1,
                  phase: LiveStatusWorking(
                    items: [
                      LiveWorkItem(
                        id: 'hourly-exec',
                        callId: 'hourly-exec',
                        kind: 'tool',
                        toolName: 'exec',
                        status: 'running',
                        summary: 'cargo flutter test --no-pub test/ui',
                        startedAtMs: (100) * 1000,
                      ),
                    ],
                    startedAtMs: 100_000,
                  ),
                  attentions: [
                    LiveAttention(
                      id: 'preview-read-error',
                      kind: 'error',
                      summary: '最近一次集合分页请求超时，请重试',
                    ),
                  ],
                  suppressedByInteraction: false,
                ),
                liveWorkInitiallyExpanded: true,
                liveWorkChildBuilder: (_) => const Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TimelineToolItemView(
                      item: TimelineToolPresentation(
                        id: 'hourly-exec',
                        toolCallId: 'hourly-exec',
                        name: 'exec',
                        presentationContract: 'builtin.exec@2',
                        statusString: 'running',
                        arguments:
                            '{"command":"cargo flutter test --no-pub test/ui"}',
                        output: '',
                      ),
                    ),
                    TimelineToolItemView(
                      item: TimelineToolPresentation(
                        id: 'hourly-write',
                        toolCallId: 'hourly-write',
                        name: 'write_file',
                        presentationContract: 'builtin.write_file@1',
                        statusString: 'succeeded',
                        arguments: '{"path":"design/19-studio-ui.md"}',
                        output: '',
                      ),
                    ),
                  ],
                ),
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
                      LiveWorkItem(
                        id: 'write-tool',
                        callId: 'write-tool',
                        kind: 'tool',
                        toolName: 'write_file',
                        status: 'running',
                        summary: '写入 design/19-studio-ui.md',
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
      phase: LiveStatusWorking(items: [], startedAtMs: 100_000),
      attentions: [
        LiveAttention(
          id: 'preview-narrow-approval',
          kind: 'approval',
          summary: 'exec: cargo flutter test --no-pub test/ui',
        ),
      ],
      suppressedByInteraction: false,
    ),
    presentationAttentions: [
      _storageAttention(
        const ThreadStorageStateView(
          fault: ThreadHistoryFault.writeFailed,
          faultGeneration: 1,
          execution: ThreadStorageExecution.paused,
          resumeRequired: true,
          canResume: true,
        ),
      ),
    ],
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
        items: [],
        reasoningPreview: '核对运行期选择器锁定规则',
        startedAtMs: 100_000,
      ),
      attentions: [],
      suppressedByInteraction: false,
    ),
    liveWorkInitiallyExpanded: true,
    now: () => DateTime.fromMillisecondsSinceEpoch(225_000),
    liveWorkChildBuilder: (_) => const Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TimelineReasoningView(
          summary: '梳理会话共享组件与锁定边界',
          startedAt: 100,
          finishedAt: null,
          body: ConversationCurrentWindowView(
            id: 'summary-body',
            text: '先核对现有调用链和组件边界，再确认布局、状态文案与自适应高度。',
          ),
        ),
        TimelineReasoningView(
          summary: '核对运行期选择器锁定规则',
          startedAt: 100,
          finishedAt: null,
        ),
        TimelineReasoningView(
          startedAt: 100,
          finishedAt: null,
          body: ConversationCurrentWindowView(
            id: 'body-only',
            text: '会话运行时保留草稿与附件。工作模式、模型和思考强度在当前轮次执行期间保持锁定。',
          ),
        ),
      ],
    ),
  ),
);

@Preview(name: '工作组 · 长工具输出', group: '实时状态栏', size: Size(760, 300))
Widget conversationLiveStatusLongToolPreview() => liveStatusPreviewHost(
  _liveMachineSurface(
    snapshot: LiveStatusSnapshot(
      revision: 1,
      phase: LiveStatusWorking(
        items: [
          LiveWorkItem(
            id: 'long-tool-output',
            callId: 'long-tool-output',
            kind: 'tool',
            toolName: 'exec',
            status: 'running',
            summary: 'cargo flutter analyze',
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
    liveWorkChildBuilder: (_) => TimelineToolItemView(
      initiallyExpanded: true,
      item: TimelineToolPresentation(
        id: 'long-tool-output',
        toolCallId: 'long-tool-output',
        name: 'exec',
        presentationContract: 'builtin.exec@2',
        statusString: 'running',
        arguments: '{"command":"cargo flutter analyze"}',
        output: jsonEncode({
          'stdout': {
            'content': [for (var i = 1; i <= 60; i++) '检查第 $i 项：通过。']
                .join('\n'),
          },
          'stderr': {'content': ''},
        }),
      ),
    ),
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
