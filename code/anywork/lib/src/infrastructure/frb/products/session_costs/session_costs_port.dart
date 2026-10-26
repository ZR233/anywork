import 'package:anywork_client/account_usage_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import 'session_costs_feed.dart';
import 'session_costs_read_connection.dart';

SessionCostsPort createSessionCostsPort() => const FrbSessionCostsPort();

/// The two root-session cost capabilities only. Model performance statistics
/// are a separate domain with their own feeds, reads and port.
final class FrbSessionCostsPort implements SessionCostsPort {
  const FrbSessionCostsPort();

  @override
  Future<FeedConnection<SessionCostsFrame>> openSessionCosts(
    String rootThreadId,
  ) async {
    final connection = FrbSessionCostsConnection(rootThreadId);
    await connection.opened;
    return connection;
  }

  @override
  Future<SessionCostsReadConnection> openSessionCostsRead(
    SessionCostsReadRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final connection = FrbSessionCostsReadConnection(reference, origin);
    await connection.opened;
    return connection;
  }
}
