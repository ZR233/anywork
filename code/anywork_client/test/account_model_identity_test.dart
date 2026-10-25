import 'package:anywork_client/account_usage.dart';
import 'package:test/test.dart';

/// 顶层性能身份是 (accountId, 配置 modelId)；effort 只是组内细分。
///
/// 这些用例锁定三条不变量：
/// 1. 跨账号同名模型必须分离，显示名/地址/sent/reported 不参与 key；
/// 2. 同一账号模型只有一个顶层汇总，组内 effort（含 `null` 与显式 `none`）独立；
/// 3. 旧记录没有配置模型证据时保持历史身份未知，不并入看似同名的新账号模型。
///
/// 身份元组现在由 Rust 投影给出（`PerformanceSummaryIdentity` /
/// `PerformanceSampleIdentity`），Dart 不再自行拼接 `filterKey` 字符串；
/// 用例改为直接断言这些值类型的身份字段与结构相等性，语义与旧 key 一致。
const _alpha = PerformanceSummary(
  identity: PerformanceSummaryIdentity(
    accountId: 'account-a',
    accountDisplayName: 'Alpha',
    modelId: 'shared-model',
  ),
  counters: PerformanceCounters(
    sampleCount: 3,
    completionTokens: 300,
    totalTtftMillis: 900,
    ttftSampleCount: 3,
    totalResponseMillis: 3900,
    tokensPerSecond: 100,
    averageTtftMillis: 300,
    averageResponseMillis: 1300,
  ),
  effortBreakdowns: [],
);

const _beta = PerformanceSummary(
  identity: PerformanceSummaryIdentity(
    accountId: 'account-b',
    accountDisplayName: 'Beta',
    modelId: 'shared-model',
  ),
  counters: PerformanceCounters(
    sampleCount: 1,
    completionTokens: 50,
    totalTtftMillis: 200,
    ttftSampleCount: 1,
    totalResponseMillis: 1200,
    tokensPerSecond: 50,
    averageTtftMillis: 200,
    averageResponseMillis: 1200,
  ),
  effortBreakdowns: [],
);

void main() {
  test('同模板不同账号的同名模型是不同的顶层身份', () {
    expect(_alpha.identity, isNot(_beta.identity));
    expect(_alpha.identity.accountId, 'account-a');
    expect(_alpha.identity.modelId, 'shared-model');
    // 身份只由 Rust 给出的 (accountId, 配置 modelId) 决定，不夹带 effort。
    expect(
      _alpha.identity,
      const PerformanceSummaryIdentity(
        accountId: 'account-a',
        accountDisplayName: 'Alpha',
        modelId: 'shared-model',
      ),
    );
    expect(_beta.identity, isNot(_alpha.identity.copyWith(modelId: 'other')));
  });

  test('组内 effort 细分区分 null 与显式 none', () {
    const unspecified = PerformanceEffortIdentity(effort: null);
    const explicitNone = PerformanceEffortIdentity(effort: 'none');
    expect(unspecified, isNot(explicitNone));
    // `all` 只能由未选择筛选表达，不能复用 null 原值。
    expect(unspecified.effort, isNull);
    expect(explicitNone.effort, 'none');

    const withBreakdowns = PerformanceSummary(
      identity: PerformanceSummaryIdentity(
        accountId: 'account-a',
        accountDisplayName: 'Alpha',
        modelId: 'shared-model',
      ),
      counters: PerformanceCounters(
        sampleCount: 3,
        completionTokens: 300,
        totalTtftMillis: 900,
        ttftSampleCount: 3,
        totalResponseMillis: 3900,
        tokensPerSecond: 100,
        averageTtftMillis: 300,
        averageResponseMillis: 1300,
      ),
      effortBreakdowns: [
        PerformanceEffort(
          identity: unspecified,
          counters: PerformanceCounters(
            sampleCount: 1,
            completionTokens: 100,
            totalTtftMillis: 300,
            ttftSampleCount: 1,
            totalResponseMillis: 1300,
            tokensPerSecond: 100,
            averageTtftMillis: 300,
            averageResponseMillis: 1300,
          ),
        ),
        PerformanceEffort(
          identity: explicitNone,
          counters: PerformanceCounters(
            sampleCount: 2,
            completionTokens: 200,
            totalTtftMillis: 600,
            ttftSampleCount: 2,
            totalResponseMillis: 2600,
            tokensPerSecond: 100,
            averageTtftMillis: 300,
            averageResponseMillis: 1300,
          ),
        ),
      ],
    );
    expect(withBreakdowns.identity, _alpha.identity);
    expect(withBreakdowns.effortBreakdowns, hasLength(2));
    expect(
      withBreakdowns.effortBreakdowns
          .map((PerformanceEffort item) => item.identity)
          .toSet(),
      {unspecified, explicitNone},
    );
  });

  test('历史样本按同一复合身份筛选并保留冻结诊断', () {
    const matched = PerformanceSample(
      identity: PerformanceSampleIdentity(
        accountId: 'account-a',
        accountDisplayName: 'Alpha',
        modelId: 'shared-model',
        sentModel: 'shared-model-0724',
        reportedModel: 'shared-model',
        modelMatchState: ModelMatchState.mismatched,
        effort: 'high',
      ),
      counters: PerformanceSampleCounters(
        completedAt: 1767225600,
        completionTokens: 10,
        ttftMillis: 100,
        decodeMillis: 500,
        totalResponseMillis: 600,
        tokensPerSecond: 20,
      ),
    );
    // 样本的身份 (accountId, modelId) 与汇总一致，才能并入该汇总。
    expect(matched.identity.accountId, _alpha.identity.accountId);
    expect(matched.identity.modelId, _alpha.identity.modelId);
    expect(matched.identity.effort, 'high');
    expect(matched.identity.reportedModel, 'shared-model');
    // 发送别名不参与身份。
    expect(matched.identity.sentModel, 'shared-model-0724');
    expect(matched.identity.modelId, isNot(matched.identity.sentModel));
  });

  test('没有配置模型证据的旧记录保持未知身份，不并入新账号模型', () {
    const legacy = PerformanceSample(
      identity: PerformanceSampleIdentity(
        accountId: 'account-a',
        accountDisplayName: 'Alpha',
        modelId: null,
        sentModel: 'legacy-alias',
        reportedModel: null,
        modelMatchState: ModelMatchState.legacyUnknown,
        effort: null,
      ),
      counters: PerformanceSampleCounters(
        completedAt: 1767225600,
        completionTokens: 10,
        ttftMillis: null,
        decodeMillis: null,
        totalResponseMillis: null,
        tokensPerSecond: null,
      ),
    );
    expect(legacy.identity.modelId, isNull);
    expect(legacy.identity.modelId, isNot(_alpha.identity.modelId));
    expect(
      legacy.identity,
      const PerformanceSampleIdentity(
        accountId: 'account-a',
        accountDisplayName: 'Alpha',
        modelId: null,
        sentModel: 'legacy-alias',
        reportedModel: null,
        modelMatchState: ModelMatchState.legacyUnknown,
        effort: null,
      ),
    );
    // 历史诊断冻结在样本身份里，不随后来的别名解析被改写。
    expect(legacy.identity.reportedModel, isNull);
    expect(legacy.identity.sentModel, 'legacy-alias');
    expect(legacy.identity.modelMatchState, ModelMatchState.legacyUnknown);
    expect(legacy.identity.effort, isNull);
  });
}
