import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../shared/bridge_failure.dart';
import 'authoring_connection.dart';
import 'authoring_reads.dart';

/// Concrete Authoring factories, not an incomplete ObservationPort with dummy
/// Context/ThreadConfiguration methods. The root composes the real leaves.
Future<FeedConnection<ThreadAuthoringFrame>> openFrbThreadAuthoring(
  String threadId, {
  required ThreadObservationMode mode,
}) => bridgeQuery(() async {
  final connection = FrbThreadAuthoringConnection.open(
    threadId: threadId,
    mode: mode,
  );
  await connection.opened;
  return connection;
});

Future<TodoReadConnection> openFrbTodoRead(
  String threadId,
  TodoReadRef reference, {
  required ThreadFacetStamp origin,
}) => bridgeQuery(() async {
  _requireAuthoringOrigin(origin);
  final connection = FrbTodoReadConnection(
    threadId: threadId,
    reference: reference,
    origin: origin,
  );
  await connection.opened;
  return connection;
});

Future<WorkflowReadConnection> openFrbWorkflowRead(
  String threadId,
  WorkflowReadRef reference, {
  required ThreadFacetStamp origin,
}) => bridgeQuery(() async {
  _requireAuthoringOrigin(origin);
  final connection = FrbWorkflowReadConnection(
    threadId: threadId,
    reference: reference,
    origin: origin,
  );
  await connection.opened;
  return connection;
});

Future<PlanDocumentReadConnection> openFrbPlanDocumentRead(
  String threadId,
  PlanDocumentRef reference, {
  required ThreadFacetStamp origin,
}) => bridgeQuery(() async {
  _requireAuthoringOrigin(origin);
  final connection = FrbPlanDocumentReadConnection(
    threadId: threadId,
    reference: reference,
    origin: origin,
  );
  await connection.opened;
  return connection;
});

void _requireAuthoringOrigin(ThreadFacetStamp origin) {
  if (origin.facet != ThreadFacet.authoring || origin.runtimeEpoch.isEmpty) {
    throw const StudioFailure(
      code: StudioFailureCode.invalidArgument,
      message: 'An Authoring read requires its original Authoring facet',
      retryable: false,
      correlationId: 'adapter-authoring-read-origin',
    );
  }
}
