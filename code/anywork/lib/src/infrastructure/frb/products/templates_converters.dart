import 'package:anywork_client/models_ports.dart';

import '../../../rust/api/studio/products/feed/account_templates.dart' as native;
import '../shared/bridge_failure.dart';
import '../shared/exact_numbers.dart';
import '../shared/read_converters.dart';
import 'catalog_references.dart';
import 'identity_converters.dart';

AccountTemplatesHeader templatesHeaderFromBridge(native.BridgeAccountTemplatesHeader value) => AccountTemplatesHeader(
  schemaVersion: value.schemaVersion,
  reference: templatesReadRefFromBridge(value.reference),
);

AccountTemplatesBaseline templatesBaselineFromBridge(native.BridgeAccountTemplatesBaseline value) => AccountTemplatesBaseline(
  header: templatesHeaderFromBridge(value.header),
  collection: value.collection == null ? null : collectionRefFromBridge(value.collection!),
);

AccountTemplatesChange templatesChangeFromBridge(native.BridgeAccountTemplatesChange value) => AccountTemplatesChange(
  header: templatesHeaderFromBridge(value.header),
  baseCollectionRevision: nullableU64(value.baseCollectionRevision, 'templates base collection revision'),
  collection: value.collection == null ? null : collectionRefFromBridge(value.collection!),
  upserted: value.upserted.map(entityRefFromBridge).toList(growable: false),
  removedEntries: value.removedEntries.map((entry) => exactU64(entry, 'templates removed entry')).toList(growable: false),
);

AccountTemplatesEvent templatesEventFromBridge(native.BridgeAccountTemplatesEvent value) => switch (value) {
  native.BridgeAccountTemplatesEvent_Baseline(:final identity, :final stamp, :final value) => AccountTemplatesEvent.baseline(
    identity: productFeedIdentityFromBridge(identity), stamp: productStampFromBridge(stamp), value: templatesBaselineFromBridge(value),
  ),
  native.BridgeAccountTemplatesEvent_Change(:final stamp, :final baseRevision, :final value) => AccountTemplatesEvent.change(
    stamp: productStampFromBridge(stamp), baseRevision: exactU64(baseRevision, 'templates base revision'), value: templatesChangeFromBridge(value),
  ),
};

AccountTemplatesFrame templatesFrameFromBridge(native.BridgeAccountTemplatesFrame value) => switch (value) {
  native.BridgeAccountTemplatesFrame_Data(:final deliverySequence, :final event) => AccountTemplatesFrame.data(
    deliverySequence: exactU64(deliverySequence, 'templates delivery sequence'), event: templatesEventFromBridge(event),
  ),
  native.BridgeAccountTemplatesFrame_ResyncRequired(:final identity, :final reason) => AccountTemplatesFrame.resyncRequired(
    identity: productFeedIdentityFromBridge(identity), reason: productResyncFromBridge(reason),
  ),
  native.BridgeAccountTemplatesFrame_Failure(:final identity, :final error) => AccountTemplatesFrame.failure(
    identity: productFeedIdentityFromBridge(identity), error: bridgeFailure(error),
  ),
  native.BridgeAccountTemplatesFrame_Closed(:final identity, :final reason) => AccountTemplatesFrame.closed(
    identity: productFeedIdentityFromBridge(identity), reason: productClosedFromBridge(reason),
  ),
};
