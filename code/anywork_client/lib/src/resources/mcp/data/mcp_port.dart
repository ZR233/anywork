import 'package:anywork_client/resources_ports.dart';

import '../domain/mcp_state.dart';
import 'mcp_frames.dart';
import 'mcp_reads.dart';

abstract interface class McpPort {
  Future<FeedConnection<McpFrame>> openMcp();
  Future<McpReadConnection> openMcpRead(
    McpReadRef reference, {
    required ProductReadOrigin origin,
  });
  Future<ProductSourceStatusReadConnection> openSourceStatus(
    ProductSourceStatusRef reference, {
    required ProductReadOrigin origin,
  });
  Future<McpReadTarget> resetServer(String serverId);
  Future<McpReadTarget> resetAll();
}

abstract interface class McpReadConnection {
  Future<McpReadHeader> header();
  Future<McpEntryPage> entries({int offset = 0, int limit = 32});
  Future<McpEntityRead> entity(ProductEntityRef reference);
  Future<ProductEntityRef?> lookupServer(String serverId);
  Future<McpServerReadPage> servers(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  Future<TextReadPage> activeServers(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536});
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}
