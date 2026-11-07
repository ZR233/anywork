import 'dart:convert';

import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

import '../../../../app/theme/material3_theme.dart';
import '../../../../app/theme/studio_tokens.dart';
import '../../../../domain/models/timeline_commands.dart';
import '../../../../l10n/app_localizations.dart';
import '../state/chat_item_presentation.dart';
import '../state/chat_payload_reading.dart';
import '../state/timeline_display_unit.dart';
import '../state/timeline_ui_controllers.dart';
import '../state/timeline_view_state.dart';
import '../views/timeline_view.dart';
import '../widgets/chat_item_view.dart';
import '../widgets/conversation_current_views.dart';
import '../widgets/timeline_activity_row.dart';
import '../widgets/timeline_attachments_view.dart';
import '../widgets/timeline_children_view.dart';
import '../widgets/timeline_content_range_view.dart';
import '../widgets/timeline_display_unit_view.dart';
import '../widgets/timeline_image_view.dart';
import '../widgets/timeline_markdown.dart';
import '../widgets/timeline_plain_text.dart';
import '../widgets/timeline_tool_blocks.dart';
import '../widgets/timeline_wait_blocks.dart';
import 'timeline_preview_fixtures.dart';

Widget _timelinePreviewHost(
  Widget child, {
  double maxWidth = StudioLayout.conversationWidth,
  double textScale = 1,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('zh'),
  theme: pureStudioTheme(locale: const Locale('zh')),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, appChild) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(textScale)),
    child: ListTileTheme(
      data: Theme.of(context).listTileTheme,
      child: appChild!,
    ),
  ),
  home: Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: const EdgeInsets.all(20), child: child),
      ),
    ),
  ),
);

Widget _chatItem(
  ChatItemPresentation item, {
  String? resourceErrorAttachmentId,
}) => ChatItemView(
  key: ValueKey(item.id),
  item: item,
  bodyBuilder: (id, text) => TimelineMarkdown(
    id: id,
    text: text,
    onLink: (_) {},
    isSafeLink: (url) => Uri.tryParse(url)?.scheme == 'https',
    imageBuilder: (_, _) => const Text('外部图片需要显式加载'),
  ),
  attachmentBuilder: (item) => _previewAttachments(
    item.id,
    item.attachments,
    isTool: item.type == 'tool',
    resourceErrorAttachmentId: resourceErrorAttachmentId,
  ),
);

Widget _previewAttachments(
  String itemId,
  List<ThreadAttachmentView> values, {
  bool isTool = false,
  String? resourceErrorAttachmentId,
}) => TimelineAttachmentsView(
  attachments: values,
  imageBuilder: (attachment) => TimelineImageView(
    itemId: itemId,
    attachment: attachment,
    isTool: isTool,
    active: true,
    imageIdentity: ('preview', itemId, attachment.id),
    bytes: attachment.id == resourceErrorAttachmentId
        ? null
        : TimelinePreviewFixtures.imageBytes,
    width: TimelinePreviewFixtures.imageWidth,
    height: TimelinePreviewFixtures.imageHeight,
    error: attachment.id == resourceErrorAttachmentId ? '合成读取失败' : null,
  ),
);

@Preview(name: '历史 / 正文、思考与工具', group: 'Timeline · 历史组件', size: Size(820, 720))
Widget timelineHistoryTypesPreview() => _timelinePreviewHost(
  SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _chatItem(TimelinePreviewFixtures.user),
        const SizedBox(height: 12),
        _chatItem(TimelinePreviewFixtures.assistant),
        const SizedBox(height: 12),
        _chatItem(TimelinePreviewFixtures.reasoning),
        _chatItem(TimelinePreviewFixtures.tool),
        _chatItem(TimelinePreviewFixtures.waiting),
      ],
    ),
  ),
);

