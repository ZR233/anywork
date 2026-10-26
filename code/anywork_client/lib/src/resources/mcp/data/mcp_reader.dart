import 'package:anywork_client/resources_ports.dart';

import '../domain/mcp_values.dart';
import 'mcp_port.dart';
import 'mcp_reads.dart';

final class McpReader {
  McpReader(this.connection)
    : _readText = ((field, offset) =>
          connection.text(field, offset: offset, maxBytes: 65536));
  final McpReadConnection connection;
  final Future<TextChunk> Function(int fieldId, int offset) _readText;

  Future<McpServer> server(McpServerRead value) async => McpServer(
    id: await materializeReadText(value.id, read: _readText),
    transport: await materializeReadText(value.transport, read: _readText),
    endpoint: await materializeReadText(value.endpoint, read: _readText),
    sourceKind: await materializeReadText(value.sourceKind, read: _readText),
    mutationPolicy: await materializeReadText(
      value.mutationPolicy,
      read: _readText,
    ),
    state: await state(value.state),
  );

  Future<McpServerState> state(McpServerStateRead value) async =>
      switch (value) {
        DisabledMcpServerStateRead(:final message) => McpServerState.disabled(
          message: await materializeReadText(message, read: _readText),
        ),
        MissingCredentialMcpServerStateRead(:final message) =>
          McpServerState.missingCredential(
            message: await materializeReadText(message, read: _readText),
          ),
        CheckingMcpServerStateRead(:final message) => McpServerState.checking(
          message: await materializeReadText(message, read: _readText),
        ),
        AvailableMcpServerStateRead(:final checkedAt, :final toolCount) =>
          McpServerState.available(checkedAt: checkedAt, toolCount: toolCount),
        UnavailableMcpServerStateRead(:final checkedAt, :final error) =>
          McpServerState.unavailable(
            checkedAt: checkedAt,
            error: SourceStateError(
              code: await materializeReadText(error.code, read: _readText),
              message: await materializeReadText(
                error.message,
                read: _readText,
              ),
              retryable: error.retryable,
            ),
          ),
      };

  Future<List<String>> activeIds(TypedListRef ref) async {
    if (ref.listId < 0 || ref.total < 0)
      throw resourceProtocol('Invalid MCP active-server list.');
    final values = <String>[];
    var offset = 0;
    while (offset < ref.total) {
      final page = await connection.activeServers(ref.listId, offset: offset);
      final items = List.of(page.items);
      final end = offset + items.length;
      if (page.listId != ref.listId ||
          page.offset != offset ||
          page.total != ref.total ||
          items.isEmpty ||
          items.length > 32 ||
          end > ref.total ||
          page.nextOffset != (end == ref.total ? null : end)) {
        throw resourceProtocol(
          'MCP active-server page changed its frozen list.',
        );
      }
      for (final item in items) {
        values.add(await materializeReadText(item.value, read: _readText));
      }
      offset = end;
    }
    return List.unmodifiable(values);
  }
}
