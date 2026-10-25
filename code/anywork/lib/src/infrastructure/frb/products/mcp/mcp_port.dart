import 'package:anywork_client/mcp_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../../../../rust/api/studio/products/read/mcp.dart' as native;
import '../../shared/bridge_failure.dart';
import '../resource_references.dart';
import 'mcp_feed.dart';
import 'mcp_read_connection.dart';
import 'source_status_connection.dart';

/// Transport leaf only; the Repository owns demand, state and read budgets.
final class FrbMcpPort implements McpPort {
  const FrbMcpPort();

  @override
  Future<FeedConnection<McpFrame>> openMcp() async {
    final connection = FrbMcpConnection();
    await connection.opened;
    return connection;
  }

  @override
  Future<McpReadConnection> openMcpRead(
    McpReadRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final connection = FrbMcpReadConnection(reference, origin);
    await connection.opened;
    return connection;
  }

  @override
  Future<ProductSourceStatusReadConnection> openSourceStatus(
    ProductSourceStatusRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final connection = FrbMcpSourceStatusConnection(reference, origin);
    await connection.opened;
    return connection;
  }

  @override
  Future<McpReadTarget> resetServer(String serverId) => bridgeQuery(
    () async =>
        mcpTargetFromBridge(await native.mcpResetServer(serverId: serverId)),
  );

  @override
  Future<McpReadTarget> resetAll() =>
      bridgeQuery(() async => mcpTargetFromBridge(await native.mcpResetAll()));
}
