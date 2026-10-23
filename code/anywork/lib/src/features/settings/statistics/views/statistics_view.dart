import 'package:anywork_client/account_usage.dart';
import 'package:flutter/material.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../widgets/settings_pane.dart';
import '../state/statistics_view_state.dart';
import '../widgets/statistics_format.dart';
import '../widgets/statistics_history_row.dart';
import '../widgets/statistics_summary_view.dart';

class StatisticsView extends StatelessWidget {
  const StatisticsView({required this.state, required this.summaries, required this.history,
    required this.modelOptions, required this.effortOptions, required this.errors,
    required this.summaryKnownEmpty, required this.historyKnownEmpty, required this.hasMoreSummaries,
    required this.hasMoreHistory, required this.hasHistory, required this.pending, required this.gap,
    required this.readFailed, required this.summaryProvenance, required this.historyProvenance,
    required this.onModel, required this.onEffort, required this.onMismatch,
    required this.onRead, super.key});
  final StatisticsViewState state;
  final List<PerformanceSummary> summaries;
  final List<PerformanceSample> history;
  final List<StatisticsModelOption> modelOptions;
  final List<StatisticsEffortFilter> effortOptions;
  final List<String> errors;
  final bool summaryKnownEmpty;
  final bool historyKnownEmpty;
  final bool hasMoreSummaries;
  final bool hasMoreHistory;
  final bool hasHistory;
  final bool pending;
  final bool gap;
  final bool readFailed;
  final String? summaryProvenance;
  final String? historyProvenance;
  final ValueChanged<StatisticsModelKey?> onModel;
  final ValueChanged<StatisticsEffortFilter?> onEffort;
  final ValueChanged<bool> onMismatch;
  final ValueChanged<StatisticsReadField> onRead;

