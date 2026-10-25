import 'package:anywork_client/statistics.dart';
import 'package:anywork_client/models.dart' show formatTokenCount;
import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_driver_keys.dart';
import '../../settings_common.dart';
import 'statistics_formatters.dart';

class StatisticsHistoryHeader extends StatelessWidget {
  const StatisticsHistoryHeader({
    required this.history,
    required this.summaries,
    required this.value,
    required this.onChanged,
    required this.effortValue,
    required this.onEffortChanged,
    required this.mismatchesOnly,
    required this.onMismatchesOnlyChanged,
    super.key,
  });

  final List<StatisticsSample> history;
  final List<StatisticsSummary> summaries;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String? effortValue;
  final ValueChanged<String?> onEffortChanged;
  final bool mismatchesOnly;
  final ValueChanged<bool> onMismatchesOnlyChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final seen = <String>{};
        final filterWidth = constraints.maxWidth < 240
            ? constraints.maxWidth
            : 240.0;
        final title = Text(
          context.l10n.settingsStatisticsHistoryTitle,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        );
        final filter = SizedBox(
          key: StudioDriverKeys.statisticsFilter,
          width: filterWidth,
          child: DropdownMenu<String?>(
            // Caller-owned canonical selection, not a draft edit: the field
            // follows [value] via initialSelection without a value-driven
            // key, so choosing a filter never remounts the field's state
            // (an explicit null — "all models" — stays a legitimate value;
            // 初始空选择以提示文案呈现“全部模型”）。
            initialSelection: value,
            hintText: context.l10n.settingsStatisticsAllModels,
            expandedInsets: EdgeInsets.zero,
            dropdownMenuEntries: [
              DropdownMenuEntry<String?>(
                value: null,
                label: context.l10n.settingsStatisticsAllModels,
                labelWidget: Text(context.l10n.settingsStatisticsAllModels),
              ),
              for (final sample in history)
                if (seen.add(sample.filterKey))
                  DropdownMenuEntry<String?>(
                    value: sample.filterKey,
                    label: formatStatisticsPerformanceIdentity(
                      context,
                      sample.accountDisplayName,
                      sample.accountId,
                      sample.displayModel,
                    ),
                    labelWidget: Text(
                      formatStatisticsPerformanceIdentity(
                        context,
                        sample.accountDisplayName,
                        sample.accountId,
                        sample.displayModel,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              for (final summary in summaries)
                if (seen.add(summary.filterKey))
                  DropdownMenuEntry<String?>(
                    value: summary.filterKey,
                    label: formatStatisticsPerformanceIdentity(
                      context,
                      summary.accountDisplayName,
                      summary.accountId,
                      summary.modelId,
                    ),
                    labelWidget: Text(
                      formatStatisticsPerformanceIdentity(
                        context,
                        summary.accountDisplayName,
                        summary.accountId,
                        summary.modelId,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
            ],
            onSelected: onChanged,
          ),
        );
        final seenEfforts = <String>{};
        final effortFilter = SizedBox(
          key: StudioDriverKeys.statisticsEffortFilter,
          width: filterWidth,
          child: DropdownMenu<String?>(
            // 强度筛选是顶层模型身份的组内细分，独立于模型筛选。
            initialSelection: effortValue,
            hintText: context.l10n.statisticsAllEfforts,
            expandedInsets: EdgeInsets.zero,
            dropdownMenuEntries: [
              DropdownMenuEntry<String?>(
                value: null,
                label: context.l10n.statisticsAllEfforts,
                labelWidget: Text(context.l10n.statisticsAllEfforts),
              ),
              for (final sample in history)
                if (seenEfforts.add(sample.effortKey))
                  DropdownMenuEntry<String?>(
                    value: sample.effortKey,
                    label: formatStatisticsReasoningEffort(
                      context,
                      sample.effort,
                    ),
                    labelWidget: Text(
                      formatStatisticsReasoningEffort(context, sample.effort),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
            ],
            onSelected: onEffortChanged,
          ),
        );
        final mismatchFilter = InkWell(
          onTap: () => onMismatchesOnlyChanged(!mismatchesOnly),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  key: StudioDriverKeys.statisticsMismatchOnly,
                  value: mismatchesOnly,
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
      },
    );
  }
}

class StatisticsWideHistoryHeader extends StatelessWidget {
  const StatisticsWideHistoryHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return _WideCells(
      emphasized: true,
      children: [
        Text(context.l10n.statisticsCompletedAt),
        Text(context.l10n.statisticsHistoryModelHeader),
        Text(context.l10n.statisticsReasoningEffort),
        Text(context.l10n.statisticsOutputTokens),
        const Text('TTFT'),
        Text(context.l10n.statisticsDecode),
        Text(context.l10n.statisticsTotalResponse),
        Text(context.l10n.statisticsSpeed),
      ],
    );
  }
}

class StatisticsWideHistoryRow extends StatelessWidget {
  const StatisticsWideHistoryRow({required this.sample, super.key});

  final StatisticsSample sample;

  @override
  Widget build(BuildContext context) {
    return _WideCells(
      children: [
        Text(formatStatisticsCompletedAt(context, sample.completedAt)),
        _ModelIdentity(sample: sample),
        Text(formatStatisticsReasoningEffort(context, sample.effort)),
        Text(formatTokenCount(sample.completionTokens)),
        Text(formatStatisticsSampleMillis(context, sample.ttftMillis)),
        Text(formatStatisticsSampleMillis(context, sample.decodeMillis)),
        Text(formatStatisticsSampleMillis(context, sample.totalResponseMillis)),
        Text(formatStatisticsSampleSpeed(context, sample.tokensPerSecond)),
      ],
    );
  }
}

class _WideCells extends StatelessWidget {
  const _WideCells({required this.children, this.emphasized = false});

  final List<Widget> children;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: emphasized
            ? context.colors.surfaceContainer
            : Colors.transparent,
        border: Border(
          bottom: BorderSide(color: context.colors.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            for (var index = 0; index < children.length; index++)
              Expanded(
                flex: index == 1 ? 2 : 1,
                child: DefaultTextStyle(
                  style: emphasized
                      ? Theme.of(context).textTheme.labelMedium!
                            .copyWith(fontWeight: FontWeight.w600)
                      : Theme.of(context).textTheme.bodySmall!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  child: children[index],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class StatisticsCompactHistoryCard extends StatelessWidget {
  const StatisticsCompactHistoryCard({required this.sample, super.key});

  final StatisticsSample sample;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ModelIdentity(sample: sample),
          const SizedBox(height: 4),
          Text(
            formatStatisticsCompletedAt(context, sample.completedAt),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              SettingsMetric(
                context.l10n.statisticsReasoningEffort,
                formatStatisticsReasoningEffort(context, sample.effort),
              ),
              SettingsMetric(
                context.l10n.statisticsSpeed,
                formatStatisticsSampleSpeed(context, sample.tokensPerSecond),
              ),
              SettingsMetric(
                context.l10n.statisticsOutputTokens,
                formatTokenCount(sample.completionTokens),
              ),
              SettingsMetric(
                'TTFT',
                formatStatisticsSampleMillis(context, sample.ttftMillis),
              ),
              SettingsMetric(
                context.l10n.statisticsDecode,
                formatStatisticsSampleMillis(context, sample.decodeMillis),
              ),
              SettingsMetric(
                context.l10n.statisticsTotalResponse,
                formatStatisticsSampleMillis(
                  context,
                  sample.totalResponseMillis,
                ),
              ),
            ],
          ),
          const Divider(height: 24),
        ],
      ),
    );
  }
}

/// 历史行模型身份：第一行为请求（配置）模型，缺失时回退发送模型或历史模型；
/// 仅在配置与发送模型都存在且不同时展示映射行，发送与响应模型都存在且不同时
/// 展示橙色上游响应行并跟随不匹配徽标；未报告/未采集仅保留中性文字提示。
class _ModelIdentity extends StatelessWidget {
  const _ModelIdentity({required this.sample});

  final StatisticsSample sample;

  @override
  Widget build(BuildContext context) {
    final configured = sample.modelId;
    final sent = sample.sentModel;
    final reported = sample.reportedModel;
    final hasMapping = configured != null && sent != null && configured != sent;
    final responseDiffers =
        sent != null && reported != null && reported != sent;
    final mismatched =
        sample.modelMatchState == StatisticsModelMatchState.mismatched;
    final neutralStatus = switch (sample.modelMatchState) {
      StatisticsModelMatchState.unreported =>
        context.l10n.statisticsModelUnreported,
      StatisticsModelMatchState.legacyUnknown =>
        context.l10n.statisticsModelLegacyUnknown,
      _ => null,
    };
    final detailStyle = context.text.labelSmall?.copyWith(
      color: context.colors.onSurfaceVariant,
    );
    final warning = Theme.of(context)
        .extension<StudioSemanticColors>()!
        .warning;
    final description = describeStatisticsModelIdentity(context, sample);
    return Tooltip(
      message: description,
      child: Semantics(
        container: true,
        label: description,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              statisticsIdentityLabel(
                context,
                configured ?? sample.displayModel,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (hasMapping)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 2),
                child: Text(
                  '↳ ${statisticsIdentityLabel(context, sent)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: detailStyle,
                ),
              ),
            if (responseDiffers)
              Padding(
                padding: EdgeInsets.only(left: hasMapping ? 24 : 12, top: 2),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '↳ ${context.l10n.statisticsUpstreamReportedModel}: '
                      '${statisticsIdentityLabel(context, reported)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: detailStyle?.copyWith(color: warning),
                    ),
                    if (mismatched)
                      _ModelMismatchBadge(
                        label: context.l10n.statisticsModelMismatchBadge,
                      ),
                  ],
                ),
              ),
            if (mismatched && !responseDiffers)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 2),
                child: _ModelMismatchBadge(
                  label: context.l10n.statisticsModelMismatchBadge,
                ),
              ),
            if (neutralStatus != null)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 2),
                child: Text(
                  neutralStatus,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: detailStyle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 「模型不匹配」徽标：浅橙底、橙字、橙色细边框的小圆角标签。
class _ModelMismatchBadge extends StatelessWidget {
  const _ModelMismatchBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final semantic = Theme.of(context).extension<StudioSemanticColors>()!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: semantic.warningContainer,
        borderRadius: BorderRadius.circular(StudioRadii.xs),
        border: Border.all(color: semantic.warning.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.text.labelSmall?.copyWith(
            fontSize: 10,
            color: semantic.warning,
          ),
        ),
      ),
    );
  }
}

class StatisticsEmptyState extends StatelessWidget {
  const StatisticsEmptyState({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Text(
          label,
          style: TextStyle(color: context.colors.onSurfaceVariant),
        ),
      ),
    );
  }
}
