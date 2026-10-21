part of 'timeline_view.dart';

class _EmptyTimeline extends StatelessWidget {
  const _EmptyTimeline();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: StudioEmptyState(
        icon: Icons.forum_outlined,
        title: context.l10n.timelineEmptyTitle,
        message: context.l10n.timelineEmptyMessage,
      ),
    );
  }
}

/// 一个原始成员的内容；可以独立呈现，也可以被展示组惰性构建。
class _TimelineMessageBlock extends StatelessWidget {
  const _TimelineMessageBlock({
    required this.payload,
    required this.lease,
    required this.threadId,
    this.inActivityGroup = false,
    this.embeddedReasoning = false,
    this.pairedSkillTool,
  });

  final TimelineMessagePayload payload;
  final TimelineDisplayLease lease;
  final String threadId;

  /// 该成员是否作为活动组成员呈现：组内节奏比独立条目更紧。
  final bool inActivityGroup;

  /// 单成员纯思考组：外层组摘要已承担折叠身份，正文直接展开显示。
  final bool embeddedReasoning;

  /// 与这条技能激活共享同一条可见行的原 `skill_view` 调用。
  ///
  /// 只由技能分支消费：包装、回退标记、间距与紧凑主题都沿用本成员原有路径。
  final TimelineMessagePayload? pairedSkillTool;

  @override
  Widget build(BuildContext context) {
    final payload = this.payload;
    final item = payload.item;
    if (_rendersNoContent(item)) return const SizedBox.shrink();
    final isUser = item.kind == ThreadItemKind.userMessage;
    final isParentAgent = item.kind == ThreadItemKind.parentAgentMessage;
    final isPrompt = isUser || isParentAgent;
    final compact = _isCompactActivity(item);
    final rolledBack =
        item.contextDisposition == ThreadContextDisposition.rolledBack;
    Widget content = Opacity(
      opacity: rolledBack ? 0.52 : 1,
      child: _messageContent(context, payload),
    );
    if (compact) {
      // 活动行自带行高，ListTile 默认垂直内边距只在这个作用域内收紧。
      content = TimelineActivityTileTheme(child: content);
    }
    return Padding(
      key: StudioDriverKeys.timelineRow(item.id),
      padding: EdgeInsets.only(
        bottom: isPrompt
            ? 14
            : inActivityGroup
            ? 2
            : compact
            ? 6
            : 12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isPrompt
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          Flexible(
            child: ConstrainedBox(
              // 回复正文使用阅读列内的可用宽度，不再叠加更窄的独立上限；
              // 用户与父代理消息保持右对齐的紧凑气泡（design/19 §19.7）。
              constraints: BoxConstraints(
                maxWidth: isPrompt
                    ? StudioLayout.conversationPromptWidth
                    : double.infinity,
              ),
              child: Column(
                crossAxisAlignment: isPrompt
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (isPrompt && item.turnId.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        context.l10n.promptAccepted,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  if (isParentAgent)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        context.l10n.timelineParentAgent,
                        key: StudioDriverKeys.parentAgentLabel(item.id),
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: context.colors.onSurfaceVariant),
                      ),
                    ),
                  content,
                  if (rolledBack)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: DecoratedBox(
                        key: StudioDriverKeys.timelineRolledBack(item.id),
                        decoration: BoxDecoration(
                          color: context.colors.surfaceContainer,
                          border: Border.all(
                            color: context.colors.outlineVariant,
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          child: Text(
                            context.l10n.timelineRolledBack,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: context.colors.onSurfaceVariant,
                                ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (isPrompt)
            _Avatar(
              icon: isParentAgent
                  ? Icons.account_tree_outlined
                  : Icons.person_outline,
            ),
        ],
      ),
    );
  }

  Widget _messageContent(BuildContext context, TimelineMessagePayload payload) {
    final item = payload.item;
    return switch (item.state) {
      ThreadTextItemStateView() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MarkdownBubble(
            key: ValueKey('timeline-text-${item.id}'),
            entry: _entryViewOf(item),
            isUser: item.kind == ThreadItemKind.userMessage,
          ),
          ?_detailNotice(context, payload),
        ],
      ),
      final ThreadRawItemStateView raw => _RawRecordBlock(
        itemId: item.id,
        record: raw,
        details: _detailNotice(context, payload),
      ),
      ThreadThinkingItemStateView() => _ReasoningBlock(
        itemId: item.id,
        entry: _entryViewOf(item),
        details: _detailNotice(context, payload),
        embedded: embeddedReasoning,
      ),
      ThreadToolItemStateView(:final userInput) => _toolOrReceipt(
        context,
        item: item,
        payload: payload,
        userInput: userInput,
      ),
      final ThreadAgentItemStateView agent => _AgentPart(agent: agent),
      ThreadSkillItemStateView() => _SkillActivityRow(
        payload: payload,
        tool: pairedSkillTool,
        lease: lease,
        threadId: threadId,
      ),
      final ThreadContextCompactionItemStateView compaction => _CompactionBlock(
        itemId: item.id,
        compaction: compaction,
      ),
      ThreadTurnItemStateView() => _TurnOutcomeBlock(item: item),
      ThreadInferenceItemStateView() ||
      ThreadFileItemStateView() => const SizedBox.shrink(),
    };
  }

  Widget _toolOrReceipt(
    BuildContext context, {
    required ThreadItemView item,
    required TimelineMessagePayload payload,
    required ThreadToolUserInputView? userInput,
  }) {
    final history = userInput ?? item.tool?.userInput;
    if (history != null) {
      final receipt = history.planReceipt;
      if (receipt != null) {
        // 待确认期间只保留尾部唯一摘要入口，不出现第二张计划历史卡。
        if (!receipt.isResolved) return const SizedBox.shrink();
        return _PlanConfirmationReceipt(itemId: item.id, receipt: receipt);
      }
      return _UserInputReceipt(itemId: item.id, history: history);
    }
    final wait = item.tool?.wait;
    if (wait != null) {
      final toolItem = _ToolItem(_entryViewOf(item));
      return TimelineWaitPanel(
        presentation: wait,
        identity: item.id,
        diagnostics: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ToolDetails(item: toolItem),
            ?_detailNotice(context, payload),
          ],
        ),
      );
    }
    final toolItem = _ToolItem(_entryViewOf(item));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _isWebSearch(toolItem)
            ? _WebSearchToolCard(item: toolItem)
            : _ToolDetails(item: toolItem),
        ?_detailNotice(context, payload),
      ],
    );
  }

  /// 被省略的正文仍可显式读取：默认预览不因异步全文回包自动扩大历史行。
  Widget? _detailNotice(BuildContext context, TimelineMessagePayload payload) {
    return _payloadDetailNotice(
      context,
      payload,
      lease: lease,
      threadId: threadId,
    );
  }
}

