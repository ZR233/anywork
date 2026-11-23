import 'dart:convert';

import 'package:anywork_client/models.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/widget_previews.dart';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/timeline_views.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_display_unit_view.dart';

import 'timeline_preview_fixtures.dart';
import 'expanded_work_timeline_fixture.dart' show ExpandedWorkPreviewControls;

import 'package:anywork/src/features/conversation/timeline/widgets/timeline_resting_cat.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_reasoning_view.dart';

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
    '接下来继续核对各项交互：保留当前草稿与附件，检查宽窄窗口下的对齐，并逐项确认停止、等待和保存异常的呈现。\n\n'
    '成员完成后继续留在原工作组；首个可靠 Single 边界封存工作组，不等待全部成员进入 terminal。继续检查不同文字缩放下的自然高度与阅读位置，确保新内容不会打断正在进行的阅读。';

Widget liveStatusGroupPreview({
  bool idle = false,
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
  if (idle) {
    return _ActivityPreview(
      thinkingSummary: '梳理 **会话共享组件** 与 `LiveStatusBar` 锁定边界',
      activity: const ConversationActivityView(
        identity: 'preview-group-idle',
        kind: ConversationActivityKind.thinking,
      ),
      timing: const WorkTiming(startedAtMillis: 100_000),
      childBuilder: (_) => const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TimelineReasoningView(
            summary: '梳理 **会话共享组件** 与 `LiveStatusBar` 锁定边界',
            startedAt: 100,
            finishedAt: 140,
            body: ConversationCurrentWindowView(
              id: 'preview-idle-reasoning',
              text: '核对现有调用链和组件边界，随后检查布局和状态。',
            ),
          ),
          TimelineToolItemView(
            item: TimelineToolPresentation(
              id: 'preview-idle-command',
              toolCallId: 'preview-idle-command',
              name: 'exec',
              presentationContract: 'builtin.exec@2',
              statusString: 'succeeded',
              arguments: '{"command":"cargo flutter analyze"}',
              output: r'{"stdout":{"content":"No issues found!"},"stderr":{"content":""},"exitCode":0}',
            ),
          ),
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
        activity: _threadActivity(
          ThreadActivityKind.thinking,
          identity: 'preview-cat-thinking',
          thinkingSeconds: 17,
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
        activity: _threadActivity(
          ThreadActivityKind.compacting,
          identity: 'preview-zip-compacting',
        ),
      ),
    ],
  ),
);

Widget _liveMachineSurface({
  ThreadActivityView? activity,
  ThreadStorageStateView? storage,
  List<PendingInteraction> interactions = const [],
  ThreadBusinessRefs? businessRefs,
  String? activeTurnId = 'preview-turn',
  CurrentAtomSnapshot? current,
  DisplayBlock? liveOpenWork,
  Set<String> renderedCurrentAtomIds = const {},
  LiveConnectionStatus connectionStatus = LiveConnectionStatus.connected,
  String? connectionDetail,
  Object? currentAtomsError,
  String? previewResponseText,
  int? previewResponseStartedAt,
  LiveActivityToolsWindow? activityTools,
  WidgetBuilder? liveWorkChildBuilder,
  bool liveWorkInitiallyExpanded = false,
  DateTime Function()? now,
}) {
  final projected = LiveStatusMachine.project(
    threadId: 'preview-thread',
    inputs: LiveStatusInputs(
      storage: storage,
      interactions: interactions,
      businessRefs: businessRefs,
      activeTurnId: activeTurnId,
      activity: activity,
      current: current,
      liveOpenWork: liveOpenWork,
      renderedCurrentAtomIds: renderedCurrentAtomIds,
      hasContentOwner: true,
      connectionStatus: connectionStatus,
      connectionDetail: connectionDetail,
      currentAtomsError: currentAtomsError,
      previewResponseText: previewResponseText,
      previewResponseStartedAt: previewResponseStartedAt,
    ),
    activityTools: activityTools,
  );
  return LiveStatusSurfaceView(
    gate: projected.gate,
    liveWorkChildBuilder: liveWorkChildBuilder,
    liveWorkInitiallyExpanded: liveWorkInitiallyExpanded,
    now: now,
  );
}

ThreadActivityView _threadActivity(
  ThreadActivityKind kind, {
  String identity = 'preview',
  String summary = '',
  String? thinkingSummary,
  int? thinkingSeconds,
  ThreadActivityTools tools = ThreadActivityTools.empty,
}) => ThreadActivityView(
  threadId: 'preview-thread',
  identity: identity,
  revision: 1,
  turnId: 'preview-turn',
  kind: kind,
  summary: summary,
  thinkingSummary: thinkingSummary,
  thinkingSeconds: thinkingSeconds,
  tools: tools,
);

@Preview(name: '四态顶栏指示器零抖动对比', group: '实时状态栏', size: Size(760, 440))
Widget conversationFourStatesComparisonPreview() => liveStatusPreviewHost(
  SingleChildScrollView(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _liveMachineSurface(
          activity: _threadActivity(
            ThreadActivityKind.waitingApi,
            identity: 'preview-four-thinking',
            thinkingSeconds: 17,
          ),
        ),
        _liveMachineSurface(
          activity: _threadActivity(
            ThreadActivityKind.runningTool,
            identity: 'preview-four-exec',
            tools: ThreadActivityTools(
              count: 1,
              active: const [
                ThreadActivityToolEntry(
                  callId: 'preview-exec-call',
                  name: 'exec',
                  summary: 'cargo flutter test --no-pub test/ui',
                  arguments: ThreadActivityArgumentsKind.commandLine,
                  state: ThreadActivityToolState.running,
                  startedAt: 100,
                ),
              ],
            ),
          ),
        ),
        _liveMachineSurface(
          previewResponseText: '四态顶栏共享同一 32×32 引导槽位与 15px 标题字号，切换零位移。',
          previewResponseStartedAt: 100,
          now: () => DateTime.fromMillisecondsSinceEpoch(117_000),
        ),
        _liveMachineSurface(
          activity: _threadActivity(
            ThreadActivityKind.compacting,
            identity: 'preview-four-compacting',
          ),
        ),
      ],
    ),
  ),
);