@Preview(
  name: '历史 / 问答与 Plan 回执（点击展开）',
  group: 'Timeline · 历史组件',
  size: Size(760, 420),
)
Widget timelineReceiptsPreview() => _timelinePreviewHost(
  SingleChildScrollView(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _chatItem(TimelinePreviewFixtures.questionReceipt),
        _chatItem(TimelinePreviewFixtures.planReceipt),
      ],
    ),
  ),
);

@Preview(name: '工作组 / 实时等待下一步', group: 'Timeline · 原子工作组', size: Size(760, 360))
Widget timelineAtomicLiveGroupPreview() => _timelinePreviewHost(
  const _AtomicGroupPreview(
    key: ValueKey('atomic-live'),
    live: true,
    executionPresent: true,
  ),
);

@Preview(name: '工作组 / 工作与正文交替', group: 'Timeline · 原子工作组', size: Size(760, 600))
Widget timelineAtomicStoryPreview() => _timelinePreviewHost(
  const _AtomicGroupPreview(
    key: ValueKey('atomic-story'),
    live: false,
    executionPresent: false,
  ),
);

@Preview(name: '工作组 / 窄窗 160%', group: 'Timeline · 原子工作组', size: Size(390, 540))
Widget timelineAtomicNarrowPreview() => _timelinePreviewHost(
  const _AtomicGroupPreview(
    key: ValueKey('atomic-narrow'),
    live: false,
    executionPresent: false,
  ),
  textScale: 1.6,
);

@Preview(
  name: '工作组 / 保存的 current 无执行 owner',
  group: 'Timeline · 原子工作组',
  size: Size(760, 360),
)
Widget timelineAtomicSavedCurrentPreview() => _timelinePreviewHost(
  const _AtomicGroupPreview(
    key: ValueKey('atomic-saved-current'),
    live: true,
    executionPresent: false,
  ),
);

@Preview(
  name: '工作组 / 零活动等待后继边界',
  group: 'Timeline · 原子工作组',
  size: Size(760, 420),
)
Widget timelineAtomicOpenIdlePreview() => _timelinePreviewHost(
  const _AtomicGroupPreview(
    key: ValueKey('atomic-open-idle'),
    live: true,
    executionPresent: true,
    waitingForBoundary: true,
  ),
);

@Preview(
  name: '工作组 / 零活动等待后继边界 390 / 160%',
  group: 'Timeline · 原子工作组',
  size: Size(390, 540),
)
Widget timelineAtomicOpenIdleNarrowPreview() => _timelinePreviewHost(
  const _AtomicGroupPreview(
    key: ValueKey('atomic-open-idle-narrow'),
    live: true,
    executionPresent: true,
    waitingForBoundary: true,
  ),
  textScale: 1.6,
);

/// Static presentation inputs only. The real shared group/item widgets own
/// disclosure; no preview reducer simulates admission or source completion.
class _AtomicGroupPreview extends StatefulWidget {
  const _AtomicGroupPreview({
    required this.live,
    required this.executionPresent,
    this.waitingForBoundary = false,
    super.key,
  });
  final bool live;
  final bool executionPresent;
  final bool waitingForBoundary;
  @override
  State<_AtomicGroupPreview> createState() => _AtomicGroupPreviewState();
}

