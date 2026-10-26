import 'package:anywork_client/statistics.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../ui/formatters/token_format.dart';
import '../../widgets/settings_layout.dart';
import '../../widgets/settings_resource_row.dart';
import 'statistics_format.dart';

/// Performance summary of every account model plus its reasoning-effort split.
///
/// Wide panes keep the real table; narrow panes keep one compact resource block
/// per account model: identity, the six group metrics and one line per effort
/// split.
class StatisticsSummaryView extends StatelessWidget {
  const StatisticsSummaryView({
    required this.summaries,
    required this.compact,
    required this.knownEmpty,
    super.key,
  });

  final List<PerformanceSummary> summaries;

  /// Below 760 the table becomes the compact blocks.
  final bool compact;

  /// A complete snapshot is the only proof that the summary is empty. Before
  /// the first publication the section shows the unknown placeholder instead.
  final bool knownEmpty;

  @override
  Widget build(BuildContext context) {
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
              style: context.text.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          )
        else if (compact)
          for (final summary in summaries) _CompactSummaryCard(summary: summary)
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                DataColumn(label: Text(context.l10n.statisticsModel)),
                DataColumn(label: Text(context.l10n.statisticsReasoningEffort)),
                DataColumn(label: Text(context.l10n.statisticsSpeed)),
                DataColumn(label: Text(context.l10n.statisticsSamples)),
                DataColumn(label: Text(context.l10n.statisticsOutputTokens)),
                DataColumn(label: Text(context.l10n.statisticsAverageTtft)),
                DataColumn(label: Text(context.l10n.statisticsAverageResponse)),
              ],
              rows: [
                for (final summary in summaries) ...[
                  DataRow(
                    cells: [
                      DataCell(
                        _ModelLabel(
                          key: StudioDriverKeys.statisticsSummaryRow(
                            summary.identity.accountId,
                            summary.identity.modelId,
                          ),
                          summary: summary,
                        ),
                      ),
                      DataCell(Text(context.l10n.statisticsGroupTotal)),
                      ..._cells(context, summary.counters),
                    ],
                  ),
                  for (final effort in summary.effortBreakdowns)
                    DataRow(
                      cells: [
                        // 行身份挂在真实渲染的单元格内容上：`DataRow.key` 由
                        // `Table` 消费，不进入元素树，无法作为可见身份。
                        DataCell(
                          KeyedSubtree(
                            key: StudioDriverKeys.statisticsSummaryEffortRow(
                              summary.identity.accountId,
                              summary.identity.modelId,
                              effort.identity.effort,
                            ),
                            child: const SizedBox.shrink(),
                          ),
                        ),
                        DataCell(
                          Text(
                            statisticsEffort(context, effort.identity.effort),
                          ),
                        ),
                        ..._cells(context, effort.counters),
                      ],
                    ),
                ],
              ],
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
}

class _CompactSummaryCard extends StatelessWidget {
  const _CompactSummaryCard({required this.summary});

  final PerformanceSummary summary;

  @override
  Widget build(BuildContext context) => SettingsResourceRow(
    key: StudioDriverKeys.statisticsSummaryRow(
      summary.identity.accountId,
      summary.identity.modelId,
    ),
    title: statisticsIdentity(context, summary.identity.modelId),
    subtitle:
        '${statisticsIdentity(context, summary.identity.accountDisplayName)}'
        ' · ${statisticsIdentity(context, summary.identity.accountId)}',
    children: [
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
          style: context.text.labelSmall?.copyWith(
            color: context.colors.onSurfaceVariant,
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
              style: context.text.bodySmall,
            ),
          ),
      ],
      const Divider(height: 24),
    ],
  );
}

class _ModelLabel extends StatelessWidget {
  const _ModelLabel({required this.summary, super.key});

  final PerformanceSummary summary;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        statisticsIdentity(context, summary.identity.modelId),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      Text(
        '${statisticsIdentity(context, summary.identity.accountDisplayName)}'
        ' · ${statisticsIdentity(context, summary.identity.accountId)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: context.colors.onSurfaceVariant),
      ),
    ],
  );
}

Widget _metric(BuildContext context, String label, String value) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  mainAxisSize: MainAxisSize.min,
  children: [
    Text(label, style: context.text.labelSmall),
    Text(value),
  ],
);