@Preview(name: '思考中 · 无内容', group: '实时状态栏', size: Size(760, 110))
Widget conversationLiveStatusWaitingPreview() => liveStatusPreviewHost(
  _liveMachineSurface(
    activity: _threadActivity(
      ThreadActivityKind.waitingApi,
      identity: 'preview-waiting',
      thinkingSeconds: 17,
    ),
  ),
);

@Preview(name: '正在压缩上下文', group: '实时状态栏', size: Size(760, 110))
Widget conversationLiveStatusCompactingPreview() => liveStatusPreviewHost(
  _liveMachineSurface(
    activity: _threadActivity(
      ThreadActivityKind.compacting,
      identity: 'preview-compacting',
    ),
  ),
);

@Preview(name: '工作组 · 进行中', group: '实时状态栏', size: Size(760, 300))
Widget conversationLiveStatusToolsPreview() => liveStatusPreviewHost(
  _TimelineWorkPreviewHost(work: liveStatusGroupPreview()),
);

@Preview(name: '工作组 · 调用失败后继续思考（折叠单行）', group: '实时状态栏', size: Size(1067, 110))
Widget conversationLiveStatusFailedCallPreview() => liveStatusPreviewHost(
  _TimelineWorkPreviewHost(
    work: _ActivityPreview(
      activity: const ConversationActivityView(
        identity: 'preview-failed-call-thinking',
        kind: ConversationActivityKind.thinking,
      ),
      timing: const WorkTiming(startedAtMillis: 154_000),
      childBuilder: (_) => const TimelineToolItemView(
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
  ),
);

@Preview(name: '工作组 · 成员完成待交接', group: '实时状态栏', size: Size(760, 300))
Widget conversationLiveStatusIdleGroupPreview() => liveStatusPreviewHost(
  _TimelineWorkPreviewHost(work: liveStatusGroupPreview(idle: true)),
);

@Preview(name: '工作组 · 已完成', group: '实时状态栏', size: Size(760, 150))
Widget conversationLiveStatusCompletedGroupPreview() => liveStatusPreviewHost(
  _TimelineWorkPreviewHost(
    work: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26),
      child: liveStatusGroupPreview(history: true),
    ),
  ),
);

