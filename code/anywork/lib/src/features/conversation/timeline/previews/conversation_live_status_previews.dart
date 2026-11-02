import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../../../../app/theme/material3_theme.dart';
import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../state/tool_presentation.dart';
import '../widgets/conversation_activity_bar.dart';
import '../widgets/conversation_current_views.dart';
import '../widgets/timeline_tool_blocks.dart';
import '../widgets/timeline_wait_blocks.dart';

Widget _liveStatusPreviewHost(
  Widget child, {
  TextScaler textScaler = TextScaler.noScaling,
  double maxWidth = StudioLayout.conversationWidth,
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh'),
    theme: pureStudioTheme(locale: const Locale('zh')),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, appChild) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: ListTileTheme(
        data: Theme.of(context).listTileTheme,
        child: appChild!,
      ),
    ),
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: StudioLayout.conversationWidth,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Pure inputs for the production widget; previews own no feed or reducer.
abstract final class ConversationLiveStatusPreviewFixtures {
  static const waiting = ConversationActivityView(
    identity: 'preview:waiting',
    turnId: 'preview-turn',
    kind: ConversationActivityKind.thinking,
  );

  static const compacting = ConversationActivityView(
    identity: 'preview:compacting',
    turnId: 'preview-turn',
    kind: ConversationActivityKind.compacting,
    summary: '正在整理前序记录，保留本轮任务与关键决定。',
  );

  static const thinking = ConversationActivityView(
    identity: 'preview:thinking',
    turnId: 'preview-turn',
    kind: ConversationActivityKind.thinking,
    thinkingSummary: '核对依赖，准备下一步修改',
    expandable: true,
  );

  static const tools = ConversationActivityView(
    identity: 'preview:tools',
    turnId: 'preview-turn',
    kind: ConversationActivityKind.runningTool,
    thinkingSummary: '核对依赖，准备下一步修改',
    summary: '运行检查并读取相关说明',
    activeToolCount: 2,
    activeTools: [
      ThreadActivityToolEntry(
        callId: 'preview-exec',
        name: 'exec',
        summary: 'cargo test -p pl-core --features sqlite',
        arguments: ThreadActivityArgumentsKind.commandLine,
        state: ThreadActivityToolState.running,
      ),
      ThreadActivityToolEntry(
        callId: 'preview-read',
        name: 'exec',
        summary: 'rg -n "publish_batch" code/pl-core',
        arguments: ThreadActivityArgumentsKind.commandLine,
        state: ThreadActivityToolState.running,
      ),
    ],
    expandable: true,
  );

  static final waitPresentation = ThreadWaitPresentationView(
    intent: ThreadWaitEventsIntentView(
      targets: const [
        ThreadWaitTargetView(
          taskId: 'task:explorer',
          toolName: 'delegation',
          summary: '梳理实时投影与内容读取边界',
          status: ThreadWaitTargetStatusView.succeeded,
        ),
        ThreadWaitTargetView(
          taskId: 'task:reviewer',
          toolName: 'delegation',
          summary: '复核工具与等待详情的视觉层级',
          status: ThreadWaitTargetStatusView.running,
        ),
      ],
      timeoutMs: 300000,
    ),
    state: ThreadWaitStateView.waiting,
    messagesReady: false,
  );

  static final waitingOnTools = ConversationActivityView(
    identity: 'preview:wait-tools',
    turnId: 'preview-turn',
    kind: ConversationActivityKind.runningTool,
    activeTools: [
      ThreadActivityToolEntry(
        callId: 'preview-wait',
        name: 'wait',
        summary: '等待两个成员返回结果',
        arguments: ThreadActivityArgumentsKind.opaque,
        state: ThreadActivityToolState.running,
        wait: waitPresentation,
      ),
    ],
    activeToolCount: 1,
    wait: waitPresentation,
    expandable: true,
  );

  static const responding = ConversationActivityView(
    identity: 'preview:responding',
    turnId: 'preview-turn',
    kind: ConversationActivityKind.responding,
  );

  static const toolPresentations = [
    TimelineToolPresentation(
      id: 'preview-tool-exec',
      toolCallId: 'preview-exec',
      name: 'exec',
      presentationContract: 'builtin.exec@2',
      statusString: 'running',
      arguments: 'cargo test -p pl-core --features sqlite',
      output:
          'running 12 tests\n'
          'test completed_items_keep_their_identity ... ok',
      workingDirectory: 'code/pl-core',
    ),
    TimelineToolPresentation(
      id: 'preview-tool-read',
      toolCallId: 'preview-read',
      name: 'exec',
      presentationContract: 'builtin.exec@2',
      statusString: 'running',
      arguments: 'rg -n "publish_batch" code/pl-core',
      output: 'code/pl-core/src/conversation.rs:318: publish_batch(...)',
      workingDirectory: '.',
    ),
  ];
}

