import 'package:anywork_client/persistence_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../../../../rust/api/studio/products/read/persistence.dart' as native;
import '../../../../rust/api/studio/products/read/persistence_queue.dart'
    as queue;
import '../../shared/bridge_failure.dart';
import '../../shared/exact_numbers.dart';
import '../resource_references.dart';
import 'command_results.dart';
import 'persistence_feed.dart';
import 'persistence_queue_feed.dart';
import 'persistence_read_connection.dart';
import 'queue_read_connection.dart';

/// The original writer is the only persistence path. Replies are not mirrors.
final class FrbPersistencePort implements PersistencePort {
  const FrbPersistencePort();

  @override
  Future<FeedConnection<PersistenceFrame>> openPersistence() async {
    final connection = FrbPersistenceConnection();
    await connection.opened;
    return connection;
  }

  @override
  Future<FeedConnection<PersistenceQueueFrame>> openPersistenceQueue() async {
    final connection = FrbPersistenceQueueConnection();
    await connection.opened;
    return connection;
  }

  @override
  Future<PersistenceReadConnection> openPersistenceRead(
    PersistenceReadRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final connection = FrbPersistenceReadConnection(reference, origin);
    await connection.opened;
    return connection;
  }

  @override
  Future<PersistenceQueueReadConnection> openPersistenceQueueRead(
    PersistenceQueueReadRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final connection = FrbPersistenceQueueReadConnection(reference, origin);
    await connection.opened;
    return connection;
  }

  @override
  Future<PersistenceReadTarget> retry() => bridgeQuery(
    () async => persistenceTargetFromBridge(await native.retryPersistence()),
  );

  @override
  Future<PersistenceQueueSnapshot> retryThreadHistory(
    String threadId,
    int faultGeneration,
  ) => bridgeQuery(
    () async => persistenceQueueCommandFromBridge(
      await queue.retryThreadHistory(
        threadId: threadId,
        faultGeneration: nativeU64(faultGeneration, 'history fault generation'),
      ),
    ),
  );

  @override
  Future<PersistenceQueueSnapshot> resumeThreadHistory(
    String threadId,
    int faultGeneration,
  ) => bridgeQuery(
    () async => persistenceQueueCommandFromBridge(
      await queue.resumeThreadHistory(
        threadId: threadId,
        faultGeneration: nativeU64(faultGeneration, 'history fault generation'),
      ),
    ),
  );
}
