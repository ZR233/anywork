import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/widget_previews.dart';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/state/tool_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/conversation_activity_bar.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/conversation_current_views.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_display_unit_view.dart';

import 'timeline_preview_fixtures.dart';

import 'package:anywork/src/features/conversation/timeline/widgets/timeline_tool_blocks.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_wait_blocks.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_compacting_zip_icon.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_resting_cat.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_reasoning_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/completion_run_view.dart';

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
    '已经把会话界面收敛为同一套共享模块：**起始页与运行期会话共用外壳、顶栏与输入框，上方时间线只放已结束内容，下方状态栏承载正在进行的工作组**。\n\n'
    '### 运行期配置可配性分层\n'
    '- **创建期一次性冻结**：工作区模式与子智能体分发在会话创建后上移至顶栏只读徽标。\n'
    '- **运行期条件锁定**：轮次运行或等待期间锁定模式、主模型与思考强度。\n'
    '- **子智能体只读**：详情展示历史、进展与工作区，主会话保持独立草稿。\n\n'
    '长正文达到可用高度后在区内滚动，向上阅读或选择文字暂停跟随，点击“跟随输出”回到底部。\n\n'
    '接下来继续核对各项交互：保留当前草稿与附件，检查宽窄窗口下的对齐，并逐项确认停止、等待和保存异常的呈现。\n\n'
    '成员完成后继续留在当前工作组，真实边界确定且成员收束后整组进入时间线。继续检查不同文字缩放下的自然高度与阅读位置，确保新内容不会打断正在进行的阅读。';

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
      timing: const WorkTiming(startedAt: 100, finishedAt: null),
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
          TimelineToolDetails(
            item: TimelineToolPresentation(
              id: 'preview-idle-command',
              toolCallId: 'preview-idle-command',
              name: 'exec',
              presentationContract: 'builtin.exec@2',
              statusString: 'succeeded',
              arguments: '{"command":"cargo flutter analyze"}',
              output: 'No issues found!',
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
    timing: WorkTiming(startedAt: 100, finishedAt: null),
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
          const TimelineToolDetails(
            item: TimelineToolPresentation(
              id: 'preview-command',
              toolCallId: 'preview-command',
              name: 'exec',
              presentationContract: 'builtin.exec@2',
              statusString: 'running',
              arguments: '{"command":"cargo flutter analyze"}',
              output: '检查进行中。',
            ),
          ),
      ],
    ),
  );
}

Widget _status(ConversationActivityKind kind, {String? error}) =>
    ConversationActivityStatus(
      view: ConversationActivityView(
        identity: 'preview-${kind.name}',
        kind: kind,
        thinkingSeconds: kind == ConversationActivityKind.thinking ? 17 : null,
        errorMessage: error,
      ),
    );

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
      ConversationActivityBar(
        children: [_status(ConversationActivityKind.thinking)],
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
      ConversationActivityBar(
        children: [_status(ConversationActivityKind.compacting)],
      ),
    ],
  ),
);

