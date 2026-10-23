import 'package:anywork_client/modes_ports.dart';

import '../../../rust/api/studio/products/feed/mode_catalog.dart' as native;
import '../shared/bridge_failure.dart';
import '../shared/exact_numbers.dart';
import '../shared/read_converters.dart';
import 'catalog_references.dart';
import 'identity_converters.dart';

ModeCatalogHeader modeCatalogHeaderFromBridge(native.BridgeModeCatalogHeader value) => ModeCatalogHeader(
  revision: exactU64(value.revision, 'Mode catalog revision'),
  reference: modeCatalogReadRefFromBridge(value.reference),
);

ModeCatalogBaseline modeCatalogBaselineFromBridge(native.BridgeModeCatalogBaseline value) => ModeCatalogBaseline(
  header: modeCatalogHeaderFromBridge(value.header),
  collection: value.collection == null ? null : collectionRefFromBridge(value.collection!),
);

ModeCatalogChange modeCatalogChangeFromBridge(native.BridgeModeCatalogChange value) => ModeCatalogChange(
  header: modeCatalogHeaderFromBridge(value.header),
  baseCollectionRevision: nullableU64(value.baseCollectionRevision, 'Mode catalog base collection revision'),
  collection: value.collection == null ? null : collectionRefFromBridge(value.collection!),
  upserted: value.upserted.map(entityRefFromBridge).toList(growable: false),
  removedEntries: value.removedEntries.map((entry) => exactU64(entry, 'Mode catalog removed entry')).toList(growable: false),
);

ModeCatalogEvent modeCatalogEventFromBridge(native.BridgeModeCatalogEvent value) => switch (value) {
  native.BridgeModeCatalogEvent_Baseline(:final identity, :final stamp, :final value) => ModeCatalogEvent.baseline(
    identity: productFeedIdentityFromBridge(identity), stamp: productStampFromBridge(stamp), value: modeCatalogBaselineFromBridge(value),
  ),
  native.BridgeModeCatalogEvent_Change(:final stamp, :final baseRevision, :final value) => ModeCatalogEvent.change(
    stamp: productStampFromBridge(stamp), baseRevision: exactU64(baseRevision, 'Mode catalog base revision'), value: modeCatalogChangeFromBridge(value),
  ),
};

ModeCatalogFrame modeCatalogFrameFromBridge(native.BridgeModeCatalogFrame value) => switch (value) {
  native.BridgeModeCatalogFrame_Data(:final deliverySequence, :final event) => ModeCatalogFrame.data(
    deliverySequence: exactU64(deliverySequence, 'Mode catalog delivery sequence'), event: modeCatalogEventFromBridge(event),
  ),
  native.BridgeModeCatalogFrame_ResyncRequired(:final identity, :final reason) => ModeCatalogFrame.resyncRequired(
    identity: productFeedIdentityFromBridge(identity), reason: productResyncFromBridge(reason),
  ),
  native.BridgeModeCatalogFrame_Failure(:final identity, :final error) => ModeCatalogFrame.failure(
    identity: productFeedIdentityFromBridge(identity), error: bridgeFailure(error),
  ),
  native.BridgeModeCatalogFrame_Closed(:final identity, :final reason) => ModeCatalogFrame.closed(
    identity: productFeedIdentityFromBridge(identity), reason: productClosedFromBridge(reason),
  ),
};