  @override
  Widget build(BuildContext context) => SettingsPane(title: context.l10n.settingsStatisticsTitle,
    subtitle: context.l10n.settingsStatisticsSubtitle,
    toolbar: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // statisticsPending deliberately has no visible row, badge or spinner.
      if (readFailed) Text(context.l10n.settingsStatisticsReadFailedTitle, key: const ValueKey('statistics-status-read-failed'),
        style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (gap) Text(context.l10n.settingsStatisticsGapTitle, key: const ValueKey('statistics-status-gap')),
      for (final error in errors) SelectableText(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (errors.isNotEmpty || readFailed || gap) Wrap(children: [for (final field in StatisticsReadField.values)
        TextButton(onPressed: state.reading.contains(field) ? null : () => onRead(field),
          child: Text('${context.l10n.runtimeFatalRetry} · ${field == StatisticsReadField.summaries
            ? context.l10n.settingsStatisticsSummaryTitle : context.l10n.settingsStatisticsHistoryTitle}'))]),
    ]), child: LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < 760;
      final filtered = state.modelFilter != null || state.effortFilter != null || state.mismatchesOnly;
      final showEmpty = filtered || hasHistory || historyKnownEmpty && !pending && !gap && !readFailed;
      return CustomScrollView(key: StudioDriverKeys.statisticsHistory, slivers: [
        if (summaryProvenance != null) SliverToBoxAdapter(child: Text(summaryProvenance!, style: Theme.of(context).textTheme.bodySmall)),
        SliverToBoxAdapter(child: StatisticsSummaryView(summaries: summaries, knownEmpty: summaryKnownEmpty && !pending && !gap && !readFailed,
          hasMore: hasMoreSummaries, reading: state.reading.contains(StatisticsReadField.summaries),
          onMore: () => onRead(StatisticsReadField.summaries))),
        SliverPadding(padding: const EdgeInsets.symmetric(vertical: 20), sliver: SliverToBoxAdapter(child: _filters(context, constraints.maxWidth))),
        if (historyProvenance != null) SliverToBoxAdapter(child: Text(historyProvenance!, style: Theme.of(context).textTheme.bodySmall)),
        if (history.isEmpty && showEmpty) SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(vertical: 40),
          child: Center(child: Text(state.mismatchesOnly ? context.l10n.settingsStatisticsMismatchEmpty
            : filtered || hasHistory ? context.l10n.settingsStatisticsFilteredEmpty : context.l10n.settingsStatisticsEmpty))))
        else if (history.isNotEmpty) ...[
          if (!compact) SliverToBoxAdapter(child: _wideHeader(context)),
          SliverList.builder(itemCount: history.length, itemBuilder: (context, index) {
            final sample = history[index];
            return StatisticsHistoryRow(key: StudioDriverKeys.statisticsHistoryRow(sample.identity.accountId,
              sample.identity.modelId ?? '', sample.identity.effort, index), sample: sample, compact: compact);
          }),
        ],
        if (hasMoreHistory) SliverToBoxAdapter(child: Align(alignment: Alignment.centerLeft,
          child: TextButton(onPressed: state.reading.contains(StatisticsReadField.history) ? null : () => onRead(StatisticsReadField.history),
            child: Text(context.l10n.settingsSshNextPage)))),
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(vertical: 20),
          child: Text(context.l10n.settingsStatisticsThroughputNote, style: Theme.of(context).textTheme.bodySmall))),
      ]);
    }));
  Widget _filters(BuildContext context, double maxWidth) {
    final width = maxWidth < 240 ? maxWidth : 240.0;
    return Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Text(context.l10n.settingsStatisticsHistoryTitle, style: Theme.of(context).textTheme.titleMedium),
      Row(mainAxisSize: MainAxisSize.min, children: [
        Checkbox(key: StudioDriverKeys.statisticsMismatchOnly, value: state.mismatchesOnly,
          onChanged: (value) { if (value != null) onMismatch(value); }), Text(context.l10n.settingsStatisticsMismatchesOnly),
      ]),
      SizedBox(key: StudioDriverKeys.statisticsFilter, width: width, child: DropdownMenu<StatisticsModelKey?>(
        initialSelection: state.modelFilter, hintText: context.l10n.settingsStatisticsAllModels, expandedInsets: EdgeInsets.zero,
        dropdownMenuEntries: [
          DropdownMenuEntry(value: null, label: context.l10n.settingsStatisticsAllModels),
          for (final option in modelOptions) DropdownMenuEntry(value: option.key,
            label: '${statisticsIdentity(context, option.accountDisplayName)} · ${statisticsIdentity(context, option.key.accountId)} · ${statisticsIdentity(context, option.displayModel)}'),
          if (state.modelFilter case final selected?) if (!modelOptions.any((option) => option.key == selected))
            DropdownMenuEntry(value: selected, label: '${selected.accountId} · ${statisticsIdentity(context, selected.modelId)}'),
        ], onSelected: onModel)),
      SizedBox(key: StudioDriverKeys.statisticsEffortFilter, width: width, child: DropdownMenu<StatisticsEffortFilter?>(
        initialSelection: state.effortFilter, hintText: context.l10n.statisticsAllEfforts, expandedInsets: EdgeInsets.zero,
        dropdownMenuEntries: [
          DropdownMenuEntry(value: null, label: context.l10n.statisticsAllEfforts),
          for (final effort in effortOptions) DropdownMenuEntry(value: effort, label: statisticsEffort(context, effort.value)),
          if (state.effortFilter case final selected?) if (!effortOptions.contains(selected))
            DropdownMenuEntry(value: selected, label: statisticsEffort(context, selected.value)),
        ], onSelected: onEffort)),
    ]);
  }
  Widget _wideHeader(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    child: Row(children: [
      for (final (index, label) in [context.l10n.statisticsCompletedAt, context.l10n.statisticsHistoryModelHeader,
        context.l10n.statisticsReasoningEffort, context.l10n.statisticsOutputTokens, 'TTFT', context.l10n.statisticsDecode,
        context.l10n.statisticsTotalResponse, context.l10n.statisticsSpeed].indexed)
        Expanded(flex: index == 1 ? 2 : 1, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelMedium)),
    ]));
}
