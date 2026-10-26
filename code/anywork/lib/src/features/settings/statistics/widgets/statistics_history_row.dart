import 'package:anywork_client/statistics.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../ui/formatters/token_format.dart';
import 'statistics_format.dart';

/// One history sample. Identity, order, spacing and every value keep the
/// established statistics presentation: a table row on wide panes and a block
/// on narrow ones.
class StatisticsHistoryRow extends StatelessWidget {
  const StatisticsHistoryRow({
    required this.sample,
    required this.compact,
    super.key,
  });

  final PerformanceSample sample;

  /// Below 760 the row becomes the established compact block.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final counters = sample.counters;
    if (!compact) {
      return _WideCells(
        children: [
          Text(statisticsCompletedAt(context, counters.completedAt)),
          _ModelIdentity(sample: sample),
          Text(statisticsEffort(context, sample.identity.effort)),
          Text(formatTokenCount(counters.completionTokens)),
          Text(statisticsSampleMillis(context, counters.ttftMillis)),
          Text(statisticsSampleMillis(context, counters.decodeMillis)),
          Text(statisticsSampleMillis(context, counters.totalResponseMillis)),
          Text(
            counters.tokensPerSecond == null
                ? context.l10n.statisticsMetricNotCollected
                : context.tokenThroughputLabel(counters.tokensPerSecond),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ModelIdentity(sample: sample),
          const SizedBox(height: 4),
          Text(
            statisticsCompletedAt(context, counters.completedAt),
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
              _metric(
                context,
                context.l10n.statisticsReasoningEffort,
                statisticsEffort(context, sample.identity.effort),
              ),
              _metric(
                context,
                context.l10n.statisticsSpeed,
                counters.tokensPerSecond == null
                    ? context.l10n.statisticsMetricNotCollected
                    : context.tokenThroughputLabel(counters.tokensPerSecond),
              ),
              _metric(
                context,
                context.l10n.statisticsOutputTokens,
                formatTokenCount(counters.completionTokens),
              ),
              _metric(
                context,
                'TTFT',
                statisticsSampleMillis(context, counters.ttftMillis),
              ),
              _metric(
                context,
                context.l10n.statisticsDecode,
                statisticsSampleMillis(context, counters.decodeMillis),
              ),
              _metric(
                context,
                context.l10n.statisticsTotalResponse,
                statisticsSampleMillis(context, counters.totalResponseMillis),
              ),
            ],
          ),
          const Divider(height: 24),
        ],
      ),
    );
  }

  Widget _metric(BuildContext context, String title, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(title, style: context.text.labelSmall),
      Text(value),
    ],
  );
}

/// History model identity: the requested (configured) model, falling back to
/// the sent model; the mapping line appears only when both exist and differ,
/// the upstream line and the mismatch badge only when the response differs or
/// the frozen diagnostic says mismatched. Unreported/legacy stays neutral.
class _ModelIdentity extends StatelessWidget {
  const _ModelIdentity({required this.sample});

  final PerformanceSample sample;

  @override
  Widget build(BuildContext context) {
    final identity = sample.identity;
    final configured = identity.modelId;
    final sent = identity.sentModel;
    final reported = identity.reportedModel;
    final hasMapping = configured != null && sent != null && configured != sent;
    final responseDiffers =
        sent != null && reported != null && reported != sent;
    final mismatched = identity.modelMatchState == ModelMatchState.mismatched;
    final neutralStatus = switch (identity.modelMatchState) {
      ModelMatchState.unreported => context.l10n.statisticsModelUnreported,
      ModelMatchState.legacyUnknown =>
        context.l10n.statisticsModelLegacyUnknown,
      _ => null,
    };
    final detailStyle = context.text.labelSmall?.copyWith(
      color: context.colors.onSurfaceVariant,
    );
    final warning = context.statusColors.warning;
    final description = [
      identity.accountDisplayName == identity.accountId
          ? statisticsIdentity(context, identity.accountDisplayName)
          : '${statisticsIdentity(context, identity.accountDisplayName)}'
                ' · ${statisticsIdentity(context, identity.accountId)}',
      _describeModel(
        context.l10n.statisticsConfiguredModel,
        configured,
        context.l10n.statisticsModelUnavailable,
      ),
      _describeModel(
        context.l10n.statisticsSentModel,
        sent,
        context.l10n.statisticsModelUnavailable,
      ),
      _describeModel(
        context.l10n.statisticsReportedModel,
        reported,
        context.l10n.statisticsModelUnavailable,
      ),
      switch (identity.modelMatchState) {
        ModelMatchState.matched => context.l10n.statisticsModelMatched,
        ModelMatchState.mismatched => context.l10n.statisticsModelMismatched,
        ModelMatchState.unreported => context.l10n.statisticsModelUnreported,
        ModelMatchState.legacyUnknown =>
          context.l10n.statisticsModelLegacyUnknown,
      },
    ].join('\n');
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
              statisticsIdentity(context, configured ?? sent),
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
                  '↳ $sent',
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
                      '$reported',
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

  String _describeModel(String label, String? value, String unavailable) =>
      '$label: ${value ?? unavailable}';
}

/// 「模型不匹配」徽标：浅橙底、橙字、橙色细边框的小圆角标签。
class _ModelMismatchBadge extends StatelessWidget {
  const _ModelMismatchBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final semantic = context.statusColors;
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

/// Wide-pane cell row shared by the history header and its samples.
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
                      ? context.text.labelMedium!.copyWith(
                          fontWeight: FontWeight.w600,
                        )
                      : context.text.bodySmall!,
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

/// The wide history header keeps its own emphasised cell row.
class StatisticsWideHistoryHeader extends StatelessWidget {
  const StatisticsWideHistoryHeader({super.key});

  @override
  Widget build(BuildContext context) => _WideCells(
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
