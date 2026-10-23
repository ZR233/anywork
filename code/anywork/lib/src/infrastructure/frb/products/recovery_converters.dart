import 'package:anywork_client/recovery_ports.dart';

import '../../../rust/api/studio/products/feed/recovery.dart' as native;
import '../shared/bridge_failure.dart';
import '../shared/exact_numbers.dart';
import '../shared/read_converters.dart';
import 'identity_converters.dart';
import 'resource_references.dart';
import 'source_converters.dart';

RecoveryHeader recoveryHeaderFromBridge(native.BridgeRecoveryHeader value) => RecoveryHeader(
  source: observedHeaderFromBridge(value.source),
  reference: value.reference == null ? null : recoveryReadRefFromBridge(value.reference!),
);

RecoveryBaseline recoveryBaselineFromBridge(native.BridgeRecoveryBaseline value) => RecoveryBaseline(
  header: recoveryHeaderFromBridge(value.header),
  collection: value.collection == null ? null : collectionRefFromBridge(value.collection!),
);

RecoveryChange recoveryChangeFromBridge(native.BridgeRecoveryChange value) => RecoveryChange(
  header: recoveryHeaderFromBridge(value.header),
  baseCollectionRevision: nullableU64(value.baseCollectionRevision, 'recovery base collection revision'),
  collection: value.collection == null ? null : collectionRefFromBridge(value.collection!),
  upserted: value.upserted.map(entityRefFromBridge).toList(growable: false),
  removedEntries: value.removedEntries.map((entry) => exactU64(entry, 'recovery removed entry')).toList(growable: false),
);

RecoveryEvent recoveryEventFromBridge(native.BridgeRecoveryEvent value) => switch (value) {
  native.BridgeRecoveryEvent_Baseline(:final identity, :final stamp, :final value) => RecoveryEvent.baseline(
    identity: productFeedIdentityFromBridge(identity), stamp: productStampFromBridge(stamp), value: recoveryBaselineFromBridge(value),
  ),
  native.BridgeRecoveryEvent_Change(:final stamp, :final baseRevision, :final value) => RecoveryEvent.change(
    stamp: productStampFromBridge(stamp), baseRevision: exactU64(baseRevision, 'recovery base revision'), value: recoveryChangeFromBridge(value),
  ),
};

RecoveryFrame recoveryFrameFromBridge(native.BridgeRecoveryFrame value) => switch (value) {
  native.BridgeRecoveryFrame_Data(:final deliverySequence, :final event) => RecoveryFrame.data(
    deliverySequence: exactU64(deliverySequence, 'recovery delivery sequence'), event: recoveryEventFromBridge(event),
  ),
  native.BridgeRecoveryFrame_ResyncRequired(:final identity, :final reason) => RecoveryFrame.resyncRequired(
    identity: productFeedIdentityFromBridge(identity), reason: productResyncFromBridge(reason),
  ),
  native.BridgeRecoveryFrame_Failure(:final identity, :final error) => RecoveryFrame.failure(
    identity: productFeedIdentityFromBridge(identity), error: bridgeFailure(error),
  ),
  native.BridgeRecoveryFrame_Closed(:final identity, :final reason) => RecoveryFrame.closed(
    identity: productFeedIdentityFromBridge(identity), reason: productClosedFromBridge(reason),
  ),
};
