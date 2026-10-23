import 'package:anywork_client/account_usage_ports.dart';

import '../../../rust/api/studio/products/feed/performance_summaries.dart' as native;
import '../shared/bridge_failure.dart';
import '../shared/exact_numbers.dart';
import '../shared/read_converters.dart';
import 'identity_converters.dart';
import 'statistics_references.dart';

PerformanceSummariesHeader summariesHeaderFromBridge(native.BridgePerformanceSummariesHeader value) => PerformanceSummariesHeader(
  revision: exactU64(value.revision, 'performance summaries revision'),
  updatedAt: exactI64(value.updatedAt, 'performance summaries updated Unix seconds'),
  statisticsPending: value.statisticsPending,
  statisticsGap: value.statisticsGap,
  readFailed: value.readFailed,
  reference: summariesReadRefFromBridge(value.reference),
);

PerformanceSummariesBaseline summariesBaselineFromBridge(native.BridgePerformanceSummariesBaseline value) => PerformanceSummariesBaseline(
  header: summariesHeaderFromBridge(value.header),
  collection: value.collection == null ? null : collectionRefFromBridge(value.collection!),
);

PerformanceSummariesChange summariesChangeFromBridge(native.BridgePerformanceSummariesChange value) => PerformanceSummariesChange(
  header: summariesHeaderFromBridge(value.header),
  baseCollectionRevision: nullableU64(value.baseCollectionRevision, 'performance summaries base collection revision'),
  collection: value.collection == null ? null : collectionRefFromBridge(value.collection!),
  upserted: value.upserted.map(entityRefFromBridge).toList(growable: false),
  removedEntries: value.removedEntries.map((entry) => exactU64(entry, 'performance summaries removed entry')).toList(growable: false),
);

PerformanceSummariesEvent summariesEventFromBridge(native.BridgePerformanceSummariesEvent value) => switch (value) {
  native.BridgePerformanceSummariesEvent_Baseline(:final identity, :final stamp, :final value) => PerformanceSummariesEvent.baseline(
    identity: productFeedIdentityFromBridge(identity), stamp: productStampFromBridge(stamp), value: summariesBaselineFromBridge(value),
  ),
  native.BridgePerformanceSummariesEvent_Change(:final stamp, :final baseRevision, :final value) => PerformanceSummariesEvent.change(
    stamp: productStampFromBridge(stamp), baseRevision: exactU64(baseRevision, 'performance summaries base revision'), value: summariesChangeFromBridge(value),
  ),
};

PerformanceSummariesFrame summariesFrameFromBridge(native.BridgePerformanceSummariesFrame value) => switch (value) {
  native.BridgePerformanceSummariesFrame_Data(:final deliverySequence, :final event) => PerformanceSummariesFrame.data(
    deliverySequence: exactU64(deliverySequence, 'performance summaries delivery sequence'), event: summariesEventFromBridge(event),
  ),
  native.BridgePerformanceSummariesFrame_ResyncRequired(:final identity, :final reason) => PerformanceSummariesFrame.resyncRequired(
    identity: productFeedIdentityFromBridge(identity), reason: productResyncFromBridge(reason),
  ),
  native.BridgePerformanceSummariesFrame_Failure(:final identity, :final error) => PerformanceSummariesFrame.failure(
    identity: productFeedIdentityFromBridge(identity), error: bridgeFailure(error),
  ),
  native.BridgePerformanceSummariesFrame_Closed(:final identity, :final reason) => PerformanceSummariesFrame.closed(
    identity: productFeedIdentityFromBridge(identity), reason: productClosedFromBridge(reason),
  ),
};
