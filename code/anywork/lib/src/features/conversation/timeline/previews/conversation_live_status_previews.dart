import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../../../../app/theme/material3_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../state/tool_presentation.dart';
import '../widgets/conversation_activity_bar.dart';
import '../widgets/conversation_current_views.dart';
import '../widgets/chat_item_view.dart';
import 'timeline_preview_fixtures.dart';
import '../widgets/timeline_tool_blocks.dart';
import '../widgets/timeline_wait_blocks.dart';
import '../widgets/timeline_work_group_view.dart';
import '../widgets/timeline_reasoning_view.dart';

/// 官方预览只装配生产组件，不装配 Client、原生桥或第二套状态投影。
Widget liveStatusPreviewHost(Widget child, {double scale = 1}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('zh'),
  theme: pureStudioTheme(locale: const Locale('zh')),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
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
    '工作组成员逐项结束后仍留在当前区域，正文结束后完整进入时间线。继续检查不同文字缩放下的自然高度与阅读位置，确保新内容不会打断正在进行的阅读。';

Widget liveStatusGroupPreview({
  bool idle = false,
  bool history = false,
  bool thinkingOnly = false,
}) => TimelineWorkGroupView(
  id: history ? 'preview-history' : 'preview-live',
  summary: TimelineGroupSummary(
    memberCount: thinkingOnly ? 1 : 4,
    activeCount: idle || history ? 0 : 1,
    failedCount: 0,
    cancelledCount: 0,
    startedAt: history ? 100 : null,
    finishedAt: history ? 225 : null,
    latestThinkingSummary: thinkingOnly
        ? '**Reading receipt metadata** · *检查* `owner`'
        : null,
    categories: [
      const TimelineCategoryCount(
        category: TimelineCategory.thinking,
        count: 1,
      ),
      if (!thinkingOnly) ...[
        const TimelineCategoryCount(category: TimelineCategory.read, count: 1),
        const TimelineCategoryCount(
          category: TimelineCategory.command,
          count: 1,
        ),
        const TimelineCategoryCount(
          category: TimelineCategory.search,
          count: 1,
        ),
      ],
    ],
  ),
  live: !history,
  executionPresent: !history,
  admissionClosed: history,
  initiallyExpanded: !history,
  childBuilder: (_) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (thinkingOnly && !idle && !history)
        const TimelineReasoningView(
          summary: '梳理会话共享组件与锁定边界',
          running: true,
          body: ConversationCurrentWindowView(
            id: 'preview-reasoning',
            text: '先核对现有调用链和组件边界，再确认布局、状态文案与自适应高度。',
          ),
        )
      else
        ChatItemView(
          item: TimelinePreviewFixtures.item(
            'preview-reasoning',
            'thinking',
            const {},
            bodies: [
              TimelinePreviewFixtures.body(
                'part.summaryText.0',
                '梳理会话共享组件与锁定边界',
              ),
              TimelinePreviewFixtures.body(
                'part.reasoningText.0',
                '已完成的成员**留在状态栏的当前工作组**；同时核对运行期选择器的就地锁定提示。',
              ),
            ],
          ),
          bodyBuilder: (id, text) =>
              ConversationCurrentWindowView(id: id, text: text),
        ),
      if (!thinkingOnly) ...[
        const TimelineToolDetails(
          item: TimelineToolPresentation(
            id: 'preview-read',
            toolCallId: 'preview-read',
            name: 'stat_path',
            presentationContract: 'builtin.stat_path@1',
            statusString: 'succeeded',
            arguments: '{"path":"composer_dock_connector.dart"}',
            output: '{"kind":"file"}',
          ),
        ),
        TimelineToolDetails(
          item: TimelineToolPresentation(
            id: 'preview-command',
            toolCallId: 'preview-command',
            name: 'exec',
            presentationContract: 'builtin.exec@2',
            statusString: idle || history ? 'succeeded' : 'running',
            arguments: '{"command":"cargo test -p pl-core --features sqlite"}',
            output: 'running 12 tests\ntest completed_items_keep_their_identity ... ok',
            workingDirectory: '.',
          ),
        ),
        const TimelineToolDetails(
          item: TimelineToolPresentation(
            id: 'preview-search',
            toolCallId: 'preview-search',
            name: 'search_session_note',
            presentationContract: 'builtin.search_session_note@1',
            statusString: 'succeeded',
            arguments: '{"query":"选择器锁定 · 运行中发送"}',
            output: '已找到交互约定',
          ),
        ),
      ],
    ],
  ),
);

Widget _status(ConversationActivityKind kind, {String? error}) =>
    ConversationActivityStatus(
      view: ConversationActivityView(
        identity: 'preview-${kind.name}',
        kind: kind,
        thinkingSeconds: kind == ConversationActivityKind.thinking ? 17 : null,
        errorMessage: error,
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
      TimelineWorkGroupView(
        id: 'preview-wait',
        live: true,
        executionPresent: true,
        admissionClosed: false,
        initiallyExpanded: true,
        summary: TimelineGroupSummary(
          memberCount: 1,
          activeCount: 1,
          failedCount: 0,
          cancelledCount: 0,
          categories: const [
            TimelineCategoryCount(category: TimelineCategory.wait, count: 1),
          ],
        ),
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
      TimelineWorkGroupView(
        id: 'reasoning-variants',
        summary: TimelineGroupSummary(
          memberCount: 3,
          activeCount: 0,
          failedCount: 0,
          cancelledCount: 0,
          categories: [
            TimelineCategoryCount(
              category: TimelineCategory.thinking,
              count: 3,
            ),
          ],
        ),
        live: true,
        executionPresent: true,
        admissionClosed: false,
        initiallyExpanded: true,
        childBuilder: (_) => const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TimelineReasoningView(
              summary: '梳理会话共享组件与锁定边界',
              startedAt: 100,
              finishedAt: 225,
              body: ConversationCurrentWindowView(
                id: 'summary-body',
                text: '先核对现有调用链和组件边界，再确认布局、状态文案与自适应高度。',
              ),
            ),
            TimelineReasoningView(
              summary: '核对运行期选择器锁定规则',
              startedAt: 100,
              finishedAt: 225,
            ),
            TimelineReasoningView(
              startedAt: 100,
              finishedAt: 225,
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
      TimelineWorkGroupView(
        id: 'long-tool',
        summary: TimelineGroupSummary(
          memberCount: 1,
          activeCount: 1,
          failedCount: 0,
          cancelledCount: 0,
          categories: const [
            TimelineCategoryCount(category: TimelineCategory.command, count: 1),
          ],
        ),
        live: true,
        executionPresent: true,
        admissionClosed: false,
        initiallyExpanded: true,
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
