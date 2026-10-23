import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';

import '../../../diagnostics/studio_driver_keys.dart';
import '../../../l10n/studio_l10n.dart';
import '../../../ui/formatters/cost_format.dart';
import '../../../ui/formatters/token_format.dart';
import '../../../ui/status/status_detail_panel.dart';
import '../state/thread_context_state.dart';

class ContextUsageGraphic extends StatelessWidget {
  const ContextUsageGraphic({required this.fraction, super.key});
  final double? fraction;
  @override
  Widget build(BuildContext context) => Semantics(
    label: context.l10n.statusContextLabel,
    value: fraction == null ? '—' : '${(fraction! * 100).toStringAsFixed(1)}%',
    child: SizedBox(width: 36, height: 10, child: ClipRRect(
      borderRadius: BorderRadius.circular(8), child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: fraction == null ? const SizedBox.shrink() : Align(
          alignment: Alignment.centerLeft, child: FractionallySizedBox(
            widthFactor: fraction!.clamp(0.0, 1.0), heightFactor: 1,
            child: ColoredBox(color: Theme.of(context).colorScheme.primary)))))));
}

class ThreadContextDetailView extends StatelessWidget {
  const ThreadContextDetailView({required this.state, required this.onRetry,
    required this.onLoadCosts, required this.onLoadSavings, required this.onLoadText,
    this.onCompact, super.key});
  final ThreadContextViewState state;
  final VoidCallback onRetry;
  final VoidCallback onLoadCosts;
  final VoidCallback onLoadSavings;
  final ValueChanged<int> onLoadText;
  final VoidCallback? onCompact;

  @override
  Widget build(BuildContext context) {
    final usage = state.frozenUsage;
    final current = state.currentPolicy;
    final ratio = state.fraction;
    return StatusDetailPanel(title: context.l10n.statusContextLabel, children: [
      if (state.loading) const LinearProgressIndicator(),
      Row(children: [Expanded(child: ContextUsageGraphic(fraction: ratio)),
        Text(ratio == null ? '—' : '${(ratio * 100).toStringAsFixed(1)}%'),
        TextButton(key: StudioDriverKeys.compactContext(),
          onPressed: onCompact, child: Text(context.l10n.statusCompactNow))]),
      StatusDetailRow(label: context.l10n.statusContextLabel, value: formatTokenCount(state.usedTokens)),
      StatusDetailRow(label: context.l10n.statusAutoCompactLimitLabel, value: formatTokenCount(state.displayLimit)),
      // Current policy is a separate canonical source, never a repair for history.
      StatusDetailRow(label: context.l10n.statusModelEffectiveWindowLabel, value: formatTokenCount(current?.contextWindow)),
      StatusDetailRow(label: context.l10n.statusModelMaxContextLabel, value: formatTokenCount(current?.maxContextWindow)),
      if (state.header?.frozenModelId case final model?) _readText(context, model),
      if (state.header?.promptCachePolicy case final policy?) _readText(context, policy),
      if (usage != null) ...[
        const Divider(),
        Text(context.l10n.statusSessionUsageSection),
        StatusDetailRow(label: context.l10n.statusInputTokensLabel, value: formatTokenCount(usage.promptTokens)),
        StatusDetailRow(label: context.l10n.statusOutputTokensLabel, value: formatTokenCount(usage.completionTokens)),
        StatusDetailRow(label: context.l10n.statusReasoningTokensLabel, value: formatTokenCount(usage.reasoningTokens)),
        StatusDetailRow(label: context.l10n.statusTotalTokensLabel, value: formatTokenCount(usage.totalTokens)),
        StatusDetailRow(label: context.l10n.statusInferenceCountLabel, value: '${usage.inferenceCount}'),
        StatusDetailRow(label: context.l10n.statusCacheLabel,
          value: usage.cacheUsage.hitRate == null ? '—' : '${(usage.cacheUsage.hitRate! * 100).toStringAsFixed(1)}%'),
        StatusDetailRow(label: context.l10n.statusCacheHitTokensLabel, value: formatTokenCount(usage.cacheUsage.cacheReadTokens)),
        StatusDetailRow(label: context.l10n.statusCacheWriteTokensLabel, value: formatTokenCount(usage.cacheWriteTokens)),
        if (usage.cacheUsage.hasIncompleteUsage || usage.hasIncompleteUsage) Text(context.l10n.statusUsageIncompleteLabel),
        if (usage.hasUnpricedUsage) Text(context.l10n.statusUnpricedUsageLabel),
      ],
      for (final cost in state.costs)
        StatusDetailRow(label: context.l10n.statusCostEstimateLabel,
          value: state.textOf(cost.currency) == null ? '—' : formatRuntimeCostAmount(state.textOf(cost.currency)!, cost.amount)),
      if (state.nextCostOffset != null) TextButton(onPressed: onLoadCosts,
        child: Text(context.l10n.timelineItemBodyLoad)),
      for (final saving in state.cacheSavings)
        StatusDetailRow(label: context.l10n.statusCacheSavingsLabel,
          value: state.textOf(saving.currency) == null ? '—' : formatRuntimeCostAmount(state.textOf(saving.currency)!, saving.amount)),
      if (state.nextSavingOffset != null) TextButton(onPressed: onLoadSavings,
        child: Text(context.l10n.timelineItemBodyLoad)),
      if (state.error != null) ...[
        Text(state.error!.message), TextButton(onPressed: onRetry, child: Text(context.l10n.sidebarRetry)),
      ],
    ]);
  }

  Widget _readText(BuildContext context, ReadText value) {
    final text = state.textOf(value);
    return text == null ? TextButton(onPressed: () => onLoadText((value as DeferredReadText).fieldId),
      child: Text(context.l10n.timelineItemBodyLoad)) : Text(text);
  }
}
