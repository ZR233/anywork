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

/// Timeline 的收束区域：计划摘要位于消息之后。
///
/// 当前活动不再在这里渲染（那会与消息列里的同一行形成两套搬动的渲染）；活动只由
/// 输入框上方的固定活动条呈现。收束区作为正向区的一部分参与贴底几何
/// 由 Timeline 的官方 Sliver 布局自然决定，不依赖固定最小高度。
class _TimelineTail extends StatelessWidget {
  const _TimelineTail({this.planSummary});

  final Widget? planSummary;

  @override
  Widget build(BuildContext context) {
    final currentPlan = planSummary;
    final alignedPlan = currentPlan == null
        ? null
        : Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: currentPlan,
            ),
          );
    return Column(
      key: const ValueKey('timeline-tail'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?alignedPlan,
        const SizedBox(key: ValueKey('timeline-tail-bottom-gap'), height: 14),
      ],
    );
  }
}

class _JumpToLatestButton extends StatelessWidget {
  const _JumpToLatestButton({
    required this.pendingCount,
    required this.onPressed,
  });

  final int pendingCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.labelSmall;
    return Tooltip(
      key: ValueKey('timeline-jump-to-latest:$pendingCount'),
      message: context.l10n.timelineJumpToLatest,
      child: Material(
        elevation: 0,
        color: context.colors.primaryContainer,
        shape: StadiumBorder(
          side: BorderSide(
            color: context.colors.primary.withValues(alpha: 0.18),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('timeline-jump-latest'),
          onTap: onPressed,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: pendingCount > 0 ? 10 : 8,
              vertical: 7,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: context.colors.onPrimaryContainer,
                ),
                if (pendingCount > 0) ...[
                  const SizedBox(width: 4),
                  Text(
                    context.l10n.timelineNew,
                    style: textStyle?.copyWith(
                      color: context.colors.onPrimaryContainer,
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

class _TimelineRowBlock extends StatelessWidget {
  const _TimelineRowBlock({required this.row, this.body = const [], super.key});

  final TimelineRow row;

  /// 该行底层超大条目的完整正文状态；空列表表示该行不需要回源。
  ///
  /// 按 canonical item id 携带，因此分组行（工具/推理）可以携带多条互不相同的回源入口。
  final List<_ItemBodyState> body;

  @override
  Widget build(BuildContext context) {
    if (row.raw case final raw?) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExpansionTile(
              key: ValueKey('raw-history-${row.id}'),
              title: Text(context.l10n.timelineRawRecord),
              subtitle: Text(raw.notice),
              children: [
                for (final payload in raw.payloads)
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
            // raw 载荷同样可能被单条预览预算截断：展开只显示截断文本，回源入口单独给出。
            for (final state in body) _ItemBodyNotice(state: state),
          ],
        ),
      );
    }
    final isUser = row.type == TimelineRowType.userMessage;
    final isParentAgent = row.type == TimelineRowType.parentAgentMessage;
    final isPrompt = isUser || isParentAgent;
    final isCompactActivity = row.isCompactActivity;
    return Padding(
      key: StudioDriverKeys.timelineRow(row.id),
      padding: EdgeInsets.only(
        bottom: isCompactActivity
            ? 6
            : isPrompt
            ? 14
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
                  if (isPrompt && row.turnId?.isEmpty == true)
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
                        key: StudioDriverKeys.parentAgentLabel(row.id),
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: context.colors.onSurfaceVariant),
                      ),
                    ),
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Opacity(
                        opacity: row.isRolledBack ? 0.52 : 1,
                        child: _RowCard(key: ValueKey(row.id), row: row),
                      ),
                      // 等待保存状态以内联角标附着在行块角落：状态切换只改变
                      // 图标可见性，不额外撑高行底部，正文几何与滚动锚点因此不受影响。
                      Positioned(
                        right: isPrompt ? 6 : null,
                        left: isPrompt ? null : 0,
                        bottom: 2,
                        child: SizedBox.square(
                          dimension: 16,
                          child: Center(
                            child: Visibility(
                              visible: !row.saved,
                              maintainSize: true,
                              maintainAnimation: true,
                              maintainState: true,
                              child: Tooltip(
                                message: context.l10n.timelinePendingSave,
                                child: Icon(
                                  Icons.cloud_upload_outlined,
                                  size: 13,
                                  color: context.colors.onSurfaceVariant
                                      .withValues(alpha: 0.72),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (row.isRolledBack)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: DecoratedBox(
                        key: StudioDriverKeys.timelineRolledBack(row.id),
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
                  // 分组行的展开只放大已截断文本；完整正文按底层条目身份单独回源。
                  for (final state in body) _ItemBodyNotice(state: state),
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

/// 折叠条目的完整正文提示：可见的加载 / 失败 / 重试路径。
///
/// 推理 / 工具 / raw 的窗口预览按底层条目身份给出显式补齐入口；补齐
/// 进行中显示加载态；失败时显示错误与重试。智能体正文不在此列：它由窗口按身份自动补齐，
/// 因此既不显示分页/折叠入口，也不需要读者点击加载。所有状态只改变该条目的载荷，不改变
/// 身份、ordinal 或用户阅读位置。
class _ItemBodyNotice extends StatelessWidget {
  const _ItemBodyNotice({required this.state});

  final _ItemBodyState state;

  @override
  Widget build(BuildContext context) {
    final error = state.error;
    final message = state.isLoading
        ? context.l10n.timelineItemBodyLoading
        : error ??
              (state.isUnavailable
                  ? context.l10n.timelineItemBodyUnavailable
                  : state.isPending
                  ? context.l10n.timelineItemBodyPending
                  : context.l10n.timelineItemBodyTruncated);
    // 数据来源标签（例如工具名）让同一分组里的多条回源入口彼此可区分。
    final source = state.label;
    final label = source == null || source.isEmpty
        ? message
        : '$source · $message';
    final onLoad = state.onLoad;
    // "在途/失败" 都是可重试的：只有数据源明确表示身份不可解析时才收起入口。
    final canLoad =
        !state.isLoading &&
        !state.isUnavailable &&
        state.isPreviewed &&
        onLoad != null;
    final needsRetry = error != null || state.isPending;
    return Padding(
      key: StudioDriverKeys.timelineItemBodyNotice(state.itemId),
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state.isLoading) ...[
            const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
          ] else ...[
            Icon(
              error != null
                  ? Icons.error_outline
                  : state.isUnavailable
                  ? Icons.info_outline
                  : state.isPending
                  ? Icons.hourglass_empty
                  : Icons.unfold_more,
              size: 15,
              color: error == null
                  ? context.colors.onSurfaceVariant
                  : context.colors.error,
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: error == null
                    ? context.colors.onSurfaceVariant
                    : context.colors.error,
              ),
            ),
          ),
          if (canLoad) ...[
            const SizedBox(width: 6),
            TextButton(
              key: needsRetry
                  ? StudioDriverKeys.timelineItemBodyRetry(state.itemId)
                  : StudioDriverKeys.timelineItemBodyLoad(state.itemId),
              onPressed: onLoad,
              child: Text(
                needsRetry
                    ? context.l10n.timelineItemBodyRetry
                    : context.l10n.timelineItemBodyLoad,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RowCard extends StatelessWidget {
  const _RowCard({required this.row, super.key});

  final TimelineRow row;

  @override
  Widget build(BuildContext context) {
    final row = this.row;
    return switch (row) {
      TimelineOutcomeRow() => Semantics(
        liveRegion: true,
        child: Container(
          key: ValueKey('timeline-turn-outcome:${row.turnId}'),
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
                  row.reason,
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.error,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      final TimelineTextRow text => _MarkdownBubble(
        key: ValueKey(text.part.id),
        part: text.part,
        isUser: text.isPrompt,
      ),
      final TimelineRawRow raw => _MarkdownBubble(
        part: raw.part,
        isUser: false,
      ),
      TimelineActivityRow(:final group) => _ActivityGroupPart(group: group),
      TimelineImageRow() => _ImageReadPart(row: row),
      // 计划确认复用同一 typed 历史通道，但用计划专用回执而不是普通问答表单；
      // 待确认期间只保留尾部唯一摘要入口，因此这里不出现第二张计划历史卡。
      // 普通问答的投影、脱敏与排序都不经过这条分支之外的变化。
      final TimelineUserInputRow input => switch (input.history.planReceipt) {
        final receipt? when receipt.isResolved => _PlanConfirmationReceipt(
          row: input,
          receipt: receipt,
        ),
        PlanConfirmationReceiptView() => const SizedBox.shrink(),
        null => _UserInputReceipt(row: input),
      },
      TimelineSkillRow(:final activation) => _SkillActivationPart(
        key: StudioDriverKeys.timelineSkillActivation(row.id),
        activation: activation,
      ),
      TimelineAgentRow(:final agent) => _AgentPart(agent: agent),
      TimelineCompactionRow(:final compaction) => Tooltip(
        message: switch ((compaction.beforeTokens, compaction.afterTokens)) {
          (final int before, final int after) =>
            context.l10n.timelineCompactionDetail(before, after),
          _ => context.l10n.timelineContextCompacted,
        },
        child: _TimelineActivitySummary(
          icon: Icons.compress_outlined,
          label: context.l10n.timelineContextCompacted,
        ),
      ),
    };
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
  const _MarkdownBubble({required this.part, required this.isUser, super.key});

  final TimelineEntry part;
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
        }.contains(part.status);
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
            if (part.attachments.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final attachment in part.attachments)
                    _ThreadAttachmentCard(
                      driverKey: StudioDriverKeys.historyAttachment(
                        attachment.id,
                      ),
                      threadId: part.threadId,
                      attachment: attachment,
                    ),
                ],
              ),
            if (part.attachments.isNotEmpty && part.text.trim().isNotEmpty)
              const SizedBox(height: 8),
            if (part.text.trim().isNotEmpty || part.error != null)
              _AgentMarkdown(
                id: part.id,
                text: part.text.trim().isEmpty ? part.error ?? '' : part.text,
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
  });

  final IconData icon;
  final String label;
  final bool isIssue;

  @override
  Widget build(BuildContext context) {
    final color = isIssue
        ? Theme.of(context).colorScheme.error
        : context.colors.onSurfaceVariant;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 28),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color.withValues(alpha: 0.78)),
            const SizedBox(width: 8),
            Flexible(
              // 摘要是持续追加的文本，不是一次性出现的内容：这里必须是普通 Text。
              // 用 AnimatedSwitcher + label-key 会让每次增量都重新开始一段淡入淡出，
              // 持续输出时多个旧文本同时退场，表现为摘要忽明忽暗、叠影。
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: context.text.bodySmall?.copyWith(
                  color: color,
                  fontWeight: isIssue ? FontWeight.w600 : FontWeight.w400,
                  height: 1.25,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 15,
              color: color.withValues(alpha: 0.72),
            ),
          ],
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
