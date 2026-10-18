part of 'timeline_view.dart';

class TimelinePlanSummaryCard extends StatelessWidget {
  const TimelinePlanSummaryCard({
    required this.plan,
    required this.expanded,
    required this.onPressed,
    super.key,
  });

  final PlanConfirmationView plan;
  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    void toggle() {
      _TimelineItemLayoutScope.report(
        context,
        expanded
            ? _TimelineLayoutChangeKind.collapse
            : _TimelineLayoutChangeKind.expand,
      );
      onPressed();
    }

    final summary = plan.summary;
    final title = plan.title.isEmpty
        ? context.l10n.interactionPlanReadyTitle
        : plan.title;
    return Semantics(
      button: true,
      expanded: expanded,
      child: StudioPanel(
        key: StudioDriverKeys.planSummary,
        backgroundColor: expanded
            ? context.colors.surfaceContainerLow
            : context.colors.surfaceContainerLowest,
        borderColor: Colors.transparent,
        radius: StudioRadii.lg,
        shadow: false,
        child: InkWell(
          onTap: toggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.checklist_outlined,
                  size: 20,
                  color: context.colors.onSurfaceVariant,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.titleSmall?.copyWith(
                          color: context.colors.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (summary.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodySmall?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          StudioPill(
                            tone: StudioTone.warning,
                            icon: Icons.schedule_outlined,
                            label: context
                                .l10n
                                .interactionPlanAwaitingConfirmation,
                          ),
                          Text(
                            context.l10n.interactionPlanViewDetails,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.labelMedium?.copyWith(
                              color: context.colors.onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Icon(
                    expanded ? Icons.chevron_left : Icons.chevron_right,
                    size: 20,
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 计划确认的历史回执：批准、请求修改或取消，展开后可选读完整原回复。
///
/// 事实只来自发起 `plan_submit` 的工具条目携带的 typed 问答投影，因此待确认期间
/// 不出现这张卡（那时只有唯一的摘要入口），answered 之后也不因后续修订而改写。
/// 决定标记只用于选择本地化文案，`Approve` / `Revise` 这类内部标记不进入正文。
class _PlanConfirmationReceipt extends StatelessWidget {
  const _PlanConfirmationReceipt({required this.row, required this.receipt});

  final TimelineUserInputRow row;
  final PlanConfirmationReceiptView receipt;

  @override
  Widget build(BuildContext context) {
    final controller = _TimelineExpansionScope.controllerOf(context, row.id);
    final status = _planReceiptStatus(context, receipt.decision);
    final title = receipt.title;
    return StudioPanel(
      backgroundColor: context.colors.surfaceContainerLowest,
      radius: StudioRadii.md,
      child: ExpansionTile(
        key: StudioDriverKeys.timelinePlanReceipt(row.id),
        controller: controller,
        initiallyExpanded: controller.isExpanded,
        maintainState: false,
        dense: true,
        minTileHeight: 44,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        shape: const Border(),
        collapsedShape: const Border(),
        onExpansionChanged: (expanded) => _TimelineItemLayoutScope.report(
          context,
          expanded
              ? _TimelineLayoutChangeKind.expand
              : _TimelineLayoutChangeKind.collapse,
        ),
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _UserInputStatusMark(icon: status.icon, tone: status.tone),
            const SizedBox(width: 9),
            Flexible(
              child: Text(
                status.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.labelLarge?.copyWith(
                  color: context.colors.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        subtitle: title.isEmpty
            ? null
            : Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
        children: [
          _PlanReceiptReply(
            key: StudioDriverKeys.timelinePlanReceiptReply(row.id),
            receipt: receipt,
          ),
        ],
      ),
    );
  }
}

/// 展开内容：批准只本地化显示，修改意见保留用户原文并可选择复制。
class _PlanReceiptReply extends StatelessWidget {
  const _PlanReceiptReply({required this.receipt, super.key});

  final PlanConfirmationReceiptView receipt;

  @override
  Widget build(BuildContext context) {
    final reply = _planReceiptReplyText(context, receipt);
    if (reply.isEmpty) return const SizedBox.shrink();
    final label =
        receipt.decision == PlanConfirmationDecisionView.revisionRequested
        ? context.l10n.planReceiptYourFeedback
        : context.l10n.planReceiptYourReply;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: context.text.labelSmall?.copyWith(
            color: context.colors.onSurfaceVariant,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 5),
        DecoratedBox(
          decoration: BoxDecoration(
            color: context.colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(StudioRadii.xs),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            child: SelectableText(
              reply,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurface,
                height: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

({IconData icon, String label, StudioTone tone}) _planReceiptStatus(
  BuildContext context,
  PlanConfirmationDecisionView decision,
) {
  return switch (decision) {
    PlanConfirmationDecisionView.approved => (
      icon: Icons.check_rounded,
      label: context.l10n.planReceiptApproved,
      tone: StudioTone.success,
    ),
    PlanConfirmationDecisionView.revisionRequested => (
      icon: Icons.rate_review_outlined,
      label: context.l10n.planReceiptRevisionRequested,
      tone: StudioTone.warning,
    ),
    PlanConfirmationDecisionView.cancelled => (
      icon: Icons.remove_rounded,
      label: context.l10n.planReceiptCancelled,
      tone: StudioTone.neutral,
    ),
    PlanConfirmationDecisionView.resolved => (
      icon: Icons.task_alt_outlined,
      label: context.l10n.planReceiptAnswered,
      tone: StudioTone.neutral,
    ),
    PlanConfirmationDecisionView.pending => (
      icon: Icons.schedule_rounded,
      label: context.l10n.interactionPlanAwaitingConfirmation,
      tone: StudioTone.warning,
    ),
  };
}

String _planReceiptReplyText(
  BuildContext context,
  PlanConfirmationReceiptView receipt,
) {
  final reply = receipt.feedback
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .join('\n\n');
  if (reply.isNotEmpty) return reply;
  return switch (receipt.decision) {
    PlanConfirmationDecisionView.approved =>
      context.l10n.planReceiptApproveReply,
    PlanConfirmationDecisionView.cancelled => '',
    PlanConfirmationDecisionView.revisionRequested => '',
    PlanConfirmationDecisionView.resolved => '',
    PlanConfirmationDecisionView.pending => '',
  };
}

/// 计划详情头部动作组的统一最小命中尺寸（阅读切换与关闭同高）。
const double _planHeaderActionSize = 40;

/// 头部动作组的密度与命中区：桌面 `ThemeData` 默认 `shrinkWrap`，主题的
/// [VisualDensity.compact] 会把 40 缩到 32，因此这里显式要求标准密度与标准命中区，
/// 视觉 40、布局盒 48，与反馈栏的计划决定动作一致（design/13-plan.md §13.5）。
const VisualDensity _planHeaderVisualDensity = VisualDensity.standard;
const MaterialTapTargetSize _planHeaderTapTargetSize =
    MaterialTapTargetSize.padded;

/// 计划详情：安静、可独立滚动的只读文档页。
///
/// 头部只放标题、权威状态与阅读布局入口；正文自己滚动并显示滚动条，因此并排、
/// 全宽与短窗口下都不与对话滚动耦合（design/13-plan.md §13.5）。
class PlanDetailPanel extends StatefulWidget {
  const PlanDetailPanel({
    required this.identity,
    required this.markdown,
    required this.awaitingConfirmation,
    required this.onClose,
    this.onToggleReadingMode,
    this.fullWidth = false,
    super.key,
  });

  /// 固定头部 + 独立滚动正文至少需要的可用高度。
  ///
  /// 低于该高度时（短窗口 / 大字号），固定头部自身就可能超过可用高度并触发
  /// RenderFlex 溢出；此时整块退化为单一滚动容器，读法与锚点不变。
  static const double _minimumPinnedHeight = 260;

  final String identity;
  final String markdown;

  /// 待确认为真、已批准为假；只取交互/投影的权威状态，不由工具成功推断。
  final bool awaitingConfirmation;

  final VoidCallback onClose;

  /// 并排与全宽阅读之间的切换入口；为空表示当前窗口没有并排可能，不显示无意义开关。
  final VoidCallback? onToggleReadingMode;

  /// 当前是否整块占满会话阅读区域。
  final bool fullWidth;

  @override
  State<PlanDetailPanel> createState() => _PlanDetailPanelState();
}

class _PlanDetailPanelState extends State<PlanDetailPanel> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = planDocumentTitle(
      widget.markdown,
      fallback: context.l10n.interactionPlanDetailsTitle,
    );
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        // 头部动作组与标题列垂直居中：阅读/关闭不再随标题行高漂移。
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.article_outlined, size: 19, color: context.colors.primary),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  key: StudioDriverKeys.planDetailsTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleSmall?.copyWith(
                    color: context.colors.onSurface,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: StudioPill(
                    key: StudioDriverKeys.planDetailsStatus,
                    tone: widget.awaitingConfirmation
                        ? StudioTone.warning
                        : StudioTone.success,
                    icon: widget.awaitingConfirmation
                        ? Icons.schedule_outlined
                        : Icons.check_rounded,
                    label: widget.awaitingConfirmation
                        ? context.l10n.interactionPlanAwaitingConfirmation
                        : context.l10n.interactionPlanApproved,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 阅读切换与关闭组成一个紧凑动作组：统一标准命中尺寸、同组间距 4px。
          // 动作槽用紧约束 [Expanded] 填满自己那份宽度，组内再用 [MainAxisAlignment.end]
          // 把动作贴到头部右内边距上——宽松槽会把剩余空间留在关闭按钮右侧，动作组就
          // 停在标题旁边而不是面板右边界。紧约束同时保持有界：组内先分配固定尺寸的
          // 关闭按钮，可变的阅读标签只在自己的份额内省略，360px 最小宽度与英文大字号下
          // 都不会溢出，关闭始终可达；标题则在它之前的 [Expanded] 里两行截断。
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (widget.onToggleReadingMode case final toggle?) ...[
                  Flexible(
                    child: TextButton.icon(
                      key: StudioDriverKeys.planDetailsReadingMode,
                      icon: Icon(
                        widget.fullWidth
                            ? Icons.vertical_split_outlined
                            : Icons.open_in_full_rounded,
                        size: 16,
                      ),
                      label: Text(
                        widget.fullWidth
                            ? context.l10n.planRestoreSplit
                            : context.l10n.planExpandReading,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, _planHeaderActionSize),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        textStyle: context.text.labelMedium,
                        visualDensity: _planHeaderVisualDensity,
                        tapTargetSize: _planHeaderTapTargetSize,
                      ),
                      onPressed: toggle,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                IconButton(
                  key: StudioDriverKeys.planDetailsClose,
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  style: IconButton.styleFrom(
                    minimumSize: const Size.square(_planHeaderActionSize),
                    padding: EdgeInsets.zero,
                    visualDensity: _planHeaderVisualDensity,
                    tapTargetSize: _planHeaderTapTargetSize,
                  ),
                  icon: const Icon(Icons.chevron_right),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    final divider = Divider(height: 1, color: context.colors.outlineVariant);
    final markdown = KeyedSubtree(
      key: StudioDriverKeys.planDetailsMarkdown,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: StudioLayout.conversationWidth,
          ),
          child: _AgentMarkdown(
            id: 'plan:${widget.identity}',
            text: widget.markdown,
            surface: _MarkdownSurface.panel,
          ),
        ),
      ),
    );
    final body = ScrollConfiguration(
      behavior: ScrollConfiguration.of(context)
          .copyWith(scrollbars: false, overscroll: false),
      child: RawScrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        child: SelectionArea(
          child: ListView(
            key: PageStorageKey<String>('plan-details:${widget.identity}'),
            controller: _scrollController,
            primary: false,
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
            children: [markdown],
          ),
        ),
      ),
    );
    return Material(
      key: StudioDriverKeys.planDetails,
      color: context.colors.surfaceContainerLowest,
      elevation: 0,
      shape: Border(left: BorderSide(color: context.colors.outline)),
      child: SafeArea(
        left: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.hasBoundedHeight &&
                constraints.maxHeight < PlanDetailPanel._minimumPinnedHeight) {
              // 放不下固定头部时整块滚动，避免 RenderFlex 溢出（§19.10 短视口可读）。
              return KeyedSubtree(
                key: StudioDriverKeys.planDetailsScroll,
                child: RawScrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: SelectionArea(
                    child: SingleChildScrollView(
                      key: PageStorageKey<String>(
                        'plan-details:${widget.identity}',
                      ),
                      controller: _scrollController,
                      primary: false,
                      padding: const EdgeInsets.only(bottom: 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          header,
                          divider,
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                            child: markdown,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                divider,
                Expanded(
                  child: KeyedSubtree(
                    key: StudioDriverKeys.planDetailsScroll,
                    child: body,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
