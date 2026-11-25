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

/// Fixture pair for the paged history interaction previews: the first fixed
/// read result and the second fixed result adopted after the preview-only
/// refresh delay.
final class StatisticsPaginationPreviewData {
  const StatisticsPaginationPreviewData({
    required this.snapshot,
    required this.refreshedSnapshot,
  });

  final StatisticsSnapshot snapshot;
  final StatisticsSnapshot refreshedSnapshot;
}

/// 137 synthetic history calls across two accounts, three models, three
/// efforts and three request tiers with a few mismatched upstream reports and
/// self-consistent aggregate summaries. The refreshed variant deterministically
/// drifts every metric so the refresh interaction visibly adopts another fixed
/// result without any I/O.
StatisticsPaginationPreviewData statisticsPaginationFixtures() =>
    StatisticsPaginationPreviewData(
      snapshot: _statisticsPaginationSnapshot(
        publicationRevision: 4,
        summariesRevision: 2,
        historyRevision: 6,
        refreshed: false,
      ),
      refreshedSnapshot: _statisticsPaginationSnapshot(
        publicationRevision: 5,
        summariesRevision: 3,
        historyRevision: 7,
        refreshed: true,
      ),
    );

StatisticsSnapshot _statisticsPaginationSnapshot({
  required int publicationRevision,
  required int summariesRevision,
  required int historyRevision,
  required bool refreshed,
}) {
  const accounts = [
    ('preview-account-chatgpt', 'ChatGPT · Preview'),
    ('preview-account-claude', 'Claude · Preview'),
  ];
  const models = ['gpt-6.2-sol', 'claude-opus-4.6', 'claude-sonnet-4.6'];
  const accountForModel = [0, 1, 1];
  const reportedAliases = [
    'gpt-6.1-sol-preview',
    'claude-opus-4.5',
    'claude-3-9-sonnet',
  ];
  const efforts = ['high', 'medium', 'low'];
  const tiers = ['standard', 'tier:priority', 'tier:ultrafast'];
  const baseSpeeds = [86.0, 132.0, 168.0];
  const baseTtftMillis = [900, 450, 250];
  const historyCount = 137;
  const mismatchIndexes = {9, 46, 83, 129};
  final drift = refreshed ? 1 : 0;
  final samples = <StatisticsSample>[];
  for (var index = 0; index < historyCount; index++) {
    final modelIndex = index % models.length;
    final effortIndex = (index ~/ models.length) % efforts.length;
    final tierIndex = (index ~/ 2) % tiers.length;
    final accountIndex = accountForModel[modelIndex];
    final mismatch = mismatchIndexes.contains(index);
    final completionTokens = 480 + (index * 37) % 1400 + drift * 90;
    final ttftMillis =
        baseTtftMillis[tierIndex] + (index * 53) % 240 + drift * 30;
    final tokensPerSecond =
        baseSpeeds[tierIndex] + (index * 17) % 60 + drift * 8;
    final decodeMillis = (completionTokens / tokensPerSecond * 1000).round();
    final model = models[modelIndex];
    samples.add(
      StatisticsSample(
        threadId: 'preview-thread-${index ~/ 4}',
        callId: 'preview-call-${index.toString().padLeft(4, '0')}',
        purpose: index % 17 == 5 ? 'acpTextEstimate' : 'primary',
        firstOutputSource: FirstOutputSource.incremental,
        usageStatus: UsageReportStatus.reported,
        ttftAvailability: MetricAvailability.available,
        throughputAvailability: MetricAvailability.available,
        completedAt: DateTime(
          2026,
          3,
          1,
          9,
          30,
        ).subtract(Duration(minutes: index * 11)),
        accountId: accounts[accountIndex].$1,
        accountDisplayName: accounts[accountIndex].$2,
        modelId: model,
        sentModel: model,
        reportedModel: mismatch ? reportedAliases[modelIndex] : model,
        modelMatchState: mismatch
            ? StatisticsModelMatchState.mismatched
            : StatisticsModelMatchState.matched,
        effort: efforts[effortIndex],
        requestedServiceTier: tiers[tierIndex],
        completionTokens: completionTokens,
        ttftMillis: ttftMillis,
        decodeMillis: decodeMillis,
        totalResponseMillis: decodeMillis + ttftMillis,
        tokensPerSecond: completionTokens * 1000 / (decodeMillis + ttftMillis),
      ),
    );
  }
  return StatisticsSnapshot(
    ownerEpoch: 'preview-owner',
    feedId: 'preview-feed',
    publicationRevision: publicationRevision,
    summariesRevision: summariesRevision,
    historyRevision: historyRevision,
    summaries: [
      for (var modelIndex = 0; modelIndex < models.length; modelIndex++)
        _statisticsSummaryFixture(
          accountId: accounts[accountForModel[modelIndex]].$1,
          accountDisplayName: accounts[accountForModel[modelIndex]].$2,
          modelId: models[modelIndex],
          samples: [
            for (final sample in samples)
              if (sample.modelId == models[modelIndex] &&
                  sample.accountId == accounts[accountForModel[modelIndex]].$1)
                sample,
          ],
        ),
    ],
    history: samples,
    statisticsPending: false,
    statisticsGap: false,
    readFailed: false,
  );
}