class _AtomicGroupPreviewState extends State<_AtomicGroupPreview> {
  late final groups = [
    for (var index = 0; index < (widget.live ? 1 : 2); index++)
      TimelineDisplayUnit(
        live: widget.live,
        item: TimelineItem(
          id: 'preview-group-$index',
          kind: TimelineItemKind.workGroup,
          source: TimelinePreviewFixtures.groupSource,
          delivery: ChatDeliveryKind.foreground,
          turnId: 'preview-turn',
          position: widget.live ? null : index * 2 + 1,
          admissionClosed: !widget.live,
          contents: const [],
          members: TimelineMembersRef(
            databaseId: 'preview',
            projectionVersion: 1,
            projectionGeneration: 'preview-projection-generation',
            itemId: 'preview-group-$index',
          ),
          summary: TimelineGroupSummary(
            memberCount: index == 0 ? 2 : 1,
            activeCount: widget.live && !widget.waitingForBoundary ? 1 : 0,
            failedCount: 0,
            cancelledCount: 0,
            categories: [
              const TimelineCategoryCount(
                category: TimelineCategory.thinking,
                count: 1,
              ),
              if (index == 0)
                const TimelineCategoryCount(
                  category: TimelineCategory.command,
                  count: 1,
                ),
            ],
            startedAt: widget.live && !widget.waitingForBoundary
                ? null
                : index == 0
                ? TimelinePreviewFixtures.groupStartedAt
                : 1735689603,
            finishedAt: widget.live && !widget.waitingForBoundary
                ? null
                : index == 0
                ? TimelinePreviewFixtures.commandFinishedAt
                : 1735689603,
          ),
        ),
      ),
  ];

  @override
  void dispose() {
    for (final group in groups) {
      group.expansion.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < groups.length; index++) ...[
          TimelineDisplayUnitView(
            key: ValueKey(groups[index].id),
            unit: groups[index],
            executionPresent: widget.executionPresent,
            childBuilder: (_) => Column(
              children: [
                if (widget.live && !widget.waitingForBoundary)
                  _activeReasoningWindow()
                else
                  _chatItem(
                    ChatItemPresentation.decode(
                      index == 0
                          ? TimelinePreviewFixtures.completedReasoning
                          : TimelinePreviewFixtures.secondCompletedReasoning,
                    ),
                  ),
                if (index == 0)
                  _chatItem(
                    ChatItemPresentation.decode(
                      TimelinePreviewFixtures.completedCommand,
                    ),
                  ),
              ],
            ),
          ),
          if (!widget.live)
            _chatItem(
              TimelinePreviewFixtures.item(
                'preview-answer-$index',
                'text',
                const {'channel': 'final', 'attachments': []},
                sealedAt: index == 0 ? 1735689602 : 1735689604,
                bodies: [
                  TimelinePreviewFixtures.body(
                    'part.text.0',
                    index == 0 ? '已确认共享组件与交接边界，接下来检查收尾。' : '收尾检查完成，工作组与正文分别保留。',
                  ),
                ],
              ),
            ),
        ],
      ],
    ),
  );
}

// This is exactly the pure window view used by TimelineMemberAtom for an active
// reasoning member. There is no preview content owner, subscription or query.
Widget _activeReasoningWindow() {
  final window = TimelinePreviewFixtures.activeReasoningWindow;
  return ConversationCurrentWindowView(
    id: TimelinePreviewFixtures.activeReasoning.id,
    text: utf8.decode(window.bytes),
    offset: window.offset,
    end: window.offset + window.bytes.length,
    availableThrough: window.availableThrough,
  );
}

@Preview(
  name: 'Current / A07 R 未结束、T 已结束',
  group: 'Timeline · 原子工作组',
  size: Size(760, 480),
)
Widget timelineAtomicOverlapPreview() =>
    _timelinePreviewHost(const _OverlapCurrentPreview());

@Preview(
  name: 'Current / A07 390 / 160%',
  group: 'Timeline · 原子工作组',
  size: Size(390, 600),
)
Widget timelineAtomicOverlapNarrowPreview() =>
    _timelinePreviewHost(const _OverlapCurrentPreview(), textScale: 1.6);

/// Only the local group + following text composition, not a complete current
/// dock. R → T is the fixture's given order, never a computed committed prefix.
class _OverlapCurrentPreview extends StatefulWidget {
  const _OverlapCurrentPreview();
  @override
  State<_OverlapCurrentPreview> createState() => _OverlapCurrentPreviewState();
}

