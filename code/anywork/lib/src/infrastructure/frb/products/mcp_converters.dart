import 'package:anywork_client/mcp_ports.dart';

import '../../../rust/api/studio/products/feed/mcp.dart' as native;
import '../shared/bridge_failure.dart';
import '../shared/exact_numbers.dart';
import '../shared/read_converters.dart';
import 'identity_converters.dart';
import 'resource_headers.dart';

McpBaseline mcpBaselineFromBridge(native.BridgeMcpBaseline value) =>
    McpBaseline(
      header: mcpHeaderFromBridge(value.header),
      collection: value.collection == null
          ? null
          : collectionRefFromBridge(value.collection!),
    );

McpChange mcpChangeFromBridge(native.BridgeMcpChange value) => McpChange(
  header: mcpHeaderFromBridge(value.header),
  baseCollectionRevision: nullableU64(
    value.baseCollectionRevision,
    'MCP base collection revision',
  ),
  collection: value.collection == null
      ? null
      : collectionRefFromBridge(value.collection!),
  upserted: value.upserted.map(entityRefFromBridge).toList(growable: false),
  removedEntries: value.removedEntries
      .map((entry) => exactU64(entry, 'MCP removed entry'))
      .toList(growable: false),
);

McpEvent mcpEventFromBridge(native.BridgeMcpEvent value) => switch (value) {
  native.BridgeMcpEvent_Baseline(:final identity, :final stamp, :final value) =>
    McpEvent.baseline(
      identity: productFeedIdentityFromBridge(identity),
      stamp: productStampFromBridge(stamp),
      value: mcpBaselineFromBridge(value),
    ),
  native.BridgeMcpEvent_Change(
    :final stamp,
    :final baseRevision,
    :final value,
  ) =>
    McpEvent.change(
      stamp: productStampFromBridge(stamp),
      baseRevision: exactU64(baseRevision, 'MCP base revision'),
      value: mcpChangeFromBridge(value),
    ),
};

McpFrame mcpFrameFromBridge(native.BridgeMcpFrame value) => switch (value) {
  native.BridgeMcpFrame_Data(:final deliverySequence, :final event) =>
    McpFrame.data(
      deliverySequence: exactU64(deliverySequence, 'MCP delivery sequence'),
      event: mcpEventFromBridge(event),
    ),
  native.BridgeMcpFrame_ResyncRequired(:final identity, :final reason) =>
    McpFrame.resyncRequired(
      identity: productFeedIdentityFromBridge(identity),
      reason: productResyncFromBridge(reason),
    ),
  native.BridgeMcpFrame_Failure(:final identity, :final error) =>
    McpFrame.failure(
      identity: productFeedIdentityFromBridge(identity),
      error: bridgeFailure(error),
    ),
  native.BridgeMcpFrame_Closed(:final identity, :final reason) =>
    McpFrame.closed(
      identity: productFeedIdentityFromBridge(identity),
      reason: productClosedFromBridge(reason),
    ),
};
