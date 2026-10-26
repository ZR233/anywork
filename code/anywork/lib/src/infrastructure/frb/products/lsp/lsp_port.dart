import 'package:anywork_client/lsp_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../../../../rust/api/studio/products/read/lsp.dart' as native;
import '../../shared/bridge_failure.dart';
import '../resource_references.dart';
import 'lsp_feed.dart';
import 'lsp_read_connection.dart';
import 'source_status_connection.dart';

/// No probing or repair is performed by construction or observation.
final class FrbLspPort implements LspPort {
  const FrbLspPort();

  @override
  Future<FeedConnection<LspFrame>> openLsp() async {
    final connection = FrbLspConnection();
    await connection.opened;
    return connection;
  }

  @override
  Future<LspReadConnection> openLspRead(
    LspReadRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final connection = FrbLspReadConnection(reference, origin);
    await connection.opened;
    return connection;
  }

  @override
  Future<ProductSourceStatusReadConnection> openSourceStatus(
    ProductSourceStatusRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final connection = FrbLspSourceStatusConnection(reference, origin);
    await connection.opened;
    return connection;
  }

  @override
  Future<LspReadTarget> probe(String projectId) => bridgeQuery(
    () async =>
        lspTargetFromBridge(await native.lspProbe(projectId: projectId)),
  );

  @override
  Future<LspReadTarget> repair(String projectId, String serverId) =>
      bridgeQuery(
        () async => lspTargetFromBridge(
          await native.lspRepair(projectId: projectId, serverId: serverId),
        ),
      );

  @override
  Future<LspReadTarget> resetServer(String projectId, String serverId) =>
      bridgeQuery(
        () async => lspTargetFromBridge(
          await native.lspResetServer(projectId: projectId, serverId: serverId),
        ),
      );

  @override
  Future<LspReadTarget> resetWorkspace(String projectId) => bridgeQuery(
    () async => lspTargetFromBridge(
      await native.lspResetWorkspace(projectId: projectId),
    ),
  );
}
