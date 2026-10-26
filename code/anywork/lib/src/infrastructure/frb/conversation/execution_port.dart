import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../../../rust/api/studio/conversation/read/connections.dart' as native;
import '../shared/adapter_failure.dart';
import '../shared/bridge_failure.dart';
import '../shared/exact_numbers.dart';
import 'activity_read_connection.dart';
import 'execution_connection.dart';
import 'execution_reads.dart';
import 'identity_converters.dart';
import 'interaction_read_connection.dart';

/// Real Execution leaves matching ConversationObservationPort's named factory
/// signatures. The composition root supplies the remaining facets separately;
/// this is not a partial implementation with dummy Context/Authoring methods.
Future<FeedConnection<ThreadExecutionFrame>> openFrbThreadExecution(
  String threadId, {
  required ThreadObservationMode mode,
}) => bridgeQuery(() async {
  final connection = FrbThreadExecutionConnection.open(
    threadId: threadId,
    mode: mode,
  );
  await connection.opened;
  return connection;
});

Future<TurnReadConnection> openFrbTurnRead(
  String threadId,
  TurnReadRef reference, {
  required ThreadFacetStamp origin,
}) => bridgeQuery(() async {
  _requireExecutionOrigin(origin);
  final connection = FrbTurnReadConnection(
    threadId: threadId,
    reference: reference,
    origin: origin,
  );
  await connection.opened;
  return connection;
});

Future<InteractionIndexReadConnection> openFrbInteractionIndexRead(
  String threadId,
  InteractionIndexRef reference, {
  required ThreadFacetStamp origin,
}) => bridgeQuery(() async {
  _requireExecutionOrigin(origin);
  final connection = FrbInteractionIndexReadConnection(
    threadId: threadId,
    reference: reference,
    origin: origin,
  );
  await connection.opened;
  return connection;
});

Future<InteractionReadRef> resolveFrbInteractionReadRef(
  String threadId,
  String interactionId, {
  required int revision,
  required ThreadFacetStamp origin,
}) => bridgeQuery(() async {
  _requireExecutionOrigin(origin);
  final reference = interactionRefFromBridge(
    await native.resolveInteractionReadRef(
      threadId: threadId,
      interactionId: interactionId,
      revision: nativeU64(revision, 'resolved interaction revision'),
      // Preserve the exact caller's exposure origin, including its revision.
      // Resident and durable resolution are both native decisions, not latest.
      origin: facetStampToBridge(origin),
    ),
  );
  if (reference.revision != revision) {
    throw adapterProtocol('resolved-interaction-revision');
  }
  return reference;
});

Future<InteractionReadConnection> openFrbInteractionRead(
  String threadId,
  InteractionReadRef reference, {
  required ThreadFacetStamp origin,
}) => bridgeQuery(() async {
  _requireExecutionOrigin(origin);
  final connection = FrbInteractionReadConnection(
    threadId: threadId,
    reference: reference,
    origin: origin,
  );
  await connection.opened;
  return connection;
});

Future<ActivityReadConnection> openFrbActivityRead(
  String threadId,
  ActivityReadRef reference, {
  required ThreadFacetStamp origin,
}) => bridgeQuery(() async {
  _requireExecutionOrigin(origin);
  final connection = FrbActivityReadConnection(
    threadId: threadId,
    reference: reference,
    origin: origin,
  );
  await connection.opened;
  return connection;
});

Future<StorageReadConnection> openFrbStorageRead(
  String threadId,
  StorageReadRef reference, {
  required ThreadFacetStamp origin,
}) => bridgeQuery(() async {
  _requireExecutionOrigin(origin);
  final connection = FrbStorageReadConnection(
    threadId: threadId,
    reference: reference,
    origin: origin,
  );
  await connection.opened;
  return connection;
});

void _requireExecutionOrigin(ThreadFacetStamp origin) {
  if (origin.facet != ThreadFacet.execution || origin.runtimeEpoch.isEmpty) {
    throw const StudioFailure(
      code: StudioFailureCode.invalidArgument,
      message: 'An Execution read requires its original Execution facet',
      retryable: false,
      correlationId: 'adapter-execution-read-origin',
    );
  }
}
