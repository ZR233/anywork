import 'package:anywork_client/statistics.dart';
import 'package:test/test.dart';

/// 顶层性能身份是 (accountId, 配置 modelId)；effort 只是组内细分。
///
/// 这些用例锁定三条不变量：
/// 1. 跨账号同名模型必须分离，显示名/地址/sent/reported 不参与 key；
/// 2. 同一账号模型只有一个顶层汇总，组内 effort（含 `null` 与显式 `none`）独立；
/// 3. 旧记录没有配置模型证据时保持历史身份未知，不并入看似同名的新账号模型。
void main() {
  final alpha = StatisticsSummary(
    accountId: 'account-a',
    accountDisplayName: 'Alpha',
    modelId: 'shared-model',
    sampleCount: 3,
    completionTokens: 300,
    totalTtftMillis: 900,
    ttftSampleCount: 3,
    totalResponseMillis: 3900,
    tokensPerSecond: 100,
    averageTtftMillis: 300,
    averageResponseMillis: 1300,
  );
  final beta = StatisticsSummary(
    accountId: 'account-b',
    accountDisplayName: 'Beta',
    modelId: 'shared-model',
    sampleCount: 1,
    completionTokens: 50,
    totalTtftMillis: 200,
    ttftSampleCount: 1,
    totalResponseMillis: 1200,
    tokensPerSecond: 50,
    averageTtftMillis: 200,
    averageResponseMillis: 1200,
  );

  test('同模板不同账号的同名模型是不同的顶层身份', () {
    expect(alpha.filterKey, isNot(beta.filterKey));
    expect(alpha.filterKey, contains('account-a'));
    expect(alpha.filterKey, contains('shared-model'));
    // key 只由 accountId 与配置 modelId 组成，不夹带 effort/显示名。
    expect(alpha.filterKey, '["account-a","shared-model"]');
  });

  test('组内 effort 细分区分 null 与显式 none', () {
    const unspecified = StatisticsEffortSummary(
      effort: null,
      sampleCount: 1,
      completionTokens: 100,
      totalTtftMillis: 300,
      ttftSampleCount: 1,
      totalResponseMillis: 1300,
      tokensPerSecond: 100,
      averageTtftMillis: 300,
      averageResponseMillis: 1300,
    );
    const explicitNone = StatisticsEffortSummary(
      effort: 'none',
      sampleCount: 2,
      completionTokens: 200,
      totalTtftMillis: 600,
      ttftSampleCount: 2,
      totalResponseMillis: 2600,
      tokensPerSecond: 100,
      averageTtftMillis: 300,
      averageResponseMillis: 1300,
    );
    expect(unspecified.effortKey, isNot(explicitNone.effortKey));
    // `all` 只能由未选择筛选表达，不能复用 null 原值。
    expect(unspecified.effortKey, '[null]');
    expect(explicitNone.effortKey, '["none"]');

    final withBreakdowns = StatisticsSummary(
      accountId: 'account-a',
      accountDisplayName: 'Alpha',
      modelId: 'shared-model',
      sampleCount: 3,
      completionTokens: 300,
      totalTtftMillis: 900,
      ttftSampleCount: 3,
      totalResponseMillis: 3900,
      tokensPerSecond: 100,
      averageTtftMillis: 300,
      averageResponseMillis: 1300,
      effortBreakdowns: [unspecified, explicitNone],
    );
    expect(withBreakdowns.filterKey, alpha.filterKey);
    expect(withBreakdowns.effortBreakdowns, hasLength(2));
    expect(
      withBreakdowns.effortBreakdowns.map((item) => item.effortKey).toSet(),
      {unspecified.effortKey, explicitNone.effortKey},
    );
  });

  test('历史样本按同一复合身份筛选并保留冻结诊断', () {
    final matched = StatisticsSample(
      threadId: 'thread-statistics',
      callId: 'call-1',
      purpose: 'primary',
      firstOutputSource: FirstOutputSource.incremental,
      usageStatus: UsageReportStatus.reported,
      ttftAvailability: MetricAvailability.available,
      throughputAvailability: MetricAvailability.available,
      completedAt: DateTime.utc(2026, 1, 1),
      accountId: 'account-a',
      accountDisplayName: 'Alpha',
      modelId: 'shared-model',
      sentModel: 'shared-model-0724',
      reportedModel: 'shared-model',
      modelMatchState: StatisticsModelMatchState.mismatched,
      effort: 'high',
      completionTokens: 10,
      ttftMillis: 100,
      decodeMillis: 500,
      totalResponseMillis: 600,
      tokensPerSecond: 20,
    );
    expect(matched.filterKey, alpha.filterKey);
    expect(matched.effortKey, '["high"]');
    expect(matched.displayModel, 'shared-model');
    // 发送别名不参与身份。
    expect(matched.filterKey, isNot(contains('shared-model-0724')));
    final source = [matched];
    final snapshot = StatisticsSnapshot(
      ownerEpoch: 'owner',
      feedId: 'feed',
      publicationRevision: 1,
      summariesRevision: 1,
      historyRevision: 1,
      summaries: [alpha],
      history: source,
      statisticsPending: false,
      statisticsGap: false,
      readFailed: false,
    );
    source.clear();
    expect(snapshot.history, [matched]);
    expect(() => snapshot.history.add(matched), throwsUnsupportedError);
  });

  test('没有配置模型证据的旧记录保持未知身份，不并入新账号模型', () {
    final legacy = StatisticsSample(
      threadId: 'thread-statistics',
      callId: 'call-2',
      purpose: null,
      firstOutputSource: FirstOutputSource.legacyUnknown,
      usageStatus: UsageReportStatus.legacyUnknown,
      ttftAvailability: MetricAvailability.legacyUnknown,
      throughputAvailability: MetricAvailability.legacyUnknown,
      completedAt: DateTime.utc(2026, 1, 1),
      accountId: 'account-a',
      accountDisplayName: 'Alpha',
      modelId: null,
      sentModel: 'legacy-alias',
      reportedModel: null,
      effort: null,
      modelMatchState: StatisticsModelMatchState.legacyUnknown,
      completionTokens: 10,
      ttftMillis: null,
      decodeMillis: null,
      totalResponseMillis: null,
      tokensPerSecond: null,
    );
    expect(legacy.modelId, isNull);
    expect(legacy.filterKey, isNot(alpha.filterKey));
    expect(legacy.filterKey, '["account-a",null]');
    expect(legacy.displayModel, 'legacy-alias');
    expect(legacy.modelMatchState, StatisticsModelMatchState.legacyUnknown);
    expect(legacy.effortKey, '[null]');
  });
}