@Preview(name: '工作组 · 推理详情', group: '实时状态栏', size: Size(760, 260))
Widget conversationLiveStatusThinkingPreview() => liveStatusPreviewHost(
  _TimelineWorkPreviewHost(work: liveStatusGroupPreview(thinkingOnly: true)),
);

@Preview(name: '正文 · 长文与跟随', group: '实时状态栏', size: Size(760, 300))
Widget conversationLiveStatusRespondingPreview() => liveStatusPreviewHost(
  _liveMachineSurface(
    previewResponseText: liveStatusResponseText,
    previewResponseStartedAt: 100,
    now: () => DateTime.fromMillisecondsSinceEpoch(125_000),
  ),
);

@Preview(name: '正文 · 短文自然高度', group: '实时状态栏', size: Size(760, 180))
Widget conversationLiveStatusShortResponsePreview() => liveStatusPreviewHost(
  _liveMachineSurface(
    previewResponseText: '已完成组件布局调整，正在核对各工况。',
    previewResponseStartedAt: 100,
    now: () => DateTime.fromMillisecondsSinceEpoch(108_000),
  ),
);

@Preview(name: '等待成员', group: '实时状态栏', size: Size(760, 300))
Widget conversationLiveStatusWaitPreview() => liveStatusPreviewHost(
  _TimelineWorkPreviewHost(
    work: _ActivityPreview(
      timing: const WorkTiming(startedAtMillis: 100_000),
      childBuilder: (_) => TimelineWaitDetails(
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
  ),
);

@Preview(name: '窄窗 · 160% 文字缩放', group: '实时状态栏', size: Size(360, 380))
Widget conversationLiveStatusNarrowScaledPreview() => liveStatusPreviewHost(
  _TimelineWorkPreviewHost(work: liveStatusGroupPreview()),
  scale: 1.6,
);

@Preview(name: '宽窗 · 正文', group: '实时状态栏', size: Size(1040, 300))
Widget conversationLiveStatusWidePreview() => liveStatusPreviewHost(
  _liveMachineSurface(
    previewResponseText: liveStatusResponseText,
    previewResponseStartedAt: 100,
    now: () => DateTime.fromMillisecondsSinceEpoch(125_000),
  ),
);

@Preview(name: '停止中', group: '实时状态栏', size: Size(760, 110))
Widget conversationLiveStatusStoppingPreview() => liveStatusPreviewHost(
  _liveMachineSurface(
    activity: _threadActivity(
      ThreadActivityKind.stopping,
      identity: 'preview-stopping',
    ),
  ),
);

@Preview(name: '存储状态五态对比', group: '实时状态栏', size: Size(760, 440))
Widget conversationLiveStatusStorageFailurePreview() => liveStatusPreviewHost(
  SingleChildScrollView(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _liveMachineSurface(
          storage: const ThreadStorageStateView(
            fault: ThreadHistoryFault.writeFailed,
            faultGeneration: 1,
            execution: ThreadStorageExecution.paused,
            resumeRequired: true,
            canResume: true,
            lastError: '保存暂时失败，当前内容已保留。',
          ),
        ),
        _liveMachineSurface(
          storage: const ThreadStorageStateView(
            fault: ThreadHistoryFault.writeFailed,
            faultGeneration: 2,
            execution: ThreadStorageExecution.paused,
            resumeRequired: true,
            canResume: false,
            lastError: '保存暂时失败，当前内容已保留。',
          ),
        ),
        _liveMachineSurface(
          storage: const ThreadStorageStateView(
            pressurePaused: true,
            execution: ThreadStorageExecution.running,
          ),
        ),
        _liveMachineSurface(
          storage: const ThreadStorageStateView(
            resumeRequired: true,
            canResume: false,
            execution: ThreadStorageExecution.paused,
          ),
        ),
        _liveMachineSurface(
          storage: const ThreadStorageStateView(
            execution: ThreadStorageExecution.paused,
          ),
        ),
      ],
    ),
  ),
);

