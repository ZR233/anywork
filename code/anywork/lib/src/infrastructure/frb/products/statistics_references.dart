import 'package:anywork_client/account_usage.dart';

import '../../../rust/api/studio/products/references.dart' as native;
import '../shared/exact_numbers.dart';

PerformanceSummariesReadRef summariesReadRefFromBridge(
  native.BridgePerformanceSummariesReadRef value,
) => PerformanceSummariesReadRef(
  entry: exactU64(value.entry, 'performance summaries read entry'),
  revision: exactU64(value.revision, 'performance summaries read revision'),
);
PerformanceHistoryReadRef historyReadRefFromBridge(
  native.BridgePerformanceHistoryReadRef value,
) => PerformanceHistoryReadRef(
  entry: exactU64(value.entry, 'performance history read entry'),
  revision: exactU64(value.revision, 'performance history read revision'),
);
SessionCostsReadRef costsReadRefFromBridge(
  native.BridgeSessionCostsReadRef value,
) => SessionCostsReadRef(
  entry: exactU64(value.entry, 'session costs read entry'),
  revision: exactU64(value.revision, 'session costs read revision'),
);
PerformanceSummaryIdentityRef summaryIdentityRefFromBridge(
  native.BridgePerformanceSummaryIdentityRef value,
) => PerformanceSummaryIdentityRef(
  entry: exactU64(value.entry, 'performance summary identity entry'),
  revision: exactU64(value.revision, 'performance summary identity revision'),
);
PerformanceEffortIdentityRef effortIdentityRefFromBridge(
  native.BridgePerformanceEffortIdentityRef value,
) => PerformanceEffortIdentityRef(
  entry: exactU64(value.entry, 'performance effort identity entry'),
  revision: exactU64(value.revision, 'performance effort identity revision'),
);
PerformanceSampleIdentityRef sampleIdentityRefFromBridge(
  native.BridgePerformanceSampleIdentityRef value,
) => PerformanceSampleIdentityRef(
  entry: exactU64(value.entry, 'performance sample identity entry'),
  revision: exactU64(value.revision, 'performance sample identity revision'),
);

native.BridgePerformanceSummariesReadRef summariesReadRefToBridge(
  PerformanceSummariesReadRef value,
) => native.BridgePerformanceSummariesReadRef(
  entry: nativeU64(value.entry, 'performance summaries read entry'),
  revision: nativeU64(value.revision, 'performance summaries read revision'),
);
native.BridgePerformanceHistoryReadRef historyReadRefToBridge(
  PerformanceHistoryReadRef value,
) => native.BridgePerformanceHistoryReadRef(
  entry: nativeU64(value.entry, 'performance history read entry'),
  revision: nativeU64(value.revision, 'performance history read revision'),
);
native.BridgeSessionCostsReadRef costsReadRefToBridge(
  SessionCostsReadRef value,
) => native.BridgeSessionCostsReadRef(
  entry: nativeU64(value.entry, 'session costs read entry'),
  revision: nativeU64(value.revision, 'session costs read revision'),
);
native.BridgePerformanceSummaryIdentityRef summaryIdentityRefToBridge(
  PerformanceSummaryIdentityRef value,
) => native.BridgePerformanceSummaryIdentityRef(
  entry: nativeU64(value.entry, 'performance summary identity entry'),
  revision: nativeU64(value.revision, 'performance summary identity revision'),
);
native.BridgePerformanceEffortIdentityRef effortIdentityRefToBridge(
  PerformanceEffortIdentityRef value,
) => native.BridgePerformanceEffortIdentityRef(
  entry: nativeU64(value.entry, 'performance effort identity entry'),
  revision: nativeU64(value.revision, 'performance effort identity revision'),
);
native.BridgePerformanceSampleIdentityRef sampleIdentityRefToBridge(
  PerformanceSampleIdentityRef value,
) => native.BridgePerformanceSampleIdentityRef(
  entry: nativeU64(value.entry, 'performance sample identity entry'),
  revision: nativeU64(value.revision, 'performance sample identity revision'),
);
