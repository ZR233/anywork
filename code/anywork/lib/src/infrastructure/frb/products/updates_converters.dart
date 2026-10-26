import 'package:anywork_client/updates_ports.dart';

import '../../../rust/api/studio/products/feed/updates.dart' as native;
import '../shared/bridge_failure.dart';
import '../shared/exact_numbers.dart';
import 'identity_converters.dart';
import 'update_headers.dart';

UpdatesEvent updatesEventFromBridge(native.BridgeUpdatesEvent value) =>
    switch (value) {
      native.BridgeUpdatesEvent_Baseline(
        :final identity,
        :final stamp,
        :final value,
      ) =>
        UpdatesEvent.baseline(
          identity: productFeedIdentityFromBridge(identity),
          stamp: productStampFromBridge(stamp),
          value: updatesHeaderFromBridge(value),
        ),
      native.BridgeUpdatesEvent_Replace(
        :final stamp,
        :final baseRevision,
        :final value,
      ) =>
        UpdatesEvent.replace(
          stamp: productStampFromBridge(stamp),
          baseRevision: exactU64(baseRevision, 'updates base revision'),
          value: updatesHeaderFromBridge(value),
        ),
    };

UpdatesFrame updatesFrameFromBridge(
  native.BridgeUpdatesFrame value,
) => switch (value) {
  native.BridgeUpdatesFrame_Data(:final deliverySequence, :final event) =>
    UpdatesFrame.data(
      deliverySequence: exactU64(deliverySequence, 'updates delivery sequence'),
      event: updatesEventFromBridge(event),
    ),
  native.BridgeUpdatesFrame_ResyncRequired(:final identity, :final reason) =>
    UpdatesFrame.resyncRequired(
      identity: productFeedIdentityFromBridge(identity),
      reason: productResyncFromBridge(reason),
    ),
  native.BridgeUpdatesFrame_Failure(:final identity, :final error) =>
    UpdatesFrame.failure(
      identity: productFeedIdentityFromBridge(identity),
      error: bridgeFailure(error),
    ),
  native.BridgeUpdatesFrame_Closed(:final identity, :final reason) =>
    UpdatesFrame.closed(
      identity: productFeedIdentityFromBridge(identity),
      reason: productClosedFromBridge(reason),
    ),
};
