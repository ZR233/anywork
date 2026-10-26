import 'package:anywork_client/recovery_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../../../../rust/api/studio/products/read/recovery.dart' as native;
import '../../shared/bridge_failure.dart';
import '../../shared/exact_numbers.dart';
import '../resource_references.dart';
import 'read_values.dart';
import 'recovery_feed.dart';
import 'recovery_read_connection.dart';
import 'source_status_connection.dart';

final class FrbRecoveryPort implements RecoveryPort {
  const FrbRecoveryPort();

  @override
  Future<FeedConnection<RecoveryFrame>> openRecovery() async {
    final connection = FrbRecoveryConnection();
    await connection.opened;
    return connection;
  }

  @override
  Future<RecoveryReadConnection> openRecoveryRead(
    RecoveryReadRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final connection = FrbRecoveryReadConnection(reference, origin);
    await connection.opened;
    return connection;
  }

  @override
  Future<ProductSourceStatusReadConnection> openSourceStatus(
    ProductSourceStatusRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final connection = FrbRecoverySourceStatusConnection(reference, origin);
    await connection.opened;
    return connection;
  }

  @override
  Future<RecoveryReadTarget> retry() => bridgeQuery(
    () async => recoveryTargetFromBridge(await native.retryRecovery()),
  );

  @override
  Future<void> cleanupWorktree(
    WorktreeOwner ownerKind,
    String ownerThreadId,
    int expectedLeaseRevision,
  ) => bridgeQuery(
    () => native.cleanupWorktree(
      ownerKind: worktreeOwnerToBridge(ownerKind),
      ownerThreadId: ownerThreadId,
      expectedLeaseRevision: nativeU64(
        expectedLeaseRevision,
        'worktree lease revision',
      ),
    ),
  );
}