const _thinkingText =
    '先核对现有调用链和测试入口，再确认需要修改的边界。\n\n'
    '长段落应在阅读列内自然换行，展开后仍能完整阅读与选择复制。\n\n'
    '随后检查错误传播与关闭后的资源归属，保留已有验证证据。';

const _respondingText =
    '已完成当前修改，并保留相关验证结果。\n\n'
    '- 已完成的内容逐条进入历史；\n'
    '- 当前工具输出仍按原始段落展示；\n'
    '- 长中文、链接和 `行内代码` 在阅读列内换行。\n\n'
    '这段回复继续增长时，状态栏先按 Markdown 的自然高度展开；'
    '达到上限后只在正文区域滚动，不显示暗示额外业务状态的箭头。\n\n'
    '接下来检查剩余调用方和实际界面表现。';

Widget _thinkingContent() => const ConversationCurrentDetailsView(
  windows: [
    ConversationCurrentWindowView(
      id: 'preview-thinking',
      label: '当前思考',
      text: _thinkingText,
    ),
  ],
);

Widget _respondingContent() => const ConversationCurrentDetailsView(
  windows: [
    ConversationCurrentWindowView(
      id: 'preview-response',
      text: _respondingText,
    ),
  ],
);

Widget _toolsContent() => ConversationCurrentDetailsView(
  windows: [
    for (final tool in ConversationLiveStatusPreviewFixtures.toolPresentations)
      TimelineToolDetails(item: tool),
  ],
);

Widget _waitContent() => ConversationCurrentDetailsView(
  windows: [
    TimelineWaitDetails(
      presentation: ConversationLiveStatusPreviewFixtures.waitPresentation,
      identity: 'preview-wait',
    ),
  ],
);

@Preview(
  name: '实时活动 / 等待正文（不可展开）',
  group: 'Timeline · 实时活动',
  size: Size(760, 140),
)
Widget conversationLiveStatusWaitingPreview() => _liveStatusPreviewHost(
  const ConversationActivityBar(
    view: ConversationLiveStatusPreviewFixtures.waiting,
  ),
);

@Preview(name: '实时活动 / 正在压缩', group: 'Timeline · 实时活动', size: Size(760, 140))
Widget conversationLiveStatusCompactingPreview() => _liveStatusPreviewHost(
  const ConversationActivityBar(
    view: ConversationLiveStatusPreviewFixtures.compacting,
  ),
);

@Preview(
  name: '实时活动 / 并行工具（点击展开）',
  group: 'Timeline · 实时活动',
  size: Size(760, 380),
)
Widget conversationLiveStatusToolsPreview() => _liveStatusPreviewHost(
  ConversationActivityBar(
    view: ConversationLiveStatusPreviewFixtures.tools,
    content: _toolsContent(),
  ),
);

@Preview(
  name: '实时活动 / 等待成员详情（点击展开）',
  group: 'Timeline · 实时活动',
  size: Size(760, 420),
)
Widget conversationLiveStatusWaitPreview() => _liveStatusPreviewHost(
  ConversationActivityBar(
    view: ConversationLiveStatusPreviewFixtures.waitingOnTools,
    content: _waitContent(),
  ),
);

@Preview(
  name: '实时活动 / 分段思考（点击展开）',
  group: 'Timeline · 实时活动',
  size: Size(760, 260),
)
Widget conversationLiveStatusThinkingPreview() => _liveStatusPreviewHost(
  ConversationActivityBar(
    view: ConversationLiveStatusPreviewFixtures.thinking,
    content: _thinkingContent(),
  ),
);

@Preview(
  name: '实时活动 / Markdown 回复（动态高度）',
  group: 'Timeline · 实时活动',
  size: Size(760, 280),
)
Widget conversationLiveStatusRespondingPreview() => _liveStatusPreviewHost(
  ConversationActivityBar(
    view: ConversationLiveStatusPreviewFixtures.responding,
    content: _respondingContent(),
  ),
);

@Preview(
  name: '实时活动 / 窄窗与 160% 字体缩放',
  group: 'Timeline · 实时活动',
  size: Size(390, 420),
)
Widget conversationLiveStatusNarrowScaledPreview() => _liveStatusPreviewHost(
  ConversationActivityBar(
    view: ConversationLiveStatusPreviewFixtures.responding,
    content: _respondingContent(),
    maxResponseHeight: 240,
  ),
  textScaler: const TextScaler.linear(1.6),
  maxWidth: 350,
);