/// 一条成员预览的详情入口：技能行复用同一入口访问原调用与被省略的正文。
///
/// 每个被截断字段占一行活动行，没有字段可读时用同一行的说明如实报告，两种形态都不额外
/// 渲染“预览被截断”的解释段落（design/19 §19.9、design/26 §26.2）。
Widget? _payloadDetailNotice(
  BuildContext context,
  TimelineMessagePayload payload, {
  required TimelineDisplayLease lease,
  required String threadId,
}) {
  final truncated = [
    for (final detail in payload.details)
      if (detail.truncated) detail,
  ];
  if (truncated.isEmpty) {
    // 省略量已声明但没有任何字段引用：用不可点击的说明行如实报告原文不可得，
    // 不把省略当成原文不存在，也不伪造可读入口。
    if (!payload.hasOmittedBody) return null;
    return _TimelineTruncationNotice(itemId: payload.item.id);
  }
  return _TimelineDetailNotice(
    itemId: payload.item.id,
    lease: lease,
    threadId: threadId,
    details: truncated,
  );
}

/// 活动/推理/工具等紧凑行只占更小垂直间距。
/// 不承载可见内容的条目（推理/文件引用与正常完成的 Turn）不占任何高度。
///
/// 这些身份仍然存在于 stock controller 里（身份与顺序是权威事实），只是没有可展示正文；
/// 不能用带留白的空行把它们变成视觉空洞。
bool _rendersNoContent(ThreadItemView item) => switch (item.kind) {
  ThreadItemKind.inference || ThreadItemKind.file => true,
  ThreadItemKind.turn =>
    !item.isTerminal || (item.error == null || item.error!.isEmpty),
  _ => false,
};

bool _isCompactActivity(ThreadItemView item) => switch (item.kind) {
  ThreadItemKind.reasoning ||
  ThreadItemKind.toolCall ||
  ThreadItemKind.contextCompaction ||
  ThreadItemKind.skill ||
  ThreadItemKind.agent => true,
  _ => false,
};

