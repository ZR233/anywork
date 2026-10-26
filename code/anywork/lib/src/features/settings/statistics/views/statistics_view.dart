import 'package:anywork_client/statistics.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../widgets/settings_layout.dart';
import '../state/statistics_view_state.dart';
import '../widgets/statistics_format.dart';
import '../widgets/statistics_history_row.dart';
import '../widgets/statistics_status_widgets.dart';
import '../widgets/statistics_summary_view.dart';

/// Pure statistics view. Every filter and the whole snapshot arrive through
/// immutable props; this page never reads, pages or holds a resource identity.
class StatisticsView extends StatelessWidget {
  const StatisticsView({
    required this.state,
    required this.onModelChanged,
    required this.onEffortChanged,
    required this.onMismatchesOnlyChanged,
    required this.onRetry,
    super.key,
  });

  final StatisticsViewState state;
  final ValueChanged<StatisticsModelKey?> onModelChanged;
  final ValueChanged<StatisticsEffortFilter?> onEffortChanged;
  final ValueChanged<bool> onMismatchesOnlyChanged;

  /// The page's only recovery: the domain's read-only re-sync.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final header = state.snapshot;
    final summaries = header?.summaries ?? const <PerformanceSummary>[];
    final sourceHistory = header?.history ?? const <PerformanceSample>[];
    final history = state.filteredHistory;
    final filter = state.modelFilter;
    final mismatchesOnly = state.mismatchesOnly;
    final sync = state.source.sync;
    final readFailed = header?.readFailed ?? false;
    final gap = header?.statisticsGap ?? false;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        // gap/readFailed are stable header issues. pending is the routine
        // transient while a call lands: it never gets a status line and only
        // suppresses a premature empty-history conclusion.
        final headerIssue = gap || readFailed;
        final hasProjectionIssue =
            header == null ||
            header.statisticsPending ||
            header.statisticsGap ||
            header.readFailed;
        final knownEmpty = header != null && !hasProjectionIssue;
        return SettingsPageLayout(
          maxWidth: 1120,
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsHeader(
                title: context.l10n.settingsStatisticsTitle,
                subtitle: context.l10n.settingsStatisticsSubtitle,
              ),
              // gap/readFailed 在固定页头轻量显示，不在正文顶部插拔大块。
              if (state.visible && headerIssue)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: StatisticsStatusLine(readFailed: readFailed, gap: gap),
                ),
              // 只有真实失败（或必要重连）才出现的统计连接状态，沿用原 topic 状态
              // 的几何、文案与 key；idle/connecting/ready 不渲染。
              if (state.visible)
                StatisticsConnectionStatus(sync: sync, onRetry: onRetry),
            ],
          ),
          child: CustomScrollView(
            key: StudioDriverKeys.statisticsHistory,
            slivers: [
              SliverToBoxAdapter(
                child: StatisticsSummaryView(
                  summaries: summaries,
                  compact: compact,
                  knownEmpty: knownEmpty,
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                sliver: SliverToBoxAdapter(
                  child: _filters(context, constraints.maxWidth),
                ),
              ),
              if (history.isEmpty) ...[
                if (filter != null ||
                    mismatchesOnly ||
                    sourceHistory.isNotEmpty ||
                    !hasProjectionIssue)
                  SliverToBoxAdapter(
                    child: _EmptyState(
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
                  const SliverToBoxAdapter(
                    child: StatisticsWideHistoryHeader(),
                  ),
                SliverList.builder(
                  itemCount: history.length,
                  itemBuilder: (context, index) {
                    final sample = history[index];
                    return StatisticsHistoryRow(
                      key: StudioDriverKeys.statisticsHistoryRow(
                        sample.identity.accountId,
                        sample.identity.modelId ?? '',
                        sample.identity.effort,
                        index,
                      ),
                      sample: sample,
                      compact: compact,
                    );
                  },
                ),
              ],
              // 口径说明放在页面末尾：既解释公式与耗时边界，也不挤占顶部筛选与汇总的
              // 可视区域。
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

  Widget _filters(BuildContext context, double maxWidth) {
    final filterWidth = maxWidth < 240 ? maxWidth : 240.0;
    final title = Text(
      context.l10n.settingsStatisticsHistoryTitle,
      style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(fontWeight: FontWeight.w600),
    );
    final filter = SizedBox(
      key: StudioDriverKeys.statisticsFilter,
      width: filterWidth,
      child: DropdownMenu<StatisticsModelKey?>(
        // Caller-owned canonical selection, not a draft edit: the field follows
        // [state] via initialSelection without a value-driven key, so choosing
        // a filter never remounts the field's state (an explicit null —
        // 「全部模型」 — stays a legitimate value).
        initialSelection: state.modelFilter,
        hintText: context.l10n.settingsStatisticsAllModels,
        expandedInsets: EdgeInsets.zero,
        dropdownMenuEntries: [
          DropdownMenuEntry<StatisticsModelKey?>(
            value: null,
            label: context.l10n.settingsStatisticsAllModels,
            labelWidget: Text(context.l10n.settingsStatisticsAllModels),
          ),
          for (final option in state.modelOptions)
            DropdownMenuEntry<StatisticsModelKey?>(
              value: option.key,
              label:
                  '${statisticsIdentity(context, option.accountDisplayName)}'
                  ' · ${statisticsIdentity(context, option.key.accountId)}'
                  ' · ${statisticsIdentity(context, option.displayModel)}',
              labelWidget: Text(
                '${statisticsIdentity(context, option.accountDisplayName)}'
                ' · ${statisticsIdentity(context, option.key.accountId)}'
                ' · ${statisticsIdentity(context, option.displayModel)}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          // A selection that is no longer in the complete set is pruned by the
          // ViewModel; until then it keeps its own label instead of silently
          // reading as 「全部模型」.
          if (state.modelFilter case final selected?)
            if (!state.modelOptions.any((option) => option.key == selected))
              DropdownMenuEntry<StatisticsModelKey?>(
                value: selected,
                label:
                    '${statisticsIdentity(context, selected.accountId)}'
                    ' · ${statisticsIdentity(context, selected.modelId)}',
              ),
        ],
        onSelected: onModelChanged,
      ),
    );
    final effortFilter = SizedBox(
      key: StudioDriverKeys.statisticsEffortFilter,
      width: filterWidth,
      child: DropdownMenu<StatisticsEffortFilter?>(
        // 强度筛选是顶层模型身份的组内细分，独立于模型筛选。
        initialSelection: state.effortFilter,
        hintText: context.l10n.statisticsAllEfforts,
        expandedInsets: EdgeInsets.zero,
        dropdownMenuEntries: [
          DropdownMenuEntry<StatisticsEffortFilter?>(
            value: null,
            label: context.l10n.statisticsAllEfforts,
            labelWidget: Text(context.l10n.statisticsAllEfforts),
          ),
          for (final effort in state.effortOptions)
            DropdownMenuEntry<StatisticsEffortFilter?>(
              value: effort,
              label: statisticsEffort(context, effort.value),
              labelWidget: Text(
                statisticsEffort(context, effort.value),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (state.effortFilter case final selected?)
            if (!state.effortOptions.contains(selected))
              DropdownMenuEntry<StatisticsEffortFilter?>(
                value: selected,
                label: statisticsEffort(context, selected.value),
              ),
        ],
        onSelected: onEffortChanged,
      ),
    );
    final mismatchFilter = InkWell(
      onTap: () => onMismatchesOnlyChanged(!state.mismatchesOnly),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              key: StudioDriverKeys.statisticsMismatchOnly,
              value: state.mismatchesOnly,
              onChanged: (value) => onMismatchesOnlyChanged(value ?? false),
              visualDensity: VisualDensity.compact,
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
    // 筛选区域按可用宽度换行：标题与三个控件都保持自身宽度，空间不足时整组
    // 换到下一行，不隐藏、不压缩，也不依赖固定机型阈值。
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [title, mismatchFilter, filter, effortFilter],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Center(
      child: Text(
        label,
        style: TextStyle(color: context.colors.onSurfaceVariant),
      ),
    ),
  );
}
