import 'package:anywork_client/account_usage.dart';
import 'package:flutter/material.dart';

import '../../../../l10n/studio_l10n.dart';

String statisticsIdentity(BuildContext context, String? value) =>
    value == null || value.isEmpty
    ? context.l10n.statisticsMetricNotCollected
    : value;
String statisticsEffort(BuildContext context, String? value) =>
    value ?? context.l10n.statisticsReasoningEffortUnspecified;
String statisticsMillis(double value) => value < 1000
    ? '${value.round()} ms'
    : '${(value / 1000).toStringAsFixed(1)} s';
String statisticsSampleMillis(BuildContext context, int? value) => value == null
    ? context.l10n.statisticsMetricNotCollected
    : statisticsMillis(value.toDouble());
String statisticsAverageTtft(
  BuildContext context,
  PerformanceCounters counters,
) => counters.averageTtftMillis == null || counters.ttftSampleCount == 0
    ? context.l10n.statisticsMetricNotCollected
    : '${statisticsMillis(counters.averageTtftMillis!)} · ${context.l10n.statisticsTtftSampleCount(counters.ttftSampleCount)}';
String statisticsCompletedAt(BuildContext context, int completedAt) {
  final date = DateTime.fromMillisecondsSinceEpoch(completedAt * 1000)
      .toLocal();
  return '${MaterialLocalizations.of(context).formatShortDate(date)} ${TimeOfDay.fromDateTime(date).format(context)}';
}