/// 单条 canonical 条目的**无缓存** typed 展示视图。
///
/// 它只服务这一条 Message 的本次构建：不缓存、不参与身份判断、不形成第二套行集合或全文
/// 存储（design/26 §26.8「无缓存的单条转换／builder 可以保留」）。
TimelineEntry _entryViewOf(ThreadItemView item) => TimelineEntry(
  id: item.id,
  groupId: item.turnId,
  threadId: item.threadId,
  turnId: item.turnId,
  type: switch (item.kind) {
    ThreadItemKind.userMessage ||
    ThreadItemKind.parentAgentMessage ||
    ThreadItemKind.agentMessage ||
    ThreadItemKind.raw ||
    ThreadItemKind.agent => TimelineEntryType.text,
    ThreadItemKind.reasoning => TimelineEntryType.reasoning,
    ThreadItemKind.skill => TimelineEntryType.skill,
    ThreadItemKind.toolCall => TimelineEntryType.tool,
    ThreadItemKind.turn ||
    ThreadItemKind.inference ||
    ThreadItemKind.file ||
    ThreadItemKind.contextCompaction => TimelineEntryType.file,
  },
  order: item.ordinal,
  sequence: item.ordinal,
  revision: item.revision,
  createdAt: item.createdAt,
  updatedAt: item.updatedAt,
  completedAt: item.completedAt,
  error: item.error,
  // 推理正文不做整段拼接：分块原样交给 reasoningSummary/reasoningContent。
  text: item.kind == ThreadItemKind.reasoning ? '' : item.text,
  reasoningSummary: item.reasoningSummary,
  reasoningContent: item.reasoningContent,
  status: item.status,
  textChannel: switch (item.kind) {
    ThreadItemKind.userMessage => TimelineTextChannel.user,
    ThreadItemKind.parentAgentMessage => TimelineTextChannel.parentAgent,
    ThreadItemKind.agentMessage =>
      item.channel == AgentMessageChannel.commentary
          ? TimelineTextChannel.commentary
          : TimelineTextChannel.finalAnswer,
    _ => null,
  },
  tool: item.tool,
  skill: _skillOf(item),
  attachments: item.attachments,
  contextDisposition: item.contextDisposition,
);

TimelineSkillActivation? _skillOf(ThreadItemView item) {
  final skill = item.skill;
  if (skill == null) return null;
  return TimelineSkillActivation(
    name: skill.name,
    source: skill.source,
    providerId: skill.providerId,
    resourceBase: skill.resourceBase,
    cause: skill.cause,
    activatedAt: skill.activatedAt,
  );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          border: Border.all(color: colors.outlineVariant),
          shape: BoxShape.circle,
        ),
        child: SizedBox.square(
          dimension: 27,
          child: Icon(icon, size: 15, color: colors.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// 概要和内容各自按已有字段展示；缺失字段不生成占位区域。
class _ReasoningBlock extends StatefulWidget {
  const _ReasoningBlock({
    required this.itemId,
    required this.entry,
    this.details,
    this.embedded = false,
  });

  final String itemId;
  final TimelineEntry entry;
  final Widget? details;

  /// 外层组摘要已承担折叠身份时，只渲染该思考的原有正文，不再重复折叠行。
  final bool embedded;

  @override
  State<_ReasoningBlock> createState() => _ReasoningBlockState();
}

class _ReasoningBlockState extends State<_ReasoningBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final summary = entry.reasoningSummary
        .where((chunk) => chunk.trim().isNotEmpty)
        .join('\n\n');
    final content = entry.reasoningContent
        .where((chunk) => chunk.trim().isNotEmpty)
        .join('\n\n');
    final active = !isTerminalTimelineStatus(entry.status);
    final isIssue = _issueStatuses.contains(entry.status);
    final hasReasoning = summary.isNotEmpty || content.isNotEmpty;
    if (widget.embedded) {
      if (!hasReasoning && widget.details == null) {
        return const SizedBox.shrink();
      }
      // 正文已经随组展开常驻，不再占用成员折叠细节的 key（该 key 表示“此处可展开”）。
      return Padding(
        padding: const EdgeInsets.only(
          left: TimelineActivityRow.contentIndent,
          top: 2,
          bottom: 4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ..._sections(context, summary: summary, content: content),
            ?widget.details,
          ],
        ),
      );
    }
    final label = active
        ? plainReasoningSummary(entry.reasoningSummary.firstOrNull ?? '') ??
              context.l10n.timelineReasoningActive
        : _reasoningTerminalLabel(
            context,
            entry.status,
            entry.createdAt,
            entry.completedAt,
          );
    final expandable = hasReasoning || widget.details != null;
    final title = TimelineActivityRow(
      key: StudioDriverKeys.timelineActivitySummary(widget.itemId),
      icon: Icons.psychology_alt_outlined,
      label: label,
      active: active,
      isIssue: isIssue,
      expanded: _expanded,
      expandable: expandable,
    );
    if (!expandable) return title;
    return ExpansionTile(
      initiallyExpanded: _expanded,
      onExpansionChanged: (expanded) => setState(() => _expanded = expanded),
      maintainState: false,
      showTrailingIcon: false,
      minTileHeight: 28,
      dense: true,
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      shape: const Border(),
      collapsedShape: const Border(),
      title: title,
      children: [
        if (hasReasoning)
          Padding(
            key: const ValueKey('timeline-activity-details'),
            padding: const EdgeInsets.only(
              left: TimelineActivityRow.contentIndent,
              top: 2,
              bottom: 4,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _sections(context, summary: summary, content: content),
            ),
          ),
        ?widget.details,
      ],
    );
  }

  List<Widget> _sections(
    BuildContext context, {
    required String summary,
    required String content,
  }) => [
    if (summary.isNotEmpty)
      _section(
        context,
        key: 'timeline-thinking-summary-${widget.itemId}',
        title: context.l10n.timelineReasoningSummary,
        text: summary,
      ),
    if (content.isNotEmpty)
      _section(
        context,
        key: 'timeline-thinking-content-${widget.itemId}',
        title: context.l10n.timelineReasoningContent,
        text: content,
      ),
  ];

  Widget _section(
    BuildContext context, {
    required String key,
    required String title,
    required String text,
  }) => Padding(
    key: ValueKey(key),
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelectionContainer.disabled(
          child: Text(
            title,
            style: context.text.labelSmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 4),
        _AgentMarkdown(
          id: key,
          text: text,
          surface: _MarkdownSurface.reasoning,
        ),
      ],
    ),
  );
}

