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
  });

  final TimelineMessagePayload payload;
  final TimelineDisplayLease lease;
  final String threadId;

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
    return Padding(
      key: StudioDriverKeys.timelineRow(item.id),
      padding: EdgeInsets.only(
        bottom: isPrompt
            ? 14
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
              constraints: BoxConstraints(maxWidth: isPrompt ? 560 : 700),
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
                  Opacity(
                    opacity: rolledBack ? 0.52 : 1,
                    child: _messageContent(context, payload),
                  ),
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
      ),
      ThreadToolItemStateView(:final userInput) => _toolOrReceipt(
        context,
        item: item,
        payload: payload,
        userInput: userInput,
      ),
      final ThreadAgentItemStateView agent => _AgentPart(agent: agent),
      ThreadSkillItemStateView() => _SkillActivationPart(
        key: StudioDriverKeys.timelineSkillActivation(item.id),
        activation: _skillOf(item)!,
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
    final truncated = [
      for (final detail in payload.details)
        if (detail.truncated) detail,
    ];
    if (truncated.isEmpty) {
      // 省略量已声明但没有任何字段引用：如实显示“预览被截断”，
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
  });

  final String itemId;
  final TimelineEntry entry;
  final Widget? details;

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
    final label = active
        ? plainReasoningSummary(entry.reasoningSummary.firstOrNull ?? '') ??
              context.l10n.timelineReasoningActive
        : context.l10n.timelineReasoningCompleted;
    final expandable =
        summary.isNotEmpty || content.isNotEmpty || widget.details != null;
    final title = _TimelineActivitySummary(
      key: StudioDriverKeys.timelineActivitySummary(widget.itemId),
      icon: Icons.psychology_alt_outlined,
      label: label,
      active: active,
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
      childrenPadding: const EdgeInsets.only(left: 7, bottom: 6),
      shape: const Border(),
      collapsedShape: const Border(),
      title: title,
      children: [
        if (summary.isNotEmpty || content.isNotEmpty)
          DecoratedBox(
            key: const ValueKey('timeline-activity-details'),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: context.colors.outlineVariant),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                ],
              ),
            ),
          ),
        ?widget.details,
      ],
    );
  }

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
                      SelectableText(payload.content),
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
      child: _TimelineActivitySummary(
        key: StudioDriverKeys.timelineBlock(itemId),
        icon: Icons.compress_outlined,
        label: context.l10n.timelineContextCompacted,
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

class _SkillActivationPart extends StatelessWidget {
  const _SkillActivationPart({required this.activation, super.key});

  final TimelineSkillActivation activation;

  @override
  Widget build(BuildContext context) {
    final label = switch (activation.cause.kind) {
      SkillActivationCauseKind.tool => context.l10n.timelineSkillAgentActivated(
        activation.name,
      ),
      SkillActivationCauseKind.userGesture =>
        context.l10n.timelineSkillUserActivated(activation.name),
    };
    return Semantics(
      container: true,
      label: label,
      value: activation.source,
      child: Tooltip(
        message: activation.resourceBase.value,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.colors.primaryContainer.withValues(alpha: 0.6),
            border: Border.all(color: context.colors.outlineVariant),
            borderRadius: BorderRadius.circular(StudioRadii.md),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.extension_outlined,
                  size: 15,
                  color: context.colors.onPrimaryContainer,
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (activation.source.trim().isNotEmpty) ...[
                  const SizedBox(width: 8),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: context.colors.surfaceContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      child: Text(
                        activation.source,
                        style: context.text.labelSmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
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

class _TimelineActivitySummary extends StatelessWidget {
  const _TimelineActivitySummary({
    required this.icon,
    required this.label,
    this.isIssue = false,
    this.expanded = false,
    this.active = false,
    this.expandable = true,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool isIssue;
  final bool expanded;
  final bool active;
  final bool expandable;

  @override
  Widget build(BuildContext context) {
    final color = context.colors.onSurfaceVariant;
    return SelectionContainer.disabled(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 28),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isIssue
                    ? Icons.error_outline
                    : active
                    ? Icons.pending_outlined
                    : icon,
                size: 15,
                color: isIssue
                    ? context.colors.error
                    : color.withValues(alpha: .78),
              ),
              const SizedBox(width: 8),
              Flexible(
                // 摘要持续追加：普通 Text，避免每次增量重新淡入。
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: context.text.bodySmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w400,
                    height: 1.25,
                  ),
                ),
              ),
              if (expandable) const SizedBox(width: 4),
              if (expandable)
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.chevron_right_rounded,
                  size: 15,
                  color: color.withValues(alpha: 0.72),
                ),
            ],
          ),
        ),
      ),
    );
  }
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

class _TimelinePanel extends StatelessWidget {
  const _TimelinePanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return StudioPanel(
      backgroundColor: context.colors.surfaceContainer,
      borderColor: colors.outlineVariant.withValues(alpha: 0.82),
      radius: StudioRadii.md,
      child: child,
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return StudioPill(label: label);
  }
}
