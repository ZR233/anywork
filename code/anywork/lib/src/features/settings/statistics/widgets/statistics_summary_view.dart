import 'package:anywork_client/account_usage.dart';
import 'package:flutter/material.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../widgets/settings_layout.dart';
import '../../../../ui/formatters/token_format.dart';
import 'statistics_format.dart';

/// Performance summary of every account model plus its reasoning-effort split.
///
/// Wide panes keep the real table; narrow panes collapse each account model into
/// one compact resource block: identity, the six group metrics and one single
/// line per effort split. The compact block stays short enough that the history
/// filters below remain on the first screen without scrolling.
class StatisticsSummaryView extends StatelessWidget {
  const StatisticsSummaryView({
    required this.summaries,
    required this.knownEmpty,
    super.key,
  });

  final List<PerformanceSummary> summaries;
  final bool knownEmpty;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SettingsSectionPanel(
      key: StudioDriverKeys.statisticsSummary,
      title: context.l10n.settingsStatisticsSummaryTitle,
      children: [
        if (summaries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              knownEmpty
                  ? context.l10n.settingsStatisticsSummaryEmpty
                  : statisticsIdentity(context, null),
              style: text.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth < 760
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final summary in summaries)
                        _compactBlock(context, summary),
                    ],
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: [
                        DataColumn(label: Text(context.l10n.statisticsModel)),
                        DataColumn(
                          label: Text(context.l10n.statisticsReasoningEffort),
                        ),
                        DataColumn(label: Text(context.l10n.statisticsSpeed)),
                        DataColumn(label: Text(context.l10n.statisticsSamples)),
                        DataColumn(
                          label: Text(context.l10n.statisticsOutputTokens),
                        ),
                        DataColumn(
                          label: Text(context.l10n.statisticsAverageTtft),
                        ),
                        DataColumn(
                          label: Text(context.l10n.statisticsAverageResponse),
                        ),
                      ],
                      rows: [
                        for (final summary in summaries) ...[
                          DataRow(
                            cells: [
                              DataCell(_identity(context, summary)),
                              DataCell(Text(context.l10n.statisticsGroupTotal)),
                              ..._cells(context, summary.counters),
                            ],
                          ),
                          for (final effort in summary.effortBreakdowns)
                            DataRow(
                              cells: [
                                // Row identity rides on the rendered cell: a
                                // `DataRow.key` is consumed by `Table` and never
                                // enters the element tree.
                                DataCell(
                                  KeyedSubtree(
                                    key:
                                        StudioDriverKeys.statisticsSummaryEffortRow(
                                          summary.identity.accountId,
                                          summary.identity.modelId,
                                          effort.identity.effort,
                                        ),
                                    child: const SizedBox.shrink(),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    statisticsEffort(
                                      context,
                                      effort.identity.effort,
                                    ),
                                  ),
                                ),
                                ..._cells(context, effort.counters),
                              ],
                            ),
                        ],
                      ],
                    ),
                  ),
          ),
      ],
    );
  }

  /// Wide-pane identity cell: `(accountId, modelId)` is the row identity.
  Widget _identity(BuildContext context, PerformanceSummary summary) {
    final text = Theme.of(context).textTheme;
    return Column(
      key: StudioDriverKeys.statisticsSummaryRow(
        summary.identity.accountId,
        summary.identity.modelId,
      ),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(statisticsIdentity(context, summary.identity.modelId)),
        Text(
          '${statisticsIdentity(context, summary.identity.accountDisplayName)}'
          ' · ${statisticsIdentity(context, summary.identity.accountId)}',
          style: text.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  List<DataCell> _cells(BuildContext context, PerformanceCounters counters) => [
    DataCell(Text(context.tokenThroughputLabel(counters.tokensPerSecond))),
    DataCell(Text('${counters.sampleCount}')),
    DataCell(Text(formatTokenCount(counters.completionTokens))),
    DataCell(Text(statisticsAverageTtft(context, counters))),
    DataCell(Text(statisticsMillis(counters.averageResponseMillis))),
  ];

  /// Narrow-pane block: the same facts as one table row, in a fixed height.
  Widget _compactBlock(BuildContext context, PerformanceSummary summary) {
    final text = Theme.of(context).textTheme;
    final variant = text.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Padding(
      key: StudioDriverKeys.statisticsSummaryRow(
        summary.identity.accountId,
        summary.identity.modelId,
      ),
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            statisticsIdentity(context, summary.identity.modelId),
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '${statisticsIdentity(context, summary.identity.accountDisplayName)}'
            ' · ${statisticsIdentity(context, summary.identity.accountId)}',
            style: variant,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _metric(
                context,
                context.l10n.statisticsReasoningEffort,
                context.l10n.statisticsGroupTotal,
              ),
              _metric(
                context,
                context.l10n.statisticsSpeed,
                context.tokenThroughputLabel(summary.counters.tokensPerSecond),
              ),
              _metric(
                context,
                context.l10n.statisticsSamples,
                '${summary.counters.sampleCount}',
              ),
              _metric(
                context,
                context.l10n.statisticsOutputTokens,
                formatTokenCount(summary.counters.completionTokens),
              ),
              _metric(
                context,
                context.l10n.statisticsAverageTtft,
                statisticsAverageTtft(context, summary.counters),
              ),
              _metric(
                context,
                context.l10n.statisticsAverageResponse,
                statisticsMillis(summary.counters.averageResponseMillis),
              ),
            ],
          ),
          if (summary.effortBreakdowns.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              context.l10n.statisticsEffortBreakdownTitle,
              style: text.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            for (final effort in summary.effortBreakdowns)
              Padding(
                key: StudioDriverKeys.statisticsSummaryEffortRow(
                  summary.identity.accountId,
                  summary.identity.modelId,
                  effort.identity.effort,
                ),
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${statisticsEffort(context, effort.identity.effort)} · '
                  '${context.tokenThroughputLabel(effort.counters.tokensPerSecond)}'
                  ' · ${context.l10n.statisticsSamples} '
                  '${effort.counters.sampleCount}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall,
                ),
              ),
          ],
          const Divider(height: 24),
        ],
      ),
    );
  }

  Widget _metric(BuildContext context, String label, String value) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: text.labelSmall),
        Text(value, style: text.bodyMedium),
      ],
    );
  }
}