@Preview(name: '四态顶栏指示器零抖动对比', group: '实时状态栏', size: Size(760, 360))
Widget conversationFourStatesComparisonPreview() => liveStatusPreviewHost(
  Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ConversationActivityBar(
        children: [_status(ConversationActivityKind.thinking)],
      ),
      ConversationActivityBar(
        children: [
          ConversationActivityStatus(
            view: const ConversationActivityView(
              identity: 'preview-running-exec',
              kind: ConversationActivityKind.runningTool,
              activeTools: [
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
        ],
      ),
      const ConversationActivityBar(
        children: [
          ConversationResponseView(
            child: ConversationCurrentWindowView(
              id: 'preview-four-states-writing',
              text: '四态顶栏共享同一 32×32 引导槽位与 15px 标题字号，切换零位移。',
            ),
          ),
        ],
      ),
      ConversationActivityBar(
        children: [_status(ConversationActivityKind.compacting)],
      ),
    ],
  ),
);

@Preview(name: '思考中 · 无内容', group: '实时状态栏', size: Size(760, 110))
Widget conversationLiveStatusWaitingPreview() => liveStatusPreviewHost(
  ConversationActivityBar(
    children: [_status(ConversationActivityKind.thinking)],
  ),
);

@Preview(name: '正在压缩上下文', group: '实时状态栏', size: Size(760, 110))
Widget conversationLiveStatusCompactingPreview() => liveStatusPreviewHost(
  ConversationActivityBar(
    children: [_status(ConversationActivityKind.compacting)],
  ),
);

@Preview(name: '工作组 · 进行中', group: '实时状态栏', size: Size(760, 300))
Widget conversationLiveStatusToolsPreview() => liveStatusPreviewHost(
  ConversationActivityBar(children: [liveStatusGroupPreview()]),
);

@Preview(name: '工作组 · 调用失败后继续思考（折叠单行）', group: '实时状态栏', size: Size(1067, 110))
Widget conversationLiveStatusFailedCallPreview() => liveStatusPreviewHost(
  ConversationActivityBar(
    children: [
      _ActivityPreview(
        activity: const ConversationActivityView(
          identity: 'preview-failed-call-thinking',
          kind: ConversationActivityKind.thinking,
        ),
        timing: const WorkTiming(startedAt: 154, finishedAt: null),
        childBuilder: (_) => const TimelineToolDetails(
          item: TimelineToolPresentation(
            id: 'preview-failed-call',
            toolCallId: 'preview-failed-call',
            name: 'exec',
            presentationContract: 'builtin.exec@2',
            statusString: 'failed',
            arguments: '{"command":"cargo flutter analyze"}',
            output: '命令退出码 1；调用失败后继续思考，不代表会话执行失败。',
            error: '命令退出码 1',
            exitCode: 1,
          ),
        ),
      ),
    ],
  ),
);

@Preview(name: '工作组 · 成员完成待交接', group: '实时状态栏', size: Size(760, 300))
Widget conversationLiveStatusIdleGroupPreview() => liveStatusPreviewHost(
  ConversationActivityBar(children: [liveStatusGroupPreview(idle: true)]),
);

@Preview(name: '工作组 · 已完成', group: '实时状态栏', size: Size(760, 150))
Widget conversationLiveStatusCompletedGroupPreview() => liveStatusPreviewHost(
  Padding(
    padding: const EdgeInsets.symmetric(horizontal: 26),
    child: liveStatusGroupPreview(history: true),
  ),
);

@Preview(name: '工作组 · 推理详情', group: '实时状态栏', size: Size(760, 260))
Widget conversationLiveStatusThinkingPreview() => liveStatusPreviewHost(
  ConversationActivityBar(
    children: [liveStatusGroupPreview(thinkingOnly: true)],
  ),
);

@Preview(name: '正文 · 长文与跟随', group: '实时状态栏', size: Size(760, 300))
Widget conversationLiveStatusRespondingPreview() => liveStatusPreviewHost(
  const ConversationActivityBar(
    children: [
      ConversationResponseView(
        child: ConversationCurrentWindowView(
          id: 'preview-response',
          text: liveStatusResponseText,
        ),
      ),
    ],
  ),
);

@Preview(name: '正文 · 短文自然高度', group: '实时状态栏', size: Size(760, 180))
Widget conversationLiveStatusShortResponsePreview() => liveStatusPreviewHost(
  const ConversationActivityBar(
    children: [
      ConversationResponseView(
        child: ConversationCurrentWindowView(
          id: 'preview-short',
          text: '已完成组件布局调整，正在核对各工况。',
        ),
      ),
    ],
  ),
);

@Preview(name: '等待成员', group: '实时状态栏', size: Size(760, 300))
Widget conversationLiveStatusWaitPreview() => liveStatusPreviewHost(
  ConversationActivityBar(
    children: [
      _ActivityPreview(
        timing: const WorkTiming(startedAt: 100, finishedAt: null),
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
    ],
  ),
);

@Preview(name: '窄窗 · 160% 文字缩放', group: '实时状态栏', size: Size(360, 380))
Widget conversationLiveStatusNarrowScaledPreview() => liveStatusPreviewHost(
  ConversationActivityBar(children: [liveStatusGroupPreview()]),
  scale: 1.6,
);

@Preview(name: '宽窗 · 正文', group: '实时状态栏', size: Size(1040, 300))
Widget conversationLiveStatusWidePreview() => liveStatusPreviewHost(
  const ConversationActivityBar(
    children: [
      ConversationResponseView(
        child: ConversationCurrentWindowView(
          id: 'preview-wide',
          text: liveStatusResponseText,
        ),
      ),
    ],
  ),
);

@Preview(name: '停止中', group: '实时状态栏', size: Size(760, 110))
Widget conversationLiveStatusStoppingPreview() => liveStatusPreviewHost(
  ConversationActivityBar(
    children: [_status(ConversationActivityKind.stopping)],
  ),
);

@Preview(name: '保存故障', group: '实时状态栏', size: Size(760, 150))
Widget conversationLiveStatusStorageFailurePreview() => liveStatusPreviewHost(
  ConversationActivityBar(
    children: [
      _status(
        ConversationActivityKind.storageBlocked,
        error: '保存暂时失败，当前内容已保留。',
      ),
    ],
  ),
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
  ConversationActivityBar(
    children: [
      _ActivityPreview(
        initiallyExpanded: true,
        activity: const ConversationActivityView(
          identity: 'preview-reasoning-variants',
          kind: ConversationActivityKind.thinking,
          thinkingSummary: '核对运行期选择器锁定规则',
        ),
        timing: const WorkTiming(startedAt: 100, finishedAt: null),
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
    ],
  ),
);

@Preview(name: '工作组 · 长工具输出', group: '实时状态栏', size: Size(760, 300))
Widget conversationLiveStatusLongToolPreview() => liveStatusPreviewHost(
  ConversationActivityBar(
    children: [
      _ActivityPreview(
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
        childBuilder: (_) => TimelineToolDetails(
          initiallyExpanded: true,
          item: TimelineToolPresentation(
            id: 'long-tool-output',
            toolCallId: 'long-tool-output',
            name: 'exec',
            presentationContract: 'builtin.exec@2',
            statusString: 'running',
            arguments: '{"command":"cargo flutter analyze"}',
            output: [for (var i = 1; i <= 60; i++) '检查第 $i 项：通过。'].join('\n'),
          ),
        ),
      ),
    ],
  ),
);

@Preview(name: '正文后开启新工作组', group: '实时状态栏', size: Size(760, 340))
Widget conversationLiveStatusNextGroupPreview() => liveStatusPreviewHost(
  Column(
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
      ConversationActivityBar(
        children: [
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
            timing: const WorkTiming(startedAt: 213, finishedAt: null),
            childBuilder: (_) => const TimelineToolDetails(
              item: TimelineToolPresentation(
                id: 'preview-next-group-cmd',
                toolCallId: 'preview-next-group-cmd',
                name: 'exec',
                presentationContract: 'builtin.exec@2',
                statusString: 'running',
                arguments: '{"command":"cargo flutter test --no-pub test/ui"}',
                output: '正在执行实时状态栏防抖动测试…',
              ),
            ),
          ),
        ],
      ),
    ],
  ),
);

class _ActivityPreview extends StatelessWidget {
  const _ActivityPreview({
    required this.childBuilder,
    this.initiallyExpanded = false,
    this.activity,
    this.timing = const WorkTiming(startedAt: 100),
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
      historyPos: 2,
      body: WorkDisplayBlock(
        timing: const WorkTiming(startedAt: 1735689600, finishedAt: 1735689725),
        members: const DisplayBlockRef(
          databaseId: 'preview',
          blockId: 'sealed-tool-preview-group',
        ),
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
              TimelineToolDetails(
                item: TimelineToolPresentation(
                  id: 'sealed-tool-preview-exec',
                  toolCallId: 'sealed-tool-preview-exec-call',
                  name: 'exec',
                  presentationContract: 'builtin.exec@2',
                  statusString: 'succeeded',
                  arguments: '{"command":"cargo flutter test test/ui"}',
                  output: 'exec 执行完成：测试命令成功退出。',
                ),
                initiallyExpanded: true,
              ),
              TimelineToolDetails(
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
