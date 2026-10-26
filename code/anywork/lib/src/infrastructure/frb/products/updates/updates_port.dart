import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/updates_ports.dart';

import '../../../../rust/api/studio/products/read/updates.dart' as native;
import '../../shared/exact_numbers.dart';
import 'field_read_connections.dart';
import 'update_task_connection.dart';
import 'updates_connection.dart';
import 'updates_read_connection.dart';

UpdatesPort createUpdatesPort() => const FrbUpdatesPort();

/// Constructing this port never initializes Rust, opens a feed or starts work.
/// Application controls and explicit Repository/lifecycle demand own the gate.
final class FrbUpdatesPort implements UpdatesPort {
  const FrbUpdatesPort();

  @override
  Future<FeedConnection<UpdatesFrame>> openUpdates() async {
    final connection = FrbUpdatesConnection();
    await connection.opened;
    return connection;
  }

  @override
  Future<UpdatesReadConnection> openUpdatesRead(
    UpdatesReadRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final connection = FrbUpdatesReadConnection(reference, origin);
    await connection.opened;
    return connection;
  }

  @override
  Future<UpdateSummaryReadConnection> openSummary(
    UpdateSummaryReadRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final connection = FrbUpdateSummaryReadConnection(reference, origin);
    await connection.opened;
    return connection;
  }

  @override
  Future<UpdateOperationReadConnection> openOperation(
    UpdateOperationReadRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final connection = FrbUpdateOperationReadConnection(reference, origin);
    await connection.opened;
    return connection;
  }

  @override
  Future<UpdateErrorReadConnection> openError(
    UpdateErrorReadRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final connection = FrbUpdateErrorReadConnection(reference, origin);
    await connection.opened;
    return connection;
  }

  @override
  Future<UpdateDetailsReadConnection> openDetails(
    UpdateDetailsReadRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final connection = FrbUpdateDetailsReadConnection(reference, origin);
    await connection.opened;
    return connection;
  }

  @override
  Future<UpdateTaskConnection> openUpdateCheck(OperationId operationId) async {
    final connection = FrbUpdateTaskConnection(
      operationId,
      () => native.openUpdateCheck(operationId: operationId.value),
    );
    await connection.opened;
    return connection;
  }

  @override
  Future<UpdateTaskConnection> openAutomaticUpdate(
    OperationId operationId,
  ) async {
    final connection = FrbUpdateTaskConnection(
      operationId,
      () => native.openAutomaticUpdate(operationId: operationId.value),
    );
    await connection.opened;
    return connection;
  }

  @override
  Future<UpdateTaskConnection> openUpdatePreparation(
    OperationId operationId, {
    required int expectedRevision,
    required String version,
  }) async {
    final BigInt revision;
    try {
      revision = nativeU64(
        expectedRevision,
        'expected update business revision',
      );
    } on Object catch (error, stack) {
      Error.throwWithStackTrace(
        CommandDispatchFailure.rejected(failure: updateTaskFailure(error)),
        stack,
      );
    }
    final connection = FrbUpdateTaskConnection(
      operationId,
      () => native.openUpdatePreparation(
        operationId: operationId.value,
        expectedRevision: revision,
        version: version,
      ),
    );
    await connection.opened;
    return connection;
  }
}
