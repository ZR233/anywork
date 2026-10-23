import 'package:anywork_client/account_usage_ports.dart';

import '../../../rust/api/studio/products/feed/performance_history.dart' as native;
import '../shared/bridge_failure.dart';
import '../shared/exact_numbers.dart';
import '../shared/read_converters.dart';
import 'identity_converters.dart';
import 'statistics_references.dart';

PerformanceHistoryHeader historyHeaderFromBridge(native.BridgePerformanceHistoryHeader value) => PerformanceHistoryHeader(
  revision: exactU64(value.revision, 'performance history revision'),
  updatedAt: exactI64(value.updatedAt, 'performance history updated Unix seconds'),
  statisticsPending: value.statisticsPending,
  statisticsGap: value.statisticsGap,
  readFailed: value.readFailed,
  reference: historyReadRefFromBridge(value.reference),
);

PerformanceHistoryBaseline historyBaselineFromBridge(native.BridgePerformanceHistoryBaseline value) => PerformanceHistoryBaseline(
  header: historyHeaderFromBridge(value.header),
  collection: value.collection == null ? null : collectionRefFromBridge(value.collection!),
);

PerformanceHistoryChange historyChangeFromBridge(native.BridgePerformanceHistoryChange value) => PerformanceHistoryChange(
  header: historyHeaderFromBridge(value.header),
  baseCollectionRevision: nullableU64(value.baseCollectionRevision, 'performance history base collection revision'),
  collection: value.collection == null ? null : collectionRefFromBridge(value.collection!),
  upserted: value.upserted.map(entityRefFromBridge).toList(growable: false),
  removedEntries: value.removedEntries.map((entry) => exactU64(entry, 'performance history removed entry')).toList(growable: false),
);

PerformanceHistoryEvent historyEventFromBridge(native.BridgePerformanceHistoryEvent value) => switch (value) {
  native.BridgePerformanceHistoryEvent_Baseline(:final identity, :final stamp, :final value) => PerformanceHistoryEvent.baseline(
    identity: productFeedIdentityFromBridge(identity), stamp: productStampFromBridge(stamp), value: historyBaselineFromBridge(value),
  ),
  native.BridgePerformanceHistoryEvent_Change(:final stamp, :final baseRevision, :final value) => PerformanceHistoryEvent.change(
    stamp: productStampFromBridge(stamp), baseRevision: exactU64(baseRevision, 'performance history base revision'), value: historyChangeFromBridge(value),
  ),
};

PerformanceHistoryFrame historyFrameFromBridge(native.BridgePerformanceHistoryFrame value) => switch (value) {
  native.BridgePerformanceHistoryFrame_Data(:final deliverySequence, :final event) => PerformanceHistoryFrame.data(
    deliverySequence: exactU64(deliverySequence, 'performance history delivery sequence'), event: historyEventFromBridge(event),
  ),
  native.BridgePerformanceHistoryFrame_ResyncRequired(:final identity, :final reason) => PerformanceHistoryFrame.resyncRequired(
    identity: productFeedIdentityFromBridge(identity), reason: productResyncFromBridge(reason),
  ),
  native.BridgePerformanceHistoryFrame_Failure(:final identity, :final error) => PerformanceHistoryFrame.failure(
    identity: productFeedIdentityFromBridge(identity), error: bridgeFailure(error),
  ),
  native.BridgePerformanceHistoryFrame_Closed(:final identity, :final reason) => PerformanceHistoryFrame.closed(
    identity: productFeedIdentityFromBridge(identity), reason: productClosedFromBridge(reason),
  ),
};