class _OverlapCurrentPreviewState extends State<_OverlapCurrentPreview> {
  final current = TimelinePreviewFixtures.overlapCurrent;
  late final units = [
    for (final item in current.items)
      TimelineDisplayUnit(item: item, live: true),
  ];
  @override
  void dispose() {
    for (final unit in units) {
      unit.expansion.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TimelineDisplayUnitView(
          unit: units[0],
          executionPresent: current.executionPresent,
          childBuilder: (_) => _activeReasoningWindow(),
        ),
        _chatItem(ChatItemPresentation.forUnit(units[1])),
      ],
    ),
  );
}

@Preview(
  name: '工作组 / 同成员三图与文字、工具失败、媒体错误',
  group: 'Timeline · 原子工作组',
  size: Size(760, 620),
)
Widget timelineAtomicMediaPreview() =>
    _timelinePreviewHost(const _MediaGroupPreview());

@Preview(
  name: '工作组 / 图文与两类错误 390 / 160%',
  group: 'Timeline · 原子工作组',
  size: Size(390, 640),
)
Widget timelineAtomicMediaNarrowPreview() =>
    _timelinePreviewHost(const _MediaGroupPreview(), textScale: 1.6);

class _MediaGroupPreview extends StatefulWidget {
  const _MediaGroupPreview();
  @override
  State<_MediaGroupPreview> createState() => _MediaGroupPreviewState();
}

class _MediaGroupPreviewState extends State<_MediaGroupPreview> {
  final unit = TimelineDisplayUnit(
    item: TimelinePreviewFixtures.mediaGroup,
    live: false,
  );
  @override
  void dispose() {
    unit.expansion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: TimelineDisplayUnitView(
      unit: unit,
      executionPresent: false,
      childBuilder: (_) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _chatItem(
            ChatItemPresentation.decode(TimelinePreviewFixtures.mediaTool),
          ),
          _chatItem(
            ChatItemPresentation.decode(
              TimelinePreviewFixtures.failedImageTool,
            ),
          ),
          _chatItem(
            ChatItemPresentation.decode(
              TimelinePreviewFixtures.resourceErrorTool,
            ),
            resourceErrorAttachmentId: 'preview-resource-error-image',
          ),
        ],
      ),
    ),
  );
}

@Preview(name: '内容窗口 / 已接纳呈现值', group: 'Timeline · 资源纯视图', size: Size(720, 300))
Widget timelineContentWindowPreview() => _timelinePreviewHost(
  TimelineContentRangeView(
    itemId: 'preview-deferred',
    contentKey: 'payload',
    label: '按需查看原文 · 196608 字节',
    initiallyExpanded: true,
    loading: false,
    active: true,
    canRead: true,
    window: TimelinePreviewFixtures.contentWindow,
    onExpansionChanged: (_) {},
    onNext: () {},
    onCopy: () {},
    witness: (_, child) => child,
  ),
);

@Preview(name: '媒体 / 缩略图与原图弹层', group: 'Timeline · 资源纯视图', size: Size(420, 320))
Widget timelineImagePreview() => _timelinePreviewHost(
  Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('合成 PNG · 320 × 180'),
      const SizedBox(height: 8),
      TimelineImageView(
        itemId: 'preview-media-item',
        attachment: TimelinePreviewFixtures.imageAttachment,
        isTool: false,
        active: true,
        imageIdentity: const ('preview', 'preview-image'),
        bytes: TimelinePreviewFixtures.imageBytes,
        width: TimelinePreviewFixtures.imageWidth,
        height: TimelinePreviewFixtures.imageHeight,
      ),
    ],
  ),
  maxWidth: 320,
);

@Preview(name: '附件 / 同一生产排列', group: 'Timeline · 资源纯视图', size: Size(640, 260))
Widget timelineAttachmentsPreview() => _timelinePreviewHost(
  _previewAttachments('preview-attachments', [
    TimelinePreviewFixtures.imageAttachment,
    const ThreadAttachmentView(
      id: 'preview-video',
      modality: AttachmentModalityView.video,
      mediaType: 'video/mp4',
      byteSize: 4096,
      filename: 'synthetic-video.mp4',
    ),
  ]),
);

