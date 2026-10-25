import 'package:anywork_client/account_usage_ports.dart';

import '../../../rust/api/studio/products/feed/account_usage.dart' as native;
import '../shared/bridge_failure.dart';
import '../shared/exact_numbers.dart';
import '../shared/read_converters.dart';
import 'catalog_references.dart';
import 'identity_converters.dart';
import 'source_converters.dart';

AccountUsageHeader accountUsageHeaderFromBridge(
  native.BridgeAccountUsageHeader value,
) => AccountUsageHeader(
  source: observedHeaderFromBridge(value.source),
  reference: value.reference == null
      ? null
      : accountUsageReadRefFromBridge(value.reference!),
);

AccountUsageBaseline accountUsageBaselineFromBridge(
  native.BridgeAccountUsageBaseline value,
) => AccountUsageBaseline(
  header: accountUsageHeaderFromBridge(value.header),
  collection: value.collection == null
      ? null
      : collectionRefFromBridge(value.collection!),
);

AccountUsageChange accountUsageChangeFromBridge(
  native.BridgeAccountUsageChange value,
) => AccountUsageChange(
  header: accountUsageHeaderFromBridge(value.header),
  baseCollectionRevision: nullableU64(
    value.baseCollectionRevision,
    'account usage base collection revision',
  ),
  collection: value.collection == null
      ? null
      : collectionRefFromBridge(value.collection!),
  upserted: value.upserted.map(entityRefFromBridge).toList(growable: false),
  removedEntries: value.removedEntries
      .map((entry) => exactU64(entry, 'account usage removed entry'))
      .toList(growable: false),
);

AccountUsageEvent accountUsageEventFromBridge(
  native.BridgeAccountUsageEvent value,
) => switch (value) {
  native.BridgeAccountUsageEvent_Baseline(
    :final identity,
    :final stamp,
    :final value,
  ) =>
    AccountUsageEvent.baseline(
      identity: productFeedIdentityFromBridge(identity),
      stamp: productStampFromBridge(stamp),
      value: accountUsageBaselineFromBridge(value),
    ),
  native.BridgeAccountUsageEvent_Change(
    :final stamp,
    :final baseRevision,
    :final value,
  ) =>
    AccountUsageEvent.change(
      stamp: productStampFromBridge(stamp),
      baseRevision: exactU64(baseRevision, 'account usage base revision'),
      value: accountUsageChangeFromBridge(value),
    ),
};

AccountUsageFrame accountUsageFrameFromBridge(
  native.BridgeAccountUsageFrame value,
) => switch (value) {
  native.BridgeAccountUsageFrame_Data(:final deliverySequence, :final event) =>
    AccountUsageFrame.data(
      deliverySequence: exactU64(
        deliverySequence,
        'account usage delivery sequence',
      ),
      event: accountUsageEventFromBridge(event),
    ),
  native.BridgeAccountUsageFrame_ResyncRequired(
    :final identity,
    :final reason,
  ) =>
    AccountUsageFrame.resyncRequired(
      identity: productFeedIdentityFromBridge(identity),
      reason: productResyncFromBridge(reason),
    ),
  native.BridgeAccountUsageFrame_Failure(:final identity, :final error) =>
    AccountUsageFrame.failure(
      identity: productFeedIdentityFromBridge(identity),
      error: bridgeFailure(error),
    ),
  native.BridgeAccountUsageFrame_Closed(:final identity, :final reason) =>
    AccountUsageFrame.closed(
      identity: productFeedIdentityFromBridge(identity),
      reason: productClosedFromBridge(reason),
    ),
};
