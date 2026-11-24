import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_chrome.dart';
import '../state/acp_view_state.dart';

/// 统一右侧边栏内的 ACP 执行步骤面板，保留进度条、状态图标、高优先级标签与
/// 完整步骤文本。
class AcpPlanPanel extends StatelessWidget {
  const AcpPlanPanel({super.key, required this.state});

  final AcpPlanCardViewState state;

  @override
  Widget build(BuildContext context) {
    final total = state.entries.length;
    final completed = state.completedCount;
    final allDone = total > 0 && completed == total;
    final progress = total > 0 ? (completed / total).clamp(0.0, 1.0) : 0.0;

    return Material(
      color: context.colors.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (total > 0)
            LinearProgressIndicator(
              value: progress,
              minHeight: 2,
              backgroundColor: context.colors.surfaceContainerHigh,
              color: allDone
                  ? StudioTone.success.indicator(context)
                  : context.colors.primary,
            ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              itemCount: state.entries.length,
              separatorBuilder: (context, index) => const SizedBox(height: 4),
              itemBuilder: (context, index) =>
                  _PlanEntryRow(entry: state.entries[index]),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanEntryRow extends StatelessWidget {
  const _PlanEntryRow({required this.entry});

  final AcpPlanEntryPresentation entry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (statusIcon, statusColor, statusLabel) = switch (entry.status) {
      AcpPlanStatusKind.completed => (
        Icons.check_circle_rounded,
        StudioTone.success.indicator(context),
        l10n.acpPlanStatusCompleted,
      ),
      AcpPlanStatusKind.inProgress => (
        Icons.timelapse_rounded,
        context.colors.primary,
        l10n.acpPlanStatusInProgress,
      ),
      AcpPlanStatusKind.pending => (
        Icons.radio_button_unchecked_rounded,
        context.colors.onSurfaceVariant,
        l10n.acpPlanStatusPending,
      ),
    };
    final priorityLabel = switch (entry.priority) {
      AcpPlanPriorityKind.high => l10n.acpPlanPriorityHigh,
      AcpPlanPriorityKind.medium => l10n.acpPlanPriorityMedium,
      AcpPlanPriorityKind.low => l10n.acpPlanPriorityLow,
    };
    final inProgress = entry.status == AcpPlanStatusKind.inProgress;
    final completed = entry.status == AcpPlanStatusKind.completed;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: inProgress
            ? context.colors.primary.withValues(alpha: 0.06)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(StudioRadii.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Tooltip(
                message: '$statusLabel · $priorityLabel',
                child: Icon(
                  statusIcon,
                  size: 16,
                  color: statusColor,
                  semanticLabel: '$statusLabel · $priorityLabel',
                ),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                entry.content,
                style: context.text.bodySmall?.copyWith(
                  color: completed
                      ? context.colors.onSurfaceVariant
                      : context.colors.onSurface,
                  fontWeight: inProgress ? FontWeight.w500 : FontWeight.w400,
                  decoration: completed ? TextDecoration.lineThrough : null,
                  decorationColor: context.colors.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  height: 1.45,
                ),
              ),
            ),
            if (entry.priority == AcpPlanPriorityKind.high) ...[
              const SizedBox(width: 8),
              StudioPill(label: priorityLabel, tone: StudioTone.warning),
            ],
          ],
        ),
      ),
    );
  }
}
