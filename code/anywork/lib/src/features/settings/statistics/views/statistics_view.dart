import 'package:anywork_client/account_usage.dart';
import 'package:flutter/material.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../widgets/settings_layout.dart';
import '../../accounts/widgets/auto_page_loader.dart';
import '../state/statistics_view_state.dart';
import '../widgets/statistics_format.dart';
import '../widgets/statistics_history_row.dart';
import '../widgets/statistics_summary_view.dart';

class StatisticsView extends StatelessWidget {
  const StatisticsView({
    required this.state,
    required this.summaries,
    required this.history,
    required this.modelOptions,
    required this.effortOptions,
    required this.summaryKnownEmpty,
    required this.historyKnownEmpty,
    required this.hasMoreSummaries,
    required this.hasMoreHistory,
    required this.hasHistory,
    required this.pending,
    required this.gap,
    required this.readFailed,
    required this.onModel,
    required this.onEffort,
    required this.onMismatch,
    required this.onRead,
    super.key,
  });
  final StatisticsViewState state;
  final List<PerformanceSummary> summaries;
  final List<PerformanceSample> history;
  final List<StatisticsModelOption> modelOptions;
  final List<StatisticsEffortFilter> effortOptions;
  final bool summaryKnownEmpty;
  final bool historyKnownEmpty;
  final bool hasMoreSummaries;
  final bool hasMoreHistory;
  final bool hasHistory;
  final bool pending;
  final bool gap;
  final bool readFailed;
  final ValueChanged<StatisticsModelKey?> onModel;
  final ValueChanged<StatisticsEffortFilter?> onEffort;
  final ValueChanged<bool> onMismatch;
  final ValueChanged<StatisticsReadField> onRead;

