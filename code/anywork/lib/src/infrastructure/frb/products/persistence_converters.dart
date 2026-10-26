import 'package:anywork_client/persistence_ports.dart';

import '../../../rust/api/studio/products/feed/persistence.dart' as native;
import '../shared/bridge_failure.dart';
import '../shared/exact_numbers.dart';
import 'identity_converters.dart';
import 'persistence_headers.dart';

PersistenceEvent persistenceEventFromBridge(
  native.BridgePersistenceEvent value,
) => switch (value) {
  native.BridgePersistenceEvent_Baseline(
    :final identity,
    :final stamp,
    :final value,
  ) =>
    PersistenceEvent.baseline(
      identity: productFeedIdentityFromBridge(identity),
      stamp: productStampFromBridge(stamp),
      value: persistenceHeaderFromBridge(value),
    ),
  native.BridgePersistenceEvent_Replace(
    :final stamp,
    :final baseRevision,
    :final value,
  ) =>
    PersistenceEvent.replace(
      stamp: productStampFromBridge(stamp),
      baseRevision: exactU64(baseRevision, 'persistence base revision'),
      value: persistenceHeaderFromBridge(value),
    ),
};

PersistenceFrame persistenceFrameFromBridge(
  native.BridgePersistenceFrame value,
) => switch (value) {
  native.BridgePersistenceFrame_Data(:final deliverySequence, :final event) =>
    PersistenceFrame.data(
      deliverySequence: exactU64(
        deliverySequence,
        'persistence delivery sequence',
      ),
      event: persistenceEventFromBridge(event),
    ),
  native.BridgePersistenceFrame_ResyncRequired(
    :final identity,
    :final reason,
  ) =>
    PersistenceFrame.resyncRequired(
      identity: productFeedIdentityFromBridge(identity),
      reason: productResyncFromBridge(reason),
    ),
  native.BridgePersistenceFrame_Failure(:final identity, :final error) =>
    PersistenceFrame.failure(
      identity: productFeedIdentityFromBridge(identity),
      error: bridgeFailure(error),
    ),
  native.BridgePersistenceFrame_Closed(:final identity, :final reason) =>
    PersistenceFrame.closed(
      identity: productFeedIdentityFromBridge(identity),
      reason: productClosedFromBridge(reason),
    ),
};
