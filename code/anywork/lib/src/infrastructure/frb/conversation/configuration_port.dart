import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../shared/bridge_failure.dart';
import 'configuration_connection.dart';
import 'configuration_reads.dart';

Future<FeedConnection<ThreadConfigurationFrame>> openFrbThreadConfiguration(
  String threadId, {
  required ThreadObservationMode mode,
}) => bridgeQuery(() async {
  final connection = FrbThreadConfigurationConnection.open(
    threadId: threadId,
    mode: mode,
  );
  await connection.opened;
  return connection;
});

Future<ThreadConfigurationReadConnection> openFrbThreadConfigurationRead(
  String threadId,
  ThreadConfigurationReadRef reference, {
  required ThreadFacetStamp origin,
}) => bridgeQuery(() async {
  if (origin.facet != ThreadFacet.configuration ||
      origin.runtimeEpoch.isEmpty) {
    throw const StudioFailure(
      code: StudioFailureCode.invalidArgument,
      message: 'A Thread Configuration read requires its original Configuration facet',
      retryable: false,
      correlationId: 'adapter-thread-configuration-read-origin',
    );
  }
  final connection = FrbThreadConfigurationReadConnection(
    threadId: threadId,
    reference: reference,
    origin: origin,
  );
  await connection.opened;
  return connection;
});