@Preview(name: '正文 / Markdown', group: 'Timeline · 历史组件', size: Size(720, 320))
Widget timelineMarkdownPreview() => _timelinePreviewHost(
  TimelineMarkdown(
    id: 'preview-markdown',
    text:
        '## 有界阅读\n\n正文与 **强调**、`代码`、列表共享生产排版。\n\n'
        '- [官方文档](https://api.flutter.dev/)\n- 长行自然换行，不截断正文。',
    onLink: (_) {},
    isSafeLink: (url) => Uri.tryParse(url)?.scheme == 'https',
    imageBuilder: (_, _) => const Text('外部图片需要显式加载'),
  ),
);

@Preview(name: '正文 / 纯文本', group: 'Timeline · 历史组件', size: Size(340, 180))
Widget timelinePlainTextPreview() => _timelinePreviewHost(
  const TimelinePlainText(
    id: 'preview-plain',
    text: '不含 Markdown 的正文使用标准 Flutter 文本排版。窄窗口下这段合成文本仍应自然换行，并保留完整内容。',
  ),
);

@Preview(name: '过程 / 基础行与语义', group: 'Timeline · 历史组件', size: Size(600, 180))
Widget timelineActivityRowPreview() => _timelinePreviewHost(
  const Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TimelineActivityRow(icon: Icons.check, label: '已完成'),
      TimelineActivityRow(icon: Icons.stop_circle_outlined, label: '已停止'),
      TimelineActivityRow(label: '真实失败', isIssue: true),
    ],
  ),
);

@Preview(name: '工具 / 参数与结果', group: 'Timeline · 历史组件', size: Size(760, 400))
Widget timelineToolDetailsPreview() => _timelinePreviewHost(
  TimelineActivityTileTheme(
    child: TimelineToolDetails(
      item: (TimelinePreviewFixtures.tool.toolCard as DecodedToolCard).value,
    ),
  ),
);

@Preview(name: '工具 / 网页搜索', group: 'Timeline · 历史组件', size: Size(720, 320))
Widget timelineWebSearchPreview() => _timelinePreviewHost(
  TimelineActivityTileTheme(
    child: TimelineWebSearchToolCard(
      item:
          (TimelinePreviewFixtures.webSearch.toolCard as DecodedToolCard).value,
    ),
  ),
);

@Preview(name: '等待 / 折叠过程', group: 'Timeline · 历史组件', size: Size(720, 360))
Widget timelineWaitPanelPreview() => _timelinePreviewHost(
  TimelineActivityTileTheme(
    child: TimelineWaitPanel(
      identity: 'preview-wait-panel',
      presentation:
          (TimelinePreviewFixtures.waiting.toolCard as DecodedToolCard)
              .value
              .wait!,
    ),
  ),
);

@Preview(name: '等待 / 来源与规则', group: 'Timeline · 历史组件', size: Size(720, 360))
Widget timelineWaitDetailsPreview() => _timelinePreviewHost(
  TimelineWaitDetails(
    identity: 'preview-wait-details',
    presentation: (TimelinePreviewFixtures.waiting.toolCard as DecodedToolCard)
        .value
        .wait!,
  ),
);

@Preview(
  name: 'Children / 独立列表呈现',
  group: 'Timeline · 资源纯视图',
  size: Size(760, 400),
)
Widget timelineChildrenPreview() => _timelinePreviewHost(
  const SingleChildScrollView(child: _TimelineChildrenPreview()),
);

// Only the borrowed UI controller needs a local lifetime. No domain owner,
// provider, paging simulation or expansion mirror is constructed here.
class _TimelineChildrenPreview extends StatefulWidget {
  const _TimelineChildrenPreview();

  @override
  State<_TimelineChildrenPreview> createState() =>
      _TimelineChildrenPreviewState();
}

