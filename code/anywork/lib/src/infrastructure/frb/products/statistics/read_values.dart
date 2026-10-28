import 'package:anywork_client/statistics_ports.dart';

import '../../../../rust/api/studio/products/read/statistics.dart' as native;
import '../../shared/exact_numbers.dart';
import '../../shared/read_converters.dart';
import '../statistics_references.dart';

PerformanceCounters performanceCountersFromBridge(
  native.BridgePerformanceCounters value,
) => PerformanceCounters(
  sampleCount: exactU64(value.sampleCount, 'performance sample count'),
  completionTokens: exactU64(
    value.completionTokens,
    'performance completion tokens',
  ),
  totalTtftMillis: exactU64(
    value.totalTtftMillis,
    'performance total TTFT milliseconds',
  ),
  ttftSampleCount: exactU64(
    value.ttftSampleCount,
    'performance TTFT sample count',
  ),
  totalResponseMillis: exactU64(
    value.totalResponseMillis,
    'performance total response milliseconds',
  ),
  tokensPerSecond: value.tokensPerSecond,
  averageTtftMillis: value.averageTtftMillis,
  averageResponseMillis: value.averageResponseMillis,
);

PerformanceSampleCounters sampleCountersFromBridge(
  native.BridgePerformanceSampleCounters value,
) => PerformanceSampleCounters(
  completedAt: exactI64(
    BigInt.from(value.completedAt),
    'performance sample completed Unix seconds',
  ),
  completionTokens: exactU64(
    value.completionTokens,
    'sample completion tokens',
  ),
  ttftMillis: nullableU64(value.ttftMillis, 'sample TTFT milliseconds'),
  decodeMillis: nullableU64(value.decodeMillis, 'sample decode milliseconds'),
  totalResponseMillis: nullableU64(
    value.totalResponseMillis,
    'sample total response milliseconds',
  ),
  tokensPerSecond: value.tokensPerSecond,
);

PerformanceSummariesReadHeader summariesReadHeaderFromBridge(
  native.BridgePerformanceSummariesReadHeader value,
) => PerformanceSummariesReadHeader(
  summaries: typedListFromBridge(value.summaries),
);

PerformanceHistoryReadHeader historyReadHeaderFromBridge(
  native.BridgePerformanceHistoryReadHeader value,
) => PerformanceHistoryReadHeader(samples: typedListFromBridge(value.samples));

PerformanceSummaryRead summaryReadFromBridge(
  native.BridgePerformanceSummaryRead value,
) => PerformanceSummaryRead(
  identity: summaryIdentityRefFromBridge(value.identity),
  counters: performanceCountersFromBridge(value.counters),
  effortBreakdowns: typedListFromBridge(value.effortBreakdowns),
);

PerformanceEffortRead effortReadFromBridge(
  native.BridgePerformanceEffortRead value,
) => PerformanceEffortRead(
  identity: effortIdentityRefFromBridge(value.identity),
  counters: performanceCountersFromBridge(value.counters),
);

PerformanceSampleRead sampleReadFromBridge(
  native.BridgePerformanceSampleRead value,
) => PerformanceSampleRead(
  identity: sampleIdentityRefFromBridge(value.identity),
  counters: sampleCountersFromBridge(value.counters),
);

PerformanceSummaryIdentityRead summaryIdentityReadFromBridge(
  native.BridgePerformanceSummaryIdentityRead value,
) => PerformanceSummaryIdentityRead(
  accountId: readTextFromBridge(value.accountId),
  accountDisplayName: readTextFromBridge(value.accountDisplayName),
  modelId: readTextFromBridge(value.modelId),
);

PerformanceEffortIdentityRead effortIdentityReadFromBridge(
  native.BridgePerformanceEffortIdentityRead value,
) => PerformanceEffortIdentityRead(effort: nullableReadText(value.effort));

PerformanceSampleIdentityRead sampleIdentityReadFromBridge(
  native.BridgePerformanceSampleIdentityRead value,
) => PerformanceSampleIdentityRead(
  accountId: readTextFromBridge(value.accountId),
  accountDisplayName: readTextFromBridge(value.accountDisplayName),
  modelId: nullableReadText(value.modelId),
  sentModel: nullableReadText(value.sentModel),
  reportedModel: nullableReadText(value.reportedModel),
  modelMatchState: switch (value.modelMatchState) {
    native.BridgeModelMatchState.matched => ModelMatchState.matched,
    native.BridgeModelMatchState.mismatched => ModelMatchState.mismatched,
    native.BridgeModelMatchState.unreported => ModelMatchState.unreported,
    native.BridgeModelMatchState.legacyUnknown => ModelMatchState.legacyUnknown,
  },
  effort: nullableReadText(value.effort),
);