  @override
  Widget build(BuildContext context) {
    return AutoPageLoader(
      hasMore: hasMoreSummaries,
      loading: state.reading.contains(StatisticsReadField.summaries),
      blocked: state.readIssues.containsKey(StatisticsReadField.summaries),
      requestedCount: summaries.length,
      onLoadMore: () => onRead(StatisticsReadField.summaries),
      child: AutoPageLoader(
        hasMore: hasMoreHistory,
        loading: state.reading.contains(StatisticsReadField.history),
        blocked: state.readIssues.containsKey(StatisticsReadField.history),
        requestedCount: history.length,
        onLoadMore: () => onRead(StatisticsReadField.history),
        child: SettingsPageLayout(
          maxWidth: 1120,
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsHeader(
                title: context.l10n.settingsStatisticsTitle,
                subtitle: context.l10n.settingsStatisticsSubtitle,
              ),
              // gap/readFailed stay in the fixed heading as a light status line and
              // never push the body down.
              if (gap || readFailed)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _StatisticsStatusLine(
                    readFailed: readFailed,
                    gap: gap,
                  ),
                ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 760;
              final filtered =
                  state.modelFilter != null ||
                  state.effortFilter != null ||
                  state.mismatchesOnly;
              final showEmpty =
                  filtered ||
                  hasHistory ||
                  historyKnownEmpty && !pending && !gap && !readFailed;
              return CustomScrollView(
                key: StudioDriverKeys.statisticsHistory,
                slivers: [
                  SliverToBoxAdapter(
                    child: StatisticsSummaryView(
                      summaries: summaries,
                      knownEmpty:
                          summaryKnownEmpty && !pending && !gap && !readFailed,
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    sliver: SliverToBoxAdapter(
                      child: _filters(context, constraints.maxWidth),
                    ),
                  ),
                  if (history.isEmpty && showEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Text(
                            state.mismatchesOnly
                                ? context.l10n.settingsStatisticsMismatchEmpty
                                : filtered || hasHistory
                                ? context.l10n.settingsStatisticsFilteredEmpty
                                : context.l10n.settingsStatisticsEmpty,
                          ),
                        ),
                      ),
                    )
                  else if (history.isNotEmpty) ...[
                    if (!compact)
                      SliverToBoxAdapter(child: _wideHeader(context)),
                    // The loaded history page is bounded, so rows are materialised
                    // eagerly: every keyed row stays addressable regardless of the
                    // viewport height, with no change in order or appearance.
                    SliverToBoxAdapter(
                      child: Column(
                        children: [
                          for (var index = 0; index < history.length; index++)
                            StatisticsHistoryRow(
                              key: StudioDriverKeys.statisticsHistoryRow(
                                history[index].identity.accountId,
                                history[index].identity.modelId ?? '',
                                history[index].identity.effort,
                                index,
                              ),
                              sample: history[index],
                              compact: compact,
                            ),
                        ],
                      ),
                    ),
                  ],
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        context.l10n.settingsStatisticsThroughputNote,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _filters(BuildContext context, double maxWidth) {
    final width = maxWidth < 240 ? maxWidth : 240.0;
    final title = Text(
      context.l10n.settingsStatisticsHistoryTitle,
      style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(fontWeight: FontWeight.w600),
    );
    final mismatchesOnly = InkWell(
      onTap: () => onMismatch(!state.mismatchesOnly),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              key: StudioDriverKeys.statisticsMismatchOnly,
              value: state.mismatchesOnly,
              visualDensity: VisualDensity.compact,
              onChanged: (value) => onMismatch(value ?? false),
            ),
            Flexible(
              child: Text(
                context.l10n.settingsStatisticsMismatchesOnly,
                maxLines: 2,
              ),
            ),
          ],
        ),
      ),
    );
    final model = SizedBox(
      key: StudioDriverKeys.statisticsFilter,
      width: width,
      child: DropdownMenu<StatisticsModelKey?>(
        initialSelection: state.modelFilter,
        hintText: context.l10n.settingsStatisticsAllModels,
        expandedInsets: EdgeInsets.zero,
        dropdownMenuEntries: [
          DropdownMenuEntry(
            value: null,
            label: context.l10n.settingsStatisticsAllModels,
          ),
          for (final option in modelOptions)
            DropdownMenuEntry(
              value: option.key,
              label:
                  '${statisticsIdentity(context, option.accountDisplayName)} · ${statisticsIdentity(context, option.key.accountId)} · ${statisticsIdentity(context, option.displayModel)}',
            ),
          if (state.modelFilter case final selected?)
            if (!modelOptions.any((option) => option.key == selected))
              DropdownMenuEntry(
                value: selected,
                label:
                    '${selected.accountId} · ${statisticsIdentity(context, selected.modelId)}',
              ),
        ],
        onSelected: onModel,
      ),
    );
    final effort = SizedBox(
      key: StudioDriverKeys.statisticsEffortFilter,
      width: width,
      child: DropdownMenu<StatisticsEffortFilter?>(
        initialSelection: state.effortFilter,
        hintText: context.l10n.statisticsAllEfforts,
        expandedInsets: EdgeInsets.zero,
        dropdownMenuEntries: [
          DropdownMenuEntry(
            value: null,
            label: context.l10n.statisticsAllEfforts,
          ),
          for (final effort in effortOptions)
            DropdownMenuEntry(
              value: effort,
              label: statisticsEffort(context, effort.value),
            ),
          if (state.effortFilter case final selected?)
            if (!effortOptions.contains(selected))
              DropdownMenuEntry(
                value: selected,
                label: statisticsEffort(context, selected.value),
              ),
        ],
        onSelected: onEffort,
      ),
    );
    // The title, the mismatch toggle and both filters keep their own width and
    // wrap as a group; nothing hides or compresses on narrow windows.
    // Filters never hide or shrink below their content: below the wrap
    // threshold the whole group falls to the next line, and on a real desktop
    // row the two width-capped dropdowns share the leftover width.
    if (maxWidth < 620) {
      return Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [title, mismatchesOnly, model, effort],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        title,
        mismatchesOnly,
        Flexible(child: model),
        Flexible(child: effort),
      ],
    );
  }

  Widget _wideHeader(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    child: Row(
      children: [
        for (final (index, label) in [
          context.l10n.statisticsCompletedAt,
          context.l10n.statisticsHistoryModelHeader,
          context.l10n.statisticsReasoningEffort,
          context.l10n.statisticsOutputTokens,
          'TTFT',
          context.l10n.statisticsDecode,
          context.l10n.statisticsTotalResponse,
          context.l10n.statisticsSpeed,
        ].indexed)
          Expanded(
            flex: index == 1 ? 2 : 1,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
      ],
    ),
  );
}

/// Light status line of the fixed heading: a failure and a projection gap read
/// as inline items with their established identities.
class _StatisticsStatusLine extends StatelessWidget {
  const _StatisticsStatusLine({required this.readFailed, required this.gap});

  final bool readFailed;
  final bool gap;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      if (readFailed)
        _StatisticsStatusItem(
          key: const ValueKey('statistics-status-read-failed'),
          icon: Icons.error_outline,
          label: context.l10n.settingsStatisticsReadFailedTitle,
          color: Theme.of(context).colorScheme.error,
        ),
      if (gap)
        _StatisticsStatusItem(
          key: const ValueKey('statistics-status-gap'),
          icon: Icons.warning_amber_rounded,
          label: context.l10n.settingsStatisticsGapTitle,
          color: context.statusColors.warning,
        ),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 16, runSpacing: 4, children: items);
  }
}

class _StatisticsStatusItem extends StatelessWidget {
  const _StatisticsStatusItem({
    required this.icon,
    required this.label,
    required this.color,
    super.key,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 15, color: color),
      const SizedBox(width: 6),
      Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
      ),
    ],
  );
}
