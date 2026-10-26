import 'package:anywork_client/account_usage.dart';
import 'package:flutter/material.dart';

import '../../../diagnostics/studio_driver_keys.dart';
import '../../../l10n/studio_l10n.dart';
import '../../../ui/formatters/cost_format.dart';

class WorkspaceCostChip extends StatelessWidget {
  const WorkspaceCostChip({required this.cost, super.key});
  final SessionCost? cost;

  @override
  Widget build(BuildContext context) {
    final value = cost;
    final label = value == null ? '' : formatRuntimeCosts(value.estimatedCosts);
    return Tooltip(
      message: [
        context.l10n.sessionAllAgentsCostTooltip,
        if (value?.hasUnpricedUsage == true)
          context.l10n.statusUnpricedUsageLabel,
        for (final purpose in value?.purposeCosts ?? const <PurposeCost>[])
          '${_purpose(context, purpose.purpose)}: ${formatRuntimeCosts(purpose.estimatedCosts)}'
              '${purpose.hasUnpricedUsage ? ' (${context.l10n.statusUnpricedUsageLabel})' : ''}',
      ].join('\n'),
      child: Padding(
        key: StudioDriverKeys.sessionCost,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(
          label.isEmpty ? '-' : label,
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ),
    );
  }

  String _purpose(BuildContext context, String? purpose) => switch (purpose) {
    'main' => context.l10n.costPurposeMain,
    'summary' => context.l10n.costPurposeSummary,
    'review' => context.l10n.costPurposeReview,
    'title' => context.l10n.costPurposeTitle,
    null => context.l10n.costPurposeUnknown,
    String value => value,
  };
}
