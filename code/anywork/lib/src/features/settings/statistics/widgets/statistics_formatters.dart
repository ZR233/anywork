import 'package:anywork_client/statistics.dart';
import 'package:flutter/material.dart';

import '../../../../l10n/studio_l10n.dart';

String formatStatisticsMillis(double millis) {
  if (millis < 1_000) return '${millis.round()} ms';
  return '${(millis / 1_000).toStringAsFixed(1)} s';
}

/// 平均首字只在真正测得首字的样本上求平均，并同时给出独立样本数。
String formatStatisticsAverageTtft(
  BuildContext context,
  double? averageMillis,
  int sampleCount,
) {
  if (averageMillis == null || sampleCount == 0) {
    return context.l10n.statisticsMetricNotCollected;
  }
  return '${formatStatisticsMillis(averageMillis)} · '
      '${context.l10n.statisticsTtftSampleCount(sampleCount)}';
}

String formatStatisticsSampleMillis(BuildContext context, int? millis) {
  return millis == null
      ? context.l10n.statisticsMetricNotCollected
      : formatStatisticsMillis(millis.toDouble());
}

String formatStatisticsSampleSpeed(
  BuildContext context,
  double? tokensPerSecond,
) {
  return tokensPerSecond == null
      ? context.l10n.statisticsMetricNotCollected
      : context.tokenThroughputLabel(tokensPerSecond);
}

String statisticsIdentityLabel(BuildContext context, String value) {
  return value.isEmpty ? context.l10n.statisticsMetricNotCollected : value;
}

String formatStatisticsReasoningEffort(BuildContext context, String? effort) {
  return effort ?? context.l10n.statisticsReasoningEffortUnspecified;
}

String describeStatisticsModelIdentity(
  BuildContext context,
  StatisticsSample sample,
) {
  final status = switch (sample.modelMatchState) {
    StatisticsModelMatchState.matched => context.l10n.statisticsModelMatched,
    StatisticsModelMatchState.mismatched =>
      context.l10n.statisticsModelMismatched,
    StatisticsModelMatchState.unreported =>
      context.l10n.statisticsModelUnreported,
    StatisticsModelMatchState.legacyUnknown =>
      context.l10n.statisticsModelLegacyUnknown,
  };
  final accountName = statisticsIdentityLabel(
    context,
    sample.accountDisplayName,
  );
  final instanceId = statisticsIdentityLabel(context, sample.accountId);
  final account = sample.accountDisplayName == sample.accountId
      ? accountName
      : '$accountName · $instanceId';
  final unavailable = context.l10n.statisticsModelUnavailable;
  return [
    account,
    '${context.l10n.statisticsConfiguredModel}: ${sample.modelId == null ? unavailable : statisticsIdentityLabel(context, sample.modelId!)}',
    '${context.l10n.statisticsSentModel}: ${sample.sentModel == null ? unavailable : statisticsIdentityLabel(context, sample.sentModel!)}',
    '${context.l10n.statisticsReportedModel}: ${sample.reportedModel == null ? unavailable : statisticsIdentityLabel(context, sample.reportedModel!)}',
    status,
  ].join('\n');
}

String formatStatisticsPerformanceIdentity(
  BuildContext context,
  String accountDisplayName,
  String accountId,
  String modelId,
) {
  return [
    statisticsIdentityLabel(context, accountDisplayName),
    statisticsIdentityLabel(context, accountId),
    statisticsIdentityLabel(context, modelId),
  ].join(' · ');
}

String formatStatisticsCompletedAt(BuildContext context, DateTime value) {
  final local = MaterialLocalizations.of(context);
  return '${local.formatShortDate(value)} ${TimeOfDay.fromDateTime(value).format(context)}';
}
