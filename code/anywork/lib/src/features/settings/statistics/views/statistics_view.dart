import 'package:anywork_client/statistics.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_driver_keys.dart';
import '../../settings_common.dart';
import '../state/statistics_filter_options.dart';
import '../state/statistics_view_state.dart';
import '../widgets/statistics_history_widgets.dart';
import '../widgets/statistics_status_widgets.dart';
import '../widgets/statistics_summary_widgets.dart';

/// Pure paged statistics presentation; the owner supplies data and user actions.
class StatisticsView extends StatefulWidget {
  const StatisticsView({
    required this.state,
    required this.visible,
    required this.onModelChanged,
    required this.onEffortChanged,
    this.onServiceTierChanged,
    required this.onMismatchesOnlyChanged,
    required this.onRefresh,
    required this.onSectionChanged,
    required this.onPageChanged,
    super.key,
  });

  final StatisticsViewState state;
  final bool visible;
  final ValueChanged<String?> onModelChanged;
  final ValueChanged<String?> onEffortChanged;
  final ValueChanged<String?>? onServiceTierChanged;
  final ValueChanged<bool> onMismatchesOnlyChanged;
  final VoidCallback onRefresh;
  final ValueChanged<StatisticsSection> onSectionChanged;
  final ValueChanged<int> onPageChanged;

  @override
  State<StatisticsView> createState() => _StatisticsViewState();
}

class _StatisticsViewState extends State<StatisticsView> {
  final _scroll = ScrollController();
  List<StatisticsSample>? _optionsHistory;
  List<StatisticsSummary>? _optionsSummaries;
  late StatisticsFilterOptions _options;

  @override
  void didUpdateWidget(covariant StatisticsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.state;
    final after = widget.state;
    if (before.section != after.section ||
        before.pageIndex != after.pageIndex ||
        before.modelFilter != after.modelFilter ||
        before.effortFilter != after.effortFilter ||
        before.serviceTierFilter != after.serviceTierFilter ||
        before.mismatchesOnly != after.mismatchesOnly) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final snapshot = state.snapshot;
    final sourceHistory = snapshot?.history ?? const <StatisticsSample>[];
    final summaries = snapshot?.summaries ?? const <StatisticsSummary>[];
    if (!identical(_optionsHistory, sourceHistory) ||
        !identical(_optionsSummaries, summaries)) {
      _options = StatisticsFilterOptions.fromMaterials(
        sourceHistory,
        summaries,
      );
      _optionsHistory = sourceHistory;
      _optionsSummaries = summaries;
    }
    final isHistory = state.section == StatisticsSection.history;
    final pageHistory = state.pageHistory;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        return SettingsPageLayout(
          maxWidth: 1320,
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.settingsStatisticsTitle,
                      style: context.text.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    key: StudioDriverKeys.statisticsRefresh,
                    onPressed: widget.visible && !state.isRefreshing
                        ? widget.onRefresh
                        : null,
                    icon: state.isRefreshing
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 18),
                    label: Text(
                      state.isRefreshing
                          ? context.l10n.statisticsRefreshing
                          : context.l10n.statisticsRefresh,
                    ),
                  ),
                ],
              ),
              if (widget.visible &&
                  snapshot != null &&
                  (snapshot.statisticsGap || snapshot.readFailed))
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: StatisticsStatusLine(snapshot: snapshot),
                ),
              if (widget.visible)
                StatisticsConnectionStatus(
                  state: state.connection,
                  onRefresh: widget.onRefresh,
                ),
            ],
          ),
          toolbar: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<StatisticsSection>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: StatisticsSection.summaries,
                      label: Text(context.l10n.settingsStatisticsSummaryTitle),
                    ),
                    ButtonSegment(
                      value: StatisticsSection.history,
                      label: Text(context.l10n.settingsStatisticsHistoryTitle),
                    ),
                  ],
                  selected: {state.section},
                  onSelectionChanged: (values) =>
                      widget.onSectionChanged(values.single),
                ),
              ),
              if (isHistory) ...[
                const SizedBox(height: 18),
                StatisticsHistoryHeader(
                  options: _options,
                  value: state.modelFilter,
                  onChanged: widget.onModelChanged,
                  effortValue: state.effortFilter,
                  onEffortChanged: widget.onEffortChanged,
                  serviceTierValue: state.serviceTierFilter,
                  onServiceTierChanged: widget.onServiceTierChanged,
                  mismatchesOnly: state.mismatchesOnly,
                  onMismatchesOnlyChanged: widget.onMismatchesOnlyChanged,
                ),
              ],
            ],
          ),
          footer: _StatisticsPagination(
            state: state,
            onPageChanged: widget.onPageChanged,
          ),
          child: CustomScrollView(
            key: StudioDriverKeys.statisticsHistory,
            controller: _scroll,
            slivers: [
              if (!isHistory)
                SliverToBoxAdapter(
                  child: StatisticsSummarySection(
                    compact: compact,
                    summaries: state.pageSummaries,
                    showEmptyState: snapshot != null && !state.isRefreshing,
                  ),
                )
              else if (state.filteredHistory.isEmpty) ...[
                if (snapshot != null &&
                    !(sourceHistory.isEmpty &&
                        (snapshot.statisticsPending ||
                            snapshot.readFailed ||
                            snapshot.statisticsGap ||
                            state.isRefreshing)))
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: StatisticsEmptyState(
                        label: sourceHistory.isEmpty
                            ? context.l10n.settingsStatisticsEmpty
                            : state.mismatchesOnly
                            ? context.l10n.settingsStatisticsMismatchEmpty
                            : context.l10n.settingsStatisticsFilteredEmpty,
                      ),
                    ),
                  ),
              ] else ...[
                if (!compact)
                  const SliverToBoxAdapter(
                    child: StatisticsWideHistoryHeader(),
                  ),
                SliverList.builder(
                  itemCount: pageHistory.length,
                  itemBuilder: (context, index) {
                    final sample = pageHistory[index];
                    final key = StudioDriverKeys.statisticsHistoryCall(
                      sample.callKey,
                    );
                    return compact
                        ? StatisticsCompactHistoryCard(key: key, sample: sample)
                        : StatisticsWideHistoryRow(key: key, sample: sample);
                  },
                ),
              ],
              if (snapshot == null && state.isRefreshing)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ],
          ),
        );
      },
    );
  }
}

class _StatisticsPagination extends StatelessWidget {
  const _StatisticsPagination({
    required this.state,
    required this.onPageChanged,
  });

  final StatisticsViewState state;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 16,
    runSpacing: 8,
    children: [
      Text(
        context.l10n.statisticsItemRange(
          state.firstItem,
          state.lastItem,
          state.itemCount,
        ),
        style: context.text.bodySmall?.copyWith(
          color: context.colors.onSurfaceVariant,
        ),
      ),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: StudioDriverKeys.statisticsPreviousPage,
            tooltip: context.l10n.statisticsPreviousPage,
            onPressed: state.pageIndex > 0
                ? () => onPageChanged(state.pageIndex - 1)
                : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              context.l10n.statisticsPageNumber(
                state.itemCount == 0 ? 0 : state.pageIndex + 1,
                state.itemCount == 0 ? 0 : state.pageCount,
              ),
              key: StudioDriverKeys.statisticsPageNumber,
              style: context.text.labelLarge,
            ),
          ),
          IconButton(
            key: StudioDriverKeys.statisticsNextPage,
            tooltip: context.l10n.statisticsNextPage,
            onPressed: state.pageIndex + 1 < state.pageCount
                ? () => onPageChanged(state.pageIndex + 1)
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    ],
  );
}
