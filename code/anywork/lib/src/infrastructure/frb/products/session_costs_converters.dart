import 'package:anywork_client/account_usage_ports.dart';

import '../../../rust/api/studio/products/feed/session_costs.dart' as native;
import '../shared/bridge_failure.dart';
import '../shared/exact_numbers.dart';
import 'identity_converters.dart';
import 'statistics_references.dart';

SessionCostsHeader costsHeaderFromBridge(
  native.BridgeSessionCostsHeader value,
) => SessionCostsHeader(
  revision: exactU64(value.revision, 'session costs revision'),
  updatedAt: exactI64(
    BigInt.from(value.updatedAt),
    'session costs updated Unix seconds',
  ),
  statisticsPending: value.statisticsPending,
  statisticsGap: value.statisticsGap,
  readFailed: value.readFailed,
  hasCost: value.hasCost,
  hasUnpricedUsage: value.hasUnpricedUsage,
  reference: costsReadRefFromBridge(value.reference),
);

SessionCostsEvent costsEventFromBridge(native.BridgeSessionCostsEvent value) =>
    switch (value) {
      native.BridgeSessionCostsEvent_Baseline(
        :final identity,
        :final stamp,
        :final value,
      ) =>
        SessionCostsEvent.baseline(
          identity: productFeedIdentityFromBridge(identity),
          stamp: productStampFromBridge(stamp),
          value: costsHeaderFromBridge(value),
        ),
      native.BridgeSessionCostsEvent_Replace(
        :final stamp,
        :final baseRevision,
        :final value,
      ) =>
        SessionCostsEvent.replace(
          stamp: productStampFromBridge(stamp),
          baseRevision: exactU64(baseRevision, 'session costs base revision'),
          value: costsHeaderFromBridge(value),
        ),
    };

SessionCostsFrame costsFrameFromBridge(native.BridgeSessionCostsFrame value) =>
    switch (value) {
      native.BridgeSessionCostsFrame_Data(
        :final deliverySequence,
        :final event,
      ) =>
        SessionCostsFrame.data(
          deliverySequence: exactU64(
            deliverySequence,
            'session costs delivery sequence',
          ),
          event: costsEventFromBridge(event),
        ),
      native.BridgeSessionCostsFrame_ResyncRequired(
        :final identity,
        :final reason,
      ) =>
        SessionCostsFrame.resyncRequired(
          identity: productFeedIdentityFromBridge(identity),
          reason: productResyncFromBridge(reason),
        ),
      native.BridgeSessionCostsFrame_Failure(:final identity, :final error) =>
        SessionCostsFrame.failure(
          identity: productFeedIdentityFromBridge(identity),
          error: bridgeFailure(error),
        ),
      native.BridgeSessionCostsFrame_Closed(:final identity, :final reason) =>
        SessionCostsFrame.closed(
          identity: productFeedIdentityFromBridge(identity),
          reason: productClosedFromBridge(reason),
        ),
    };
