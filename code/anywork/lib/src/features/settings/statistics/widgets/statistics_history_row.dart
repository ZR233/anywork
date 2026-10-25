import 'package:anywork_client/account_usage.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../ui/formatters/token_format.dart';
import 'statistics_format.dart';

class StatisticsHistoryRow extends StatelessWidget {
  const StatisticsHistoryRow({
    required this.sample,
    required this.compact,
    super.key,
  });
  final PerformanceSample sample;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final counters = sample.counters;
    final speed = counters.tokensPerSecond == null
        ? context.l10n.statisticsMetricNotCollected
        : context.tokenThroughputLabel(counters.tokensPerSecond);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _identity(context),
                  const SizedBox(height: 4),
                  Text(statisticsCompletedAt(context, counters.completedAt)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 18,
                    runSpacing: 8,
                    children: [
                      _metric(
                        context,
                        context.l10n.statisticsReasoningEffort,
                        statisticsEffort(context, sample.identity.effort),
                      ),
                      _metric(context, context.l10n.statisticsSpeed, speed),
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
                        statisticsSampleMillis(
                          context,
                          counters.totalResponseMillis,
                        ),
                      ),
                    ],
                  ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      statisticsCompletedAt(context, counters.completedAt),
                    ),
                  ),
                  Expanded(flex: 2, child: _identity(context)),
                  Expanded(
                    child: Text(
                      statisticsEffort(context, sample.identity.effort),
                    ),
                  ),
                  Expanded(
                    child: Text(formatTokenCount(counters.completionTokens)),
                  ),
                  Expanded(
                    child: Text(
                      statisticsSampleMillis(context, counters.ttftMillis),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      statisticsSampleMillis(context, counters.decodeMillis),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      statisticsSampleMillis(
                        context,
                        counters.totalResponseMillis,
                      ),
                    ),
                  ),
                  Expanded(child: Text(speed)),
                ],
              ),
      ),
    );
  }

  Widget _identity(BuildContext context) {
    final identity = sample.identity;
    final configured = identity.modelId;
    final sent = identity.sentModel;
    final reported = identity.reportedModel;
    final mapping = configured != null && sent != null && configured != sent;
    final responseDiffers =
        sent != null && reported != null && sent != reported;
    final mismatched = identity.modelMatchState == ModelMatchState.mismatched;
    final status = switch (identity.modelMatchState) {
      ModelMatchState.matched => context.l10n.statisticsModelMatched,
      ModelMatchState.mismatched => context.l10n.statisticsModelMismatched,
      ModelMatchState.unreported => context.l10n.statisticsModelUnreported,
      ModelMatchState.legacyUnknown =>
        context.l10n.statisticsModelLegacyUnknown,
    };
    final unavailable = context.l10n.statisticsModelUnavailable;
    final description = [
      '${statisticsIdentity(context, identity.accountDisplayName)} · ${statisticsIdentity(context, identity.accountId)}',
      '${context.l10n.statisticsConfiguredModel}: ${configured ?? unavailable}',
      '${context.l10n.statisticsSentModel}: ${sent ?? unavailable}',
      '${context.l10n.statisticsReportedModel}: ${reported ?? unavailable}',
      status,
    ].join('\n');
    final warning = Theme.of(context)
        .extension<StudioSemanticColors>()!
        .warning;
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
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (mapping)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 2),
                child: Text(
                  '↳ $sent',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (responseDiffers)
              Padding(
                padding: EdgeInsets.only(left: mapping ? 24 : 12, top: 2),
                child: Text(
                  '↳ ${context.l10n.statisticsUpstreamReportedModel}: $reported',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: warning),
                ),
              ),
            if (mismatched)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 2),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: warning.withValues(alpha: .1),
                    border: Border.all(color: warning.withValues(alpha: .6)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    child: Text(
                      context.l10n.statisticsModelMismatchBadge,
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: warning),
                    ),
                  ),
                ),
              ),
            if (identity.modelMatchState == ModelMatchState.unreported ||
                identity.modelMatchState == ModelMatchState.legacyUnknown)
              Text(status, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }

  Widget _metric(BuildContext context, String title, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(title, style: Theme.of(context).textTheme.labelSmall),
      Text(value),
    ],
  );
}