@Preview(
  name: '控制与连接 · 审批 / 输入 / 重连 / 断开',
  group: '实时状态栏',
  size: Size(760, 420),
)
Widget conversationLiveStatusControlAndConnectionPreview() =>
    liveStatusPreviewHost(
      SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _liveMachineSurface(
              activity: _threadActivity(
                ThreadActivityKind.stopping,
                identity: 'preview-ctrl-stopping',
              ),
            ),
            _liveMachineSurface(
              activity: _threadActivity(
                ThreadActivityKind.awaitingApproval,
                identity: 'preview-ctrl-approval',
                summary: 'exec: cargo test',
              ),
            ),
            _liveMachineSurface(
              activity: _threadActivity(
                ThreadActivityKind.awaitingInput,
                identity: 'preview-ctrl-input',
                summary: '确认发布分支目标',
              ),
            ),
            _liveMachineSurface(
              connectionStatus: LiveConnectionStatus.reconnecting,
            ),
            _liveMachineSurface(
              connectionStatus: LiveConnectionStatus.disconnected,
            ),
          ],
        ),
      ),
    );

@Preview(name: '主阶段 · 流式正文与伴随工作组', group: '实时状态栏', size: Size(760, 600))
Widget conversationLiveStatusResponseWithWorkPreview() => liveStatusPreviewHost(
  _liveMachineSurface(
    activity: _threadActivity(
      ThreadActivityKind.responding,
      identity: 'preview-resp-work',
      thinkingSummary: '梳理 **状态机** 与 `LiveStatusSurfaceView` 复用边界',
    ),
    liveOpenWork: DisplayBlock(
      id: 'preview-companion-work',
      blockOrder: 1,
      body: WorkDisplayBlock(
        timing: const WorkTiming(startedAtMillis: 100_000),
        summary: '梳理 **状态机** 与 `LiveStatusSurfaceView` 复用边界',
        members: const DisplayBlockRef(
          blockId: 'preview-companion-work',
          cut: HistoryCut(''),
          anchorSeq: 1,
          headSeq: 1,
        ),
        executionPresent: true,
        memberCount: 2,
        unfinishedCount: 0,
        groupClosed: false,
      ),
    ),
    previewResponseText: liveStatusResponseText,
    previewResponseStartedAt: 112,
    now: () => DateTime.fromMillisecondsSinceEpoch(225_000),
    liveWorkInitiallyExpanded: true,
    liveWorkChildBuilder: (_) => const Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TimelineReasoningView(
          summary: '确认四选一主阶段与正交关注条分层',
          startedAt: 100,
          finishedAt: 112,
        ),
        TimelineToolItemView(
          item: TimelineToolPresentation(
            id: 'preview-companion-exec',
            toolCallId: 'preview-companion-exec',
            name: 'exec',
            presentationContract: 'builtin.exec@2',
            statusString: 'succeeded',
            arguments: '{"command":"cargo flutter analyze"}',
            output: r'{"stdout":{"content":"No issues found!"},"stderr":{"content":""},"exitCode":0}',
          ),
        ),
      ],
    ),
  ),
);

