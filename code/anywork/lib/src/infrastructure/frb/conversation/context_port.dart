import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../shared/bridge_failure.dart';
import 'context_connection.dart';
import 'context_reads.dart';

Future<FeedConnection<ThreadContextFrame>> openFrbThreadContext(
  String threadId, {
  required ThreadObservationMode mode,
}) => bridgeQuery(() async {
  final connection = FrbThreadContextConnection.open(
    threadId: threadId,
    mode: mode,
  );
  await connection.opened;
  return connection;
});

Future<ContextReadConnection> openFrbThreadContextRead(
  String threadId,
  ContextReadRef reference, {
  required ThreadFacetStamp origin,
}) => bridgeQuery(() async {
  if (origin.facet != ThreadFacet.context || origin.runtimeEpoch.isEmpty) {
    throw const StudioFailure(
      code: StudioFailureCode.invalidArgument,
      message: 'A Thread Context read requires its original Context facet',
      retryable: false,
      correlationId: 'adapter-thread-context-read-origin',
    );
  }
  final connection = FrbThreadContextReadConnection(
    threadId: threadId,
    reference: reference,
    origin: origin,
  );
  await connection.opened;
  return connection;
});
