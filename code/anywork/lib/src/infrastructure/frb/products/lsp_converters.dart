import 'package:anywork_client/lsp_ports.dart';

import '../../../rust/api/studio/products/feed/lsp.dart' as native;
import '../shared/bridge_failure.dart';
import '../shared/exact_numbers.dart';
import '../shared/read_converters.dart';
import 'identity_converters.dart';
import 'resource_headers.dart';

LspBaseline lspBaselineFromBridge(native.BridgeLspBaseline value) =>
    LspBaseline(
      header: lspHeaderFromBridge(value.header),
      collection: value.collection == null
          ? null
          : collectionRefFromBridge(value.collection!),
    );

LspChange lspChangeFromBridge(native.BridgeLspChange value) => LspChange(
  header: lspHeaderFromBridge(value.header),
  baseCollectionRevision: nullableU64(
    value.baseCollectionRevision,
    'LSP base collection revision',
  ),
  collection: value.collection == null
      ? null
      : collectionRefFromBridge(value.collection!),
  upserted: value.upserted.map(entityRefFromBridge).toList(growable: false),
  removedEntries: value.removedEntries
      .map((entry) => exactU64(entry, 'LSP removed entry'))
      .toList(growable: false),
);

LspEvent lspEventFromBridge(native.BridgeLspEvent value) => switch (value) {
  native.BridgeLspEvent_Baseline(:final identity, :final stamp, :final value) =>
    LspEvent.baseline(
      identity: productFeedIdentityFromBridge(identity),
      stamp: productStampFromBridge(stamp),
      value: lspBaselineFromBridge(value),
    ),
  native.BridgeLspEvent_Change(
    :final stamp,
    :final baseRevision,
    :final value,
  ) =>
    LspEvent.change(
      stamp: productStampFromBridge(stamp),
      baseRevision: exactU64(baseRevision, 'LSP base revision'),
      value: lspChangeFromBridge(value),
    ),
};

LspFrame lspFrameFromBridge(native.BridgeLspFrame value) => switch (value) {
  native.BridgeLspFrame_Data(:final deliverySequence, :final event) =>
    LspFrame.data(
      deliverySequence: exactU64(deliverySequence, 'LSP delivery sequence'),
      event: lspEventFromBridge(event),
    ),
  native.BridgeLspFrame_ResyncRequired(:final identity, :final reason) =>
    LspFrame.resyncRequired(
      identity: productFeedIdentityFromBridge(identity),
      reason: productResyncFromBridge(reason),
    ),
  native.BridgeLspFrame_Failure(:final identity, :final error) =>
    LspFrame.failure(
      identity: productFeedIdentityFromBridge(identity),
      error: bridgeFailure(error),
    ),
  native.BridgeLspFrame_Closed(:final identity, :final reason) =>
    LspFrame.closed(
      identity: productFeedIdentityFromBridge(identity),
      reason: productClosedFromBridge(reason),
    ),
};
