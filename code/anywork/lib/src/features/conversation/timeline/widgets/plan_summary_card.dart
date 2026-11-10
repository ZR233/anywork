import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';

/// A document entry only: the reading panel and decision dock own their actions.
class PlanSummaryCard extends StatelessWidget {
  const PlanSummaryCard({
    required this.title,
    required this.expanded,
    required this.onToggle,
    super.key,
  });

  final String title;
  final bool expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = Theme.of(context)
        .extension<StudioSemanticColors>()!
        .activeIndicator;
    final radius = BorderRadius.circular(12);
    return MergeSemantics(
      child: Semantics(
        button: true,
        expanded: expanded,
        child: Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          color: colors.surfaceContainerLowest,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: colors.outlineVariant),
          ),
          child: InkWell(
            onTap: onToggle,
            borderRadius: radius,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Icon(
                        Icons.description_outlined,
                        color: accent,
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: context.text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          spacing: 16,
                          runSpacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            // Unlike a compact pill, this badge must retain its
                            // entire label when the reading column is narrow.
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: StudioTone.warning.background(context),
                                border: Border.all(
                                  color: colors.outlineVariant,
                                ),
                                borderRadius: BorderRadius.circular(
                                  StudioRadii.pill,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 4,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.schedule_outlined,
                                      size: 14,
                                      color: StudioTone.warning.indicator(
                                        context,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Flexible(
                                      child: Text(
                                        context
                                            .l10n
                                            .interactionPlanAwaitingConfirmation,
                                        style: context.text.labelSmall
                                            ?.copyWith(
                                              color: StudioTone.warning
                                                  .foreground(context),
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    expanded
                                        ? context
                                              .l10n
                                              .interactionPlanCollapseDetails
                                        : context
                                              .l10n
                                              .interactionPlanViewDetails,
                                    style: context.text.labelLarge?.copyWith(
                                      color: colors.primary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  expanded
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  color: colors.primary,
                                  size: 20,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
