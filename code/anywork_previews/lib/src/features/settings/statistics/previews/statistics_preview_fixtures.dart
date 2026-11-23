import 'package:anywork_client/statistics.dart';

/// Synthetic request-frozen tiers on the same account, configured model and effort.
StatisticsSnapshot statisticsServiceTierSnapshot() {
  const account = 'ChatGPT · Preview';
  const model = 'gpt-6.2-sol';
  const tiers = ['standard', 'tier:priority', 'tier:ultrafast'];
  const decodeMillis = [19100, 9550, 5750];
  const ttftMillis = [900, 450, 250];
  const speeds = [60.0, 120.0, 200.0];
  return StatisticsSnapshot(
    ownerEpoch: 'preview-owner',
    feedId: 'preview-feed',
    publicationRevision: 1,
    summariesRevision: 1,
    historyRevision: 1,
    summaries: [
      StatisticsSummary(
        accountId: 'preview-account',
        accountDisplayName: account,
        modelId: model,
        sampleCount: 3,
        completionTokens: 3600,
        totalTtftMillis: 1600,
        ttftSampleCount: 3,
        totalResponseMillis: 36000,
        tokensPerSecond: 100,
        averageTtftMillis: 1600 / 3,
        averageResponseMillis: 12000,
        effortBreakdowns: [
          for (var index = 0; index < tiers.length; index++)
            StatisticsEffortSummary(
              effort: 'high',
              requestedServiceTier: tiers[index],
              sampleCount: 1,
              completionTokens: 1200,
              totalTtftMillis: ttftMillis[index],
              ttftSampleCount: 1,
              totalResponseMillis: decodeMillis[index] + ttftMillis[index],
              tokensPerSecond: speeds[index],
              averageTtftMillis: ttftMillis[index].toDouble(),
              averageResponseMillis: (decodeMillis[index] + ttftMillis[index])
                  .toDouble(),
            ),
        ],
      ),
    ],
    history: [
      for (var index = 0; index < tiers.length; index++)
        StatisticsSample(
          threadId: 'preview-thread',
          callId: 'preview-call-$index',
          purpose: 'primary',
          firstOutputSource: FirstOutputSource.incremental,
          usageStatus: UsageReportStatus.reported,
          ttftAvailability: MetricAvailability.available,
          throughputAvailability: MetricAvailability.available,
          completedAt: DateTime(2026, 3, 1, 10, 42 - index),
          accountId: 'preview-account',
          accountDisplayName: account,
          modelId: model,
          sentModel: model,
          reportedModel: model,
          modelMatchState: StatisticsModelMatchState.matched,
          effort: 'high',
          requestedServiceTier: tiers[index],
          completionTokens: 1200,
          ttftMillis: ttftMillis[index],
          decodeMillis: decodeMillis[index],
          totalResponseMillis: decodeMillis[index] + ttftMillis[index],
          tokensPerSecond: speeds[index],
        ),
    ],
    statisticsPending: false,
    statisticsGap: false,
    readFailed: false,
  );
}
