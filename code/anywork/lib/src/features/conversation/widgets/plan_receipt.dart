import 'package:anywork_client/conversation.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../l10n/studio_l10n.dart';
import '../../../diagnostics/studio_driver_keys.dart';
import '../../../ui/layout/studio_panel.dart';

import 'user_input_receipt.dart';

class PlanConfirmationReceipt extends StatelessWidget {
  const PlanConfirmationReceipt({required this.itemId, required this.receipt,
    this.expanded = false, this.onExpanded});
  final bool expanded;
  final ValueChanged<bool>? onExpanded;

  /// 承载这条计划回执的 canonical 工具条目身份。
  final String itemId;
  final PlanConfirmationReceiptView receipt;

  @override
  Widget build(BuildContext context) {
    final status = _planReceiptStatus(context, receipt.decision);
    final title = receipt.title;
    return StudioPanel(
      backgroundColor: context.colors.surfaceContainerLowest,
      radius: StudioRadii.md,
      child: ExpansionTile(
        initiallyExpanded: expanded,
        onExpansionChanged: onExpanded,
        key: StudioDriverKeys.timelinePlanReceipt(itemId),
        maintainState: false,
        dense: true,
        minTileHeight: 44,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        shape: const Border(),
        collapsedShape: const Border(),
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            UserInputStatusMark(icon: status.icon, tone: status.tone),
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
            key: StudioDriverKeys.timelinePlanReceiptReply(itemId),
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
