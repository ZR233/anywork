import 'package:anywork_client/statistics.dart';
import 'package:anywork_client/models.dart' show formatTokenCount;
import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_driver_keys.dart';
import '../../settings_common.dart';
import 'statistics_formatters.dart';

class StatisticsSummarySection extends StatelessWidget {
  const StatisticsSummarySection({
    required this.compact,
    required this.summaries,
    required this.showEmptyState,
    super.key,
  });

  final bool compact;
  final List<StatisticsSummary> summaries;
  final bool showEmptyState;

  @override
  Widget build(BuildContext context) {
    return SettingsSectionPanel(
      key: StudioDriverKeys.statisticsSummary,
      title: context.l10n.settingsStatisticsSummaryTitle,
      children: [
        if (summaries.isEmpty && showEmptyState)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              context.l10n.settingsStatisticsSummaryEmpty,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: context.colors.onSurfaceVariant),
            ),
          )
        else if (summaries.isEmpty)
          const SizedBox.shrink()
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
                            summary.accountId,
                            summary.modelId,
                          ),
                          summary: summary,
                        ),
                      ),
                      DataCell(Text(context.l10n.statisticsGroupTotal)),
                      DataCell(
                        Text(
                          context.tokenThroughputLabel(summary.tokensPerSecond),
                        ),
                      ),
                      DataCell(Text('${summary.sampleCount}')),
                      DataCell(
                        Text(formatTokenCount(summary.completionTokens)),
                      ),
                      DataCell(
                        Text(
                          formatStatisticsAverageTtft(
                            context,
                            summary.averageTtftMillis,
                            summary.ttftSampleCount,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          formatStatisticsMillis(summary.averageResponseMillis),
                        ),
                      ),
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
                              summary.accountId,
                              summary.modelId,
                              effort.effort,
                            ),
                            child: const SizedBox.shrink(),
                          ),
                        ),
                        DataCell(
                          Text(
                            formatStatisticsReasoningEffort(
                              context,
                              effort.effort,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            context.tokenThroughputLabel(
                              effort.tokensPerSecond,
                            ),
                          ),
                        ),
                        DataCell(Text('${effort.sampleCount}')),
                        DataCell(
                          Text(formatTokenCount(effort.completionTokens)),
                        ),
                        DataCell(
                          Text(
                            formatStatisticsAverageTtft(
                              context,
                              effort.averageTtftMillis,
                              effort.ttftSampleCount,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            formatStatisticsMillis(
                              effort.averageResponseMillis,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _CompactSummaryCard extends StatelessWidget {
  const _CompactSummaryCard({required this.summary});

  final StatisticsSummary summary;

  @override
  Widget build(BuildContext context) => SettingsResourceRow(
    key: StudioDriverKeys.statisticsSummaryRow(
      summary.accountId,
      summary.modelId,
    ),
    title: statisticsIdentityLabel(context, summary.modelId),
    subtitle:
        '${statisticsIdentityLabel(context, summary.accountDisplayName)} · ${statisticsIdentityLabel(context, summary.accountId)}',
    children: [
      Wrap(
        spacing: 16,
        runSpacing: 8,
        children: [
          SettingsMetric(
            context.l10n.statisticsReasoningEffort,
            context.l10n.statisticsGroupTotal,
          ),
          SettingsMetric(
            context.l10n.statisticsSpeed,
            context.tokenThroughputLabel(summary.tokensPerSecond),
          ),
          SettingsMetric(
            context.l10n.statisticsSamples,
            '${summary.sampleCount}',
          ),
          SettingsMetric(
            context.l10n.statisticsOutputTokens,
            formatTokenCount(summary.completionTokens),
          ),
          SettingsMetric(
            context.l10n.statisticsAverageTtft,
            formatStatisticsAverageTtft(
              context,
              summary.averageTtftMillis,
              summary.ttftSampleCount,
            ),
          ),
          SettingsMetric(
            context.l10n.statisticsAverageResponse,
            formatStatisticsMillis(summary.averageResponseMillis),
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
              summary.accountId,
              summary.modelId,
              effort.effort,
            ),
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${formatStatisticsReasoningEffort(context, effort.effort)} · '
              '${context.tokenThroughputLabel(effort.tokensPerSecond)} · '
              '${context.l10n.statisticsSamples} ${effort.sampleCount}',
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

  final StatisticsSummary summary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          statisticsIdentityLabel(context, summary.modelId),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          '${statisticsIdentityLabel(context, summary.accountDisplayName)} · ${statisticsIdentityLabel(context, summary.accountId)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: context.colors.onSurfaceVariant),
        ),
      ],
    );
  }
}
