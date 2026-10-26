import 'package:anywork_client/mcp_ports.dart';

import '../../../../rust/api/studio/products/read/mcp.dart' as native;
import '../../shared/exact_numbers.dart';
import '../../shared/read_converters.dart';
import '../identity_converters.dart';
import '../source_converters.dart';

McpReadHeader mcpReadHeaderFromBridge(
  native.BridgeMcpReadHeader value,
) => McpReadHeader(
  desiredConfigFingerprint: readTextFromBridge(value.desiredConfigFingerprint),
  appliedConfigFingerprint: readTextFromBridge(value.appliedConfigFingerprint),
  health: McpHealthRead(
    mcpServers: typedListFromBridge(value.health.mcpServers),
    activeMcpServers: typedListFromBridge(value.health.activeMcpServers),
  ),
);

McpServerStateRead mcpServerStateFromBridge(
  native.BridgeMcpServerStateRead value,
) => switch (value) {
  native.BridgeMcpServerStateRead_Disabled(:final message) =>
    McpServerStateRead.disabled(message: readTextFromBridge(message)),
  native.BridgeMcpServerStateRead_MissingCredential(:final message) =>
    McpServerStateRead.missingCredential(message: readTextFromBridge(message)),
  native.BridgeMcpServerStateRead_Checking(:final message) =>
    McpServerStateRead.checking(message: readTextFromBridge(message)),
  native.BridgeMcpServerStateRead_Available(
    :final checkedAt,
    :final toolCount,
  ) =>
    McpServerStateRead.available(
      checkedAt: exactI64(BigInt.from(checkedAt), 'MCP checked Unix seconds'),
      toolCount: exactU64(toolCount, 'MCP tool count'),
    ),
  native.BridgeMcpServerStateRead_Unavailable(:final checkedAt, :final error) =>
    McpServerStateRead.unavailable(
      checkedAt: exactI64(BigInt.from(checkedAt), 'MCP checked Unix seconds'),
      error: sourceErrorReadFromBridge(error),
    ),
};

McpServerRead mcpServerReadFromBridge(native.BridgeMcpServerRead value) =>
    McpServerRead(
      id: readTextFromBridge(value.id),
      transport: readTextFromBridge(value.transport),
      endpoint: readTextFromBridge(value.endpoint),
      sourceKind: readTextFromBridge(value.sourceKind),
      mutationPolicy: readTextFromBridge(value.mutationPolicy),
      state: mcpServerStateFromBridge(value.state),
    );

McpEntityRead mcpEntityFromBridge(native.BridgeMcpEntityRead value) =>
    McpEntityRead(
      reference: entityRefFromBridge(value.reference),
      value: mcpServerReadFromBridge(value.value),
    );

McpEntryPage mcpEntriesFromBridge(native.BridgeMcpEntryPage value) =>
    McpEntryPage(
      collection: collectionRefFromBridge(value.collection),
      offset: exactU64(value.offset, 'MCP entries offset'),
      items: value.items.map(entityRefFromBridge).toList(growable: false),
      nextOffset: nullableU64(value.nextOffset, 'MCP next entries offset'),
    );

McpServerReadPage mcpServersFromBridge(native.BridgeMcpServerReadPage value) =>
    McpServerReadPage(
      listId: exactU64(value.listId, 'MCP server list'),
      offset: exactU64(value.offset, 'MCP servers offset'),
      total: exactU64(value.total, 'MCP server total'),
      items: value.items.map(mcpServerReadFromBridge).toList(growable: false),
      nextOffset: nullableU64(value.nextOffset, 'MCP next servers offset'),
    );
