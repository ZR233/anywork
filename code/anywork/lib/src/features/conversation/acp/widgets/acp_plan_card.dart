import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_chrome.dart';
import '../state/acp_view_state.dart';

/// Collapsible execution plan card rendered with Siamese Light tokens.
///
/// When collapsed (e.g. sticky top bar inside an active conversation), the
/// single-line header surfaces the current `inProgress` step or completion state
/// along with a thin progress strip.
class AcpPlanCard extends StatefulWidget {
  const AcpPlanCard({
    super.key,
    required this.state,
    this.initiallyExpanded = true,
  });

  final AcpPlanCardViewState state;
  final bool initiallyExpanded;

  @override
  State<AcpPlanCard> createState() => _AcpPlanCardState();
}

class _AcpPlanCardState extends State<AcpPlanCard> {
  late bool _expanded = widget.initiallyExpanded;

  String _collapsedHeadline(BuildContext context, bool allDone) {
    final l10n = context.l10n;
    for (final entry in widget.state.entries) {
      if (entry.status == AcpPlanStatusKind.inProgress &&
          entry.content.trim().isNotEmpty) {
        return entry.content.trim();
      }
    }
    if (allDone) return l10n.acpPlanCompletedHeadline;
    return l10n.acpPlanTitle;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final total = widget.state.entries.length;
    final completed = widget.state.completedCount;
    final allDone = total > 0 && completed == total;
    final progress = total > 0 ? (completed / total).clamp(0.0, 1.0) : 0.0;
    final headerText = _expanded
        ? l10n.acpPlanTitle
        : _collapsedHeadline(context, allDone);

    return StudioPanel(
      backgroundColor: context.colors.surfaceContainerLowest,
      borderColor: context.colors.outlineVariant,
      radius: StudioRadii.md,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(StudioRadii.md),
              bottom: _expanded ? Radius.zero : Radius.circular(StudioRadii.md),
            ),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                children: [
                  Icon(
                    allDone ? Icons.task_alt_rounded : Icons.checklist_rounded,
                    size: 17,
                    color: allDone
                        ? StudioTone.success.indicator(context)
                        : context.colors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Tooltip(
                      message: headerText,
                      child: Text(
                        headerText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  StudioPill(
                    label: l10n.acpPlanProgress(completed, total),
                    tone: allDone ? StudioTone.success : StudioTone.brand,
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: context.colors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          LinearProgressIndicator(
            value: progress,
            minHeight: 2,
            backgroundColor: context.colors.surfaceContainerHigh,
            color: allDone
                ? StudioTone.success.indicator(context)
                : context.colors.primary,
          ),
          if (_expanded)
            Flexible(
              fit: FlexFit.loose,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < widget.state.entries.length; i++) ...[
                        if (i > 0) const SizedBox(height: 4),
                        _PlanEntryRow(entry: widget.state.entries[i]),
                      ],
                    ],
                  ),
                ),
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

    return DecoratedBox(
      decoration: BoxDecoration(
        color: inProgress
            ? context.colors.primary.withValues(alpha: 0.06)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(StudioRadii.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Tooltip(
                message: '$statusLabel · $priorityLabel',
                child: Icon(statusIcon, size: 16, color: statusColor),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                entry.content,
                style: context.text.bodySmall?.copyWith(
                  color: entry.status == AcpPlanStatusKind.completed
                      ? context.colors.onSurfaceVariant
                      : context.colors.onSurface,
                  fontWeight: inProgress ? FontWeight.w500 : FontWeight.w400,
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
