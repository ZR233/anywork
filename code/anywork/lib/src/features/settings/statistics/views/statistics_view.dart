import 'package:anywork_client/statistics.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_driver_keys.dart';
import '../../settings_common.dart';
import '../state/statistics_view_state.dart';
import '../widgets/statistics_history_widgets.dart';
import '../widgets/statistics_status_widgets.dart';
import '../widgets/statistics_summary_widgets.dart';

/// Pure statistics view. All filtering and resource ownership arrive through immutable props.
class StatisticsView extends StatelessWidget {
  const StatisticsView({
    required this.state,
    required this.visible,
    required this.onModelChanged,
    required this.onEffortChanged,
    required this.onMismatchesOnlyChanged,
    required this.onRetry,
    super.key,
  });

  final StatisticsViewState state;
  final bool visible;
  final ValueChanged<String?> onModelChanged;
  final ValueChanged<String?> onEffortChanged;
  final ValueChanged<bool> onMismatchesOnlyChanged;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final snapshot = state.snapshot;
    final summaries = snapshot?.summaries ?? const <StatisticsSummary>[];
    final sourceHistory = snapshot?.history ?? const <StatisticsSample>[];
    final history = state.filteredHistory;
    final filter = state.modelFilter;
    final effortFilter = state.effortFilter;
    final mismatchesOnly = state.mismatchesOnly;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        // gap/readFailed are stable header issues. Pending remains invisible and only suppresses
        // a premature empty-history conclusion.
        final headerIssue =
            snapshot != null && (snapshot.statisticsGap || snapshot.readFailed);
        final hasProjectionIssue =
            snapshot == null || (snapshot.statisticsPending || headerIssue);
        return SettingsPageLayout(
          maxWidth: 1120,
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsHeader(
                title: context.l10n.settingsStatisticsTitle,
                subtitle: context.l10n.settingsStatisticsSubtitle,
              ),
              if (visible && headerIssue)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: StatisticsStatusLine(snapshot: snapshot),
                ),
              if (visible)
                StatisticsConnectionStatus(
                  state: state.connection,
                  onRetry: onRetry,
                ),
            ],
          ),
          child: CustomScrollView(
            key: StudioDriverKeys.statisticsHistory,
            slivers: [
              SliverToBoxAdapter(
                child: StatisticsSummarySection(
                  compact: compact,
                  summaries: summaries,
                  showEmptyState:
                      snapshot != null &&
                      state.connection.phase == StatisticsConnectionPhase.ready,
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                sliver: SliverToBoxAdapter(
                  child: StatisticsHistoryHeader(
                    history: sourceHistory,
                    summaries: summaries,
                    value: filter,
                    onChanged: onModelChanged,
                    effortValue: effortFilter,
                    onEffortChanged: onEffortChanged,
                    mismatchesOnly: mismatchesOnly,
                    onMismatchesOnlyChanged: onMismatchesOnlyChanged,
                  ),
                ),
              ),
              if (history.isEmpty) ...[
                if (filter != null ||
                    mismatchesOnly ||
                    sourceHistory.isNotEmpty ||
                    !hasProjectionIssue)
                  SliverToBoxAdapter(
                    child: StatisticsEmptyState(
                      label:
                          sourceHistory.isEmpty &&
                              filter == null &&
                              !mismatchesOnly
                          ? context.l10n.settingsStatisticsEmpty
                          : mismatchesOnly
                          ? context.l10n.settingsStatisticsMismatchEmpty
                          : context.l10n.settingsStatisticsFilteredEmpty,
                    ),
                  ),
              ] else ...[
                if (!compact)
                  SliverToBoxAdapter(child: StatisticsWideHistoryHeader()),
                SliverList.builder(
                  itemCount: history.length,
                  itemBuilder: (context, index) {
                    final sample = history[index];
                    final key = StudioDriverKeys.statisticsHistoryRow(
                      sample.accountId,
                      sample.modelId ?? '',
                      sample.effort,
                      index,
                    );
                    return compact
                        ? StatisticsCompactHistoryCard(key: key, sample: sample)
                        : StatisticsWideHistoryRow(key: key, sample: sample);
                  },
                ),
              ],
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Text(
                    context.l10n.settingsStatisticsThroughputNote,
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        );
      },
    );
  }
}