@Preview(name: '长耗时与工具分页 · 小时 / 日', group: '实时状态栏', size: Size(760, 620))
Widget conversationLiveStatusDeferredToolsAndDurationsPreview() =>
    liveStatusPreviewHost(
      SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _liveMachineSurface(
              activity: _threadActivity(
                ThreadActivityKind.runningTool,
                identity: 'preview-hourly-work',
                tools: ThreadActivityTools(
                  count: 8,
                  active: const [
                    ThreadActivityToolEntry(
                      callId: 'hourly-exec',
                      name: 'exec',
                      summary: 'cargo flutter test --no-pub test/ui',
                      arguments: ThreadActivityArgumentsKind.commandLine,
                      state: ThreadActivityToolState.running,
                      startedAt: 100,
                    ),
                  ],
                ),
              ),
              liveOpenWork: DisplayBlock(
                id: 'preview-hourly-group',
                blockOrder: 1,
                body: WorkDisplayBlock(
                  timing: const WorkTiming(startedAtMillis: 100_000),
                  members: const DisplayBlockRef(
                    blockId: 'preview-hourly-group',
                    cut: HistoryCut(''),
                    anchorSeq: 1,
                    headSeq: 1,
                  ),
                  executionPresent: true,
                  memberCount: 2,
                  unfinishedCount: 1,
                  groupClosed: false,
                ),
              ),
              currentAtomsError: '最近一次集合分页请求超时，请重试',
              activityTools: LiveActivityToolsWindow(
                reference: const CurrentCollectionRef(
                  ownerId: 'owner-1',
                  collection: 'tools.active',
                  revision: 3,
                ),
                totalCount: 8,
                entries: const [
                  ThreadActivityToolEntry(
                    callId: 'tool-1',
                    name: 'exec',
                    summary: 'cargo flutter test --no-pub test/ui',
                    arguments: ThreadActivityArgumentsKind.commandLine,
                    state: ThreadActivityToolState.running,
                  ),
                  ThreadActivityToolEntry(
                    callId: 'tool-2',
                    name: 'read_file',
                    summary: '读取 design/19-studio-ui.md',
                    arguments: ThreadActivityArgumentsKind.opaque,
                    state: ThreadActivityToolState.finished,
                  ),
                ],
                expanded: true,
                loading: false,
                hasPrevious: false,
                hasNext: true,
              ),
              now: () => DateTime.fromMillisecondsSinceEpoch(
                100_000 + (3600 + 15 * 60 + 8) * 1000,
              ),
            ),
            _liveMachineSurface(
              activity: _threadActivity(
                ThreadActivityKind.thinking,
                identity: 'preview-daily-work',
              ),
              liveOpenWork: DisplayBlock(
                id: 'preview-daily-group',
                blockOrder: 2,
                body: WorkDisplayBlock(
                  timing: const WorkTiming(startedAtMillis: 100_000),
                  members: const DisplayBlockRef(
                    blockId: 'preview-daily-group',
                    cut: HistoryCut(''),
                    anchorSeq: 2,
                    headSeq: 2,
                  ),
                  executionPresent: true,
                  memberCount: 1,
                  unfinishedCount: 1,
                  groupClosed: false,
                ),
              ),
              now: () => DateTime.fromMillisecondsSinceEpoch(
                100_000 + (86400 + 3 * 3600 + 120) * 1000,
              ),
            ),
          ],
        ),
      ),
    );