/// 终态思考的文案：失败与取消先保留真实状态，其余只报告该条目自身的有效耗时。
String _reasoningTerminalLabel(
  BuildContext context,
  String status,
  DateTime? createdAt,
  DateTime? completedAt,
) {
  final l10n = context.l10n;
  return switch (status) {
    'failed' => l10n.timelineReasoningFailed,
    'cancelled' => l10n.timelineReasoningCancelled,
    _ => _reasoningElapsedLabel(
      context,
      _reasoningElapsed(createdAt, completedAt),
    ),
  };
}

/// 耗时只来自同一思考条目的创建时间与 canonical 终态时间。
///
/// 不使用保存或更新时间冒充完成时间；缺失终态时间或时间顺序无效时返回 null，
/// 由调用方只说明思考结束，不 clamp 成看似正常的时长。
Duration? _reasoningElapsed(DateTime? createdAt, DateTime? completedAt) {
  if (createdAt == null || completedAt == null) return null;
  final elapsed = completedAt.difference(createdAt);
  return elapsed.isNegative ? null : elapsed;
}

String _reasoningElapsedLabel(BuildContext context, Duration? elapsed) {
  final l10n = context.l10n;
  if (elapsed == null) return l10n.timelineReasoningEnded;
  final seconds = elapsed.inSeconds;
  if (seconds <= 0) return l10n.timelineReasoningElapsedUnderSecond;
  if (seconds < 60) return l10n.timelineReasoningElapsedSeconds(seconds);
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  return remainder == 0
      ? l10n.timelineReasoningElapsedMinutes(minutes)
      : l10n.timelineReasoningElapsedMinutesSeconds(minutes, remainder);
}

/// raw 历史记录：展开只显示已交付的截断正文，完整字段走详情查看器。
class _RawRecordBlock extends StatelessWidget {
  const _RawRecordBlock({
    required this.itemId,
    required this.record,
    this.details,
  });

  final String itemId;
  final ThreadRawItemStateView record;
  final Widget? details;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExpansionTile(
            key: ValueKey('raw-history-$itemId'),
            title: Text(context.l10n.timelineRawRecord),
            subtitle: Text(record.notice),
            children: [
              for (final payload in record.payloads)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${payload.format} · v${payload.version}'),
                      const SizedBox(height: 8),
                      SelectableText(
                        payload.content,
                        style: DefaultTextStyle.of(context).style
                            .copyWith(fontFamily: studioCodeFontFamily),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          ?details,
        ],
      ),
    );
  }
}

