import 'package:anywork_client/account_usage.dart';
import 'package:flutter/material.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../ui/formatters/token_format.dart';
import 'statistics_format.dart';

class StatisticsSummaryView extends StatelessWidget {
  const StatisticsSummaryView({required this.summaries, required this.knownEmpty,
    required this.hasMore, required this.reading, required this.onMore, super.key});
  final List<PerformanceSummary> summaries;
  final bool knownEmpty;
  final bool hasMore;
  final bool reading;
  final VoidCallback onMore;
  @override
  Widget build(BuildContext context) => Column(key: StudioDriverKeys.statisticsSummary,
    crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(context.l10n.settingsStatisticsSummaryTitle, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      if (summaries.isEmpty) Text(knownEmpty ? context.l10n.settingsStatisticsSummaryEmpty : '—')
      else LayoutBuilder(builder: (context, constraints) => constraints.maxWidth < 760
        ? Column(children: [for (final summary in summaries) _card(context, summary)])
        : SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(
          columns: [
            DataColumn(label: Text(context.l10n.statisticsModel)),
            DataColumn(label: Text(context.l10n.statisticsReasoningEffort)),
            DataColumn(label: Text(context.l10n.statisticsSpeed)),
            DataColumn(label: Text(context.l10n.statisticsSamples)),
            DataColumn(label: Text(context.l10n.statisticsOutputTokens)),
            DataColumn(label: Text(context.l10n.statisticsAverageTtft)),
            DataColumn(label: Text(context.l10n.statisticsAverageResponse)),
          ], rows: [for (final summary in summaries) ...[
            DataRow(cells: [
              DataCell(_identity(context, summary)),
              DataCell(Text(context.l10n.statisticsGroupTotal)), ..._cells(context, summary.counters),
            ]),
            for (final effort in summary.effortBreakdowns) DataRow(cells: [
              DataCell(SizedBox.shrink(key: StudioDriverKeys.statisticsSummaryEffortRow(
                summary.identity.accountId, summary.identity.modelId, effort.identity.effort))),
              DataCell(Text(statisticsEffort(context, effort.identity.effort))), ..._cells(context, effort.counters),
            ]),
          ]]))),
      if (hasMore) Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: reading ? null : onMore,
        child: Text(context.l10n.settingsSshNextPage))),
    ]);
  Widget _identity(BuildContext context, PerformanceSummary summary) => Column(
    key: StudioDriverKeys.statisticsSummaryRow(summary.identity.accountId, summary.identity.modelId),
    crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(statisticsIdentity(context, summary.identity.modelId)),
      Text('${statisticsIdentity(context, summary.identity.accountDisplayName)} · ${statisticsIdentity(context, summary.identity.accountId)}',
        style: Theme.of(context).textTheme.labelSmall),
    ]);
  List<DataCell> _cells(BuildContext context, PerformanceCounters counters) => [
    DataCell(Text(context.tokenThroughputLabel(counters.tokensPerSecond))), DataCell(Text('${counters.sampleCount}')),
    DataCell(Text(formatTokenCount(counters.completionTokens))), DataCell(Text(statisticsAverageTtft(context, counters))),
    DataCell(Text(statisticsMillis(counters.averageResponseMillis))),
  ];
  Widget _card(BuildContext context, PerformanceSummary summary) => Card(child: Padding(
    padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _identity(context, summary), const SizedBox(height: 8),
      Text(context.l10n.statisticsGroupTotal, style: Theme.of(context).textTheme.labelSmall),
      _metrics(context, summary.counters),
      for (final effort in summary.effortBreakdowns) Padding(
        key: StudioDriverKeys.statisticsSummaryEffortRow(summary.identity.accountId, summary.identity.modelId, effort.identity.effort),
        padding: const EdgeInsets.only(top: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(statisticsEffort(context, effort.identity.effort)), _metrics(context, effort.counters),
        ])),
    ])));
  Widget _metrics(BuildContext context, PerformanceCounters counters) => Wrap(spacing: 18, runSpacing: 8, children: [
    _metric(context, context.l10n.statisticsSpeed, context.tokenThroughputLabel(counters.tokensPerSecond)),
    _metric(context, context.l10n.statisticsSamples, '${counters.sampleCount}'),
    _metric(context, context.l10n.statisticsOutputTokens, formatTokenCount(counters.completionTokens)),
    _metric(context, context.l10n.statisticsAverageTtft, statisticsAverageTtft(context, counters)),
    _metric(context, context.l10n.statisticsAverageResponse, statisticsMillis(counters.averageResponseMillis)),
  ]);
  Widget _metric(BuildContext context, String title, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min, children: [Text(title, style: Theme.of(context).textTheme.labelSmall), Text(value)]);
}
