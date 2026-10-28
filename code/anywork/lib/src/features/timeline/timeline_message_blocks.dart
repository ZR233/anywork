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
  });

  final TimelineMessagePayload payload;
  final TimelineDisplayLease lease;
  final String threadId;

  /// 该成员是否作为活动组成员呈现：组内节奏比独立条目更紧。
  final bool inActivityGroup;

  @override
  Widget build(BuildContext context) {
    final payload = this.payload;
    final item = payload.item;
    if (timelineRendersNoContent(item)) return const SizedBox.shrink();
    final isUser = item.kind == ThreadItemKind.userMessage;
    final isParentAgent = item.kind == ThreadItemKind.parentAgentMessage;
    final isPrompt = isUser || isParentAgent;
    final compact = timelineIsCompactActivity(item);
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
            entry: timelineEntryViewOf(item),
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
      ThreadThinkingItemStateView() => TimelineReasoningBlock(
        itemId: item.id,
        entry: timelineEntryViewOf(item),
        details: _detailNotice(context, payload),
      ),
      ThreadToolItemStateView(:final userInput) => _toolOrReceipt(
        context,
        item: item,
        payload: payload,
        userInput: userInput,
      ),
      final ThreadAgentItemStateView agent => TimelineAgentPart(agent: agent),
      ThreadSkillItemStateView() => TimelineSkillActivityRow(
        payload: payload,
        onOpenDetail: (itemId, field) => unawaited(
          _openTimelineDetailViewer(
            context,
            lease: lease,
            itemId: itemId,
            field: field,
          ),
        ),
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
      // 计划语义只属于发起计划确认的那次工具调用：旧历史的普通问答工具可能复用过
      // 保留的问题 ID，因此不能按问题 ID/标题推断，只看工具条目自己的权威名称。
      // 普通问答历史继续走同一只读回执，不隐藏、也不冒充计划。
      final receipt = ownsPlanConfirmation(item.tool?.name)
          ? history.planReceipt
          : null;
      if (receipt != null) {
        // 待确认期间只保留尾部唯一摘要入口，不出现第二张计划历史卡。
        if (!receipt.isResolved) return const SizedBox.shrink();
        return _PlanConfirmationReceipt(itemId: item.id, receipt: receipt);
      }
      return _UserInputReceipt(itemId: item.id, history: history);
    }
    final wait = item.tool?.wait;
    if (wait != null) {
      final toolItem = TimelineToolItem(timelineEntryViewOf(item));
      return TimelineWaitPanel(
        presentation: wait,
        identity: item.id,
        diagnostics: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TimelineToolDetails(item: toolItem),
            ?_detailNotice(context, payload),
          ],
        ),
      );
    }
    final toolItem = TimelineToolItem(timelineEntryViewOf(item));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        timelineIsWebSearch(toolItem)
            ? TimelineWebSearchToolCard(item: toolItem)
            : TimelineToolDetails(item: toolItem),
        ?_detailNotice(context, payload),
      ],
    );
  }

  /// 被省略的正文仍可显式读取：默认预览不因异步全文回包自动扩大历史行。
  Widget? _detailNotice(BuildContext context, TimelineMessagePayload payload) {
    return timelinePayloadDetailNotice(
      context,
      payload,
      onOpenDetail: (itemId, field) => unawaited(
        _openTimelineDetailViewer(
          context,
          lease: lease,
          itemId: itemId,
          field: field,
        ),
      ),
    );
  }
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
    // 运行时说明不是历史载荷：它没有可展开内容，标题和正文都由界面本地化，
    // 不能用“原始历史记录”冒充，也不能把框架内部句子当作用户可见文案。
    if (record.origin == ThreadRawItemOrigin.runtimeControl) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TimelineActivityRow(
          key: ValueKey('runtime-notice-$itemId'),
          icon: Icons.info_outline,
          label: context.l10n.timelineRuntimeNotice,
          tooltip: context.l10n.timelineRuntimeNoticeDetail,
          expandable: false,
        ),
      );
    }
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

/// Turn 的终态结论；正常完成的 Turn 不额外占一行。
///
/// 取消与中断是正常控制结果，不等同执行失败：使用与思考／工具摘要对齐的
/// 紧凑中性状态行（停止图标 + 本地化文案），不使用错误底色或错误图标；
/// 真正失败与预算限制继续给出明确原因的错误横幅（design/19 §19.9）。
class _TurnOutcomeBlock extends StatelessWidget {
  const _TurnOutcomeBlock({required this.item});

  final ThreadItemView item;

  @override
  Widget build(BuildContext context) {
    if (!item.isTerminal) return const SizedBox.shrink();
    return switch (item.state) {
      ThreadTurnItemStateView(:final state) => switch (state) {
        CancelledStudioTurnState(:final cause) => Semantics(
          liveRegion: true,
          child: TimelineActivityRow(
            key: ValueKey('timeline-turn-outcome:${item.id}'),
            icon: Icons.stop_circle_outlined,
            label: _turnCancellationLabel(context, cause),
            expandable: false,
          ),
        ),
        FailedStudioTurnState() ||
        BudgetLimitedStudioTurnState() => _turnErrorBanner(context, item.error),
        QueuedStudioTurnState() ||
        RunningStudioTurnState() ||
        CompletedStudioTurnState() => const SizedBox.shrink(),
      },
      _ => _turnErrorBanner(context, item.error),
    };
  }

  Widget _turnErrorBanner(BuildContext context, String? reason) {
    if (reason == null || reason.isEmpty) return const SizedBox.shrink();
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

/// 按 typed 取消原因本地化。当前点击停止与运行中发送新消息都收束为
/// `Interrupted`；typed `UserRequested`（如 demo 停止）同样表示正常用户控制。
/// 两者都用中性“本轮已停止”；不根据草稿或活动推断打断来源，也不暗示已自动
/// 继续。`Unspecified` 保留“本轮已取消”。
String _turnCancellationLabel(
  BuildContext context,
  StudioTurnCancellationCause cause,
) => switch (cause) {
  InterruptedTurnCancellation() ||
  UserRequestedTurnCancellation() => context.l10n.timelineTurnStopped,
  UnspecifiedTurnCancellation() => context.l10n.timelineTurnCancelled,
  RuntimeShutdownTurnCancellation() => context.l10n.timelineTurnRuntimeShutdown,
  AgentClosedTurnCancellation() => context.l10n.timelineTurnAgentClosed,
  RecoveryTurnCancellation() => context.l10n.timelineTurnRecoveryStopped,
  CoalescedTurnCancellation() => context.l10n.timelineTurnCoalesced,
};

class _MarkdownBubble extends StatelessWidget {
  const _MarkdownBubble({required this.entry, required this.isUser, super.key});

  final TimelineEntry entry;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 取消与中断是正常控制结果，不用错误气泡；只有真实失败/拒绝/预算限制保留。
    final isIssue =
        !isUser &&
        const {'failed', 'denied', 'budgetLimited'}.contains(entry.status);
    final surface = isUser
        ? TimelineMarkdownSurface.user
        : isIssue
        ? TimelineMarkdownSurface.error
        : TimelineMarkdownSurface.assistant;
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
              TimelineAgentMarkdown(
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