/// 上下文压缩的紧凑事实行。
class _CompactionBlock extends StatelessWidget {
  const _CompactionBlock({required this.itemId, required this.compaction});

  final String itemId;
  final ThreadContextCompactionItemStateView compaction;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: switch ((compaction.beforeTokens, compaction.afterTokens)) {
        (final int before, final int after) =>
          context.l10n.timelineCompactionDetail(before, after),
        _ => context.l10n.timelineContextCompacted,
      },
      child: TimelineActivityRow(
        key: StudioDriverKeys.timelineBlock(itemId),
        icon: Icons.compress_outlined,
        label: context.l10n.timelineContextCompacted,
        expandable: false,
      ),
    );
  }
}

/// Turn 的失败/中断结论文本；正常完成的 Turn 不额外占一行。
class _TurnOutcomeBlock extends StatelessWidget {
  const _TurnOutcomeBlock({required this.item});

  final ThreadItemView item;

  @override
  Widget build(BuildContext context) {
    final reason = item.error;
    if (!item.isTerminal || reason == null || reason.isEmpty) {
      return const SizedBox.shrink();
    }
    return Semantics(
      liveRegion: true,
      child: Container(
        key: ValueKey('timeline-turn-outcome:${item.id}'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.colors.errorContainer.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: 18, color: context.colors.error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                reason,
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.error,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一条技能激活的可见活动行，必要时与原 `skill_view` 调用共享这一行。
///
/// 技能与其他活动成员使用同一个 [TimelineActivityRow]：固定图标列、单行次级文案与紧邻
/// 文案的箭头，不使用彩底徽章或来源胶囊。完整名称、来源与资源位置保留在提示和按需详情中；
/// 配对成功的原调用只隐藏它自己的行，参数、结果、诊断与全文详情仍从展开区读取
/// （design/19 §19.9、design/26 §26.8）。
class _SkillActivityRow extends StatefulWidget {
  const _SkillActivityRow({
    required this.payload,
    required this.lease,
    required this.threadId,
    this.tool,
  });

  /// 技能激活成员；标签与来源只来自它的 typed 事实。
  final TimelineMessagePayload payload;

  /// 同一 Turn 内被这次激活接管的 `skill_view` 成功调用；null 表示没有可配对的一侧。
  final TimelineMessagePayload? tool;

  final TimelineDisplayLease lease;
  final String threadId;

  @override
  State<_SkillActivityRow> createState() => _SkillActivityRowState();
}

class _SkillActivityRowState extends State<_SkillActivityRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final activation = _skillOf(widget.payload.item);
    if (activation == null) return const SizedBox.shrink();
    final tool = widget.tool;
    final meta = _skillActivityMeta(activation);
    final toolNotice = tool == null
        ? null
        : _payloadDetailNotice(
            context,
            tool,
            lease: widget.lease,
            threadId: widget.threadId,
          );
    final skillNotice = _payloadDetailNotice(
      context,
      widget.payload,
      lease: widget.lease,
      threadId: widget.threadId,
    );
    final expandable = meta.isNotEmpty || tool != null || skillNotice != null;
    final title = TimelineActivityRow(
      key: StudioDriverKeys.timelineSkillActivation(widget.payload.item.id),
      icon: Icons.extension_outlined,
      label: switch (activation.cause.kind) {
        SkillActivationCauseKind.tool =>
          context.l10n.timelineSkillAgentActivated(activation.name),
        SkillActivationCauseKind.userGesture =>
          context.l10n.timelineSkillUserActivated(activation.name),
      },
      active: !widget.payload.item.isTerminal,
      isIssue: _issueStatuses.contains(widget.payload.item.status),
      expandable: expandable,
      expanded: _expanded,
      tooltip: [
        activation.name.trim(),
        ...meta,
      ].where((value) => value.isNotEmpty).join('\n'),
    );
    if (!expandable) return title;
    return ExpansionTile(
      key: ValueKey('timeline-skill-details:${widget.payload.item.id}'),
      initiallyExpanded: _expanded,
      onExpansionChanged: (expanded) => setState(() => _expanded = expanded),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(
        left: TimelineActivityRow.contentIndent,
        bottom: 8,
      ),
      shape: const Border(),
      collapsedShape: const Border(),
      dense: true,
      minTileHeight: 28,
      showTrailingIcon: false,
      title: title,
      children: [
        if (meta.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              meta.join(' · '),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        // 原调用的参数、结果、诊断与出错原因仍走同一工具详情实现。
        if (tool != null)
          _ToolDetails(item: _ToolItem(_entryViewOf(tool.item)), inline: true),
        ?toolNotice,
        ?skillNotice,
      ],
    );
  }
}

/// 技能激活的来源与资源位置：只作按需详情与提示，不塞进单行文案。
List<String> _skillActivityMeta(TimelineSkillActivation activation) {
  final source = activation.source.trim();
  final resourceBase = activation.resourceBase.value.trim();
  return [
    if (source.isNotEmpty) source,
    if (resourceBase.isNotEmpty && resourceBase != source) resourceBase,
  ];
}

/// 技能行与接管调用的成员监听绑定：任一侧更新只重建这一行。
///
/// 行内容仍走 [_TimelineMessageBlock]：canonical 行身份、回退标记、组内间距、阅读宽度与
/// 紧凑主题都与其它活动成员一致，技能不重复实现一套包装。
class _SkillActivity extends StatelessWidget {
  const _SkillActivity({
    required this.skill,
    required this.lease,
    required this.threadId,
    this.tool,
    super.key,
  });

  final ValueListenable<TimelineMessagePayload> skill;
  final ValueListenable<TimelineMessagePayload>? tool;
  final TimelineDisplayLease lease;
  final String threadId;

  @override
  Widget build(BuildContext context) {
    final tool = this.tool;
    if (tool == null) {
      return ValueListenableBuilder<TimelineMessagePayload>(
        valueListenable: skill,
        builder: (context, payload, _) => _TimelineMessageBlock(
          payload: payload,
          lease: lease,
          threadId: threadId,
          inActivityGroup: true,
        ),
      );
    }
    return ValueListenableBuilder<TimelineMessagePayload>(
      valueListenable: skill,
      builder: (context, skillPayload, _) =>
          ValueListenableBuilder<TimelineMessagePayload>(
            valueListenable: tool,
            builder: (context, toolPayload, _) => _TimelineMessageBlock(
              payload: skillPayload,
              pairedSkillTool: toolPayload,
              lease: lease,
              threadId: threadId,
              inActivityGroup: true,
            ),
          ),
    );
  }
}

class _MarkdownBubble extends StatelessWidget {
  const _MarkdownBubble({required this.entry, required this.isUser, super.key});

  final TimelineEntry entry;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isIssue =
        !isUser &&
        const {
          'failed',
          'interrupted',
          'cancelled',
          'denied',
          'budgetLimited',
        }.contains(entry.status);
    final surface = isUser
        ? _MarkdownSurface.user
        : isIssue
        ? _MarkdownSurface.error
        : _MarkdownSurface.assistant;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isUser ? context.colors.surfaceContainer : Colors.transparent,
        border: isUser
            ? Border.all(color: scheme.outlineVariant.withValues(alpha: 0.72))
            : null,
        borderRadius: BorderRadius.circular(StudioRadii.md),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isUser ? 14 : 0,
          vertical: isUser ? 10 : 0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (entry.attachments.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final attachment in entry.attachments)
                    _ThreadAttachmentCard(
                      driverKey: StudioDriverKeys.historyAttachment(
                        attachment.id,
                      ),
                      threadId: entry.threadId,
                      attachment: attachment,
                    ),
                ],
              ),
            if (entry.attachments.isNotEmpty && entry.text.trim().isNotEmpty)
              const SizedBox(height: 8),
            if (entry.text.trim().isNotEmpty || entry.error != null)
              _AgentMarkdown(
                id: entry.id,
                text: entry.text.trim().isEmpty
                    ? entry.error ?? ''
                    : entry.text,
                surface: surface,
              ),
          ],
        ),
      ),
    );
  }
}

IconData _attachmentIcon(AttachmentModalityView modality) => switch (modality) {
  AttachmentModalityView.image => Icons.image_outlined,
  AttachmentModalityView.video => Icons.movie_outlined,
  AttachmentModalityView.file => Icons.insert_drive_file_outlined,
};

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _TimelineMetaRow extends StatelessWidget {
  const _TimelineMetaRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          Icon(icon, size: 17, color: context.colors.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelLarge?.copyWith(
                    color: context.colors.onSurface,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