StatisticsSummary _statisticsSummaryFixture({
  required String accountId,
  required String accountDisplayName,
  required String modelId,
  required List<StatisticsSample> samples,
}) {
  final groups = <(String?, String?), List<StatisticsSample>>{};
  for (final sample in samples) {
    groups
        .putIfAbsent((sample.effort, sample.requestedServiceTier), () => [])
        .add(sample);
  }
  final (
    tokens,
    ttft,
    ttftCount,
    response,
    speed,
    averageTtft,
    averageResponse,
  ) = _statisticsAggregate(
    samples,
  );
  return StatisticsSummary(
    accountId: accountId,
    accountDisplayName: accountDisplayName,
    modelId: modelId,
    sampleCount: samples.length,
    completionTokens: tokens,
    totalTtftMillis: ttft,
    ttftSampleCount: ttftCount,
    totalResponseMillis: response,
    tokensPerSecond: speed,
    averageTtftMillis: averageTtft,
    averageResponseMillis: averageResponse,
    effortBreakdowns: [
      for (final entry in groups.entries)
        _statisticsEffortSummaryFixture(
          entry.key.$1,
          entry.key.$2,
          entry.value,
        ),
    ],
  );
}

StatisticsEffortSummary _statisticsEffortSummaryFixture(
  String? effort,
  String? requestedServiceTier,
  List<StatisticsSample> samples,
) {
  final (
    tokens,
    ttft,
    ttftCount,
    response,
    speed,
    averageTtft,
    averageResponse,
  ) = _statisticsAggregate(
    samples,
  );
  return StatisticsEffortSummary(
    effort: effort,
    requestedServiceTier: requestedServiceTier,
    sampleCount: samples.length,
    completionTokens: tokens,
    totalTtftMillis: ttft,
    ttftSampleCount: ttftCount,
    totalResponseMillis: response,
    tokensPerSecond: speed,
    averageTtftMillis: averageTtft,
    averageResponseMillis: averageResponse,
  );
}

/// Weighted aggregate matching the repository contract: throughput is
/// sum(output tokens) * 1000 / sum(total response milliseconds).
(int, int, int, int, double, double, double) _statisticsAggregate(
  List<StatisticsSample> samples,
) {
  var completionTokens = 0;
  var totalTtftMillis = 0;
  var ttftSampleCount = 0;
  var totalResponseMillis = 0;
  for (final sample in samples) {
    completionTokens += sample.completionTokens ?? 0;
    final ttft = sample.ttftMillis;
    if (ttft != null) {
      totalTtftMillis += ttft;
      ttftSampleCount += 1;
    }
    totalResponseMillis += sample.totalResponseMillis ?? 0;
  }
  return (
    completionTokens,
    totalTtftMillis,
    ttftSampleCount,
    totalResponseMillis,
    totalResponseMillis == 0
        ? 0.0
        : completionTokens * 1000 / totalResponseMillis,
    ttftSampleCount == 0 ? 0.0 : totalTtftMillis / ttftSampleCount,
    samples.isEmpty ? 0.0 : totalResponseMillis / samples.length,
  );
}
