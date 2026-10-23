import 'package:anywork_client/persistence_ports.dart';

import '../../../rust/api/studio/products/feed/persistence_queue.dart' as native;
import '../shared/bridge_failure.dart';
import '../shared/exact_numbers.dart';
import '../shared/read_converters.dart';
import 'identity_converters.dart';
import 'persistence_headers.dart';

PersistenceQueueBaseline persistenceQueueBaselineFromBridge(native.BridgePersistenceQueueBaseline value) => PersistenceQueueBaseline(
  header: persistenceQueueHeaderFromBridge(value.header),
  collection: value.collection == null ? null : collectionRefFromBridge(value.collection!),
);

PersistenceQueueChange persistenceQueueChangeFromBridge(native.BridgePersistenceQueueChange value) => PersistenceQueueChange(
  header: persistenceQueueHeaderFromBridge(value.header),
  baseCollectionRevision: nullableU64(value.baseCollectionRevision, 'persistence queue base collection revision'),
  collection: value.collection == null ? null : collectionRefFromBridge(value.collection!),
  upserted: value.upserted.map(entityRefFromBridge).toList(growable: false),
  removedEntries: value.removedEntries.map((entry) => exactU64(entry, 'persistence queue removed entry')).toList(growable: false),
);

PersistenceQueueEvent persistenceQueueEventFromBridge(native.BridgePersistenceQueueEvent value) => switch (value) {
  native.BridgePersistenceQueueEvent_Baseline(:final identity, :final stamp, :final value) => PersistenceQueueEvent.baseline(
    identity: productFeedIdentityFromBridge(identity), stamp: productStampFromBridge(stamp), value: persistenceQueueBaselineFromBridge(value),
  ),
  native.BridgePersistenceQueueEvent_Change(:final stamp, :final baseRevision, :final value) => PersistenceQueueEvent.change(
    stamp: productStampFromBridge(stamp), baseRevision: exactU64(baseRevision, 'persistence queue base revision'), value: persistenceQueueChangeFromBridge(value),
  ),
};

PersistenceQueueFrame persistenceQueueFrameFromBridge(native.BridgePersistenceQueueFrame value) => switch (value) {
  native.BridgePersistenceQueueFrame_Data(:final deliverySequence, :final event) => PersistenceQueueFrame.data(
    deliverySequence: exactU64(deliverySequence, 'persistence queue delivery sequence'), event: persistenceQueueEventFromBridge(event),
  ),
  native.BridgePersistenceQueueFrame_ResyncRequired(:final identity, :final reason) => PersistenceQueueFrame.resyncRequired(
    identity: productFeedIdentityFromBridge(identity), reason: productResyncFromBridge(reason),
  ),
  native.BridgePersistenceQueueFrame_Failure(:final identity, :final error) => PersistenceQueueFrame.failure(
    identity: productFeedIdentityFromBridge(identity), error: bridgeFailure(error),
  ),
  native.BridgePersistenceQueueFrame_Closed(:final identity, :final reason) => PersistenceQueueFrame.closed(
    identity: productFeedIdentityFromBridge(identity), reason: productClosedFromBridge(reason),
  ),
};