class _TimelineChildrenPreviewState extends State<_TimelineChildrenPreview> {
  late final controller = InMemoryChatController(
    messages: TimelinePreviewFixtures.messages(),
  );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TimelineChildrenView(
    controller: controller,
    generation: 1,
    isDisplayActive: () => true,
    contentRangeBuilder: (itemId, contentKey, label, reference, witness) =>
        TimelineContentRangeView(
          itemId: itemId,
          contentKey: contentKey,
          label: label,
          loading: false,
          active: true,
          canRead: true,
          window: TimelinePreviewFixtures.contentWindow,
          onExpansionChanged: (_) {},
          onNext: () {},
          onCopy: () {},
          witness: witness,
        ),
  );
}

@Preview(name: '降级 / 未知展示契约', group: 'Timeline · 历史组件', size: Size(720, 220))
Widget timelineFallbackPreview() =>
    _timelinePreviewHost(_chatItem(TimelinePreviewFixtures.fallback));

@Preview(name: '窄窗 / 150% 字体缩放', group: 'Timeline · 响应式', size: Size(340, 720))
Widget timelineNarrowScaledPreview() => _timelinePreviewHost(
  SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _chatItem(TimelinePreviewFixtures.assistant),
        _chatItem(TimelinePreviewFixtures.tool),
        _chatItem(TimelinePreviewFixtures.questionReceipt),
      ],
    ),
  ),
  maxWidth: 300,
  textScale: 1.5,
);

@Preview(
  name: '组合 TimelineView / 合成历史',
  group: 'Timeline · 组合视图',
  size: Size(1120, 820),
)
Widget timelineCombinedPreview() =>
    _timelinePreviewHost(const _TimelineCombinedPreview());

class _TimelineCombinedPreview extends StatefulWidget {
  const _TimelineCombinedPreview();

  @override
  State<_TimelineCombinedPreview> createState() =>
      _TimelineCombinedPreviewState();
}

class _TimelineCombinedPreviewState extends State<_TimelineCombinedPreview> {
  late final _PreviewTimelineControls controls = _PreviewTimelineControls();

  @override
  void dispose() {
    controls.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TimelineView(
    threadId: 'preview-thread',
    view: const TimelineSessionViewState(
      threadId: 'preview-thread',
      generation: 1,
      mode: TimelineDisplayMode.live,
      connection: TimelineConnectionPhase.ready,
    ),
    controls: controls,
    onLoadOlder: () async {},
    onRetryOlder: () async {},
    onReturnLive: () async {},
    onEnterHistory: () {},
    onRetryConnection: () {},
    onLink: (_) {},
    isSafeLink: (url) => Uri.tryParse(url)?.scheme == 'https',
    remoteImageBuilder: (_, _) => const Text('外部图片需要显式加载'),
    contentRangeBuilder: (itemId, contentKey, label, reference, witness) =>
        TimelineContentRangeView(
          itemId: itemId,
          contentKey: contentKey,
          label: label,
          initiallyExpanded: true,
          loading: false,
          active: true,
          canRead: true,
          window: TimelinePreviewFixtures.contentWindow,
          onExpansionChanged: (_) {},
          onNext: () {},
          onCopy: () {},
          witness: witness,
        ),
    attachmentBuilder: (item) => _previewAttachments(item.id, item.attachments),
  );
}

final class _PreviewTimelineControls implements TimelineUiControllers {
  _PreviewTimelineControls()
    : controller = InMemoryChatController(
        messages: TimelinePreviewFixtures.messages(),
      );

  @override
  final Key chatKey = const ValueKey('timeline-preview-chat');

  @override
  final InMemoryChatController controller;

  @override
  final ScrollController scrollController = ScrollController();

  @override
  bool get isRetired => false;

  @override
  void bind() {}

  @override
  Future<void> unbind() async {}

  void dispose() {
    controller.dispose();
    scrollController.dispose();
  }
}
