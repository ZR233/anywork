import 'package:anywork_client/models_ports.dart';

import '../../../rust/api/studio/products/feed/model_catalog.dart' as native;
import '../shared/bridge_failure.dart';
import '../shared/exact_numbers.dart';
import '../shared/read_converters.dart';
import 'catalog_references.dart';
import 'identity_converters.dart';
import 'source_converters.dart';

ModelCatalogHeader modelCatalogHeaderFromBridge(native.BridgeModelCatalogHeader value) => ModelCatalogHeader(
  source: observedHeaderFromBridge(value.source),
  catalogRevision: nullableU64(value.catalogRevision, 'model catalog revision'),
  updatedAt: nullableI64(value.updatedAt, 'model catalog updated Unix seconds'),
  reference: value.reference == null ? null : modelCatalogReadRefFromBridge(value.reference!),
);

ModelCatalogBaseline modelCatalogBaselineFromBridge(native.BridgeModelCatalogBaseline value) => ModelCatalogBaseline(
  header: modelCatalogHeaderFromBridge(value.header),
  collection: value.collection == null ? null : collectionRefFromBridge(value.collection!),
);

ModelCatalogChange modelCatalogChangeFromBridge(native.BridgeModelCatalogChange value) => ModelCatalogChange(
  header: modelCatalogHeaderFromBridge(value.header),
  baseCollectionRevision: nullableU64(value.baseCollectionRevision, 'model catalog base collection revision'),
  collection: value.collection == null ? null : collectionRefFromBridge(value.collection!),
  upserted: value.upserted.map(entityRefFromBridge).toList(growable: false),
  removedEntries: value.removedEntries.map((entry) => exactU64(entry, 'model catalog removed entry')).toList(growable: false),
);

ModelCatalogEvent modelCatalogEventFromBridge(native.BridgeModelCatalogEvent value) => switch (value) {
  native.BridgeModelCatalogEvent_Baseline(:final identity, :final stamp, :final value) => ModelCatalogEvent.baseline(
    identity: productFeedIdentityFromBridge(identity), stamp: productStampFromBridge(stamp), value: modelCatalogBaselineFromBridge(value),
  ),
  native.BridgeModelCatalogEvent_Change(:final stamp, :final baseRevision, :final value) => ModelCatalogEvent.change(
    stamp: productStampFromBridge(stamp), baseRevision: exactU64(baseRevision, 'model catalog base revision'), value: modelCatalogChangeFromBridge(value),
  ),
};

ModelCatalogFrame modelCatalogFrameFromBridge(native.BridgeModelCatalogFrame value) => switch (value) {
  native.BridgeModelCatalogFrame_Data(:final deliverySequence, :final event) => ModelCatalogFrame.data(
    deliverySequence: exactU64(deliverySequence, 'model catalog delivery sequence'), event: modelCatalogEventFromBridge(event),
  ),
  native.BridgeModelCatalogFrame_ResyncRequired(:final identity, :final reason) => ModelCatalogFrame.resyncRequired(
    identity: productFeedIdentityFromBridge(identity), reason: productResyncFromBridge(reason),
  ),
  native.BridgeModelCatalogFrame_Failure(:final identity, :final error) => ModelCatalogFrame.failure(
    identity: productFeedIdentityFromBridge(identity), error: bridgeFailure(error),
  ),
  native.BridgeModelCatalogFrame_Closed(:final identity, :final reason) => ModelCatalogFrame.closed(
    identity: productFeedIdentityFromBridge(identity), reason: productClosedFromBridge(reason),
  ),
};