@Preview(name: '窄窗 360px · 160% 缩放与并发审批', group: '实时状态栏', size: Size(360, 440))
Widget conversationLiveStatusNarrowMachinePreview() => liveStatusPreviewHost(
  _liveMachineSurface(
    activity: _threadActivity(
      ThreadActivityKind.awaitingApproval,
      identity: 'preview-narrow-approval',
      summary: 'exec: cargo flutter test --no-pub test/ui',
    ),
    liveOpenWork: DisplayBlock(
      id: 'preview-narrow-work',
      blockOrder: 1,
      body: WorkDisplayBlock(
        timing: const WorkTiming(startedAtMillis: 100_000),
        summary: '检查窄屏 360px 下长文本单行省略、耗时进位与并发审批展示',
        members: const DisplayBlockRef(
          blockId: 'preview-narrow-work',
          cut: HistoryCut(''),
          anchorSeq: 1,
          headSeq: 1,
        ),
        executionPresent: true,
        memberCount: 2,
        unfinishedCount: 1,
        groupClosed: false,
      ),
    ),
    storage: const ThreadStorageStateView(
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
  _TimelineWorkPreviewHost(
    work: _ActivityPreview(
      initiallyExpanded: true,
      activity: const ConversationActivityView(
        identity: 'preview-reasoning-variants',
        kind: ConversationActivityKind.thinking,
        thinkingSummary: '核对运行期选择器锁定规则',
      ),
      timing: const WorkTiming(startedAtMillis: 100_000),
      childBuilder: (_) => const Column(
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
  ),
);

@Preview(name: '工作组 · 长工具输出', group: '实时状态栏', size: Size(760, 300))
Widget conversationLiveStatusLongToolPreview() => liveStatusPreviewHost(
  _TimelineWorkPreviewHost(
    work: _ActivityPreview(
      initiallyExpanded: true,
      activity: const ConversationActivityView(
        identity: 'preview-long-tool-activity',
        kind: ConversationActivityKind.runningTool,
        activeTools: [
          ThreadActivityToolEntry(
            callId: 'long-tool-output',
            name: 'exec',
            summary: 'cargo flutter analyze',
            arguments: ThreadActivityArgumentsKind.commandLine,
            state: ThreadActivityToolState.running,
            startedAt: 100,
          ),
        ],
      ),
      childBuilder: (_) => TimelineToolItemView(
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
  ),
);

@Preview(name: '正文后开启新工作组', group: '实时状态栏', size: Size(760, 340))
Widget conversationLiveStatusNextGroupPreview() => liveStatusPreviewHost(
  _TimelineWorkPreviewHost(
    work: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
          child: liveStatusGroupPreview(history: true),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Text('前序分析已完成，下面继续执行自动化测试并汇总各工况验证结果。'),
        ),
        _ActivityPreview(
          activity: const ConversationActivityView(
            identity: 'preview-next-group-activity',
            kind: ConversationActivityKind.runningTool,
            activeTools: [
              ThreadActivityToolEntry(
                callId: 'preview-next-group-cmd',
                name: 'exec',
                summary: 'cargo flutter test --no-pub test/ui',
                arguments: ThreadActivityArgumentsKind.commandLine,
                state: ThreadActivityToolState.running,
                startedAt: 213,
              ),
            ],
          ),
          timing: const WorkTiming(startedAtMillis: 213_000),
          childBuilder: (_) => const TimelineToolItemView(
            item: TimelineToolPresentation(
              id: 'preview-next-group-cmd',
              toolCallId: 'preview-next-group-cmd',
              name: 'exec',
              presentationContract: 'builtin.exec@2',
              statusString: 'running',
              arguments: '{"command":"cargo flutter test --no-pub test/ui"}',
              output: '',
            ),
          ),
        ),
      ],
    ),
  ),
);

/// Reuses production Main and existing UI-only preview resources. Work is a
/// naturally sized bottom sliver, never a child of the limited output dock.
class _TimelineWorkPreviewHost extends StatefulWidget {
  const _TimelineWorkPreviewHost({required this.work});
  final Widget work;
  @override
  State<_TimelineWorkPreviewHost> createState() =>
      _TimelineWorkPreviewHostState();
}

class _TimelineWorkPreviewHostState extends State<_TimelineWorkPreviewHost> {
  final _controls = ExpandedWorkPreviewControls();
  TimelineDisplayMode _mode = TimelineDisplayMode.live;
  @override
  void initState() {
    super.initState();
    _controls.controller.setMessages([
      Message.custom(
        id: 'preview-work-host',
        authorId: 'assistant',
        metadata: {
          chatItemPresentationKey: TimelinePreviewFixtures.item(
            'preview-work-host',
            'text',
            const {'channel': 'final'},
          ),
        },
      ),
    ], animated: false);
  }

  @override
  void dispose() {
    _controls.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TimelineView(
    threadId: 'live-status-preview',
    controls: _controls,
    view: TimelineSessionViewState(
      threadId: 'live-status-preview',
      generation: 1,
      mode: _mode,
      connection: TimelineConnectionPhase.ready,
    ),
    canonicalPresentationBuilder: (_, _) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: widget.work,
    ),
    onLoadOlder: () async {},
    onRetryOlder: () async {},
    onReturnLive: () async {
      if (mounted) {
        setState(() => _mode = TimelineDisplayMode.live);
      }
    },
    onEnterHistory: () {
      if (mounted && _mode != TimelineDisplayMode.history) {
        setState(() => _mode = TimelineDisplayMode.history);
      }
    },
    onRetryConnection: () {},
    onLink: (_) {},
    isSafeLink: (_) => false,
    remoteImageBuilder: (_, _) => const SizedBox.shrink(),
  );
}

class _ActivityPreview extends StatelessWidget {
  const _ActivityPreview({
    required this.childBuilder,
    this.initiallyExpanded = false,
    this.activity,
    this.timing = const WorkTiming(startedAtMillis: 100_000),
    this.thinkingSummary,
  });
  final WidgetBuilder childBuilder;
  final bool initiallyExpanded;
  final ConversationActivityView? activity;
  final WorkTiming timing;
  final String? thinkingSummary;
  @override
  Widget build(BuildContext context) => CompletionRunView(
    id: 'preview-live-work',
    timing: timing,
    thinkingSummary: thinkingSummary,
    activity: activity,
    location: WorkDisplayLocation.live,
    executionPresent: true,
    initiallyExpanded: initiallyExpanded,
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
        members: const DisplayBlockRef(
          blockId: 'sealed-tool-preview-group',
          cut: HistoryCut('preview-cut'),
          anchorSeq: 2,
          headSeq: 2,
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
