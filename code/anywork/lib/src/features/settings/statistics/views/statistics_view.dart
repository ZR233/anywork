import 'package:anywork_client/statistics.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_driver_keys.dart';
import '../../settings_common.dart';
import '../state/statistics_filter_options.dart';
import '../state/statistics_view_state.dart';
import '../widgets/statistics_history_widgets.dart';
import '../widgets/statistics_status_widgets.dart';
import '../widgets/statistics_summary_widgets.dart';

/// Pure statistics view. All filtering and resource ownership arrive through immutable props.
class StatisticsView extends StatefulWidget {
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
  State<StatisticsView> createState() => _StatisticsViewState();
}

class _StatisticsViewState extends State<StatisticsView> {
  _MaterialIdentity? _optionsHistory;
  _MaterialIdentity? _optionsSummaries;
  late StatisticsFilterOptions _options;
  Object? _summaryInputs;
  late Widget _summary;
  Object? _bodyInputs;
  Widget? _body;

  // Cached widgets forward to the current owner, never to callbacks captured from an old frame.
  void _selectModel(String? value) => widget.onModelChanged(value);
  void _selectEffort(String? value) => widget.onEffortChanged(value);
  void _selectMismatches(bool value) => widget.onMismatchesOnlyChanged(value);

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
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
        final historyMaterial = _MaterialIdentity(
          snapshot?.ownerEpoch,
          snapshot?.feedId,
          snapshot?.historyRevision,
          sourceHistory,
        );
        final summaryMaterial = _MaterialIdentity(
          snapshot?.ownerEpoch,
          snapshot?.feedId,
          snapshot?.summariesRevision,
          summaries,
        );
        if (_optionsHistory != historyMaterial ||
            _optionsSummaries != summaryMaterial) {
          _options = StatisticsFilterOptions.fromMaterials(
            sourceHistory,
            summaries,
          );
          _optionsHistory = historyMaterial;
          _optionsSummaries = summaryMaterial;
        }
        final showSummaryEmpty =
            summaries.isEmpty &&
            snapshot != null &&
            state.connection.phase == StatisticsConnectionPhase.ready;
        final summaryInputs = (summaryMaterial, compact, showSummaryEmpty);
        if (_summaryInputs != summaryInputs) {
          _summaryInputs = summaryInputs;
          _summary = StatisticsSummarySection(
            compact: compact,
            summaries: summaries,
            showEmptyState: showSummaryEmpty,
          );
        }
        final emptyLabel =
            history.isNotEmpty ||
                (filter == null &&
                    !mismatchesOnly &&
                    sourceHistory.isEmpty &&
                    hasProjectionIssue)
            ? null
            : sourceHistory.isEmpty && filter == null && !mismatchesOnly
            ? context.l10n.settingsStatisticsEmpty
            : mismatchesOnly
            ? context.l10n.settingsStatisticsMismatchEmpty
            : context.l10n.settingsStatisticsFilteredEmpty;
        // Only material/presentation changes rebuild the scroll subtree. Inherited theme/locale
        // updates still reach its dependent elements; these inputs also refresh our footer text.
        final bodyInputs = (
          historyMaterial,
          summaryMaterial,
          history,
          filter,
          effortFilter,
          mismatchesOnly,
          compact,
          emptyLabel,
          showSummaryEmpty,
          context.l10n,
          Theme.of(context),
        );
        if (_bodyInputs != bodyInputs) {
          _bodyInputs = bodyInputs;
          _body = _buildBody(
            context,
            history: history,
            compact: compact,
            filter: filter,
            effortFilter: effortFilter,
            mismatchesOnly: mismatchesOnly,
            emptyLabel: emptyLabel,
          );
        }
        return SettingsPageLayout(
          maxWidth: 1120,
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _StatisticsPageHeader(),
              if (widget.visible && headerIssue)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: StatisticsStatusLine(snapshot: snapshot),
                ),
              if (widget.visible)
                StatisticsConnectionStatus(
                  state: state.connection,
                  onRetry: widget.onRetry,
                ),
            ],
          ),
          child: _body!,
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context, {
    required List<StatisticsSample> history,
    required bool compact,
    required String? filter,
    required String? effortFilter,
    required bool mismatchesOnly,
    required String? emptyLabel,
  }) {
    return CustomScrollView(
      key: StudioDriverKeys.statisticsHistory,
      slivers: [
        SliverToBoxAdapter(child: _summary),
        SliverPadding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          sliver: SliverToBoxAdapter(
            child: StatisticsHistoryHeader(
              options: _options,
              value: filter,
              onChanged: _selectModel,
              effortValue: effortFilter,
              onEffortChanged: _selectEffort,
              mismatchesOnly: mismatchesOnly,
              onMismatchesOnlyChanged: _selectMismatches,
            ),
          ),
        ),
        if (history.isEmpty) ...[
          if (emptyLabel != null)
            SliverToBoxAdapter(child: StatisticsEmptyState(label: emptyLabel)),
        ] else ...[
          if (!compact)
            const SliverToBoxAdapter(child: StatisticsWideHistoryHeader()),
          SliverList.builder(
            itemCount: history.length,
            itemBuilder: (context, index) {
              final sample = history[index];
              final key = StudioDriverKeys.statisticsHistoryCall(
                sample.callKey,
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
              '${context.l10n.settingsStatisticsThroughputNote}\n'
              '${context.l10n.usageFirstOutputNote}\n'
              '${context.l10n.usageStatisticsGapNote}',
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

class _StatisticsPageHeader extends StatelessWidget {
  const _StatisticsPageHeader();

  @override
  Widget build(BuildContext context) => SettingsHeader(
    title: context.l10n.settingsStatisticsTitle,
    subtitle: context.l10n.settingsStatisticsSubtitle,
  );
}

/// Lists are immutable material handles, not value-comparison work on the 3000-call window.
final class _MaterialIdentity {
  const _MaterialIdentity(
    this.ownerEpoch,
    this.feedId,
    this.revision,
    this.items,
  );

  final String? ownerEpoch;
  final String? feedId;
  final int? revision;
  final Object items;

  @override
  bool operator ==(Object other) =>
      other is _MaterialIdentity &&
      ownerEpoch == other.ownerEpoch &&
      feedId == other.feedId &&
      revision == other.revision &&
      identical(items, other.items);

  @override
  int get hashCode =>
      Object.hash(ownerEpoch, feedId, revision, identityHashCode(items));
}
