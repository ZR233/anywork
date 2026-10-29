import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../../../../app/theme/material3_theme.dart';
import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/app_localizations.dart';
import '../widgets/conversation_activity_bar.dart';

Widget _liveStatusPreviewHost(Widget child) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh'),
    theme: pureStudioTheme(locale: const Locale('zh')),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: StudioLayout.conversationWidth,
            ),
            child: child,
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
    reasoningParts: [
      ThreadActivityContentPart(
        itemId: 'preview-reasoning-1',
        complete: false,
        text:
            '先核对现有调用链和测试入口，再确认需要修改的边界。\n\n'
            '长段落应在阅读列内自然换行，展开后仍能完整阅读与选择复制。',
      ),
      ThreadActivityContentPart(
        itemId: 'preview-reasoning-2',
        complete: false,
        text: '随后检查错误传播与关闭后的资源归属，保留已有验证证据。',
      ),
    ],
    expandable: true,
  );

  static final tools = ConversationActivityView(
    identity: 'preview:tools',
    turnId: 'preview-turn',
    kind: ConversationActivityKind.runningTool,
    thinkingSummary: '核对依赖，准备下一步修改',
    summary: '运行检查并读取相关说明',
    activeToolCount: 2,
    activeTools: const [
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
    toolDetails: [
      ThreadActivityToolDetail(
        callId: 'preview-exec',
        name: 'exec',
        state: ThreadActivityToolState.running,
        arguments: 'cargo test -p pl-core --features sqlite',
        outputParts: const [
          ThreadActivityToolOutputPart(
            partId: 'stdout',
            text: 'running 12 tests\ntest completed_items_keep_their_identity ... ok',
          ),
          ThreadActivityToolOutputPart(
            partId: 'stderr',
            text: 'Compiling pl-core v0.1.0',
          ),
        ],
      ),
      ThreadActivityToolDetail(
        callId: 'preview-read',
        name: 'exec',
        state: ThreadActivityToolState.running,
        arguments: 'rg -n "publish_batch" code/pl-core',
      ),
    ],
    expandable: true,
  );

  static const responding = ConversationActivityView(
    identity: 'preview:responding',
    turnId: 'preview-turn',
    kind: ConversationActivityKind.responding,
    responseParts: [
      ThreadActivityContentPart(
        itemId: 'preview-response-1',
        complete: false,
        text:
            '已完成当前修改，并保留相关验证结果。\n\n'
            '- 已完成的内容逐条进入历史；\n'
            '- 当前工具输出仍按原始段落展示；\n'
            '- 长中文、链接和 `行内代码` 在阅读列内换行。',
      ),
      ThreadActivityContentPart(
        itemId: 'preview-response-2',
        complete: false,
        text: '接下来检查剩余调用方和实际界面表现。',
      ),
    ],
  );
}

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
  ConversationActivityBar(view: ConversationLiveStatusPreviewFixtures.tools),
);

@Preview(
  name: '实时活动 / 分段思考（点击展开）',
  group: 'Timeline · 实时活动',
  size: Size(760, 260),
)
Widget conversationLiveStatusThinkingPreview() => _liveStatusPreviewHost(
  const ConversationActivityBar(
    view: ConversationLiveStatusPreviewFixtures.thinking,
  ),
);

@Preview(
  name: '实时活动 / 分段回复（动态高度）',
  group: 'Timeline · 实时活动',
  size: Size(760, 280),
)
Widget conversationLiveStatusRespondingPreview() => _liveStatusPreviewHost(
  const ConversationActivityBar(
    view: ConversationLiveStatusPreviewFixtures.responding,
  ),
);

@Preview(name: '实时活动 / 切换当前态', group: 'Timeline · 实时活动', size: Size(820, 520))
Widget conversationLiveStatusInteractivePreview() =>
    _liveStatusPreviewHost(const _InteractiveActivityPreview());

class _InteractiveActivityPreview extends StatefulWidget {
  const _InteractiveActivityPreview();

  @override
  State<_InteractiveActivityPreview> createState() =>
      _InteractiveActivityPreviewState();
}

class _InteractiveActivityPreviewState
    extends State<_InteractiveActivityPreview> {
  ConversationActivityView _view =
      ConversationLiveStatusPreviewFixtures.waiting;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (label, view) in [
            ('等待正文', ConversationLiveStatusPreviewFixtures.waiting),
            ('正在压缩', ConversationLiveStatusPreviewFixtures.compacting),
            ('分段思考', ConversationLiveStatusPreviewFixtures.thinking),
            ('并行工具', ConversationLiveStatusPreviewFixtures.tools),
            ('分段回复', ConversationLiveStatusPreviewFixtures.responding),
          ])
            ChoiceChip(
              label: Text(label),
              selected: _view.identity == view.identity,
              onSelected: (_) => setState(() => _view = view),
            ),
        ],
      ),
      const SizedBox(height: 16),
      ConversationActivityBar(view: _view),
    ],
  );
}
